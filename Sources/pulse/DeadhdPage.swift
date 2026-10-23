import Darwin
import Foundation
import PulseCore

/// deadhd 진행 페이지를 여는 주소. `open.sh` 와 같은 규칙으로 로컬 서버를 먼저 확인한다.
enum DeadhdPage {
    static func url(
        for path: String,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL? {
        guard resolvesUnderTemporaryDirectory(path, rule: DeadhdState.pagePath),
              isOwnedRegularFile(path)
        else { return nil }
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
        guard resolvesUnderTemporaryDirectory(path, rule: DeadhdState.pagePath) else { return false }
        if fileManager.fileExists(atPath: path) { return isOwnedRegularFile(path) }
        guard let dataPath,
              resolvesUnderTemporaryDirectory(dataPath, rule: DeadhdState.dataPath),
              isOwnedRegularFile(dataPath),
              let script = skillURL("render.py", environment: environment)
        else { return false }
        // render.py 는 이 변수로 세션 상태 파일을 고르므로, 남아 있으면 다른 세션의 상태를 덮어쓴다.
        _ = run(
            [script.path, "--page", dataPath, path],
            environment: environment.filter { $0.key != "CLAUDE_CODE_SESSION_ID" }
        )
        return isOwnedRegularFile(path)
    }

    /// `attributesOfItem` 은 lstat 의미라 심볼릭 링크를 따라가지 않는다.
    private static func isOwnedRegularFile(_ path: String) -> Bool {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
              attributes[.type] as? FileAttributeType == .typeRegular,
              let owner = attributes[.ownerAccountID] as? NSNumber
        else { return false }
        return owner.uint32Value == getuid()
    }

    /// 가장 가까운 실제 조상까지 `realpath` 로 풀어, 하위 경로가 링크를 거쳐 /tmp 밖으로 나가는지 본다.
    /// 대상 없는 링크도 존재로 보고 멈춘다.
    private static func resolvesUnderTemporaryDirectory(
        _ path: String,
        rule: (String?) -> String?
    ) -> Bool {
        var existing = path
        var remainder: [String] = []
        while (try? FileManager.default.attributesOfItem(atPath: existing)) == nil {
            let parent = (existing as NSString).deletingLastPathComponent
            guard parent != existing else { return false }
            remainder.insert((existing as NSString).lastPathComponent, at: 0)
            existing = parent
        }
        guard let resolved = realpath(existing, nil) else { return false }
        defer { free(resolved) }
        let rebuilt = remainder.reduce(String(cString: resolved)) { $0 + "/" + $1 }
        return rule(rebuilt) != nil
    }

    private static func scriptURL(environment: [String: String]) -> URL? {
        skillURL("serve.py", environment: environment)
    }

    private static func skillURL(_ name: String, environment: [String: String]) -> URL? {
        let configured = environment["CLAUDE_CONFIG_DIR"] ?? "~/.claude"
        let configDirectory = NSString(string: configured).expandingTildeInPath
        let installedPlugins = try? Data(
            contentsOf: URL(fileURLWithPath: configDirectory)
                .appendingPathComponent("plugins/installed_plugins.json")
        )
        for directory in DeadhdSkillLocation.directories(
            configDirectory: configDirectory,
            installedPlugins: installedPlugins
        ) {
            let url = URL(fileURLWithPath: directory).appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }
        return nil
    }

    // `/usr/bin/python3`(3.9.6)에서도 render.py·serve.py 가 3.14 와 같은 결과를 냈고 deadhd 테스트 451건이 통과했다.
    private static let pythonCandidates = ["/usr/bin/python3", "/opt/homebrew/bin/python3", "/usr/local/bin/python3"]

    private static func run(_ arguments: [String], environment: [String: String]? = nil) -> String? {
        guard let executable = ExecutablePath.firstExecutable(
            in: pythonCandidates,
            isExecutable: { FileManager.default.isExecutableFile(atPath: $0) }
        ) else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
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
