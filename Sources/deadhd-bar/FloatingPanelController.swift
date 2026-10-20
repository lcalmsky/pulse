import AppKit
import Combine
import SwiftUI

final class FloatingPanelController: NSObject {
    private let panel: NSPanel
    private let hosting: NSHostingView<BoardView>
    private let model: AppModel
    private let defaults = UserDefaults.standard
    private var cancellables: Set<AnyCancellable> = []

    init(model: AppModel) {
        self.model = model
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 240),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        hosting = NSHostingView(rootView: BoardView(model: model))
        super.init()

        configurePanel()
        configureContent()
        restorePosition()

        model.$panelVisible
            .sink { [weak self] visible in self?.setVisible(visible) }
            .store(in: &cancellables)
        model.$groups
            .sink { [weak self] _ in self?.updateSize() }
            .store(in: &cancellables)
        model.$collapsed
            .sink { [weak self] _ in self?.updateSize() }
            .store(in: &cancellables)
        model.$serverOff
            .sink { [weak self] _ in self?.updateSize() }
            .store(in: &cancellables)
        model.$errorMessage
            .sink { [weak self] _ in self?.updateSize() }
            .store(in: &cancellables)

        NotificationCenter.default.addObserver(
            self, selector: #selector(rememberPosition),
            name: NSWindow.didMoveNotification, object: panel
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(rememberPosition),
            name: NSWindow.didResizeNotification, object: panel
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func configurePanel() {
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }

    private func configureContent() {
        let effect = NSVisualEffectView()
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 16
        effect.layer?.masksToBounds = true
        effect.layer?.backgroundColor = NSColor.clear.cgColor

        hosting.frame = effect.bounds
        hosting.autoresizingMask = [.width, .height]
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = NSColor.clear.cgColor
        effect.addSubview(hosting)

        panel.contentView = effect
    }

    private func setVisible(_ visible: Bool) {
        if visible {
            updateSize()
            panel.orderFrontRegardless()
        } else {
            panel.orderOut(nil)
        }
    }

    private func updateSize() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.hosting.layoutSubtreeIfNeeded()
            let fitting = self.hosting.fittingSize
            let width = max(260, ceil(fitting.width))
            let height = max(44, ceil(fitting.height))

            var frame = self.panel.frame
            guard abs(frame.width - width) > 0.5 || abs(frame.height - height) > 0.5 else { return }
            let top = frame.maxY
            frame.size = NSSize(width: width, height: height)
            frame.origin.y = top - height
            self.panel.setFrame(frame, display: true)
        }
    }

    private func restorePosition() {
        if defaults.object(forKey: "panelOriginX") != nil,
           defaults.object(forKey: "panelOriginY") != nil {
            let point = NSPoint(
                x: defaults.double(forKey: "panelOriginX"),
                y: defaults.double(forKey: "panelOriginY")
            )
            if NSScreen.screens.contains(where: { $0.visibleFrame.contains(point) }) {
                panel.setFrameOrigin(point)
                return
            }
        }
        placeByDefault()
    }

    private func placeByDefault() {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        panel.setFrameTopLeftPoint(
            NSPoint(x: visible.maxX - panel.frame.width - 16, y: visible.maxY - 16)
        )
    }

    @objc private func rememberPosition() {
        defaults.set(Double(panel.frame.origin.x), forKey: "panelOriginX")
        defaults.set(Double(panel.frame.origin.y), forKey: "panelOriginY")
    }
}
