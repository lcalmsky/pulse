import Foundation

public struct OrcaTerminal: Equatable {
    public let handle: String
    public let worktreePath: String?
    public let title: String?
    public let connected: Bool
    public let lastOutputAt: Double?

    public init(
        handle: String,
        worktreePath: String? = nil,
        title: String? = nil,
        connected: Bool = true,
        lastOutputAt: Double? = nil
    ) {
        self.handle = handle
        self.worktreePath = worktreePath
        self.title = title
        self.connected = connected
        self.lastOutputAt = lastOutputAt
    }

    enum CodingKeys: String, CodingKey {
        case handle
        case worktreePath
        case title
        case connected
        case lastOutputAt
    }
}

extension OrcaTerminal: Decodable {
    public init(from decoder: Decoder) {
        let container = try? decoder.container(keyedBy: CodingKeys.self)
        handle = Lenient.string(container, .handle) ?? ""
        worktreePath = Lenient.string(container, .worktreePath)
        title = Lenient.string(container, .title)
        connected = (try? container?.decodeIfPresent(Bool.self, forKey: .connected)) ?? true
        lastOutputAt = Lenient.double(container, .lastOutputAt)
    }
}

public struct OrcaTerminalList: Equatable {
    public let terminals: [OrcaTerminal]

    public init(terminals: [OrcaTerminal] = []) {
        self.terminals = terminals
    }

    enum CodingKeys: String, CodingKey {
        case result
    }

    enum ResultKeys: String, CodingKey {
        case terminals
    }
}

extension OrcaTerminalList: Decodable {
    public init(from decoder: Decoder) {
        let container = try? decoder.container(keyedBy: CodingKeys.self)
        let result = container.flatMap {
            try? $0.nestedContainer(keyedBy: ResultKeys.self, forKey: .result)
        }
        terminals = Lenient.array(result, .terminals, as: OrcaTerminal.self)
            .filter { !$0.handle.isEmpty }
    }
}

public enum OrcaTerminalMatch {
    /// 핸들이 없는 세션의 cwd 로 터미널을 찾는다. 정확히 같은 경로와 그 하위 경로가 대상이고,
    /// 세션 이름과 제목이 같은 터미널이 여럿이면 그중 가장 최근에 출력이 있던 것을 쓴다.
    /// 맞는 이름이 없으면 후보가 하나뿐일 때만 그 터미널을 쓰고, 여럿이면 nil 이다.
    public static func bestHandle(
        for cwd: String,
        name: String? = nil,
        among terminals: [OrcaTerminal]
    ) -> String? {
        guard let target = normalize(cwd) else { return nil }
        let matched = terminals.filter { terminal in
            guard terminal.connected, !terminal.handle.isEmpty,
                  let path = terminal.worktreePath.flatMap(normalize) else {
                return false
            }
            return path == target || target.hasPrefix(path + "/")
        }
        if let wanted = trimmedName(name) {
            let named = matched.filter { terminal in
                guard let title = terminal.title, let candidate = sessionName(fromTitle: title) else {
                    return false
                }
                return candidate.caseInsensitiveCompare(wanted) == .orderedSame
            }
            if let handle = mostRecent(named) {
                return handle
            }
        }
        return matched.count == 1 ? matched[0].handle : nil
    }

    /// Orca 터미널 제목 앞의 상태 기호(✳ ◐ 등)와 공백을 떼고 세션 이름만 남긴다.
    public static func sessionName(fromTitle title: String) -> String? {
        var value = title
        while let first = value.first, !(first.isLetter || first.isNumber) {
            value.removeFirst()
        }
        return trimmedName(value)
    }

    public static func normalize(_ path: String) -> String? {
        var value = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        value = (value as NSString).expandingTildeInPath
        while value.count > 1, value.hasSuffix("/") {
            value.removeLast()
        }
        return value
    }

    private static func trimmedName(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private static func mostRecent(_ terminals: [OrcaTerminal]) -> String? {
        terminals.max { left, right in
            (left.lastOutputAt ?? -.greatestFiniteMagnitude) < (right.lastOutputAt ?? -.greatestFiniteMagnitude)
        }?.handle
    }
}
