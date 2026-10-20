import DeadhdBarCore
import SwiftUI

struct SegmentRingView: View {
    let ratios: SegmentRatio
    var size: CGFloat = 38
    var stroke: CGFloat = 4
    var total: Int?

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.10), lineWidth: stroke)
            ForEach(segments.indices, id: \.self) { index in
                Circle()
                    .trim(from: segments[index].start, to: segments[index].end)
                    .stroke(
                        segments[index].color,
                        style: StrokeStyle(lineWidth: stroke, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
            }
            if let total {
                Text("\(total)")
                    .font(.system(size: 12, weight: .bold))
                    .monospacedDigit()
            }
        }
        .frame(width: size, height: size)
    }

    private var segments: [(start: CGFloat, end: CGFloat, color: Color)] {
        let gap = 3 / (CGFloat.pi * max(size - stroke, 1))
        let values: [(Double, Color)] = [
            (ratios.attention, .orange),
            (ratios.working, .blue),
            (ratios.done, .green),
        ]
        var result: [(start: CGFloat, end: CGFloat, color: Color)] = []
        var offset: CGFloat = 0
        for (fraction, color) in values where fraction > 0 {
            let start = offset
            let end = min(1, offset + CGFloat(fraction))
            result.append((start, max(start + 0.001, end - gap), color))
            offset = end
        }
        return result
    }
}
