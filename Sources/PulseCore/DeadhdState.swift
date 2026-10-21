import Foundation

public struct DeadhdCompactions: Equatable {
    public let count: Int
    public let lastAt: Date?

    public init(count: Int, lastAt: Date? = nil) {
        self.count = count
        self.lastAt = lastAt
    }
}

/// deadhd 스킬이 세션마다 남기는 `/tmp/deadhd-state/<sessionId>.json` 하나.
/// 스킬을 부르지 않은 세션에는 이 파일이 없고, 이 값은 비어 있다.
public struct DeadhdState: Equatable {
    public static let staleInterval: TimeInterval = 30 * 60
    public static let defaultDirectory = "/tmp/deadhd-state"
    private static let sessionIdPattern = "^[A-Za-z0-9._-]{1,128}$"

    public let sessionId: String
    public let title: String?
    public let counts: SessionCounts?
    public let total: Int?
    public let nowLabel: String?
    public let key: String?
    public let keyHref: String?
    public let pr: PullRequestLink?
    public let dataAt: Date?
    public let eta: Date?
    /// `--off` 로 갱신을 끈 세션. 요약이 남아 있어도 체크리스트로 쓰지 않는다.
    public let isOff: Bool
    public var pagePath: String?
    /// 체크리스트 JSON 의 절대 경로. 진행 페이지 HTML 이 아직 없을 때 만드는 데 쓴다.
    public var dataPath: String?
    public let hasBackgroundTasks: Bool
    public let backgroundTasks: [BackgroundTask]
    public let hasCompactions: Bool
    public let compactions: DeadhdCompactions?
    public let lastTool: LastTool?
    public let summaryAvailable: Bool

    public var hasChecklist: Bool {
        !isOff && summaryAvailable && counts != nil && (total ?? 0) > 0
    }

    /// 데이터 파일이 오래된 세션은 진행률을 흐리게 그린다.
    public func progressIsStale(at now: Date) -> Bool {
        guard let dataAt else { return false }
        return now.timeIntervalSince(dataAt) > Self.staleInterval
    }

    public static func isValidSessionId(_ value: String?) -> Bool {
        guard let value, value != ".", value != ".." else { return false }
        return value.range(of: sessionIdPattern, options: .regularExpression) != nil
    }

    public static func stateDirectory(environment: [String: String]) -> String {
        guard let configured = environment["DEADHD_STATE_DIR"], !configured.isEmpty else {
            return defaultDirectory
        }
        return configured
    }

    /// 모양이 어긋난 필드는 버리고 읽을 수 있는 것만 남긴다.
    public static func parse(_ data: Data, expectedSessionId: String? = nil) -> DeadhdState? {
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return nil
        }
        guard let sessionId = string(object["sessionId"]), isValidSessionId(sessionId) else { return nil }
        if let expectedSessionId, sessionId != expectedSessionId { return nil }

        let summary = object["summary"] as? [String: Any]
        let offAt = string(object["offAt"])
        let countsObject = summary?["counts"] as? [String: Any]
        let counts = countsObject.map { value in
            SessionCounts(
                done: integer(value["done"]) ?? 0,
                left: integer(value["left"]) ?? 0,
                now: integer(value["now"]) ?? 0,
                blocked: integer(value["blocked"]) ?? 0
            )
        }
        let tasksObject = object["backgroundTasks"] as? [[String: Any]] ?? []
        let compactionsObject = object["compactions"] as? [String: Any]

        return DeadhdState(
            sessionId: sessionId,
            title: string(summary?["title"]),
            counts: counts,
            total: integer(summary?["total"]),
            nowLabel: string(summary?["nowLabel"]),
            key: string(summary?["key"]),
            keyHref: string(summary?["keyHref"]),
            pr: pullRequest(summary?["pr"]),
            dataAt: TimestampParser.parse(string(summary?["dataAt"])),
            eta: TimestampParser.parse(string(summary?["etaCalibrated"]))
                ?? TimestampParser.parse(string(summary?["eta"])),
            isOff: offAt != nil,
            pagePath: absolutePath(object["out"]),
            dataPath: absolutePath(object["data"]),
            hasBackgroundTasks: object["backgroundTasks"] is [Any],
            backgroundTasks: tasksObject.map {
                BackgroundTask(
                    type: string($0["type"]),
                    taskDescription: string($0["description"])
                )
            },
            hasCompactions: compactionsObject != nil,
            compactions: compactionsObject.map {
                DeadhdCompactions(
                    count: integer($0["count"]) ?? 0,
                    lastAt: TimestampParser.parse(string($0["lastAt"]))
                )
            },
            lastTool: lastTool(object["lastTool"]),
            summaryAvailable: summary != nil
        )
    }

    private static func lastTool(_ value: Any?) -> LastTool? {
        guard let object = value as? [String: Any],
              let name = string(object["name"])
        else { return nil }
        let duration: Double?
        if let number = object["durationMs"] as? NSNumber,
           CFGetTypeID(number) != CFBooleanGetTypeID() {
            duration = number.doubleValue
        } else {
            duration = nil
        }
        return LastTool(
            name: name,
            at: TimestampParser.parse(string(object["at"])),
            durationMs: duration
        )
    }

    private static func pullRequest(_ value: Any?) -> PullRequestLink? {
        guard let object = value as? [String: Any],
              let url = string(object["href"]),
              url.hasPrefix("http://") || url.hasPrefix("https://")
        else { return nil }
        let label = string(object["text"])
        let number = trailingNumber(label) ?? trailingNumber(url)
        return PullRequestLink(number: number ?? 0, url: url, label: label)
    }

    private static func trailingNumber(_ value: String?) -> Int? {
        guard let value else { return nil }
        let digits = value.reversed().prefix { $0.isASCII && $0.isNumber }.reversed()
        return digits.isEmpty ? nil : Int(String(digits))
    }

    private static func absolutePath(_ value: Any?) -> String? {
        guard let path = string(value), path.hasPrefix("/") else { return nil }
        return path
    }

    private static func string(_ value: Any?) -> String? {
        guard let raw = value as? String else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func integer(_ value: Any?) -> Int? {
        guard let value else { return nil }
        if let int = value as? Int { return int }
        // JSON 의 true/false 도 NSNumber 로 오고 0/1 과 구별되지 않는다.
        if let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() {
            return number.intValue
        }
        return nil
    }
}

/// 행의 상태 줄 아래에 붙는 `압축 1 · 백그라운드 2 · Bash 12초 전`.
/// 상태 파일에 있는 값을 먼저 쓰고, 없는 항목만 트랜스크립트에서 만든 값을 쓴다.
public struct SessionActivity: Equatable {
    public let compactions: Int?
    public let backgroundTasks: Int?
    public let lastTool: LastTool?

    public init(compactions: Int? = nil, backgroundTasks: Int? = nil, lastTool: LastTool? = nil) {
        self.compactions = compactions
        self.backgroundTasks = backgroundTasks
        self.lastTool = lastTool
    }

    public static func make(state: DeadhdState?, summary: TranscriptSummary) -> SessionActivity? {
        let compactions = state?.hasCompactions == true ? state?.compactions?.count : summary.compactions
        let backgroundTasks = state?.hasBackgroundTasks == true
            ? state?.backgroundTasks.count
            : summary.backgroundTasks
        let transcriptTool = summary.lastToolName.map { LastTool(name: $0, at: summary.lastToolAt) }
        let stateTool = state?.lastTool.flatMap { $0.name == nil ? nil : $0 }
        let lastTool = stateTool ?? transcriptTool
        guard compactions != nil || backgroundTasks != nil || lastTool != nil else { return nil }
        return SessionActivity(compactions: compactions, backgroundTasks: backgroundTasks, lastTool: lastTool)
    }

    public func line(now: Date) -> String? {
        var parts: [String] = []
        if let compactions, compactions > 0 {
            parts.append("압축 \(compactions)")
        }
        if let backgroundTasks, backgroundTasks > 0 {
            parts.append("백그라운드 \(backgroundTasks)")
        }
        if let lastTool, let name = lastTool.name {
            if let at = lastTool.at, let ago = TimePhrase.ago(from: at, to: now) {
                parts.append("\(name) \(ago)")
            } else {
                parts.append(name)
            }
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
