import Foundation

/// deadhd 체크리스트 JSON 의 단계 상태.
public enum StepState: String, Equatable {
    case done
    case now
    case side
    case left
    case blocked
}

public struct ChecklistStep: Equatable {
    public let label: String
    public let state: StepState
    public let sub: String?
    public let doneAt: Date?

    public init(label: String, state: StepState, sub: String? = nil, doneAt: Date? = nil) {
        self.label = label
        self.state = state
        self.sub = sub
        self.doneAt = doneAt
    }
}

public enum Checklist {
    /// JSON 최상위가 객체가 아니거나 `items` 가 배열이 아니면 nil. 객체가 아닌 항목은 건너뛴다.
    /// 알 수 없는 상태 문자열은 `.left` 로 읽는다.
    public static func parse(_ data: Data) -> [ChecklistStep]? {
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let items = object["items"] as? [Any]
        else { return nil }

        var steps: [ChecklistStep] = []
        for item in items {
            guard let item = item as? [String: Any] else { continue }
            let state = trimmed(item["state"]).flatMap(StepState.init(rawValue:)) ?? .left
            let label = [trimmed(item["label"]), trimmed(item["title"]), trimmed(item["id"])]
                .compactMap { $0 }
                .first ?? L10n.stepFallback(steps.count + 1)
            steps.append(ChecklistStep(
                label: label,
                state: state,
                sub: trimmed(item["sub"]),
                doneAt: TimestampParser.parse(trimmed(item["doneAt"]))
            ))
        }
        return steps
    }

    private static func trimmed(_ value: Any?) -> String? {
        guard let raw = value as? String else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

/// 펼친 행에서 세 줄만 보여 줄 때 어느 단계를 고를지.
public struct StepWindow: Equatable {
    public let rows: [Int]
    public let hiddenBefore: Int
    public let total: Int

    public var hasHidden: Bool { total > rows.count }

    private init(rows: [Int], hiddenBefore: Int, total: Int) {
        self.rows = rows
        self.hiddenBefore = hiddenBefore
        self.total = total
    }

    /// 직전 완료·지금·다음을 기본으로 하고, 창 밖에 막힌 단계가 있으면 한 자리를 바꿔 넣는다.
    public static func make(_ states: [StepState]) -> StepWindow {
        let total = states.count
        guard total > 0 else { return StepWindow(rows: [], hiddenBefore: 0, total: 0) }

        let focus = states.firstIndex(of: .now)
            ?? states.firstIndex(of: .side)
            ?? states.firstIndex(of: .blocked)
            ?? states.firstIndex(of: .left)
            ?? (total - 1)
        let start = min(max(focus - 1, 0), max(total - 3, 0))
        var rows = Array(start ..< min(total, start + 3))

        if let blocked = states.firstIndex(of: .blocked), !rows.contains(blocked) {
            if let last = rows.last, blocked > last {
                rows[rows.count - 1] = blocked
            } else if let first = rows.first, blocked < first {
                rows[0] = blocked
            }
            rows.sort()
        }
        return StepWindow(rows: rows, hiddenBefore: rows.first ?? 0, total: total)
    }

    /// 접힌 줄에 쓰는 문구. 숨은 단계가 없으면 nil.
    public static func headText(
        _ steps: [ChecklistStep],
        window: StepWindow,
        timeZone: TimeZone = .current
    ) -> String? {
        guard window.hasHidden else { return nil }
        guard window.hiddenBefore > 0 else {
            return L10n.showAllSteps(window.total)
        }

        let leading = Array(steps.prefix(window.hiddenBefore))
        let doneCount = leading.filter { $0.state == .done }.count
        guard doneCount == leading.count else {
            return L10n.earlierStepsPartlyDone(window.hiddenBefore, done: doneCount)
        }

        var text = L10n.earlierStepsDone(window.hiddenBefore)
        let times = leading.compactMap(\.doneAt).sorted()
        if let first = times.first, let last = times.last {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = timeZone
            formatter.dateFormat = "HH:mm"
            let start = formatter.string(from: first)
            text += first == last ? " · \(start)" : " · \(start) – \(formatter.string(from: last))"
        }
        return text
    }

    /// 각 줄 오른쪽의 작은 글자.
    public static func trailingText(_ steps: [ChecklistStep], index: Int) -> String? {
        guard steps.indices.contains(index) else { return nil }
        let step = steps[index]
        if step.state == .left, index == steps.count - 1 {
            return step.sub.map { "\($0) · \(L10n.lastStep)" } ?? L10n.lastStep
        }
        return step.sub
    }
}
