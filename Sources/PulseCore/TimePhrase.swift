import Foundation

public enum TimePhrase {
    /// 경과 시간 문구. 1분 미만은 방금, 60분 미만은 N분, 그 이상은 N시간.
    public static func elapsed(from date: Date?, to now: Date) -> String? {
        guard let date else { return nil }
        let seconds = max(0, now.timeIntervalSince(date))
        if seconds < 60 { return "방금" }
        if seconds < 3600 { return "\(Int(seconds / 60))분" }
        return "\(Int(seconds / 3600))시간"
    }

    /// 「N분째」처럼 단위만 붙이는 자리에 쓴다. 1분 미만도 1분으로 본다.
    public static func duration(from date: Date?, to now: Date) -> String? {
        guard let date else { return nil }
        let seconds = max(0, now.timeIntervalSince(date))
        if seconds < 3600 { return "\(max(1, Int(seconds / 60)))분" }
        return "\(Int(seconds / 3600))시간"
    }

    /// 행 오른쪽에 쓰는 「7분 전」. 방금은 단위를 붙이지 않는다.
    public static func relative(from date: Date?, to now: Date) -> String? {
        guard let elapsed = elapsed(from: date, to: now) else { return nil }
        return elapsed == "방금" ? elapsed : "\(elapsed) 전"
    }
}
