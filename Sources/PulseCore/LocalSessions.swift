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
    /// 잘리기 전 답변 평문에서 고른 마지막 문장. 「지금 하는 일」 한 줄에 쓴다.
    public let lastSentence: String?
    public let lastToolName: String?
    public let lastToolAt: Date?
    public let lastMeaningfulAt: Date?
    public let pendingToolLabel: String?
    public let pullRequest: PullRequestLink?
    /// 트랜스크립트 끝에서 센 압축 경계 레코드 수.
    public let compactions: Int?
    /// 아직 완료 알림을 받지 못한 `run_in_background` 도구 호출 수.
    public let backgroundTasks: Int?

    public init(
        customTitle: String? = nil,
        agentName: String? = nil,
        lastPrompt: String? = nil,
        lastAssistantText: String? = nil,
        lastSentence: String? = nil,
        lastToolName: String? = nil,
        lastToolAt: Date? = nil,
        lastMeaningfulAt: Date? = nil,
        pendingToolLabel: String? = nil,
        pullRequest: PullRequestLink? = nil,
        compactions: Int? = nil,
        backgroundTasks: Int? = nil
    ) {
        self.customTitle = customTitle
        self.agentName = agentName
        self.lastPrompt = lastPrompt
        self.lastAssistantText = lastAssistantText
        // 요약을 직접 만드는 호출도 있어, 전체 문장이 없으면 남은 인용에서 고른다.
        self.lastSentence = lastSentence ?? NowLine.lastSentence(lastAssistantText)
        self.lastToolName = lastToolName
        self.lastToolAt = lastToolAt
        self.lastMeaningfulAt = lastMeaningfulAt
        self.pendingToolLabel = pendingToolLabel
        self.pullRequest = pullRequest
        self.compactions = compactions
        self.backgroundTasks = backgroundTasks
    }
}

public enum LocalSessions {
    public static let stallThreshold: TimeInterval = 10 * 60
    public static let replyTailLimit = 160
    public static let promptTitleLimit = 60
    public static let actionLabelLimit = 40

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
        var lastAssistantSentence: String?
        var lastToolName: String?
        var lastToolAt: Date?
        var lastMeaningfulAt: Date?
        var pendingToolUses: [(id: String?, name: String, input: [String: Any])] = []
        var resolvedToolUseIds: Set<String> = []
        var pullRequest: PullRequestLink?
        var compactions = 0
        var backgroundToolUseIds: Set<String> = []
        var completedBackgroundToolUseIds: Set<String> = []

        let lines = data.split(separator: 0x0A, omittingEmptySubsequences: false)
        let firstIndex = droppingPartialFirstLine && !lines.isEmpty ? 1 : 0

        for line in lines[firstIndex...] {
            guard let object = (try? JSONSerialization.jsonObject(with: Data(line))) as? [String: Any],
                  let type = object["type"] as? String
            else { continue }

            switch type {
            case "system":
                if object["subtype"] as? String == "compact_boundary" {
                    compactions += 1
                }
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
                        if let raw = block["text"] as? String {
                            let plain = PlainText.markdown(raw)
                                .trimmingCharacters(in: .whitespacesAndNewlines)
                            if !plain.isEmpty {
                                lastAssistantText = trimmedText(plain)
                                lastAssistantSentence = NowLine.lastSentence(plain)
                            }
                        }
                    case "tool_use":
                        if let name = nonEmpty(block["name"] as? String) {
                            lastToolName = name
                            lastToolAt = timestamp
                            let input = block["input"] as? [String: Any] ?? [:]
                            let id = nonEmpty(block["id"] as? String)
                            pendingToolUses.append((id: id, name: name, input: input))
                            if input["run_in_background"] as? Bool == true, let id {
                                backgroundToolUseIds.insert(id)
                            }
                        }
                    default:
                        break
                    }
                }
            case "user":
                if let timestamp = TimestampParser.parse(object["timestamp"] as? String) {
                    lastMeaningfulAt = timestamp
                }
                let message = object["message"] as? [String: Any]
                let blocks = message?["content"] as? [[String: Any]] ?? []
                for block in blocks where block["type"] as? String == "tool_result" {
                    if let id = nonEmpty(block["tool_use_id"] as? String) {
                        resolvedToolUseIds.insert(id)
                    }
                }
                completedBackgroundToolUseIds.formUnion(
                    taskNotificationToolUseIds(in: message?["content"])
                )
            case "pr-link":
                if let url = nonEmpty(object["prUrl"] as? String),
                   let number = prNumber(object["prNumber"]), number > 0 {
                    pullRequest = PullRequestLink(number: number, url: url)
                }
            default:
                break
            }
        }

        let pending = pendingToolUses.last { entry in
            guard let id = entry.id else { return true }
            return !resolvedToolUseIds.contains(id)
        }
        let pendingLabel = pending.flatMap { nowActionLabel(toolName: $0.name, input: $0.input) }

        return TranscriptSummary(
            customTitle: customTitle,
            agentName: agentName,
            lastPrompt: lastPrompt,
            lastAssistantText: lastAssistantText,
            lastSentence: lastAssistantSentence,
            lastToolName: lastToolName,
            lastToolAt: lastToolAt,
            lastMeaningfulAt: lastMeaningfulAt,
            pendingToolLabel: pendingLabel,
            pullRequest: pullRequest,
            compactions: compactions,
            backgroundTasks: backgroundToolUseIds.subtracting(completedBackgroundToolUseIds).count
        )
    }

    /// 백그라운드 작업 완료는 `<task-notification>` 안의 `<tool-use-id>` 로 돌아온다.
    /// 다른 안내 문구에도 같은 태그 이름이 쓰이므로 알림 블록만 본다.
    public static func taskNotificationToolUseIds(in content: Any?) -> Set<String> {
        var texts: [String] = []
        if let text = content as? String {
            texts = [text]
        } else if let blocks = content as? [[String: Any]] {
            texts = blocks.compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }
        }

        var ids: Set<String> = []
        for text in texts where text.contains("<task-notification>") {
            var remainder = text[...]
            while let start = remainder.range(of: "<tool-use-id>"),
                  let end = remainder.range(of: "</tool-use-id>", range: start.upperBound..<remainder.endIndex) {
                let id = remainder[start.upperBound..<end.lowerBound]
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !id.isEmpty {
                    ids.insert(id)
                }
                remainder = remainder[end.upperBound...]
            }
        }
        return ids
    }

    // MARK: - 현재 동작

    /// 진행 중인 세션이 마지막으로 실행한 도구를 화면 문구로 바꾼다.
    public static func nowActionLabel(toolName: String, input: [String: Any]?) -> String? {
        guard let name = nonEmpty(toolName) else { return nil }
        let input = input ?? [:]

        if name.hasPrefix("mcp__") {
            let tool = name.components(separatedBy: "__").last ?? name
            return clippedActionLabel(tool)
        }

        let label: String
        switch name {
        case "Bash":
            if let description = nonEmpty(input["description"] as? String) {
                label = description
            } else if let command = nonEmpty(input["command"] as? String) {
                label = command.split(separator: "\n", omittingEmptySubsequences: false)
                    .first
                    .map(String.init) ?? command
            } else {
                label = name
            }
        case "Agent", "Task":
            label = nonEmpty(input["description"] as? String) ?? name
        case "Edit", "Write", "MultiEdit":
            label = fileName(input["file_path"]).map { "파일 편집 · \($0)" } ?? "파일 편집"
        case "Read":
            label = fileName(input["file_path"]).map { "파일 읽기 · \($0)" } ?? "파일 읽기"
        case "Grep", "Glob":
            label = "검색"
        case "WebFetch", "WebSearch":
            label = "웹 조회"
        default:
            label = name
        }
        return clippedActionLabel(label)
    }

    /// 화면 옆에 붙는 짧은 위치. 홈 밖이면 마지막 칸만 쓴다.
    public static func shortLocation(forCwd cwd: String?, home: String?) -> String? {
        guard let cwd = nonEmpty(cwd) else { return nil }
        let components = pathComponents(cwd)
        guard !components.isEmpty else { return nil }
        let homeComponents = pathComponents(nonEmpty(home) ?? "")

        if !homeComponents.isEmpty {
            if components == homeComponents { return "~" }

            let orcaPrefix = homeComponents + ["orca", "workspaces"]
            if components.starts(with: orcaPrefix), components.count > orcaPrefix.count + 1 {
                return components[orcaPrefix.count] + "/" + components[orcaPrefix.count + 1]
            }
        }

        if let index = components.firstIndex(of: ".claude"),
           index > 0,
           components.count > index + 2,
           components[index + 1] == "worktrees" {
            return components[index - 1] + "/" + components[index + 2]
        }

        if !homeComponents.isEmpty {
            let gitPrefix = homeComponents + ["git-repo"]
            if components.starts(with: gitPrefix), components.count > gitPrefix.count {
                let repo = components[gitPrefix.count]
                if components.count > gitPrefix.count + 1 {
                    return repo + "/" + components[gitPrefix.count + 1]
                }
                return repo
            }
        }

        return components.last
    }

    /// 제목과 같은 이름의 위치는 카드에 같은 글자를 두 번 보이므로 그리지 않는다.
    public static func locationMatchesTitle(_ location: String, title: String?) -> Bool {
        guard let title = nonEmpty(title) else { return false }
        return normalizedLabel(location) == normalizedLabel(title)
    }

    // MARK: - 화면 모델

    public static func makeSession(
        record: LocalSessionRecord,
        summary: TranscriptSummary,
        now: Date,
        home: String? = nil,
        deadhd: DeadhdState? = nil
    ) -> Session {
        // 꺼진 세션의 요약은 체크리스트로 쓰지 않는다. 활동 정보는 그대로 쓴다.
        let checklist = deadhd?.hasChecklist == true ? deadhd : nil
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
                message = "답을 기다리고 있어요"
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
            checklist?.title,
            summary.customTitle,
            summary.agentName,
            record.name,
            summary.lastPrompt.map { String($0.prefix(promptTitleLimit)) }
        )
        let updatedAt = [record.statusUpdatedAt, summary.lastMeaningfulAt]
            .compactMap { $0 }
            .max()
        let lastTool = summary.lastToolName.map { LastTool(name: $0, at: summary.lastToolAt) }
        let location = shortLocation(forCwd: record.cwd, home: home)
        let place = location.flatMap { location in
            locationMatchesTitle(location, title: title)
                ? nil
                : Place(label: location, branch: nil, path: record.cwd)
        }
        let nowLabel = checklist != nil
            ? checklist?.nowLabel
            : (bucket == "working" ? summary.pendingToolLabel : nil)
        // deadhd 요약과 트랜스크립트가 같은 PR 을 가리키면 한 번만 그린다.
        let pullRequests = mergedPullRequests(checklist?.pr, summary.pullRequest)

        return Session(
            sessionId: record.sessionId,
            bucket: bucket,
            title: title,
            key: record.name,
            status: status,
            since: record.statusUpdatedAt ?? record.startedAt,
            message: message,
            replyTail: summary.lastAssistantText,
            lastSentence: summary.lastSentence,
            place: place,
            cwd: record.cwd,
            backgroundTasks: deadhd?.hasBackgroundTasks == true ? deadhd?.backgroundTasks ?? [] : [],
            lastTool: lastTool,
            updatedAt: updatedAt,
            nowLabel: nowLabel,
            pagePath: checklist?.pagePath,
            dataPath: checklist?.dataPath,
            counts: checklist?.counts,
            total: checklist?.total,
            stepStates: checklist?.states,
            pr: pullRequests.first,
            extraPRs: Array(pullRequests.dropFirst()),
            jiraKey: checklist?.key,
            jiraHref: checklist?.keyHref,
            eta: checklist?.eta,
            dataAt: checklist?.dataAt,
            activity: SessionActivity.make(state: deadhd, summary: summary),
            currentAction: summary.pendingToolLabel
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

    static func prNumber(_ value: Any?) -> Int? {
        if let number = integer(value) { return number }
        if let raw = value as? String { return Int(raw.trimmingCharacters(in: .whitespaces)) }
        return nil
    }

    static func clippedActionLabel(_ raw: String) -> String? {
        let plain = PlainText.markdown(raw)
        guard !plain.isEmpty else { return nil }
        return String(plain.prefix(actionLabelLimit))
    }

    static func fileName(_ value: Any?) -> String? {
        guard let path = nonEmpty(value as? String) else { return nil }
        return nonEmpty((path as NSString).lastPathComponent)
    }

    static func pathComponents(_ path: String) -> [String] {
        path.split(separator: "/").map(String.init)
    }

    static func normalizedLabel(_ value: String) -> String {
        String(value.lowercased().filter { $0 != "-" && $0 != "_" })
    }

    static func mergedPullRequests(_ values: PullRequestLink?...) -> [PullRequestLink] {
        var seen: Set<String> = []
        return values.compactMap { $0 }.filter { seen.insert($0.url).inserted }
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
        // 완료로 끝난 턴은 since 가 곧 완료 시각이라, 사용자가 확인해 숨긴 키를 유지한다.
        let since = session.bucket == "done" ? session.since : date
        return Session(
            sessionId: session.sessionId,
            bucket: "ended",
            title: session.title,
            key: session.key,
            status: "ended",
            since: since,
            message: session.message,
            replyTail: session.replyTail,
            lastSentence: session.lastSentence,
            place: session.place,
            cwd: session.cwd,
            orcaTerminal: session.orcaTerminal,
            backgroundTasks: session.backgroundTasks,
            lastTool: session.lastTool,
            updatedAt: date,
            nowLabel: session.nowLabel,
            pagePath: session.pagePath,
            dataPath: session.dataPath,
            counts: session.counts,
            total: session.total,
            stepStates: session.stepStates,
            pr: session.pr,
            extraPRs: session.extraPRs,
            jiraKey: session.jiraKey,
            jiraHref: session.jiraHref,
            eta: session.eta,
            dataAt: session.dataAt,
            activity: session.activity,
            currentAction: session.currentAction
        )
    }
}
