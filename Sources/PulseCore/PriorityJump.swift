import Foundation

/// 키보드로 옮겨 갈 우선순위 세션을 고른다.
public enum PriorityJump {
    public enum Kind {
        /// 답을 기다리는 세션. 오래 기다린 순으로 돌아간다.
        case reply
        /// 끝난 세션. 가장 오래전에 끝난 것부터 연다.
        case done
    }

    /// `after` 는 직전에 Space 로 옮겨 간 세션이다. 답 대기에서만 순환 기준으로 쓴다.
    public static func target(_ kind: Kind, in groups: GroupedSessions, after lastSessionId: String?) -> DisplayItem? {
        switch kind {
        case .reply:
            let candidates = groups.attention.filter { !$0.isStall && $0.isActionable }
            guard !candidates.isEmpty else { return nil }
            guard let lastSessionId,
                  let index = candidates.firstIndex(where: { $0.sessionId == lastSessionId }) else {
                return candidates.first
            }
            return candidates[(index + 1) % candidates.count]
        case .done:
            return groups.done.last { $0.isActionable }
        }
    }
}
