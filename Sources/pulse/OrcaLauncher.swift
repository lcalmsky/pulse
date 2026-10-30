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

    /// 페이지 알림의 Orca 탭으로 이동한다. Orca 에서 열지 못하면 파일 주소를 기본 앱으로 연다.
    /// 완료 콜백은 메인 스레드에서 호출된다.
    static func openPage(_ alert: PageAlert, completion: @escaping (Bool) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            if openPageInOrca(alert) {
                DispatchQueue.main.async {
                    bringForward()
                    completion(true)
                }
                return
            }
            DispatchQueue.main.async {
                let opened = openPageOutsideOrca(alert)
                if !opened {
                    logger.error("페이지를 열지 못했다: \(alert.url, privacy: .public)")
                }
                completion(opened)
            }
        }
    }

    private static func openPageInOrca(_ alert: PageAlert) -> Bool {
        var switched = false
        if let handle = alert.terminalHandle, !handle.isEmpty {
            switched = run(arguments: ["terminal", "switch", "--terminal", handle, "--json"])
        }
        if !switched, let handle = matchingTerminal(worktree: alert.worktree) {
            _ = run(arguments: ["terminal", "switch", "--terminal", handle, "--json"])
        }
        Thread.sleep(forTimeInterval: 0.3)

        let worktree = "id:" + alert.worktree
        if run(arguments: ["tab", "switch", "--page", alert.pageId, "--worktree", worktree, "--focus", "--json"]) {
            return true
        }
        guard let created = runReadingOutput(
            arguments: ["tab", "create", "--url", alert.url, "--worktree", worktree, "--json"],
            capturingError: true
        ) else {
            logger.error("orca tab create 를 실행하지 못했다: \(alert.url, privacy: .public)")
            return false
        }
        guard created.status == 0 else {
            let stderr = String(decoding: created.error, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            logger.error(
                "orca tab create 종료 코드 \(created.status), stderr: \(stderr, privacy: .public), url: \(alert.url, privacy: .public)"
            )
            return false
        }
        if let pageId = browserPageId(in: created.output) {
            _ = run(arguments: ["tab", "switch", "--page", pageId, "--worktree", worktree, "--focus", "--json"])
        }
        return true
    }

    private static func matchingTerminal(worktree: String) -> String? {
        guard let output = runReadingOutput(
            arguments: ["terminal", "list", "--worktree", "id:" + worktree, "--json"]
        ), output.status == 0,
              let list = try? JSONDecoder().decode(OrcaTerminalList.self, from: output.output)
        else { return nil }
        return list.terminals.first { $0.connected }?.handle
    }

    private static func openPageOutsideOrca(_ alert: PageAlert) -> Bool {
        guard let url = SafeLink.pageFileURL(alert.url, isRegularFile: isRegularFile) else {
            logger.error("기본 앱으로 열 수 있는 html 파일이 아니다: \(alert.url, privacy: .public)")
            return false
        }
        let opened = NSWorkspace.shared.open(url)
        if !opened {
            logger.error("기본 앱으로 페이지를 열지 못했다: \(url.absoluteString, privacy: .public)")
        }
        return opened
    }

    private static func isRegularFile(_ path: String) -> Bool {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
        return exists && !isDirectory.boolValue
    }

    private static func browserPageId(in data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) else { return nil }
        return stringValue(forKey: "browserPageId", in: object)
    }

    private static func stringValue(forKey key: String, in object: Any) -> String? {
        if let dictionary = object as? [String: Any] {
            if let value = dictionary[key] as? String, !value.isEmpty {
                return value
            }
            for value in dictionary.values {
                if let found = stringValue(forKey: key, in: value) { return found }
            }
        } else if let array = object as? [Any] {
            for value in array {
                if let found = stringValue(forKey: key, in: value) { return found }
            }
        }
        return nil
    }

    private static func runReadingOutput(
        arguments: [String],
        capturingError: Bool = false
    ) -> (status: Int32, output: Data, error: Data)? {
        guard let process = command(arguments: arguments) else { return nil }
        let pipe = Pipe()
        process.standardOutput = pipe
        let errorPipe = capturingError ? Pipe() : nil
        if let errorPipe { process.standardError = errorPipe }
        do {
            try process.run()
        } catch {
            logger.error(
                "orca \(arguments.joined(separator: " "), privacy: .public) 실행 실패: \(error.localizedDescription, privacy: .public)"
            )
            return nil
        }
        // waitUntilExit 전에 읽어야 출력이 파이프 버퍼를 넘어도 멈추지 않는다.
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = errorPipe?.fileHandleForReading.readDataToEndOfFile() ?? Data()
        process.waitUntilExit()
        return (process.terminationStatus, data, errorData)
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
