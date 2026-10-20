import AppKit

enum AppInfo {
    static let version = "0.1.0"
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = AppModel()
    private var statusController: StatusItemController?
    private var panelController: FloatingPanelController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusController = StatusItemController(model: model)
        panelController = FloatingPanelController(model: model)
        model.start()
    }
}
