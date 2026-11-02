import Foundation

/// 트랜스크립트를 처음부터 이어 읽으며 백그라운드 작업의 시작과 끝을 적는 장부.
/// 꼬리만 보면 오래 전에 띄운 셸이 빠지므로 파일 전체를 ingest 한다.
public struct BackgroundLedger {
    struct Launch: Equatable {
        var taskId: String?
        var launchedAt: Date?
    }

    private var toolUseNames: [String: String] = [:]
    private var launches: [String: Launch] = [:]
    private var completedToolUseIds: Set<String> = []
    private var completedTaskIds: Set<String> = []
    /// ingest 로 넘긴 바이트 수. 다음에 파일에서 읽기 시작할 위치다.
    public private(set) var consumedBytes: UInt64 = 0
    private var pendingLine = Data()

    public init() {}

    /// 줄 단위로 나눠 완전한 줄만 처리하고, 끝에 남은 불완전한 줄은 다음 호출로 넘긴다.
    public mutating func ingest(_ chunk: Data) {
        consumedBytes += UInt64(chunk.count)
        pendingLine.append(chunk)
        var start = pendingLine.startIndex
        while let newline = pendingLine[start...].firstIndex(of: 0x0A) {
            ingest(line: Data(pendingLine[start..<newline]))
            start = pendingLine.index(after: newline)
        }
        pendingLine = Data(pendingLine[start...])
    }

    /// 이미 온전한 한 줄을 처리한다. 꼬리 요약처럼 한 번에 나눠 읽은 줄을 넘길 때 쓴다.
    mutating func ingest(line: Data) {
        guard let object = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any],
              let type = object["type"] as? String
        else { return }

        switch type {
        case "queue-operation":
            completedTaskIds.formUnion(
                LocalSessions.taskNotificationValues(
                    tag: "task-id", in: object["content"], terminalOnly: true
                )
            )
        case "attachment":
            let attachment = object["attachment"] as? [String: Any]
            if attachment?["type"] as? String == "queued_command" {
                completedTaskIds.formUnion(
                    LocalSessions.taskNotificationValues(
                        tag: "task-id", in: attachment?["prompt"], terminalOnly: true
                    )
                )
            }
        case "assistant":
            let timestamp = TimestampParser.parse(object["timestamp"] as? String)
            let message = object["message"] as? [String: Any]
            let blocks = message?["content"] as? [[String: Any]] ?? []
            for block in blocks where block["type"] as? String == "tool_use" {
                guard let id = LocalSessions.nonEmpty(block["id"] as? String) else { continue }
                if let name = LocalSessions.nonEmpty(block["name"] as? String) {
                    toolUseNames[id] = name
                }
                if (block["input"] as? [String: Any])?["run_in_background"] as? Bool == true {
                    recordLaunch(id: id, taskId: nil, at: timestamp)
                }
            }
        case "user":
            let timestamp = TimestampParser.parse(object["timestamp"] as? String)
            let message = object["message"] as? [String: Any]
            let blocks = message?["content"] as? [[String: Any]] ?? []
            let result = object["toolUseResult"] as? [String: Any]
            for block in blocks where block["type"] as? String == "tool_result" {
                guard let id = LocalSessions.nonEmpty(block["tool_use_id"] as? String) else { continue }
                if let taskId = LocalSessions.backgroundTaskId(
                    fromToolResult: result, toolName: toolUseNames[id]
                ) {
                    recordLaunch(id: id, taskId: taskId, at: timestamp)
                }
            }
            if let stopped = LocalSessions.nonEmpty(result?["task_id"] as? String) {
                completedTaskIds.insert(stopped)
            }
            completedToolUseIds.formUnion(
                LocalSessions.taskNotificationValues(tag: "tool-use-id", in: message?["content"])
            )
            completedTaskIds.formUnion(
                LocalSessions.taskNotificationValues(
                    tag: "task-id", in: message?["content"], terminalOnly: true
                )
            )
        default:
            break
        }
    }

    /// 아직 끝나지 않은 launch 수. `launchedSince` 보다 먼저 띄운 작업은 이전 프로세스의 것이라 뺀다.
    /// 시각을 모르는 launch 는 판단할 수 없으니 남긴다.
    public func pendingCount(launchedSince: Date? = nil) -> Int {
        launches.reduce(0) { count, entry in
            let (toolUseId, launch) = entry
            guard !isCompleted(toolUseId: toolUseId, launch: launch) else { return count }
            if let launchedSince, let launchedAt = launch.launchedAt, launchedAt < launchedSince {
                return count
            }
            return count + 1
        }
    }

    public func isCompleted(taskId: String) -> Bool {
        completedBackgroundTaskIds.contains(taskId)
    }

    /// 완료로 판정된 백그라운드 작업의 task id. deadhd 가 들고 있는 옛 항목을 거를 때 쓴다.
    public var completedBackgroundTaskIds: Set<String> {
        var ids = completedTaskIds
        for (toolUseId, launch) in launches {
            guard let taskId = launch.taskId else { continue }
            if completedToolUseIds.contains(toolUseId) || completedTaskIds.contains(taskId) {
                ids.insert(taskId)
            }
        }
        return ids
    }

    private func isCompleted(toolUseId: String, launch: Launch) -> Bool {
        if completedToolUseIds.contains(toolUseId) { return true }
        guard let taskId = launch.taskId else { return false }
        return completedTaskIds.contains(taskId)
    }

    private mutating func recordLaunch(id: String, taskId: String?, at launchedAt: Date?) {
        var launch = launches[id] ?? Launch()
        if launch.taskId == nil { launch.taskId = taskId }
        if launch.launchedAt == nil { launch.launchedAt = launchedAt }
        launches[id] = launch
    }
}
