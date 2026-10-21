import Foundation

/// 알림 종류. 알림 센터에 넣는 `kind` 값과 카테고리를 고르는 데 쓴다.
public enum NotificationKind: String {
    case attention
    case done
}

public enum NotificationButton: String, CaseIterable {
    case openInOrca = "OPEN_IN_ORCA"
    case snooze = "SNOOZE_10M"
    case acknowledge = "ACKNOWLEDGE"

    public var title: String {
        switch self {
        case .openInOrca: return "Orca 에서 열기"
        case .snooze: return "10분 더"
        case .acknowledge: return "확인"
        }
    }

    public var bringsAppForward: Bool { self == .openInOrca }
}

/// 알림 한 장의 카테고리·버튼·소리·긴급도.
public struct NotificationStyle: Equatable {
    public enum Interruption: Equatable {
        case active
        case passive
    }

    public let categoryIdentifier: String
    public let buttons: [NotificationButton]
    public let interruption: Interruption
    public let playsSound: Bool

    /// 「10분 더」는 stall 의 「더 기다리기」와 같은 동작이라 `AppModel.snooze` 가 효과를 내는
    /// stall 막힘에만 단다. 질문·권한 대기처럼 stall 이 아닌 막힘에 달면 무동작 버튼이 된다.
    public static func of(kind: NotificationKind, snoozable: Bool) -> NotificationStyle {
        switch kind {
        case .attention:
            return snoozable
                ? NotificationStyle(
                    categoryIdentifier: "ATTENTION",
                    buttons: [.openInOrca, .snooze],
                    interruption: .active,
                    playsSound: true
                )
                : NotificationStyle(
                    categoryIdentifier: "ATTENTION_OPEN",
                    buttons: [.openInOrca],
                    interruption: .active,
                    playsSound: true
                )
        case .done:
            return NotificationStyle(
                categoryIdentifier: "DONE",
                buttons: [.acknowledge],
                interruption: .passive,
                playsSound: false
            )
        }
    }

    public static let allCategories: [NotificationStyle] = [
        of(kind: .attention, snoozable: true),
        of(kind: .attention, snoozable: false),
        of(kind: .done, snoozable: false),
    ]
}
