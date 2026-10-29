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

    public static func host(inProcArgs data: Data) -> MultiplexerHost? {
        if let handle = ProcessEnvironment.value(ProcessEnvironment.orcaTerminalHandleKey, inProcArgs: data) {
            return .orca(handle)
        }
        if let bundleIdentifier = ProcessEnvironment.value("__CFBundleIdentifier", inProcArgs: data) {
            return .app(bundleIdentifier)
        }
        return nil
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
