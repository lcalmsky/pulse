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
    @State private var stepHovering = false

    private var compact: Bool { model.density == .compact }
    private var highlighted: Bool { hovering || selected }
    private var showsOrca: Bool { item.orcaTerminal != nil || item.cwd != nil }
    private var showsPage: Bool { item.pagePath != nil }
    private var expanded: Bool { model.expandedSteps.contains(item.sessionId) }
    /// 진행 행은 터미널이 없어도 단계 펼침이나 브라우저 열기가 되면 흐리지 않는다.
    private var dimmed: Bool {
        !item.isActionable && !(group == .working && (item.pagePath != nil || item.dataPath != nil)) && !item.showsStepLine
    }

    var body: some View {
        Group {
            switch group {
            case .attention: attentionCard
            case .working: workingRow
            case .done: doneRow
            }
        }
        .opacity(dimmed ? 0.45 : 1)
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
                    help: item.isStall ? L10n.waitTenMoreMinutes : L10n.cannotSnoozeQuestion,
                    enabled: item.isStall,
                    symbolSize: 13,
                    restingFill: PopoverPalette.rowHover,
                    restingGlyph: PopoverPalette.text
                ) {
                    model.snooze(item)
                }
                PopoverIconButton(
                    symbol: "arrow.up.forward.square",
                    help: L10n.openShortcut,
                    enabled: item.isActionable,
                    symbolSize: 13,
                    restingFill: PopoverPalette.rowHover,
                    restingGlyph: PopoverPalette.text
                ) {
                    model.open(item)
                }
                PopoverIconButton(
                    symbol: "arrowshape.turn.up.left",
                    help: L10n.replyInOrcaShortcut,
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
            if expanded {
                StepPanel(item: item, model: model, full: model.fullSteps.contains(item.sessionId))
            }
            activityLine
            workingMetaLine
        }
        .padding(.top, 8)
        .padding(.bottom, 10)
        .padding(.horizontal, 14)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(highlighted ? PopoverPalette.rowHover : (expanded ? PopoverPalette.stepPanel : Color.clear))
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

    @ViewBuilder
    private var workingRightSlot: some View {
        if highlighted, showsPage || showsOrca {
            HStack(spacing: 2) {
                if showsPage {
                    PopoverIconButton(
                        symbol: "doc.text",
                        help: L10n.openProgressPage,
                        symbolSize: 13
                    ) {
                        model.openPageInBrowser(item)
                    }
                }
                if showsOrca {
                    PopoverIconButton(
                        symbol: "arrow.up.forward.square",
                        help: L10n.goToOrcaShortcut,
                        symbolSize: 13
                    ) {
                        model.openInOrca(item)
                    }
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
        let segments = Stepper.segments(
            states: item.stepStates,
            counts: item.counts,
            total: item.progress?.total
        )
        if item.showsStepLine {
            Button {
                model.toggleSteps(item)
            } label: {
                // plain 스타일은 그려진 획만 클릭되므로 줄 전체를 클릭 영역으로 잡는다.
                stepperContent(segments)
                    .background(
                        RoundedRectangle(cornerRadius: 7)
                            .fill(stepHovering ? PopoverPalette.rowHover : Color.clear)
                            .padding(.leading, 9)
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { stepHovering = $0 }
            .help(expanded ? L10n.collapseSteps : L10n.expandSteps)
            .accessibilityValue(stepDisclosureText)
        } else if !segments.isEmpty {
            stepperContent(segments)
        }
    }

    private var stepDisclosureText: String {
        guard expanded else { return L10n.stepsCollapsed }
        return model.fullSteps.contains(item.sessionId) ? L10n.stepsAll : L10n.stepsThree
    }

    private func stepperContent(_ segments: [StepSegment]) -> some View {
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
            if item.dataPath != nil {
                Image(systemName: expanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(expanded || stepHovering || selected ? PopoverPalette.text : PopoverPalette.secondary)
                    .frame(width: 22, height: 22)
            }
        }
        .frame(minHeight: 22)
        .padding(.leading, 15)
        .opacity(item.progressStale ? 0.45 : 1)
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
                .modifier(ReplyHelp(reply: item.replyTail))
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
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                jiraKeyView
                prView
                ForEach(item.extraPRs, id: \.url) { link in
                    let label = link.label ?? "#\(link.number)"
                    MetaLink(text: label, help: L10n.openPR(label)) {
                        model.openPullRequest(link.url)
                    }
                }
                Spacer(minLength: 0)
                if let trail = RowText.trail(
                    backgroundTasks: item.backgroundTaskCount,
                    lastTool: item.lastToolName
                ) {
                    Text(trail)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .layoutPriority(1)
                }
                if !item.isActionable {
                    Text(L10n.noTerminal)
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
                MetaLink(text: key, help: L10n.openKey(key)) {
                    model.openLink(href)
                }
            } else {
                Text(key)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
    }

    @ViewBuilder
    private var prView: some View {
        if let tag = item.prTag, let url = item.prURL {
            MetaLink(text: tag, help: L10n.openPR(tag)) {
                model.openPullRequest(url)
            }
        }
    }

    // MARK: - 완료

    private var doneRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            doneTitleLine
            if item.showsStepLine {
                stepperLine
                    .padding(.leading, 7)
                if doneStepsOpen {
                    StepPanel(item: item, model: model, full: model.fullSteps.contains(item.sessionId))
                        .padding(.leading, 7)
                }
            }
        }
        .padding(.vertical, 7)
        .padding(.leading, 14)
        .padding(.trailing, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(highlighted ? PopoverPalette.rowHover : (doneStepsOpen ? PopoverPalette.stepPanel : Color.clear))
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

    /// 진행 중에 펼친 행이 체크리스트를 다 끝내고 완료로 넘어오면 펼침 기록만 남으므로 단계 줄이 있을 때만 쓴다.
    private var doneStepsOpen: Bool { expanded && item.showsStepLine }

    private var doneTitleLine: some View {
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
    }

    @ViewBuilder
    private var doneRightSlot: some View {
        if highlighted {
            HStack(spacing: 2) {
                if item.isActionable {
                    PopoverIconButton(
                        symbol: "arrow.up.forward.square",
                        help: L10n.openShortcut,
                        symbolSize: 13,
                        restingFill: PopoverPalette.rowHover,
                        restingGlyph: PopoverPalette.text
                    ) {
                        model.open(item)
                    }
                }
                PopoverIconButton(
                    symbol: "checkmark",
                    help: L10n.acknowledgeShortcut,
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
            Text(L10n.goToOrcaArrow)
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
                Button(L10n.acknowledgeAll) {
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
        case .attention: return L10n.groupAttention
        case .working: return L10n.groupWorking
        case .done: return L10n.groupDone
        }
    }
}

/// 진행 행 아래에 펼치는 단계 목록. 창 상태에서는 세 줄, 전체 상태에서는 모든 줄을 그린다.
private struct StepPanel: View {
    let item: DisplayItem
    @ObservedObject var model: AppModel
    let full: Bool

    private static let clock: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private var snapshot: ChecklistSnapshot? { model.checklists[item.sessionId] }

    var body: some View {
        VStack(spacing: 0) {
            content
            footer
        }
        .padding(.top, 4)
        .padding(.bottom, 4)
        .padding(.horizontal, 8)
        .background(RoundedRectangle(cornerRadius: 8).fill(PopoverPalette.stepPanel))
        .padding(.leading, 15)
        .padding(.top, 2)
        .contentShape(Rectangle())
        .onTapGesture {}
    }

    @ViewBuilder
    private var content: some View {
        if let steps = snapshot?.steps {
            if steps.isEmpty {
                emptyLine(L10n.noStepsYet)
            } else {
                let window = StepWindow.make(steps.map(\.state))
                if full {
                    headLine(text: L10n.allStepsCollapse(window.total), up: true, help: L10n.showThreeSteps)
                } else if let text = StepWindow.headText(steps, window: window) {
                    headLine(text: text, up: false, help: L10n.showAllStepsHelp)
                }
                ForEach(full ? Array(steps.indices) : window.rows, id: \.self) { index in
                    stepRow(steps[index], index: index, steps: steps)
                }
            }
        } else {
            emptyLine(L10n.stepsUnreadable)
        }
    }

    private func headLine(text: String, up: Bool, help: String) -> some View {
        Button {
            model.toggleFullSteps(item)
        } label: {
            HStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(PopoverPalette.done.opacity(0.6))
                    .frame(width: 2, height: 12)
                    .frame(width: 12)
                Text(text)
                    .font(.system(size: 11))
                    .foregroundColor(PopoverPalette.tertiary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: up ? "chevron.up" : "chevron.down")
                    .font(.system(size: 9))
                    .foregroundColor(PopoverPalette.tertiary)
            }
            .frame(height: 20)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func emptyLine(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundColor(PopoverPalette.secondary)
            .frame(maxWidth: .infinity, minHeight: 20, alignment: .leading)
    }

    private func stepRow(_ step: ChecklistStep, index: Int, steps: [ChecklistStep]) -> some View {
        HStack(spacing: 8) {
            icon(step.state)
                .frame(width: 12, height: 12)
            Text(step.label)
                .font(.system(size: 12, weight: step.state == .now ? .semibold : .regular))
                .foregroundColor(labelColor(step.state))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let trailing = StepWindow.trailingText(steps, index: index) {
                Text(trailing)
                    .font(.system(size: 11, weight: step.state == .now ? .medium : .regular))
                    .foregroundColor(trailingColor(step.state))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .frame(height: step.state == .now ? 22 : 20)
    }

    @ViewBuilder
    private func icon(_ state: StepState) -> some View {
        switch state {
        case .done:
            ZStack {
                Circle()
                    .fill(PopoverPalette.done)
                    .frame(width: 11, height: 11)
                Image(systemName: "checkmark")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundColor(PopoverPalette.glassSolid)
            }
        case .now:
            Circle()
                .stroke(PopoverPalette.working, lineWidth: 2)
                .frame(width: 9, height: 9)
        case .side:
            Circle()
                .stroke(PopoverPalette.working.opacity(0.6), lineWidth: 1.5)
                .frame(width: 9, height: 9)
        case .left:
            Circle()
                .stroke(PopoverPalette.tertiary, lineWidth: 1.5)
                .frame(width: 9, height: 9)
        case .blocked:
            Circle()
                .fill(PopoverPalette.attention)
                .frame(width: 8, height: 8)
        }
    }

    private func labelColor(_ state: StepState) -> Color {
        switch state {
        case .done, .side: return PopoverPalette.secondary
        case .now, .blocked: return PopoverPalette.text
        case .left: return PopoverPalette.tertiary
        }
    }

    private func trailingColor(_ state: StepState) -> Color {
        switch state {
        case .now: return PopoverPalette.working
        case .blocked: return PopoverPalette.attention
        default: return PopoverPalette.tertiary
        }
    }

    private var footer: some View {
        HStack(spacing: 0) {
            Text(updatedText)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(PopoverPalette.tertiary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .frame(height: 28)
        .padding(.top, 2)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(PopoverPalette.stroke)
                .frame(height: 1)
        }
    }

    private var updatedText: String {
        guard let date = snapshot?.modifiedAt else { return "deadhd" }
        return L10n.deadhdUpdated(Self.clock.string(from: date))
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
                .truncationMode(.tail)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
    }
}

/// 마지막 답 전문을 호버 툴팁으로 보여 준다. 진행 행은 스크롤 중에 툴팁이 계속 뜨지 않도록 답 요약 줄에만 붙인다.
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
