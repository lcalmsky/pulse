import AppKit
import DeadhdBarCore
import Foundation

enum OrcaLauncher {
    private static let bundleIdentifier = "com.stablyai.orca"
    private static let appPath = "/Applications/Orca.app"
    private static let cliPath = "/Applications/Orca.app/Contents/Resources/bin/orca"

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
    static func switchToCwd(_ cwd: String, completion: @escaping (Bool) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            guard let handle = matchingHandle(for: cwd) else {
                DispatchQueue.main.async { completion(false) }
                return
            }
            switchTerminal(handle: handle, completion: completion)
        }
    }

    private static func matchingHandle(for cwd: String) -> String? {
        let process = command(arguments: ["terminal", "list", "--json"])
        let pipe = Pipe()
        process.standardOutput = pipe
        do {
            try process.run()
        } catch {
            return nil
        }
        // waitUntilExit 전에 읽어야 출력이 파이프 버퍼를 넘어도 멈추지 않는다.
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0,
              let list = try? JSONDecoder().decode(OrcaTerminalList.self, from: data) else {
            return nil
        }
        return OrcaTerminalMatch.bestHandle(for: cwd, among: list.terminals)
    }

    private static func run(arguments: [String]) -> Bool {
        let process = command(arguments: arguments)
        process.standardOutput = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    private static func command(arguments: [String]) -> Process {
        let process = Process()
        if FileManager.default.isExecutableFile(atPath: cliPath) {
            process.executableURL = URL(fileURLWithPath: cliPath)
            process.arguments = arguments
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["orca"] + arguments
        }
        process.standardError = FileHandle.nullDevice
        return process
    }

    private static func bringForward() {
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first {
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
