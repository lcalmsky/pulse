import AppKit
import Combine
import PulseCore

enum AppInfo {
    static let version = "0.2.0"
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = AppModel()
    private var statusController: StatusItemController?
    private var panelController: FloatingPanelController?
    private var cardPanelController: FloatingPanelController?
    private var hotKey: GlobalHotKey?
    private var cancellables: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        // AppKit 기본 툴팁 지연(약 1초)은 아이콘 버튼에 너무 길다. 밀리초 단위이고 툴팁이 만들어지기 전에 등록해야 한다.
        UserDefaults.standard.register(defaults: ["NSInitialToolTipDelay": 500])
        applyTheme(model.theme)
        model.$theme
            .sink { [weak self] theme in self?.applyTheme(theme) }
            .store(in: &cancellables)

        statusController = StatusItemController(model: model)
        panelController = FloatingPanelController.board(model: model)
        cardPanelController = FloatingPanelController.cards(model: model)

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
