import AppKit
import Combine
import DeadhdBarCore
import SwiftUI

final class StatusItemController: NSObject, NSPopoverDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let model: AppModel
    private let state = PopoverState()
    private var cancellables: Set<AnyCancellable> = []
    private var spinTimer: Timer?
    private var spinPhase: Double = 0
    private var keyMonitor: Any?
    private var lastClose = Date.distantPast

    private lazy var popover: NSPopover = {
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        let hosting = NSHostingController(rootView: PopoverView(model: model, state: state))
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
        updateSpin()
        updateStatusItem()

        model.$groups
            .sink { [weak self] _ in self?.dataChanged() }
            .store(in: &cancellables)
        model.$sessionsUnavailable
            .sink { [weak self] _ in self?.dataChanged() }
            .store(in: &cancellables)
        model.$theme
            .sink { [weak self] _ in self?.updateStatusItem() }
            .store(in: &cancellables)
    }

    deinit {
        spinTimer?.invalidate()
        removeKeyMonitor()
    }

    private func dataChanged() {
        updateSpin()
        updateStatusItem()
    }

    private func updateStatusItem() {
        updateIcon()
        guard let button = statusItem.button else { return }
        button.attributedTitle = MenuBarIcon.title(
            counts: model.groups.counts,
            unavailable: model.sessionsUnavailable
        )
    }

    private func updateIcon() {
        guard let button = statusItem.button else { return }
        button.image = MenuBarIcon.image(
            counts: model.groups.counts,
            phase: spinPhase,
            unavailable: model.sessionsUnavailable,
            appearance: button.effectiveAppearance
        )
    }

    private func updateSpin() {
        let shouldSpin = !model.sessionsUnavailable && model.groups.counts.working > 0
        guard shouldSpin else {
            spinTimer?.invalidate()
            spinTimer = nil
            spinPhase = 0
            return
        }
        guard spinTimer == nil else { return }
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.spinPhase = (self.spinPhase + 1.0 / 24.0).truncatingRemainder(dividingBy: 1)
            self.updateIcon()
        }
        timer.tolerance = 0.02
        RunLoop.main.add(timer, forMode: .common)
        spinTimer = timer
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
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.async { [weak self] in
            self?.popover.contentViewController?.view.window?.makeKey()
        }
        installKeyMonitor()
    }

    func popoverDidClose(_ notification: Notification) {
        lastClose = Date()
        state.reset()
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
