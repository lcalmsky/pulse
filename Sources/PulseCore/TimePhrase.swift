import Foundation

public enum TimePhrase {
    /// 경과 시간 문구. 1분 미만은 방금, 60분 미만은 N분, 그 이상은 N시간.
    public static func elapsed(from date: Date?, to now: Date) -> String? {
        guard let date else { return nil }
        let seconds = max(0, now.timeIntervalSince(date))
        if seconds < 60 { return L10n.justNow }
        if seconds < 3600 { return L10n.minutes(Int(seconds / 60)) }
        return L10n.hours(Int(seconds / 3600))
    }

    /// 확인 필요 카드 메타의 경과 시간. 1분 미만도 1분으로 본다.
    public static func soFar(from date: Date?, to now: Date) -> String? {
        guard let date else { return nil }
        return L10n.durationSoFar(minutes: max(1, Int(max(0, now.timeIntervalSince(date)) / 60)))
    }

    /// 「N분째」처럼 단위만 붙이는 자리에 쓴다. 1분 미만도 1분으로 본다.
    public static func duration(from date: Date?, to now: Date) -> String? {
        guard let date else { return nil }
        let seconds = max(0, now.timeIntervalSince(date))
        if seconds < 3600 { return L10n.minutes(max(1, Int(seconds / 60))) }
        return L10n.hours(Int(seconds / 3600))
    }

    /// 행 오른쪽에 쓰는 「7분 전」. 방금은 단위를 붙이지 않는다.
    public static func relative(from date: Date?, to now: Date) -> String? {
        guard let elapsed = elapsed(from: date, to: now) else { return nil }
        return elapsed == L10n.justNow ? elapsed : L10n.ago(elapsed)
    }

    /// 활동 줄에 쓰는 「12초 전」. 1분 안쪽도 초 단위로 보여 준다.
    public static func ago(from date: Date?, to now: Date) -> String? {
        guard let date else { return nil }
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        if seconds < 60 { return L10n.secondsAgo(seconds) }
        if seconds < 3600 { return L10n.minutesAgo(seconds / 60) }
        if seconds < 86_400 { return L10n.hoursAgo(seconds / 3600) }
        return L10n.daysAgo(seconds / 86_400)
    }
}
