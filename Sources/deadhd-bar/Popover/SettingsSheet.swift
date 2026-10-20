import DeadhdBarCore
import SwiftUI

struct SettingsSheet: View {
    @ObservedObject var model: AppModel
    @ObservedObject var state: PopoverState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                Text("밀도")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(PopoverPalette.tertiary)
                Spacer(minLength: 0)
                PopoverIconButton(symbol: "xmark", help: "닫기") {
                    state.settingsOpen = false
                }
            }
            .padding(.bottom, 2)

            HStack(spacing: 6) {
                SettingsOptionCard(
                    title: "풍부",
                    selected: model.density == .rich,
                    action: { model.setDensity(.rich) }
                ) {
                    DensityPreview(compact: false)
                }
                SettingsOptionCard(
                    title: "간결",
                    selected: model.density == .compact,
                    action: { model.setDensity(.compact) }
                ) {
                    DensityPreview(compact: true)
                }
            }
            .padding(.bottom, 12)

            Text("테마")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(PopoverPalette.tertiary)
                .padding(.horizontal, 2)
                .padding(.bottom, 6)

            HStack(spacing: 6) {
                ForEach(ThemePreference.allCases, id: \.self) { theme in
                    SettingsOptionCard(
                        title: theme.title,
                        selected: model.theme == theme,
                        action: { model.setTheme(theme) }
                    ) {
                        ThemePreview(theme: theme)
                    }
                }
            }
            .padding(.bottom, 12)

            HStack(spacing: 6) {
                Text("확인 필요 알림 띄우기")
                    .font(.system(size: 12))
                    .foregroundColor(PopoverPalette.secondary)
                Spacer(minLength: 0)
                Toggle("", isOn: Binding(
                    get: { model.attentionNotifications },
                    set: { model.setAttentionNotifications($0) }
                ))
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
            }
            .padding(.horizontal, 2)
        }
        .padding(12)
        .frame(width: 260)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.primary.opacity(0.14), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.24), radius: 14, x: 0, y: 6)
    }
}

private extension ThemePreference {
    var title: String {
        switch self {
        case .system: return "시스템"
        case .light: return "라이트"
        case .dark: return "다크"
        }
    }
}

private struct SettingsOptionCard<Preview: View>: View {
    let title: String
    let selected: Bool
    let action: () -> Void
    private let preview: () -> Preview

    @State private var hovering = false

    init(
        title: String,
        selected: Bool,
        action: @escaping () -> Void,
        @ViewBuilder preview: @escaping () -> Preview
    ) {
        self.title = title
        self.selected = selected
        self.action = action
        self.preview = preview
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                preview()
                    .frame(height: 34)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                Text(title)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundColor(selected || hovering ? .primary : PopoverPalette.secondary)
            }
            .padding(.horizontal, 6)
            .padding(.top, 8)
            .padding(.bottom, 7)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 9)
                    .fill(selected ? Color.primary.opacity(0.06) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9)
                    .stroke(
                        selected ? Color.accentColor : Color.primary.opacity(hovering ? 0.24 : 0.12),
                        lineWidth: selected ? 1.5 : 1
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

private struct DensityPreview: View {
    let compact: Bool

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width - 10
            VStack(alignment: .leading, spacing: 3) {
                bar(width: width)
                bar(width: compact ? width : width * 0.6)
                bar(width: compact ? width : width * 0.6)
            }
            .frame(maxHeight: .infinity)
            .padding(5)
        }
        .background(Color.primary.opacity(0.06))
    }

    private func bar(width: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(Color.primary.opacity(0.35))
            .frame(width: max(0, width), height: 4)
    }
}

private struct ThemePreview: View {
    let theme: ThemePreference

    private static let lightBackground = Color(red: 0xf2 / 255, green: 0xf2 / 255, blue: 0xf6 / 255)
    private static let darkBackground = Color(red: 0x1d / 255, green: 0x1d / 255, blue: 0x24 / 255)

    var body: some View {
        ZStack {
            background
            if theme != .system {
                GeometryReader { geometry in
                    let width = geometry.size.width - 10
                    VStack(alignment: .leading, spacing: 3) {
                        bar(width: width, opacity: 0.5)
                        bar(width: width * 0.6, opacity: 0.3)
                    }
                    .frame(maxHeight: .infinity)
                    .padding(5)
                }
            }
        }
    }

    @ViewBuilder
    private var background: some View {
        switch theme {
        case .light:
            Self.lightBackground
        case .dark:
            Self.darkBackground
        case .system:
            LinearGradient(
                stops: [
                    .init(color: Self.lightBackground, location: 0),
                    .init(color: Self.lightBackground, location: 0.5),
                    .init(color: Self.darkBackground, location: 0.5),
                    .init(color: Self.darkBackground, location: 1),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private var lineColor: Color {
        theme == .dark ? .white : Color(red: 0x22 / 255, green: 0x22 / 255, blue: 0x22 / 255)
    }

    private func bar(width: CGFloat, opacity: Double) -> some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(lineColor.opacity(opacity))
            .frame(width: max(0, width), height: 4)
    }
}
