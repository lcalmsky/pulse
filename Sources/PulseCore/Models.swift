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

    static func int<K: CodingKey>(_ container: KeyedDecodingContainer<K>?, _ key: K) -> Int? {
        guard let container, let value = try? container.decodeIfPresent(Int.self, forKey: key) else {
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

public struct SessionCounts: Equatable {
    public let done: Int
    public let left: Int
    public let now: Int
    public let blocked: Int

    public init(done: Int = 0, left: Int = 0, now: Int = 0, blocked: Int = 0) {
        self.done = done
        self.left = left
        self.now = now
        self.blocked = blocked
    }

    enum CodingKeys: String, CodingKey {
        case done
        case left
        case now
        case blocked
    }
}

extension SessionCounts: Decodable {
    public init(from decoder: Decoder) {
        let container = try? decoder.container(keyedBy: CodingKeys.self)
        done = Lenient.int(container, .done) ?? 0
        left = Lenient.int(container, .left) ?? 0
        now = Lenient.int(container, .now) ?? 0
        blocked = Lenient.int(container, .blocked) ?? 0
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
    public let counts: SessionCounts?
    public let total: Int?
    public let pr: PullRequestLink?

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
        href: String? = nil,
        counts: SessionCounts? = nil,
        total: Int? = nil,
        pr: PullRequestLink? = nil
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
        self.counts = counts
        self.total = total
        self.pr = pr
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
        case counts
        case total
        case summary
    }

    enum SummaryKeys: String, CodingKey {
        case counts
        case total
        case nowLabel
    }
}

extension Session: Decodable {
    public init(from decoder: Decoder) {
        let container = try? decoder.container(keyedBy: CodingKeys.self)
        // 세션 목록이 summary 를 펼쳐 주지 않는 서버도 있어 양쪽 모양을 모두 받는다.
        let summary = container.flatMap {
            try? $0.nestedContainer(keyedBy: SummaryKeys.self, forKey: .summary)
        }
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
        nowLabel = Lenient.string(container, .nowLabel) ?? Lenient.string(summary, .nowLabel)
        href = Lenient.string(container, .href)
        counts = Lenient.object(container, .counts, as: SessionCounts.self)
            ?? Lenient.object(summary, .counts, as: SessionCounts.self)
        total = Lenient.int(container, .total) ?? Lenient.int(summary, .total)
        pr = nil
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

public struct PullRequestLink: Equatable {
    public let number: Int
    public let url: String

    public init(number: Int, url: String) {
        self.number = number
        self.url = url
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
