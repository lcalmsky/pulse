import AppKit
import SwiftUI
import PulseCore

struct BoardView: View {
    @ObservedObject var model: AppModel
    var onContentHeightChange: (() -> Void)?

    @State private var naturalHeight: CGFloat = 0

    var body: some View {
        Group {
            if naturalHeight > maximumHeight {
                ScrollView(.vertical) {
                    board
                }
                .frame(height: maximumHeight)
            } else {
                board
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    /// 패널 높이는 내용에 맞추되 화면의 70% 를 넘으면 그 안에서 스크롤한다.
    private var maximumHeight: CGFloat {
        guard let screen = NSScreen.main else { return .greatestFiniteMagnitude }
        return floor(screen.visibleFrame.height * 0.7)
    }

    private var board: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            if model.recentAcknowledgedCount > 0 {
                HStack(spacing: 5) {
                    Text("완료 \(model.recentAcknowledgedCount)개를 확인했어요 ·")
                        .font(.system(size: 11))
                        .foregroundColor(PopoverPalette.secondary)
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
                    .foregroundColor(PopoverPalette.secondary)
            }

            if !model.collapsed {
                content
            }
        }
        .padding(12)
        .frame(minWidth: 340, idealWidth: 440, maxWidth: .infinity, alignment: .leading)
        .background(
            GeometryReader { proxy in
                Color.clear.preference(key: BoardHeightKey.self, value: proxy.size.height)
            }
        )
        .onPreferenceChange(BoardHeightKey.self) { height in
            guard abs(height - naturalHeight) > 0.5 else { return }
            naturalHeight = height
            onContentHeightChange?()
        }
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
                    .foregroundColor(PopoverPalette.secondary)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(model.collapsed ? "펼치기" : "접기")
            Button(action: { model.hidePanel() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(PopoverPalette.secondary)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("플로팅 창 닫기")
        }
    }

    private var content: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            if model.groups.totalCount == 0 {
                Text(model.sessionsUnavailable ? "Claude 세션을 읽지 못했어요" : "지금은 조용해요")
                    .font(.system(size: 11))
                    .foregroundColor(PopoverPalette.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
            }
            ForEach(DisplayGroup.allCases, id: \.self) { group in
                section(group)
            }
        }
        .padding(.bottom, 6)
    }

    @ViewBuilder
    private func section(_ group: DisplayGroup) -> some View {
        let items = model.groups.visibleItems(for: group)
        let showRestore = group == .done && model.hiddenDoneCount > 0
        if !items.isEmpty || showRestore {
            sectionHeader(group, count: model.groups.items(for: group).count, showRestore: showRestore)
            ForEach(items) { item in
                VStack(alignment: .leading, spacing: 0) {
                    SessionRowView(item: item, model: model, selected: false, optionDown: false)
                    if item.isStall, item.group == .attention {
                        stallAction(item)
                    }
                }
                .padding(.horizontal, 6)
            }
            if group == .done, let overflow = model.groups.doneOverflowText {
                Text(overflow)
                    .font(.system(size: 11))
                    .foregroundColor(PopoverPalette.secondary)
                    .padding(.horizontal, 14)
                    .padding(.top, 2)
                    .padding(.bottom, 6)
            }
        }
    }

    private func sectionHeader(_ group: DisplayGroup, count: Int, showRestore: Bool) -> some View {
        HStack(spacing: 7) {
            Circle()
                .fill(PopoverPalette.color(for: group))
                .frame(width: 6, height: 6)
            Text("\(SessionFilter.title(for: group)) \(count)")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(PopoverPalette.tertiary)
            Rectangle()
                .fill(Color.primary.opacity(0.10))
                .frame(height: 1)
            if group == .done {
                Button("모두 확인") {
                    model.acknowledgeAllDone()
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.blue)
                .contentShape(Rectangle())
                if showRestore {
                    Button("다시 보기") {
                        model.restoreAcknowledgedDone()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(PopoverPalette.secondary)
                    .contentShape(Rectangle())
                    .help("확인한 완료 \(model.hiddenDoneCount)개를 다시 보여요")
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 4)
    }

    private func stallAction(_ item: DisplayItem) -> some View {
        HStack {
            Spacer(minLength: 0)
            Button("더 기다리기") { model.snooze(item) }
                .font(.system(size: 10))
                .buttonStyle(.borderless)
                .foregroundColor(.orange)
        }
        .padding(.trailing, 8)
        .padding(.bottom, 4)
    }
}

private struct BoardHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
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
