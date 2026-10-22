import AppKit
import SwiftUI
import PulseCore

struct BoardView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var state: PopoverState
    /// 패널 창이 실제로 내어 주는 높이. 창이 내용에 맞춰 커지는 동안은 값이 없다.
    @ObservedObject var panelHeight: PanelContentHeight
    var onContentHeightChange: (() -> Void)?

    @State private var fixedHeight: CGFloat = 0
    @State private var contentHeight: CGFloat = 0

    private let boardSpacing: CGFloat = 10

    var body: some View {
        board
            .frame(maxHeight: .infinity, alignment: .top)
    }

    /// 창이 내용에 맞춰 자랄 때 기준이 되는 전체 높이.
    private var naturalHeight: CGFloat {
        guard !model.collapsed else { return fixedHeight }
        return fixedHeight + boardSpacing + contentHeight
    }

    /// 고정 영역은 그대로 두고 목록만 스크롤할지.
    private var listScrolls: Bool {
        naturalHeight > scrollLimit
    }

    /// 사용자가 직접 잡아 둔 창 높이가 있으면 그 높이를 그대로 쓴다. 창이 내용에 맞춰 커지는 중에는
    /// 창 높이를 읽지 않는다. 읽으면 지금 창 높이에 스크롤이 붙어 창이 자라지 못한다.
    private var scrollLimit: CGFloat {
        panelHeight.available ?? maximumHeight
    }

    /// 자동 크기일 때의 높이 상한. 패널 높이는 내용에 맞추되 화면의 70% 를 넘으면 목록이 그 안에서 스크롤한다.
    private var maximumHeight: CGFloat {
        guard let screen = NSScreen.main else { return .greatestFiniteMagnitude }
        return floor(screen.visibleFrame.height * 0.7)
    }

    private var listHeight: CGFloat {
        max(0, scrollLimit - fixedHeight - boardSpacing)
    }

    private var board: some View {
        VStack(alignment: .leading, spacing: boardSpacing) {
            fixed
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(key: BoardFixedHeightKey.self, value: proxy.size.height)
                    }
                )
                .onPreferenceChange(BoardFixedHeightKey.self) { height in
                    guard abs(height - fixedHeight) > 0.5 else { return }
                    fixedHeight = height
                    onContentHeightChange?()
                }

            if !model.collapsed {
                if listScrolls {
                    ScrollViewReader { proxy in
                        SlimScrollView {
                            measuredContent
                        }
                        .frame(height: listHeight)
                        .onChange(of: state.selectedIndex) { _ in
                            scrollToSelection(proxy)
                        }
                        .onChange(of: state.revealRequest) { _ in
                            revealSelection(proxy)
                        }
                    }
                } else {
                    measuredContent
                }
            }
        }
        .frame(minWidth: 340, idealWidth: 440, maxWidth: .infinity, alignment: .leading)
    }

    /// 머리글·검색 줄·되돌리기·오류 문구. 목록을 스크롤해도 창에 남는다.
    private var fixed: some View {
        VStack(alignment: .leading, spacing: boardSpacing) {
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
        }
    }

    /// 스크롤 여부와 상관없이 목록의 자연 높이를 잰다. 한쪽 경로에서만 재면 스크롤로 바뀔 때 높이가 0 이 되어 되돌아간다.
    private var measuredContent: some View {
        content
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(key: BoardContentHeightKey.self, value: proxy.size.height)
                }
            )
            .onPreferenceChange(BoardContentHeightKey.self) { height in
                guard abs(height - contentHeight) > 0.5 else { return }
                contentHeight = height
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

private struct BoardFixedHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct BoardContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
