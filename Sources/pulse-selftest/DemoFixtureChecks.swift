import Darwin
import Foundation
import PulseCore

/// scripts/demo.sh 가 전개한 README 용 데모 세션이 Pulse 가 읽는 그룹·단계로 보이는지 확인한다.
func runDemoFixtureChecks() {
    let repository = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let script = repository.appendingPathComponent("scripts/demo.sh").path
    let basicDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("pulse-demo-\(UUID().uuidString)")
    let manyDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("pulse-demo-many-\(UUID().uuidString)")

    // 세션 파일은 살아 있는 pid 여야만 읽히고 파일 이름도 pid 마다 달라야 해서, 전개하는 동안만 유지 프로세스를 둔다.
    var keepers: [Process] = []
    for _ in 0..<15 {
        let keeper = Process()
        keeper.executableURL = URL(fileURLWithPath: "/bin/sleep")
        keeper.arguments = ["60"]
        guard (try? keeper.run()) != nil else {
            expect(false, "데모: 유지 프로세스 실행")
            keepers.forEach { $0.terminate() }
            return
        }
        keepers.append(keeper)
    }
    defer {
        keepers.forEach { $0.terminate() }
        try? FileManager.default.removeItem(at: basicDirectory)
        try? FileManager.default.removeItem(at: manyDirectory)
    }

    guard demoRender(script, directory: basicDirectory, many: false, keepers: keepers) else { return }

    let now = Date()
    let grouped = Grouping.group(
        SessionsResponse(sessions: demoReadSessions(config: basicDirectory, now: now)),
        now: now
    )
    expectEqual(
        grouped.counts,
        GroupedSessions.Counts(attention: 1, working: 2, done: 2),
        "데모: 그룹별 개수"
    )

    let api = grouped.working.first { $0.sessionId == "6a1f0b3c-2d4e-4f5a-9b6c-1d2e3f4a5b6c" }
    expect(api != nil, "데모: api-server 가 진행 중")
    expectEqual(api?.stepStates?.count, 6, "데모: api-server 단계 수")
    expectEqual(api?.counts?.done, 3, "데모: api-server 완료 단계")
    expectEqual(api?.nowLabel, "통합 테스트 작성", "데모: api-server 현재 단계")
    expect(api?.dataPath != nil, "데모: api-server 진행 데이터 경로")
    let dataSteps = api?.dataPath
        .flatMap { try? Data(contentsOf: URL(fileURLWithPath: $0)) }
        .flatMap(Checklist.parse)
    expectEqual(dataSteps?.count, 6, "데모: api-server 체크리스트 항목 수")
    expect(grouped.allItems.contains { $0.placeText != nil }, "데모: 위치 줄이 보이는 세션")

    guard demoRender(script, directory: manyDirectory, many: true, keepers: keepers) else { return }
    let manyNow = Date()
    let manyGrouped = Grouping.group(
        SessionsResponse(sessions: demoReadSessions(config: manyDirectory, now: manyNow)),
        now: manyNow
    )
    expectEqual(
        manyGrouped.counts,
        GroupedSessions.Counts(attention: 2, working: 6, done: 7),
        "데모: 세션이 많은 묶음의 그룹별 개수"
    )
}

private func demoRender(_ script: String, directory: URL, many: Bool, keepers: [Process]) -> Bool {
    let render = Process()
    render.executableURL = URL(fileURLWithPath: "/bin/bash")
    var arguments = [script, "render"]
    if many { arguments.append("--many") }
    arguments.append(directory.path)
    render.arguments = arguments
    var environment = ProcessInfo.processInfo.environment
    environment["DEMO_PIDS"] = keepers.map { String($0.processIdentifier) }.joined(separator: ",")
    render.environment = environment
    render.standardOutput = FileHandle.nullDevice
    render.standardError = FileHandle.nullDevice
    guard (try? render.run()) != nil else {
        expect(false, "데모: render 실행")
        return false
    }
    render.waitUntilExit()
    expectEqual(render.terminationStatus, 0, "데모: render 종료 코드")
    return render.terminationStatus == 0
}

/// LocalSessionSource 는 앱 타깃에 있어 이 실행 파일에서 부를 수 없다. 같은 규칙을 PulseCore 로 다시 적용한다.
private func demoReadSessions(config: URL, now: Date) -> [Session] {
    let fileManager = FileManager.default
    let sessionsDirectory = config.appendingPathComponent("sessions")
    let stateDirectory = config.appendingPathComponent("deadhd-state")
    let names = (try? fileManager.contentsOfDirectory(atPath: sessionsDirectory.path)) ?? []

    var sessions: [Session] = []
    for name in names.sorted() where LocalSessions.isSessionFileName(name) {
        let url = sessionsDirectory.appendingPathComponent(name)
        guard let data = try? Data(contentsOf: url),
              let record = LocalSessions.parseRecord(data),
              LocalSessions.shouldInclude(record),
              demoIsAlive(record.pid)
        else { continue }

        sessions.append(LocalSessions.makeSession(
            record: record,
            summary: demoSummary(config: config, record: record),
            now: now,
            home: NSHomeDirectory(),
            deadhd: demoDeadhdState(directory: stateDirectory, sessionId: record.sessionId)
        ))
    }
    return sessions
}

private func demoSummary(config: URL, record: LocalSessionRecord) -> TranscriptSummary {
    guard let cwd = record.cwd else { return TranscriptSummary() }
    let url = config
        .appendingPathComponent("projects")
        .appendingPathComponent(LocalSessions.projectSlug(forCwd: cwd))
        .appendingPathComponent(record.sessionId + ".jsonl")
    guard let data = try? Data(contentsOf: url) else { return TranscriptSummary() }
    return LocalSessions.summarizeTranscriptTail(data, droppingPartialFirstLine: false)
}

private func demoDeadhdState(directory: URL, sessionId: String) -> DeadhdState? {
    let url = directory.appendingPathComponent(sessionId + ".json")
    guard let data = try? Data(contentsOf: url) else { return nil }
    return DeadhdState.parse(data, expectedSessionId: sessionId)
}

private func demoIsAlive(_ pid: Int) -> Bool {
    guard pid > 0 else { return false }
    errno = 0
    if kill(pid_t(pid), 0) == 0 { return true }
    return errno == EPERM
}
