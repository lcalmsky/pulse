import Foundation

public enum DisplayGroup: Int, CaseIterable, Equatable {
    case attention
    case working
    case done

    public var title: String {
        switch self {
        case .attention: return L10n.groupAttention
        case .working: return L10n.groupWorkingCompact
        case .done: return L10n.groupDone
        }
    }
}

public struct ChecklistProgress: Equatable {
    public let done: Int
    public let total: Int

    public init(done: Int, total: Int) {
        self.done = done
        self.total = total
    }

    public var fraction: Double {
        guard total > 0 else { return 0 }
        return Double(min(max(done, 0), total)) / Double(total)
    }

    public var text: String { "\(done)/\(total)" }
}

public struct DisplayItem: Equatable, Identifiable {
    public let sessionId: String
    public let title: String
    public let status: String
    public let detail: String?
    public let placeText: String?
    public let key: String?
    public let progress: ChecklistProgress?
    public let counts: SessionCounts?
    /// 상태 파일이 남긴 단계 순서. 스텝퍼가 막힌 단계의 실제 위치를 그릴 때 쓴다.
    public let stepStates: [String]?
    public let etaText: String?
    public let backgroundTaskCount: Int?
    public let lastToolName: String?
    /// 30분 넘게 갱신되지 않은 체크리스트. 진행률을 흐리게 그린다.
    public let progressStale: Bool
    public let blocked: Bool
    public let replyTail: String?
    /// 답변 원문에서 고른 첫 문장. 알림 카드의 요약 한 줄에 쓴다.
    public let summary: String?
    public let lastSentence: String?
    public let nowLabel: String?
    public let prTag: String?
    public let prURL: String?
    public let extraPRs: [PullRequestLink]
    public let jiraKey: String?
    public let jiraHref: String?
    public let activityLine: String?
    /// 상태 줄 아래의 「지금 뭐 하는지」 한 줄. 고를 것이 없으면 nil.
    public let nowLine: String?
    public let group: DisplayGroup
    public let isStall: Bool
    public let orcaTerminal: String?
    public let cwd: String?
    public let multiplexer: MultiplexerPane?
    public let pagePath: String?
    /// 진행 페이지 HTML 이 아직 없을 때 만들 때 쓰는 체크리스트 JSON 의 절대 경로.
    public let dataPath: String?
    public let acknowledgeKey: String
    public let sortDate: Date?

    public var id: String { sessionId }

    /// 화면에 그리는 행의 식별자. 그룹이 바뀌면 다른 행으로 취급해
    /// 목록 뷰가 섹션을 건너 같은 뷰를 재사용하지 않게 한다.
    public var rowID: String { "\(group.rawValue)+\(sessionId)" }

    public var clickAction: SessionClickAction {
        SessionClick.resolve(orcaTerminal: orcaTerminal, cwd: cwd, multiplexer: multiplexer)
    }

    public var isActionable: Bool { clickAction != .none }

    /// 지금 하는 일 한 줄을 그리는 행. 확인 필요 섹션에 있는 stall 도 진행 중으로 다룬다.
    public var isRunning: Bool { group == .working || isStall }

    /// 단계 줄을 펼칠 수 있는 행. 진행 중 행과, 체크리스트를 다 끝내지 못한 채 턴이 끝난 완료 행이다.
    public var showsStepLine: Bool {
        guard dataPath != nil else { return false }
        guard group == .working || (group == .done && hasUnfinishedChecklist) else { return false }
        return !Stepper.segments(states: stepStates, counts: counts, total: progress?.total).isEmpty
    }

    public var hasUnfinishedChecklist: Bool {
        guard let progress else { return false }
        return progress.done < progress.total
    }

    /// 제목과 같은 이름의 태그는 카드에 같은 글자를 두 번 보이므로 그리지 않는다.
    public var keyTag: String? {
        guard let key else { return nil }
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return key.caseInsensitiveCompare(trimmedTitle) == .orderedSame ? nil : key
    }

    public init(session: Session, group: DisplayGroup, now: Date) {
        self.sessionId = session.sessionId
        self.title = Grouping.clean(session.title).map { String($0.prefix(60)) } ?? L10n.untitledSession
        self.status = Grouping.statusText(session: session, group: group, now: now)
        self.detail = Grouping.detailText(session: session, group: group)
        self.placeText = Grouping.placeText(session.place)
        self.key = Grouping.nonEmpty(session.key)
        if let counts = session.counts, let total = session.total, total > 0 {
            self.progress = ChecklistProgress(done: max(0, counts.done), total: total)
            self.counts = counts
        } else {
            self.progress = nil
            self.counts = nil
        }
        self.stepStates = session.stepStates
        self.etaText = Grouping.etaText(session, now: now)
        self.backgroundTaskCount = session.activity?.backgroundTasks
        self.lastToolName = Grouping.nonEmpty(session.activity?.lastTool?.name)
        self.progressStale = session.dataAt.map { now.timeIntervalSince($0) > DeadhdState.staleInterval } ?? false
        self.blocked = (session.counts?.blocked ?? 0) > 0
        self.replyTail = Grouping.clean(session.replyTail)
        self.summary = Grouping.clean(session.replySummary)
        self.lastSentence = Grouping.clean(session.lastSentence)
        self.nowLabel = Grouping.nonEmpty(session.nowLabel)
        self.prTag = session.pr.map { $0.label ?? "#\($0.number)" }
        self.prURL = Grouping.nonEmpty(session.pr?.url)
        self.extraPRs = session.extraPRs.filter { Grouping.nonEmpty($0.url) != nil }
        self.jiraKey = Grouping.nonEmpty(session.jiraKey)
        self.jiraHref = Grouping.nonEmpty(session.jiraHref)
        self.activityLine = session.activity?.line(now: now)
        self.nowLine = NowLine.resolve(
            stage: self.nowLabel,
            currentAction: session.currentAction,
            lastSentence: self.lastSentence,
            statusLine: self.status
        )
        self.group = group
        self.isStall = session.bucket == "stall"
        self.orcaTerminal = Grouping.nonEmpty(session.orcaTerminal)
        self.cwd = Grouping.nonEmpty(session.cwd)
        self.multiplexer = session.multiplexer
        self.pagePath = Grouping.nonEmpty(session.pagePath)
        self.dataPath = Grouping.nonEmpty(session.dataPath)
        self.acknowledgeKey = Self.acknowledgeKey(sessionId: session.sessionId, since: session.since)
        self.sortDate = session.since ?? session.updatedAt
    }

    public static func acknowledgeKey(sessionId: String, since: Date?) -> String {
        let marker = since.map { String(Int($0.timeIntervalSince1970)) } ?? "none"
        return "\(sessionId)+\(marker)"
    }

    public static func sessionId(fromAcknowledgeKey key: String) -> String {
        guard let separator = key.range(of: "+", options: .backwards) else { return key }
        return String(key[..<separator.lowerBound])
    }
}

public struct GroupedSessions: Equatable {
    public struct Counts: Equatable {
        public let attention: Int
        public let working: Int
        public let done: Int

        public init(attention: Int = 0, working: Int = 0, done: Int = 0) {
            self.attention = attention
            self.working = working
            self.done = done
        }
    }

    public static let maxVisibleDone = 5

    public let attention: [DisplayItem]
    public let working: [DisplayItem]
    public let done: [DisplayItem]

    public init(
        attention: [DisplayItem] = [],
        working: [DisplayItem] = [],
        done: [DisplayItem] = []
    ) {
        self.attention = attention
        self.working = working
        self.done = done
    }

    public static let empty = GroupedSessions()

    public var counts: Counts {
        Counts(attention: attention.count, working: working.count, done: done.count)
    }

    public var totalCount: Int {
        attention.count + working.count + done.count
    }

    public var isEmpty: Bool { totalCount == 0 }

    public func items(for group: DisplayGroup) -> [DisplayItem] {
        switch group {
        case .attention: return attention
        case .working: return working
        case .done: return done
        }
    }

    /// 알림에서 세션을 찾을 때 쓰는 전체 목록. 완료 알림도 여기서 항목을 찾는다.
    public var allItems: [DisplayItem] { attention + working + done }

    /// 메뉴와 패널이 실제로 그리는 항목. 완료 그룹만 5개로 자른다.
    public func visibleItems(for group: DisplayGroup) -> [DisplayItem] {
        switch group {
        case .attention: return attention
        case .working: return working
        case .done: return Array(done.prefix(Self.maxVisibleDone))
        }
    }

    public var hiddenDoneCount: Int {
        max(0, done.count - Self.maxVisibleDone)
    }

    public var doneOverflowText: String? {
        hiddenDoneCount > 0 ? L10n.moreHidden(hiddenDoneCount) : nil
    }
}

public enum Grouping {
    /// 서버 응답을 화면 그룹으로 나눈다. 숨김 대상 완료 항목, 12시간이 지난 완료,
    /// 유예 중인 stall 은 여기서 걸러진다.
    public static func group(
        _ response: SessionsResponse?,
        now: Date,
        acknowledgedDone: Set<String> = [],
        snoozedUntil: [String: Date] = [:]
    ) -> GroupedSessions {
        guard let response else { return .empty }

        var attention: [DisplayItem] = []
        var working: [DisplayItem] = []
        var done: [DisplayItem] = []

        for session in response.sessions {
            guard var group = baseGroup(for: session.bucket) else { continue }
            if group == .attention, session.bucket == "stall",
               let until = snoozedUntil[session.sessionId], until > now {
                group = .working
            }
            let item = DisplayItem(session: session, group: group, now: now)
            switch group {
            case .attention:
                attention.append(item)
            case .working:
                working.append(item)
            case .done:
                if !acknowledgedDone.contains(item.acknowledgeKey), isWithinDoneWindow(item, now: now) {
                    done.append(item)
                }
            }
        }

        return GroupedSessions(
            attention: sorted(attention, oldestFirst: true),
            working: sorted(working, oldestFirst: true),
            done: sorted(done, oldestFirst: false)
        )
    }

    static let doneWindow: TimeInterval = 12 * 60 * 60

    static func isWithinDoneWindow(_ item: DisplayItem, now: Date) -> Bool {
        guard let date = item.sortDate else { return false }
        return now.timeIntervalSince(date) <= doneWindow
    }

    static func baseGroup(for bucket: String) -> DisplayGroup? {
        switch bucket {
        case "wait", "idle", "stall": return .attention
        case "working", "untracked": return .working
        case "done", "ended": return .done
        default: return nil
        }
    }

    static func statusText(session: Session, group: DisplayGroup, now: Date) -> String {
        let hasChecklist = session.counts != nil && (session.total ?? 0) > 0
        let stage = clean(session.nowLabel).map { hasChecklist ? "▶ \($0)" : $0 }
        let eta = etaText(session, now: now)

        switch group {
        case .attention:
            let base: String
            switch session.bucket {
            case "wait":
                base = clean(session.message) ?? L10n.grantPermission
            case "idle":
                base = L10n.waitingForReply
            case "stall":
                let duration = TimePhrase.duration(from: session.elapsedReference, to: now)
                if let task = session.backgroundTasks.first,
                   let name = clean(task.taskDescription) ?? clean(task.type),
                   let duration {
                    base = L10n.backgroundTaskFor(duration, name)
                } else if let duration, (session.activity?.backgroundTasks ?? 0) > 0 {
                    base = L10n.backgroundTaskCheckStuck(duration)
                } else if let duration {
                    base = L10n.workingForCheckStuck(duration)
                } else {
                    base = L10n.checkIfStuck
                }
            default:
                base = L10n.needsAttention
            }
            return appended(base, stage, eta)
        case .working:
            let label = clean(session.nowLabel)
            let shown = hasChecklist ? label.map { "▶ \($0)" } : label
            let base: String
            if session.bucket == "untracked" {
                base = shown ?? L10n.inProgress
            } else if let duration = TimePhrase.duration(from: session.elapsedReference, to: now) {
                base = shown.map { "\(L10n.runningFor(duration)) · \($0)" } ?? L10n.runningFor(duration)
            } else {
                base = shown ?? L10n.inProgress
            }
            return appended(base, nil, eta)
        case .done:
            if session.bucket == "ended" {
                let elapsed = TimePhrase.elapsed(from: session.elapsedReference, to: now)
                if elapsed == L10n.justNow { return L10n.justFinished }
                if let elapsed { return L10n.finishedAgo(elapsed) }
                return L10n.finished
            }
            return appended(L10n.finished, stage, eta)
        }
    }

    private static func appended(_ base: String, _ stage: String?, _ eta: String?) -> String {
        [base, stage, eta].compactMap { $0 }.joined(separator: " · ")
    }

    static func etaText(_ session: Session, now: Date) -> String? {
        guard let eta = session.eta else { return nil }
        let minutes = Int(ceil(eta.timeIntervalSince(now) / 60))
        guard minutes > 0 else { return nil }
        return L10n.minutesLeft(minutes)
    }

    static func detailText(session: Session, group: DisplayGroup) -> String? {
        switch group {
        case .attention where session.bucket == "idle":
            return clean(session.replyTail)
        case .done where session.bucket == "ended":
            return clean(session.replyTail)
        default:
            return nil
        }
    }

    static func placeText(_ place: Place?) -> String? {
        guard let place else { return nil }
        switch (clean(place.label), clean(place.branch)) {
        case let (label?, branch?):
            return String("\(label) · \(branch)".prefix(40))
        case let (label?, nil):
            return String(label.prefix(40))
        case let (nil, branch?):
            return String(branch.prefix(40))
        default:
            return nil
        }
    }

    static func clean(_ value: String?) -> String? {
        guard let value else { return nil }
        let collapsed = value.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        guard !collapsed.isEmpty else { return nil }
        return String(collapsed.prefix(160))
    }

    static func nonEmpty(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
    }

    private static func sorted(_ items: [DisplayItem], oldestFirst: Bool) -> [DisplayItem] {
        items.sorted { left, right in
            switch (left.sortDate, right.sortDate) {
            case let (l?, r?):
                if l != r { return oldestFirst ? l < r : l > r }
            case (nil, .some):
                return false
            case (.some, nil):
                return true
            case (nil, nil):
                break
            }
            return left.sessionId < right.sessionId
        }
    }
}
