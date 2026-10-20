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

// MARK: - 확인한 완료 되돌리기

let ackA = session("ackA", "done", minutesAgo: 30)
let ackB = session("ackB", "ended", minutesAgo: 90)
let ackOld = session("ackOld", "done", minutesAgo: 800)
let ackWork = session("ackWork", "working", minutesAgo: 10)
let ackResponse = SessionsResponse(sessions: [ackA, ackB, ackOld, ackWork])
let ackVisible = Grouping.group(ackResponse, now: now).done
let ackAKey = DisplayItem.acknowledgeKey(sessionId: "ackA", since: ackA.since)
let ackBKey = DisplayItem.acknowledgeKey(sessionId: "ackB", since: ackB.since)
let ackOldKey = DisplayItem.acknowledgeKey(sessionId: "ackOld", since: ackOld.since)
let ackWorkKey = DisplayItem.acknowledgeKey(sessionId: "ackWork", since: ackWork.since)

expectEqual(DisplayItem.sessionId(fromAcknowledgeKey: ackAKey), "ackA", "완료 키: sessionId 분리")

var acks = DoneAcknowledgements()
expectEqual(ackVisible.map(\.sessionId), ["ackA", "ackB"], "다시 보기: 12시간 창 안 완료만 대상")
expectEqual(acks.acknowledge(ackVisible), 2, "다시 보기: 확인한 개수")
expectEqual(acks.recent, Set([ackAKey, ackBKey]), "다시 보기: 직전 확인 키")
expectEqual(acks.hiddenCount(in: ackResponse, now: now), 2, "다시 보기: 숨겨진 완료 개수")
expectEqual(Grouping.group(ackResponse, now: now, acknowledgedDone: acks.keys).done.count, 0,
            "다시 보기: 숨긴 완료는 그룹에서 빠진다")

let outOfWindow = DoneAcknowledgements(keys: [ackOldKey, ackWorkKey])
expectEqual(outOfWindow.hiddenCount(in: ackResponse, now: now), 0,
            "다시 보기: 12시간 밖 완료와 완료가 아닌 세션은 세지 않는다")

var mixed = DoneAcknowledgements(keys: [ackOldKey])
mixed.acknowledge(ackVisible)
mixed.undoRecent()
expectEqual(mixed.keys, Set([ackOldKey]), "직전 확인 취소: 그 전에 숨긴 키는 남는다")
expectEqual(mixed.recent, Set<String>(), "직전 확인 취소: 직전 키는 비운다")
expectEqual(mixed.hiddenCount(in: ackResponse, now: now), 0, "직전 확인 취소: 되돌린 항목은 다시 보인다")

var restored = DoneAcknowledgements(keys: [ackOldKey, ackWorkKey])
restored.undoAll()
expectEqual(restored.keys, Set<String>(), "다시 보기: 숨김 집합을 모두 비운다")

var pruned = DoneAcknowledgements(keys: [ackAKey, ackBKey, ackWorkKey])
pruned.prune(keeping: SessionsResponse(sessions: [ackA, ackWork]))
expectEqual(pruned.keys, Set([ackAKey, ackWorkKey]), "정리: 응답에 없는 세션의 키를 지운다")
pruned.prune(keeping: nil)
expectEqual(pruned.keys, Set([ackAKey, ackWorkKey]), "정리: 응답이 없으면 지우지 않는다")

var reAcknowledged = DoneAcknowledgements(keys: [ackAKey])
expectEqual(reAcknowledged.acknowledge(ackVisible), 1, "다시 보기: 이미 숨긴 키는 새로 세지 않는다")
expectEqual(reAcknowledged.recent, Set([ackBKey]), "다시 보기: 직전 키는 새로 가린 것만")

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

// MARK: - Claude 세션 파일 파싱

let sessionFileJSON = """
{"pid":20837,"sessionId":"1121d7e7-9881-4c8c-8605-b1ffb8ea14fa","cwd":"/Users/alex/git-repo/deadhd-bar",
 "startedAt":1792488392202,"kind":"interactive","entrypoint":"cli","name":"deadhdbar",
 "status":"waiting","statusUpdatedAt":1792490397838,"waitingFor":"permission prompt",
 "unknownKey":{"nested":true},"peerFeatures":["notify_idle"]}
"""
if let record = LocalSessions.parseRecord(Data(sessionFileJSON.utf8)) {
    expectEqual(record.pid, 20837, "세션 파일: pid")
    expectEqual(record.sessionId, "1121d7e7-9881-4c8c-8605-b1ffb8ea14fa", "세션 파일: sessionId")
    expectEqual(record.startedAt, Date(timeIntervalSince1970: 1792488392202 / 1000),
                "세션 파일: 시작 시각은 밀리초 epoch")
    expectEqual(record.statusUpdatedAt, Date(timeIntervalSince1970: 1792490397838 / 1000),
                "세션 파일: 상태 시각은 밀리초 epoch")
    expectEqual(record.name, "deadhdbar", "세션 파일: name")
    expectEqual(record.entrypoint, "cli", "세션 파일: entrypoint")
    expectEqual(record.waitingFor, "permission prompt", "세션 파일: waitingFor")
    expectEqual(record.status, "waiting", "세션 파일: status")
    expectEqual(LocalSessions.shouldInclude(record), true, "세션 파일: cli 는 포함")
} else {
    expect(false, "세션 파일: 정상 파일을 읽지 못했다")
}

expectEqual(LocalSessions.parseRecord(Data("{\"pid\":1}".utf8)), nil, "세션 파일: sessionId 없으면 버린다")
expectEqual(LocalSessions.parseRecord(Data("{\"sessionId\":\"s\"}".utf8)), nil, "세션 파일: pid 없으면 버린다")
expectEqual(LocalSessions.parseRecord(Data("not json".utf8)), nil, "세션 파일: JSON 이 아니면 버린다")

let sdkRecord = LocalSessionRecord(pid: 2, sessionId: "sdk", entrypoint: "sdk-cli", status: "busy")
expectEqual(LocalSessions.shouldInclude(sdkRecord), false, "세션 파일: sdk-cli 는 기본으로 뺀다")
expectEqual(LocalSessions.shouldInclude(LocalSessionRecord(pid: 3, sessionId: "x")), false,
            "세션 파일: entrypoint 가 없으면 뺀다")

expectEqual(LocalSessions.isSessionFileName("20837.json"), true, "파일 이름: <pid>.json 만 읽는다")
expectEqual(LocalSessions.isSessionFileName("20837.abc.key"), false, "파일 이름: 키 파일은 읽지 않는다")
expectEqual(LocalSessions.isSessionFileName("abc.json"), false, "파일 이름: 숫자가 아니면 뺀다")
expectEqual(LocalSessions.isSessionFileName("20837.json.bak"), false, "파일 이름: 확장자가 다르면 뺀다")
expectEqual(LocalSessions.isSessionFileName(".json"), false, "파일 이름: pid 가 비면 뺀다")

// MARK: - 프로젝트 슬러그

expectEqual(
    LocalSessions.projectSlug(forCwd: "/Users/alex/git-repo/deadhd-bar"),
    "-Users-alex-git-repo-deadhd-bar",
    "슬러그: 일반 경로"
)
expectEqual(
    LocalSessions.projectSlug(
        forCwd: "/Users/alex/Library/Mobile Documents/iCloud~md~obsidian/Documents/notes"
    ),
    "-Users-alex-Library-Mobile-Documents-iCloud-md-obsidian-Documents-notes",
    "슬러그: 공백과 ~ 도 - 로 바꾼다"
)

// MARK: - 트랜스크립트 끝 요약

let transcriptJSON = """
{"type":"assistant","message":{"content":[{"type":"text","text":"잘린 답변"}]},"timestamp":"2026-10-20T08:00:00.000Z"}
{"type":"custom-title","customTitle":"첫 제목"}
{"type":"assistant","message":{"content":[{"type":"text","text":"  첫 답변  "}]},"timestamp":"2026-10-20T09:01:00.000Z"}
{"type":"custom-title","customTitle":"마지막 제목"}
{"type":"agent-name","agentName":"에이전트"}
{"type":"last-prompt","lastPrompt":"마지막 요청"}
{"type":"attachment","attachment":{"type":"mode"}}
{"type":"assistant","message":{"content":[{"type":"thinking","thinking":"생각"},{"type":"text","text":"  최종 답변입니다  "},{"type":"tool_use","name":"Bash","input":{"command":"ls"}}]},"timestamp":"2026-10-20T09:03:00.000Z"}
{"type":"user","message":{"role":"user","content":"질문"},"timestamp":"2026-10-20T09:04:00.000Z"}
"""
let transcriptSummary = LocalSessions.summarizeTranscriptTail(
    Data(transcriptJSON.utf8),
    droppingPartialFirstLine: true
)
expectEqual(transcriptSummary.customTitle, "마지막 제목", "요약: 마지막 custom-title 우선")
expectEqual(transcriptSummary.agentName, "에이전트", "요약: agent-name")
expectEqual(transcriptSummary.lastPrompt, "마지막 요청", "요약: last-prompt")
expectEqual(transcriptSummary.lastAssistantText, "최종 답변입니다", "요약: 마지막 text 앞뒤 공백 정리")
expectEqual(transcriptSummary.lastToolName, "Bash", "요약: 마지막 tool_use 이름")
expectEqual(transcriptSummary.lastToolAt, utcDate(2026, 10, 20, 9, 3), "요약: 마지막 tool_use 시각")
expectEqual(transcriptSummary.lastMeaningfulAt, utcDate(2026, 10, 20, 9, 4), "요약: 마지막 assistant/user 줄 시각")

let notDropped = LocalSessions.summarizeTranscriptTail(
    Data(transcriptJSON.utf8),
    droppingPartialFirstLine: false
)
expectEqual(notDropped.lastAssistantText, "최종 답변입니다", "요약: 첫 줄을 버리지 않으면 마지막 값은 그대로")

let onlyFirstLineText = Data("""
{"type":"assistant","message":{"content":[{"type":"text","text":"잘린 답변"}]},"timestamp":"2026-10-20T08:00:00.000Z"}
{"type":"assistant","message":{"content":[]},"timestamp":"2026-10-20T09:01:00.000Z"}
""".utf8)
expectEqual(
    LocalSessions.summarizeTranscriptTail(onlyFirstLineText, droppingPartialFirstLine: true).lastAssistantText,
    nil,
    "요약: 잘린 첫 줄은 버린다"
)
expectEqual(
    LocalSessions.summarizeTranscriptTail(onlyFirstLineText, droppingPartialFirstLine: false).lastAssistantText,
    "잘린 답변",
    "요약: 버리지 않으면 첫 줄도 읽는다"
)

let longText = String(repeating: "가", count: 200)
let longLine = """
{"type":"assistant","message":{"content":[{"type":"text","text":"\(longText)   "}]},"timestamp":"2026-10-20T09:05:00.000Z"}
"""
let longSummary = LocalSessions.summarizeTranscriptTail(Data(longLine.utf8), droppingPartialFirstLine: false)
expectEqual(longSummary.lastAssistantText?.count, 160, "요약: 답변은 160자로 자른다")
expect(!(longSummary.lastAssistantText ?? "").hasSuffix(" "), "요약: 답변 앞뒤 공백을 지운다")

let brokenTail = Data("{not json\n{\"type\":\"custom-title\",\"customTitle\":\"온전한 제목\"}\n".utf8)
expectEqual(
    LocalSessions.summarizeTranscriptTail(brokenTail, droppingPartialFirstLine: false).customTitle,
    "온전한 제목",
    "요약: 깨진 줄은 건너뛴다"
)

// MARK: - 세션 파일 → 화면 모델

func localRecord(
    status: String?,
    waitingFor: String? = nil,
    name: String? = "이름",
    statusUpdatedAt: Date? = nil,
    startedAt: Date? = nil
) -> LocalSessionRecord {
    LocalSessionRecord(
        pid: 100,
        sessionId: "local",
        cwd: "/Users/a/proj",
        name: name,
        entrypoint: "cli",
        status: status,
        waitingFor: waitingFor,
        startedAt: startedAt ?? now.addingTimeInterval(-900),
        statusUpdatedAt: statusUpdatedAt ?? now.addingTimeInterval(-120)
    )
}

func localSession(
    status: String?,
    waitingFor: String? = nil,
    summary: TranscriptSummary = TranscriptSummary(),
    name: String? = "이름",
    statusUpdatedAt: Date? = nil,
    startedAt: Date? = nil
) -> Session {
    LocalSessions.makeSession(
        record: localRecord(
            status: status,
            waitingFor: waitingFor,
            name: name,
            statusUpdatedAt: statusUpdatedAt,
            startedAt: startedAt
        ),
        summary: summary,
        now: now
    )
}

let permission = localSession(status: "waiting", waitingFor: "permission prompt")
expectEqual(permission.bucket, "wait", "상태 표: 권한 대기는 wait 버킷")
expectEqual(permission.status, "waiting_permission", "상태 표: 권한 대기 status")
expectEqual(permission.message, "권한 승인을 기다려요", "상태 표: 권한 대기 문구")
let permissionGroup = Grouping.group(SessionsResponse(sessions: [permission]), now: now)
expectEqual(permissionGroup.attention.first?.status, "권한 승인을 기다려요", "상태 표: 권한 대기는 확인 필요 그룹")

let inputNeeded = localSession(status: "waiting", waitingFor: "input needed")
expectEqual(inputNeeded.bucket, "wait", "상태 표: 입력 대기도 wait 버킷")
expectEqual(inputNeeded.status, "waiting_input", "상태 표: 입력 대기 status")
expectEqual(inputNeeded.message, "입력을 기다려요", "상태 표: 입력 대기 문구")
expectEqual(Grouping.group(SessionsResponse(sessions: [inputNeeded]), now: now).attention.first?.status,
            "입력을 기다려요", "상태 표: 입력 대기는 확인 필요 그룹")

let otherWaiting = localSession(status: "waiting", waitingFor: "something else")
expectEqual(otherWaiting.bucket, "wait", "상태 표: 그 밖의 waitingFor 도 wait 버킷")
expectEqual(otherWaiting.status, "waiting_input", "상태 표: 그 밖의 waitingFor 는 입력 대기")

let busy = localSession(status: "busy")
expectEqual(busy.bucket, "working", "상태 표: busy 는 working")
expectEqual(busy.status, "working", "상태 표: busy status")
expectEqual(busy.message, nil, "상태 표: busy 에는 message 가 없다")
expectEqual(Grouping.group(SessionsResponse(sessions: [busy]), now: now).working.count, 1, "상태 표: busy 는 진행중 그룹")

let shell = localSession(status: "shell")
expectEqual(shell.bucket, "working", "상태 표: shell 은 working")
expectEqual(shell.status, "working", "상태 표: shell status")

let idle = localSession(status: "idle")
expectEqual(idle.bucket, "done", "상태 표: idle 은 완료 버킷")
expectEqual(idle.status, "idle", "상태 표: idle status")
let idleMappedGroup = Grouping.group(SessionsResponse(sessions: [idle]), now: now)
expectEqual(idleMappedGroup.done.count, 1, "상태 표: idle 은 완료 그룹")
expectEqual(idleMappedGroup.done.first?.status, "완료했어요", "상태 표: idle 은 완료 문구")

let unknownStatus = localSession(status: "paused")
expectEqual(unknownStatus.bucket, "working", "상태 표: 그 밖의 상태는 working")
expectEqual(unknownStatus.status, "paused", "상태 표: 그 밖의 상태는 원문 유지")
expectEqual(unknownStatus.message, nil, "상태 표: 그 밖의 상태에는 message 가 없다")

let stalled = localSession(status: "busy", summary: TranscriptSummary(lastMeaningfulAt: now.addingTimeInterval(-601)))
expectEqual(stalled.bucket, "stall", "stall: 마지막 줄이 10분보다 오래되면 stall")
expectEqual(Grouping.group(SessionsResponse(sessions: [stalled]), now: now).attention.count, 1,
            "stall: 확인 필요 그룹으로 간다")

let stallShell = localSession(status: "shell", summary: TranscriptSummary(lastMeaningfulAt: now.addingTimeInterval(-3600)))
expectEqual(stallShell.bucket, "stall", "stall: shell 도 같은 기준을 쓴다")

let boundary = localSession(status: "busy", summary: TranscriptSummary(lastMeaningfulAt: now.addingTimeInterval(-600)))
expectEqual(boundary.bucket, "working", "stall: 정확히 10분이면 아직 working")

let noTranscript = localSession(status: "busy", summary: TranscriptSummary())
expectEqual(noTranscript.bucket, "working", "stall: 트랜스크립트가 없으면 working")

let staleIdle = localSession(status: "idle", summary: TranscriptSummary(lastMeaningfulAt: now.addingTimeInterval(-3600)))
expectEqual(staleIdle.bucket, "done", "stall: stall 판정은 busy/shell 에만 적용")

// MARK: - 제목·시각·필드

let titled = localSession(
    status: "busy",
    summary: TranscriptSummary(customTitle: "커스텀", agentName: "에이전트", lastPrompt: "프롬프트"),
    name: "세션이름"
)
expectEqual(titled.title, "커스텀", "제목: customTitle 우선")
expectEqual(titled.key, "세션이름", "제목: key 는 세션 파일 name")
expectEqual(titled.cwd, "/Users/a/proj", "제목: cwd 는 세션 파일 값")

let agentTitled = localSession(
    status: "busy",
    summary: TranscriptSummary(agentName: "에이전트", lastPrompt: "프롬프트"),
    name: "세션이름"
)
expectEqual(agentTitled.title, "에이전트", "제목: customTitle 이 없으면 agentName")

let nameTitled = localSession(status: "busy", summary: TranscriptSummary(lastPrompt: "프롬프트"), name: "세션이름")
expectEqual(nameTitled.title, "세션이름", "제목: agentName 이 없으면 세션 파일 name")

let longPrompt = String(repeating: "프", count: 80)
let promptTitled = localSession(status: "busy", summary: TranscriptSummary(lastPrompt: longPrompt), name: nil)
expectEqual(promptTitled.title?.count, 60, "제목: 마지막 수단 lastPrompt 는 60자")
expectEqual(promptTitled.key, nil, "제목: name 이 없으면 key 도 없다")

let untitled = localSession(status: "busy", summary: TranscriptSummary(), name: nil)
expectEqual(untitled.title, nil, "제목: 후보가 다 없으면 nil")

let statusAt = now.addingTimeInterval(-120)
let startedAt = now.addingTimeInterval(-900)
let transcriptAt = now.addingTimeInterval(-30)
let timing = localSession(
    status: "busy",
    summary: TranscriptSummary(lastMeaningfulAt: transcriptAt),
    statusUpdatedAt: statusAt,
    startedAt: startedAt
)
expectEqual(timing.since, statusAt, "시각: since 는 statusUpdatedAt")
expectEqual(timing.updatedAt, transcriptAt, "시각: updatedAt 은 더 늦은 트랜스크립트 시각")

let olderTranscript = localSession(
    status: "busy",
    summary: TranscriptSummary(lastMeaningfulAt: now.addingTimeInterval(-300)),
    statusUpdatedAt: statusAt
)
expectEqual(olderTranscript.updatedAt, statusAt, "시각: 트랜스크립트가 더 이르면 statusUpdatedAt")

let noStatusTime = LocalSessions.makeSession(
    record: LocalSessionRecord(
        pid: 100,
        sessionId: "local",
        entrypoint: "cli",
        status: "busy",
        startedAt: startedAt
    ),
    summary: TranscriptSummary(),
    now: now
)
expectEqual(noStatusTime.since, startedAt, "시각: statusUpdatedAt 이 없으면 startedAt")

let richSummary = TranscriptSummary(
    lastAssistantText: "마지막 답변",
    lastToolName: "Read",
    lastToolAt: utcDate(2026, 10, 20, 9, 3)
)
let rich = localSession(status: "busy", summary: richSummary)
expectEqual(rich.replyTail, "마지막 답변", "필드: replyTail 은 마지막 assistant text")
expectEqual(rich.lastTool?.name, "Read", "필드: lastTool 이름")
expectEqual(rich.lastTool?.at, utcDate(2026, 10, 20, 9, 3), "필드: lastTool 시각")
expectEqual(rich.lastTool?.durationMs, nil, "필드: lastTool durationMs 는 없다")
expectEqual(rich.backgroundTasks, [], "필드: backgroundTasks 는 비어 있다")
expectEqual(rich.href, nil, "필드: href 는 없다")
expectEqual(rich.orcaTerminal, nil, "필드: orcaTerminal 은 없다")

// MARK: - 종료 추적

let liveSession = Session(
    sessionId: "gone",
    bucket: "working",
    title: "떠난 세션",
    key: "gone",
    status: "working",
    since: now.addingTimeInterval(-60),
    replyTail: "하던 일",
    cwd: "/a/b"
)
let t0 = now
let t1 = now.addingTimeInterval(5)
var tracker = EndedSessionTracker()
expectEqual(tracker.reconcile(active: [liveSession], at: t0).count, 0, "종료 추적: 살아 있으면 보관본이 없다")
let disappeared = tracker.reconcile(active: [], at: t1)
expectEqual(disappeared.count, 1, "종료 추적: 사라지면 ended 로 남는다")
expectEqual(disappeared.first?.bucket, "ended", "종료 추적: bucket 은 ended")
expectEqual(disappeared.first?.status, "ended", "종료 추적: status 는 ended")
expectEqual(disappeared.first?.since, t1, "종료 추적: since 는 사라진 시각")
expectEqual(disappeared.first?.replyTail, "하던 일", "종료 추적: 마지막 모습을 보존한다")
expectEqual(Grouping.group(SessionsResponse(sessions: disappeared), now: t1).done.count, 1,
            "종료 추적: ended 는 완료 그룹으로 간다")
expectEqual(tracker.reconcile(active: [], at: t1.addingTimeInterval(12 * 3600 - 1)).count, 1,
            "종료 추적: 12시간이 되기 전에는 남는다")
expectEqual(tracker.reconcile(active: [], at: t1.addingTimeInterval(12 * 3600)).count, 0,
            "종료 추적: 12시간 뒤 지운다")

var reappeared = EndedSessionTracker()
_ = reappeared.reconcile(active: [liveSession], at: t0)
_ = reappeared.reconcile(active: [], at: t1)
expectEqual(reappeared.reconcile(active: [liveSession], at: t1.addingTimeInterval(10)).count, 0,
            "종료 추적: 다시 나타나면 보관본을 버린다")

var neverSeen = EndedSessionTracker()
expectEqual(neverSeen.reconcile(active: [], at: t0).count, 0, "종료 추적: 처음부터 없던 세션은 남기지 않는다")

// MARK: - deadhd 보강

let localOnly = Session(
    sessionId: "a",
    bucket: "working",
    title: "로컬 제목",
    key: "local",
    status: "working",
    since: now.addingTimeInterval(-60),
    cwd: "/a/b"
)
let remoteBooster = Session(
    sessionId: "a",
    bucket: "done",
    title: "원격 제목",
    place: Place(label: "shop", branch: "main"),
    orcaTerminal: "term-1",
    backgroundTasks: [BackgroundTask(type: "shell", taskDescription: "npm test")],
    nowLabel: "검증 단계",
    href: "http://127.0.0.1:47320/deadhd-a.html",
    counts: SessionCounts(done: 2),
    total: 5
)
let remoteOnlySession = Session(sessionId: "b", bucket: "done", href: "http://other")
let overlaid = SessionOverlay.apply(local: [localOnly], remote: [remoteBooster, remoteOnlySession])
expectEqual(overlaid.count, 1, "보강: 로컬에 없는 deadhd 세션은 추가하지 않는다")
expectEqual(overlaid.first?.href, "http://127.0.0.1:47320/deadhd-a.html", "보강: href 를 덧입힌다")
expectEqual(overlaid.first?.orcaTerminal, "term-1", "보강: orcaTerminal 을 덧입힌다")
expectEqual(overlaid.first?.nowLabel, "검증 단계", "보강: nowLabel 을 덧입힌다")
expectEqual(overlaid.first?.place?.branch, "main", "보강: place 를 덧입힌다")
expectEqual(overlaid.first?.counts?.done, 2, "보강: counts 를 덧입힌다")
expectEqual(overlaid.first?.backgroundTasks.first?.taskDescription, "npm test", "보강: backgroundTasks 를 덧입힌다")
expectEqual(overlaid.first?.bucket, "working", "보강: bucket 은 로컬 값을 지킨다")
expectEqual(overlaid.first?.title, "로컬 제목", "보강: title 은 로컬 값을 지킨다")
expectEqual(overlaid.first?.cwd, "/a/b", "보강: cwd 는 로컬 값을 지킨다")
expectEqual(SessionOverlay.apply(local: [localOnly], remote: []), [localOnly], "보강: deadhd 응답이 없으면 로컬 그대로")

print("selftest: \(checks) checks, \(failures) failures")
exit(failures == 0 ? 0 : 1)
