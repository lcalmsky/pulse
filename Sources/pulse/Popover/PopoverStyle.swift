import AppKit
import Combine
import OSLog
import PulseCore
import SwiftUI

/// 시안(deadhd-bar-mockup.html)의 CSS 토큰. 라이트·다크 값을 그대로 옮겨 왔다.
enum PopoverPalette {
    static let text = dynamic(
        dark: rgb(0xf4, 0xf4, 0xf7),
        light: rgb(0x16, 0x16, 0x1a)
    )

    static let secondary = dynamic(
        dark: rgb(0xeb, 0xeb, 0xf5, 0.62),
        light: rgb(0x3c, 0x3c, 0x43, 0.70)
    )

    static let tertiary = dynamic(
        dark: rgb(0xeb, 0xeb, 0xf5, 0.38),
        light: rgb(0x3c, 0x3c, 0x43, 0.42)
    )

    static let stroke = dynamic(
        dark: rgb(0xff, 0xff, 0xff, 0.10),
        light: rgb(0x00, 0x00, 0x00, 0.08)
    )

    static let strokeHi = dynamic(
        dark: rgb(0xff, 0xff, 0xff, 0.18),
        light: rgb(0x00, 0x00, 0x00, 0.14)
    )

    static let glassHi = dynamic(
        dark: rgb(0xff, 0xff, 0xff, 0.06),
        light: rgb(0xff, 0xff, 0xff, 0.60)
    )

    static let rowHover = dynamic(
        dark: rgb(0xff, 0xff, 0xff, 0.07),
        light: rgb(0x00, 0x00, 0x00, 0.05)
    )

    static let stepPanel = dynamic(
        dark: rgb(0xff, 0xff, 0xff, 0.04),
        light: rgb(0x00, 0x00, 0x00, 0.04)
    )

    /// `--glass` 의 RGB. 투명도 줄이기가 켜졌을 때 단색 배경으로 쓴다.
    static let glassSolid = dynamic(
        dark: rgb(0x1c, 0x1c, 0x22),
        light: rgb(0xf6, 0xf6, 0xfa)
    )

    static let glassVeil = dynamic(
        dark: rgb(0x1c, 0x1c, 0x22, 0),
        light: rgb(0xf6, 0xf6, 0xfa, 0.78)
    )

    static let star = dynamic(
        dark: rgb(0xff, 0xd6, 0x0a),
        light: rgb(0xe0, 0xa1, 0x00)
    )

    static let selection = dynamic(
        dark: rgb(0x0a, 0x84, 0xff, 0.90),
        light: rgb(0x00, 0x7a, 0xff, 0.92)
    )

    static let attention = dynamic(
        dark: rgb(0xff, 0x9f, 0x0a),
        light: rgb(0xe8, 0x82, 0x0c)
    )

    static let working = dynamic(
        dark: rgb(0x0a, 0x84, 0xff),
        light: rgb(0x00, 0x7a, 0xff)
    )

    static let done = dynamic(
        dark: rgb(0x30, 0xd1, 0x58),
        light: rgb(0x1f, 0xa8, 0x4a)
    )

    static let link = dynamic(
        dark: rgb(0x9b, 0xb7, 0xff),
        light: rgb(0x2f, 0x62, 0xd9)
    )

    static let purple = dynamic(
        dark: rgb(0xbf, 0x5a, 0xf2),
        light: rgb(0x9b, 0x3f, 0xd1)
    )

    static func color(for group: DisplayGroup) -> Color {
        switch group {
        case .attention: return attention
        case .working: return working
        case .done: return done
        }
    }

    private static func dynamic(dark: NSColor, light: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        })
    }

    private static func rgb(_ red: Int, _ green: Int, _ blue: Int, _ alpha: Double = 1) -> NSColor {
        NSColor(
            srgbRed: CGFloat(red) / 255,
            green: CGFloat(green) / 255,
            blue: CGFloat(blue) / 255,
            alpha: CGFloat(alpha)
        )
    }
}

/// 투명도 줄이기가 켜져 있으면 시안의 `--glass` RGB 로 단색을 채운다.
/// 꺼져 있으면 유리 머티리얼을 보여 주되, 라이트에서는 뒤의 글자가 비치지 않도록 한 겹 더 깐다.
struct PopoverBackground: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        if reduceTransparency {
            PopoverPalette.glassSolid
        } else {
            PopoverPalette.glassVeil
        }
    }
}

struct KeyHint: View {
    private let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .foregroundColor(PopoverPalette.secondary)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 4).fill(PopoverPalette.glassHi))
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(PopoverPalette.strokeHi, lineWidth: 1)
            )
    }
}

struct PopoverIconButton: View {
    let symbol: String
    let help: String
    var enabled = true
    var selected = false
    var symbolSize: CGFloat = 15
    /// 쉬는 상태의 배경. nil 이면 투명하다.
    var restingFill: Color? = nil
    /// 쉬는 상태의 글리프 색. nil 이면 보조 색을 쓴다.
    var restingGlyph: Color? = nil
    let action: () -> Void

    @State private var hovering = false

    private var active: Bool { hovering && enabled || selected }

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: symbolSize))
                .frame(width: 26, height: 26)
                .foregroundColor(restingGlyph ?? (active ? PopoverPalette.text : PopoverPalette.secondary))
                .background(
                    ZStack {
                        RoundedRectangle(cornerRadius: 7)
                            .fill(restingFill ?? Color.clear)
                        RoundedRectangle(cornerRadius: 7)
                            .fill(active ? (restingFill == nil ? PopoverPalette.rowHover : PopoverPalette.strokeHi) : Color.clear)
                    }
                )
                .contentShape(Rectangle())
                .opacity(enabled ? 1 : 0.4)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .onHover { hovering = $0 }
        .help(help)
    }
}

struct PopoverTextButton: View {
    let symbol: String
    let title: String
    let help: String
    var enabled = true
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 14))
                Text(title)
                    .font(.system(size: 12, weight: .medium))
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .foregroundColor(
                enabled
                    ? (hovering ? PopoverPalette.text : PopoverPalette.secondary)
                    : PopoverPalette.secondary.opacity(0.35)
            )
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(hovering && enabled ? PopoverPalette.rowHover : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .onHover { hovering = $0 }
        .help(help)
    }
}

/// 시스템 스크롤 막대는 "항상 보기" 설정에서 내용 폭을 차지하고 두껍게 그려진다.
/// 시스템 막대를 끄고 얇은 캡슐 막대를 직접 그린다. 스크롤·호버·드래그 중에만 보인다.
struct SlimScrollView<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    @StateObject private var state = SlimScrollState()
    @State private var hovering = false
    @State private var dragStart: CGFloat?

    private let inset: CGFloat = 6

    var body: some View {
        ScrollView(.vertical) {
            content
                .background(ScrollViewProbe { [weak state] in state?.attach($0) })
        }
        .scrollIndicators(.never)
        .mask(edgeFade)
        .overlay(alignment: .topTrailing) { indicator }
    }

    /// 가려진 내용이 있는 쪽 가장자리만 흐리게 지운다. 잘린 행이 칼로 자른 듯 보이지 않고, 더 있다는 신호도 된다.
    private var edgeFade: some View {
        let top = state.scrollable && state.offset > 1
        let bottom = state.scrollable && state.offset < state.maxOffset - 1
        return VStack(spacing: 0) {
            LinearGradient(colors: [.black.opacity(top ? 0 : 1), .black], startPoint: .top, endPoint: .bottom)
                .frame(height: 18)
            Color.black
            LinearGradient(colors: [.black, .black.opacity(bottom ? 0 : 1)], startPoint: .top, endPoint: .bottom)
                .frame(height: 18)
        }
        .animation(.easeOut(duration: 0.2), value: top)
        .animation(.easeOut(duration: 0.2), value: bottom)
    }

    private var track: CGFloat { max(state.viewport - inset * 2, 0) }
    private var knobHeight: CGFloat {
        guard state.scrollable else { return 0 }
        return min(track, max(24, track * state.viewport / state.contentHeight))
    }
    private var knobY: CGFloat {
        let progress = min(max(state.offset / state.maxOffset, 0), 1)
        return inset + (track - knobHeight) * progress
    }
    private var active: Bool { hovering || dragStart != nil }

    @ViewBuilder
    private var indicator: some View {
        if state.scrollable {
            ZStack(alignment: .topTrailing) {
                Capsule()
                    .fill(active ? Color(nsColor: .controlAccentColor).opacity(0.85) : PopoverPalette.text.opacity(0.22))
                    .frame(width: active ? 6 : 3, height: knobHeight)
                    .padding(.trailing, active ? 3 : 4.5)
                    .offset(y: knobY)
                    .opacity(state.shown || active ? 1 : 0)
                    .animation(.spring(response: 0.25, dampingFraction: 0.85), value: active)
                    .animation(.easeOut(duration: state.shown ? 0.12 : 0.5), value: state.shown)
            }
            .frame(width: 14, height: state.viewport, alignment: .topTrailing)
            .contentShape(Rectangle())
            .onHover { inside in
                hovering = inside
                state.holding = active
                // 나갈 때도 숨김 타이머를 다시 건다. 호버 중에 지나간 타이머는 막대를 숨기지 않았다.
                state.reveal()
            }
            .gesture(drag)
        }
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if dragStart == nil {
                    let y = value.startLocation.y
                    // 막대 밖을 누르면 그 위치로 먼저 옮긴 뒤 드래그를 이어 간다.
                    if y < knobY || y > knobY + knobHeight {
                        let progress = (y - inset - knobHeight / 2) / max(track - knobHeight, 1)
                        state.scroll(to: progress * state.maxOffset)
                    }
                    dragStart = state.offset
                    state.holding = true
                }
                let ratio = state.maxOffset / max(track - knobHeight, 1)
                state.scroll(to: (dragStart ?? state.offset) + value.translation.height * ratio)
            }
            .onEnded { _ in
                dragStart = nil
                state.holding = hovering
                state.reveal()
            }
    }
}

/// 스크롤 위치는 SwiftUI 레이아웃이 아니라 클립 뷰의 bounds 에서 읽는다. 스크롤만으로는 레이아웃이 다시 돌지 않는다.
/// 알림 구독과 숨김 작업이 뷰 값을 붙잡지 않도록 클래스에 두고, 값이 바뀔 때만 발행해 레이아웃 중의 갱신이 되풀이되지 않게 한다.
private final class SlimScrollState: ObservableObject {
    @Published private(set) var viewport: CGFloat = 0
    @Published private(set) var contentHeight: CGFloat = 0
    @Published private(set) var offset: CGFloat = 0
    @Published private(set) var shown = false
    /// 호버나 드래그 중이면 막대를 숨기지 않는다.
    var holding = false

    private weak var scrollView: NSScrollView?
    private var observers: [AnyCancellable] = []
    private var hideWork: DispatchWorkItem?

    var scrollable: Bool { contentHeight > viewport + 1 && viewport > 0 }
    var maxOffset: CGFloat { max(contentHeight - viewport, 1) }

    func attach(_ found: NSScrollView) {
        guard scrollView !== found else { return }
        scrollView = found
        let clip = found.contentView
        clip.postsBoundsChangedNotifications = true
        found.documentView?.postsFrameChangedNotifications = true
        observers = [
            NotificationCenter.default.publisher(for: NSView.boundsDidChangeNotification, object: clip)
                .sink { [weak self] _ in self?.measure(revealing: true) },
            NotificationCenter.default.publisher(for: NSView.frameDidChangeNotification, object: clip)
                .sink { [weak self] _ in self?.measure(revealing: false) },
        ]
        if let document = found.documentView {
            observers.append(
                NotificationCenter.default.publisher(for: NSView.frameDidChangeNotification, object: document)
                    .sink { [weak self] _ in self?.measure(revealing: false) }
            )
        }
        measure(revealing: true)
    }

    func scroll(to target: CGFloat) {
        guard let scrollView, let document = scrollView.documentView else { return }
        let clamped = min(max(target, 0), maxOffset)
        let clip = scrollView.contentView
        let y = document.isFlipped ? clamped : document.frame.height - clip.bounds.height - clamped
        clip.scroll(to: NSPoint(x: clip.bounds.origin.x, y: y))
        scrollView.reflectScrolledClipView(clip)
    }

    func reveal() {
        guard scrollable else { return }
        if !shown { shown = true }
        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.holding, self.shown else { return }
            self.shown = false
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9, execute: work)
    }

    private func measure(revealing: Bool) {
        guard let scrollView, let document = scrollView.documentView else { return }
        let clip = scrollView.contentView.bounds
        let height = document.frame.height
        let top = document.isFlipped ? clip.origin.y : height - clip.height - clip.origin.y
        // inout 으로 넘기면 @Published setter 가 값이 같아도 불리므로 그 자리에서 비교한다.
        if abs(viewport - clip.height) > 0.5 { viewport = clip.height }
        if abs(contentHeight - height) > 0.5 { contentHeight = height }
        if abs(offset - top) > 0.5 { offset = top }
        if revealing { reveal() }
    }
}

/// SwiftUI ScrollView 를 감싼 NSScrollView 를 찾는다. 막대를 드래그할 때 스크롤 위치를 옮기는 데 쓴다.
private struct ScrollViewProbe: NSViewRepresentable {
    let found: (NSScrollView) -> Void

    func makeNSView(context: Context) -> NSView { Probe(found: found) }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class Probe: NSView {
        let found: (NSScrollView) -> Void

        init(found: @escaping (NSScrollView) -> Void) {
            self.found = found
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard window != nil else { return }
            guard let scrollView = enclosingScrollView else {
                Logger(subsystem: "io.github.lcalmsky.pulse", category: "scroll").error("no enclosing scroll view")
                return
            }
            DispatchQueue.main.async { self.found(scrollView) }
        }
    }
}
