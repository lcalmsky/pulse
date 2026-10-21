import Foundation

public enum DisplayGroup: Int, CaseIterable, Equatable {
    case attention
    case working
    case done

    public var title: String {
        switch self {
        case .attention: return "확인 필요"
        case .working: return "진행중"
        case .done: return "완료"
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
    /// 30분 넘게 갱신되지 않은 체크리스트. 진행률을 흐리게 그린다.
    public let progressStale: Bool
    public let blocked: Bool
    public let replyTail: String?
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
    public let pagePath: String?
    public let acknowledgeKey: String
    public let sortDate: Date?

    public var id: String { sessionId }

    /// 화면에 그리는 행의 식별자. 그룹이 바뀌면 다른 행으로 취급해
    /// 목록 뷰가 섹션을 건너 같은 뷰를 재사용하지 않게 한다.
    public var rowID: String { "\(group.rawValue)+\(sessionId)" }

    public var clickAction: SessionClickAction {
        SessionClick.resolve(page: pagePath, orcaTerminal: orcaTerminal, cwd: cwd)
    }

    public var isActionable: Bool { clickAction != .none }

    /// 지금 하는 일 한 줄을 그리는 행. 확인 필요 섹션에 있는 stall 도 진행 중으로 다룬다.
    public var isRunning: Bool { group == .working || isStall }

    /// 제목과 같은 이름의 태그는 카드에 같은 글자를 두 번 보이므로 그리지 않는다.
    public var keyTag: String? {
        guard let key else { return nil }
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return key.caseInsensitiveCompare(trimmedTitle) == .orderedSame ? nil : key
    }

    public init(session: Session, group: DisplayGroup, now: Date) {
        self.sessionId = session.sessionId
        self.title = Grouping.clean(session.title).map { String($0.prefix(60)) } ?? "제목 없는 세션"
        self.status = Grouping.statusText(session: session, group: group, now: now)
        self.detail = Grouping.detailText(session: session, group: group)
        self.placeText = Grouping.placeText(session.place)
        self.key = Grouping.nonEmpty(session.key)
        if let counts = session.counts, let total = session.total, total > 0 {
            self.progress = ChecklistProgress(done: max(0, counts.done), total: total)
        } else {
            self.progress = nil
        }
        self.progressStale = session.dataAt.map { now.timeIntervalSince($0) > DeadhdState.staleInterval } ?? false
        self.blocked = (session.counts?.blocked ?? 0) > 0
        self.replyTail = Grouping.clean(session.replyTail)
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
            reply: self.replyTail,
            statusLine: self.status
        )
        self.group = group
        self.isStall = session.bucket == "stall"
        self.orcaTerminal = Grouping.nonEmpty(session.orcaTerminal)
        self.cwd = Grouping.nonEmpty(session.cwd)
        self.pagePath = Grouping.nonEmpty(session.pagePath)
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
        hiddenDoneCount > 0 ? "그 밖에 \(hiddenDoneCount)개" : nil
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
                base = clean(session.message) ?? "권한을 허락해 주세요"
            case "idle":
                base = "답을 기다리고 있어요"
            case "stall":
                let duration = TimePhrase.duration(from: session.elapsedReference, to: now)
                if let task = session.backgroundTasks.first,
                   let name = clean(task.taskDescription) ?? clean(task.type),
                   let duration {
                    base = "백그라운드 작업 \(duration)째 · \(name)"
                } else if let duration {
                    base = "작업 \(duration)째 · 멈췄는지 확인해 보세요"
                } else {
                    base = "멈췄는지 확인해 보세요"
                }
            default:
                base = "확인이 필요해요"
            }
            return appended(base, stage, eta)
        case .working:
            let label = clean(session.nowLabel)
            let shown = hasChecklist ? label.map { "▶ \($0)" } : label
            let base: String
            if session.bucket == "untracked" {
                base = shown ?? "진행 중이에요"
            } else if let duration = TimePhrase.duration(from: session.elapsedReference, to: now) {
                base = shown.map { "\(duration)째 · \($0)" } ?? "\(duration)째"
            } else {
                base = shown ?? "진행 중이에요"
            }
            return appended(base, nil, eta)
        case .done:
            if session.bucket == "ended" {
                let elapsed = TimePhrase.elapsed(from: session.elapsedReference, to: now)
                if elapsed == "방금" { return "방금 끝났어요" }
                if let elapsed { return "\(elapsed) 전 끝남" }
                return "끝났어요"
            }
            return appended("끝났어요", stage, eta)
        }
    }

    private static func appended(_ base: String, _ stage: String?, _ eta: String?) -> String {
        [base, stage, eta].compactMap { $0 }.joined(separator: " · ")
    }

    private static func etaText(_ session: Session, now: Date) -> String? {
        guard let eta = session.eta else { return nil }
        let minutes = Int(ceil(eta.timeIntervalSince(now) / 60))
        guard minutes > 0 else { return nil }
        return "약 \(minutes)분 남음"
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
