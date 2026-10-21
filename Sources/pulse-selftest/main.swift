import Foundation
import PulseCore

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
    title: String? = nil,
    connected: Bool = true,
    lastOutputAt: Double? = nil
) -> OrcaTerminal {
    OrcaTerminal(
        handle: handle,
        worktreePath: worktreePath,
        title: title,
        connected: connected,
        lastOutputAt: lastOutputAt
    )
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

expectEqual(OrcaTerminalMatch.sessionName(fromTitle: "✳ app1256demo3"), "app1256demo3",
            "터미널 제목: 상태 기호를 뗀다")
expectEqual(OrcaTerminalMatch.sessionName(fromTitle: "◐ notes4"), "notes4",
            "터미널 제목: 다른 상태 기호도 뗀다")
expectEqual(OrcaTerminalMatch.sessionName(fromTitle: "deadhdbar"), "deadhdbar",
            "터미널 제목: 기호가 없으면 그대로")
expectEqual(OrcaTerminalMatch.sessionName(fromTitle: "  ◑  shop2  "), "shop2",
            "터미널 제목: 앞뒤 공백을 지운다")
expectEqual(OrcaTerminalMatch.sessionName(fromTitle: "✳"), nil, "터미널 제목: 기호뿐이면 이름이 없다")

let sameCwdTerminals = [
    terminal("app3", "/w/app", title: "✳ app1256demo3", lastOutputAt: 100),
    terminal("app2", "/w/app", title: "◐ app1256demo2", lastOutputAt: 300),
    terminal("app1", "/w/app", title: "✳ app1256demo", lastOutputAt: 200),
]
expectEqual(OrcaTerminalMatch.bestHandle(for: "/w/app", name: "app1256demo3", among: sameCwdTerminals), "app3",
            "터미널 매칭: 같은 폴더에서 세션 이름이 맞는 터미널")
expectEqual(OrcaTerminalMatch.bestHandle(for: "/w/app", name: "APP1256DEMO2", among: sameCwdTerminals), "app2",
            "터미널 매칭: 세션 이름 대소문자 무시")
expectEqual(OrcaTerminalMatch.bestHandle(for: "/w/app", name: "없는이름", among: sameCwdTerminals), "app2",
            "터미널 매칭: 이름이 안 맞으면 가장 최근 출력")
expectEqual(OrcaTerminalMatch.bestHandle(for: "/w/app", among: sameCwdTerminals), "app2",
            "터미널 매칭: 이름이 없으면 가장 최근 출력")

let otherFolderSameName = [
    terminal("other", "/elsewhere", title: "✳ target", lastOutputAt: 900),
    terminal("here", "/w/app", title: "다른 이름", lastOutputAt: 100),
]
expectEqual(OrcaTerminalMatch.bestHandle(for: "/w/app", name: "target", among: otherFolderSameName), "here",
            "터미널 매칭: 다른 폴더의 같은 이름은 고르지 않는다")

let disconnectedNamed = [
    terminal("gone", "/w/app", title: "✳ target", connected: false, lastOutputAt: 900),
    terminal("alive", "/w/app", title: "다른 이름", lastOutputAt: 100),
]
expectEqual(OrcaTerminalMatch.bestHandle(for: "/w/app", name: "target", among: disconnectedNamed), "alive",
            "터미널 매칭: 끊긴 터미널은 이름이 맞아도 제외")

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
    expectEqual(list.terminals.first?.title, "◐ notes4", "터미널 목록: 제목")
    expectEqual(OrcaTerminalMatch.bestHandle(for: "/Users/a/notes", among: list.terminals), "term_091e",
                "터미널 목록: 목록에서 핸들을 찾는다")
    expectEqual(OrcaTerminalMatch.bestHandle(for: "/Users/a/notes", name: "notes4", among: list.terminals),
                "term_091e", "터미널 목록: 제목으로 세션 터미널을 찾는다")
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

// MARK: - 인용 평문화

expectEqual(PlainText.markdown("**굵게**"), "굵게", "평문화: 굵게")
expectEqual(PlainText.markdown("__굵게__"), "굵게", "평문화: 밑줄 굵게")
expectEqual(PlainText.markdown("*기울임*"), "기울임", "평문화: 기울임")
expectEqual(PlainText.markdown("_기울임_"), "기울임", "평문화: 밑줄 기울임")
expectEqual(PlainText.markdown("`코드`"), "코드", "평문화: 백틱은 지우고 글자는 남긴다")
expectEqual(PlainText.markdown("[글](https://example.com)"), "글", "평문화: 링크는 글자만")
expectEqual(PlainText.markdown("- 항목"), "항목", "평문화: 목록 기호")
expectEqual(PlainText.markdown("* 항목"), "항목", "평문화: 별표 목록 기호")
expectEqual(PlainText.markdown("# 제목"), "제목", "평문화: 제목 기호")
expectEqual(PlainText.markdown("> 인용"), "인용", "평문화: 인용 기호")
expectEqual(PlainText.markdown("> - 중첩"), "중첩", "평문화: 겹친 줄머리 기호")
expectEqual(PlainText.markdown("```swift\nlet a = 1\n```"), "let a = 1", "평문화: 코드 펜스 줄 제거")
expectEqual(PlainText.markdown("snake_case"), "snake_case", "평문화: 짝이 아닌 밑줄은 유지")
expectEqual(PlainText.markdown("a*b"), "a*b", "평문화: 짝이 아닌 별표는 유지")
expectEqual(PlainText.markdown("#해시태그"), "#해시태그", "평문화: 기호만 있는 줄머리는 그대로")
expectEqual(PlainText.markdown("  여러   줄\n\n공백  "), "여러 줄 공백", "평문화: 공백 접기")
expectEqual(PlainText.markdown("~~취소선~~"), "~~취소선~~", "평문화: 다루지 않는 기호는 그대로")

let markdownJSON = """
{"type":"assistant","message":{"content":[{"type":"text","text":"**정리했습니다**\\n\\n- 첫 항목\\n- [둘째](https://x) 항목"}]},"timestamp":"2026-10-20T09:06:00.000Z"}
"""
expectEqual(
    LocalSessions.summarizeTranscriptTail(Data(markdownJSON.utf8), droppingPartialFirstLine: false).lastAssistantText,
    "정리했습니다 첫 항목 둘째 항목",
    "요약: 인용에 마크다운 기호가 남지 않는다"
)

let markdownLongJSON = """
{"type":"assistant","message":{"content":[{"type":"text","text":"**\(String(repeating: "가", count: 200))**"}]}}
"""
let markdownLong = LocalSessions.summarizeTranscriptTail(
    Data(markdownLongJSON.utf8),
    droppingPartialFirstLine: false
).lastAssistantText
expectEqual(markdownLong?.count, 160, "요약: 평문화한 뒤에 160자로 자른다")
expect(!(markdownLong ?? "").contains("*"), "요약: 잘린 뒤에도 마크다운 기호가 없다")

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

// MARK: - 중복 태그

let sameKeyGroup = Grouping.group(
    SessionsResponse(sessions: [
        Session(sessionId: "same", bucket: "working", title: "deadhdbar", key: "deadhdbar"),
    ]),
    now: now
)
expectEqual(sameKeyGroup.working.first?.keyTag, nil, "태그: 제목과 같은 이름은 숨긴다")

let caseKeyGroup = Grouping.group(
    SessionsResponse(sessions: [
        Session(sessionId: "case", bucket: "working", title: "DeadhdBar", key: " deadhdbar "),
    ]),
    now: now
)
expectEqual(caseKeyGroup.working.first?.keyTag, nil, "태그: 대소문자와 앞뒤 공백을 무시한다")

let differentKeyGroup = Grouping.group(
    SessionsResponse(sessions: [
        Session(sessionId: "diff", bucket: "working", title: "다른 제목", key: "deadhdbar"),
    ]),
    now: now
)
expectEqual(differentKeyGroup.working.first?.keyTag, "deadhdbar", "태그: 제목과 다르면 그린다")

let absentKeyGroup = Grouping.group(
    SessionsResponse(sessions: [Session(sessionId: "nokey", bucket: "working", title: "제목")]),
    now: now
)
expectEqual(absentKeyGroup.working.first?.keyTag, nil, "태그: key 가 없으면 없다")

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

let completedLive = Session(
    sessionId: "completed",
    bucket: "done",
    title: "끝난 세션",
    status: "idle",
    since: now.addingTimeInterval(-120)
)
let completedAcknowledgeKey = DisplayItem.acknowledgeKey(
    sessionId: completedLive.sessionId,
    since: completedLive.since
)
var doneTracker = EndedSessionTracker()
_ = doneTracker.reconcile(active: [completedLive], at: t0)
let completedEnded = doneTracker.reconcile(active: [], at: t1)
expectEqual(completedEnded.first?.since, completedLive.since, "종료 추적: 완료로 사라지면 since 를 유지한다")
expectEqual(
    DisplayItem.acknowledgeKey(sessionId: "completed", since: completedEnded.first?.since),
    completedAcknowledgeKey,
    "종료 추적: 완료로 사라져도 숨김 키가 바뀌지 않는다"
)

if let endedSession = completedEnded.first {
    var endedPrune = DoneAcknowledgements(keys: [completedAcknowledgeKey])
    endedPrune.prune(keeping: SessionsResponse(sessions: [endedSession]))
    expectEqual(endedPrune.keys, Set([completedAcknowledgeKey]), "정리: ended 세션의 숨김 키는 유지한다")
} else {
    expect(false, "정리: ended 세션을 만들지 못했다")
}

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

// MARK: - 팝오버 링과 숫자

let ring = SegmentRatio.make(attention: 1, working: 2, done: 1)
expectEqual(ring.attention, 0.25, "링: 확인 필요 비율")
expectEqual(ring.working, 0.5, "링: 진행 중 비율")
expectEqual(ring.done, 0.25, "링: 완료 비율")

let emptyRing = SegmentRatio.make(attention: 0, working: 0, done: 0)
expectEqual(emptyRing.attention, 0, "링: 빈 그룹은 0")
expectEqual(emptyRing.working, 0, "링: 빈 그룹은 0")
expectEqual(emptyRing.done, 0, "링: 빈 그룹은 0")

let negativeRing = SegmentRatio.make(attention: -1, working: 2, done: 0)
expectEqual(negativeRing.attention, 0, "링: 음수는 0 으로 본다")
expectEqual(negativeRing.working, 1, "링: 남은 그룹이 전체")

expectEqual(MenuBarCounter.make(attention: 2, working: 3), .attention(2), "메뉴 숫자: 확인 필요 우선")
expectEqual(MenuBarCounter.make(attention: 0, working: 3), .working(3), "메뉴 숫자: 확인 필요가 없으면 진행 중")
expectEqual(MenuBarCounter.make(attention: 0, working: 0), .none, "메뉴 숫자: 둘 다 없으면 없음")
expectEqual(MenuBarCounter.none.count, nil, "메뉴 숫자: 없음은 숫자가 없다")
expectEqual(MenuBarCounter.attention(4).count, 4, "메뉴 숫자: 확인 필요 개수")

// MARK: - 필터

let filterCounts = grouped.counts
expectEqual(SessionFilter.all.count(in: grouped), 7, "필터: 전체 개수")
expectEqual(SessionFilter.attention.count(in: grouped), filterCounts.attention, "필터: 확인 필요 개수")
expectEqual(SessionFilter.working.count(in: grouped), filterCounts.working, "필터: 진행 중 개수")
expectEqual(SessionFilter.done.count(in: grouped), filterCounts.done, "필터: 완료 개수")
expectEqual(SessionFilter.attention.sections(in: grouped).map(\.group), [.attention],
            "필터: 확인 필요만 남는다")
expectEqual(SessionFilter.all.sections(in: grouped).map(\.group), [.attention, .working, .done],
            "필터: 전체는 세 그룹")
expectEqual(SessionFilter.title(for: .attention), "확인 필요", "필터: 확인 필요 문구")
expectEqual(SessionFilter.title(for: .working), "진행 중", "필터: 진행 중 문구")
expectEqual(SessionFilter.title(for: .done), "완료", "필터: 완료 문구")
expectEqual(SessionFilter.all.title, "전체", "필터: 전체 문구")
expectEqual(SessionFilter.done.sections(in: manyDone).first?.items.count, 5,
            "필터: 완료는 5개까지만 그린다")
expectEqual(SessionFilter.done.count(in: manyDone), 7, "필터: 칩 숫자는 전체")

let selectableItems = SessionFilter.all.selectableItems(in: clickGrouped)
expectEqual(selectableItems.count, 3, "필터: 이동 대상이 없는 행은 빼고 고른다")
expect(!selectableItems.contains { $0.sessionId == "none" }, "필터: 비활성 행은 고를 수 없다")

// MARK: - 행 동작

expectEqual(PopoverRowAction.resolve(byId["done"]!), .hideDone, "행 동작: 완료는 숨긴다")
expectEqual(PopoverRowAction.resolve(byId["stall"]!), .snooze, "행 동작: stall 은 더 기다린다")
expectEqual(PopoverRowAction.resolve(byId["wait"]!), .none, "행 동작: 권한 대기는 확인 버튼이 없다")
expectEqual(PopoverRowAction.resolve(byId["idle"]!), .none, "행 동작: 입력 대기는 확인 버튼이 없다")
expectEqual(PopoverRowAction.resolve(byId["working"]!), .none, "행 동작: 진행 중은 확인 버튼이 없다")

// MARK: - 키보드 선택

expectEqual(KeyboardSelection.move(from: nil, by: 1, count: 3), 0, "키보드: 처음 아래는 첫 행")
expectEqual(KeyboardSelection.move(from: nil, by: -1, count: 3), 2, "키보드: 처음 위는 마지막 행")
expectEqual(KeyboardSelection.move(from: 0, by: 1, count: 3), 1, "키보드: 아래로")
expectEqual(KeyboardSelection.move(from: 2, by: 1, count: 3), 0, "키보드: 마지막에서 아래는 처음")
expectEqual(KeyboardSelection.move(from: 0, by: -1, count: 3), 2, "키보드: 처음에서 위는 마지막")
expectEqual(KeyboardSelection.move(from: 9, by: 1, count: 3), 0, "키보드: 범위를 벗어난 선택은 처음으로")
expectEqual(KeyboardSelection.move(from: nil, by: 1, count: 0), nil, "키보드: 고를 행이 없으면 없음")

// MARK: - 되돌리기 토스트

expectEqual(UndoToast.duration, 6, "토스트: 6초")
expectEqual(UndoToast.progress(elapsed: 0), 1, "토스트: 시작은 남은 비율 1")
expectEqual(UndoToast.progress(elapsed: 3), 0.5, "토스트: 절반 남는다")
expectEqual(UndoToast.progress(elapsed: 6), 0, "토스트: 끝나면 0")
expectEqual(UndoToast.progress(elapsed: 9), 0, "토스트: 지난 뒤에도 0")

// MARK: - 시간 표시

expectEqual(TimePhrase.relative(from: now.addingTimeInterval(-30), to: now), "방금", "시간: 방금은 단위 없이")
expectEqual(TimePhrase.relative(from: now.addingTimeInterval(-420), to: now), "7분 전", "시간: 분 전")
expectEqual(TimePhrase.relative(from: now.addingTimeInterval(-7200), to: now), "2시간 전", "시간: 시간 전")
expectEqual(TimePhrase.relative(from: nil, to: now), nil, "시간: 기준이 없으면 없다")

// MARK: - 항목 하나 확인

var singleAck = DoneAcknowledgements()
expectEqual(singleAck.acknowledge(doneGrouped.done[0]), 1, "항목 확인: 하나를 가린다")
expectEqual(singleAck.keys, Set([doneKey]), "항목 확인: 키가 들어간다")
expectEqual(singleAck.recent, Set([doneKey]), "항목 확인: 되돌릴 키로 남는다")
expectEqual(singleAck.acknowledge(doneGrouped.done[0]), 0, "항목 확인: 이미 가린 항목은 세지 않는다")
expectEqual(singleAck.recent, Set([doneKey]), "항목 확인: 다시 눌러도 되돌릴 키는 남는다")
singleAck.undoRecent()
expectEqual(singleAck.hiddenCount(in: SessionsResponse(sessions: [doneSession]), now: now), 0,
            "항목 확인: 되돌리면 다시 보인다")

// MARK: - 앱 설정

expectEqual(AppSettings.default.density, .rich, "설정: 기본 밀도는 풍부")
expectEqual(AppSettings.default.theme, .system, "설정: 기본 테마는 시스템")
expectEqual(AppSettings.default.attentionNotifications, true, "설정: 기본 알림은 켜짐")

let storedSettings = AppSettings(densityRaw: "compact", themeRaw: "dark", attentionNotifications: false)
expectEqual(storedSettings.density, .compact, "설정: 저장된 밀도를 읽는다")
expectEqual(storedSettings.theme, .dark, "설정: 저장된 테마를 읽는다")
expectEqual(storedSettings.attentionNotifications, false, "설정: 저장된 알림 값을 읽는다")

let unknownSettings = AppSettings(densityRaw: "dense", themeRaw: "sepia", attentionNotifications: nil)
expectEqual(unknownSettings, AppSettings.default, "설정: 알 수 없는 값과 없는 값은 기본값")
expectEqual(AppSettings(densityRaw: "", themeRaw: " ", attentionNotifications: nil), AppSettings.default,
            "설정: 빈 문자열과 공백은 기본값")

expectEqual(Density.allCases.map(\.rawValue), ["rich", "compact"], "설정: 밀도 저장값")
expectEqual(ThemePreference.allCases.map(\.rawValue), ["system", "light", "dark"], "설정: 테마 저장값")
expectEqual(AppSettings(densityRaw: "light", themeRaw: nil, attentionNotifications: true).density, .rich,
            "설정: 밀도 키에 테마 값이 와도 기본값")

// MARK: - 확인 필요 알림

let noteA = Grouping.group(
    SessionsResponse(sessions: [session("attn-a", "idle", minutesAgo: 1, replyTail: "**첫 번째** 답")]),
    now: now
).attention
let noteB = Grouping.group(
    SessionsResponse(sessions: [session("attn-b", "wait", minutesAgo: 2, message: "권한 승인을 기다려요")]),
    now: now
).attention
let noteAReborn = Grouping.group(
    SessionsResponse(sessions: [session("attn-a", "idle", minutesAgo: 5, replyTail: "다시 답")]),
    now: now
).attention

var notifier = AttentionNotifier()
expectEqual(notifier.notes(for: noteA, popoverVisible: false, enabled: true, isFirstUpdate: true).count, 0,
            "알림: 첫 갱신은 조용히 기록만 한다")
expectEqual(notifier.notes(for: noteA, popoverVisible: false, enabled: true, isFirstUpdate: false).count, 0,
            "알림: 이미 본 항목은 알리지 않는다")

let freshNotes = notifier.notes(for: noteA + noteB, popoverVisible: false, enabled: true, isFirstUpdate: false)
expectEqual(freshNotes.count, 1, "알림: 새 항목만 알린다")
expectEqual(freshNotes.first?.sessionId, "attn-b", "알림: sessionId")
expectEqual(freshNotes.first?.identifier, noteB[0].acknowledgeKey, "알림: 식별자는 sessionId+since")
expectEqual(freshNotes.first?.title, "확인이 필요해요 · attn-b", "알림: 제목")
expectEqual(freshNotes.first?.body, "권한 승인을 기다려요", "알림: 답이 없으면 상태 문구")
expectEqual(notifier.notes(for: noteA + noteB, popoverVisible: false, enabled: true, isFirstUpdate: false).count, 0,
            "알림: 같은 키는 다시 알리지 않는다")
expectEqual(notifier.notes(for: noteAReborn, popoverVisible: false, enabled: true, isFirstUpdate: false).count, 1,
            "알림: since 가 바뀌면 새 항목이다")

expectEqual(AttentionNotifier.body(replyTail: "**굵은** [링크](https://example.com) 답", status: "상태"),
            "굵은 링크 답", "알림: 본문은 평문 마지막 답")
expectEqual(AttentionNotifier.body(replyTail: String(repeating: "가", count: 300), status: "상태").count, 200,
            "알림: 본문은 200자")
expectEqual(AttentionNotifier.body(replyTail: "   ", status: "상태"), "상태",
            "알림: 평문화한 답이 비면 상태 문구")

var popoverNotifier = AttentionNotifier()
_ = popoverNotifier.notes(for: noteA, popoverVisible: false, enabled: true, isFirstUpdate: true)
expectEqual(popoverNotifier.notes(for: noteA + noteB, popoverVisible: true, enabled: true, isFirstUpdate: false).count,
            0, "알림: 팝오버가 열려 있으면 알리지 않는다")
expectEqual(popoverNotifier.notes(for: noteB, popoverVisible: false, enabled: true, isFirstUpdate: false).count,
            0, "알림: 열려 있는 동안 본 항목은 나중에도 알리지 않는다")

var offNotifier = AttentionNotifier()
_ = offNotifier.notes(for: [], popoverVisible: false, enabled: false, isFirstUpdate: true)
expectEqual(offNotifier.notes(for: noteA, popoverVisible: false, enabled: false, isFirstUpdate: false).count,
            0, "알림: 설정이 꺼져 있으면 알리지 않는다")
expectEqual(offNotifier.notes(for: noteA, popoverVisible: false, enabled: true, isFirstUpdate: false).count,
            0, "알림: 꺼져 있는 동안 본 항목은 켠 뒤에도 알리지 않는다")

var pruneNotifier = AttentionNotifier()
_ = pruneNotifier.notes(for: [], popoverVisible: false, enabled: true, isFirstUpdate: true)
expectEqual(pruneNotifier.notes(for: noteA, popoverVisible: false, enabled: true, isFirstUpdate: false).count, 1,
            "알림: 새 항목을 알린다")
_ = pruneNotifier.notes(for: [], popoverVisible: false, enabled: true, isFirstUpdate: false)
expectEqual(pruneNotifier.notes(for: noteA, popoverVisible: false, enabled: true, isFirstUpdate: false).count, 1,
            "알림: 응답에서 빠진 키는 지워 다시 새 항목이 된다")

print("selftest: \(checks) checks, \(failures) failures")
exit(failures == 0 ? 0 : 1)
