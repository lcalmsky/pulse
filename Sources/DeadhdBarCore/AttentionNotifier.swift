import Foundation

public struct AttentionNote: Equatable, Identifiable {
    public let identifier: String
    public let title: String
    public let body: String
    public let sessionId: String

    public var id: String { identifier }

    public init(identifier: String, title: String, body: String, sessionId: String) {
        self.identifier = identifier
        self.title = title
        self.body = body
        self.sessionId = sessionId
    }
}

/// 새로 「확인 필요」에 들어온 세션만 골라 알림 후보로 바꾼다.
/// 본 것으로 기록한 키는 지금 응답에 없으면 지워, 다시 나타난 항목은 새 항목으로 본다.
public struct AttentionNotifier {
    public static let titlePrefix = "확인이 필요해요"
    public static let bodyLimit = 200

    private var seen: Set<String>

    public init() {
        seen = []
    }

    public mutating func notes(
        for items: [DisplayItem],
        popoverVisible: Bool,
        enabled: Bool,
        isFirstUpdate: Bool
    ) -> [AttentionNote] {
        let current = Set(items.map(\.acknowledgeKey))
        seen.formIntersection(current)
        defer { seen.formUnion(current) }

        guard enabled, !popoverVisible, !isFirstUpdate else { return [] }
        return items
            .filter { !seen.contains($0.acknowledgeKey) }
            .map { Self.note(for: $0) }
    }

    public static func note(for item: DisplayItem) -> AttentionNote {
        AttentionNote(
            identifier: item.acknowledgeKey,
            title: "\(titlePrefix) · \(item.title)",
            body: body(replyTail: item.replyTail, status: item.status),
            sessionId: item.sessionId
        )
    }

    public static func body(replyTail: String?, status: String) -> String {
        let reply = replyTail
            .map { PlainText.markdown($0) }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let text = reply.flatMap { $0.isEmpty ? nil : $0 } ?? status
        return String(text.prefix(bodyLimit))
    }
}
