import Foundation

/// 「완료 전부 확인」으로 가려 둔 완료 항목. 키 규칙은 `DisplayItem.acknowledgeKey` 를 따른다.
public struct DoneAcknowledgements: Equatable {
    public private(set) var keys: Set<String>
    /// 직전 확인으로 새로 가려진 키. 되돌리기 안내에 쓴다.
    public private(set) var recent: Set<String>

    public init(keys: Set<String> = []) {
        self.keys = keys
        self.recent = []
    }

    /// 지금 응답에서 12시간 창 안에 있으면서 확인으로 가려진 완료 항목.
    public func hiddenItems(in response: SessionsResponse?, now: Date) -> [DisplayItem] {
        guard let response, !keys.isEmpty else { return [] }
        return Grouping.group(response, now: now).done.filter { keys.contains($0.acknowledgeKey) }
    }

    public func hiddenCount(in response: SessionsResponse?, now: Date) -> Int {
        hiddenItems(in: response, now: now).count
    }

    /// 완료 항목을 확인 처리하고, 방금 새로 가려진 개수를 돌려준다.
    @discardableResult
    public mutating func acknowledge(_ items: [DisplayItem]) -> Int {
        let fresh = Set(items.map(\.acknowledgeKey)).subtracting(keys)
        keys.formUnion(fresh)
        recent = fresh
        return fresh.count
    }

    /// 완료 항목 하나를 확인 처리한다. 새로 가렸으면 1, 이미 가려져 있었으면 0.
    @discardableResult
    public mutating func acknowledge(_ item: DisplayItem) -> Int {
        guard !keys.contains(item.acknowledgeKey) else { return 0 }
        keys.insert(item.acknowledgeKey)
        recent = [item.acknowledgeKey]
        return 1
    }

    /// 확인한 완료를 모두 다시 보이게 한다.
    public mutating func undoAll() {
        keys.removeAll()
        recent.removeAll()
    }

    /// 직전 확인으로 가려진 항목만 다시 보이게 한다.
    @discardableResult
    public mutating func undoRecent() -> Int {
        let restored = keys.intersection(recent)
        keys.subtract(recent)
        recent.removeAll()
        return restored.count
    }

    /// 지금 응답에 없는 세션의 키를 지운다. 응답이 없는 동안은 그대로 둔다.
    public mutating func prune(keeping response: SessionsResponse?) {
        guard let response else { return }
        let live = Set(response.sessions.map(\.sessionId))
        keys = keys.filter { live.contains(DisplayItem.sessionId(fromAcknowledgeKey: $0)) }
    }
}
