import AppKit
import Combine
import PulseCore
import SwiftUI

final class StatusItemController: NSObject, NSPopoverDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let model: AppModel
    private let state = PopoverState()
    private var cancellables: Set<AnyCancellable> = []
    private var keyMonitor: Any?
    private var lastClose = Date.distantPast
    private var appearanceObservation: NSKeyValueObservation?
    private var drawnState: (counts: GroupedSessions.Counts, unavailable: Bool, appearance: NSAppearance.Name)?

    private lazy var popover: NSPopover = {
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        let hosting = NSHostingController(rootView: PopoverView(model: model, state: state, onClose: { [weak self] in
            self?.popover.performClose(nil)
        }))
        hosting.sizingOptions = [.preferredContentSize]
        popover.contentViewController = hosting
        return popover
    }()

    init(model: AppModel) {
        self.model = model
        super.init()

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(togglePopover)
            button.imagePosition = .imageLeading
        }
        updateStatusItem()
        updatePopoverAppearance()

        // @Published 는 값이 바뀌기 직전에 발행하므로 sink 안에서 model 을 읽으면 이전 값이다.
        // 다음 런루프로 미뤄 dataChanged 가 항상 바뀐 값을 읽게 한다.
        model.$groups
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.dataChanged() }
            .store(in: &cancellables)
        model.$sessionsUnavailable
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.dataChanged() }
            .store(in: &cancellables)
        // groups 는 값이 같으면 발행하지 않으므로, 매 틱 발행되는 lastSuccess 로 외형 변화를 확인한다.
        model.$lastSuccess
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.dataChanged() }
            .store(in: &cancellables)
        model.$theme
            .sink { [weak self] _ in
                self?.updateStatusItem()
                self?.updatePopoverAppearance()
            }
            .store(in: &cancellables)
        // NSPopover 는 상태 버튼의 외형을 물려받으므로 NSApp.appearance 만으로는 테마를 따르지 않는다.
        appearanceObservation = NSApp.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
            guard let self, self.model.theme == .system else { return }
            self.updatePopoverAppearance()
        }
    }

    deinit {
        removeKeyMonitor()
        appearanceObservation?.invalidate()
    }

    private func dataChanged() {
        guard let button = statusItem.button else {
            updateStatusItem()
            return
        }
        let state = (counts: model.groups.counts,
                     unavailable: model.sessionsUnavailable,
                     appearance: button.effectiveAppearance.name)
        // 아이콘은 버튼 외형으로 그리므로 외형 이름도 키에 넣어 라이트·다크 전환을 다음 틱에 반영한다.
        if let drawnState, drawnState == state { return }
        updateStatusItem()
    }

    private func updateStatusItem() {
        updateIcon()
        guard let button = statusItem.button else { return }
        button.attributedTitle = MenuBarIcon.title(
            counts: model.groups.counts,
            unavailable: model.sessionsUnavailable
        )
        drawnState = (counts: model.groups.counts,
                      unavailable: model.sessionsUnavailable,
                      appearance: button.effectiveAppearance.name)
    }

    private func updateIcon() {
        guard let button = statusItem.button else { return }
        button.image = MenuBarIcon.image(
            counts: model.groups.counts,
            unavailable: model.sessionsUnavailable,
            appearance: button.effectiveAppearance
        )
    }

    private func updatePopoverAppearance() {
        switch model.theme {
        case .light:
            popover.appearance = NSAppearance(named: .aqua)
        case .dark:
            popover.appearance = NSAppearance(named: .darkAqua)
        case .system:
            let name = NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) ?? .aqua
            popover.appearance = NSAppearance(named: name)
        }
    }

    // MARK: - 팝오버

    @objc private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
            return
        }
        // 같은 클릭이 transient 팝오버를 닫은 직후에 다시 열지 않는다.
        guard Date().timeIntervalSince(lastClose) > 0.2 else { return }
        showPopover()
    }

    private func showPopover() {
        guard let button = statusItem.button else { return }
        state.reset()
        model.setPopoverVisible(true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.async { [weak self] in
            self?.popover.contentViewController?.view.window?.makeKey()
        }
        installKeyMonitor()
    }

    var isPopoverShown: Bool {
        popover.isShown
    }

    func showPopoverFromHotKey() {
        guard !popover.isShown else { return }
        showPopover()
    }

    func closePopoverFromHotKey() {
        guard popover.isShown else { return }
        popover.performClose(nil)
    }

    func popoverDidClose(_ notification: Notification) {
        lastClose = Date()
        state.reset()
        model.setPopoverVisible(false)
        removeKeyMonitor()
    }

    // MARK: - 키보드

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self else { return event }
            if event.type == .flagsChanged {
                self.state.optionDown = event.modifierFlags.contains(.option)
                return event
            }
            return self.handleKey(event) ? nil : event
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
        keyMonitor = nil
        state.optionDown = false
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        guard popover.isShown else { return false }
        if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "," {
            state.settingsOpen.toggle()
            return true
        }

        switch event.keyCode {
        case 53:
            if state.settingsOpen {
                state.settingsOpen = false
            } else {
                popover.performClose(nil)
            }
            return true
        case 126, 125, 36, 76, 51, 117:
            // 설정 시트가 열려 있는 동안에는 목록 단축키를 넘기지 않는다.
            if state.settingsOpen { return true }
        default:
            break
        }
        if state.settingsOpen {
            return false
        }

        let items = state.filter.selectableItems(in: model.groups)
        switch event.keyCode {
        case 126, 125:
            let step = event.keyCode == 126 ? -1 : 1
            state.selectedIndex = KeyboardSelection.move(
                from: state.selectedIndex, by: step, count: items.count
            )
            return true
        case 36, 76:
            guard let item = selectedItem(in: items) else { return true }
            let hasOrca = item.orcaTerminal != nil || item.cwd != nil
            if event.modifierFlags.contains(.option), hasOrca {
                model.openInOrca(item)
            } else {
                model.open(item)
            }
            return true
        case 51, 117:
            guard let item = selectedItem(in: items) else { return true }
            model.acknowledge(item)
            return true
        default:
            return false
        }
    }

    private func selectedItem(in items: [DisplayItem]) -> DisplayItem? {
        guard let index = state.selectedIndex, items.indices.contains(index) else { return nil }
        return items[index]
    }
}
