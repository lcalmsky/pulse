import Foundation
import DeadhdBarCore
import UserNotifications

/// UserNotifications 연동. 번들 식별자가 없으면 디버그 실행 파일이므로 아무것도 하지 않는다.
/// `UNUserNotificationCenter.current()` 자체가 번들 없는 프로세스에서 예외를 던지기 때문이다.
final class AttentionNotificationCenter: NSObject, UNUserNotificationCenterDelegate {
    private static let categoryIdentifier = "ATTENTION"
    private static let openAction = "OPEN_IN_ORCA"
    private static let laterAction = "LATER"
    private static let sessionIdKey = "sessionId"

    private weak var model: AppModel?
    private var authorizationRequested = false
    private var authorized = false

    private var center: UNUserNotificationCenter? {
        guard Bundle.main.bundleIdentifier != nil else { return nil }
        return UNUserNotificationCenter.current()
    }

    init(model: AppModel) {
        self.model = model
        super.init()

        guard let center = center else { return }
        center.delegate = self
        let open = UNNotificationAction(
            identifier: Self.openAction,
            title: "Orca 에서 열기",
            options: [.foreground]
        )
        let later = UNNotificationAction(identifier: Self.laterAction, title: "나중에", options: [])
        center.setNotificationCategories([
            UNNotificationCategory(
                identifier: Self.categoryIdentifier,
                actions: [open, later],
                intentIdentifiers: [],
                options: []
            ),
        ])
    }

    func requestAuthorizationIfNeeded() {
        guard let center = center, !authorizationRequested else { return }
        authorizationRequested = true
        center.requestAuthorization(options: [.alert, .sound]) { [weak self] granted, _ in
            DispatchQueue.main.async {
                self?.authorized = granted
            }
        }
    }

    func post(_ notes: [AttentionNote]) {
        guard let center = center, authorized else { return }
        for note in notes {
            let content = UNMutableNotificationContent()
            content.title = note.title
            content.body = note.body
            content.sound = .default
            content.categoryIdentifier = Self.categoryIdentifier
            content.userInfo = [Self.sessionIdKey: note.sessionId]
            center.add(UNNotificationRequest(identifier: note.identifier, content: content, trigger: nil))
        }
    }

    /// 「확인 필요」를 벗어난 항목의 알림을 알림 센터에서 거둔다.
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

    func removeAllDelivered() {
        guard let center = center else { return }
        center.removeAllDeliveredNotifications()
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
            guard action == UNNotificationDefaultActionIdentifier || action == Self.openAction,
                  let sessionId,
                  let item = self?.model?.groups.attention.first(where: { $0.sessionId == sessionId })
            else { return }
            self?.model?.openInOrca(item)
        }
    }
}
