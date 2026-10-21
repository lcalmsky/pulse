import PulseCore
import SwiftUI

/// 팝오버와 플로팅 패널이 함께 쓰는 머리글. 제목 줄 아래에 그룹별 뱃지를 둔다.
struct PopoverHeader: View {
    @ObservedObject var model: AppModel
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                Text("Claude 세션")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(PopoverPalette.text)
                    .lineLimit(1)
                Spacer(minLength: 4)
                PopoverIconButton(
                    symbol: model.collapsed ? "chevron.down" : "chevron.up",
                    help: model.collapsed ? "펼치기" : "접기",
                    symbolSize: 12
                ) {
                    model.collapsed.toggle()
                }
                PopoverIconButton(symbol: "xmark", help: "닫기", symbolSize: 12, action: onClose)
            }
            .padding(.top, 12)
            .padding(.leading, 14)
            .padding(.trailing, 10)
            .padding(.bottom, 4)

            if model.sessionsUnavailable {
                Color.clear.frame(height: 8)
            } else {
                HStack(spacing: 6) {
                    badge(.attention)
                    badge(.working)
                    badge(.done)
                }
                .padding(.horizontal, 14)
                .padding(.top, 4)
                .padding(.bottom, 12)
            }
        }
    }

    private func badge(_ group: DisplayGroup) -> some View {
        let count = model.groups.items(for: group).count
        let tone = HeaderBadge.tone(for: group, count: count)
        let accent = color(for: tone)
        return HStack(spacing: 5) {
            Circle()
                .fill(accent)
                .frame(width: 6, height: 6)
            Text(HeaderBadge.label(for: group, count: count))
                .font(.system(size: 11, weight: group == .attention ? .semibold : .medium))
                .foregroundColor(tone == .muted ? PopoverPalette.secondary : PopoverPalette.text)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 3)
        .background(Capsule().fill(background(for: tone)))
    }

    private func color(for tone: BadgeTone) -> Color {
        switch tone {
        case .attention: return PopoverPalette.attention
        case .working: return PopoverPalette.working
        case .done: return PopoverPalette.done
        case .muted: return PopoverPalette.tertiary
        }
    }

    private func background(for tone: BadgeTone) -> Color {
        switch tone {
        case .attention: return PopoverPalette.attention.opacity(0.16)
        case .working: return PopoverPalette.working.opacity(0.16)
        case .done: return PopoverPalette.done.opacity(0.16)
        case .muted: return PopoverPalette.glassHi
        }
    }
}
