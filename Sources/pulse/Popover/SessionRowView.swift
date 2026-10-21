import PulseCore
import SwiftUI

struct SessionRowView: View {
    let item: DisplayItem
    /// 행의 모양은 이 행이 놓인 섹션의 판정을 따른다.
    let group: DisplayGroup
    @ObservedObject var model: AppModel
    let selected: Bool
    let optionDown: Bool

    @State private var hovering = false

    private var compact: Bool { model.density == .compact }
    private var highlighted: Bool { hovering || selected }
    private var acknowledgeAction: PopoverRowAction { PopoverRowAction.resolve(item) }
    private var showsActions: Bool { highlighted && item.isActionable }
    private var showsOrca: Bool { item.orcaTerminal != nil || item.cwd != nil }
    private var showsPage: Bool { item.pagePath != nil }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                avatar
                VStack(alignment: .leading, spacing: 2) {
                    titleRow
                    if compact, group != .attention {
                        EmptyView()
                    } else {
                        subtitle
                    }
                    if !compact, let activity = item.activityLine {
                        Text(activity)
                            .font(.system(size: 10.5))
                            .foregroundColor(PopoverPalette.tertiary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .padding(.top, 1)
                    }
                    if !compact, group == .attention, let reply = item.replyTail {
                        quote(reply)
                    }
                    if !compact {
                        metadata
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .modifier(ReplyHelp(reply: group == .attention ? nil : item.replyTail))
            .contentShape(Rectangle())
            .onTapGesture {
                guard item.isActionable else { return }
                model.open(item)
            }

            VStack(alignment: .trailing, spacing: 6) {
                time
                if showsActions {
                    HStack(spacing: 2) {
                        if showsPage {
                            RowActionButton(
                                symbol: "doc.text",
                                help: "진행 페이지 (↩)"
                            ) {
                                model.openPage(item)
                            }
                        }
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
                .stroke(selected ? PopoverPalette.selection : Color.clear, lineWidth: 1.5)
        )
        .opacity(item.isActionable ? 1 : 0.45)
        .onHover { hovering = $0 }
    }

    @ViewBuilder
    private var avatar: some View {
        let side: CGFloat = compact ? 18 : 28
        switch group {
        case .attention:
            badgeAvatar("!", color: PopoverPalette.attention, side: side)
        case .working:
            WorkingAvatar(progress: item.progress?.fraction, size: side)
        case .done:
            badgeAvatar("✓", color: PopoverPalette.done, side: side)
        }
    }

    private func badgeAvatar(_ symbol: String, color: Color, side: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(color.opacity(0.18))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
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
                .foregroundColor(PopoverPalette.text)
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
            .foregroundColor(item.blocked ? PopoverPalette.attention : PopoverPalette.color(for: group))
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
                    .fill(PopoverPalette.glassHi)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(PopoverPalette.stroke, lineWidth: 1)
            )
            .padding(.top, 6)
    }

    @ViewBuilder
    private var metadata: some View {
        let tags = item.keyTag.map { [$0] } ?? []
        let pullRequest = item.prURL != nil ? item.prTag : nil
        let stripes = group == .working && item.progress == nil
        if item.progress != nil || stripes || !tags.isEmpty || item.jiraKey != nil
            || pullRequest != nil || !item.extraPRs.isEmpty {
            HStack(spacing: 5) {
                if let progress = item.progress {
                    ProgressBar(
                        fraction: progress.fraction,
                        tint: item.blocked ? PopoverPalette.attention : nil
                    )
                    .opacity(item.progressStale ? 0.45 : 1)
                    TagView(
                        text: progress.text,
                        color: item.blocked ? PopoverPalette.attention : PopoverPalette.secondary
                    )
                    .opacity(item.progressStale ? 0.45 : 1)
                } else if stripes {
                    StripedProgressBar()
                }
                ForEach(tags, id: \.self) { tag in
                    TagView(text: tag)
                }
                if let jiraKey = item.jiraKey {
                    if let href = item.jiraHref {
                        TagButton(text: jiraKey, help: "\(jiraKey) 열기") {
                            model.openLink(href)
                        }
                    } else {
                        TagView(text: jiraKey)
                    }
                }
                if let pullRequest, let url = item.prURL {
                    TagButton(text: pullRequest, help: "PR \(pullRequest) 열기") {
                        model.openPullRequest(url)
                    }
                }
                ForEach(item.extraPRs, id: \.url) { link in
                    let label = link.label ?? "#\(link.number)"
                    TagButton(text: label, help: "PR \(label) 열기") {
                        model.openPullRequest(link.url)
                    }
                }
            }
            .padding(.top, 5)
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
        if group == .attention {
            RoundedRectangle(cornerRadius: 3)
                .fill(PopoverPalette.attention)
                .frame(width: 3)
                .padding(.vertical, 10)
                .shadow(color: PopoverPalette.attention.opacity(0.6), radius: 5)
        }
    }

    @ViewBuilder
    private var rowBackground: some View {
        if group == .attention {
            LinearGradient(
                stops: [
                    .init(color: PopoverPalette.attention.opacity(highlighted ? 0.24 : 0.16), location: 0),
                    .init(color: highlighted ? PopoverPalette.rowHover : Color.clear, location: 0.7),
                    .init(color: highlighted ? PopoverPalette.rowHover : Color.clear, location: 1),
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        } else if highlighted {
            PopoverPalette.rowHover
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
                .font(.system(size: 15, weight: .medium))
                .frame(width: 24, height: 24)
                .foregroundColor(hovering ? PopoverPalette.text : PopoverPalette.secondary)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(hovering ? PopoverPalette.rowHover : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
    }
}

/// 체크리스트 수치가 없는 진행 중 행에 쓰는 줄무늬 막대.
/// 애니메이션은 막대 안쪽 그리기에만 걸어 레이아웃에 영향을 주지 않는다.
private struct StripedProgressBar: View {
    var body: some View {
        TimelineView(.animation) { context in
            let phase = context.date.timeIntervalSinceReferenceDate
                .truncatingRemainder(dividingBy: 1)
            Canvas { context, size in
                context.clip(
                    to: Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 2)
                )
                context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(PopoverPalette.working))
                let stripe: CGFloat = 6
                let period = stripe * 2
                var x = -period + CGFloat(phase) * period
                while x < size.width + period {
                    var path = Path()
                    path.move(to: CGPoint(x: x, y: size.height))
                    path.addLine(to: CGPoint(x: x + stripe, y: size.height))
                    path.addLine(to: CGPoint(x: x + stripe + size.height, y: 0))
                    path.addLine(to: CGPoint(x: x + size.height, y: 0))
                    path.closeSubpath()
                    context.fill(path, with: .color(PopoverPalette.purple.opacity(0.6)))
                    x += period
                }
            }
        }
        .frame(width: 64, height: 4)
    }
}

private struct ProgressBar: View {
    let fraction: Double
    var tint: Color?

    var body: some View {
        ZStack(alignment: .leading) {
            Capsule()
                .fill(PopoverPalette.stroke)
            Capsule()
                .fill(
                    LinearGradient(
                        colors: tint.map { [$0, $0] } ?? [PopoverPalette.working, PopoverPalette.purple],
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
    var color: Color = PopoverPalette.secondary

    var body: some View {
        Text(text)
            .font(.system(size: 10.5, design: .monospaced))
            .foregroundColor(color)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(PopoverPalette.glassHi)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .stroke(PopoverPalette.stroke, lineWidth: 1)
            )
    }
}

private struct TagButton: View {
    let text: String
    let help: String
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(text)
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundColor(hovering ? PopoverPalette.text : PopoverPalette.secondary)
                .lineLimit(1)
                .padding(.horizontal, 6)
                .frame(minWidth: 22, minHeight: 22)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(hovering ? PopoverPalette.rowHover : PopoverPalette.glassHi)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(PopoverPalette.stroke, lineWidth: 1)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
    }
}

/// 인용 상자는 「확인 필요」 행에만 그린다. 다른 행의 마지막 답은 호버 툴팁으로 보여 준다.
private struct ReplyHelp: ViewModifier {
    let reply: String?

    func body(content: Content) -> some View {
        if let reply, !reply.isEmpty {
            content.help(reply)
        } else {
            content
        }
    }
}

private struct WorkingAvatar: View {
    let progress: Double?
    let size: CGFloat

    var body: some View {
        if let progress {
            ZStack {
                Circle()
                    .stroke(PopoverPalette.stroke, lineWidth: size * 0.11)
                Circle()
                    .trim(from: 0, to: max(0.02, CGFloat(progress)))
                    .stroke(
                        PopoverPalette.working,
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

    // 무한 반복 애니메이션을 걸면 같은 트랜잭션의 레이아웃 변화까지 영원히 애니메이션해
    // 패널 내용이 계속 출렁인다. 각도는 시각에서 계산해 레이아웃에 애니메이션을 남기지 않는다.
    var body: some View {
        TimelineView(.animation) { context in
            let phase = context.date.timeIntervalSinceReferenceDate
                .truncatingRemainder(dividingBy: 1.1) / 1.1
            ZStack {
                Circle()
                    .stroke(PopoverPalette.stroke, lineWidth: size * 0.11)
                Circle()
                    .trim(from: 0, to: 0.28)
                    .stroke(
                        PopoverPalette.working,
                        style: StrokeStyle(lineWidth: size * 0.11, lineCap: .round)
                    )
                    .rotationEffect(.degrees(phase * 360 - 90))
            }
            .frame(width: size, height: size)
        }
    }
}
