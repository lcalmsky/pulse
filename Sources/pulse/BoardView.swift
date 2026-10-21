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
            PopoverHeader(model: model, onClose: { model.hidePanel() })

            if model.recentAcknowledgedCount > 0 {
                HStack(spacing: 5) {
                    Text("완료 \(model.recentAcknowledgedCount)개를 확인했어요 ·")
                        .font(.system(size: 11))
                        .foregroundColor(PopoverPalette.secondary)
                    Button("되돌리기") { model.undoRecentAcknowledge() }
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
                Text("Claude 세션을 읽지 못했어요")
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
        LazyVStack(alignment: .leading, spacing: 0) {
            if model.groups.totalCount == 0 {
                Text(model.sessionsUnavailable ? "Claude 세션을 읽지 못했어요" : "지금은 조용해요")
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
                        selected: false,
                        optionDown: false
                    )
                    .padding(.horizontal, 8)
                    .padding(.bottom, section.group == .attention ? 12 : 0)
                }
                if section.group == .done, let overflow = model.groups.doneOverflowText {
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
        DisplayGroup.allCases.compactMap { group in
            let items = model.groups.visibleItems(for: group)
            return items.isEmpty ? nil : SessionSection(group: group, items: items)
        }
    }
}

private struct BoardHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
