import PulseCore
import SwiftUI

struct PopoverHeader: View {
    @ObservedObject var model: AppModel
    @ObservedObject var state: PopoverState

    var body: some View {
        HStack(spacing: 10) {
            if model.density == .rich, !model.sessionsUnavailable {
                SegmentRingView(
                    ratios: SegmentRatio.make(
                        attention: counts.attention,
                        working: counts.working,
                        done: counts.done
                    ),
                    total: model.groups.totalCount
                )
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 11.5))
                    .foregroundColor(PopoverPalette.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            HStack(spacing: 2) {
                PopoverIconButton(
                    symbol: "sidebar.right",
                    help: model.panelVisible ? "플로팅 창 숨기기" : "플로팅 창 보기"
                ) {
                    model.togglePanel()
                }
                PopoverIconButton(
                    symbol: "gearshape",
                    help: "보기 설정 (⌘,)",
                    selected: state.settingsOpen
                ) {
                    state.settingsOpen.toggle()
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    private var counts: GroupedSessions.Counts {
        model.groups.counts
    }

    private var title: String {
        if model.sessionsUnavailable { return "세션을 읽지 못했어요" }
        return counts.attention > 0 ? "확인할 세션 \(counts.attention)개" : "모두 순조로워요"
    }

    private var subtitle: String {
        if model.sessionsUnavailable { return "지금 재시도로 다시 읽어 볼게요" }
        let updated = TimePhrase.relative(from: model.lastSuccess, to: Date()).map { "\($0) 갱신" } ?? "갱신 전"
        return "진행 중 \(counts.working) · 완료 \(counts.done) · \(updated)"
    }
}
