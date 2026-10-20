import AppKit

enum AppInfo {
    static let version = "0.1.0"
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = AppModel()
    private var statusController: StatusItemController?
    private var panelController: FloatingPanelController?
    private var detailController: DetailWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        detailController = DetailWindowController(model: model)
        model.detailPresenter = detailController
        statusController = StatusItemController(model: model)
        panelController = FloatingPanelController(model: model)
        model.start()
    }
}
