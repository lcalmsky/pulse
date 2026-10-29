import Foundation

public enum MultiplexerKind: String, Equatable {
    case herdr
    case tmux
}

/// 세션이 들어 있는 터미널 멀티플렉서의 패널. 값은 모두 세션 프로세스 환경에서 읽는다.
public struct MultiplexerPane: Equatable {
    public let kind: MultiplexerKind
    public let paneId: String
    public let socketPath: String?
    public let workspaceId: String?
    public let tabId: String?

    public init(
        kind: MultiplexerKind,
        paneId: String,
        socketPath: String? = nil,
        workspaceId: String? = nil,
        tabId: String? = nil
    ) {
        self.kind = kind
        self.paneId = paneId
        self.socketPath = socketPath
        self.workspaceId = workspaceId
        self.tabId = tabId
    }

    enum CodingKeys: String, CodingKey {
        case kind
        case paneId
        case socketPath
        case workspaceId
        case tabId
    }
}

extension MultiplexerPane: Decodable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawKind = try container.decode(String.self, forKey: .kind)
        guard let kind = MultiplexerKind(rawValue: rawKind) else {
            throw DecodingError.dataCorruptedError(
                forKey: .kind, in: container, debugDescription: "알 수 없는 멀티플렉서"
            )
        }
        let paneId = try container.decode(String.self, forKey: .paneId)
        guard !paneId.isEmpty else {
            throw DecodingError.dataCorruptedError(
                forKey: .paneId, in: container, debugDescription: "패널 id 가 비었다"
            )
        }
        self.init(
            kind: kind,
            paneId: paneId,
            socketPath: try container.decodeIfPresent(String.self, forKey: .socketPath),
            workspaceId: try container.decodeIfPresent(String.self, forKey: .workspaceId),
            tabId: try container.decodeIfPresent(String.self, forKey: .tabId)
        )
    }
}

/// herdr 클라이언트가 떠 있는 터미널 앱. 패널을 옮긴 뒤 창을 앞으로 꺼낼 때 쓴다.
public enum MultiplexerHost: Equatable {
    case orca(String)
    case app(String)
}

/// herdr 세션 하나. `herdr session list --json` 의 항목이다.
public struct HerdrSession: Equatable {
    public let name: String
    public let isDefault: Bool
    public let socketPath: String

    public init(name: String, isDefault: Bool, socketPath: String) {
        self.name = name
        self.isDefault = isDefault
        self.socketPath = socketPath
    }
}

public enum Multiplexer {
    public static func pane(inProcArgs data: Data) -> MultiplexerPane? {
        let herdrPane = ProcessEnvironment.value(ProcessEnvironment.herdrPaneIdKey, inProcArgs: data)
        let tmuxPane = ProcessEnvironment.value(ProcessEnvironment.tmuxPaneKey, inProcArgs: data)
        // herdr 패널 안에서 tmux 를 다시 띄우는 쪽이 흔해, 둘 다 보이면 안쪽인 tmux 를 고른다.
        if let tmuxPane {
            return MultiplexerPane(
                kind: .tmux,
                paneId: tmuxPane,
                socketPath: socketPath(fromTMUX: ProcessEnvironment.value(ProcessEnvironment.tmuxKey, inProcArgs: data))
            )
        }
        if let herdrPane {
            return MultiplexerPane(
                kind: .herdr,
                paneId: herdrPane,
                socketPath: ProcessEnvironment.value(ProcessEnvironment.herdrSocketPathKey, inProcArgs: data),
                workspaceId: ProcessEnvironment.value(ProcessEnvironment.herdrWorkspaceIdKey, inProcArgs: data),
                tabId: ProcessEnvironment.value(ProcessEnvironment.herdrTabIdKey, inProcArgs: data)
            )
        }
        return nil
    }

    /// `TMUX` 값은 `<소켓 경로>,<서버 pid>,<세션 번호>` 다.
    public static func socketPath(fromTMUX value: String?) -> String? {
        guard let value else { return nil }
        let socket = value.split(separator: ",", maxSplits: 1, omittingEmptySubsequences: false)
            .first.map(String.init)
        guard let socket, !socket.isEmpty else { return nil }
        return socket
    }

    /// 짧게 끝나는 `herdr pane ...` 같은 CLI 호출이 아니라 TUI 클라이언트만 고른다.
    public static func isHerdrClient(arguments: [String]) -> Bool {
        guard let executable = arguments.first,
              (executable as NSString).lastPathComponent == "herdr" else {
            return false
        }
        let rest = Array(arguments.dropFirst())
        if rest.isEmpty { return true }
        if rest.first == "--session" { return true }
        return rest.count >= 2 && rest[0] == "session" && rest[1] == "attach"
    }

    /// TUI 클라이언트 argv 가 붙는 세션 이름. 이름 없이 `herdr` 만 띄우면 nil(기본 세션)이다.
    public static func herdrSessionName(arguments: [String]) -> String? {
        guard isHerdrClient(arguments: arguments) else { return nil }
        let rest = Array(arguments.dropFirst())
        if rest.first == "--session" {
            return rest.count >= 2 ? rest[1] : nil
        }
        if rest.count >= 3, rest[0] == "session", rest[1] == "attach" {
            return rest[2]
        }
        return nil
    }

    /// `herdr session list --json` 출력을 읽는다. 형식이 다르면 nil.
    public static func herdrSessions(fromListJSON text: String) -> [HerdrSession]? {
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any],
              let items = dictionary["sessions"] as? [[String: Any]] else {
            return nil
        }
        return items.compactMap { item in
            guard let name = item["name"] as? String,
                  let socketPath = item["socket_path"] as? String else {
                return nil
            }
            let isDefault = item["default"] as? Bool ?? false
            return HerdrSession(name: name, isDefault: isDefault, socketPath: socketPath)
        }
    }

    /// 패널 소켓 경로에 해당하는 세션. 경로는 `~` 를 펼치고 standardizingPath 로 맞춰 비교한다.
    public static func herdrSession(forSocket socketPath: String, in sessions: [HerdrSession]) -> HerdrSession? {
        let target = standardizedPath(socketPath)
        return sessions.first { standardizedPath($0.socketPath) == target }
    }

    /// 클라이언트 argv 가 그 세션에 붙는지. 이름이 없으면 기본 세션에 붙는다.
    public static func herdrClient(arguments: [String], attachesTo session: HerdrSession) -> Bool {
        guard isHerdrClient(arguments: arguments) else { return false }
        guard let name = herdrSessionName(arguments: arguments) else { return session.isDefault }
        return name == session.name
    }

    private static func standardizedPath(_ path: String) -> String {
        (NSString(string: path).expandingTildeInPath as NSString).standardizingPath
    }

    /// 포커스 요청 줄을 workspace → tab → pane 순서로 만든다. id 가 없는 단계는 건너뛴다.
    public static func focusRequestLines(workspaceId: String?, tabId: String?, paneId: String?) -> [String] {
        var lines: [String] = []
        appendFocusRequest(
            method: "workspace.focus", key: "workspace_id", value: workspaceId, to: &lines
        )
        appendFocusRequest(method: "tab.focus", key: "tab_id", value: tabId, to: &lines)
        appendFocusRequest(method: "pane.focus", key: "pane_id", value: paneId, to: &lines)
        return lines
    }

    public static func focusRequestLines(for pane: MultiplexerPane) -> [String] {
        focusRequestLines(workspaceId: pane.workspaceId, tabId: pane.tabId, paneId: pane.paneId)
    }

    /// 응답 한 줄이 성공이면 `result` 키가 있다. 오류는 `error` 키로 온다.
    public static func isSuccessResponse(_ line: String) -> Bool {
        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any] else {
            return false
        }
        return dictionary["result"] != nil
    }

    public static let orcaBundleIdentifier = "com.stablyai.orca"

    public static func host(inProcArgs data: Data) -> MultiplexerHost? {
        let handle = ProcessEnvironment.value(ProcessEnvironment.orcaTerminalHandleKey, inProcArgs: data)
        let bundleIdentifier = ProcessEnvironment.value("__CFBundleIdentifier", inProcArgs: data)
        // Orca 셸에서 연 다른 터미널 앱도 ORCA_TERMINAL_HANDLE 을 물려받으므로, 앱이 Orca 일 때만 핸들을 믿는다.
        if let handle, bundleIdentifier == nil || bundleIdentifier == orcaBundleIdentifier {
            return .orca(handle)
        }
        return bundleIdentifier.map { .app($0) }
    }

    private static func appendFocusRequest(
        method: String,
        key: String,
        value: String?,
        to lines: inout [String]
    ) {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return
        }
        let object: [String: Any] = [
            "id": "pulse-\(method)",
            "method": method,
            "params": [key: value],
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
              let line = String(data: data, encoding: .utf8) else {
            return
        }
        lines.append(line)
    }
}
