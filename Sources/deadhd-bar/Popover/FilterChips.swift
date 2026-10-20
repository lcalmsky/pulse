import DeadhdBarCore
import SwiftUI

struct FilterChips: View {
    @ObservedObject var model: AppModel
    @ObservedObject var state: PopoverState

    var body: some View {
        HStack(spacing: 6) {
            ForEach(SessionFilter.allCases) { filter in
                chip(filter)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 10)
    }

    private func chip(_ filter: SessionFilter) -> some View {
        let selected = state.filter == filter
        return Button {
            state.select(filter)
        } label: {
            HStack(spacing: 5) {
                if let group = filter.group {
                    Circle()
                        .fill(PopoverPalette.color(for: group))
                        .frame(width: 7, height: 7)
                }
                Text(filter.title)
                    .font(.system(size: 11.5, weight: .medium))
                Text("\(filter.count(in: model.groups))")
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
                    .foregroundColor(selected ? PopoverPalette.secondary : PopoverPalette.tertiary)
            }
            .foregroundColor(selected ? .primary : PopoverPalette.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Capsule().fill(selected ? Color.primary.opacity(0.07) : Color.clear))
            .overlay(
                Capsule()
                    .stroke(
                        selected ? Color.primary.opacity(0.15) : Color.primary.opacity(0.10),
                        lineWidth: 1
                    )
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
