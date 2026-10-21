import Foundation

/// 메뉴 막대 아이콘과 팝오버 머리글 로고가 함께 쓰는 Pulse 글리프.
public enum PulseGlyph {
    /// 링 반지름을 1로 둔 파형 꼭짓점. y 는 위쪽이 양수다.
    public static let wave: [CGPoint] = [
        CGPoint(x: -0.6, y: 0),
        CGPoint(x: -0.26, y: 0),
        CGPoint(x: -0.1, y: 0.43),
        CGPoint(x: 0.1, y: -0.43),
        CGPoint(x: 0.26, y: 0),
        CGPoint(x: 0.6, y: 0),
    ]

    /// 파형 그라데이션 정지점. 0=확인, 1=진행, 2=완료이고 각 그룹 구간의 가운데에 놓는다.
    public static func stops(counts: GroupedSessions.Counts) -> [(location: CGFloat, group: Int)] {
        let ratio = SegmentRatio.make(
            attention: counts.attention,
            working: counts.working,
            done: counts.done
        )
        var result: [(location: CGFloat, group: Int)] = []
        var offset = 0.0
        for (group, fraction) in [ratio.attention, ratio.working, ratio.done].enumerated() where fraction > 0 {
            result.append((CGFloat(offset + fraction / 2), group))
            offset += fraction
        }
        return result
    }
}
