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
        /// true 면 macOS 26 의 Liquid Glass(NSGlassEffectView)로 창 배경을 그린다. 그 아래 OS 에서는 NSVisualEffectView 로 돌아간다.
        let liquidGlass: Bool
        /// 목록 패널만 클릭했을 때 키 창이 되어 목록 키를 받는다.
        let acceptsKeyboard: Bool
    }

    private let panel: ListPanel
    private let hosting: FirstMouseHostingView
    private let options: Options
    private let defaults = UserDefaults.standard
    private var cancellables: Set<AnyCancellable> = []
    private var manualSize = false
    private var programmaticSize: NSSize?
    private var listState: PopoverState?
    private var keyMonitor: Any?

    var onHover: ((Bool) -> Void)? {
        didSet { hosting.onHover = onHover }
    }

    var onPointerMove: ((CGPoint?) -> Void)? {
        didSet { hosting.onPointerMove = onPointerMove }
    }

    init(
        options: Options,
        visible: AnyPublisher<Bool, Never>,
        resizeTriggers: AnyPublisher<Void, Never>,
        content: (@escaping () -> Void) -> AnyView
    ) {
        self.options = options
        panel = ListPanel(
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
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
    }

    /// 목록 패널이 키 창일 때만 공용 목록 키 처리로 넘긴다.
    func installListKeyboard(model: AppModel, state: PopoverState) {
        listState = state
        let keyboard = ListKeyboard(
            model: model,
            state: state,
            handlesSettings: false,
            close: { state.selectedIndex = nil }
        )
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self, self.panel.isVisible, self.panel.isKeyWindow, event.window === self.panel else {
                return event
            }
            if event.type == .flagsChanged {
                state.optionDown = event.modifierFlags.contains(.option)
                return event
            }
            return keyboard.handle(event) ? nil : event
        }
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
        let state = PopoverState()
        let controller = FloatingPanelController(
            options: Options(
                defaultWidth: 440,
                minimumWidth: 340,
                fixedWidth: false,
                remembersFrame: true,
                cornerRadius: 16,
                liquidGlass: false,
                acceptsKeyboard: true
            ),
            visible: model.$panelVisible.eraseToAnyPublisher(),
            resizeTriggers: triggers
        ) { updateSize in
            AnyView(BoardView(model: model, state: state, onContentHeightChange: updateSize))
        }
        controller.installListKeyboard(model: model, state: state)
        return controller
    }

    static func cards(model: AppModel) -> FloatingPanelController {
        let triggers = Publishers.MergeMany([
            model.$cards.map { _ in () }.eraseToAnyPublisher(),
            model.$groups.map { _ in () }.eraseToAnyPublisher(),
        ]).eraseToAnyPublisher()
        let pointer = CardPointer()
        let controller = FloatingPanelController(
            options: Options(
                defaultWidth: 340,
                minimumWidth: 340,
                fixedWidth: true,
                remembersFrame: false,
                cornerRadius: 14,
                liquidGlass: true,
                acceptsKeyboard: false
            ),
            visible: model.$cardPanelVisible.eraseToAnyPublisher(),
            resizeTriggers: triggers
        ) { updateSize in
            AnyView(
                CardPanelView(model: model, onContentHeightChange: updateSize)
                    .environmentObject(pointer)
            )
        }
        controller.onHover = { model.setCardHover($0) }
        controller.onPointerMove = { pointer.move(to: $0) }
        controller.panel.acceptsMouseMovedEvents = true
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
        panel.acceptsKeyboard = options.acceptsKeyboard
        // 키를 받는 패널은 클릭할 때만 키 창이 되고, 그 밖에는 띄워도 키를 가져가지 않는다.
        panel.becomesKeyOnlyIfNeeded = !options.acceptsKeyboard
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }

    private func configureContent() {
        hosting.autoresizingMask = [.width, .height]
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = NSColor.clear.cgColor

        if options.liquidGlass, #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.cornerRadius = options.cornerRadius
            glass.style = .regular
            hosting.frame = glass.bounds
            glass.contentView = hosting
            panel.contentView = glass
            return
        }

        let effect = NSVisualEffectView()
        effect.material = .popover
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = options.cornerRadius
        effect.layer?.masksToBounds = true
        effect.layer?.backgroundColor = NSColor.clear.cgColor
        hosting.frame = effect.bounds
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
            listState?.reset()
            // 숨긴 창에는 mouseExited 가 오지 않아, 다시 뜰 때 남은 위치로 호버가 켜지지 않게 비운다.
            hosting.onPointerMove?(nil)
        }
    }

    private func updateSize() {
        guard !manualSize else { return }
        DispatchQueue.main.async { [weak self] in
            // setVisible(true) 는 updateSize() 직후 같은 동기 구간에서 orderFrontRegardless() 를 부르므로, 여기서는 이미 보인다.
            guard let self, !self.manualSize, self.panel.isVisible else { return }
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

/// borderless NSPanel 은 기본적으로 키 창이 되지 않는다. 목록 패널만 키 입력을 받는다.
private final class ListPanel: NSPanel {
    var acceptsKeyboard = false

    override var canBecomeKey: Bool { acceptsKeyboard }
}

/// 비활성 패널에서 첫 클릭이 창 활성화에만 쓰이지 않고 버튼에 닿게 한다.
private final class FirstMouseHostingView: NSHostingView<AnyView> {
    var onHover: ((Bool) -> Void)?
    var onPointerMove: ((CGPoint?) -> Void)?
    private var hoverArea: NSTrackingArea?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // accessory 앱은 대개 비활성이라 `.activeAlways` 가 있어야 마우스 이동을 받는다.
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        hoverArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        onHover?(true)
        onPointerMove?(pointerLocation(for: event))
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        onPointerMove?(pointerLocation(for: event))
    }

    override func mouseExited(with event: NSEvent) {
        onHover?(false)
        onPointerMove?(nil)
    }

    private func pointerLocation(for event: NSEvent) -> CGPoint {
        let point = convert(event.locationInWindow, from: nil)
        guard !isFlipped else { return point }
        return CGPoint(x: point.x, y: bounds.height - point.y)
    }
}
