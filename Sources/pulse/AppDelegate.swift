import AppKit
import Combine
import PulseCore

enum AppInfo {
    static let version = "0.1.0"
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = AppModel()
    private var statusController: StatusItemController?
    private var panelController: FloatingPanelController?
    private var hotKey: GlobalHotKey?
    private var cancellables: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        applyTheme(model.theme)
        model.$theme
            .sink { [weak self] theme in self?.applyTheme(theme) }
            .store(in: &cancellables)

        statusController = StatusItemController(model: model)
        panelController = FloatingPanelController(model: model)

        let hotKey = GlobalHotKey { [weak self] in self?.handleHotKey() }
        self.hotKey = hotKey
        model.setHotKeyUnavailable(!hotKey.register())

        model.start()
    }

    private func handleHotKey() {
        guard let statusController else { return }
        switch HotKeyRouting.action(
            popoverOpen: statusController.isPopoverShown,
            panelVisible: model.panelVisible
        ) {
        case .openPopover:
            statusController.showPopoverFromHotKey()
        case .closePopoverAndShowPanel:
            statusController.closePopoverFromHotKey()
            model.showPanel()
        case .closePopover:
            statusController.closePopoverFromHotKey()
        case .hidePanel:
            model.hidePanel()
        }
    }

    private func applyTheme(_ theme: ThemePreference) {
        switch theme {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }
}
