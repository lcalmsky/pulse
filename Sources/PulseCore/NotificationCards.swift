import Foundation

public enum CardKind: String, Equatable {
    case attention
    case done
}

public struct NotificationCard: Equatable, Identifiable {
    public let sessionId: String
    public let kind: CardKind
    public let arrivedAt: Date
    /// 끝남 카드가 사라질 시각. 멈춘 동안에는 nil 이고 남은 시간은 `pausedRemaining` 에 있다.
    public var expiresAt: Date?
    public var pausedRemaining: TimeInterval?
    /// 끝남 카드: 그 턴이 걸린 시간(초). 모르면 nil.
    public let runDuration: TimeInterval?

    public var id: String { sessionId }
}

/// 떠 있는 알림 카드의 순서·수명·일시 정지를 들고 있는 값 타입.
public struct CardDeck: Equatable {
    public static let doneLifetime: TimeInterval = 8

    /// 저장 순서는 자유, 화면 순서는 `ordered`.
    public private(set) var cards: [NotificationCard]
    public private(set) var paused: Bool
    private var runStarts: [String: Date]

    public init() {
        cards = []
        paused = false
        runStarts = [:]
    }

    /// 갱신마다 부른다. 순서: (1) 새 알림 후보를 카드로 넣고 (2) 지금 목록에 맞춰 카드를 거두고 (3) 턴 시작 시각을 갱신한다.
    public mutating func update(
        newAttention: [DisplayItem],
        newDone: [DisplayItem],
        groups: GroupedSessions,
        now: Date
    ) {
        // (1) 이 (3) 보다 먼저라 막 끝난 세션도 직전 갱신의 시작 시각으로 걸린 시간을 잰다.
        for item in newAttention {
            insert(NotificationCard(
                sessionId: item.sessionId,
                kind: .attention,
                arrivedAt: now,
                expiresAt: nil,
                pausedRemaining: nil,
                runDuration: nil
            ))
        }
        for item in newDone {
            insert(NotificationCard(
                sessionId: item.sessionId,
                kind: .done,
                arrivedAt: now,
                expiresAt: paused ? nil : now.addingTimeInterval(Self.doneLifetime),
                pausedRemaining: paused ? Self.doneLifetime : nil,
                runDuration: runDuration(for: item)
            ))
        }

        let attentionIds = Set(groups.attention.map(\.sessionId))
        let doneIds = Set(groups.done.map(\.sessionId))
        cards.removeAll { card in
            switch card.kind {
            case .attention: return !attentionIds.contains(card.sessionId)
            case .done: return !doneIds.contains(card.sessionId)
            }
        }

        var running: [String: Date] = [:]
        for item in groups.working + groups.attention {
            running[item.sessionId] = runStarts[item.sessionId] ?? item.sortDate ?? now
        }
        runStarts = running
        endPauseIfEmpty()
    }

    public mutating func dismiss(_ sessionId: String) {
        cards.removeAll { $0.sessionId == sessionId }
        endPauseIfEmpty()
    }

    public mutating func dismissAll() {
        cards.removeAll()
        endPauseIfEmpty()
    }

    /// 패널 위에 마우스가 있는 동안 끝남 카드의 시간을 멈춘다.
    public mutating func setPaused(_ value: Bool, now: Date) {
        guard paused != value else { return }
        paused = value
        for index in cards.indices where cards[index].kind == .done {
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

    /// 만료된 끝남 카드를 거둔다. 거둔 것이 있으면 true.
    @discardableResult
    public mutating func expire(now: Date) -> Bool {
        let before = cards.count
        cards.removeAll { card in
            guard card.kind == .done, let expiresAt = card.expiresAt else { return false }
            return expiresAt <= now
        }
        endPauseIfEmpty()
        return cards.count != before
    }

    /// 확인 필요가 항상 위, 같은 종류 안에서는 늦게 온 것이 위.
    public var ordered: [NotificationCard] {
        cards.sorted { left, right in
            if left.kind != right.kind { return left.kind == .attention }
            if left.arrivedAt != right.arrivedAt { return left.arrivedAt > right.arrivedAt }
            return left.sessionId < right.sessionId
        }
    }

    /// 다음에 만료될 시각(멈춘 동안 nil).
    public var nextDeadline: Date? {
        cards.filter { $0.kind == .done }.compactMap(\.expiresAt).min()
    }

    /// 끝남 카드의 남은 비율 0...1. 확인 필요 카드는 1.
    public static func remainingFraction(of card: NotificationCard, paused: Bool, now: Date) -> Double {
        guard card.kind == .done else { return 1 }
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
        if attention > 0 { parts.append("확인 \(attention)") }
        if done > 0 { parts.append("끝남 \(done)") }
        return parts.joined(separator: " · ")
    }

    /// 패널이 숨으면 mouseExited 가 오지 않아 멈춤이 남는다. 카드가 없으면 풀어 둔다.
    private mutating func endPauseIfEmpty() {
        guard cards.isEmpty else { return }
        paused = false
    }

    private mutating func insert(_ card: NotificationCard) {
        if let index = cards.firstIndex(where: { $0.sessionId == card.sessionId }) {
            cards[index] = card
        } else {
            cards.append(card)
        }
    }

    private func runDuration(for item: DisplayItem) -> TimeInterval? {
        guard let start = runStarts[item.sessionId], let end = item.sortDate else { return nil }
        return max(0, end.timeIntervalSince(start))
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
        if let runDuration { return "\(duration(runDuration)) 걸림" }
        return TimePhrase.relative(from: finishedAt, to: now)
    }

    /// 끝남 카드 한 장일 때의 상태 문구.
    public static func doneBanner(runDuration: TimeInterval?) -> String {
        guard let runDuration else { return "끝났어요" }
        return "끝났어요 · \(duration(runDuration)) 걸림"
    }

    /// 끝남 카드 본문: 요약 한 줄, 없으면 상태 문구.
    public static func doneSummary(summary: String?, status: String) -> String {
        guard let trimmed = summary?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return status }
        return trimmed
    }

    /// 확인 필요 카드 바닥줄: 「워크트리 · N분째」. 둘 중 있는 것만 잇는다.
    public static func attentionMeta(place: String?, since: Date?, now: Date) -> String? {
        var parts: [String] = []
        if let place = place?.trimmingCharacters(in: .whitespacesAndNewlines), !place.isEmpty {
            parts.append(place)
        }
        if let duration = TimePhrase.duration(from: since, to: now) {
            parts.append("\(duration)째")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// `TimePhrase.duration` 과 같은 규칙으로 초를 문구로 바꾼다. 1분 미만도 1분으로 본다.
    private static func duration(_ seconds: TimeInterval) -> String {
        let seconds = max(0, seconds)
        if seconds < 3600 { return "\(max(1, Int(seconds / 60)))분" }
        return "\(Int(seconds / 3600))시간"
    }
}
