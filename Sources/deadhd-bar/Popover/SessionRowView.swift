import DeadhdBarCore
import SwiftUI

struct SessionRowView: View {
    let item: DisplayItem
    @ObservedObject var model: AppModel
    let selected: Bool
    let optionDown: Bool

    @State private var hovering = false

    private var compact: Bool { model.density == .compact }
    private var highlighted: Bool { hovering || selected }
    private var acknowledgeAction: PopoverRowAction { PopoverRowAction.resolve(item) }
    private var showsActions: Bool { highlighted && item.isActionable }
    private var showsOrca: Bool { item.orcaTerminal != nil || item.cwd != nil }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                avatar
                VStack(alignment: .leading, spacing: 2) {
                    titleRow
                    if compact, item.group != .attention {
                        EmptyView()
                    } else {
                        subtitle
                    }
                    if !compact, let reply = item.replyTail {
                        quote(reply)
                    }
                    if !compact {
                        metadata
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                guard item.isActionable else { return }
                model.open(item)
            }

            VStack(alignment: .trailing, spacing: 6) {
                time
                if showsActions {
                    HStack(spacing: 2) {
                        if showsOrca {
                            RowActionButton(
                                symbol: "arrow.up.right.square",
                                help: "Orca 로 이동 (⌥↩)"
                            ) {
                                model.openInOrca(item)
                            }
                        }
                        if acknowledgeAction != .none {
                            RowActionButton(
                                symbol: "checkmark",
                                help: acknowledgeAction == .snooze ? "더 기다리기 (⌫)" : "확인 (⌫)"
                            ) {
                                model.acknowledge(item)
                            }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, compact ? 6 : 9)
        .background(rowBackground)
        .overlay(alignment: .leading) { attentionBar }
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .overlay(
            RoundedRectangle(cornerRadius: 9)
                .stroke(selected ? Color.accentColor.opacity(0.9) : Color.clear, lineWidth: 1.5)
        )
        .opacity(item.isActionable ? 1 : 0.45)
        .onHover { hovering = $0 }
    }

    @ViewBuilder
    private var avatar: some View {
        let side: CGFloat = compact ? 18 : 28
        switch item.group {
        case .attention:
            badgeAvatar("!", color: .orange, side: side)
        case .working:
            WorkingAvatar(progress: item.progress?.fraction, size: side)
        case .done:
            badgeAvatar("✓", color: .green, side: side)
        }
    }

    private func badgeAvatar(_ symbol: String, color: Color, side: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: side * 0.28)
            .fill(color.opacity(0.18))
            .overlay(
                RoundedRectangle(cornerRadius: side * 0.28)
                    .stroke(color.opacity(0.4), lineWidth: 1)
            )
            .overlay(
                Text(symbol)
                    .font(.system(size: compact ? 9 : 12, weight: .heavy))
                    .foregroundColor(color)
            )
            .frame(width: side, height: side)
    }

    private var titleRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(item.title)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.tail)
            if optionDown, item.isActionable, showsOrca {
                Text("→ Orca 로 이동")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundColor(.blue)
                    .lineLimit(1)
                    .fixedSize()
            }
            Spacer(minLength: 0)
        }
    }

    private var subtitle: some View {
        subtitleText
            .lineLimit(1)
            .truncationMode(.tail)
    }

    private var subtitleText: Text {
        var text = Text(item.status)
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundColor(PopoverPalette.color(for: item.group))
        if let place = item.placeText {
            text = text + Text(" · \(place)")
                .font(.system(size: 11.5))
                .foregroundColor(PopoverPalette.secondary)
        }
        if !item.isActionable {
            text = text + Text(" · 터미널 없음")
                .font(.system(size: 11.5))
                .foregroundColor(PopoverPalette.tertiary)
        }
        return text
    }

    private func quote(_ reply: String) -> some View {
        Text("“\(reply)”")
            .font(.system(size: 11.5))
            .foregroundColor(PopoverPalette.secondary)
            .lineLimit(2)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(Color.primary.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
            .padding(.top, 4)
    }

    @ViewBuilder
    private var metadata: some View {
        let tags = item.key.map { [$0] } ?? []
        if item.progress != nil || !tags.isEmpty {
            HStack(spacing: 5) {
                if let progress = item.progress {
                    ProgressBar(fraction: progress.fraction)
                    Text(progress.text)
                        .font(.system(size: 10.5, weight: .medium))
                        .monospacedDigit()
                        .foregroundColor(PopoverPalette.secondary)
                }
                ForEach(tags, id: \.self) { tag in
                    TagView(text: tag)
                }
            }
            .padding(.top, 3)
        }
    }

    private var time: some View {
        Group {
            if let text = TimePhrase.relative(from: item.sortDate, to: Date()) {
                Text(text)
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundColor(PopoverPalette.tertiary)
                    .lineLimit(1)
            }
        }
    }

    @ViewBuilder
    private var attentionBar: some View {
        if item.group == .attention {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.orange)
                .frame(width: 3)
                .padding(.vertical, 9)
        }
    }

    @ViewBuilder
    private var rowBackground: some View {
        if item.group == .attention {
            LinearGradient(
                stops: [
                    .init(color: Color.orange.opacity(highlighted ? 0.24 : 0.16), location: 0),
                    .init(color: highlighted ? Color.primary.opacity(0.07) : Color.clear, location: 0.7),
                    .init(color: highlighted ? Color.primary.opacity(0.07) : Color.clear, location: 1),
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        } else if highlighted {
            Color.primary.opacity(0.07)
        } else {
            Color.clear
        }
    }
}

private struct RowActionButton: View {
    let symbol: String
    let help: String
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 24, height: 24)
                .foregroundColor(hovering ? .primary : PopoverPalette.secondary)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(hovering ? Color.primary.opacity(0.08) : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
    }
}

private struct ProgressBar: View {
    let fraction: Double

    var body: some View {
        ZStack(alignment: .leading) {
            Capsule()
                .fill(Color.primary.opacity(0.12))
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [.blue, .purple],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: 64 * CGFloat(min(max(fraction, 0), 1)))
        }
        .frame(width: 64, height: 4)
    }
}

private struct TagView: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 10.5, design: .monospaced))
            .foregroundColor(PopoverPalette.secondary)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color.primary.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
    }
}

private struct WorkingAvatar: View {
    let progress: Double?
    let size: CGFloat

    var body: some View {
        if let progress {
            ZStack {
                Circle()
                    .stroke(Color.primary.opacity(0.10), lineWidth: size * 0.11)
                Circle()
                    .trim(from: 0, to: max(0.02, CGFloat(progress)))
                    .stroke(
                        Color.blue,
                        style: StrokeStyle(lineWidth: size * 0.11, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: size, height: size)
        } else {
            SpinningAvatar(size: size)
        }
    }
}

private struct SpinningAvatar: View {
    let size: CGFloat

    @State private var spinning = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.10), lineWidth: size * 0.11)
            Circle()
                .trim(from: 0, to: 0.28)
                .stroke(
                    Color.blue,
                    style: StrokeStyle(lineWidth: size * 0.11, lineCap: .round)
                )
                .rotationEffect(.degrees(spinning ? 270 : -90))
        }
        .frame(width: size, height: size)
        .onAppear {
            withAnimation(.linear(duration: 1.1).repeatForever(autoreverses: false)) {
                spinning = true
            }
        }
    }
}
