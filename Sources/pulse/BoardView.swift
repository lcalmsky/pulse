import SwiftUI
import PulseCore

struct BoardView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            if model.recentAcknowledgedCount > 0 {
                HStack(spacing: 5) {
                    Text("완료 \(model.recentAcknowledgedCount)개를 확인했어요 ·")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Button("되돌리기") { model.undoRecentAcknowledge() }
                        .font(.system(size: 11))
                        .buttonStyle(.borderless)
                }
            }

            if let error = model.errorMessage {
                Text(error)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if model.sessionsUnavailable {
                Text("Claude 세션을 읽지 못했어요")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            if !model.collapsed {
                ScrollView(.vertical) {
                    content
                }
            }
        }
        .padding(12)
        .frame(minWidth: 340, idealWidth: 440, maxWidth: .infinity, alignment: .leading)
    }

    private var header: some View {
        let counts = model.groups.counts
        return HStack(spacing: 6) {
            Text("Claude 세션")
                .font(.system(size: 13, weight: .semibold))
            Spacer(minLength: 4)
            CountBadge(count: counts.attention, color: .orange)
            CountBadge(count: counts.working, color: .blue)
            CountBadge(count: counts.done, color: .green)
            Button(action: { model.collapsed.toggle() }) {
                Image(systemName: model.collapsed ? "chevron.down" : "chevron.up")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(model.collapsed ? "펼치기" : "접기")
            Button(action: { model.hidePanel() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("플로팅 창 닫기")
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 10) {
            if model.groups.totalCount == 0 {
                Text(model.sessionsUnavailable ? "Claude 세션을 읽지 못했어요" : "지금은 조용해요")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            ForEach(DisplayGroup.allCases, id: \.self) { group in
                groupSection(group)
            }
        }
    }

    @ViewBuilder
    private func groupSection(_ group: DisplayGroup) -> some View {
        let items = model.groups.visibleItems(for: group)
        let showRestore = group == .done && model.hiddenDoneCount > 0
        if !items.isEmpty || showRestore {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text("\(group.title) \(model.groups.items(for: group).count)")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(color(for: group))
                    if showRestore {
                        Button("다시 보기") { model.restoreAcknowledgedDone() }
                            .font(.system(size: 10))
                            .buttonStyle(.borderless)
                            .help("확인한 완료 \(model.hiddenDoneCount)개를 다시 보여요")
                    }
                }
                ForEach(items) { item in
                    CardRow(item: item, model: model)
                }
                if group == .done, let overflow = model.groups.doneOverflowText {
                    Text(overflow)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    private func color(for group: DisplayGroup) -> Color {
        switch group {
        case .attention: return .orange
        case .working: return .blue
        case .done: return .green
        }
    }
}

private struct CountBadge: View {
    let count: Int
    let color: Color

    var body: some View {
        Text("\(count)")
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .clipShape(Capsule())
    }
}

private struct CardRow: View {
    let item: DisplayItem
    @ObservedObject var model: AppModel

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Button(action: { model.open(item) }) {
                HStack(alignment: .top, spacing: 8) {
                    icon
                        .frame(width: 14, height: 14, alignment: .center)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(item.title)
                                .font(.system(size: 12, weight: .semibold))
                                .lineLimit(2)
                            if let key = item.keyTag {
                                Text(key)
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(Color.secondary.opacity(0.15))
                                    .clipShape(Capsule())
                            }
                        }
                        Text(item.status)
                            .font(.system(size: 11))
                            .foregroundColor(statusColor)
                            .lineLimit(2)
                        if let progress = item.progress {
                            HStack(spacing: 6) {
                                ProgressView(value: progress.fraction)
                                    .progressViewStyle(.linear)
                                    .frame(width: 110)
                                Text(progress.text)
                                    .font(.system(size: 10, weight: .medium))
                                    .monospacedDigit()
                                    .foregroundColor(.secondary)
                                if let label = item.nowLabel {
                                    Text("· \(label)")
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }
                            }
                        }
                        if let place = item.placeText {
                            Text(place)
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                        if let reply = item.replyTail {
                            Text(reply)
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                                .lineLimit(3)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!item.isActionable)

            VStack(alignment: .trailing, spacing: 6) {
                if item.orcaTerminal != nil || item.cwd != nil {
                    Button(action: { model.openInOrca(item) }) {
                        Image(systemName: "terminal")
                            .font(.system(size: 11))
                            .frame(width: 22, height: 22)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                    .help("Orca 로 이동")
                }
                if item.isStall && item.group == .attention {
                    Button("더 기다리기") { model.snooze(item) }
                        .font(.system(size: 10))
                        .buttonStyle(.borderless)
                        .foregroundColor(.orange)
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(background)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .opacity(item.isActionable ? 1 : 0.65)
    }

    @ViewBuilder
    private var icon: some View {
        switch item.group {
        case .attention:
            Text("⚠")
                .font(.system(size: 12))
                .foregroundColor(.orange)
        case .working:
            ProgressView()
                .controlSize(.small)
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 11))
                .foregroundColor(.green)
        }
    }

    private var statusColor: Color {
        switch item.group {
        case .attention: return .orange
        case .working: return .secondary
        case .done: return .green
        }
    }

    private var background: Color {
        switch item.group {
        case .attention: return Color.orange.opacity(0.18)
        case .working: return Color.primary.opacity(0.06)
        case .done: return Color.green.opacity(0.10)
        }
    }
}
