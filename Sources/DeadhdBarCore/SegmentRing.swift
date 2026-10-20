import Foundation

/// 링 하나에 세 그룹의 비율을 나눠 그릴 때 쓰는 조각. 합이 0 이면 모든 조각이 0 이다.
public struct SegmentRatio: Equatable {
    public let attention: Double
    public let working: Double
    public let done: Double

    public init(attention: Double, working: Double, done: Double) {
        self.attention = attention
        self.working = working
        self.done = done
    }

    public static func make(attention: Int, working: Int, done: Int) -> SegmentRatio {
        let values = [attention, working, done].map { Double(max(0, $0)) }
        let sum = values.reduce(0, +)
        guard sum > 0 else {
            return SegmentRatio(attention: 0, working: 0, done: 0)
        }
        return SegmentRatio(
            attention: values[0] / sum,
            working: values[1] / sum,
            done: values[2] / sum
        )
    }
}

/// 메뉴 막대 링 옆에 붙는 숫자. 확인 필요가 있으면 그것만 꺼내고,
/// 없으면 진행 중 수를 흐리게 두며, 둘 다 없으면 숫자를 두지 않는다.
public enum MenuBarCounter: Equatable {
    case attention(Int)
    case working(Int)
    case none

    public static func make(attention: Int, working: Int) -> MenuBarCounter {
        if attention > 0 { return .attention(attention) }
        if working > 0 { return .working(working) }
        return .none
    }

    public var count: Int? {
        switch self {
        case let .attention(count), let .working(count): return count
        case .none: return nil
        }
    }
}
