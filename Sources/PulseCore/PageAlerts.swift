import Foundation

public struct PageAlert: Equatable {
    public let version: Int
    public let pageId: String
    public let worktree: String
    public let url: String
    public let label: String
    public let createdAt: Date
    public let terminalHandle: String?
    public let sessionId: String?
    public let sessionName: String?
    public let fileName: String
}

public struct PageAlertReadResult: Equatable {
    public let alerts: [PageAlert]
    /// 읽지 못한 파일의 이름. 조용히 버리지 않고 화면에 남긴다.
    public let unreadableFiles: [String]
    /// 디렉터리가 있는데 목록을 읽지 못했을 때만 true. 디렉터리가 없으면 0건이고 오류가 아니다.
    public let directoryUnreadable: Bool

    public init(alerts: [PageAlert] = [], unreadableFiles: [String] = [], directoryUnreadable: Bool = false) {
        self.alerts = alerts
        self.unreadableFiles = unreadableFiles
        self.directoryUnreadable = directoryUnreadable
    }
}

public enum PageAlerts {
    public static let defaultDirectory = "~/.pulse/pages"

    public static func directory(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        let configured = environment["PULSE_PAGES_DIR"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let raw = configured.flatMap { $0.isEmpty ? nil : $0 } ?? defaultDirectory
        return URL(fileURLWithPath: (raw as NSString).expandingTildeInPath)
    }

    /// 쓰는 쪽은 `.<id>.json.tmp` 에 쓴 뒤 mv 하므로, 점으로 시작하는 파일은 아직 완성되지 않은 쓰기다.
    public static func isPageFileName(_ name: String) -> Bool {
        !name.hasPrefix(".") && name.hasSuffix(".json")
    }

    public static func parse(data: Data, fileName: String) -> PageAlert? {
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data) else { return nil }
        guard let pageId = nonEmpty(payload.pageId),
              let worktree = nonEmpty(payload.worktree),
              let url = nonEmpty(payload.url),
              let label = nonEmpty(payload.label),
              let createdAt = TimestampParser.parse(payload.createdAt)
        else { return nil }
        return PageAlert(
            version: payload.version ?? 1,
            pageId: pageId,
            worktree: worktree,
            url: url,
            label: label,
            createdAt: createdAt,
            terminalHandle: nonEmpty(payload.terminalHandle),
            sessionId: nonEmpty(payload.sessionId),
            sessionName: nonEmpty(payload.sessionName),
            fileName: fileName
        )
    }

    public static func load(directory: URL) -> PageAlertReadResult {
        let names: [String]
        do {
            names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        } catch {
            let exists = FileManager.default.fileExists(atPath: directory.path)
            return PageAlertReadResult(directoryUnreadable: exists)
        }

        var alerts: [PageAlert] = []
        var unreadable: [String] = []
        for name in names where isPageFileName(name) {
            let url = directory.appendingPathComponent(name)
            guard let data = try? Data(contentsOf: url),
                  let alert = parse(data: data, fileName: name)
            else {
                unreadable.append(name)
                continue
            }
            alerts.append(alert)
        }
        return PageAlertReadResult(
            alerts: sorted(alerts),
            unreadableFiles: unreadable.sorted()
        )
    }

    public static func sorted(_ alerts: [PageAlert]) -> [PageAlert] {
        alerts.sorted { left, right in
            if left.createdAt != right.createdAt { return left.createdAt < right.createdAt }
            return left.pageId < right.pageId
        }
    }

    /// session_id 가 있으면 그 세션만, 없으면 같은 Orca 터미널을 쓰는 세션이다.
    public static func alerts(for item: DisplayItem, in alerts: [PageAlert]) -> [PageAlert] {
        sorted(alerts.filter { alert in
            if let sessionId = alert.sessionId {
                return sessionId == item.sessionId
            }
            guard let handle = alert.terminalHandle, let terminal = item.orcaTerminal else { return false }
            return handle == terminal
        })
    }

    public static func rowText(for alerts: [PageAlert]) -> String? {
        let ordered = sorted(alerts)
        guard let first = ordered.first else { return nil }
        let extra = ordered.count - 1
        return extra > 0 ? "\(first.label) +\(extra)" : first.label
    }

    public static func tabTarget(in alerts: [PageAlert]) -> PageAlert? {
        sorted(alerts).first
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty
        else { return nil }
        return trimmed
    }

    private struct Payload: Decodable {
        let version: Int?
        let pageId: String?
        let worktree: String?
        let url: String?
        let label: String?
        let createdAt: String?
        let terminalHandle: String?
        let sessionId: String?
        let sessionName: String?

        enum CodingKeys: String, CodingKey {
            case version
            case pageId = "page_id"
            case worktree
            case url
            case label
            case createdAt = "created_at"
            case terminalHandle = "terminal_handle"
            case sessionId = "session_id"
            case sessionName = "session_name"
        }
    }
}
