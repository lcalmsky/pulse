import AppKit
import Combine
import SwiftUI

/// 목록 패널과 알림 카드 패널이 함께 쓰는 borderless 창. 내용만 바꿔 끼운다.
final class FloatingPanelController: NSObject {
    struct Options {
        let defaultWidth: CGFloat
        let minimumWidth: CGFloat
        let fixedWidth: Bool
        let remembersFrame: Bool
        let cornerRadius: CGFloat
    }

    private let panel: NSPanel
    private let hosting: FirstMouseHostingView
    private let options: Options
    private let defaults = UserDefaults.standard
    private var cancellables: Set<AnyCancellable> = []
    private var manualSize = false
    private var programmaticSize: NSSize?

    var onHover: ((Bool) -> Void)? {
        didSet { hosting.onHover = onHover }
    }

    init(
        options: Options,
        visible: AnyPublisher<Bool, Never>,
        resizeTriggers: AnyPublisher<Void, Never>,
        content: (@escaping () -> Void) -> AnyView
    ) {
        self.options = options
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: options.defaultWidth, height: 240),
            styleMask: options.fixedWidth
                ? [.borderless, .nonactivatingPanel]
                : [.borderless, .nonactivatingPanel, .resizable],
            backing: .buffered,
            defer: false
        )
        hosting = FirstMouseHostingView(rootView: AnyView(EmptyView()))
        super.init()

        hosting.rootView = content { [weak self] in self?.updateSize() }
        configurePanel()
        configureContent()
        restoreSize()
        restorePosition()

        visible
            .sink { [weak self] visible in self?.setVisible(visible) }
            .store(in: &cancellables)
        resizeTriggers
            .sink { [weak self] _ in self?.updateSize() }
            .store(in: &cancellables)

        if options.remembersFrame {
            NotificationCenter.default.addObserver(
                self, selector: #selector(rememberPosition),
                name: NSWindow.didMoveNotification, object: panel
            )
            NotificationCenter.default.addObserver(
                self, selector: #selector(rememberSize),
                name: NSWindow.didResizeNotification, object: panel
            )
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    static func board(model: AppModel) -> FloatingPanelController {
        let triggers = Publishers.MergeMany([
            model.$groups.map { _ in () }.eraseToAnyPublisher(),
            model.$collapsed.map { _ in () }.eraseToAnyPublisher(),
            model.$sessionsUnavailable.map { _ in () }.eraseToAnyPublisher(),
            model.$errorMessage.map { _ in () }.eraseToAnyPublisher(),
            model.$hiddenDoneCount.map { _ in () }.eraseToAnyPublisher(),
            model.$recentAcknowledgedCount.map { _ in () }.eraseToAnyPublisher(),
        ]).eraseToAnyPublisher()
        return FloatingPanelController(
            options: Options(
                defaultWidth: 440,
                minimumWidth: 340,
                fixedWidth: false,
                remembersFrame: true,
                cornerRadius: 16
            ),
            visible: model.$panelVisible.eraseToAnyPublisher(),
            resizeTriggers: triggers
        ) { updateSize in
            AnyView(BoardView(model: model, onContentHeightChange: updateSize))
        }
    }

    static func cards(model: AppModel) -> FloatingPanelController {
        let triggers = Publishers.MergeMany([
            model.$cards.map { _ in () }.eraseToAnyPublisher(),
            model.$groups.map { _ in () }.eraseToAnyPublisher(),
        ]).eraseToAnyPublisher()
        let controller = FloatingPanelController(
            options: Options(
                defaultWidth: 340,
                minimumWidth: 340,
                fixedWidth: true,
                remembersFrame: false,
                cornerRadius: 14
            ),
            visible: model.$cardPanelVisible.eraseToAnyPublisher(),
            resizeTriggers: triggers
        ) { updateSize in
            AnyView(CardPanelView(model: model, onContentHeightChange: updateSize))
        }
        controller.onHover = { model.setCardHover($0) }
        return controller
    }

    private func configurePanel() {
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = options.remembersFrame
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }

    private func configureContent() {
        let effect = NSVisualEffectView()
        effect.material = .popover
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = options.cornerRadius
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
            if !options.remembersFrame {
                placeTopRight()
            }
            updateSize()
            panel.orderFrontRegardless()
        } else {
            panel.orderOut(nil)
        }
    }

    private func updateSize() {
        guard !manualSize else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.manualSize else { return }
            self.hosting.layoutSubtreeIfNeeded()
            let fitting = self.hosting.fittingSize
            let width = self.options.fixedWidth
                ? self.options.defaultWidth
                : min(max(self.options.defaultWidth, ceil(fitting.width)), 1200)
            let height = min(max(44, ceil(fitting.height)), self.maximumContentHeight)

            var frame = self.panel.frame
            guard abs(frame.width - width) > 0.5 || abs(frame.height - height) > 0.5 else { return }
            let top = frame.maxY
            frame.size = NSSize(width: width, height: height)
            frame.origin.y = top - height
            self.programmaticSize = frame.size
            self.panel.setFrame(frame, display: true)
        }
    }

    private var maximumContentHeight: CGFloat {
        guard let screen = panel.screen ?? NSScreen.main else { return .greatestFiniteMagnitude }
        return floor(screen.visibleFrame.height * 0.7)
    }

    private func restoreSize() {
        guard options.remembersFrame else { return }
        panel.contentMinSize = NSSize(width: options.minimumWidth, height: 44)
        guard defaults.object(forKey: "panelWidth") != nil,
              defaults.object(forKey: "panelHeight") != nil else { return }
        let width = max(options.minimumWidth, CGFloat(defaults.double(forKey: "panelWidth")))
        let height = max(44, CGFloat(defaults.double(forKey: "panelHeight")))
        var frame = panel.frame
        frame.size = NSSize(width: width, height: height)
        programmaticSize = frame.size
        panel.setFrame(frame, display: false)
        manualSize = true
    }

    private func restorePosition() {
        guard options.remembersFrame else {
            placeTopRight()
            return
        }
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

    private func placeTopRight() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let visible = screen.visibleFrame
        panel.setFrameTopLeftPoint(
            NSPoint(x: visible.maxX - panel.frame.width - 12, y: visible.maxY - 12)
        )
    }

    @objc private func rememberPosition() {
        defaults.set(Double(panel.frame.origin.x), forKey: "panelOriginX")
        defaults.set(Double(panel.frame.origin.y), forKey: "panelOriginY")
    }

    @objc private func rememberSize() {
        if let expected = programmaticSize {
            programmaticSize = nil
            if abs(expected.width - panel.frame.width) < 0.5,
               abs(expected.height - panel.frame.height) < 0.5 {
                return
            }
        }
        manualSize = true
        defaults.set(Double(panel.frame.width), forKey: "panelWidth")
        defaults.set(Double(panel.frame.height), forKey: "panelHeight")
    }
}

/// 비활성 패널에서 첫 클릭이 창 활성화에만 쓰이지 않고 버튼에 닿게 한다.
private final class FirstMouseHostingView: NSHostingView<AnyView> {
    var onHover: ((Bool) -> Void)?
    private var hoverArea: NSTrackingArea?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // accessory 앱은 대개 비활성이라 `.activeAlways` 가 있어야 마우스 이동을 받는다.
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        hoverArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        onHover?(true)
    }

    override func mouseExited(with event: NSEvent) {
        onHover?(false)
    }
}
