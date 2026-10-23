import Foundation

public enum Density: String, CaseIterable, Equatable {
    case rich
    case compact
}

public struct SessionSection: Equatable {
    public let group: DisplayGroup
    public let items: [DisplayItem]

    public init(group: DisplayGroup, items: [DisplayItem]) {
        self.group = group
        self.items = items
    }
}

/// 팝오버 필터 칩. 전체 보기와 그룹 하나를 같은 값으로 다룬다.
public enum SessionFilter: Int, CaseIterable, Identifiable, Equatable {
    case all
    case attention
    case working
    case done

    public var id: Int { rawValue }

    public var title: String {
        guard let group else { return L10n.groupAll }
        return Self.title(for: group)
    }

    public var group: DisplayGroup? {
        switch self {
        case .all: return nil
        case .attention: return .attention
        case .working: return .working
        case .done: return .done
        }
    }

    public static func title(for group: DisplayGroup) -> String {
        switch group {
        case .attention: return L10n.groupAttention
        case .working: return L10n.groupWorking
        case .done: return L10n.groupDone
        }
    }

    public func count(in groups: GroupedSessions) -> Int {
        guard let group else { return groups.totalCount }
        return groups.items(for: group).count
    }

    /// 칩에 맞는 그룹만, 화면에 그리는 개수만큼 잘라 돌려준다. 빈 그룹은 빼 둔다.
    /// 검색어가 있으면 칩 안의 잘리지 않은 전체 항목에서 일치하는 행만 돌려준다.
    public func sections(in groups: GroupedSessions, query: String = "") -> [SessionSection] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return DisplayGroup.allCases.compactMap { candidate in
            guard group == nil || group == candidate else { return nil }
            let items: [DisplayItem]
            if trimmed.isEmpty {
                items = groups.visibleItems(for: candidate)
            } else {
                items = groups.items(for: candidate).filter { SessionSearch.matches($0, query: trimmed) }
            }
            return items.isEmpty ? nil : SessionSection(group: candidate, items: items)
        }
    }

    /// 키보드로 고를 수 있는 행. 이동 대상이 없는 행은 건너뛴다.
    public func selectableItems(in groups: GroupedSessions, query: String = "") -> [DisplayItem] {
        sections(in: groups, query: query).flatMap(\.items).filter(\.isActionable)
    }
}

public enum PopoverRowAction: Equatable {
    case hideDone
    case snooze
    case none

    public static func resolve(_ item: DisplayItem) -> PopoverRowAction {
        switch item.group {
        case .done:
            return .hideDone
        case .attention:
            return item.isStall ? .snooze : .none
        case .working:
            return .none
        }
    }
}

public enum KeyboardSelection {
    /// nil 은 아직 고른 행이 없는 상태다. 아래로 가면 처음, 위로 가면 마지막에서 시작한다.
    public static func move(from index: Int?, by step: Int, count: Int) -> Int? {
        guard count > 0 else { return nil }
        guard let index, (0..<count).contains(index) else {
            return step > 0 ? 0 : count - 1
        }
        return ((index + step) % count + count) % count
    }

    /// 처음(위) 또는 마지막(아래) 행. 고를 행이 없으면 nil.
    public static func edge(up: Bool, count: Int) -> Int? {
        guard count > 0 else { return nil }
        return up ? 0 : count - 1
    }
}

/// 단계 목록을 펼친 정도. 접힘 → 세 단계 창 → 전체 순서다.
public enum StepDisclosure: Int, Comparable {
    case collapsed
    case window
    case full

    public static func < (lhs: StepDisclosure, rhs: StepDisclosure) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// 키를 눌렀을 때 옮겨 갈 단계. `by` 는 +1(→)·-1(←), `toEnd` 는 ⌥ 동반, `canShowFull` 은 전체 단계 표시 가능 여부다.
    public static func next(
        from current: StepDisclosure,
        by step: Int,
        toEnd: Bool,
        canShowFull: Bool
    ) -> StepDisclosure {
        guard step != 0 else { return current }
        if step > 0 {
            switch current {
            case .collapsed: return toEnd && canShowFull ? .full : .window
            case .window: return canShowFull ? .full : .window
            case .full: return .full
            }
        }
        switch current {
        case .collapsed: return .collapsed
        case .window: return .collapsed
        case .full: return toEnd ? .collapsed : .window
        }
    }
}

public enum NoticeToast {
    public static let duration: TimeInterval = 5
}

public enum UndoToast {
    public static let duration: TimeInterval = 6

    /// 남은 시간 비율. 그리는 쪽에서 1 에서 0 으로 줄어드는 막대에 쓴다.
    public static func progress(elapsed: TimeInterval) -> Double {
        guard duration > 0 else { return 0 }
        return min(1, max(0, 1 - elapsed / duration))
    }
}
