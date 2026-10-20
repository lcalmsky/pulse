import AppKit
import Combine
import DeadhdBarCore

final class StatusItemController: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private let model: AppModel
    private var cancellables: Set<AnyCancellable> = []

    init(model: AppModel) {
        self.model = model
        super.init()
        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu
        updateBadge()
        model.$groups
            .sink { [weak self] _ in self?.updateBadge() }
            .store(in: &cancellables)
        model.$serverOff
            .sink { [weak self] _ in self?.updateBadge() }
            .store(in: &cancellables)
    }

    private func updateBadge() {
        guard let button = statusItem.button else { return }
        if model.serverOff {
            button.attributedTitle = NSAttributedString(
                string: "◌ deadhd",
                attributes: [.foregroundColor: NSColor.tertiaryLabelColor]
            )
            return
        }

        let counts = model.groups.counts
        let badge = NSMutableAttributedString()
        let parts: [(String, NSColor)] = [
            ("● \(counts.attention)", .systemOrange),
            ("⟳ \(counts.working)", .systemBlue),
            ("✓ \(counts.done)", .systemGreen),
        ]
        for (index, part) in parts.enumerated() {
            if index > 0 {
                badge.append(NSAttributedString(string: "  "))
            }
            badge.append(NSAttributedString(
                string: part.0,
                attributes: [
                    .foregroundColor: part.1,
                    .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
                ]
            ))
        }
        button.attributedTitle = badge
    }

    // MARK: - 메뉴

    func menuWillOpen(_ menu: NSMenu) {
        rebuild()
    }

    private func rebuild() {
        menu.removeAllItems()

        if let error = model.errorMessage {
            info(error, color: .systemRed)
        }
        if model.serverOff {
            info("deadhd 서버가 꺼져 있어요", color: .secondaryLabelColor)
            action("서버 시작", #selector(startServer))
            menu.addItem(.separator())
        }

        let groups = model.groups
        if groups.totalCount == 0 {
            info(model.serverOff ? "세션 정보를 받지 못했어요" : "지금은 조용해요", color: .secondaryLabelColor)
        }

        for group in DisplayGroup.allCases {
            let items = groups.items(for: group)
            guard !items.isEmpty else { continue }
            info("\(group.title) \(items.count)", color: color(for: group), bold: true)
            for item in items {
                addSession(item, group: group)
            }
        }

        menu.addItem(.separator())
        let acknowledge = action("완료 전부 확인", #selector(acknowledgeAllDone))
        acknowledge.isEnabled = !groups.done.isEmpty
        action(model.panelVisible ? "플로팅 창 숨기기" : "플로팅 창 보기", #selector(togglePanel))
        menu.addItem(.separator())
        action("종료", #selector(quit))
    }

    private func addSession(_ item: DisplayItem, group: DisplayGroup) {
        var parts = ["\(short(item.title, 30)) · \(short(item.status, 44))"]
        if let place = item.placeText {
            parts.append(short(place, 24))
        }
        let title = parts.joined(separator: " · ")

        let menuItem = NSMenuItem(title: title, action: #selector(openSession(_:)), keyEquivalent: "")
        menuItem.target = self
        menuItem.representedObject = item
        menuItem.isEnabled = item.isActionable
        menuItem.toolTip = [item.title, item.status, item.detail, item.placeText]
            .compactMap { $0 }
            .joined(separator: "\n")
        menuItem.attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                .font: NSFont.menuFont(ofSize: 0),
                .foregroundColor: group == .attention ? NSColor.systemOrange : NSColor.labelColor,
            ]
        )
        menu.addItem(menuItem)
    }

    @discardableResult
    private func info(_ title: String, color: NSColor, bold: Bool = false) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        item.attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                .font: bold ? NSFont.boldSystemFont(ofSize: NSFont.smallSystemFontSize)
                            : NSFont.menuFont(ofSize: 0),
                .foregroundColor: color,
            ]
        )
        menu.addItem(item)
        return item
    }

    @discardableResult
    private func action(_ title: String, _ selector: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
        item.target = self
        menu.addItem(item)
        return item
    }

    private func short(_ text: String, _ limit: Int) -> String {
        text.count <= limit ? text : String(text.prefix(limit - 1)) + "…"
    }

    private func color(for group: DisplayGroup) -> NSColor {
        switch group {
        case .attention: return .systemOrange
        case .working: return .systemBlue
        case .done: return .systemGreen
        }
    }

    // MARK: - 액션

    @objc private func openSession(_ sender: NSMenuItem) {
        guard let item = sender.representedObject as? DisplayItem else { return }
        model.open(item)
    }

    @objc private func acknowledgeAllDone() {
        model.acknowledgeAllDone()
    }

    @objc private func togglePanel() {
        model.togglePanel()
    }

    @objc private func startServer() {
        model.startServer()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
