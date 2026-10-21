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
    let englishBasicDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("pulse-demo-en-\(UUID().uuidString)")
    let englishManyDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("pulse-demo-en-many-\(UUID().uuidString)")

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
        try? FileManager.default.removeItem(at: englishBasicDirectory)
        try? FileManager.default.removeItem(at: englishManyDirectory)
    }

    guard demoRender(script, directory: basicDirectory, many: false, language: nil, keepers: keepers) else { return }

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

    guard demoRender(script, directory: manyDirectory, many: true, language: nil, keepers: keepers) else { return }
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

    guard demoRender(script, directory: englishBasicDirectory, many: false, language: "en", keepers: keepers) else { return }
    let englishNow = Date()
    let englishGrouped = Grouping.group(
        SessionsResponse(sessions: demoReadSessions(config: englishBasicDirectory, now: englishNow)),
        now: englishNow
    )
    expectEqual(
        englishGrouped.counts,
        GroupedSessions.Counts(attention: 1, working: 2, done: 2),
        "데모: 영어 묶음의 그룹별 개수"
    )

    let englishApi = englishGrouped.working.first { $0.sessionId == "6a1f0b3c-2d4e-4f5a-9b6c-1d2e3f4a5b6c" }
    expect(englishApi != nil, "데모: 영어 묶음에서 api-server 가 진행 중")
    expectEqual(englishApi?.stepStates?.count, 6, "데모: 영어 묶음 api-server 단계 수")
    expectEqual(englishApi?.counts?.done, 3, "데모: 영어 묶음 api-server 완료 단계")
    expectEqual(englishApi?.nowLabel, "Write integration tests", "데모: 영어 묶음 api-server 현재 단계")
    let englishDataSteps = englishApi?.dataPath
        .flatMap { try? Data(contentsOf: URL(fileURLWithPath: $0)) }
        .flatMap(Checklist.parse)
    expectEqual(englishDataSteps?.count, 6, "데모: 영어 묶음 api-server 체크리스트 항목 수")
    expectEqual(demoHangulFiles(englishBasicDirectory), [], "데모: 영어 기본 묶음에 한글 없음")

    guard demoRender(script, directory: englishManyDirectory, many: true, language: "en", keepers: keepers) else { return }
    let englishManyNow = Date()
    let englishManyGrouped = Grouping.group(
        SessionsResponse(sessions: demoReadSessions(config: englishManyDirectory, now: englishManyNow)),
        now: englishManyNow
    )
    expectEqual(
        englishManyGrouped.counts,
        GroupedSessions.Counts(attention: 2, working: 6, done: 7),
        "데모: 영어로 세션이 많은 묶음의 그룹별 개수"
    )
    expectEqual(demoHangulFiles(englishManyDirectory), [], "데모: 영어 --many 묶음에 한글 없음")
    // render 는 진행 데이터를 고정 경로에 쓰므로, 데이터 파일 전체를 덮어쓴 --many 렌더 뒤에 검사한다.
    expectEqual(
        demoHangulFiles(URL(fileURLWithPath: "/tmp/pulse-demo")),
        [],
        "데모: 영어 묶음의 진행 데이터에 한글 없음"
    )

    let englishRoot = repository.appendingPathComponent("demo/en")
    let koreanRoot = repository.appendingPathComponent("demo")
    let englishFiles = demoFiles(under: englishRoot)
    expectEqual(englishFiles.count, 23, "데모: 영어판 템플릿 수")
    for relative in englishFiles {
        expectEqual(
            demoLineCount(englishRoot.appendingPathComponent(relative)),
            demoLineCount(koreanRoot.appendingPathComponent(relative)),
            "데모: 영어판 줄 수 · \(relative)"
        )
    }
}

private func demoRender(
    _ script: String,
    directory: URL,
    many: Bool,
    language: String?,
    keepers: [Process]
) -> Bool {
    let render = Process()
    render.executableURL = URL(fileURLWithPath: "/bin/bash")
    var arguments = [script, "render"]
    if many { arguments.append("--many") }
    if let language {
        arguments.append("--lang")
        arguments.append(language)
    }
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

/// 루트 아래 일반 파일의 상대 경로 목록.
private func demoFiles(under root: URL) -> [String] {
    let fileManager = FileManager.default
    guard let enumerator = fileManager.enumerator(
        at: root,
        includingPropertiesForKeys: [.isRegularFileKey]
    ) else { return [] }
    var relatives: [String] = []
    for case let url as URL in enumerator {
        let isFile = (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true
        guard isFile else { continue }
        relatives.append(url.path.replacingOccurrences(of: root.path + "/", with: ""))
    }
    return relatives.sorted()
}

private func demoLineCount(_ url: URL) -> Int? {
    guard let data = try? Data(contentsOf: url),
          let text = String(data: data, encoding: .utf8)
    else { return nil }
    return text.reduce(0) { $1 == "\n" ? $0 + 1 : $0 }
}

/// 한글(가-힣)이 남아 있는 파일의 경로 목록.
private func demoHangulFiles(_ root: URL) -> [String] {
    var hits: [String] = []
    for relative in demoFiles(under: root) {
        let url = root.appendingPathComponent(relative)
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8)
        else { continue }
        if text.range(of: "[가-힣]", options: .regularExpression) != nil {
            hits.append(relative)
        }
    }
    return hits
}

private func demoIsAlive(_ pid: Int) -> Bool {
    guard pid > 0 else { return false }
    errno = 0
    if kill(pid_t(pid), 0) == 0 { return true }
    return errno == EPERM
}
