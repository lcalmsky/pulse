import Foundation
import DeadhdBarCore

var checks = 0
var failures = 0

func expect(_ condition: Bool, _ label: String) {
    checks += 1
    if !condition {
        failures += 1
        FileHandle.standardError.write(Data("FAIL: \(label)\n".utf8))
    }
}

func expectEqual<T: Equatable>(_ actual: T, _ expected: T, _ label: String) {
    checks += 1
    if actual != expected {
        failures += 1
        let message = "FAIL: \(label)\n  expected: \(expected)\n  actual:   \(actual)\n"
        FileHandle.standardError.write(Data(message.utf8))
    }
}

func decode(_ json: String) -> SessionsResponse? {
    try? JSONDecoder().decode(SessionsResponse.self, from: Data(json.utf8))
}

func utcDate(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0, _ second: Int = 0) -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    var components = DateComponents()
    components.year = year
    components.month = month
    components.day = day
    components.hour = hour
    components.minute = minute
    components.second = second
    return calendar.date(from: components)!
}

// MARK: - 관대한 디코딩

let lenientJSON = """
{
  "unexpectedTopLevel": true,
  "renderedAt": null,
  "sessions": [
    {
      "sessionId": "a",
      "bucket": "wait",
      "title": null,
      "key": 123,
      "unknownField": {"nested": true},
      "place": {"label": "shop", "branch": null, "extra": 1},
      "backgroundTasks": [{"type": "shell", "description": "npm test"}],
      "lastTool": {"name": "Bash", "at": "2026-10-20T18:00:00+09:00", "durationMs": 12}
    },
    {"sessionId": "b", "bucket": "working", "since": "2026-10-20T18:00:00+09:00"},
    {"sessionId": "c"},
    {"bucket": "done"}
  ]
}
"""
if let response = decode(lenientJSON) {
    expectEqual(response.sessions.count, 3, "관대한 디코딩: sessionId 없는 세션은 버린다")
    expectEqual(response.renderedAt, nil, "관대한 디코딩: null renderedAt")
    let first = response.sessions[0]
    expectEqual(first.title, nil, "관대한 디코딩: null title")
    expectEqual(first.key, nil, "관대한 디코딩: 타입이 다른 key 는 무시")
    expectEqual(first.place?.label, "shop", "관대한 디코딩: place.label")
    expectEqual(first.place?.branch, nil, "관대한 디코딩: null place.branch")
    expectEqual(first.backgroundTasks.first?.taskDescription, "npm test", "관대한 디코딩: backgroundTasks")
    expectEqual(first.lastTool?.name, "Bash", "관대한 디코딩: lastTool.name")
    expectEqual(first.lastTool?.durationMs, 12, "관대한 디코딩: lastTool.durationMs")
    expectEqual(response.sessions[1].bucket, "working", "관대한 디코딩: 필드 누락")
} else {
    expect(false, "관대한 디코딩: 응답을 읽지 못했다")
}

if let response = decode("{}") {
    expectEqual(response.sessions.count, 0, "관대한 디코딩: sessions 없음")
    expectEqual(response.renderedAt, nil, "관대한 디코딩: renderedAt 없음")
} else {
    expect(false, "관대한 디코딩: 빈 객체를 읽지 못했다")
}

if let response = decode("{\"sessions\": \"nope\"}") {
    expectEqual(response.sessions.count, 0, "관대한 디코딩: sessions 타입 불일치")
} else {
    expect(false, "관대한 디코딩: sessions 타입 불일치에서 실패했다")
}

// MARK: - ISO8601

let secondsOffset = TimestampParser.parse("2026-10-20T18:30:00+09:00")
expectEqual(secondsOffset, utcDate(2026, 10, 20, 9, 30), "ISO8601: 초 단위 + 시간대")

let millisOffset = TimestampParser.parse("2026-10-20T18:30:00.250+09:00")
expectEqual(millisOffset, utcDate(2026, 10, 20, 9, 30).addingTimeInterval(0.25), "ISO8601: 밀리초 + 시간대")

let zulu = TimestampParser.parse("2026-10-20T09:30:00Z")
expectEqual(zulu, utcDate(2026, 10, 20, 9, 30), "ISO8601: Z 표기")

let millisZulu = TimestampParser.parse("2026-10-20T09:30:00.500Z")
expectEqual(millisZulu, utcDate(2026, 10, 20, 9, 30).addingTimeInterval(0.5), "ISO8601: 밀리초 + Z")

expectEqual(TimestampParser.parse("not a date"), nil, "ISO8601: 잘못된 문자열")
expectEqual(TimestampParser.parse(nil), nil, "ISO8601: nil")

// MARK: - 시간 문구

let now = utcDate(2026, 10, 20, 12, 0, 0)
expectEqual(TimePhrase.elapsed(from: now.addingTimeInterval(-30), to: now), "방금", "시간 문구: 30초")
expectEqual(TimePhrase.elapsed(from: now.addingTimeInterval(-60), to: now), "1분", "시간 문구: 1분")
expectEqual(TimePhrase.elapsed(from: now.addingTimeInterval(-3599), to: now), "59분", "시간 문구: 59분")
expectEqual(TimePhrase.elapsed(from: now.addingTimeInterval(-3600), to: now), "1시간", "시간 문구: 1시간")
expectEqual(TimePhrase.elapsed(from: now.addingTimeInterval(-7200), to: now), "2시간", "시간 문구: 2시간")
expectEqual(TimePhrase.elapsed(from: nil, to: now), nil, "시간 문구: 기준 없음")
expectEqual(TimePhrase.duration(from: now.addingTimeInterval(-10), to: now), "1분", "단위 문구: 10초는 1분")
expectEqual(TimePhrase.duration(from: now.addingTimeInterval(-900), to: now), "15분", "단위 문구: 15분")

// MARK: - 버킷 → 그룹

func session(
    _ id: String,
    _ bucket: String,
    minutesAgo: Double = 5,
    message: String? = nil,
    replyTail: String? = nil,
    place: Place? = nil,
    tasks: [BackgroundTask] = [],
    nowLabel: String? = nil
) -> Session {
    Session(
        sessionId: id,
        bucket: bucket,
        title: id,
        since: now.addingTimeInterval(-minutesAgo * 60),
        message: message,
        replyTail: replyTail,
        place: place,
        backgroundTasks: tasks,
        nowLabel: nowLabel
    )
}

let allBuckets = [
    session("wait", "wait"),
    session("idle", "idle"),
    session("stall", "stall", minutesAgo: 7, tasks: [BackgroundTask(type: "shell", taskDescription: "npm test")]),
    session("working", "working", minutesAgo: 3, nowLabel: "테스트 실행"),
    session("untracked", "untracked"),
    session("done", "done"),
    session("ended", "ended"),
    session("off", "off"),
    session("stale", "stale"),
    session("unknown", "mystery"),
]
let grouped = Grouping.group(SessionsResponse(sessions: allBuckets), now: now)
expectEqual(grouped.counts, GroupedSessions.Counts(attention: 3, working: 2, done: 2), "그룹: 버킷별 개수")
expect(!grouped.items(for: .attention).contains { $0.sessionId == "off" }, "그룹: off 숨김")
expect(!grouped.items(for: .attention).contains { $0.sessionId == "stale" }, "그룹: stale 숨김")
expect(!grouped.items(for: .done).contains { $0.sessionId == "unknown" }, "그룹: 모르는 버킷 숨김")

// MARK: - 상태 문구

let byId = Dictionary(uniqueKeysWithValues: grouped.items(for: .attention).map { ($0.sessionId, $0) })
    .merging(grouped.items(for: .working).map { ($0.sessionId, $0) }) { a, _ in a }
    .merging(grouped.items(for: .done).map { ($0.sessionId, $0) }) { a, _ in a }

expectEqual(byId["wait"]?.status, "권한을 허락해 주세요", "문구: wait 기본")
expectEqual(byId["idle"]?.status, "답을 기다리고 있어요", "문구: idle")
expectEqual(byId["stall"]?.status, "백그라운드 작업 7분째 · npm test", "문구: stall 백그라운드")
expectEqual(byId["working"]?.status, "3분째 · 테스트 실행", "문구: working")
expectEqual(byId["untracked"]?.status, "진행 중이에요", "문구: untracked")
expectEqual(byId["done"]?.status, "완료했어요", "문구: done")
expectEqual(byId["ended"]?.status, "5분 전 끝남", "문구: ended")

let messageGroup = Grouping.group(
    SessionsResponse(sessions: [session("msg", "wait", message: "결제 API 배포를 승인해 주세요")]),
    now: now
)
expectEqual(messageGroup.attention.first?.status, "결제 API 배포를 승인해 주세요", "문구: wait 메시지")
expectEqual(messageGroup.attention.first?.isActionable, false, "행동: 대상 없음")

let idleGroup = Grouping.group(
    SessionsResponse(sessions: [session("i", "idle", replyTail: "리뷰 반영 중입니다\n두 번째 줄")]),
    now: now
)
expectEqual(idleGroup.attention.first?.status, "답을 기다리고 있어요", "문구: idle 첫 줄")
expectEqual(idleGroup.attention.first?.detail, "리뷰 반영 중입니다 두 번째 줄", "문구: idle 둘째 줄")
expectEqual(idleGroup.attention.first?.placeText, nil, "부제: place 없음")

let stallGroup = Grouping.group(
    SessionsResponse(sessions: [session("s", "stall", minutesAgo: 12)]),
    now: now
)
expectEqual(stallGroup.attention.first?.status, "작업 12분째 · 멈췄는지 확인해 보세요", "문구: stall 기본")

let endedRecent = Grouping.group(
    SessionsResponse(sessions: [session("e", "ended", minutesAgo: 0.5, replyTail: "마무리했습니다")]),
    now: now
)
expectEqual(endedRecent.done.first?.status, "방금 끝났어요", "문구: ended 방금")
expectEqual(endedRecent.done.first?.detail, "마무리했습니다", "문구: ended 둘째 줄")

let placed = Grouping.group(
    SessionsResponse(sessions: [session("p", "working", place: Place(label: "shop", branch: "main"))]),
    now: now
)
expectEqual(placed.working.first?.placeText, "shop · main", "부제: label · branch")

// MARK: - 완료 숨김

let doneSession = session("done", "done")
let doneGrouped = Grouping.group(SessionsResponse(sessions: [doneSession]), now: now)
let doneKey = doneGrouped.done[0].acknowledgeKey
expectEqual(doneKey, DisplayItem.acknowledgeKey(sessionId: "done", since: doneSession.since), "완료 키: sessionId+since")
let acknowledged = Grouping.group(
    SessionsResponse(sessions: [doneSession]),
    now: now,
    acknowledgedDone: [doneKey]
)
expectEqual(acknowledged.done.count, 0, "완료 숨김: 확인한 항목 제외")
expectEqual(acknowledged.totalCount, 0, "완료 숨김: 개수에서도 제외")

// MARK: - 더 기다리기

let stallItem = stallGroup.attention[0]
let snoozed = Grouping.group(
    SessionsResponse(sessions: [session("s", "stall", minutesAgo: 12)]),
    now: now,
    snoozedUntil: ["s": now.addingTimeInterval(600)]
)
expectEqual(snoozed.attention.count, 0, "더 기다리기: 확인 필요에서 빠진다")
expectEqual(snoozed.working.count, 1, "더 기다리기: 진행 중으로 내려간다")
expectEqual(snoozed.working.first?.status, "12분째", "더 기다리기: 진행 중 문구")
expectEqual(stallItem.isStall, true, "더 기다리기: stall 표시 유지")

let expired = Grouping.group(
    SessionsResponse(sessions: [session("s", "stall", minutesAgo: 12)]),
    now: now,
    snoozedUntil: ["s": now.addingTimeInterval(-1)]
)
expectEqual(expired.attention.count, 1, "더 기다리기: 10분 뒤 되돌아온다")

// MARK: - 정렬

let ordered = Grouping.group(
    SessionsResponse(sessions: [
        session("recent", "wait", minutesAgo: 2),
        session("old", "wait", minutesAgo: 10),
    ]),
    now: now
)
expectEqual(ordered.attention.map(\.sessionId), ["old", "recent"], "정렬: 확인 필요는 오래 기다린 순")

// MARK: - 완료 그룹 제한

let doneWindow = Grouping.group(
    SessionsResponse(sessions: [
        session("within", "done", minutesAgo: 720),
        session("outside", "ended", minutesAgo: 721),
    ]),
    now: now
)
expectEqual(doneWindow.done.map(\.sessionId), ["within"], "완료 제한: 12시간 경계 포함, 넘으면 제외")

let doneTimeless = Grouping.group(
    SessionsResponse(sessions: [
        Session(sessionId: "nodate", bucket: "done"),
        Session(sessionId: "updatedOnly", bucket: "ended", updatedAt: now.addingTimeInterval(-3600)),
    ]),
    now: now
)
expectEqual(doneTimeless.done.map(\.sessionId), ["updatedOnly"], "완료 제한: 시각 없는 완료 제외, updatedAt 대체")

let doneOrdered = Grouping.group(
    SessionsResponse(sessions: [
        session("oldDone", "done", minutesAgo: 600),
        session("newDone", "done", minutesAgo: 10),
        session("midDone", "done", minutesAgo: 120),
    ]),
    now: now
)
expectEqual(doneOrdered.done.map(\.sessionId), ["newDone", "midDone", "oldDone"], "정렬: 완료는 최근 끝난 순")

let manyDone = Grouping.group(
    SessionsResponse(sessions: (0..<7).map { session("done\($0)", "done", minutesAgo: Double($0 + 1)) }),
    now: now
)
expectEqual(manyDone.counts.done, 7, "완료 잘라내기: 배지와 헤더는 전체 개수")
expectEqual(manyDone.visibleItems(for: .done).count, 5, "완료 잘라내기: 보이는 항목 5개")
expectEqual(manyDone.visibleItems(for: .done).map(\.sessionId), ["done0", "done1", "done2", "done3", "done4"],
            "완료 잘라내기: 최근 것부터 5개")
expectEqual(manyDone.hiddenDoneCount, 2, "완료 잘라내기: 남은 개수")
expectEqual(manyDone.doneOverflowText, "그 밖에 2개", "완료 잘라내기: 남은 개수 문구")

let manyWorking = Grouping.group(
    SessionsResponse(sessions: (0..<7).map { session("work\($0)", "working", minutesAgo: Double($0 + 1)) }),
    now: now
)
expectEqual(manyWorking.visibleItems(for: .working).count, 7, "완료 잘라내기: 다른 그룹은 자르지 않는다")

let fewDone = Grouping.group(
    SessionsResponse(sessions: (0..<5).map { session("few\($0)", "done", minutesAgo: Double($0 + 1)) }),
    now: now
)
expectEqual(fewDone.hiddenDoneCount, 0, "완료 잘라내기: 5개 이하면 남지 않는다")
expectEqual(fewDone.doneOverflowText, nil, "완료 잘라내기: 5개 이하면 문구 없음")

// MARK: - 클릭 규칙

expectEqual(SessionClick.resolve(href: nil, orcaTerminal: nil), SessionClickAction.none,
            "클릭 규칙: 둘 다 없으면 비활성")
expectEqual(SessionClick.resolve(href: "  ", orcaTerminal: " "), SessionClickAction.none,
            "클릭 규칙: 공백뿐이면 없는 것으로 본다")
expectEqual(SessionClick.resolve(href: nil, orcaTerminal: "term-1"), .orca("term-1"),
            "클릭 규칙: 페이지가 없으면 Orca")
expectEqual(
    SessionClick.resolve(href: "http://127.0.0.1:47320/deadhd-x.html", orcaTerminal: "term-1"),
    .detail("http://127.0.0.1:47320/deadhd-x.html"),
    "클릭 규칙: 페이지가 있으면 Orca 보다 페이지"
)
expectEqual(SessionClick.resolve(href: "", orcaTerminal: " term-1 "), .orca("term-1"),
            "클릭 규칙: 앞뒤 공백을 지운다")
expectEqual(SessionClick.resolve(href: nil, orcaTerminal: nil, cwd: "/a/b"), .cwd("/a/b"),
            "클릭 규칙: 핸들이 없으면 cwd 로 찾는다")
expectEqual(SessionClick.resolve(href: nil, orcaTerminal: "term-1", cwd: "/a/b"), .orca("term-1"),
            "클릭 규칙: cwd 보다 핸들")
expectEqual(SessionClick.resolve(href: "http://a", orcaTerminal: nil, cwd: "/a/b"), .detail("http://a"),
            "클릭 규칙: cwd 보다 페이지")
expectEqual(SessionClick.resolve(href: nil, orcaTerminal: nil, cwd: "  "), SessionClickAction.none,
            "클릭 규칙: 공백뿐인 cwd 는 없는 것으로 본다")

let clickGrouped = Grouping.group(
    SessionsResponse(sessions: [
        Session(sessionId: "page", bucket: "working", orcaTerminal: "t", href: "http://a"),
        Session(sessionId: "orca", bucket: "working", orcaTerminal: "t"),
        Session(sessionId: "cwd", bucket: "working", cwd: "/a/b"),
        Session(sessionId: "none", bucket: "working"),
    ]),
    now: now
)
let clickItems: [String: DisplayItem] = Dictionary(
    uniqueKeysWithValues: clickGrouped.working.map { ($0.sessionId, $0) }
)
expectEqual(clickItems["page"]?.clickAction, .detail("http://a"), "클릭 규칙: 항목이 상세 창으로 간다")
expectEqual(clickItems["orca"]?.clickAction, .orca("t"), "클릭 규칙: 항목이 Orca 로 간다")
expectEqual(clickItems["page"]?.isActionable, true, "클릭 규칙: 페이지 항목은 누를 수 있다")
expectEqual(clickItems["cwd"]?.clickAction, .cwd("/a/b"), "클릭 규칙: cwd 만 있어도 Orca 로 간다")
expectEqual(clickItems["cwd"]?.isActionable, true, "클릭 규칙: cwd 만 있어도 누를 수 있다")
expectEqual(clickItems["none"]?.isActionable, false, "클릭 규칙: 대상 없는 항목은 비활성")

// MARK: - Orca 터미널 cwd 매칭

func terminal(
    _ handle: String,
    _ worktreePath: String?,
    connected: Bool = true,
    lastOutputAt: Double? = nil
) -> OrcaTerminal {
    OrcaTerminal(handle: handle, worktreePath: worktreePath, connected: connected, lastOutputAt: lastOutputAt)
}

let oneTerminal = [terminal("exact", "/a/b")]
expectEqual(OrcaTerminalMatch.bestHandle(for: "/a/b", among: oneTerminal), "exact", "터미널 매칭: 정확히 일치")
expectEqual(OrcaTerminalMatch.bestHandle(for: "/a/b", among: [terminal("exact", "/a/b/")]), "exact",
            "터미널 매칭: 끝 슬래시 정규화")
expectEqual(OrcaTerminalMatch.bestHandle(for: "/a/b/sub", among: oneTerminal), "exact", "터미널 매칭: 하위 경로")
expectEqual(OrcaTerminalMatch.bestHandle(for: "/a/bc", among: oneTerminal), nil, "터미널 매칭: 접두어만 같은 다른 폴더")
expectEqual(OrcaTerminalMatch.bestHandle(for: "/a", among: oneTerminal), nil, "터미널 매칭: 상위 경로는 불일치")
expectEqual(OrcaTerminalMatch.bestHandle(for: "", among: oneTerminal), nil, "터미널 매칭: 빈 cwd")

let homeProject = NSHomeDirectory() + "/proj"
expectEqual(OrcaTerminalMatch.bestHandle(for: "~/proj", among: [terminal("home", homeProject)]), "home",
            "터미널 매칭: ~ 확장")

let manyTerminals = [
    terminal("old", "/a/b", lastOutputAt: 100),
    terminal("recent", "/a/b", lastOutputAt: 200),
    terminal("child", "/a/b/sub", lastOutputAt: 300),
]
expectEqual(OrcaTerminalMatch.bestHandle(for: "/a/b", among: manyTerminals), "recent",
            "터미널 매칭: 여럿이면 가장 최근 출력")
expectEqual(OrcaTerminalMatch.bestHandle(for: "/a/b/sub", among: manyTerminals), "child",
            "터미널 매칭: 정확히 일치하는 터미널도 후보")

let disconnected = [
    terminal("gone", "/a/b", connected: false, lastOutputAt: 300),
    terminal("alive", "/a/b", lastOutputAt: 100),
]
expectEqual(OrcaTerminalMatch.bestHandle(for: "/a/b", among: disconnected), "alive",
            "터미널 매칭: 끊긴 터미널 제외")
expectEqual(OrcaTerminalMatch.bestHandle(for: "/a/c", among: [terminal("gone", "/a/c", connected: false)]), nil,
            "터미널 매칭: 끊긴 터미널만 있으면 없음")

let orcaListJSON = """
{"ok":true,"result":{"terminals":[
  {"handle":"term_091e","worktreePath":"/Users/a/notes","title":"◐ notes4","connected":true,"lastOutputAt":1792488183685},
  {"handle":"term_off","worktreePath":"/Users/a/notes","connected":false},
  {"worktreePath":"/Users/a/other"}
]}}
"""
if let list = try? JSONDecoder().decode(OrcaTerminalList.self, from: Data(orcaListJSON.utf8)) {
    expectEqual(list.terminals.count, 2, "터미널 목록: 핸들 없는 항목은 버린다")
    expectEqual(list.terminals.first?.lastOutputAt, 1792488183685, "터미널 목록: 밀리초 epoch")
    expectEqual(OrcaTerminalMatch.bestHandle(for: "/Users/a/notes", among: list.terminals), "term_091e",
                "터미널 목록: 목록에서 핸들을 찾는다")
} else {
    expect(false, "터미널 목록: 응답을 읽지 못했다")
}

if let emptyList = try? JSONDecoder().decode(OrcaTerminalList.self, from: Data("{\"ok\":true}".utf8)) {
    expectEqual(emptyList.terminals.count, 0, "터미널 목록: result 가 없으면 빈 목록")
} else {
    expect(false, "터미널 목록: result 없는 응답을 읽지 못했다")
}

// MARK: - 체크리스트 진행도

let countsJSON = """
{"sessions": [{
  "sessionId": "p", "bucket": "working",
  "counts": {"done": 3, "left": 1, "now": 1, "blocked": 0}, "total": 4
}]}
"""
if let response = decode(countsJSON) {
    let item = Grouping.group(response, now: now).working.first
    expectEqual(item?.progress?.text, "3/4", "진행도: done/total 문구")
    expectEqual(item?.progress?.fraction, 0.75, "진행도: 비율")
} else {
    expect(false, "진행도: counts 응답을 읽지 못했다")
}

let summaryCountsJSON = """
{"sessions": [{
  "sessionId": "s", "bucket": "working",
  "summary": {"counts": {"done": 2}, "total": 5, "nowLabel": "검증 단계"}
}]}
"""
if let response = decode(summaryCountsJSON) {
    let item = Grouping.group(response, now: now).working.first
    expectEqual(item?.progress?.text, "2/5", "진행도: summary 안의 counts")
    expectEqual(item?.nowLabel, "검증 단계", "진행도: summary 안의 nowLabel")
} else {
    expect(false, "진행도: summary 응답을 읽지 못했다")
}

let noCounts = Grouping.group(
    SessionsResponse(sessions: [Session(sessionId: "n", bucket: "working", total: 5)]),
    now: now
)
expectEqual(noCounts.working.first?.progress, nil, "진행도: counts 가 없으면 표시하지 않는다")

let zeroTotal = Grouping.group(
    SessionsResponse(sessions: [Session(sessionId: "z", bucket: "working",
                                          counts: SessionCounts(done: 0), total: 0)]),
    now: now
)
expectEqual(zeroTotal.working.first?.progress, nil, "진행도: total 0 은 표시하지 않는다")

print("selftest: \(checks) checks, \(failures) failures")
exit(failures == 0 ? 0 : 1)
