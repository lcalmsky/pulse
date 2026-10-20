import AppKit
import Combine
import DeadhdBarCore

enum AppInfo {
    static let version = "0.1.0"
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = AppModel()
    private var statusController: StatusItemController?
    private var panelController: FloatingPanelController?
    private var detailController: DetailWindowController?
    private var cancellables: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        applyTheme(model.theme)
        model.$theme
            .sink { [weak self] theme in self?.applyTheme(theme) }
            .store(in: &cancellables)

        detailController = DetailWindowController(model: model)
        model.detailPresenter = detailController
        statusController = StatusItemController(model: model)
        panelController = FloatingPanelController(model: model)
        model.start()
    }

    private func applyTheme(_ theme: ThemePreference) {
        switch theme {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }
}
