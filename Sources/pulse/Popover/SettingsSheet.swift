import PulseCore
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

            permissionNote

            HStack(spacing: 6) {
                Text("작업이 끝나면 알림 띄우기")
                    .font(.system(size: 12))
                    .foregroundColor(PopoverPalette.secondary)
                Spacer(minLength: 0)
                Toggle("", isOn: Binding(
                    get: { model.doneNotifications },
                    set: { model.setDoneNotifications($0) }
                ))
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
            }
            .padding(.horizontal, 2)
            .padding(.top, 8)
            .padding(.bottom, 10)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text("단축키")
                        .font(.system(size: 12))
                        .foregroundColor(PopoverPalette.secondary)
                    Spacer(minLength: 0)
                    KeyHint("⌃⌥P")
                        .opacity(model.hotKeyUnavailable ? 0.4 : 1)
                }
                Text(
                    model.hotKeyUnavailable
                        ? "단축키 ⌃⌥P 를 다른 앱이 쓰고 있어요"
                        : "한 번: 팝오버 · 열린 채로 한 번 더: 플로팅 패널"
                )
                .font(.system(size: 11))
                .foregroundColor(PopoverPalette.tertiary.opacity(model.hotKeyUnavailable ? 0.6 : 1))
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 2)
        }
        .onAppear { model.refreshNotificationPermission() }
        .padding(12)
        .frame(width: 260)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(PopoverPalette.strokeHi, lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.24), radius: 14, x: 0, y: 6)
    }

    @ViewBuilder
    private var permissionNote: some View {
        switch model.notificationPermission {
        case .notDetermined:
            permissionButton("알림 권한을 아직 받지 않았어요", action: "허용하기") {
                model.requestNotificationAuthorization()
            }
        case .denied:
            permissionButton("시스템 설정에서 알림이 꺼져 있어요", action: "설정 열기") {
                model.openNotificationSettings()
            }
        case .unknown, .authorized:
            EmptyView()
        }
    }

    private func permissionButton(
        _ text: String,
        action: String,
        _ run: @escaping () -> Void
    ) -> some View {
        Button(action: run) {
            HStack(spacing: 0) {
                Text(text)
                    .foregroundColor(PopoverPalette.tertiary)
                Text(" · ")
                    .foregroundColor(PopoverPalette.tertiary)
                Text(action)
                    .foregroundColor(.blue)
            }
            .font(.system(size: 11))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 2)
        .padding(.top, 4)
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
                    .foregroundColor(selected || hovering ? PopoverPalette.text : PopoverPalette.secondary)
            }
            .padding(.horizontal, 6)
            .padding(.top, 8)
            .padding(.bottom, 7)
            .frame(maxWidth: .infinity)
            .overlay(
                RoundedRectangle(cornerRadius: 9)
                    .stroke(
                        selected ? PopoverPalette.selection : (hovering ? PopoverPalette.strokeHi : PopoverPalette.stroke),
                        lineWidth: 1
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9)
                    .stroke(PopoverPalette.selection.opacity(selected ? 0.3 : 0), lineWidth: 2)
                    .padding(-2)
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
        .background(PopoverPalette.glassHi)
    }

    private func bar(width: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(PopoverPalette.secondary.opacity(0.5))
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
