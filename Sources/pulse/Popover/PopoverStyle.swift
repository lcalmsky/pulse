import AppKit
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

    /// `--glass` 의 RGB. 투명도 줄이기가 켜졌을 때 단색 배경으로 쓴다.
    static let glassSolid = dynamic(
        dark: rgb(0x1c, 0x1c, 0x22),
        light: rgb(0xf6, 0xf6, 0xfa)
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

/// 투명도 줄이기가 꺼져 있으면 NSPopover 의 기본 유리 머티리얼을 그대로 보여 준다.
/// 켜져 있으면 시안의 `--glass` RGB 로 단색을 채운다.
struct PopoverBackground: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        if reduceTransparency {
            PopoverPalette.glassSolid
        } else {
            Color.clear
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
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15))
                .frame(width: 26, height: 26)
                .foregroundColor(hovering && enabled || selected ? PopoverPalette.text : PopoverPalette.secondary)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(hovering && enabled || selected ? PopoverPalette.rowHover : Color.clear)
                )
                .contentShape(Rectangle())
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
