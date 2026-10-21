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

    private static func scriptURL(environment: [String: String]) -> URL? {
        let configured = environment["CLAUDE_CONFIG_DIR"] ?? "~/.claude"
        let url = URL(fileURLWithPath: NSString(string: configured).expandingTildeInPath)
            .appendingPathComponent("skills/deadhd/serve.py")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    private static func run(_ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["python3"] + arguments
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
