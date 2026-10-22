import PulseCore
import SwiftUI

struct PopoverView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var state: PopoverState
    var onClose: () -> Void = {}

    var body: some View {
        VStack(spacing: 0) {
            PopoverHeader(model: model, onClose: onClose)
            banners

            if !model.collapsed {
                if !model.sessionsUnavailable, model.groups.totalCount == 0 {
                    PopoverEmptyState()
                } else if model.groups.totalCount > 0 {
                    list
                }
            }

            PopoverFooter(model: model, state: state)
        }
        .frame(width: model.density == .compact ? 340 : 400)
        .background(PopoverBackground())
        .overlay(alignment: .topTrailing) { settingsSheet }
        .overlay(alignment: .bottom) { toast }
        .animation(.easeOut(duration: 0.18), value: model.recentAcknowledgedCount)
        .onAppear { state.selectedIndex = nil }
    }

    @ViewBuilder
    private var banners: some View {
        if let error = model.errorMessage {
            PopoverBanner(style: .error, message: error) {
                model.poll()
            }
        }
        if model.sessionsUnavailable {
            PopoverBanner(style: .muted, message: L10n.sessionsUnreadable) {
                model.poll()
            }
        }
    }

    private var sections: [SessionSection] {
        state.filter.sections(in: model.groups)
    }

    private var list: some View {
        ScrollViewReader { proxy in
            SlimScrollView {
                // LazyVStack 은 행 높이 추정과 스크롤 위치 보정이 맞물려 배치를 끝없이 되풀이한 적이 있다. 행 수가 적어 전부 그린다.
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(sections.enumerated()), id: \.element.group.rawValue) { index, section in
                        Section {
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
                            if section.group == .done,
                               let overflow = model.groups.doneOverflowText {
                                Text(overflow)
                                    .font(.system(size: 11))
                                    .foregroundColor(PopoverPalette.secondary)
                                    .padding(.horizontal, 14)
                                    .padding(.top, 2)
                                    .padding(.bottom, 6)
                            }
                        } header: {
                            SessionSectionLabel(
                                group: section.group,
                                model: model,
                                topPadding: index == 0 ? 0 : 14
                            )
                        }
                    }
                }
                .padding(.top, 2)
                .padding(.bottom, 6)
            }
            .frame(maxHeight: 470)
            .onChange(of: state.selectedIndex) { _ in
                scrollToSelection(proxy)
            }
            .onChange(of: state.revealRequest) { _ in
                revealSelection(proxy)
            }
        }
    }

    private func isSelected(_ item: DisplayItem) -> Bool {
        guard let index = state.selectedIndex else { return false }
        let items = state.filter.selectableItems(in: model.groups)
        guard items.indices.contains(index) else { return false }
        return items[index].id == item.id
    }

    private func scrollToSelection(_ proxy: ScrollViewProxy) {
        guard let index = state.selectedIndex else { return }
        let items = state.filter.selectableItems(in: model.groups)
        guard items.indices.contains(index) else { return }
        withAnimation(.easeOut(duration: 0.12)) {
            proxy.scrollTo(items[index].rowID, anchor: .center)
        }
    }

    /// 펼침이 바뀌어 행 높이가 달라진 뒤에 최소한으로 스크롤한다.
    private func revealSelection(_ proxy: ScrollViewProxy) {
        guard let index = state.selectedIndex else { return }
        let items = state.filter.selectableItems(in: model.groups)
        guard items.indices.contains(index) else { return }
        let rowID = items[index].rowID
        DispatchQueue.main.async {
            proxy.scrollTo(rowID, anchor: nil)
        }
    }

    @ViewBuilder
    private var settingsSheet: some View {
        if state.settingsOpen {
            SettingsSheet(model: model, state: state)
                .padding(.top, 58)
                .padding(.trailing, 12)
        }
    }

    @ViewBuilder
    private var toast: some View {
        if model.recentAcknowledgedCount > 0 {
            PopoverToast(count: model.recentAcknowledgedCount) {
                model.undoRecentAcknowledge()
            }
            .id(model.recentAcknowledgedGeneration)
            .padding(.bottom, 46)
        }
    }
}
