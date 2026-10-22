import PulseCore
import SwiftUI

/// 팝오버와 목록 패널이 함께 쓰는 검색 줄. 검색어가 비어 있고 필드에 포커스가 없으면 그리지 않는다.
struct SessionSearchBar: View {
    @ObservedObject var model: AppModel
    @ObservedObject var state: PopoverState

    @FocusState private var focused: Bool

    private var showsCount: Bool {
        !state.query.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var matchCount: Int {
        state.filter.sections(in: model.groups, query: state.query).reduce(0) { $0 + $1.items.count }
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(PopoverPalette.secondary)
            TextField(L10n.searchSessions, text: text)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundColor(PopoverPalette.text)
                .focused($focused)
            if showsCount {
                Text("\(matchCount)")
                    .font(.system(size: 11, design: .monospaced))
                    .monospacedDigit()
                    .foregroundColor(PopoverPalette.secondary)
            }
            Button {
                state.clearSearch()
                state.syncSelection(to: model.groups)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundColor(PopoverPalette.tertiary)
            }
            .buttonStyle(.plain)
            .help(L10n.clearSearch)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 8).fill(PopoverPalette.glassHi))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(PopoverPalette.stroke, lineWidth: 1))
        .padding(.horizontal, 14)
        .onAppear {
            if !state.query.isEmpty { focus() }
        }
        .onChange(of: state.searchFocusRequest) { _ in focus() }
        .onChange(of: focused) { state.searchFocused = $0 }
        .onDisappear { state.searchFocused = false }
    }

    private var text: Binding<String> {
        Binding(
            get: { state.query },
            set: { newValue in
                state.query = newValue
                state.syncSelection(to: model.groups)
            }
        )
    }

    private func focus() {
        // 새로 그려진 필드가 같은 갱신 주기에 있지 않을 수 있어 다음 런루프에 넘긴다.
        DispatchQueue.main.async { focused = true }
    }
}
