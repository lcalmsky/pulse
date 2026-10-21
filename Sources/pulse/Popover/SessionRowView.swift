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
    private var showsOrca: Bool { item.orcaTerminal != nil || item.cwd != nil }
    private var showsPage: Bool { item.pagePath != nil }

    var body: some View {
        Group {
            switch group {
            case .attention: attentionCard
            case .working: workingRow
            case .done: doneRow
            }
        }
        .opacity(item.isActionable ? 1 : 0.45)
        .onHover { hovering = $0 }
    }

    // MARK: - 확인 필요

    private var attentionCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Circle()
                    .fill(PopoverPalette.attention)
                    .frame(width: 7, height: 7)
                Text(item.title)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundColor(PopoverPalette.text)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
                if let waiting = RowText.waiting(since: item.sortDate, now: Date()) {
                    Text(waiting)
                        .font(.system(size: 11))
                        .foregroundColor(PopoverPalette.attention)
                        .fixedSize()
                }
            }

            Text("“\(RowText.question(detail: item.detail, replyTail: item.replyTail, status: item.status))”")
                .font(.system(size: 12.5))
                .foregroundColor(PopoverPalette.text)
                .lineLimit(compact ? 2 : 6)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 15)

            HStack(spacing: 6) {
                if !attentionMeta.isEmpty {
                    Text(attentionMeta)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(PopoverPalette.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                Spacer(minLength: 0)
                PopoverIconButton(
                    symbol: "clock",
                    help: item.isStall ? "10분 더 기다리기" : "질문·권한 대기는 미룰 수 없어요",
                    enabled: item.isStall,
                    symbolSize: 13,
                    restingFill: PopoverPalette.rowHover,
                    restingGlyph: PopoverPalette.text
                ) {
                    model.snooze(item)
                }
                PopoverIconButton(
                    symbol: "arrow.up.forward.square",
                    help: "열기 (↩)",
                    enabled: item.isActionable,
                    symbolSize: 13,
                    restingFill: PopoverPalette.rowHover,
                    restingGlyph: PopoverPalette.text
                ) {
                    model.open(item)
                }
                PopoverIconButton(
                    symbol: "arrowshape.turn.up.left",
                    help: "답하기 · Orca 에서 터미널 열기 (⌥↩)",
                    enabled: showsOrca,
                    symbolSize: 13,
                    restingFill: PopoverPalette.attention,
                    restingGlyph: Color.black.opacity(0.85)
                ) {
                    model.openInOrca(item)
                }
            }
            .padding(.leading, 15)
        }
        .padding(.top, 9)
        .padding(.bottom, 9)
        .padding(.leading, 14)
        .padding(.trailing, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(PopoverPalette.attention.opacity(highlighted ? 0.14 : 0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(PopoverPalette.attention.opacity(0.28), lineWidth: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(selected ? PopoverPalette.selection : Color.clear, lineWidth: 1.5)
        )
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .onTapGesture {
            guard item.isActionable else { return }
            model.open(item)
        }
    }

    private var attentionMeta: String {
        var parts: [String] = []
        if let place = item.placeText { parts.append(place) }
        if let background = item.backgroundTaskCount, background > 0 {
            parts.append("bg \(background)")
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - 진행 중

    private var workingRow: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Circle()
                    .fill(item.blocked ? PopoverPalette.attention : PopoverPalette.working)
                    .frame(width: 7, height: 7)
                Text(item.title)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundColor(PopoverPalette.text)
                    .lineLimit(1)
                    .truncationMode(.tail)
                orcaHint
                Spacer(minLength: 0)
                workingRightSlot
            }

            stepperLine
            activityLine
            workingMetaLine
        }
        .padding(.top, 8)
        .padding(.bottom, 10)
        .padding(.horizontal, 14)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(highlighted ? PopoverPalette.rowHover : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(selected ? PopoverPalette.selection : Color.clear, lineWidth: 1.5)
        )
        .modifier(ReplyHelp(reply: item.replyTail))
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .onTapGesture {
            guard item.isActionable else { return }
            model.open(item)
        }
    }

    @ViewBuilder
    private var workingRightSlot: some View {
        if highlighted, item.isActionable {
            HStack(spacing: 2) {
                if showsPage {
                    PopoverIconButton(
                        symbol: "doc.text",
                        help: "진행 페이지 (↩)",
                        symbolSize: 13
                    ) {
                        model.openPage(item)
                    }
                }
                PopoverIconButton(
                    symbol: "arrow.up.forward.square",
                    help: "Orca 로 이동 (⌥↩)",
                    symbolSize: 13
                ) {
                    model.openInOrca(item)
                }
            }
            .frame(minHeight: 26)
        } else {
            timeText
                .frame(minHeight: 26, alignment: .trailing)
        }
    }

    @ViewBuilder
    private var stepperLine: some View {
        let segments = Stepper.segments(counts: item.counts, total: item.progress?.total)
        if !segments.isEmpty {
            HStack(spacing: 10) {
                stepBar(segments)
                HStack(spacing: 3) {
                    if let label = item.nowLabel {
                        Text(label)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(PopoverPalette.text)
                    }
                    if let position = Stepper.position(counts: item.counts, total: item.progress?.total) {
                        Text(position)
                            .font(.system(size: 12))
                            .foregroundColor(PopoverPalette.secondary)
                            .fixedSize()
                    }
                }
                .lineLimit(1)
                .truncationMode(.tail)
                Spacer(minLength: 0)
                if let eta = item.etaText {
                    Text(eta)
                        .font(.system(size: 11))
                        .foregroundColor(PopoverPalette.secondary)
                        .fixedSize()
                }
            }
            .padding(.leading, 15)
            .opacity(item.progressStale ? 0.45 : 1)
        }
    }

    private func stepBar(_ segments: [StepSegment]) -> some View {
        HStack(spacing: 2) {
            ForEach(segments.indices, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(segmentColor(segments[index]))
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(width: compact ? 84 : 108, height: 4)
    }

    private func segmentColor(_ segment: StepSegment) -> Color {
        switch segment {
        case .done: return PopoverPalette.working
        case .current: return PopoverPalette.working.opacity(0.45)
        case .blocked: return PopoverPalette.attention
        case .left: return PopoverPalette.strokeHi
        }
    }

    @ViewBuilder
    private var activityLine: some View {
        if !compact, let activity = RowText.activity(lastSentence: item.lastSentence, nowLine: item.nowLine) {
            Text("“\(activity)”")
                .font(.system(size: 12))
                .foregroundColor(PopoverPalette.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.leading, 15)
        }
    }

    @ViewBuilder
    private var workingMetaLine: some View {
        if hasWorkingMeta {
            HStack(spacing: 10) {
                if let place = item.placeText {
                    Text(place)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                if let keyTag = item.keyTag, keyTag != item.jiraKey {
                    Text(keyTag)
                        .fixedSize()
                }
                jiraKeyView
                prView
                ForEach(item.extraPRs, id: \.url) { link in
                    let label = link.label ?? "#\(link.number)"
                    MetaLink(text: label, help: "PR \(label) 열기") {
                        model.openPullRequest(link.url)
                    }
                }
                Spacer(minLength: 0)
                if let trail = RowText.trail(
                    backgroundTasks: item.backgroundTaskCount,
                    lastTool: item.lastToolName
                ) {
                    Text(trail)
                        .fixedSize()
                }
                if !item.isActionable {
                    Text("터미널 없음")
                        .foregroundColor(PopoverPalette.tertiary)
                        .fixedSize()
                }
            }
            .font(.system(size: 11, design: .monospaced))
            .foregroundColor(PopoverPalette.secondary)
            .lineLimit(1)
            .padding(.leading, 15)
        }
    }

    private var hasWorkingMeta: Bool {
        item.placeText != nil
            || (item.keyTag != nil && item.keyTag != item.jiraKey)
            || item.jiraKey != nil
            || (item.prTag != nil && item.prURL != nil)
            || !item.extraPRs.isEmpty
            || RowText.trail(backgroundTasks: item.backgroundTaskCount, lastTool: item.lastToolName) != nil
            || !item.isActionable
    }

    @ViewBuilder
    private var jiraKeyView: some View {
        if let key = item.jiraKey {
            if let href = item.jiraHref {
                MetaLink(text: key, help: "\(key) 열기") {
                    model.openLink(href)
                }
            } else {
                Text(key)
                    .fixedSize()
            }
        }
    }

    @ViewBuilder
    private var prView: some View {
        if let tag = item.prTag, let url = item.prURL {
            MetaLink(text: tag, help: "PR \(tag) 열기") {
                model.openPullRequest(url)
            }
        }
    }

    // MARK: - 완료

    private var doneRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(PopoverPalette.done)
            Text(item.title)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(PopoverPalette.text)
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(1)
            if let place = item.placeText {
                Text(place)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(PopoverPalette.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            prView
            orcaHint
            Spacer(minLength: 0)
            doneRightSlot
        }
        .padding(.vertical, 7)
        .padding(.leading, 14)
        .padding(.trailing, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(highlighted ? PopoverPalette.rowHover : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(selected ? PopoverPalette.selection : Color.clear, lineWidth: 1.5)
        )
        .modifier(ReplyHelp(reply: item.replyTail))
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .onTapGesture {
            guard item.isActionable else { return }
            model.open(item)
        }
    }

    @ViewBuilder
    private var doneRightSlot: some View {
        if highlighted {
            HStack(spacing: 2) {
                if item.isActionable {
                    PopoverIconButton(
                        symbol: "arrow.up.forward.square",
                        help: "열기 (↩)",
                        symbolSize: 13,
                        restingFill: PopoverPalette.rowHover,
                        restingGlyph: PopoverPalette.text
                    ) {
                        model.open(item)
                    }
                }
                PopoverIconButton(
                    symbol: "checkmark",
                    help: "확인 (⌫)",
                    symbolSize: 13,
                    restingFill: PopoverPalette.rowHover,
                    restingGlyph: PopoverPalette.text
                ) {
                    model.acknowledge(item)
                }
            }
            .frame(minHeight: 26)
        } else {
            timeText
                .frame(minHeight: 26, alignment: .trailing)
        }
    }

    // MARK: - 공통

    @ViewBuilder
    private var orcaHint: some View {
        if optionDown, item.isActionable, showsOrca {
            Text("→ Orca 로 이동")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundColor(.blue)
                .lineLimit(1)
                .fixedSize()
        }
    }

    @ViewBuilder
    private var timeText: some View {
        if let text = TimePhrase.relative(from: item.sortDate, to: Date()) {
            Text(text)
                .font(.system(size: 11))
                .monospacedDigit()
                .foregroundColor(PopoverPalette.secondary)
                .lineLimit(1)
                .fixedSize()
        }
    }
}

/// 섹션 머리. 팝오버와 플로팅 패널이 같은 모양으로 쓴다.
struct SessionSectionLabel: View {
    let group: DisplayGroup
    @ObservedObject var model: AppModel
    /// 첫 섹션은 위 여백 없이 붙인다.
    var topPadding: CGFloat = 14

    var body: some View {
        HStack(spacing: 0) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(group == .attention ? PopoverPalette.attention : PopoverPalette.secondary)
            Spacer(minLength: 0)
            if group == .done {
                Button("모두 확인") {
                    model.acknowledgeAllDone()
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(PopoverPalette.link)
                .contentShape(Rectangle())
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, topPadding)
        .padding(.bottom, 6)
    }

    private var title: String {
        switch group {
        case .attention: return "확인 필요"
        case .working: return "진행 중"
        case .done: return "완료"
        }
    }
}

private struct MetaLink: View {
    let text: String
    let help: String
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(text)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(hovering ? PopoverPalette.text : PopoverPalette.link)
                .underline(hovering)
                .lineLimit(1)
                .fixedSize()
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
    }
}

/// 확인 필요가 아닌 행의 마지막 답은 호버 툴팁으로 보여 준다.
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
