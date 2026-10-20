import DeadhdBarCore
import SwiftUI

enum PopoverPalette {
    static let secondary = Color(nsColor: .secondaryLabelColor)
    static let tertiary = Color(nsColor: .tertiaryLabelColor)

    static func color(for group: DisplayGroup) -> Color {
        switch group {
        case .attention: return .orange
        case .working: return .blue
        case .done: return .green
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
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .foregroundColor(PopoverPalette.secondary)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.06)))
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.primary.opacity(0.10), lineWidth: 1)
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
                .font(.system(size: 13))
                .frame(width: 26, height: 26)
                .foregroundColor(hovering && enabled || selected ? .primary : PopoverPalette.secondary)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(hovering && enabled || selected ? Color.primary.opacity(0.07) : Color.clear)
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
                    .font(.system(size: 12))
                Text(title)
                    .font(.system(size: 12, weight: .medium))
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .foregroundColor(
                enabled
                    ? (hovering ? .primary : PopoverPalette.secondary)
                    : PopoverPalette.secondary.opacity(0.35)
            )
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(hovering && enabled ? Color.primary.opacity(0.07) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .onHover { hovering = $0 }
        .help(help)
    }
}
