import Foundation

/// Claude Code 가 `<설정 루트>/sessions/<pid>.json` 에 남기는 살아 있는 세션 한 건.
public struct LocalSessionRecord: Equatable {
    public let pid: Int
    public let sessionId: String
    public let cwd: String?
    public let name: String?
    public let entrypoint: String?
    public let status: String?
    public let waitingFor: String?
    public let startedAt: Date?
    public let updatedAt: Date?
    public let statusUpdatedAt: Date?

    public init(
        pid: Int,
        sessionId: String,
        cwd: String? = nil,
        name: String? = nil,
        entrypoint: String? = nil,
        status: String? = nil,
        waitingFor: String? = nil,
        startedAt: Date? = nil,
        updatedAt: Date? = nil,
        statusUpdatedAt: Date? = nil
    ) {
        self.pid = pid
        self.sessionId = sessionId
        self.cwd = cwd
        self.name = name
        self.entrypoint = entrypoint
        self.status = status
        self.waitingFor = waitingFor
        self.startedAt = startedAt
        self.updatedAt = updatedAt
        self.statusUpdatedAt = statusUpdatedAt
    }
}

/// 트랜스크립트 끝에서 뽑은 화면용 요약. 파일 IO 없이 Data 만으로 만든다.
public struct TranscriptSummary: Equatable {
    public let customTitle: String?
    public let agentName: String?
    public let lastPrompt: String?
    public let lastAssistantText: String?
    public let lastToolName: String?
    public let lastToolAt: Date?
    public let lastMeaningfulAt: Date?

    public init(
        customTitle: String? = nil,
        agentName: String? = nil,
        lastPrompt: String? = nil,
        lastAssistantText: String? = nil,
        lastToolName: String? = nil,
        lastToolAt: Date? = nil,
        lastMeaningfulAt: Date? = nil
    ) {
        self.customTitle = customTitle
        self.agentName = agentName
        self.lastPrompt = lastPrompt
        self.lastAssistantText = lastAssistantText
        self.lastToolName = lastToolName
        self.lastToolAt = lastToolAt
        self.lastMeaningfulAt = lastMeaningfulAt
    }
}

public enum LocalSessions {
    public static let stallThreshold: TimeInterval = 10 * 60
    public static let replyTailLimit = 160
    public static let promptTitleLimit = 60

    // MARK: - 파일 규칙

    /// `sessions/` 에서 읽을 파일은 `<pid>.json` 뿐이다. 옆의 `<pid>.<hash>.key` 는 비밀 토큰이다.
    public static func isSessionFileName(_ name: String) -> Bool {
        let suffix = ".json"
        guard name.hasSuffix(suffix), name.count > suffix.count else { return false }
        let stem = name.dropLast(suffix.count)
        return !stem.isEmpty && stem.allSatisfy { $0.isASCII && $0.isNumber }
    }

    /// cwd 의 영숫자가 아닌 문자를 모두 `-` 로 바꾼 프로젝트 디렉터리 이름.
    public static func projectSlug(forCwd cwd: String) -> String {
        var slug = ""
        for character in cwd {
            if character.isASCII && (character.isLetter || character.isNumber) {
                slug.append(character)
            } else {
                slug.append("-")
            }
        }
        return slug
    }

    // MARK: - 세션 파일

    public static func parseRecord(_ data: Data) -> LocalSessionRecord? {
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return nil
        }
        guard let sessionId = nonEmpty(object["sessionId"] as? String) else { return nil }
        guard let pid = integer(object["pid"]), pid > 0 else { return nil }
        return LocalSessionRecord(
            pid: pid,
            sessionId: sessionId,
            cwd: object["cwd"] as? String,
            name: nonEmpty(object["name"] as? String),
            entrypoint: object["entrypoint"] as? String,
            status: object["status"] as? String,
            waitingFor: object["waitingFor"] as? String,
            startedAt: date(fromMilliseconds: object["startedAt"]),
            updatedAt: date(fromMilliseconds: object["updatedAt"]),
            statusUpdatedAt: date(fromMilliseconds: object["statusUpdatedAt"])
        )
    }

    /// 대화형 CLI 세션만 화면에 올린다. SDK·`claude -p` 계열은 기본으로 뺀다.
    public static func shouldInclude(_ record: LocalSessionRecord) -> Bool {
        record.entrypoint == "cli"
    }

    // MARK: - 트랜스크립트

    /// 트랜스크립트 끝 조각을 요약한다. 잘린 첫 줄은 `droppingPartialFirstLine` 으로 버린다.
    public static func summarizeTranscriptTail(
        _ data: Data,
        droppingPartialFirstLine: Bool
    ) -> TranscriptSummary {
        var customTitle: String?
        var agentName: String?
        var lastPrompt: String?
        var lastAssistantText: String?
        var lastToolName: String?
        var lastToolAt: Date?
        var lastMeaningfulAt: Date?

        let lines = data.split(separator: 0x0A, omittingEmptySubsequences: false)
        let firstIndex = droppingPartialFirstLine && !lines.isEmpty ? 1 : 0

        for line in lines[firstIndex...] {
            guard let object = (try? JSONSerialization.jsonObject(with: Data(line))) as? [String: Any],
                  let type = object["type"] as? String
            else { continue }

            switch type {
            case "custom-title":
                if let value = nonEmpty(object["customTitle"] as? String) {
                    customTitle = value
                }
            case "agent-name":
                if let value = nonEmpty(object["agentName"] as? String) {
                    agentName = value
                }
            case "last-prompt":
                if let value = nonEmpty(object["lastPrompt"] as? String) {
                    lastPrompt = value
                }
            case "assistant":
                let timestamp = TimestampParser.parse(object["timestamp"] as? String)
                if let timestamp {
                    lastMeaningfulAt = timestamp
                }
                let message = object["message"] as? [String: Any]
                let blocks = message?["content"] as? [[String: Any]] ?? []
                for block in blocks {
                    switch block["type"] as? String {
                    case "text":
                        if let text = trimmedText(block["text"] as? String) {
                            lastAssistantText = text
                        }
                    case "tool_use":
                        if let name = nonEmpty(block["name"] as? String) {
                            lastToolName = name
                            lastToolAt = timestamp
                        }
                    default:
                        break
                    }
                }
            case "user":
                if let timestamp = TimestampParser.parse(object["timestamp"] as? String) {
                    lastMeaningfulAt = timestamp
                }
            default:
                break
            }
        }

        return TranscriptSummary(
            customTitle: customTitle,
            agentName: agentName,
            lastPrompt: lastPrompt,
            lastAssistantText: lastAssistantText,
            lastToolName: lastToolName,
            lastToolAt: lastToolAt,
            lastMeaningfulAt: lastMeaningfulAt
        )
    }

    // MARK: - 화면 모델

    public static func makeSession(
        record: LocalSessionRecord,
        summary: TranscriptSummary,
        now: Date
    ) -> Session {
        var bucket: String
        var status: String?
        var message: String?

        switch record.status {
        case "waiting":
            bucket = "wait"
            if record.waitingFor == "permission prompt" {
                status = "waiting_permission"
                message = "권한 승인을 기다려요"
            } else {
                status = "waiting_input"
                message = "입력을 기다려요"
            }
        case "busy", "shell":
            if let last = summary.lastMeaningfulAt,
               now.timeIntervalSince(last) > stallThreshold {
                bucket = "stall"
            } else {
                bucket = "working"
            }
            status = "working"
        case "idle":
            bucket = "done"
            status = "idle"
        default:
            bucket = "working"
            status = record.status
        }

        let title = firstNonEmpty(
            summary.customTitle,
            summary.agentName,
            record.name,
            summary.lastPrompt.map { String($0.prefix(promptTitleLimit)) }
        )
        let updatedAt = [record.statusUpdatedAt, summary.lastMeaningfulAt]
            .compactMap { $0 }
            .max()
        let lastTool = summary.lastToolName.map { LastTool(name: $0, at: summary.lastToolAt) }

        return Session(
            sessionId: record.sessionId,
            bucket: bucket,
            title: title,
            key: record.name,
            status: status,
            since: record.statusUpdatedAt ?? record.startedAt,
            message: message,
            replyTail: summary.lastAssistantText,
            cwd: record.cwd,
            lastTool: lastTool,
            updatedAt: updatedAt
        )
    }

    // MARK: - 도우미

    static func integer(_ value: Any?) -> Int? {
        guard let value, !(value is Bool) else { return nil }
        if let int = value as? Int { return int }
        if let number = value as? NSNumber { return number.intValue }
        return nil
    }

    static func date(fromMilliseconds value: Any?) -> Date? {
        guard let value, !(value is Bool) else { return nil }
        let milliseconds: Double
        if let number = value as? NSNumber {
            milliseconds = number.doubleValue
        } else if let double = value as? Double {
            milliseconds = double
        } else {
            return nil
        }
        guard milliseconds > 0 else { return nil }
        return Date(timeIntervalSince1970: milliseconds / 1000)
    }

    static func nonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty
        else { return nil }
        return trimmed
    }

    static func trimmedText(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty
        else { return nil }
        return String(trimmed.prefix(replyTailLimit))
    }

    static func firstNonEmpty(_ values: String?...) -> String? {
        for value in values {
            if let value = nonEmpty(value) {
                return value
            }
        }
        return nil
    }
}

/// 사라진 세션을 12시간 동안 `ended` 로 들고 있는 메모리 상태. 디스크에 남기지 않는다.
public struct EndedSessionTracker {
    public static let retention: TimeInterval = 12 * 60 * 60

    private var lastActive: [String: Session] = [:]
    private var endedSessions: [String: (session: Session, endedAt: Date)] = [:]

    public init() {}

    /// 이번 폴링의 살아 있는 세션을 받아, 사라진 세션을 `ended` 로 돌려준다.
    public mutating func reconcile(active: [Session], at now: Date) -> [Session] {
        let current = Dictionary(active.map { ($0.sessionId, $0) }, uniquingKeysWith: { first, _ in first })

        for sessionId in current.keys {
            endedSessions[sessionId] = nil
        }
        for (sessionId, session) in lastActive where current[sessionId] == nil {
            if endedSessions[sessionId] == nil {
                endedSessions[sessionId] = (session, now)
            }
        }
        lastActive = current
        endedSessions = endedSessions.filter { now.timeIntervalSince($0.value.endedAt) < Self.retention }

        return endedSessions.values
            .sorted { $0.endedAt < $1.endedAt }
            .map { ended($0.session, at: $0.endedAt) }
    }

    private func ended(_ session: Session, at date: Date) -> Session {
        Session(
            sessionId: session.sessionId,
            bucket: "ended",
            title: session.title,
            key: session.key,
            status: "ended",
            since: date,
            message: session.message,
            replyTail: session.replyTail,
            place: session.place,
            cwd: session.cwd,
            orcaTerminal: session.orcaTerminal,
            backgroundTasks: session.backgroundTasks,
            lastTool: session.lastTool,
            updatedAt: date,
            nowLabel: session.nowLabel,
            href: session.href,
            counts: session.counts,
            total: session.total
        )
    }
}

/// deadhd 서버가 살아 있을 때만 로컬 세션에 덧입히는 값.
public enum SessionOverlay {
    public static func apply(local: [Session], remote: [Session]) -> [Session] {
        guard !remote.isEmpty else { return local }
        let byId = Dictionary(remote.map { ($0.sessionId, $0) }, uniquingKeysWith: { first, _ in first })
        return local.map { session in
            guard let remote = byId[session.sessionId] else { return session }
            return Session(
                sessionId: session.sessionId,
                bucket: session.bucket,
                title: session.title,
                key: session.key,
                status: session.status,
                since: session.since,
                message: session.message,
                replyTail: session.replyTail,
                place: remote.place,
                cwd: session.cwd,
                orcaTerminal: remote.orcaTerminal,
                backgroundTasks: remote.backgroundTasks,
                lastTool: session.lastTool,
                updatedAt: session.updatedAt,
                nowLabel: remote.nowLabel,
                href: remote.href,
                counts: remote.counts,
                total: session.total
            )
        }
    }
}
