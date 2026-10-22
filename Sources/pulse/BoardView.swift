import AppKit
import SwiftUI
import PulseCore

struct BoardView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var state: PopoverState
    /// 패널 창이 실제로 내어 주는 높이. 창이 내용에 맞춰 커지는 동안은 값이 없다.
    @ObservedObject var panelHeight: PanelContentHeight
    var onContentHeightChange: (() -> Void)?

    @State private var naturalHeight: CGFloat = 0

    var body: some View {
        Group {
            if naturalHeight > scrollLimit {
                ScrollViewReader { proxy in
                    SlimScrollView {
                        board
                    }
                    .frame(height: scrollLimit)
                    .onChange(of: state.selectedIndex) { _ in
                        scrollToSelection(proxy)
                    }
                    .onChange(of: state.revealRequest) { _ in
                        revealSelection(proxy)
                    }
                }
            } else {
                board
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    /// 스크롤 뷰 높이. 사용자가 잡아 둔 창 높이가 있으면 그 높이와 화면 높이 70% 중 작은 쪽을 쓴다.
    /// 창이 내용에 맞춰 커지는 중에는 창 높이를 읽지 않는다. 읽으면 지금 창 높이에 스크롤이 붙어 창이 자라지 못한다.
    private var scrollLimit: CGFloat {
        guard let available = panelHeight.available else { return maximumHeight }
        return min(maximumHeight, available)
    }

    /// 패널 높이는 내용에 맞추되 화면의 70% 를 넘으면 그 안에서 스크롤한다.
    private var maximumHeight: CGFloat {
        guard let screen = NSScreen.main else { return .greatestFiniteMagnitude }
        return floor(screen.visibleFrame.height * 0.7)
    }

    private var board: some View {
        VStack(alignment: .leading, spacing: 10) {
            PopoverHeader(model: model, onClose: { model.hidePanel() })

            if !state.query.isEmpty || state.searchFocused {
                SessionSearchBar(model: model, state: state)
            }

            if model.recentAcknowledgedCount > 0 {
                HStack(spacing: 5) {
                    Text("\(L10n.acknowledgedDone(model.recentAcknowledgedCount)) ·")
                        .font(.system(size: 11))
                        .foregroundColor(PopoverPalette.secondary)
                    Button(L10n.undo) { model.undoRecentAcknowledge() }
                        .font(.system(size: 11))
                        .buttonStyle(.borderless)
                }
                .padding(.horizontal, 14)
            }

            if let error = model.errorMessage {
                Text(error)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 14)
            }

            if model.sessionsUnavailable {
                Text(L10n.sessionsUnreadable)
                    .font(.system(size: 11))
                    .foregroundColor(PopoverPalette.secondary)
                    .padding(.horizontal, 14)
            }

            if !model.collapsed {
                content
            }
        }
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

    private var content: some View {
        // 팝오버 목록과 같은 이유로 LazyVStack 을 쓰지 않는다.
        VStack(alignment: .leading, spacing: 0) {
            if model.groups.totalCount == 0 {
                Text(model.sessionsUnavailable ? L10n.sessionsUnreadable : L10n.allQuiet)
                    .font(.system(size: 11))
                    .foregroundColor(PopoverPalette.secondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
            } else if sections.isEmpty, !state.query.isEmpty {
                Text(L10n.noSearchResults)
                    .font(.system(size: 11))
                    .foregroundColor(PopoverPalette.secondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
            }
            ForEach(Array(sections.enumerated()), id: \.element.group) { index, section in
                SessionSectionLabel(
                    group: section.group,
                    model: model,
                    topPadding: index == 0 ? 0 : 14
                )
                ForEach(section.items, id: \.rowID) { item in
                    SessionRowView(
                        item: item,
                        group: section.group,
                        model: model,
                        selected: isSelected(item),
                        optionDown: state.optionDown
                    )
                    .padding(.horizontal, 8)
                    .padding(.bottom, section.group == .attention ? 12 : 0)
                    .id(item.rowID)
                }
                if section.group == .done, state.query.isEmpty, let overflow = model.groups.doneOverflowText {
                    Text(overflow)
                        .font(.system(size: 11))
                        .foregroundColor(PopoverPalette.secondary)
                        .padding(.horizontal, 14)
                        .padding(.top, 2)
                        .padding(.bottom, 6)
                }
            }
        }
        .padding(.bottom, 6)
    }

    private var sections: [SessionSection] {
        state.filter.sections(in: model.groups, query: state.query)
    }

    private func isSelected(_ item: DisplayItem) -> Bool {
        guard let index = state.selectedIndex else { return false }
        let items = state.filter.selectableItems(in: model.groups, query: state.query)
        guard items.indices.contains(index) else { return false }
        return items[index].id == item.id
    }

    private func scrollToSelection(_ proxy: ScrollViewProxy) {
        guard let index = state.selectedIndex else { return }
        let items = state.filter.selectableItems(in: model.groups, query: state.query)
        guard items.indices.contains(index) else { return }
        withAnimation(.easeOut(duration: 0.12)) {
            proxy.scrollTo(items[index].rowID, anchor: .center)
        }
    }

    /// 펼침이 바뀌어 행 높이가 달라진 뒤에 최소한으로 스크롤한다.
    private func revealSelection(_ proxy: ScrollViewProxy) {
        guard let index = state.selectedIndex else { return }
        let items = state.filter.selectableItems(in: model.groups, query: state.query)
        guard items.indices.contains(index) else { return }
        let rowID = items[index].rowID
        DispatchQueue.main.async {
            proxy.scrollTo(rowID, anchor: nil)
        }
    }
}

private struct BoardHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
