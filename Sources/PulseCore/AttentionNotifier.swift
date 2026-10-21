import Foundation

public struct AttentionNote: Equatable, Identifiable {
    public let identifier: String
    public let title: String
    public let body: String
    public let sessionId: String
    public let snoozable: Bool

    public var id: String { identifier }

    public init(identifier: String, title: String, body: String, sessionId: String, snoozable: Bool) {
        self.identifier = identifier
        self.title = title
        self.body = body
        self.sessionId = sessionId
        self.snoozable = snoozable
    }
}

/// macOS 알림 권한. 설정 시트가 안내 문구를 고르고, 보내기 직전 판정에 쓴다.
public enum NotificationPermission: Equatable {
    case unknown
    case notDetermined
    case denied
    case authorized

    public var isAuthorized: Bool { self == .authorized }
}

/// 알림을 보내지 않은 까닭. 로그와 selftest 가 같은 값을 본다.
public enum NotificationSuppression: String, Equatable {
    case firstUpdate
    case popoverVisible
    case panelVisible
    case disabled
}

/// 한 갱신에서 고른 알림 후보와, 후보가 있어도 보내지 않은 까닭.
public struct NotificationBatch: Equatable {
    public let notes: [AttentionNote]
    public let candidates: Int
    public let suppression: NotificationSuppression?

    public init(notes: [AttentionNote], candidates: Int, suppression: NotificationSuppression?) {
        self.notes = notes
        self.candidates = candidates
        self.suppression = suppression
    }
}

/// 새로 「확인 필요」에 들어온 세션만 골라 알림 후보로 바꾼다.
/// 본 것으로 기록한 키는 지금 응답에 없으면 지워, 다시 나타난 항목은 새 항목으로 본다.
public struct AttentionNotifier {
    public static let titlePrefix = "확인이 필요해요"

    private var seen: Set<String>

    public init() {
        seen = []
    }

    public mutating func notes(
        for items: [DisplayItem],
        popoverVisible: Bool,
        panelVisible: Bool,
        enabled: Bool,
        isFirstUpdate: Bool
    ) -> [AttentionNote] {
        evaluate(
            for: items,
            popoverVisible: popoverVisible,
            panelVisible: panelVisible,
            enabled: enabled,
            isFirstUpdate: isFirstUpdate
        ).notes
    }

    public mutating func evaluate(
        for items: [DisplayItem],
        popoverVisible: Bool,
        panelVisible: Bool,
        enabled: Bool,
        isFirstUpdate: Bool
    ) -> NotificationBatch {
        let current = Set(items.map(\.acknowledgeKey))
        seen.formIntersection(current)
        defer { seen.formUnion(current) }

        let candidates = items.filter { !seen.contains($0.acknowledgeKey) }
        guard enabled else {
            return NotificationBatch(notes: [], candidates: candidates.count, suppression: .disabled)
        }
        guard !popoverVisible else {
            return NotificationBatch(notes: [], candidates: candidates.count, suppression: .popoverVisible)
        }
        guard !panelVisible else {
            return NotificationBatch(notes: [], candidates: candidates.count, suppression: .panelVisible)
        }
        guard !isFirstUpdate else {
            return NotificationBatch(notes: [], candidates: candidates.count, suppression: .firstUpdate)
        }
        return NotificationBatch(notes: candidates.map { Self.note(for: $0) }, candidates: candidates.count, suppression: nil)
    }

    public static func note(for item: DisplayItem) -> AttentionNote {
        AttentionNote(
            identifier: item.sessionId,
            title: "\(titlePrefix) · \(item.title)",
            body: body(summary: item.summary, status: item.status),
            sessionId: item.sessionId,
            snoozable: PopoverRowAction.resolve(item) == .snooze
        )
    }

    public static func body(summary: String?, status: String) -> String {
        let trimmed = summary?.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = trimmed.flatMap { $0.isEmpty ? nil : $0 } ?? status
        guard text.count > ReplySummary.limit else { return text }
        return text.prefix(ReplySummary.limit - 1).trimmingCharacters(in: .whitespaces) + "…"
    }
}

/// 진행 중(working·stall)이던 세션이 완료로 바뀌면 알린다.
/// 앱이 처음 본 세션이 이미 완료였거나, 처음 읽은 목록·팝오버나 플로팅 패널이 열린 동안·
/// 설정이 꺼진 동안 완료가 된 경우에는 보내지 않고 본 것으로만 기록한다.
public struct DoneNotifier {
    public static let titlePrefix = "끝났어요"

    private var seen: Set<String>
    private var active: Set<String>

    public init() {
        seen = []
        active = []
    }

    public mutating func notes(
        done: [DisplayItem],
        working: [DisplayItem],
        attention: [DisplayItem],
        popoverVisible: Bool,
        panelVisible: Bool,
        enabled: Bool,
        isFirstUpdate: Bool
    ) -> [AttentionNote] {
        evaluate(
            done: done,
            working: working,
            attention: attention,
            popoverVisible: popoverVisible,
            panelVisible: panelVisible,
            enabled: enabled,
            isFirstUpdate: isFirstUpdate
        ).notes
    }

    public mutating func evaluate(
        done: [DisplayItem],
        working: [DisplayItem],
        attention: [DisplayItem],
        popoverVisible: Bool,
        panelVisible: Bool,
        enabled: Bool,
        isFirstUpdate: Bool
    ) -> NotificationBatch {
        let currentDone = Set(done.map(\.acknowledgeKey))
        seen.formIntersection(currentDone)
        let activeNow = Set(
            working.map(\.sessionId) + attention.filter(\.isStall).map(\.sessionId)
        )
        let candidates = done.filter { item in
            active.contains(item.sessionId) && !seen.contains(item.acknowledgeKey)
        }
        seen.formUnion(currentDone)
        active = activeNow

        guard enabled else {
            return NotificationBatch(notes: [], candidates: candidates.count, suppression: .disabled)
        }
        guard !popoverVisible else {
            return NotificationBatch(notes: [], candidates: candidates.count, suppression: .popoverVisible)
        }
        guard !panelVisible else {
            return NotificationBatch(notes: [], candidates: candidates.count, suppression: .panelVisible)
        }
        guard !isFirstUpdate else {
            return NotificationBatch(notes: [], candidates: candidates.count, suppression: .firstUpdate)
        }
        return NotificationBatch(notes: candidates.map { Self.note(for: $0) }, candidates: candidates.count, suppression: nil)
    }

    public static func note(for item: DisplayItem) -> AttentionNote {
        AttentionNote(
            identifier: item.sessionId,
            title: "\(titlePrefix) · \(item.title)",
            body: AttentionNotifier.body(summary: item.summary, status: item.status),
            sessionId: item.sessionId,
            snoozable: false
        )
    }
}
