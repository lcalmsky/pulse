import PulseCore
import SwiftUI

/// 팝오버와 플로팅 패널이 함께 쓰는 머리글. 제목 줄 아래에 그룹별 뱃지를 둔다.
struct PopoverHeader: View {
    @ObservedObject var model: AppModel
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                PulseLogo(counts: model.groups.counts)
                    .frame(width: 18, height: 18)
                    .padding(.trailing, 7)
                Text("Pulse")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(PopoverPalette.text)
                    .lineLimit(1)
                Spacer(minLength: 4)
                PopoverIconButton(
                    symbol: model.collapsed ? "chevron.down" : "chevron.up",
                    help: model.collapsed ? L10n.expand : L10n.collapse,
                    symbolSize: 12
                ) {
                    model.collapsed.toggle()
                }
                PopoverIconButton(symbol: "xmark", help: L10n.close, symbolSize: 12, action: onClose)
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

/// 머리글 로고. 파형은 메뉴 막대 아이콘과 같은 꼭짓점을 쓴다.
struct PulseLogo: View {
    let counts: GroupedSessions.Counts

    private static let lineRatio: CGFloat = 0.13
    private static let radiusRatio = (1 - lineRatio) / 2

    private var waveStyle: AnyShapeStyle {
        let palette = [PopoverPalette.attention, PopoverPalette.working, PopoverPalette.done]
        let stops = PulseGlyph.stops(counts: counts)
        switch stops.count {
        case 0: return AnyShapeStyle(PopoverPalette.text)
        case 1: return AnyShapeStyle(palette[stops[0].group])
        default:
            let first = 0.5 + PulseGlyph.wave.first!.x * Self.radiusRatio
            let last = 0.5 + PulseGlyph.wave.last!.x * Self.radiusRatio
            return AnyShapeStyle(LinearGradient(
                stops: stops.map { .init(color: palette[$0.group], location: $0.location) },
                startPoint: UnitPoint(x: first, y: 0.5),
                endPoint: UnitPoint(x: last, y: 0.5)
            ))
        }
    }

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let line = side * Self.lineRatio
            let radius = (side - line) / 2
            ZStack {
                Circle()
                    .stroke(
                        AngularGradient(
                            colors: [PopoverPalette.working, PopoverPalette.purple, PopoverPalette.working],
                            center: .center
                        ),
                        lineWidth: line
                    )
                    .frame(width: radius * 2, height: radius * 2)
                Path { path in
                    let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
                    for (index, point) in PulseGlyph.wave.enumerated() {
                        let target = CGPoint(x: center.x + point.x * radius, y: center.y - point.y * radius)
                        if index == 0 { path.move(to: target) } else { path.addLine(to: target) }
                    }
                }
                .stroke(waveStyle, style: StrokeStyle(lineWidth: side * 0.085, lineCap: .round, lineJoin: .round))
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }
}
