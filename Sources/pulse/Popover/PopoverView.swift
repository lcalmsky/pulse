import PulseCore
import SwiftUI

struct PopoverView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var state: PopoverState

    var body: some View {
        VStack(spacing: 0) {
            PopoverHeader(model: model, state: state)
            banners

            if !model.sessionsUnavailable, model.groups.totalCount == 0 {
                PopoverEmptyState()
            } else if model.groups.totalCount > 0 {
                if model.density == .rich {
                    FilterChips(model: model, state: state)
                }
                list
            }

            PopoverFooter(model: model)
        }
        .frame(width: model.density == .compact ? 340 : 400)
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
            PopoverBanner(style: .muted, message: "Claude 세션을 읽지 못했어요") {
                model.poll()
            }
        }
    }

    private var sections: [SessionSection] {
        state.filter.sections(in: model.groups)
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    ForEach(sections, id: \.group.rawValue) { section in
                        Section {
                            ForEach(section.items) { item in
                                SessionRowView(
                                    item: item,
                                    model: model,
                                    selected: isSelected(item),
                                    optionDown: state.optionDown
                                )
                                .padding(.horizontal, 6)
                                .id(item.sessionId)
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
                            sectionHeader(section)
                        }
                    }
                }
                .padding(.bottom, 6)
            }
            .frame(maxHeight: 470)
            .onChange(of: state.selectedIndex) { _ in
                scrollToSelection(proxy)
            }
        }
    }

    private func sectionHeader(_ section: SessionSection) -> some View {
        HStack(spacing: 7) {
            Circle()
                .fill(PopoverPalette.color(for: section.group))
                .frame(width: 6, height: 6)
            Text("\(SessionFilter.title(for: section.group)) \(model.groups.items(for: section.group).count)")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(PopoverPalette.tertiary)
            Rectangle()
                .fill(Color.primary.opacity(0.10))
                .frame(height: 1)
            if section.group == .done {
                Button("모두 확인") {
                    model.acknowledgeAllDone()
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.blue)
                .contentShape(Rectangle())
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 4)
        .background(.bar)
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
            proxy.scrollTo(items[index].sessionId, anchor: .center)
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
