import Foundation

/// deadhd 진행 페이지를 여는 주소. `open.sh` 와 같은 규칙으로 로컬 서버를 먼저 확인한다.
enum DeadhdPage {
    static func url(
        for path: String,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL {
        let fileURL = URL(fileURLWithPath: path)
        guard let script = scriptURL(environment: environment) else { return fileURL }
        guard run([script.path, "--ensure"]) != nil,
              let output = run([script.path, "--url", path])
        else { return fileURL }

        let address = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard address.hasPrefix("http://") || address.hasPrefix("https://"),
              let url = URL(string: address)
        else { return fileURL }
        return url
    }

    /// HTML 이 아직 없으면 render.py 로 한 번 만들어 둔다. 만들었거나 이미 있으면 true.
    /// `--view` 는 넘기지 않아 band·statusline 세션의 보기가 바뀌지 않는다.
    static func ensurePage(
        path: String,
        dataPath: String?,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: path) { return true }
        guard let dataPath, fileManager.fileExists(atPath: dataPath),
              let script = skillURL("render.py", environment: environment)
        else { return false }
        // render.py 는 이 변수로 세션 상태 파일을 고르므로, 남아 있으면 다른 세션의 상태를 덮어쓴다.
        _ = run(
            [script.path, "--page", dataPath, path],
            environment: environment.filter { $0.key != "CLAUDE_CODE_SESSION_ID" }
        )
        return fileManager.fileExists(atPath: path)
    }

    private static func scriptURL(environment: [String: String]) -> URL? {
        skillURL("serve.py", environment: environment)
    }

    private static func skillURL(_ name: String, environment: [String: String]) -> URL? {
        let configured = environment["CLAUDE_CONFIG_DIR"] ?? "~/.claude"
        let url = URL(fileURLWithPath: NSString(string: configured).expandingTildeInPath)
            .appendingPathComponent("skills/deadhd/\(name)")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    private static func run(_ arguments: [String], environment: [String: String]? = nil) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["python3"] + arguments
        if let environment {
            process.environment = environment
        }
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
