import Foundation

public enum BadgeTone: Equatable {
    case attention
    case working
    case done
    case muted
}

/// 머리글의 그룹 뱃지. 세션이 없는 그룹은 확인 필요라도 흐리게 둔다.
public enum HeaderBadge {
    public static func tone(for group: DisplayGroup, count: Int) -> BadgeTone {
        switch group {
        case .attention:
            return count == 0 ? .muted : .attention
        case .working:
            return .working
        case .done:
            return .done
        }
    }

    public static func label(for group: DisplayGroup, count: Int) -> String {
        switch group {
        case .attention:
            return "확인 \(count)"
        case .working:
            return "진행 \(count)"
        case .done:
            return "완료 \(count)"
        }
    }
}

public enum StepSegment: Equatable {
    case done
    case current
    case blocked
    case left
}

/// 진행 행의 스텝퍼. 체크리스트 개수만큼 칸을 만들고 완료·현재·막힘·남음을 순서대로 채운다.
public enum Stepper {
    public static func segments(counts: SessionCounts?, total: Int?) -> [StepSegment] {
        guard let counts, let total, total > 0 else { return [] }
        var segments = Array(repeating: StepSegment.done, count: max(0, counts.done))
            + Array(repeating: .current, count: max(0, counts.now))
            + Array(repeating: .blocked, count: max(0, counts.blocked))
        if segments.count > total {
            segments = Array(segments.prefix(total))
        }
        if segments.count < total {
            segments += Array(repeating: .left, count: total - segments.count)
        }
        return segments
    }

    public static func position(counts: SessionCounts?, total: Int?) -> String? {
        guard !segments(counts: counts, total: total).isEmpty,
              let counts, let total else { return nil }
        let reached = max(0, counts.done) + (max(0, counts.now) > 0 ? 1 : 0)
        return "\(min(reached, total))/\(total)"
    }
}

/// 행에 그리는 문구. 뷰는 여기서 고른 문자열만 그린다.
public enum RowText {
    public static func waiting(since: Date?, now: Date) -> String? {
        guard let duration = TimePhrase.duration(from: since, to: now) else { return nil }
        return "\(duration)째 기다림"
    }

    /// 확인 필요 카드의 본문. 질문 전문이 가장 먼저, 없으면 마지막 답, 그다음 상태 문구.
    public static func question(detail: String?, replyTail: String?, status: String) -> String {
        detail ?? replyTail ?? status
    }

    /// 진행 행의 인용 한 줄. 단계 이름은 스텝퍼 줄에 이미 있어 「▶ 」 로 시작하는 줄은 다시 쓰지 않는다.
    public static func activity(lastSentence: String?, nowLine: String?) -> String? {
        if let lastSentence, !lastSentence.isEmpty { return lastSentence }
        guard let nowLine, !nowLine.hasPrefix(NowLine.stagePrefix) else { return nil }
        return nowLine
    }

    public static func trail(backgroundTasks: Int?, lastTool: String?) -> String? {
        let background = backgroundTasks.flatMap { $0 > 0 ? "bg \($0)" : nil }
        switch (background, lastTool) {
        case let (background?, tool?):
            return "\(background) · \(tool)"
        case let (background?, nil):
            return background
        case let (nil, tool?):
            return tool
        case (nil, nil):
            return nil
        }
    }
}
