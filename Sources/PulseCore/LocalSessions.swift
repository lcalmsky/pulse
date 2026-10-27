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
    /// 답변 원문에서 고른 첫 문장. 알림 카드의 요약 한 줄에 쓴다.
    public let lastAssistantSummary: String?
    public let lastToolName: String?
    public let lastToolAt: Date?
    public let lastMeaningfulAt: Date?
    public let pendingToolLabel: String?
    public let pullRequest: PullRequestLink?
    /// 트랜스크립트 끝에서 센 압축 경계 레코드 수.
    public let compactions: Int?
    /// 아직 완료 알림을 받지 못한 백그라운드 작업(셸, 비동기 에이전트, 모니터) 수.
    public let backgroundTasks: Int?

    public init(
        customTitle: String? = nil,
        agentName: String? = nil,
        lastPrompt: String? = nil,
        lastAssistantText: String? = nil,
        lastSentence: String? = nil,
        lastAssistantSummary: String? = nil,
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
        self.lastAssistantSummary = lastAssistantSummary
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
    /// shell 세션에 쓰는 기준. shell 은 턴이 끝나고 백그라운드 셸이 도는 상태다.
    public static let backgroundStallThreshold: TimeInterval = 60 * 60
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
        guard let sessionId = nonEmpty(object["sessionId"] as? String),
              DeadhdState.isValidSessionId(sessionId)
        else { return nil }
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
        var lastAssistantSummary: String?
        var lastToolName: String?
        var lastToolAt: Date?
        var lastMeaningfulAt: Date?
        var pendingToolUses: [(id: String?, name: String, input: [String: Any])] = []
        var resolvedToolUseIds: Set<String> = []
        var pullRequest: PullRequestLink?
        var compactions = 0
        var backgroundToolUseIds: Set<String> = []
        var backgroundTaskIds: [String: String] = [:]
        var completedBackgroundToolUseIds: Set<String> = []
        var completedTaskIds: Set<String> = []
        var assistantTexts: [String] = []

        let lines = data.split(separator: 0x0A, omittingEmptySubsequences: false)
        let firstIndex = droppingPartialFirstLine && !lines.isEmpty ? 1 : 0

        for line in lines[firstIndex...] {
            guard let object = (try? JSONSerialization.jsonObject(with: Data(line))) as? [String: Any],
                  let type = object["type"] as? String
            else { continue }

            switch type {
            case "queue-operation":
                completedTaskIds.formUnion(taskNotificationValues(tag: "task-id", in: object["content"], terminalOnly: true))
            case "attachment":
                let attachment = object["attachment"] as? [String: Any]
                if attachment?["type"] as? String == "queued_command" {
                    completedTaskIds.formUnion(taskNotificationValues(tag: "task-id", in: attachment?["prompt"], terminalOnly: true))
                }
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
                            assistantTexts.append(raw)
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
                let result = object["toolUseResult"] as? [String: Any]
                for block in blocks where block["type"] as? String == "tool_result" {
                    if let id = nonEmpty(block["tool_use_id"] as? String) {
                        resolvedToolUseIds.insert(id)
                        let toolName = pendingToolUses.last { $0.id == id }?.name
                        if let taskId = backgroundTaskId(fromToolResult: result, toolName: toolName) {
                            backgroundToolUseIds.insert(id)
                            backgroundTaskIds[id] = taskId
                        }
                    }
                }
                if let stopped = nonEmpty(result?["task_id"] as? String) {
                    completedTaskIds.insert(stopped)
                }
                completedBackgroundToolUseIds.formUnion(
                    taskNotificationValues(tag: "tool-use-id", in: message?["content"])
                )
                completedTaskIds.formUnion(taskNotificationValues(tag: "task-id", in: message?["content"], terminalOnly: true))
            case "pr-link":
                if let url = nonEmpty(object["prUrl"] as? String),
                   SafeLink.httpURL(url) != nil,
                   let number = prNumber(object["prNumber"]), number > 0 {
                    pullRequest = PullRequestLink(number: number, url: url)
                }
            default:
                break
            }
        }

        // 평문화 결과가 빈 블록(코드 펜스뿐 등)은 답변으로 치지 않고 그 앞 블록을 쓴다.
        for raw in assistantTexts.reversed() {
            let plain = PlainText.markdown(raw)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !plain.isEmpty else { continue }
            lastAssistantText = trimmedText(plain)
            lastAssistantSentence = NowLine.lastSentence(plain)
            lastAssistantSummary = ReplySummary.firstSentence(raw)
            break
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
            lastAssistantSummary: lastAssistantSummary,
            lastToolName: lastToolName,
            lastToolAt: lastToolAt,
            lastMeaningfulAt: lastMeaningfulAt,
            pendingToolLabel: pendingLabel,
            pullRequest: pullRequest,
            compactions: compactions,
            backgroundTasks: backgroundToolUseIds.filter { id in
                !completedBackgroundToolUseIds.contains(id)
                    && !(backgroundTaskIds[id].map(completedTaskIds.contains) ?? false)
            }.count
        )
    }

    /// `run_in_background` 없이도 뒤로 넘어간 셸(Ctrl+B, 시간 초과)과 비동기 에이전트가 있어 도구 결과로 판정한다.
    static func backgroundTaskId(fromToolResult result: [String: Any]?, toolName: String?) -> String? {
        guard let result else { return nil }
        if let id = nonEmpty(result["backgroundTaskId"] as? String) { return id }
        if result["isAsync"] as? Bool == true, let id = nonEmpty(result["agentId"] as? String) { return id }
        return toolName == "Monitor" ? nonEmpty(result["taskId"] as? String) : nil
    }

    /// 백그라운드 작업 완료는 `<task-notification>` 으로 돌아온다. 턴 도중에 끝나면 대기열 레코드에만 남는다.
    /// 다른 안내 문구에도 같은 태그 이름이 쓰이므로 알림 블록만 본다.
    /// `terminalOnly` 면 `<status>` 가 있는 블록만 본다. 모니터 이벤트처럼 작업이 도는 중에 오는 알림에는 `<status>` 가 없다.
    public static func taskNotificationValues(tag: String, in content: Any?, terminalOnly: Bool = false) -> Set<String> {
        var texts: [String] = []
        if let text = content as? String {
            texts = [text]
        } else if let blocks = content as? [[String: Any]] {
            texts = blocks.compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }
        }

        var ids: Set<String> = []
        for text in texts {
            var rest = text[...]
            while let open = rest.range(of: "<task-notification>") {
                let close = rest.range(of: "</task-notification>", range: open.upperBound..<rest.endIndex)
                let block = rest[open.upperBound..<(close?.lowerBound ?? rest.endIndex)]
                rest = close.map { rest[$0.upperBound...] } ?? rest[rest.endIndex...]
                if terminalOnly && !block.contains("<status>") { continue }
                var remainder = block
                while let start = remainder.range(of: "<\(tag)>"),
                      let end = remainder.range(of: "</\(tag)>", range: start.upperBound..<remainder.endIndex) {
                    let id = remainder[start.upperBound..<end.lowerBound]
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if !id.isEmpty {
                        ids.insert(id)
                    }
                    remainder = remainder[end.upperBound...]
                }
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
            label = fileName(input["file_path"]).map { "\(L10n.editFile) · \($0)" } ?? L10n.editFile
        case "Read":
            label = fileName(input["file_path"]).map { "\(L10n.readFile) · \($0)" } ?? L10n.readFile
        case "Grep", "Glob":
            label = L10n.search
        case "WebFetch", "WebSearch":
            label = L10n.webFetch
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
        deadhd: DeadhdState? = nil,
        orcaTerminal: String? = nil
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
                message = L10n.waitingForPermission
            } else {
                status = "waiting_input"
                message = L10n.waitingForReply
            }
        case "busy", "shell":
            // 셸을 띄운 줄이 읽어 들인 트랜스크립트 꼬리 밖에 있으면 개수가 0 으로 나오므로 상태만 본다.
            let threshold = record.status == "shell" ? backgroundStallThreshold : stallThreshold
            if let last = summary.lastMeaningfulAt,
               now.timeIntervalSince(last) > threshold {
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
            replySummary: summary.lastAssistantSummary,
            lastSentence: summary.lastSentence,
            place: place,
            cwd: record.cwd,
            orcaTerminal: orcaTerminal,
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
