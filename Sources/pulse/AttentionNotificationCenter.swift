import Foundation
import OSLog
import PulseCore
import UserNotifications

/// UserNotifications 연동. 번들 식별자가 없으면 디버그 실행 파일이므로 아무것도 하지 않는다.
/// `UNUserNotificationCenter.current()` 자체가 번들 없는 프로세스에서 예외를 던지기 때문이다.
final class AttentionNotificationCenter: NSObject, UNUserNotificationCenterDelegate {
    typealias Kind = NotificationKind

    private static let sessionIdKey = "sessionId"
    private static let kindKey = "kind"

    private static let logger = Logger(subsystem: "io.github.lcalmsky.pulse", category: "notify")

    private weak var model: AppModel?
    private var authorizationRequested = false

    private var center: UNUserNotificationCenter? {
        guard Bundle.main.bundleIdentifier != nil else { return nil }
        return UNUserNotificationCenter.current()
    }

    init(model: AppModel) {
        self.model = model
        super.init()

        guard let center = center else { return }
        center.delegate = self
        center.setNotificationCategories(Set(NotificationStyle.allCategories.map { style in
            UNNotificationCategory(
                identifier: style.categoryIdentifier,
                actions: style.buttons.map { button in
                    UNNotificationAction(
                        identifier: button.rawValue,
                        title: button.title,
                        options: button.bringsAppForward ? [.foreground] : []
                    )
                },
                intentIdentifiers: [],
                options: []
            )
        }))
    }

    /// 시작할 때 현재 권한 상태를 읽어 로그와 설정 시트에 남긴다. 요청은 하지 않는다.
    func logStartupState() {
        guard let center = center else {
            Self.logger.notice("알림 센터를 쓸 수 없어요 · 번들 식별자 없음")
            return
        }
        center.getNotificationSettings { settings in
            Self.log(settings, context: "시작")
            Self.publish(settings, to: self)
        }
    }

    /// 설정 시트를 열 때처럼 현재 권한을 다시 읽을 때 쓴다.
    func refreshPermission() {
        logStartupState()
    }

    /// 권한을 묻는다. `force` 는 사용자가 설정에서 「허용하기」를 다시 누른 경우다.
    func requestAuthorization(force: Bool = false) {
        guard let center = center else { return }
        guard force || !authorizationRequested else { return }
        authorizationRequested = true
        center.getNotificationSettings { settings in
            Self.log(settings, context: "요청 전")
            Self.publish(settings, to: self)
            guard settings.authorizationStatus == .notDetermined else { return }
            center.requestAuthorization(options: [.alert, .sound]) { granted, error in
                if let error {
                    Self.logger.error("알림 권한 요청 실패: \(error.localizedDescription, privacy: .public)")
                }
                Self.logger.notice("알림 권한 요청 결과 granted=\(granted, privacy: .public)")
                center.getNotificationSettings { settings in
                    Self.log(settings, context: "요청 뒤")
                    Self.publish(settings, to: self)
                }
            }
        }
    }

    func requestAuthorizationIfNeeded() {
        requestAuthorization()
    }

    /// 보내기 직전에 현재 권한을 다시 읽는다. 사용자가 시스템 설정에서 나중에 허용해도
    /// 앱을 다시 켜지 않고 동작하게 하기 위해서다.
    func post(_ notes: [AttentionNote], kind: Kind) {
        guard let center = center, !notes.isEmpty else { return }
        center.getNotificationSettings { settings in
            Self.publish(settings, to: self)
            guard Self.permission(settings).isAuthorized else {
                Self.logger.notice(
                    "알림 \(notes.count)건을 보내지 못했어요 · 권한 상태=\(settings.authorizationStatus.rawValue, privacy: .public) kind=\(kind.rawValue, privacy: .public)"
                )
                return
            }
            for note in notes {
                let style = NotificationStyle.of(kind: kind, snoozable: note.snoozable)
                let content = UNMutableNotificationContent()
                content.title = note.title
                content.body = note.body
                content.sound = style.playsSound ? .default : nil
                content.categoryIdentifier = style.categoryIdentifier
                content.threadIdentifier = note.sessionId
                content.interruptionLevel = style.interruption == .active ? .active : .passive
                content.userInfo = [
                    Self.sessionIdKey: note.sessionId,
                    Self.kindKey: kind.rawValue,
                ]
                center.add(UNNotificationRequest(identifier: note.identifier, content: content, trigger: nil)) { error in
                    if let error {
                        Self.logger.error(
                            "알림 전송 실패 \(note.identifier, privacy: .public): \(error.localizedDescription, privacy: .public)"
                        )
                    } else {
                        let level = style.interruption == .active ? "active" : "passive"
                        Self.logger.notice(
                            "알림 전송 \(note.identifier, privacy: .public) kind=\(kind.rawValue, privacy: .public) level=\(level, privacy: .public)"
                        )
                    }
                }
            }
        }
    }

    /// 지금 목록에 없는 세션의 배달 알림을 거둔다. 완료 알림도 확인하거나 진행 중으로 돌아가면 여기서 사라진다.
    func syncDelivered(keeping keys: Set<String>) {
        guard let center = center else { return }
        center.getDeliveredNotifications { delivered in
            let stale = delivered
                .map(\.request.identifier)
                .filter { !keys.contains($0) }
            guard !stale.isEmpty else { return }
            center.removeDeliveredNotifications(withIdentifiers: stale)
        }
    }

    /// 스위치를 끌 때 그 종류의 배달 알림만 거둔다. 다른 종류의 알림은 남긴다.
    func removeDelivered(kind: Kind) {
        guard let center = center else { return }
        center.getDeliveredNotifications { delivered in
            let ids = delivered
                .filter { $0.request.content.userInfo[Self.kindKey] as? String == kind.rawValue }
                .map(\.request.identifier)
            guard !ids.isEmpty else { return }
            center.removeDeliveredNotifications(withIdentifiers: ids)
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let action = response.actionIdentifier
        let sessionId = response.notification.request.content.userInfo[Self.sessionIdKey] as? String
        DispatchQueue.main.async { [weak self] in
            defer { completionHandler() }
            let button: NotificationButton?
            switch action {
            case UNNotificationDefaultActionIdentifier, NotificationButton.openInOrca.rawValue:
                button = .openInOrca
            case NotificationButton.snooze.rawValue:
                button = .snooze
            case NotificationButton.acknowledge.rawValue:
                button = .acknowledge
            default:
                button = nil
            }
            guard let button else { return }
            let groups = self?.model?.groups
            let item: DisplayItem?
            switch button {
            case .openInOrca:
                item = groups?.allItems.first(where: { $0.sessionId == sessionId })
            case .snooze:
                item = groups?.attention.first(where: { $0.sessionId == sessionId })
            case .acknowledge:
                item = groups?.done.first(where: { $0.sessionId == sessionId })
            }
            Self.logger.notice(
                "알림 응답 button=\(button.rawValue, privacy: .public) sessionId=\(sessionId ?? "-", privacy: .public) 항목=\(item == nil ? "없음" : "있음", privacy: .public)"
            )
            guard let item else { return }
            switch button {
            case .openInOrca: self?.model?.openInOrca(item)
            case .snooze: self?.model?.snooze(item)
            case .acknowledge: self?.model?.acknowledge(item)
            }
        }
    }

    private static func permission(_ settings: UNNotificationSettings) -> NotificationPermission {
        switch settings.authorizationStatus {
        case .authorized, .provisional: return .authorized
        case .denied: return .denied
        case .notDetermined: return .notDetermined
        @unknown default: return .unknown
        }
    }

    private static func publish(_ settings: UNNotificationSettings, to center: AttentionNotificationCenter) {
        let value = permission(settings)
        DispatchQueue.main.async { [weak center] in
            center?.model?.updateNotificationPermission(value)
        }
    }

    private static func log(_ settings: UNNotificationSettings, context: String) {
        logger.notice(
            "\(context, privacy: .public) authorizationStatus=\(settings.authorizationStatus.rawValue, privacy: .public) alertSetting=\(settings.alertSetting.rawValue, privacy: .public) alertStyle=\(settings.alertStyle.rawValue, privacy: .public) soundSetting=\(settings.soundSetting.rawValue, privacy: .public)"
        )
    }
}
