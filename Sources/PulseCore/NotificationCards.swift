import Foundation

public enum CardKind: String, Equatable {
    case attention
    case done
    /// 자리 비움 동안 모은 사건을 한 장으로 묶은 카드.
    case away
}

public struct NotificationCard: Equatable, Identifiable {
    public let sessionId: String
    public let kind: CardKind
    public var arrivedAt: Date
    /// 수명이 있는 카드가 사라질 시각. 멈춘 동안에는 nil 이고 남은 시간은 `pausedRemaining` 에 있다.
    public var expiresAt: Date?
    public var pausedRemaining: TimeInterval?
    /// 끝남 카드: 그 턴이 걸린 시간(초). 모르면 nil.
    public let runDuration: TimeInterval?
    /// 자리 비움 요약 카드가 모은 확인 필요·끝남 세션. 요약 카드가 아니면 빈 집합.
    public private(set) var awayAttentionIds: Set<String>
    public private(set) var awayDoneIds: Set<String>

    public var id: String { sessionId }

    /// 요약 카드가 모은 확인 필요·끝남 수.
    public var awayAttention: Int { awayAttentionIds.count }
    public var awayDone: Int { awayDoneIds.count }

    /// 끝남 카드와, 막힘이 없이 끝남만 모은 요약 카드는 8초 수명을 갖는다.
    public var expires: Bool { kind == .done || (kind == .away && awayAttention == 0) }

    /// 이번에 모은 개별 카드를 요약 멤버로 더한다. 같은 세션은 이번에 모은 쪽 종류를 따른다.
    mutating func absorbAway(_ other: NotificationCard) {
        switch other.kind {
        case .attention:
            awayDoneIds.remove(other.sessionId)
            awayAttentionIds.insert(other.sessionId)
        case .done:
            awayAttentionIds.remove(other.sessionId)
            awayDoneIds.insert(other.sessionId)
        case .away:
            awayAttentionIds.formUnion(other.awayAttentionIds)
            awayDoneIds.formUnion(other.awayDoneIds)
        }
    }

    /// 지금 목록에 없는 세션을 요약 멤버에서 뺀다.
    mutating func pruneAwayMembers(attentionIds: Set<String>, doneIds: Set<String>) {
        awayAttentionIds.formIntersection(attentionIds)
        awayDoneIds.formIntersection(doneIds)
    }

    mutating func removeAwayMembers(kind: CardKind) {
        switch kind {
        case .attention: awayAttentionIds.removeAll()
        case .done: awayDoneIds.removeAll()
        case .away:
            awayAttentionIds.removeAll()
            awayDoneIds.removeAll()
        }
    }
}

/// 떠 있는 알림 카드의 순서·수명·일시 정지를 들고 있는 값 타입.
public struct CardDeck: Equatable {
    public static let doneLifetime: TimeInterval = 8
    public static let awayCardId = "pulse.away"

    /// 저장 순서는 자유, 화면 순서는 `ordered`.
    public private(set) var cards: [NotificationCard]
    public private(set) var paused: Bool
    public private(set) var awaySince: Date?
    /// 자리 비움 동안 모은 개별 카드. 화면에는 나오지 않고 복귀할 때 한 장으로 바뀐다.
    private var awayCards: [NotificationCard]
    private var runStarts: [String: Date]

    public var isAway: Bool { awaySince != nil }

    public init() {
        cards = []
        awayCards = []
        paused = false
        awaySince = nil
        runStarts = [:]
    }

    /// 갱신마다 부른다. 순서: (1) 새 알림 후보를 카드로 넣고 (2) 지금 목록에 맞춰 카드를 거두고 (3) 턴 시작 시각을 갱신한다.
    /// 돌려주는 값은 이번 호출에서 `cards` 에 넣은 막힘 카드 수다. 자리 비움 동안에는 0 이라 소리가 나지 않는다.
    @discardableResult
    public mutating func update(
        newAttention: [DisplayItem],
        newDone: [DisplayItem],
        groups: GroupedSessions,
        now: Date
    ) -> Int {
        // (1) 이 (3) 보다 먼저라 막 끝난 세션도 직전 갱신의 시작 시각으로 걸린 시간을 잰다.
        var insertedAttention = 0
        for item in newAttention {
            let card = NotificationCard(
                sessionId: item.sessionId,
                kind: .attention,
                arrivedAt: now,
                expiresAt: nil,
                pausedRemaining: nil,
                runDuration: nil,
                awayAttentionIds: [],
                awayDoneIds: []
            )
            if isAway {
                Self.insert(card, into: &awayCards)
            } else {
                Self.insert(card, into: &cards)
                insertedAttention += 1
            }
        }
        for item in newDone {
            let card = NotificationCard(
                sessionId: item.sessionId,
                kind: .done,
                arrivedAt: now,
                expiresAt: paused ? nil : now.addingTimeInterval(Self.doneLifetime),
                pausedRemaining: paused ? Self.doneLifetime : nil,
                runDuration: runDuration(for: item),
                awayAttentionIds: [],
                awayDoneIds: []
            )
            if isAway {
                Self.insert(card, into: &awayCards)
            } else {
                Self.insert(card, into: &cards)
            }
        }

        let attentionIds = Set(groups.attention.map(\.sessionId))
        let doneIds = Set(groups.done.map(\.sessionId))
        Self.retire(matching: attentionIds, doneIds: doneIds, now: now, paused: paused, from: &cards)
        // 자리 비움 동안 막혔다가 그대로 끝난 세션은 끝남 하나로 센다.
        Self.retire(matching: attentionIds, doneIds: doneIds, now: now, paused: paused, from: &awayCards)

        var running: [String: Date] = [:]
        for item in groups.working + groups.attention {
            running[item.sessionId] = runStarts[item.sessionId] ?? item.sortDate ?? now
        }
        runStarts = running
        endPauseIfEmpty()
        return insertedAttention
    }

    /// 자리 비움을 시작한다. 이미 자리 비움이면 처음 시각과 모은 것을 지킨다.
    public mutating func beginAway(now: Date) {
        guard awaySince == nil else { return }
        awaySince = now
    }

    /// 자리 비움을 끝내고 모은 사건을 한 장으로 낸다.
    @discardableResult
    public mutating func endAway(now: Date) -> AwayReturn {
        guard isAway else { return .none }
        awaySince = nil
        let collected = awayCards
        awayCards = []
        guard !collected.isEmpty else { return .none }

        if let index = cards.firstIndex(where: { $0.kind == .away }) {
            var card = cards[index]
            for item in collected { card.absorbAway(item) }
            card.arrivedAt = now
            if card.awayAttention > 0 {
                card.expiresAt = nil
                card.pausedRemaining = nil
            } else {
                Self.startDoneLifetime(of: &card, now: now, paused: paused)
            }
            cards[index] = card
            return .summary(attention: card.awayAttention, done: card.awayDone)
        }

        if collected.count == 1, let kept = collected.first {
            Self.insert(NotificationCard(
                sessionId: kept.sessionId,
                kind: kept.kind,
                arrivedAt: now,
                expiresAt: kept.kind == .done && !paused ? now.addingTimeInterval(Self.doneLifetime) : nil,
                pausedRemaining: kept.kind == .done && paused ? Self.doneLifetime : nil,
                runDuration: kept.runDuration,
                awayAttentionIds: [],
                awayDoneIds: []
            ), into: &cards)
            return .single(kept.kind)
        }

        let attentionIds = Set(collected.filter { $0.kind == .attention }.map(\.sessionId))
        let doneIds = Set(collected.filter { $0.kind == .done }.map(\.sessionId))
        Self.insert(NotificationCard(
            sessionId: Self.awayCardId,
            kind: .away,
            arrivedAt: now,
            expiresAt: attentionIds.isEmpty && !paused ? now.addingTimeInterval(Self.doneLifetime) : nil,
            pausedRemaining: attentionIds.isEmpty && paused ? Self.doneLifetime : nil,
            runDuration: nil,
            awayAttentionIds: attentionIds,
            awayDoneIds: doneIds
        ), into: &cards)
        return .summary(attention: attentionIds.count, done: doneIds.count)
    }

    public mutating func dismiss(_ sessionId: String) {
        cards.removeAll { $0.sessionId == sessionId }
        endPauseIfEmpty()
    }

    public mutating func dismissAll() {
        cards.removeAll()
        endPauseIfEmpty()
    }

    public mutating func dismiss(kind: CardKind, now: Date = Date()) {
        cards.removeAll { $0.kind == kind }
        awayCards.removeAll { $0.kind == kind }
        var kept: [NotificationCard] = []
        for var card in cards {
            guard card.kind == .away else {
                kept.append(card)
                continue
            }
            let hadAttention = card.awayAttention > 0
            card.removeAwayMembers(kind: kind)
            if card.awayAttention == 0 && card.awayDone == 0 { continue }
            if hadAttention && card.awayAttention == 0 {
                Self.startDoneLifetime(of: &card, now: now, paused: paused)
            }
            kept.append(card)
        }
        cards = kept
        endPauseIfEmpty()
    }

    /// 패널 위에 마우스가 있는 동안 수명이 있는 카드의 시간을 멈춘다.
    public mutating func setPaused(_ value: Bool, now: Date) {
        guard paused != value else { return }
        paused = value
        for index in cards.indices where cards[index].expires {
            if value {
                if let expiresAt = cards[index].expiresAt {
                    cards[index].pausedRemaining = max(0, expiresAt.timeIntervalSince(now))
                }
                cards[index].expiresAt = nil
            } else if let remaining = cards[index].pausedRemaining {
                cards[index].expiresAt = now.addingTimeInterval(remaining)
                cards[index].pausedRemaining = nil
            }
        }
    }

    /// 만료된 수명 카드를 거둔다. 거둔 것이 있으면 true.
    @discardableResult
    public mutating func expire(now: Date) -> Bool {
        let before = cards.count
        cards.removeAll { card in
            guard card.expires, let expiresAt = card.expiresAt else { return false }
            return expiresAt <= now
        }
        endPauseIfEmpty()
        return cards.count != before
    }

    /// 자리 비움 요약이 맨 위, 그다음 확인 필요, 그다음 끝남. 같은 종류 안에서는 늦게 온 것이 위.
    public var ordered: [NotificationCard] {
        cards.sorted { left, right in
            if left.kind != right.kind { return Self.rank(left.kind) < Self.rank(right.kind) }
            if left.arrivedAt != right.arrivedAt { return left.arrivedAt > right.arrivedAt }
            return left.sessionId < right.sessionId
        }
    }

    /// 다음에 만료될 시각(멈춘 동안 nil).
    public var nextDeadline: Date? {
        cards.filter(\.expires).compactMap(\.expiresAt).min()
    }

    /// 수명이 있는 카드의 남은 비율 0...1. 확인 필요 카드는 1.
    public static func remainingFraction(of card: NotificationCard, paused: Bool, now: Date) -> Double {
        guard card.expires else { return 1 }
        let remaining: TimeInterval
        if paused {
            remaining = card.pausedRemaining ?? doneLifetime
        } else {
            remaining = max(0, (card.expiresAt ?? now).timeIntervalSince(now))
        }
        return min(1, max(0, remaining / doneLifetime))
    }

    /// 카드가 둘 이상일 때의 머리글 「확인 N · 끝남 M」. 0 인 쪽은 뺀다. 하나 이하면 nil.
    public static func headerText(attention: Int, done: Int) -> String? {
        guard attention + done > 1 else { return nil }
        var parts: [String] = []
        if attention > 0 { parts.append(L10n.cardHeaderAttention(attention)) }
        if done > 0 { parts.append(L10n.cardHeaderDone(done)) }
        return parts.joined(separator: " · ")
    }

    /// 패널이 숨으면 mouseExited 가 오지 않아 멈춤이 남는다. 카드가 없으면 풀어 둔다.
    private mutating func endPauseIfEmpty() {
        guard cards.isEmpty else { return }
        paused = false
    }

    private static func insert(_ card: NotificationCard, into list: inout [NotificationCard]) {
        if let index = list.firstIndex(where: { $0.sessionId == card.sessionId }) {
            list[index] = card
        } else {
            list.append(card)
        }
    }

    /// 지금 목록에 없는 세션의 카드를 거둔다. 요약 카드는 멤버만 덜어 내고,
    /// 막힘을 다 잃고 끝남이 남으면 그때부터 끝남 수명을 이어받는다.
    private static func retire(
        matching attentionIds: Set<String>,
        doneIds: Set<String>,
        now: Date,
        paused: Bool,
        from list: inout [NotificationCard]
    ) {
        var kept: [NotificationCard] = []
        kept.reserveCapacity(list.count)
        for var card in list {
            switch card.kind {
            case .attention:
                if attentionIds.contains(card.sessionId) { kept.append(card) }
            case .done:
                if doneIds.contains(card.sessionId) { kept.append(card) }
            case .away:
                let hadAttention = card.awayAttention > 0
                card.pruneAwayMembers(attentionIds: attentionIds, doneIds: doneIds)
                if card.awayAttention == 0 && card.awayDone == 0 { continue }
                if hadAttention && card.awayAttention == 0 {
                    startDoneLifetime(of: &card, now: now, paused: paused)
                }
                kept.append(card)
            }
        }
        list = kept
    }

    private static func startDoneLifetime(of card: inout NotificationCard, now: Date, paused: Bool) {
        if paused {
            card.expiresAt = nil
            card.pausedRemaining = doneLifetime
        } else {
            card.expiresAt = now.addingTimeInterval(doneLifetime)
            card.pausedRemaining = nil
        }
    }

    private static func rank(_ kind: CardKind) -> Int {
        switch kind {
        case .away: return 0
        case .attention: return 1
        case .done: return 2
        }
    }

    private func runDuration(for item: DisplayItem) -> TimeInterval? {
        guard let start = runStarts[item.sessionId], let end = item.sortDate else { return nil }
        return max(0, end.timeIntervalSince(start))
    }
}

/// `CardDeck.endAway` 가 복귀 때 낸 결과. 로그에 쓴다.
public enum AwayReturn: Equatable {
    case none
    case single(CardKind)
    case summary(attention: Int, done: Int)
}

/// 화면 잠김 신호와 폴링이 본 잠김 값으로 덱에 할 일을 고른다. 읽기 실패(nil)면 상태를 바꾸지 않는다.
public enum ScreenLockTransition: Equatable {
    case begin
    case end
    case none

    public static func decide(locked: Bool?, isAway: Bool) -> ScreenLockTransition {
        guard let locked else { return .none }
        if locked && !isAway { return .begin }
        if !locked && isAway { return .end }
        return .none
    }
}

/// 시스템 알림을 언제 보조로 보낼지.
public enum SystemNotificationPolicy: String, Equatable {
    /// 카드와 함께 시스템 알림도 보낸다.
    case always
    /// 카드만.
    case never
}

public struct NotificationRoute: Equatable {
    public let cards: Bool
    public let system: Bool

    public static func decide(policy: SystemNotificationPolicy) -> NotificationRoute {
        switch policy {
        case .always:
            return NotificationRoute(cards: true, system: true)
        case .never:
            return NotificationRoute(cards: true, system: false)
        }
    }
}

/// 카드에 그리는 문구. 뷰는 여기서 고른 문자열만 그린다.
public enum CardText {
    /// 끝남 카드 머리 오른쪽: 걸린 시간이 있으면 「14분 걸림」, 없으면 완료 시각 기준 「11분 전」.
    public static func doneTrail(runDuration: TimeInterval?, finishedAt: Date?, now: Date) -> String? {
        if let runDuration { return L10n.took(duration(runDuration)) }
        return TimePhrase.relative(from: finishedAt, to: now)
    }

    /// 끝남 카드 2행: 「{세션} · 끝남 · 1분 걸림」. 걸린 시간을 모르면 「{세션} · 끝남」.
    public static func doneMeta(title: String, runDuration: TimeInterval?) -> String {
        guard let runDuration else { return L10n.doneMeta(title) }
        return L10n.doneMeta(title, took: duration(runDuration))
    }

    /// 끝남 카드 본문: 요약 한 줄, 없으면 상태 문구.
    public static func doneSummary(summary: String?, status: String) -> String {
        guard let trimmed = summary?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return status }
        return trimmed
    }

    public static var awayTitle: String { L10n.awayTitle }

    /// 자리 비움 카드 1행. 막힌 세션이 있으면 그것을 먼저 센다.
    public static func awayHeadline(attention: Int, done: Int) -> String {
        attention > 0 ? L10n.awaySessionsWaiting(attention) : L10n.awaySessionsFinished(done)
    }

    /// 자리 비움 카드 2행 본문. 막힘과 끝남이 함께 있으면 끝남 수도 센다.
    public static func awayDetail(attention: Int, done: Int) -> String {
        attention > 0 && done > 0 ? L10n.awayFinishedAndOpen(done) : L10n.awayOpenList
    }

    /// 자리 비움 카드 2행: 「자리 비운 사이 · 3개 끝났어요 · 누르면 목록이 열려요」.
    public static func awayMeta(attention: Int, done: Int) -> String {
        "\(awayTitle) · \(awayDetail(attention: attention, done: done))"
    }

    /// `TimePhrase.duration` 과 같은 규칙으로 초를 문구로 바꾼다. 1분 미만도 1분으로 본다.
    private static func duration(_ seconds: TimeInterval) -> String {
        let seconds = max(0, seconds)
        if seconds < 3600 { return L10n.minutes(max(1, Int(seconds / 60))) }
        return L10n.hours(Int(seconds / 3600))
    }
}
