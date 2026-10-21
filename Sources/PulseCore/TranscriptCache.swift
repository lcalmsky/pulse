import Foundation

/// 트랜스크립트가 바뀌었는지 가르는 키. 덧붙여 쓰는 파일이라 크기와 수정 시각을 함께 본다.
/// 크기만 보면 압축으로 같은 크기가 된 경우를, 수정 시각만 보면 같은 시각 해상도 안의 쓰기를 놓친다.
public struct TranscriptFileKey: Equatable {
    public let size: UInt64
    public let modifiedAt: Date

    public init(size: UInt64, modifiedAt: Date) {
        self.size = size
        self.modifiedAt = modifiedAt
    }
}

/// 트랜스크립트를 못 찾은 세션의 마지막 전체 스캔 기록.
public struct TranscriptMiss: Equatable {
    public let checkedAt: Date
    public let projectsModifiedAt: Date?

    public init(checkedAt: Date, projectsModifiedAt: Date?) {
        self.checkedAt = checkedAt
        self.projectsModifiedAt = projectsModifiedAt
    }

    public static let rescanInterval: TimeInterval = 30

    /// 세션을 막 열면 첫 프롬프트 뒤에야 파일이 생겨 영구히 기억하지 않는다.
    /// 30초가 지났거나 projects 디렉터리의 수정 시각이 바뀌면 다시 훑는다.
    public func needsRescan(now: Date, projectsModifiedAt current: Date?) -> Bool {
        now.timeIntervalSince(checkedAt) >= Self.rescanInterval || current != projectsModifiedAt
    }
}

/// 세션별 마지막 요약을 키와 함께 들고 있다가, 키가 같으면 다시 파싱하지 않는다.
public struct TranscriptSummaryCache {
    private struct Entry {
        let summary: TranscriptSummary
        let key: TranscriptFileKey
    }

    private var entries: [String: Entry] = [:]

    public init() {}

    /// 키가 같으면 저장된 요약, 다르거나 없으면 nil.
    public func summary(for sessionId: String, key: TranscriptFileKey) -> TranscriptSummary? {
        guard let entry = entries[sessionId], entry.key == key else { return nil }
        return entry.summary
    }

    public mutating func store(_ summary: TranscriptSummary, key: TranscriptFileKey, for sessionId: String) {
        entries[sessionId] = Entry(summary: summary, key: key)
    }

    /// 이번 틱에 보지 않은 세션을 버린다.
    public mutating func retain(only sessionIds: Set<String>) {
        entries = entries.filter { sessionIds.contains($0.key) }
    }
}
