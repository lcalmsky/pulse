import Darwin
import Foundation
import OSLog
import PulseCore

enum LocalSessionReadError: Error {
    case sessionsDirectoryUnreadable(Error)
}

/// Claude Code 가 남기는 `<설정 루트>/sessions/*.json` 과 트랜스크립트를 읽어 화면 모델로 바꾼다.
/// 파일 IO 만 담당하고, 판단은 `LocalSessions` 가 한다.
final class LocalSessionSource {
    private static let transcriptTailBytes = 256 * 1024

    private static let stateFileLimit = 1024 * 1024
    private static let logger = Logger(subsystem: "io.github.lcalmsky.pulse", category: "session")

    private let primaryRoot: String
    private let home = NSHomeDirectory()
    private let rootDiscovery = ConfigRootDiscovery()
    private let stateDirectory: URL
    private let fileManager = FileManager.default
    private var transcriptPaths: [String: URL] = [:]
    private var sessionRoots: [String: URL] = [:]
    private var summaries = TranscriptSummaryCache()
    private var transcriptMisses: [String: TranscriptMiss] = [:]
    private var loggedStatuses: [String: String] = [:]
    private var processFacts: [String: (pid: Int, handle: String?, multiplexer: MultiplexerPane?)] = [:]

    init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        let configured = environment["CLAUDE_CONFIG_DIR"] ?? ""
        primaryRoot = configured.isEmpty ? "~/.claude" : configured
        stateDirectory = URL(
            fileURLWithPath: NSString(
                string: DeadhdState.stateDirectory(environment: environment)
            ).expandingTildeInPath
        )
    }

    func read(now: Date) throws -> [Session] {
        let roots = currentRoots()
        var sessions: [Session] = []
        var seenSessionIds: Set<String> = []
        var primaryError: Error?
        var readableRoots = 0

        for (index, root) in roots.enumerated() {
            let directory = root.appendingPathComponent("sessions")
            let names: [String]
            do {
                names = try fileManager.contentsOfDirectory(atPath: directory.path)
            } catch {
                if index == 0 { primaryError = error }
                continue
            }
            readableRoots += 1

            for name in names where LocalSessions.isSessionFileName(name) {
                let url = directory.appendingPathComponent(name)
                guard let data = try? Data(contentsOf: url),
                      let record = LocalSessions.parseRecord(data),
                      LocalSessions.shouldInclude(record),
                      isProcessAlive(record.pid),
                      seenSessionIds.insert(record.sessionId).inserted
                else { continue }

                sessionRoots[record.sessionId] = root
                let summary = transcriptSummary(for: record, now: now)
                logStatusChange(record, summary: summary)
                let facts = processFacts(for: record)
                sessions.append(LocalSessions.makeSession(
                    record: record,
                    summary: summary,
                    now: now,
                    home: home,
                    deadhd: deadhdState(for: record),
                    orcaTerminal: facts.handle,
                    multiplexer: facts.multiplexer
                ))
            }
        }
        if readableRoots == 0, let primaryError {
            throw LocalSessionReadError.sessionsDirectoryUnreadable(primaryError)
        }

        let sessionIds = Set(sessions.map(\.sessionId))
        summaries.retain(only: sessionIds)
        transcriptPaths = transcriptPaths.filter { sessionIds.contains($0.key) }
        sessionRoots = sessionRoots.filter { sessionIds.contains($0.key) }
        transcriptMisses = transcriptMisses.filter { sessionIds.contains($0.key) }
        loggedStatuses = loggedStatuses.filter { sessionIds.contains($0.key) }
        processFacts = processFacts.filter { sessionIds.contains($0.key) }
        return sessions
    }

    /// 설정 루트는 매번 다시 구한다. 새 런처가 언제든 뜰 수 있다.
    private func currentRoots() -> [URL] {
        let merged = ConfigRoots.merge(
            primary: primaryRoot,
            discovered: rootDiscovery.discoveredRoots(),
            home: home
        )
        guard let primary = merged.first else { return [] }
        var roots = [URL(fileURLWithPath: primary)]
        for path in merged.dropFirst() {
            var isDirectory: ObjCBool = false
            let sessions = URL(fileURLWithPath: path).appendingPathComponent("sessions").path
            guard fileManager.fileExists(atPath: sessions, isDirectory: &isDirectory),
                  isDirectory.boolValue
            else { continue }
            roots.append(URL(fileURLWithPath: path))
        }
        return roots
    }

    private func logStatusChange(_ record: LocalSessionRecord, summary: TranscriptSummary) {
        let status = "\(record.status ?? "-")/\(record.waitingFor ?? "-")"
        guard loggedStatuses[record.sessionId] != status else { return }
        loggedStatuses[record.sessionId] = status
        Self.logger.info(
            "상태 \(status, privacy: .public) 백그라운드 \(summary.backgroundTasks ?? 0) 세션 \(record.sessionId, privacy: .public)"
        )
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

    /// 프로세스 환경 변수는 띄운 뒤 바뀌지 않으므로 pid 가 같으면 처음 읽은 값을 쓴다.
    private func processFacts(
        for record: LocalSessionRecord
    ) -> (handle: String?, multiplexer: MultiplexerPane?) {
        if let cached = processFacts[record.sessionId], cached.pid == record.pid {
            return (cached.handle, cached.multiplexer)
        }
        // 읽기에 실패하면 다음 갱신에서 다시 읽도록 캐시하지 않는다.
        guard let args = ProcessEnvironment.procArgs(record.pid) else { return (nil, nil) }
        let handle = ProcessEnvironment.value(ProcessEnvironment.orcaTerminalHandleKey, inProcArgs: args)
        let multiplexer = Multiplexer.pane(inProcArgs: args)
        processFacts[record.sessionId] = (record.pid, handle, multiplexer)
        return (handle, multiplexer)
    }

    private func isProcessAlive(_ pid: Int) -> Bool {
        guard pid > 0 else { return false }
        errno = 0
        if kill(pid_t(pid), 0) == 0 { return true }
        return errno == EPERM
    }

    private func transcriptSummary(for record: LocalSessionRecord, now: Date) -> TranscriptSummary {
        guard let url = transcriptURL(for: record, now: now) else {
            return TranscriptSummary()
        }
        let key = transcriptFileKey(url)
        if let key, let cached = summaries.summary(for: record.sessionId, key: key) {
            return cached
        }
        guard let tail = readTail(url) else {
            return TranscriptSummary()
        }
        let summary = LocalSessions.summarizeTranscriptTail(
            tail.data,
            droppingPartialFirstLine: tail.truncated
        )
        if let key {
            summaries.store(summary, key: key, for: record.sessionId)
        }
        return summary
    }

    private func transcriptFileKey(_ url: URL) -> TranscriptFileKey? {
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path),
              let size = (attributes[.size] as? NSNumber)?.uint64Value,
              let modifiedAt = attributes[.modificationDate] as? Date
        else {
            return nil
        }
        return TranscriptFileKey(size: size, modifiedAt: modifiedAt)
    }

    private func transcriptURL(for record: LocalSessionRecord, now: Date) -> URL? {
        if let cached = transcriptPaths[record.sessionId],
           fileManager.fileExists(atPath: cached.path) {
            return cached
        }

        let fileName = record.sessionId + ".jsonl"
        guard let root = sessionRoots[record.sessionId] else { return nil }
        let projects = root.appendingPathComponent("projects")
        if let cwd = record.cwd {
            let slug = LocalSessions.projectSlug(forCwd: cwd)
            let direct = projects.appendingPathComponent(slug).appendingPathComponent(fileName)
            if fileManager.fileExists(atPath: direct.path) {
                transcriptPaths[record.sessionId] = direct
                transcriptMisses[record.sessionId] = nil
                return direct
            }
        }

        let projectsModifiedAt = (try? fileManager.attributesOfItem(atPath: projects.path))?[.modificationDate]
            as? Date
        if let miss = transcriptMisses[record.sessionId],
           !miss.needsRescan(now: now, projectsModifiedAt: projectsModifiedAt) {
            return nil
        }

        let directories = (try? fileManager.contentsOfDirectory(atPath: projects.path)) ?? []
        for directory in directories {
            let candidate = projects.appendingPathComponent(directory).appendingPathComponent(fileName)
            if fileManager.fileExists(atPath: candidate.path) {
                transcriptPaths[record.sessionId] = candidate
                transcriptMisses[record.sessionId] = nil
                return candidate
            }
        }
        transcriptMisses[record.sessionId] = TranscriptMiss(
            checkedAt: now,
            projectsModifiedAt: projectsModifiedAt
        )
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
