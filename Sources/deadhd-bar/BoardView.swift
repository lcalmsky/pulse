import SwiftUI
import DeadhdBarCore

struct BoardView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            if let error = model.errorMessage {
                Text(error)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if model.serverOff {
                HStack(spacing: 6) {
                    Text("deadhd 서버가 꺼져 있어요")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Button("서버 시작") { model.startServer() }
                        .font(.system(size: 11))
                        .buttonStyle(.borderless)
                }
            }

            if !model.collapsed {
                content
            }
        }
        .padding(12)
        .frame(width: 320, alignment: .leading)
    }

    private var header: some View {
        let counts = model.groups.counts
        return HStack(spacing: 6) {
            Text("deadhd")
                .font(.system(size: 13, weight: .semibold))
            Spacer(minLength: 4)
            CountBadge(count: counts.attention, color: .orange)
            CountBadge(count: counts.working, color: .blue)
            CountBadge(count: counts.done, color: .green)
            Button(action: { model.collapsed.toggle() }) {
                Image(systemName: model.collapsed ? "chevron.down" : "chevron.up")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help(model.collapsed ? "펼치기" : "접기")
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 10) {
            if model.groups.totalCount == 0 {
                Text(model.serverOff ? "세션 정보를 받지 못했어요" : "지금은 조용해요")
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
        let items = model.groups.items(for: group)
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("\(group.title) \(items.count)")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(color(for: group))
                ForEach(items) { item in
                    CardRow(item: item, model: model)
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
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title)
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(1)
                        Text(item.status)
                            .font(.system(size: 11))
                            .foregroundColor(statusColor)
                            .lineLimit(2)
                        if let detail = item.detail {
                            Text(detail)
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                        }
                        if let place = item.placeText {
                            Text(place)
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!item.isActionable)

            if item.isStall && item.group == .attention {
                Button("더 기다리기") { model.snooze(item) }
                    .font(.system(size: 10))
                    .buttonStyle(.borderless)
                    .foregroundColor(.orange)
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
