import Darwin
import Foundation
import PulseCore

enum LocalSessionReadError: Error {
    case sessionsDirectoryUnreadable(Error)
}

/// Claude Code 가 남기는 `<설정 루트>/sessions/*.json` 과 트랜스크립트를 읽어 화면 모델로 바꾼다.
/// 파일 IO 만 담당하고, 판단은 `LocalSessions` 가 한다.
final class LocalSessionSource {
    private static let transcriptTailBytes = 256 * 1024

    private static let stateFileLimit = 1024 * 1024

    private let root: URL
    private let stateDirectory: URL
    private let fileManager = FileManager.default
    private var transcriptPaths: [String: URL] = [:]

    init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        let configured = environment["CLAUDE_CONFIG_DIR"] ?? "~/.claude"
        root = URL(fileURLWithPath: NSString(string: configured).expandingTildeInPath)
        stateDirectory = URL(
            fileURLWithPath: NSString(
                string: DeadhdState.stateDirectory(environment: environment)
            ).expandingTildeInPath
        )
    }

    func read(now: Date) throws -> [Session] {
        let directory = root.appendingPathComponent("sessions").path
        let names: [String]
        do {
            names = try fileManager.contentsOfDirectory(atPath: directory)
        } catch {
            throw LocalSessionReadError.sessionsDirectoryUnreadable(error)
        }

        var sessions: [Session] = []
        for name in names where LocalSessions.isSessionFileName(name) {
            let url = root.appendingPathComponent("sessions").appendingPathComponent(name)
            guard let data = try? Data(contentsOf: url),
                  let record = LocalSessions.parseRecord(data),
                  LocalSessions.shouldInclude(record),
                  isProcessAlive(record.pid)
            else { continue }

            let summary = transcriptSummary(for: record)
            sessions.append(LocalSessions.makeSession(
                record: record,
                summary: summary,
                now: now,
                home: NSHomeDirectory(),
                deadhd: deadhdState(for: record)
            ))
        }
        return sessions
    }

    private func deadhdState(for record: LocalSessionRecord) -> DeadhdState? {
        guard DeadhdState.isValidSessionId(record.sessionId) else { return nil }
        let url = stateDirectory.appendingPathComponent(record.sessionId + ".json")
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path),
              attributes[.type] as? FileAttributeType == .typeRegular,
              ((attributes[.size] as? NSNumber)?.intValue ?? Int.max) <= Self.stateFileLimit,
              let data = try? Data(contentsOf: url)
        else {
            return nil
        }
        guard var state = DeadhdState.parse(data, expectedSessionId: record.sessionId) else {
            return nil
        }
        // HTML 이 아직 없어도 데이터 파일이 있으면 누를 때 만들 수 있어 경로를 남긴다.
        if let page = state.pagePath,
           !fileManager.fileExists(atPath: page),
           state.dataPath.map({ fileManager.fileExists(atPath: $0) }) != true {
            state.pagePath = nil
        }
        return state
    }

    private func isProcessAlive(_ pid: Int) -> Bool {
        guard pid > 0 else { return false }
        errno = 0
        if kill(pid_t(pid), 0) == 0 { return true }
        return errno == EPERM
    }

    private func transcriptSummary(for record: LocalSessionRecord) -> TranscriptSummary {
        guard let url = transcriptURL(for: record),
              let tail = readTail(url)
        else {
            return TranscriptSummary()
        }
        return LocalSessions.summarizeTranscriptTail(
            tail.data,
            droppingPartialFirstLine: tail.truncated
        )
    }

    private func transcriptURL(for record: LocalSessionRecord) -> URL? {
        if let cached = transcriptPaths[record.sessionId],
           fileManager.fileExists(atPath: cached.path) {
            return cached
        }

        let fileName = record.sessionId + ".jsonl"
        let projects = root.appendingPathComponent("projects")
        if let cwd = record.cwd {
            let slug = LocalSessions.projectSlug(forCwd: cwd)
            let direct = projects.appendingPathComponent(slug).appendingPathComponent(fileName)
            if fileManager.fileExists(atPath: direct.path) {
                transcriptPaths[record.sessionId] = direct
                return direct
            }
        }

        let directories = (try? fileManager.contentsOfDirectory(atPath: projects.path)) ?? []
        for directory in directories {
            let candidate = projects.appendingPathComponent(directory).appendingPathComponent(fileName)
            if fileManager.fileExists(atPath: candidate.path) {
                transcriptPaths[record.sessionId] = candidate
                return candidate
            }
        }
        return nil
    }

    private func readTail(_ url: URL) -> (data: Data, truncated: Bool)? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        let limit = UInt64(Self.transcriptTailBytes)
        let offset = size > limit ? size - limit : 0
        guard (try? handle.seek(toOffset: offset)) != nil else { return nil }
        let data = (try? handle.readToEnd()) ?? Data()
        return (data, offset > 0)
    }
}
