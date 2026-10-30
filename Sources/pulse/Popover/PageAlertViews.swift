import AppKit
import PulseCore
import SwiftUI

final class MenuPopupAnchor {
    weak var view: NSView?

    func show(_ menu: NSMenu) {
        guard let view, view.window != nil else { return }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: 0), in: view)
    }
}

private struct MenuPopupAnchorView: NSViewRepresentable {
    let anchor: MenuPopupAnchor

    func makeNSView(context: Context) -> NSView {
        let view = PassthroughView()
        anchor.view = view
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        anchor.view = nsView
    }

    private final class PassthroughView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}

struct HeaderPageBadge: View {
    @ObservedObject var model: AppModel

    @State private var anchor = MenuPopupAnchor()
    @State private var hovering = false

    private var total: Int { model.pageAlerts.count + model.unreadablePageFiles.count }

    var body: some View {
        if total > 0 {
            Button {
                activate()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 10, weight: .medium))
                    Text(L10n.pagesToRead(total))
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                }
                .foregroundColor(PopoverPalette.purple)
                .padding(.horizontal, 9)
                .padding(.vertical, 3)
                .background(Capsule().fill(PopoverPalette.purple.opacity(hovering ? 0.26 : 0.18)))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .background(MenuPopupAnchorView(anchor: anchor))
            .help(L10n.pagesToRead(total))
        }
    }

    private func activate() {
        if model.pageAlerts.count == 1, model.unreadablePageFiles.isEmpty {
            model.openPage(model.pageAlerts[0])
        } else {
            anchor.show(PageAlertMenus.header(model: model))
        }
    }
}

struct SessionPageBadge: View {
    @ObservedObject var model: AppModel
    let item: DisplayItem

    @State private var anchor = MenuPopupAnchor()
    @State private var hovering = false

    private var alerts: [PageAlert] { model.pages(for: item) }

    var body: some View {
        if let text = PageAlerts.rowText(for: alerts) {
            Button {
                activate()
            } label: {
                // 메타 줄이 좁으면 워크트리·티켓 대신 이 표시가 먼저 줄어든다.
                ViewThatFits(in: .horizontal) {
                    badgeLabel(text)
                    badgeLabel(alerts.count > 1 ? "\(alerts.count)" : nil)
                }
                .foregroundColor(PopoverPalette.purple)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(Capsule().fill(PopoverPalette.purple.opacity(hovering ? 0.26 : 0.18)))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .background(MenuPopupAnchorView(anchor: anchor))
            .help(text)
            .layoutPriority(-1)
        }
    }

    private func badgeLabel(_ text: String?) -> some View {
        HStack(spacing: 3) {
            Image(systemName: "doc.text")
                .font(.system(size: 9, weight: .medium))
            if let text {
                Text(text)
                    .font(.system(size: 9.5, weight: .medium))
                    .lineLimit(1)
            }
        }
        .fixedSize()
    }

    private func activate() {
        if alerts.count == 1 {
            model.openPage(alerts[0])
        } else {
            anchor.show(PageAlertMenus.session(model: model, alerts: alerts))
        }
    }
}

enum PageAlertMenus {
    static func header(model: AppModel) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        for alert in model.pageAlerts {
            menu.addItem(openItem(alert, model: model))
            menu.addItem(dismissItem(alert, model: model))
        }
        for name in model.unreadablePageFiles {
            menu.addItem(item(
                title: L10n.unreadablePageFile(name),
                meta: nil,
                action: { model.dismissUnreadablePage(name) }
            ))
        }
        if !menu.items.isEmpty {
            menu.addItem(.separator())
        }
        menu.addItem(item(title: L10n.dismissAllPages, meta: nil, action: { model.dismissAllPages() }))
        return menu
    }

    static func session(model: AppModel, alerts: [PageAlert]) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        for alert in alerts {
            menu.addItem(openItem(alert, model: model))
            menu.addItem(dismissItem(alert, model: model))
        }
        menu.addItem(.separator())
        menu.addItem(item(
            title: L10n.dismissSessionPages,
            meta: nil,
            action: { model.dismissPages(alerts) }
        ))
        return menu
    }

    private static func openItem(_ alert: PageAlert, model: AppModel) -> NSMenuItem {
        item(title: alert.label, meta: meta(for: alert), action: { model.openPage(alert) })
    }

    private static func dismissItem(_ alert: PageAlert, model: AppModel) -> NSMenuItem {
        let menuItem = item(
            title: L10n.dismissPage(alert.label),
            meta: nil,
            action: { model.dismissPage(alert) }
        )
        menuItem.isAlternate = true
        menuItem.keyEquivalentModifierMask = [.option]
        return menuItem
    }

    private static func item(
        title: String,
        meta: String?,
        action: @escaping () -> Void
    ) -> NSMenuItem {
        let menuItem = NSMenuItem(title: title, action: #selector(PageAlertMenuTarget.run(_:)), keyEquivalent: "")
        menuItem.target = PageAlertMenuTarget.shared
        menuItem.representedObject = PageAlertMenuAction(action)
        menuItem.attributedTitle = attributedTitle(title: title, meta: meta)
        menuItem.isEnabled = true
        return menuItem
    }

    private static func meta(for alert: PageAlert) -> String? {
        var parts: [String] = []
        if let name = alert.sessionName {
            parts.append(name)
        }
        if let relative = TimePhrase.relative(from: alert.createdAt, to: Date()) {
            parts.append(relative)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private static func attributedTitle(title: String, meta: String?) -> NSAttributedString {
        let result = NSMutableAttributedString(
            string: title,
            attributes: [.font: NSFont.menuFont(ofSize: 0), .foregroundColor: NSColor.labelColor]
        )
        if let meta {
            result.append(NSAttributedString(
                string: "\n" + meta,
                attributes: [
                    .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize - 1),
                    .foregroundColor: NSColor.secondaryLabelColor,
                ]
            ))
        }
        return result
    }
}

private final class PageAlertMenuAction: NSObject {
    let run: () -> Void

    init(_ run: @escaping () -> Void) {
        self.run = run
    }
}

private final class PageAlertMenuTarget: NSObject {
    static let shared = PageAlertMenuTarget()

    @objc func run(_ sender: NSMenuItem) {
        (sender.representedObject as? PageAlertMenuAction)?.run()
    }
}
