import AppKit
import PulseCore
import Foundation
import os

enum OrcaLauncher {
    private static let appPath = "/Applications/Orca.app"
    private static let cliPath = "/Applications/Orca.app/Contents/Resources/bin/orca"
    private static let logger = Logger(subsystem: "io.github.lcalmsky.pulse", category: "orca")

    /// Orca 터미널로 이동한다. 완료 콜백은 메인 스레드에서 호출된다.
    static func switchTerminal(handle: String, completion: @escaping (Bool) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let succeeded = run(arguments: ["terminal", "switch", "--terminal", handle, "--json"])

            DispatchQueue.main.async {
                if succeeded { bringForward() }
                completion(succeeded)
            }
        }
    }

    /// 핸들 없이 cwd 만 아는 세션의 터미널을 목록에서 찾아 이동한다.
    /// 완료 콜백은 메인 스레드에서 호출된다.
    static func switchToCwd(_ cwd: String, name: String?, completion: @escaping (Bool) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            guard let handle = matchingHandle(for: cwd, name: name) else {
                DispatchQueue.main.async { completion(false) }
                return
            }
            switchTerminal(handle: handle, completion: completion)
        }
    }

    private static func matchingHandle(for cwd: String, name: String?) -> String? {
        guard let process = command(arguments: ["terminal", "list", "--json"]) else { return nil }
        let pipe = Pipe()
        process.standardOutput = pipe
        do {
            try process.run()
        } catch {
            logger.error("orca terminal list 실행 실패: \(error.localizedDescription, privacy: .public)")
            return nil
        }
        // waitUntilExit 전에 읽어야 출력이 파이프 버퍼를 넘어도 멈추지 않는다.
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            logger.error("orca terminal list 종료 코드 \(process.terminationStatus)")
            return nil
        }
        let list: OrcaTerminalList
        do {
            list = try JSONDecoder().decode(OrcaTerminalList.self, from: data)
        } catch {
            logger.error("orca terminal list 디코딩 실패: \(error.localizedDescription, privacy: .public)")
            return nil
        }
        guard let handle = OrcaTerminalMatch.bestHandle(for: cwd, name: name, among: list.terminals) else {
            logger.notice(
                "orca 에 맞는 터미널 없음: cwd \(cwd, privacy: .public), 이름 \(name ?? "-", privacy: .public), 터미널 \(list.terminals.count)개"
            )
            return nil
        }
        return handle
    }

    private static func run(arguments: [String]) -> Bool {
        guard let process = command(arguments: arguments) else { return false }
        process.standardOutput = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            logger.error(
                "orca \(arguments.joined(separator: " "), privacy: .public) 실행 실패: \(error.localizedDescription, privacy: .public)"
            )
            return false
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            logger.error(
                "orca \(arguments.joined(separator: " "), privacy: .public) 종료 코드 \(process.terminationStatus)"
            )
            return false
        }
        return true
    }

    // Orca CLI 는 앱 번들 안의 고정 경로만 쓴다. PATH 의 orca 로 대신하지 않는다.
    private static func command(arguments: [String]) -> Process? {
        guard FileManager.default.isExecutableFile(atPath: cliPath) else {
            logger.error("orca 실행 파일 없음: \(cliPath, privacy: .public)")
            return nil
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: cliPath)
        process.arguments = arguments
        process.standardError = FileHandle.nullDevice
        return process
    }

    private static func bringForward() {
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: Multiplexer.orcaBundleIdentifier).first {
            if #available(macOS 14.0, *) {
                app.activate()
            } else {
                _ = NSWorkspace.shared.open(URL(fileURLWithPath: appPath))
            }
        } else {
            _ = NSWorkspace.shared.open(URL(fileURLWithPath: appPath))
        }
    }
}
