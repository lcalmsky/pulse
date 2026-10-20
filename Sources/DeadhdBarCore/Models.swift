import Foundation

/// ISO8601 문자열을 관대하게 읽는다. 초 단위·밀리초 단위·시간대 포함 표기를 모두 받는다.
public enum TimestampParser {
    private static let patterns = [
        "yyyy-MM-dd'T'HH:mm:ssXXXXX",
        "yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX",
        "yyyy-MM-dd'T'HH:mm:ss.SSSSSSXXXXX",
        "yyyy-MM-dd'T'HH:mm:ss",
        "yyyy-MM-dd'T'HH:mm:ss.SSS",
    ]

    public static func parse(_ raw: String?) -> Date? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        for pattern in patterns {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = pattern
            if let date = formatter.date(from: raw) {
                return date
            }
        }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: raw) {
            return date
        }
        iso.formatOptions = [.withInternetDateTime]
        return iso.date(from: raw)
    }
}

enum Lenient {
    static func string<K: CodingKey>(_ container: KeyedDecodingContainer<K>?, _ key: K) -> String? {
        guard let container, let value = try? container.decodeIfPresent(String.self, forKey: key) else {
            return nil
        }
        return value
    }

    static func double<K: CodingKey>(_ container: KeyedDecodingContainer<K>?, _ key: K) -> Double? {
        guard let container, let value = try? container.decodeIfPresent(Double.self, forKey: key) else {
            return nil
        }
        return value
    }

    static func date<K: CodingKey>(_ container: KeyedDecodingContainer<K>?, _ key: K) -> Date? {
        TimestampParser.parse(string(container, key))
    }

    static func object<K: CodingKey, T: Decodable>(
        _ container: KeyedDecodingContainer<K>?, _ key: K, as type: T.Type
    ) -> T? {
        guard let container, let value = try? container.decodeIfPresent(type, forKey: key) else {
            return nil
        }
        return value
    }

    static func array<K: CodingKey, T: Decodable>(
        _ container: KeyedDecodingContainer<K>?, _ key: K, as type: T.Type
    ) -> [T] {
        guard let container, let value = try? container.decodeIfPresent([T].self, forKey: key) else {
            return []
        }
        return value
    }
}

public struct SessionsResponse: Equatable {
    public let renderedAt: Date?
    public let staleAfterSeconds: Double?
    public let sessions: [Session]

    public init(renderedAt: Date? = nil, staleAfterSeconds: Double? = nil, sessions: [Session] = []) {
        self.renderedAt = renderedAt
        self.staleAfterSeconds = staleAfterSeconds
        self.sessions = sessions
    }

    enum CodingKeys: String, CodingKey {
        case renderedAt
        case staleAfterSeconds
        case sessions
    }
}

extension SessionsResponse: Decodable {
    public init(from decoder: Decoder) {
        let container = try? decoder.container(keyedBy: CodingKeys.self)
        renderedAt = Lenient.date(container, .renderedAt)
        staleAfterSeconds = Lenient.double(container, .staleAfterSeconds)
        sessions = Lenient.array(container, .sessions, as: Session.self).filter { !$0.sessionId.isEmpty }
    }
}

public struct Session: Equatable, Identifiable {
    public let sessionId: String
    public let bucket: String
    public let title: String?
    public let key: String?
    public let status: String?
    public let since: Date?
    public let message: String?
    public let replyTail: String?
    public let place: Place?
    public let cwd: String?
    public let orcaTerminal: String?
    public let backgroundTasks: [BackgroundTask]
    public let lastTool: LastTool?
    public let updatedAt: Date?
    public let nowLabel: String?
    public let href: String?

    public var id: String { sessionId }

    public var elapsedReference: Date? { since ?? updatedAt }

    public init(
        sessionId: String = "",
        bucket: String = "",
        title: String? = nil,
        key: String? = nil,
        status: String? = nil,
        since: Date? = nil,
        message: String? = nil,
        replyTail: String? = nil,
        place: Place? = nil,
        cwd: String? = nil,
        orcaTerminal: String? = nil,
        backgroundTasks: [BackgroundTask] = [],
        lastTool: LastTool? = nil,
        updatedAt: Date? = nil,
        nowLabel: String? = nil,
        href: String? = nil
    ) {
        self.sessionId = sessionId
        self.bucket = bucket
        self.title = title
        self.key = key
        self.status = status
        self.since = since
        self.message = message
        self.replyTail = replyTail
        self.place = place
        self.cwd = cwd
        self.orcaTerminal = orcaTerminal
        self.backgroundTasks = backgroundTasks
        self.lastTool = lastTool
        self.updatedAt = updatedAt
        self.nowLabel = nowLabel
        self.href = href
    }

    enum CodingKeys: String, CodingKey {
        case sessionId
        case bucket
        case title
        case key
        case status
        case since
        case message
        case replyTail
        case place
        case cwd
        case orcaTerminal
        case backgroundTasks
        case lastTool
        case updatedAt
        case nowLabel
        case href
    }
}

extension Session: Decodable {
    public init(from decoder: Decoder) {
        let container = try? decoder.container(keyedBy: CodingKeys.self)
        sessionId = Lenient.string(container, .sessionId) ?? ""
        bucket = Lenient.string(container, .bucket) ?? ""
        title = Lenient.string(container, .title)
        key = Lenient.string(container, .key)
        status = Lenient.string(container, .status)
        since = Lenient.date(container, .since)
        message = Lenient.string(container, .message)
        replyTail = Lenient.string(container, .replyTail)
        place = Lenient.object(container, .place, as: Place.self)
        cwd = Lenient.string(container, .cwd)
        orcaTerminal = Lenient.string(container, .orcaTerminal)
        backgroundTasks = Lenient.array(container, .backgroundTasks, as: BackgroundTask.self)
        lastTool = Lenient.object(container, .lastTool, as: LastTool.self)
        updatedAt = Lenient.date(container, .updatedAt)
        nowLabel = Lenient.string(container, .nowLabel)
        href = Lenient.string(container, .href)
    }
}

public struct Place: Equatable {
    public let label: String?
    public let branch: String?
    public let path: String?

    public init(label: String? = nil, branch: String? = nil, path: String? = nil) {
        self.label = label
        self.branch = branch
        self.path = path
    }

    enum CodingKeys: String, CodingKey {
        case label
        case branch
        case path
    }
}

extension Place: Decodable {
    public init(from decoder: Decoder) {
        let container = try? decoder.container(keyedBy: CodingKeys.self)
        label = Lenient.string(container, .label)
        branch = Lenient.string(container, .branch)
        path = Lenient.string(container, .path)
    }
}

public struct BackgroundTask: Equatable {
    public let type: String?
    public let taskDescription: String?

    public init(type: String? = nil, taskDescription: String? = nil) {
        self.type = type
        self.taskDescription = taskDescription
    }

    enum CodingKeys: String, CodingKey {
        case type
        case taskDescription = "description"
    }
}

extension BackgroundTask: Decodable {
    public init(from decoder: Decoder) {
        let container = try? decoder.container(keyedBy: CodingKeys.self)
        type = Lenient.string(container, .type)
        taskDescription = Lenient.string(container, .taskDescription)
    }
}

public struct LastTool: Equatable {
    public let name: String?
    public let at: Date?
    public let durationMs: Double?

    public init(name: String? = nil, at: Date? = nil, durationMs: Double? = nil) {
        self.name = name
        self.at = at
        self.durationMs = durationMs
    }

    enum CodingKeys: String, CodingKey {
        case name
        case at
        case durationMs
    }
}

extension LastTool: Decodable {
    public init(from decoder: Decoder) {
        let container = try? decoder.container(keyedBy: CodingKeys.self)
        name = Lenient.string(container, .name)
        at = Lenient.date(container, .at)
        durationMs = Lenient.double(container, .durationMs)
    }
}
