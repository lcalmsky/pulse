import Foundation
import PulseCore

// 데모 검사의 유지 프로세스 모드. 플랫폼 서명 바이너리(/bin/sleep)는 procargs 에서 환경 변수가
// 가려지므로, 서명 없는 이 바이너리를 대신 띄워 herdr 패널 환경을 읽히게 한다.
if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--demo-keeper",
   let seconds = Double(CommandLine.arguments[2]) {
    Thread.sleep(forTimeInterval: seconds)
    exit(0)
}

var checks = 0
var failures = 0

// 시스템 언어가 영어인 기계에서도 기존 한국어 기대값으로 검사한다.
L10n.language = .ko

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

func legacyTimestampParse(_ raw: String?) -> Date? {
    guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
        return nil
    }
    for pattern in [
        "yyyy-MM-dd'T'HH:mm:ssXXXXX",
        "yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX",
        "yyyy-MM-dd'T'HH:mm:ss.SSSSSSXXXXX",
        "yyyy-MM-dd'T'HH:mm:ss",
        "yyyy-MM-dd'T'HH:mm:ss.SSS",
    ] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = pattern
        if let date = formatter.date(from: raw) {
            return date
        }
    }
    let iso = ISO8601DateFormatter()
    iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = iso.date(from: raw) {
        return date
    }
    iso.formatOptions = [.withInternetDateTime]
    return iso.date(from: raw)
}

let timestampSamples: [String?] = [
    "2026-10-21T09:48:02.233Z",
    "2026-10-21T09:48:02Z",
    "2026-10-21T18:48:02.233+09:00",
    "2026-10-21T18:48:02+09:00",
    "2026-10-21T09:48:02.123456Z",
    "2026-10-21T09:48:02",
    "2026-10-21T09:48:02.233",
    " 2026-10-21T09:48:02.233Z\n",
    "2026-10-21",
    "not a date",
    "",
    nil,
]
for sample in timestampSamples {
    expectEqual(
        TimestampParser.parse(sample),
        legacyTimestampParse(sample),
        "타임스탬프 옛 구현과 동일: \(sample ?? "nil")"
    )
}
expectEqual(
    TimestampParser.parse("2026-10-21T09:48:02.233Z"),
    TimestampParser.parse("2026-10-21T09:48:02.233Z"),
    "재사용 포매터 두 번째 호출도 같은 값"
)

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
    replySummary: String? = nil,
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
        replySummary: replySummary,
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

// MARK: - 행 식별자

for group in DisplayGroup.allCases {
    expect(
        grouped.items(for: group).allSatisfy { $0.group == group },
        "행 식별자: \(group) 배열의 항목은 같은 그룹 판정을 갖는다"
    )
}
let visibleRowIDs = DisplayGroup.allCases.flatMap { grouped.visibleItems(for: $0).map(\.rowID) }
expectEqual(Set(visibleRowIDs).count, visibleRowIDs.count, "행 식별자: 그룹을 건너 유일")
let movingDone = Grouping.group(SessionsResponse(sessions: [session("moving", "done")]), now: now).done[0]
let movingWorking = Grouping.group(SessionsResponse(sessions: [session("moving", "working")]), now: now).working[0]
expectEqual(movingWorking.rowID, "\(DisplayGroup.working.rawValue)+moving", "행 식별자: 그룹 + sessionId")
expect(movingDone.rowID != movingWorking.rowID, "행 식별자: 그룹이 바뀌면 다른 행")

// MARK: - 상태 문구

let byId = Dictionary(uniqueKeysWithValues: grouped.items(for: .attention).map { ($0.sessionId, $0) })
    .merging(grouped.items(for: .working).map { ($0.sessionId, $0) }) { a, _ in a }
    .merging(grouped.items(for: .done).map { ($0.sessionId, $0) }) { a, _ in a }

expectEqual(byId["wait"]?.status, "권한을 허락해 주세요", "문구: wait 기본")
expectEqual(byId["idle"]?.status, "답을 기다리고 있어요", "문구: idle")
expectEqual(byId["stall"]?.status, "백그라운드 작업 7분째 · npm test", "문구: stall 백그라운드")
expectEqual(byId["working"]?.status, "3분째 · 테스트 실행", "문구: working")
expectEqual(byId["untracked"]?.status, "진행 중이에요", "문구: untracked")
expectEqual(byId["done"]?.status, "끝났어요", "문구: done")
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

expectEqual(SessionClick.resolve(orcaTerminal: nil), SessionClickAction.none,
            "클릭 규칙: 둘 다 없으면 비활성")
expectEqual(SessionClick.resolve(orcaTerminal: " "), SessionClickAction.none,
            "클릭 규칙: 공백뿐이면 없는 것으로 본다")
expectEqual(SessionClick.resolve(orcaTerminal: "term-1"), .orca("term-1"),
            "클릭 규칙: 핸들이 있으면 Orca")
expectEqual(SessionClick.resolve(orcaTerminal: " term-1 "), .orca("term-1"),
            "클릭 규칙: 앞뒤 공백을 지운다")
expectEqual(SessionClick.resolve(orcaTerminal: nil, cwd: "/a/b"), .cwd("/a/b"),
            "클릭 규칙: 핸들이 없으면 cwd 로 찾는다")
expectEqual(SessionClick.resolve(orcaTerminal: "term-1", cwd: "/a/b"), .orca("term-1"),
            "클릭 규칙: cwd 보다 핸들")
expectEqual(SessionClick.resolve(orcaTerminal: nil, cwd: "  "), SessionClickAction.none,
            "클릭 규칙: 공백뿐인 cwd 는 없는 것으로 본다")

let clickGrouped = Grouping.group(
    SessionsResponse(sessions: [
        Session(sessionId: "page", bucket: "working", orcaTerminal: "t", pagePath: "/tmp/a.html"),
        Session(sessionId: "pageOnly", bucket: "working", pagePath: "/tmp/a.html"),
        Session(sessionId: "dataOnly", bucket: "working", dataPath: "/tmp/a.json"),
        Session(sessionId: "orca", bucket: "working", orcaTerminal: "t"),
        Session(sessionId: "cwd", bucket: "working", cwd: "/a/b"),
        Session(sessionId: "none", bucket: "working"),
    ]),
    now: now
)
let clickItems: [String: DisplayItem] = Dictionary(
    uniqueKeysWithValues: clickGrouped.working.map { ($0.sessionId, $0) }
)
expectEqual(clickItems["page"]?.clickAction, .orca("t"), "클릭 규칙: 진행 페이지는 Orca 보다 뒤")
expectEqual(clickItems["orca"]?.clickAction, .orca("t"), "클릭 규칙: 항목이 Orca 로 간다")
expectEqual(clickItems["page"]?.isActionable, true, "클릭 규칙: 페이지 항목은 누를 수 있다")
expectEqual(clickItems["cwd"]?.clickAction, .cwd("/a/b"), "클릭 규칙: cwd 만 있어도 Orca 로 간다")
expectEqual(clickItems["cwd"]?.isActionable, true, "클릭 규칙: cwd 만 있어도 누를 수 있다")
expectEqual(clickItems["pageOnly"]?.clickAction, SessionClickAction.none,
            "클릭 규칙: 터미널 없는 페이지 항목은 행 탭이 비어 있다")
expectEqual(clickItems["pageOnly"]?.isActionable, false, "클릭 규칙: 터미널이 없으면 페이지가 있어도 행 탭 동작은 없다")
expectEqual(clickItems["dataOnly"]?.isActionable, false, "클릭 규칙: 단계만 있는 행도 행 탭 동작은 없다")
expectEqual(clickItems["none"]?.isActionable, false, "클릭 규칙: 대상 없는 항목은 비활성")

let doneClickItem = DisplayItem(
    session: Session(sessionId: "done", bucket: "done", cwd: "/a/b"),
    group: .done,
    now: now
)
expectEqual(doneClickItem.clickAction, .cwd("/a/b"), "클릭 규칙: 끝난 턴은 터미널로 간다")

// MARK: - 우선순위 이동

let jumpGroups = Grouping.group(
    SessionsResponse(sessions: [
        Session(sessionId: "jumpStall", bucket: "stall",
                since: now.addingTimeInterval(-60 * 60), orcaTerminal: "t"),
        Session(sessionId: "jumpNone", bucket: "wait", since: now.addingTimeInterval(-50 * 60)),
        Session(sessionId: "jumpOld", bucket: "wait",
                since: now.addingTimeInterval(-40 * 60), orcaTerminal: "t"),
        Session(sessionId: "jumpNew", bucket: "idle",
                since: now.addingTimeInterval(-10 * 60), cwd: "/a"),
        Session(sessionId: "jumpDoneNew", bucket: "done",
                since: now.addingTimeInterval(-20 * 60), cwd: "/a"),
        Session(sessionId: "jumpDoneOld", bucket: "done",
                since: now.addingTimeInterval(-80 * 60), cwd: "/a"),
    ]),
    now: now
)
expectEqual(PriorityJump.target(.reply, in: jumpGroups, after: nil)?.sessionId, "jumpOld",
            "우선순위 이동: stall 과 누를 수 없는 항목을 건너뛴다")
expectEqual(PriorityJump.target(.reply, in: jumpGroups, after: "jumpOld")?.sessionId, "jumpNew",
            "우선순위 이동: 답 대기는 다음 후보로 순환")
expectEqual(PriorityJump.target(.reply, in: jumpGroups, after: "jumpNew")?.sessionId, "jumpOld",
            "우선순위 이동: 답 대기는 끝에서 처음으로 순환")
expectEqual(PriorityJump.target(.reply, in: jumpGroups, after: "jumpStall")?.sessionId, "jumpOld",
            "우선순위 이동: 직전 세션이 후보에 없으면 첫 후보")
expectEqual(PriorityJump.target(.done, in: jumpGroups, after: nil)?.sessionId, "jumpDoneOld",
            "우선순위 이동: 완료는 가장 오래전에 끝난 세션")
expectEqual(PriorityJump.target(.done, in: jumpGroups, after: "jumpDoneNew")?.sessionId, "jumpDoneOld",
            "우선순위 이동: 완료는 직전 세션을 무시한다")
expectEqual(PriorityJump.target(.reply, in: .empty, after: nil)?.sessionId, nil,
            "우선순위 이동: 답 대기 후보가 없으면 nil")
expectEqual(PriorityJump.target(.done, in: .empty, after: nil)?.sessionId, nil,
            "우선순위 이동: 완료 후보가 없으면 nil")

// MARK: - Orca 터미널 cwd 매칭

func terminal(
    _ handle: String,
    _ worktreePath: String?,
    title: String? = nil,
    connected: Bool = true,
    lastOutputAt: Double? = nil,
    agentIdentity: String? = nil
) -> OrcaTerminal {
    OrcaTerminal(
        handle: handle,
        worktreePath: worktreePath,
        title: title,
        connected: connected,
        lastOutputAt: lastOutputAt,
        agentIdentity: agentIdentity
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
expectEqual(OrcaTerminalMatch.bestHandle(for: "/a/b", among: manyTerminals), nil,
            "터미널 매칭: 이름이 없고 후보가 여럿이면 고르지 않는다")
expectEqual(OrcaTerminalMatch.bestHandle(for: "/a/b/sub", among: manyTerminals), nil,
            "터미널 매칭: 하위 경로라도 후보가 여럿이면 고르지 않는다")

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
expectEqual(OrcaTerminalMatch.bestHandle(for: "/w/app", name: "없는이름", among: sameCwdTerminals), nil,
            "터미널 매칭: 이름이 안 맞고 후보가 여럿이면 고르지 않는다")
expectEqual(OrcaTerminalMatch.bestHandle(for: "/w/app", among: sameCwdTerminals), nil,
            "터미널 매칭: 이름이 없고 후보가 여럿이면 고르지 않는다")

let singleMismatchedName = [terminal("solo", "/w/solo", title: "✳ 다른 이름")]
expectEqual(OrcaTerminalMatch.bestHandle(for: "/w/solo", name: "없는이름", among: singleMismatchedName), "solo",
            "터미널 매칭: 후보가 하나면 이름이 안 맞아도 그 터미널")
let reusedNames = [
    terminal("vault2", "/w/vault", title: "✳ vault2", lastOutputAt: 200),
    terminal("vault3", "/w/vault", title: "✳ vault3", lastOutputAt: 100),
]
expectEqual(OrcaTerminalMatch.bestHandle(for: "/w/vault", name: "vault", among: reusedNames), nil,
            "터미널 매칭: 이름이 겹치면 가장 최근 터미널로 대신 가지 않는다")

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

let claudeAndShell = [
    terminal("claude", "/w/app", agentIdentity: "claude"),
    terminal("shell", "/w/app"),
]
expectEqual(OrcaTerminalMatch.bestHandle(for: "/w/app", among: claudeAndShell), "claude",
            "터미널 매칭: 제목이 없어도 Claude 터미널을 고른다")
expectEqual(OrcaTerminalMatch.bestHandle(for: "/w/app", name: "없는이름", among: claudeAndShell), "claude",
            "터미널 매칭: 이름이 안 맞아도 Claude 터미널을 고른다")
let twoClaudeAndShell = [
    terminal("claude1", "/w/app", agentIdentity: "claude"),
    terminal("claude2", "/w/app", agentIdentity: "Claude"),
    terminal("shell", "/w/app"),
]
expectEqual(OrcaTerminalMatch.bestHandle(for: "/w/app", among: twoClaudeAndShell), nil,
            "터미널 매칭: Claude 터미널이 여럿이면 고르지 않는다")
let goneClaudeAndShell = [
    terminal("claude", "/w/app", connected: false, agentIdentity: "claude"),
    terminal("shell", "/w/app"),
]
expectEqual(OrcaTerminalMatch.bestHandle(for: "/w/app", among: goneClaudeAndShell), "shell",
            "터미널 매칭: Claude 터미널이 끊겼으면 남은 셸 터미널")

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

let orcaIdentityJSON = """
{"ok":true,"result":{"terminals":[
  {"handle":"term_0805","worktreePath":"/w/app","agentIdentity":"claude"},
  {"handle":"term_1bbe","worktreePath":"/w/app"}
]}}
"""
if let identityList = try? JSONDecoder().decode(OrcaTerminalList.self, from: Data(orcaIdentityJSON.utf8)) {
    expectEqual(identityList.terminals.first?.agentIdentity, "claude", "터미널 목록: agentIdentity")
    expectEqual(identityList.terminals.last?.agentIdentity, nil, "터미널 목록: agentIdentity 키가 없으면 nil")
} else {
    expect(false, "터미널 목록: agentIdentity 응답을 읽지 못했다")
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

// MARK: - 마지막 답변 블록

let emptyLastBlockJSON = """
{"type":"assistant","message":{"content":[{"type":"text","text":"첫 답변입니다. 두 번째 문장."}]},"timestamp":"2026-10-20T09:07:00.000Z"}
{"type":"assistant","message":{"content":[{"type":"text","text":"```"}]},"timestamp":"2026-10-20T09:08:00.000Z"}
"""
let emptyLastBlock = LocalSessions.summarizeTranscriptTail(
    Data(emptyLastBlockJSON.utf8),
    droppingPartialFirstLine: false
)
let firstAnswerRaw = "첫 답변입니다. 두 번째 문장."
let firstAnswerPlain = PlainText.markdown(firstAnswerRaw)
    .trimmingCharacters(in: .whitespacesAndNewlines)
expectEqual(
    emptyLastBlock.lastAssistantText,
    String(firstAnswerPlain.prefix(LocalSessions.replyTailLimit)),
    "마지막 답변: 평문이 빈 마지막 블록은 건너뛴다"
)
expectEqual(
    emptyLastBlock.lastSentence,
    NowLine.lastSentence(firstAnswerPlain),
    "마지막 답변: 문장도 앞 블록에서 고른다"
)
expectEqual(
    emptyLastBlock.lastAssistantSummary,
    ReplySummary.firstSentence(firstAnswerRaw),
    "마지막 답변: 카드 요약도 앞 블록에서 고른다"
)

let threeTextBlocksJSON = """
{"type":"assistant","message":{"content":[{"type":"text","text":"하나."},{"type":"text","text":"둘."},{"type":"text","text":"셋."}]},"timestamp":"2026-10-20T09:09:00.000Z"}
"""
expectEqual(
    LocalSessions.summarizeTranscriptTail(Data(threeTextBlocksJSON.utf8), droppingPartialFirstLine: false)
        .lastAssistantText,
    "셋.",
    "마지막 답변: 같은 줄의 마지막 text 블록"
)

expectEqual(DeadhdState.isValidSessionId("abc-123"), true, "세션 ID: 영문·숫자·하이픈")
expectEqual(DeadhdState.isValidSessionId("a/b"), false, "세션 ID: 슬래시는 거부")
expectEqual(DeadhdState.isValidSessionId("."), false, "세션 ID: 점 하나는 거부")
expectEqual(DeadhdState.isValidSessionId(""), false, "세션 ID: 빈 문자열은 거부")
expectEqual(
    DeadhdState.isValidSessionId("abc\n"),
    "abc\n".range(of: "^[A-Za-z0-9._-]{1,128}$", options: .regularExpression) != nil,
    "세션 ID: 끝 개행은 옛 구현과 동일"
)

// MARK: - 트랜스크립트 요약 캐시

let cacheKey = TranscriptFileKey(size: 10, modifiedAt: utcDate(2026, 10, 20, 9, 0))
var summaryCache = TranscriptSummaryCache()
summaryCache.store(TranscriptSummary(customTitle: "a"), key: cacheKey, for: "s1")
expectEqual(
    summaryCache.summary(for: "s1", key: cacheKey),
    TranscriptSummary(customTitle: "a"),
    "요약 캐시: 같은 키면 저장한 요약"
)
expectEqual(
    summaryCache.summary(for: "s1", key: TranscriptFileKey(size: 11, modifiedAt: cacheKey.modifiedAt)),
    nil,
    "요약 캐시: 크기가 다르면 다시 읽는다"
)
expectEqual(
    summaryCache.summary(
        for: "s1",
        key: TranscriptFileKey(size: 10, modifiedAt: cacheKey.modifiedAt.addingTimeInterval(0.001))
    ),
    nil,
    "요약 캐시: 1밀리초만 달라도 다시 읽는다"
)
expectEqual(summaryCache.summary(for: "s2", key: cacheKey), nil, "요약 캐시: 저장하지 않은 세션")
summaryCache.store(TranscriptSummary(customTitle: "b"), key: cacheKey, for: "s2")
summaryCache.retain(only: ["s2"])
expectEqual(summaryCache.summary(for: "s1", key: cacheKey), nil, "요약 캐시: 정리 뒤 빠진 세션")
expectEqual(
    summaryCache.summary(for: "s2", key: cacheKey),
    TranscriptSummary(customTitle: "b"),
    "요약 캐시: 정리 뒤 남은 세션"
)
summaryCache.store(TranscriptSummary(customTitle: "c"), key: cacheKey, for: "s2")
expectEqual(
    summaryCache.summary(for: "s2", key: cacheKey),
    TranscriptSummary(customTitle: "c"),
    "요약 캐시: 같은 키로 다시 저장하면 새 값"
)

// MARK: - 트랜스크립트 재탐색

let missAt = utcDate(2026, 10, 20, 9, 0)
let miss = TranscriptMiss(checkedAt: missAt, projectsModifiedAt: missAt)
expectEqual(
    miss.needsRescan(now: missAt.addingTimeInterval(29), projectsModifiedAt: missAt),
    false,
    "트랜스크립트 재탐색: 29초 뒤 같은 수정 시각이면 건너뛴다"
)
expectEqual(
    miss.needsRescan(now: missAt.addingTimeInterval(30), projectsModifiedAt: missAt),
    true,
    "트랜스크립트 재탐색: 30초 뒤면 다시 훑는다"
)
expectEqual(
    miss.needsRescan(now: missAt.addingTimeInterval(5), projectsModifiedAt: missAt.addingTimeInterval(1)),
    true,
    "트랜스크립트 재탐색: 수정 시각이 바뀌면 다시 훑는다"
)
let missWithoutProjects = TranscriptMiss(checkedAt: missAt, projectsModifiedAt: nil)
expectEqual(
    missWithoutProjects.needsRescan(now: missAt.addingTimeInterval(5), projectsModifiedAt: nil),
    false,
    "트랜스크립트 재탐색: 기록과 현재 모두 없으면 건너뛴다"
)
expectEqual(
    missWithoutProjects.needsRescan(now: missAt.addingTimeInterval(5), projectsModifiedAt: missAt),
    true,
    "트랜스크립트 재탐색: 현재 수정 시각이 생기면 다시 훑는다"
)

// MARK: - 현재 동작

let pendingToolJSON = """
{"type":"assistant","message":{"content":[{"type":"tool_use","id":"a","name":"Read","input":{"file_path":"/x/a.swift"}}]}}
{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"a","content":"ok"}]}}
{"type":"assistant","message":{"content":[{"type":"tool_use","id":"b","name":"Bash","input":{"description":"테스트 실행"}}]}}
"""
let pendingToolSummary = LocalSessions.summarizeTranscriptTail(
    Data(pendingToolJSON.utf8),
    droppingPartialFirstLine: false
)
expectEqual(pendingToolSummary.pendingToolLabel, "테스트 실행", "현재 동작: 짝이 없는 마지막 tool_use")
expectEqual(pendingToolSummary.lastToolName, "Bash", "현재 동작: 마지막 tool_use 이름은 그대로")

let matchedToolJSON = """
{"type":"assistant","message":{"content":[{"type":"tool_use","id":"a","name":"Read","input":{"file_path":"/x/a.swift"}}]}}
{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"a","content":"ok"}]}}
"""
expectEqual(
    LocalSessions.summarizeTranscriptTail(Data(matchedToolJSON.utf8), droppingPartialFirstLine: false)
        .pendingToolLabel,
    nil,
    "현재 동작: 짝이 맞은 tool_use 는 제외"
)

let stackedToolJSON = """
{"type":"assistant","message":{"content":[{"type":"tool_use","id":"a","name":"Read","input":{"file_path":"/x/a.swift"}},{"type":"tool_use","id":"b","name":"Bash","input":{"description":"테스트 실행"}}]}}
{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"b","content":"ok"}]}}
"""
expectEqual(
    LocalSessions.summarizeTranscriptTail(Data(stackedToolJSON.utf8), droppingPartialFirstLine: false)
        .pendingToolLabel,
    "파일 읽기 · a.swift",
    "현재 동작: 짝이 없는 것 중 마지막"
)

expectEqual(LocalSessions.nowActionLabel(toolName: "Bash", input: ["description": "테스트 실행"]),
            "테스트 실행", "현재 동작: Bash 설명")
expectEqual(LocalSessions.nowActionLabel(toolName: "Bash", input: ["command": "npm test\n--watch"]),
            "npm test", "현재 동작: Bash 명령은 첫 줄")
expectEqual(LocalSessions.nowActionLabel(toolName: "Bash", input: [:]), "Bash",
            "현재 동작: Bash 에 설명도 명령도 없으면 도구 이름")
expectEqual(LocalSessions.nowActionLabel(toolName: "Bash",
                                         input: ["description": String(repeating: "가", count: 60)])?.count,
            40, "현재 동작: 40자로 자른다")
expectEqual(LocalSessions.nowActionLabel(toolName: "Bash", input: ["description": "**테스트** 실행"]),
            "테스트 실행", "현재 동작: 마크다운은 평문화")
expectEqual(LocalSessions.nowActionLabel(toolName: "Agent", input: ["description": "코드 조사"]),
            "코드 조사", "현재 동작: Agent 설명")
expectEqual(LocalSessions.nowActionLabel(toolName: "Task", input: ["description": "코드 조사"]),
            "코드 조사", "현재 동작: Task 설명")
expectEqual(LocalSessions.nowActionLabel(toolName: "Edit", input: ["file_path": "/a/b/LocalSessions.swift"]),
            "파일 편집 · LocalSessions.swift", "현재 동작: Edit")
expectEqual(LocalSessions.nowActionLabel(toolName: "MultiEdit", input: ["file_path": "/a/b/App.swift"]),
            "파일 편집 · App.swift", "현재 동작: MultiEdit")
expectEqual(LocalSessions.nowActionLabel(toolName: "Write", input: ["file_path": "/a/b/App.swift"]),
            "파일 편집 · App.swift", "현재 동작: Write")
expectEqual(LocalSessions.nowActionLabel(toolName: "Edit", input: [:]),
            "파일 편집", "현재 동작: 파일 이름이 없으면 동작만")
expectEqual(LocalSessions.nowActionLabel(toolName: "Read", input: ["file_path": "/a/b/LocalSessions.swift"]),
            "파일 읽기 · LocalSessions.swift", "현재 동작: Read")
expectEqual(LocalSessions.nowActionLabel(toolName: "Grep", input: [:]), "검색", "현재 동작: Grep")
expectEqual(LocalSessions.nowActionLabel(toolName: "Glob", input: [:]), "검색", "현재 동작: Glob")
expectEqual(LocalSessions.nowActionLabel(toolName: "WebFetch", input: [:]), "웹 조회", "현재 동작: WebFetch")
expectEqual(LocalSessions.nowActionLabel(toolName: "WebSearch", input: [:]), "웹 조회", "현재 동작: WebSearch")
expectEqual(LocalSessions.nowActionLabel(toolName: "Skill", input: [:]), "Skill", "현재 동작: 그 밖의 도구는 이름")
expectEqual(LocalSessions.nowActionLabel(toolName: "mcp__keenable__search_web_pages", input: [:]),
            "search_web_pages", "현재 동작: MCP 도구는 도구 이름만")

// MARK: - PR 태그

let pullRequestJSON = """
{"type":"pr-link","prNumber":16428,"prUrl":"https://github.com/example-org/shop-api/pull/16428","prRepository":"example-org/shop-api"}
{"type":"pr-link","prNumber":16500,"prUrl":"https://github.com/example-org/shop-api/pull/16500","prRepository":"example-org/shop-api"}
"""
expectEqual(
    LocalSessions.summarizeTranscriptTail(Data(pullRequestJSON.utf8), droppingPartialFirstLine: false)
        .pullRequest,
    PullRequestLink(number: 16500, url: "https://github.com/example-org/shop-api/pull/16500"),
    "PR: 마지막 pr-link 를 쓴다"
)
expectEqual(
    LocalSessions.summarizeTranscriptTail(
        Data(#"{"type":"pr-link","prNumber":"16428","prUrl":"https://github.com/example-org/shop-api/pull/16428"}"#.utf8),
        droppingPartialFirstLine: false
    ).pullRequest,
    PullRequestLink(number: 16428, url: "https://github.com/example-org/shop-api/pull/16428"),
    "PR: 문자열 번호도 읽는다"
)
expectEqual(
    LocalSessions.summarizeTranscriptTail(Data(#"{"type":"pr-link","prUrl":"https://x"}"#.utf8),
                                          droppingPartialFirstLine: false).pullRequest,
    nil,
    "PR: 번호가 없으면 버린다"
)

// MARK: - 짧은 위치

let sampleHome = "/Users/alex"
expectEqual(
    LocalSessions.shortLocation(forCwd: "/Users/alex/orca/workspaces/shop/app-1256-demo", home: sampleHome),
    "shop/app-1256-demo", "위치: orca 워크스페이스는 저장소/이름"
)
expectEqual(
    LocalSessions.shortLocation(forCwd: "/Users/alex/orca/workspaces/shop/app-1256-demo/Sources", home: sampleHome),
    "shop/app-1256-demo", "위치: orca 워크스페이스 하위 폴더도 같은 위치"
)
expectEqual(
    LocalSessions.shortLocation(forCwd: "/Users/alex/git-repo/deadhd-bar/.claude/worktrees/wbig1", home: sampleHome),
    "deadhd-bar/wbig1", "위치: worktree 는 저장소/이름"
)
expectEqual(
    LocalSessions.shortLocation(forCwd: "/tmp/x/other/.claude/worktrees/w2/sub", home: sampleHome),
    "other/w2", "위치: 홈 밖 worktree 도 저장소/이름"
)
expectEqual(
    LocalSessions.shortLocation(forCwd: "/Users/alex/git-repo/deadhd-bar", home: sampleHome),
    "deadhd-bar", "위치: git-repo 아래 저장소"
)
expectEqual(
    LocalSessions.shortLocation(forCwd: "/Users/alex/git-repo/deadhd-bar/Sources", home: sampleHome),
    "deadhd-bar/Sources", "위치: git-repo 하위 첫 칸"
)
expectEqual(LocalSessions.shortLocation(forCwd: sampleHome, home: sampleHome), "~", "위치: 홈 자체")
expectEqual(LocalSessions.shortLocation(forCwd: "/opt/tools/foo", home: sampleHome), "foo", "위치: 그 밖은 마지막 칸")
expectEqual(LocalSessions.shortLocation(forCwd: nil, home: sampleHome), nil, "위치: cwd 가 없으면 nil")
expectEqual(LocalSessions.shortLocation(forCwd: "/Users/alex", home: nil), "alex", "위치: 홈을 모르면 마지막 칸")

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
    startedAt: Date? = nil,
    deadhd: DeadhdState? = nil
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
        now: now,
        deadhd: deadhd
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
expectEqual(inputNeeded.message, "답을 기다리고 있어요", "상태 표: 입력 대기 문구")
expectEqual(Grouping.group(SessionsResponse(sessions: [inputNeeded]), now: now).attention.first?.status,
            "답을 기다리고 있어요", "상태 표: 입력 대기는 확인 필요 그룹")

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
expectEqual(idleMappedGroup.done.first?.status, "끝났어요", "상태 표: idle 은 완료 문구")

let unknownStatus = localSession(status: "paused")
expectEqual(unknownStatus.bucket, "working", "상태 표: 그 밖의 상태는 working")
expectEqual(unknownStatus.status, "paused", "상태 표: 그 밖의 상태는 원문 유지")
expectEqual(unknownStatus.message, nil, "상태 표: 그 밖의 상태에는 message 가 없다")

let stalled = localSession(status: "busy", summary: TranscriptSummary(lastMeaningfulAt: now.addingTimeInterval(-601)))
expectEqual(stalled.bucket, "stall", "stall: 마지막 줄이 10분보다 오래되면 stall")
expectEqual(Grouping.group(SessionsResponse(sessions: [stalled]), now: now).attention.count, 1,
            "stall: 확인 필요 그룹으로 간다")

let stallShell = localSession(status: "shell", summary: TranscriptSummary(lastMeaningfulAt: now.addingTimeInterval(-3660)))
expectEqual(stallShell.bucket, "stall", "stall: shell 도 60분이 넘으면 stall")

let boundary = localSession(status: "busy", summary: TranscriptSummary(lastMeaningfulAt: now.addingTimeInterval(-600)))
expectEqual(boundary.bucket, "working", "stall: 정확히 10분이면 아직 working")

let noTranscript = localSession(status: "busy", summary: TranscriptSummary())
expectEqual(noTranscript.bucket, "working", "stall: 트랜스크립트가 없으면 working")

let staleIdle = localSession(status: "idle", summary: TranscriptSummary(lastMeaningfulAt: now.addingTimeInterval(-3600)))
expectEqual(staleIdle.bucket, "done", "stall: stall 판정은 busy/shell 에만 적용")

let shellBackground = localSession(
    status: "shell",
    summary: TranscriptSummary(lastMeaningfulAt: now.addingTimeInterval(-1800), backgroundTasks: 1)
)
expectEqual(shellBackground.bucket, "working", "stall: 백그라운드 작업이 도는 shell 은 30분이 지나도 working")

let shellBackgroundBoundary = localSession(
    status: "shell",
    summary: TranscriptSummary(lastMeaningfulAt: now.addingTimeInterval(-3600), backgroundTasks: 1)
)
expectEqual(shellBackgroundBoundary.bucket, "working", "stall: 백그라운드 작업이 도는 shell 은 정확히 60분이면 working")

let shellBackgroundStalled = localSession(
    status: "shell",
    summary: TranscriptSummary(lastMeaningfulAt: now.addingTimeInterval(-3660), backgroundTasks: 1)
)
expectEqual(shellBackgroundStalled.bucket, "stall", "stall: 백그라운드 작업이 도는 shell 도 60분이 넘으면 stall")

let shellNoBackground = localSession(
    status: "shell",
    summary: TranscriptSummary(lastMeaningfulAt: now.addingTimeInterval(-660), backgroundTasks: 0)
)
expectEqual(shellNoBackground.bucket, "working", "stall: 셸을 띄운 줄이 꼬리 밖이라 개수가 0 이어도 shell 은 60분 기준")
let shellUncountedLong = localSession(
    status: "shell",
    summary: TranscriptSummary(lastMeaningfulAt: now.addingTimeInterval(-1800), backgroundTasks: 0)
)
expectEqual(shellUncountedLong.bucket, "working", "stall: 개수가 0 인 shell 도 30분이면 working")

let busyWithBackground = localSession(
    status: "busy",
    summary: TranscriptSummary(lastMeaningfulAt: now.addingTimeInterval(-660), backgroundTasks: 1)
)
expectEqual(busyWithBackground.bucket, "working", "stall: busy 도 백그라운드 작업이 있으면 60분 기준")
let busyBackgroundStalled = localSession(
    status: "busy",
    summary: TranscriptSummary(lastMeaningfulAt: now.addingTimeInterval(-3660), backgroundTasks: 1)
)
expectEqual(busyBackgroundStalled.bucket, "stall", "stall: 백그라운드 작업이 도는 busy 도 60분이 넘으면 stall")
let busyNoBackgroundLong = localSession(
    status: "busy",
    summary: TranscriptSummary(lastMeaningfulAt: now.addingTimeInterval(-660), backgroundTasks: 0)
)
expectEqual(busyNoBackgroundLong.bucket, "stall", "stall: 백그라운드 작업이 없는 busy 는 10분 기준")

expectEqual(
    Grouping.group(SessionsResponse(sessions: [shellBackgroundStalled]), now: now).attention.first?.status,
    "백그라운드 작업 2분째 · 멈췄는지 확인해 보세요",
    "stall: 백그라운드 작업이 있는 stall 은 백그라운드 작업 문구"
)

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

// MARK: - 로컬 위치·현재 동작·PR 태그

let sameTitleRecord = LocalSessionRecord(
    pid: 100,
    sessionId: "loc",
    cwd: "/Users/alex/git-repo/deadhd-bar",
    name: "deadhdbar",
    entrypoint: "cli",
    status: "busy"
)
let sameTitleSession = LocalSessions.makeSession(
    record: sameTitleRecord,
    summary: TranscriptSummary(),
    now: now,
    home: sampleHome
)
expectEqual(sameTitleSession.title, "deadhdbar", "위치: 제목은 세션 파일 이름")
expectEqual(sameTitleSession.place, nil, "위치: 제목과 같으면(대소문자·-·_ 무시) 그리지 않는다")

let differentTitleRecord = LocalSessionRecord(
    pid: 100,
    sessionId: "loc",
    cwd: "/Users/alex/git-repo/deadhd-bar",
    name: "pulse",
    entrypoint: "cli",
    status: "busy"
)
let differentTitleSession = LocalSessions.makeSession(
    record: differentTitleRecord,
    summary: TranscriptSummary(),
    now: now,
    home: sampleHome
)
expectEqual(differentTitleSession.place?.label, "deadhd-bar", "위치: 제목과 다르면 그린다")
let locatedItem = DisplayItem(session: differentTitleSession, group: .working, now: now)
expectEqual(locatedItem.placeText, "deadhd-bar", "위치: 행은 place 를 상태 옆에 그린다")

let actionWorking = localSession(status: "busy", summary: TranscriptSummary(pendingToolLabel: "테스트 실행"))
expectEqual(actionWorking.nowLabel, "테스트 실행", "현재 동작: 진행 중 세션에 넣는다")
let actionItem = Grouping.group(SessionsResponse(sessions: [actionWorking]), now: now).working.first
expectEqual(actionItem?.status, "2분째 · 테스트 실행", "현재 동작: 상태 문구 뒤에 붙는다")

let actionWaiting = localSession(
    status: "waiting",
    waitingFor: "input needed",
    summary: TranscriptSummary(pendingToolLabel: "테스트 실행")
)
expectEqual(actionWaiting.nowLabel, nil, "현재 동작: 대기 세션에는 넣지 않는다")
let actionIdle = localSession(status: "idle", summary: TranscriptSummary(pendingToolLabel: "테스트 실행"))
expectEqual(actionIdle.nowLabel, nil, "현재 동작: 완료 세션에는 넣지 않는다")

let pullRequestSession = localSession(
    status: "busy",
    summary: TranscriptSummary(
        pullRequest: PullRequestLink(number: 16428, url: "https://github.com/example-org/shop-api/pull/16428")
    )
)
let pullRequestItem = Grouping.group(SessionsResponse(sessions: [pullRequestSession]), now: now).working.first
expectEqual(pullRequestItem?.prTag, "#16428", "PR: 태그 문구")
expectEqual(pullRequestItem?.prURL, "https://github.com/example-org/shop-api/pull/16428", "PR: 태그가 여는 주소")
expectEqual(actionItem?.prTag, nil, "PR: pr-link 가 없으면 태그도 없다")

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
expectEqual(rich.pagePath, nil, "필드: pagePath 는 없다")
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

// MARK: - deadhd 상태 파일

func deadhdState(_ json: String, expected: String? = "local") -> DeadhdState? {
    DeadhdState.parse(Data(json.utf8), expectedSessionId: expected)
}

let deadhdJSON = """
{
  "sessionId": "local",
  "out": "/tmp/deadhd-x.html",
  "data": "/tmp/deadhd-x.json",
  "cwd": "/Users/a/proj",
  "lastTool": {"name": "Bash", "at": "2026-10-20T11:59:48+00:00", "durationMs": 12},
  "backgroundTasks": [{"type": "shell", "description": "npm test"}, {"type": "shell", "description": "watch"}],
  "compactions": {"count": 1, "lastAt": "2026-10-20T10:00:00+00:00"},
  "summary": {
    "title": "deadhd 제목",
    "key": "APP-1",
    "keyHref": "https://tracker.example.com/browse/APP-1",
    "counts": {"done": 5, "now": 1, "side": 0, "left": 3, "blocked": 1},
    "total": 9,
    "states": ["done", "done", "done", "done", "done", "now", "left", "left", "left"],
    "nowLabel": "흔들림·행 어긋남",
    "pr": {"text": "#16331", "href": "https://github.com/example-org/shop-api/pull/16331"},
    "eta": "2026-10-20T12:10:00+00:00",
    "etaCalibrated": "2026-10-20T12:03:00+00:00",
    "dataAt": "2026-10-20T11:58:00+00:00",
    "allDone": false
  }
}
"""
let parsedState = deadhdState(deadhdJSON)
expectEqual(parsedState?.title, "deadhd 제목", "상태 파일: 제목")
expectEqual(parsedState?.counts, SessionCounts(done: 5, left: 3, now: 1, blocked: 1), "상태 파일: counts")
expectEqual(parsedState?.total, 9, "상태 파일: total")
expectEqual(parsedState?.states, ["done", "done", "done", "done", "done", "now", "left", "left", "left"],
            "상태 파일: 단계 상태")
expectEqual(parsedState?.nowLabel, "흔들림·행 어긋남", "상태 파일: 지금 단계")
expectEqual(parsedState?.key, "APP-1", "상태 파일: 지라 키")
expectEqual(parsedState?.keyHref, "https://tracker.example.com/browse/APP-1", "상태 파일: 지라 링크")
expectEqual(parsedState?.pr, PullRequestLink(number: 16331,
                                             url: "https://github.com/example-org/shop-api/pull/16331",
                                             label: "#16331"), "상태 파일: PR")
expectEqual(parsedState?.eta, utcDate(2026, 10, 20, 12, 3), "상태 파일: 보정된 예상 시각을 먼저 쓴다")
expectEqual(parsedState?.dataAt, utcDate(2026, 10, 20, 11, 58), "상태 파일: 데이터 시각")
expectEqual(parsedState?.pagePath, "/tmp/deadhd-x.html", "상태 파일: 진행 페이지 경로")
expectEqual(parsedState?.dataPath, "/tmp/deadhd-x.json", "상태 파일: 체크리스트 데이터 경로")
expectEqual(parsedState?.hasChecklist, true, "상태 파일: 체크리스트가 있다")
expectEqual(parsedState?.hasCompactions, true, "상태 파일: 압축 필드가 있다")
expectEqual(parsedState?.compactions?.count, 1, "상태 파일: 압축 횟수")
expectEqual(parsedState?.backgroundTasks.count, 2, "상태 파일: 백그라운드 작업")
expectEqual(parsedState?.lastTool?.name, "Bash", "상태 파일: 마지막 도구")
expectEqual(parsedState?.progressIsStale(at: now), false, "상태 파일: 30분 안쪽이면 흐리지 않는다")
expectEqual(parsedState?.progressIsStale(at: utcDate(2026, 10, 20, 12, 31)), true,
            "상태 파일: 30분을 넘으면 흐린다")
expectEqual(parsedState?.progressIsStale(at: utcDate(2026, 10, 20, 12, 28)), false,
            "상태 파일: 30분 경계는 아직 흐리지 않는다")

let offJSON = deadhdJSON.replacingOccurrences(
    of: "\"sessionId\": \"local\",",
    with: "\"sessionId\": \"local\", \"offAt\": \"2026-10-20T11:00:00.100+00:00\","
)
let offState = deadhdState(offJSON)
expectEqual(offState?.isOff, true, "상태 파일: 꺼진 세션")
expectEqual(offState?.hasChecklist, false, "상태 파일: 꺼진 세션은 체크리스트를 쓰지 않는다")
expectEqual(offState?.title, "deadhd 제목", "상태 파일: 꺼져도 요약 원문은 읽는다")

let lenientStateJSON = """
{
  "sessionId": "local",
  "out": "relative/deadhd.html",
  "data": "relative/deadhd.json",
  "backgroundTasks": {"type": "shell"},
  "compactions": {"count": "many"},
  "lastTool": {"name": 42},
  "summary": {
    "title": 7,
    "counts": "none",
    "total": "9",
    "key": [],
    "nowLabel": null,
    "pr": {"text": 1, "href": "ftp://example.com/1"},
    "eta": "not-a-date",
    "dataAt": 5
  }
}
"""
let lenientState = deadhdState(lenientStateJSON)
expectEqual(lenientState?.summaryAvailable, true, "상태 파일: 어긋난 필드가 있어도 파일은 읽는다")
expectEqual(lenientState?.hasChecklist, false, "상태 파일: counts 가 어긋나면 체크리스트가 없다")
expectEqual(lenientState?.title, nil, "상태 파일: 숫자 제목은 버린다")
expectEqual(lenientState?.counts, nil, "상태 파일: 문자열 counts 는 버린다")
expectEqual(lenientState?.total, nil, "상태 파일: 문자열 total 은 버린다")
expectEqual(lenientState?.key, nil, "상태 파일: 배열 키는 버린다")
expectEqual(lenientState?.pr, nil, "상태 파일: http 가 아닌 PR 링크는 버린다")
expectEqual(lenientState?.eta, nil, "상태 파일: 못 읽는 시각은 버린다")
expectEqual(lenientState?.dataAt, nil, "상태 파일: 숫자 시각은 버린다")
expectEqual(lenientState?.pagePath, nil, "상태 파일: 상대 경로는 진행 페이지로 쓰지 않는다")
expectEqual(lenientState?.dataPath, nil, "상태 파일: 상대 경로는 체크리스트 데이터로 쓰지 않는다")
expectEqual(lenientState?.hasBackgroundTasks, false, "상태 파일: 배열이 아닌 작업 목록은 버린다")
expectEqual(lenientState?.backgroundTasks, [], "상태 파일: 버린 작업 목록은 빈 배열")
expectEqual(lenientState?.compactions?.count, 0, "상태 파일: 어긋난 압축 횟수는 0")
expectEqual(lenientState?.lastTool, nil, "상태 파일: 이름이 숫자인 도구는 버린다")
expectEqual(lenientState?.states, nil, "상태 파일: states 가 없으면 nil")
let mixedStates = deadhdState("""
{"sessionId":"local","summary":{"states":["done",1]}}
""")
expectEqual(mixedStates?.states, nil, "상태 파일: 문자열 아닌 원소가 섞이면 배열 전체를 버린다")

let absentState = deadhdState("{\"sessionId\":\"local\"}")
expectEqual(absentState?.summaryAvailable, false, "상태 파일: summary 가 없으면 체크리스트가 없다")
expectEqual(absentState?.hasChecklist, false, "상태 파일: summary 가 없으면 진행률도 없다")
expectEqual(deadhdState("{\"sessionId\":\"other\"}"), nil, "상태 파일: 다른 세션 파일은 읽지 않는다")
expectEqual(deadhdState("{\"sessionId\":\"../local\"}"), nil, "상태 파일: 경로가 섞인 id 는 버린다")
expectEqual(deadhdState("not json"), nil, "상태 파일: JSON 이 아니면 버린다")
expectEqual(DeadhdState.isValidSessionId("1121d7e7-9881-4c8c-8605-b1ffb8ea14fa"), true,
            "상태 파일: 세션 id 모양")
expectEqual(DeadhdState.isValidSessionId(".."), false, "상태 파일: 상위 경로 id 는 거부")
expectEqual(DeadhdState.stateDirectory(environment: [:]), "/tmp/deadhd-state",
            "상태 파일: 기본 디렉터리")
expectEqual(DeadhdState.stateDirectory(environment: ["DEADHD_STATE_DIR": "/x/y"]), "/x/y",
            "상태 파일: DEADHD_STATE_DIR 로 바꾼다")

// MARK: - deadhd 요약을 세션에 합치기

let deadhdSummary = TranscriptSummary(
    customTitle: "세션 제목",
    lastPrompt: "프롬프트",
    pendingToolLabel: "테스트 실행",
    pullRequest: PullRequestLink(number: 16331, url: "https://github.com/example-org/shop-api/pull/16331")
)
let mergedSession = localSession(status: "busy", summary: deadhdSummary, deadhd: parsedState)
expectEqual(mergedSession.title, "deadhd 제목", "합치기: 요약 제목이 세션 제목을 이긴다")
expectEqual(mergedSession.key, "이름", "합치기: 세션 이름은 태그로 남는다")
expectEqual(mergedSession.counts, SessionCounts(done: 5, left: 3, now: 1, blocked: 1), "합치기: counts")
expectEqual(mergedSession.total, 9, "합치기: total")
expectEqual(mergedSession.nowLabel, "흔들림·행 어긋남", "합치기: 지금 단계")
expectEqual(mergedSession.pagePath, "/tmp/deadhd-x.html", "합치기: 진행 페이지 경로")
expectEqual(mergedSession.jiraKey, "APP-1", "합치기: 지라 키")
expectEqual(mergedSession.jiraHref, "https://tracker.example.com/browse/APP-1", "합치기: 지라 링크")
expectEqual(mergedSession.pr?.label, "#16331", "합치기: 요약 PR 문구를 쓴다")
expectEqual(mergedSession.extraPRs.count, 0, "합치기: 같은 PR 은 한 번만 그린다")

let differentPRSummary = TranscriptSummary(
    pullRequest: PullRequestLink(number: 16428, url: "https://github.com/example-org/shop-api/pull/16428")
)
let twoPRSession = localSession(status: "busy", summary: differentPRSummary, deadhd: parsedState)
expectEqual(twoPRSession.pr?.number, 16331, "PR 합치기: deadhd PR 이 대표")
expectEqual(twoPRSession.extraPRs.map(\.number), [16428], "PR 합치기: 다른 PR 은 따로 남긴다")
let offPRSession = localSession(status: "busy", summary: differentPRSummary, deadhd: offState)
expectEqual(offPRSession.pr?.number, 16428, "PR 합치기: 꺼진 세션은 트랜스크립트 PR")
expectEqual(offPRSession.extraPRs.count, 0, "PR 합치기: 꺼진 세션은 deadhd PR 을 쓰지 않는다")
expectEqual(mergedSession.eta, utcDate(2026, 10, 20, 12, 3), "합치기: 예상 시각")
expectEqual(mergedSession.dataAt, utcDate(2026, 10, 20, 11, 58), "합치기: 데이터 시각")
expectEqual(mergedSession.backgroundTasks.count, 2, "합치기: 백그라운드 작업 목록")

let mergedGrouped = Grouping.group(SessionsResponse(sessions: [mergedSession]), now: now)
let mergedItem = mergedGrouped.working.first
expectEqual(mergedItem?.progress?.text, "5/9", "합치기: 진행 막대 수치")
expectEqual(mergedItem?.status, "2분째 · ▶ 흔들림·행 어긋남 · 약 3분 남음",
            "합치기: 상태 줄에 지금 단계와 남은 시간")
expectEqual(mergedItem?.blocked, true, "합치기: 막힌 항목이 있으면 확인 필요 색")
expectEqual(mergedItem?.progressStale, false, "합치기: 최근 데이터는 흐리지 않는다")
expectEqual(mergedItem?.prTag, "#16331", "합치기: PR 태그")
expectEqual(mergedItem?.jiraKey, "APP-1", "합치기: 지라 태그")
expectEqual(mergedItem?.clickAction, .cwd("/Users/a/proj"), "합치기: 행 탭은 cwd 로 터미널을 찾는다")
expectEqual(mergedItem?.isActionable, true, "합치기: cwd 가 있으면 누를 수 있다")
expectEqual(mergedItem?.stepStates, ["done", "done", "done", "done", "done", "now", "left", "left", "left"],
            "합치기: 단계 상태를 항목에 넘긴다")
expectEqual(mergedItem?.activityLine, "압축 1 · 백그라운드 2 · Bash 12초 전", "합치기: 활동 줄")

let staleSession = localSession(status: "busy", summary: deadhdSummary,
                                statusUpdatedAt: now.addingTimeInterval(-40 * 60), deadhd: parsedState)
let staleItem = Grouping.group(SessionsResponse(sessions: [staleSession]),
                               now: utcDate(2026, 10, 20, 12, 29)).working.first
expectEqual(staleItem?.progressStale, true, "합치기: 30분 넘은 진행률은 흐리게 그린다")

let idleStateSession = localSession(status: "idle", summary: deadhdSummary, deadhd: parsedState)
let idleStateItem = Grouping.group(SessionsResponse(sessions: [idleStateSession]), now: now).done.first
expectEqual(idleStateItem?.status, "끝났어요 · ▶ 흔들림·행 어긋남 · 약 3분 남음",
            "합치기: 완료로 바뀐 세션도 지금 단계를 보여 준다")
expectEqual(idleStateItem?.progress?.text, "5/9", "합치기: 완료 세션에도 진행률을 그린다")

let offSession = localSession(status: "busy", summary: deadhdSummary, deadhd: offState)
expectEqual(offSession.title, "세션 제목", "꺼짐: 요약 제목을 쓰지 않는다")
expectEqual(offSession.counts, nil, "꺼짐: 진행률을 쓰지 않는다")
expectEqual(offSession.total, nil, "꺼짐: 전체 수를 쓰지 않는다")
expectEqual(offSession.pagePath, nil, "꺼짐: 진행 페이지를 달지 않는다")
expectEqual(offSession.jiraKey, nil, "꺼짐: 지라 태그를 달지 않는다")
expectEqual(offSession.nowLabel, "테스트 실행", "꺼짐: 트랜스크립트의 현재 동작을 쓴다")
expectEqual(offSession.activity?.compactions, 1, "꺼짐: 활동 정보는 그대로 쓴다")

let noPageState = deadhdState("""
{"sessionId":"local","out":"/tmp/deadhd-x.html","summary":{"title":"페이지 없는 요약"}}
""")
let noPageSession = localSession(status: "busy", summary: deadhdSummary, deadhd: noPageState)
expectEqual(noPageState?.pagePath, "/tmp/deadhd-x.html", "상태 파일: out 경로를 읽는다")
expectEqual(noPageSession.pagePath, nil, "상태 파일: 체크리스트가 없으면 진행 페이지를 달지 않는다")
expectEqual(noPageSession.title, "세션 제목", "상태 파일: 체크리스트가 없으면 요약 제목을 쓰지 않는다")
expectEqual(noPageSession.counts, nil, "상태 파일: counts 가 없으면 체크리스트가 아니다")

// MARK: - 활동 줄

expectEqual(SessionActivity(compactions: 1, backgroundTasks: 2,
                            lastTool: LastTool(name: "Bash", at: utcDate(2026, 10, 20, 11, 59, 48)))
        .line(now: now),
    "압축 1 · 백그라운드 2 · Bash 12초 전", "활동 줄: 세 값을 가운뎃점으로 잇는다")
expectEqual(SessionActivity(compactions: 0, backgroundTasks: 0).line(now: now), nil,
            "활동 줄: 0 은 그리지 않는다")
expectEqual(SessionActivity(compactions: 2, backgroundTasks: 0, lastTool: LastTool(name: "Read", at: nil))
        .line(now: now), "압축 2 · Read", "활동 줄: 시각이 없으면 도구 이름만")
expectEqual(SessionActivity().line(now: now), nil, "활동 줄: 값이 없으면 없다")

let stateWithoutActivity = deadhdState("""
{"sessionId":"local","summary":{"title":"활동 없음","counts":{"done":1},"total":3}}
""")
let fallbackActivity = SessionActivity.make(
    state: stateWithoutActivity,
    summary: TranscriptSummary(lastToolName: "Grep", lastToolAt: utcDate(2026, 10, 20, 11, 57),
                               compactions: 2, backgroundTasks: 1)
)
expectEqual(fallbackActivity?.compactions, 2, "활동 줄: 상태 파일에 없으면 트랜스크립트 압축 횟수")
expectEqual(fallbackActivity?.backgroundTasks, 1, "활동 줄: 상태 파일에 없으면 트랜스크립트 작업 수")
expectEqual(fallbackActivity?.lastTool?.name, "Grep", "활동 줄: 상태 파일에 없으면 트랜스크립트 도구")
let stateWinsActivity = SessionActivity.make(
    state: parsedState,
    summary: TranscriptSummary(lastToolName: "Grep", lastToolAt: utcDate(2026, 10, 20, 11, 57),
                               compactions: 7, backgroundTasks: 9)
)
expectEqual(stateWinsActivity?.compactions, 1, "활동 줄: 상태 파일 압축 횟수가 먼저")
expectEqual(stateWinsActivity?.backgroundTasks, 2, "활동 줄: 상태 파일 작업 수가 먼저")
expectEqual(stateWinsActivity?.lastTool?.name, "Bash", "활동 줄: 상태 파일 도구가 먼저")

// MARK: - 지금 하는 일 한 줄

expectEqual(NowLine.resolve(stage: "테스트 작성", currentAction: "파일 편집 · A.swift",
                            lastSentence: "테스트를 돌립니다", statusLine: "2분째"),
            "▶ 테스트 작성", "지금 한 줄: 단계가 있으면 단계")
expectEqual(NowLine.resolve(stage: "테스트 작성", currentAction: "파일 편집 · A.swift",
                            lastSentence: "테스트를 돌립니다",
                            statusLine: "2분째 · ▶ 테스트 작성"),
            "파일 편집 · A.swift", "지금 한 줄: 상태 줄에 있는 단계는 건너뛴다")
expectEqual(NowLine.resolve(stage: "테스트 작성", currentAction: "테스트 작성",
                            lastSentence: "테스트를 돌립니다",
                            statusLine: "2분째 · 테스트 작성"),
            "테스트를 돌립니다", "지금 한 줄: 상태 줄에 있는 도구 문구도 건너뛴다")
expectEqual(NowLine.resolve(stage: nil, currentAction: nil,
                            lastSentence: "두 번째 문장입니다", statusLine: "2분째"),
            "두 번째 문장입니다", "지금 한 줄: 마지막 답의 마지막 문장")
expectEqual(NowLine.resolve(stage: nil, currentAction: nil,
                            lastSentence: "v1.2 를 확인합니다", statusLine: "2분째"),
            "v1.2 를 확인합니다", "지금 한 줄: 소수점은 문장 끝이 아니다")
expectEqual(NowLine.resolve(stage: nil, currentAction: nil,
                            lastSentence: "수정을 마쳤습니다.", statusLine: "2분째"),
            "수정을 마쳤습니다.", "지금 한 줄: 문장 부호로 끝나는 답")
expectEqual(NowLine.resolve(stage: "  ", currentAction: "\n", lastSentence: nil, statusLine: "2분째"), nil,
            "지금 한 줄: 빈 값뿐이면 그리지 않는다")
expectEqual(NowLine.resolve(stage: nil, currentAction: nil, lastSentence: "", statusLine: "2분째"), nil,
            "지금 한 줄: 값이 없으면 없다")

expectEqual(NowLine.lastSentence("첫 문장입니다. 두 번째 문장입니다"), "두 번째 문장입니다",
            "마지막 문장: 문장 부호로 나눈다")
expectEqual(NowLine.lastSentence("v1.2 를 확인합니다"), "v1.2 를 확인합니다",
            "마지막 문장: 소수점은 문장 끝이 아니다")
expectEqual(NowLine.lastSentence("수정을 마쳤습니다."), "수정을 마쳤습니다.",
            "마지막 문장: 문장 부호로 끝나는 답")
expectEqual(NowLine.lastSentence("정리했습니다. | 항목 | 값 |"), "정리했습니다.",
            "마지막 문장: 표 행 조각은 건너뛴다")
expectEqual(NowLine.lastSentence("정리했습니다. -"), "정리했습니다.",
            "마지막 문장: 목록 기호 조각은 건너뛴다")
expectEqual(NowLine.lastSentence("정리했습니다. 1."), "정리했습니다.",
            "마지막 문장: 번호 목록 조각은 건너뛴다")
expectEqual(NowLine.lastSentence("정리했습니다. ```swift"), "정리했습니다.",
            "마지막 문장: 코드 펜스 조각은 건너뛴다")
let cappedSentence = NowLine.lastSentence(String(repeating: "가", count: 200))
expectEqual(cappedSentence?.count, NowLine.sentenceLimit, "마지막 문장: 길이 상한")
expectEqual(cappedSentence?.hasPrefix(String(repeating: "가", count: NowLine.sentenceLimit - 1)), true,
            "마지막 문장: 자를 때는 앞쪽을 남긴다")
expectEqual(cappedSentence?.hasSuffix("…"), true, "마지막 문장: 자를 때는 끝에 줄임표")

let overLimitText = String(repeating: "가", count: 200) + ". 마지막 문장입니다."
let overLimitJSON = """
{"type":"assistant","message":{"content":[{"type":"text","text":"\(overLimitText)"}]}}
"""
let overLimitSummary = LocalSessions.summarizeTranscriptTail(
    Data(overLimitJSON.utf8),
    droppingPartialFirstLine: false
)
expectEqual(overLimitSummary.lastAssistantText?.count, 160, "요약: 인용은 160자로 자른다")
expectEqual(overLimitSummary.lastSentence, "마지막 문장입니다.",
            "요약: 마지막 문장은 자르기 전 원문에서 고른다")
let overLimitItem = Grouping.group(
    SessionsResponse(sessions: [localSession(status: "busy", summary: overLimitSummary)]),
    now: now
).working.first
expectEqual(overLimitItem?.nowLine, "마지막 문장입니다.",
            "지금 한 줄: 잘린 인용 조각이 아니라 온전한 마지막 문장")

let tableJSON = """
{"type":"assistant","message":{"content":[{"type":"text","text":"정리했습니다.\\n\\n| 항목 | 값 |\\n|---|---|"}]}}
"""
expectEqual(
    LocalSessions.summarizeTranscriptTail(Data(tableJSON.utf8), droppingPartialFirstLine: false).lastSentence,
    "정리했습니다.",
    "요약: 표 조각 대신 앞 문장"
)

let nowLineSummary = TranscriptSummary(
    lastAssistantText: "행을 고쳤습니다. 이제 스크린샷을 남깁니다",
    pendingToolLabel: "파일 편집 · SessionRowView.swift"
)
let nowLineItem = Grouping.group(
    SessionsResponse(sessions: [localSession(status: "busy", summary: nowLineSummary)]),
    now: now
).working.first
expectEqual(nowLineItem?.isRunning, true, "지금 한 줄: 진행 중 행에 그린다")
expectEqual(nowLineItem?.nowLine, "이제 스크린샷을 남깁니다",
            "지금 한 줄: 상태 줄에 이미 있는 도구 문구 대신 마지막 문장")

let checklistNowItem = Grouping.group(
    SessionsResponse(sessions: [
        localSession(status: "busy", summary: nowLineSummary, deadhd: parsedState),
    ]),
    now: now
).working.first
expectEqual(checklistNowItem?.nowLine, "파일 편집 · SessionRowView.swift",
            "지금 한 줄: 체크리스트 단계는 상태 줄에 있으므로 도구 문구")

let stallNowItem = Grouping.group(
    SessionsResponse(sessions: [
        localSession(status: "busy", summary: TranscriptSummary(
            lastAssistantText: "배포를 확인합니다",
            lastMeaningfulAt: now.addingTimeInterval(-15 * 60),
            pendingToolLabel: "웹 조회"
        )),
    ]),
    now: now
).attention.first
expectEqual(stallNowItem?.isStall, true, "지금 한 줄: stall 은 확인 필요 그룹")
expectEqual(stallNowItem?.isRunning, true, "지금 한 줄: stall 도 진행 중으로 다룬다")
expectEqual(stallNowItem?.nowLine, "웹 조회", "지금 한 줄: stall 행은 실행 중인 도구")

let idleNowItem = Grouping.group(
    SessionsResponse(sessions: [localSession(status: "idle", summary: nowLineSummary)]),
    now: now
).done.first
expectEqual(idleNowItem?.isRunning, false, "지금 한 줄: 완료 행에는 그리지 않는다")

// MARK: - 트랜스크립트의 압축·백그라운드

let compactJSON = """
{"type":"system","subtype":"compact_boundary","timestamp":"2026-10-20T11:00:00Z"}
{"type":"system","subtype":"turn_duration"}
{"type":"assistant","timestamp":"2026-10-20T11:10:00Z","message":{"content":[{"type":"tool_use","id":"bg-1","name":"Bash","input":{"run_in_background":true,"description":"watch"}},{"type":"tool_use","id":"fg-1","name":"Read","input":{}}]}}
{"type":"api-request-blob","message":{"content":[{"type":"tool_use","id":"bg-1","name":"Bash","input":{"run_in_background":true}}]}}
"""
let compactSummary = LocalSessions.summarizeTranscriptTail(
    Data(compactJSON.utf8), droppingPartialFirstLine: false
)
expectEqual(compactSummary.compactions, 1, "트랜스크립트: 압축 경계 레코드를 센다")
expectEqual(compactSummary.backgroundTasks, 1, "트랜스크립트: 끝나지 않은 백그라운드 작업")
expectEqual(compactSummary.lastToolName, "Read", "트랜스크립트: 마지막 도구")

let notifiedJSON = compactJSON + "\n" + """
{"type":"user","message":{"content":"<task-notification>\\n<task-id>bg-1</task-id>\\n<tool-use-id>bg-1</tool-use-id>\\n<status>completed</status>\\n</task-notification>"}}
"""
let notifiedSummary = LocalSessions.summarizeTranscriptTail(
    Data(notifiedJSON.utf8), droppingPartialFirstLine: false
)
expectEqual(notifiedSummary.backgroundTasks, 0, "트랜스크립트: 완료 알림을 받은 작업은 뺀다")

let asyncJSON = """
{"type":"assistant","timestamp":"2026-10-20T11:10:00Z","message":{"content":[{"type":"tool_use","id":"agent-1","name":"Agent","input":{"description":"review"}},{"type":"tool_use","id":"auto-1","name":"Bash","input":{"command":"make"}},{"type":"tool_use","id":"mon-1","name":"Monitor","input":{}}]}}
{"type":"user","toolUseResult":{"isAsync":true,"status":"async_launched","agentId":"a1"},"message":{"content":[{"type":"tool_result","tool_use_id":"agent-1","content":"launched"}]}}
{"type":"user","toolUseResult":{"backgroundTaskId":"b1"},"message":{"content":[{"type":"tool_result","tool_use_id":"auto-1","content":"moved"}]}}
{"type":"user","toolUseResult":{"taskId":"m1"},"message":{"content":[{"type":"tool_result","tool_use_id":"mon-1","content":"watching"}]}}
"""
let asyncSummary = LocalSessions.summarizeTranscriptTail(Data(asyncJSON.utf8), droppingPartialFirstLine: false)
expectEqual(asyncSummary.backgroundTasks, 3, "트랜스크립트: 비동기 에이전트·뒤로 넘긴 셸·모니터도 백그라운드 작업")

let queuedJSON = asyncJSON + "\n" + """
{"type":"queue-operation","operation":"enqueue","content":"<task-notification>\\n<task-id>a1</task-id>\\n<status>completed</status>\\n</task-notification>"}
{"type":"attachment","attachment":{"type":"queued_command","prompt":"<task-notification>\\n<task-id>b1</task-id>\\n<status>completed</status>\\n</task-notification>"}}
"""
let queuedSummary = LocalSessions.summarizeTranscriptTail(Data(queuedJSON.utf8), droppingPartialFirstLine: false)
expectEqual(queuedSummary.backgroundTasks, 1, "트랜스크립트: 턴 도중 대기열에 들어온 완료 알림도 task-id 로 뺀다")

let stoppedJSON = queuedJSON + "\n" + """
{"type":"user","toolUseResult":{"task_id":"m1","task_type":"monitor"},"message":{"content":[{"type":"tool_result","tool_use_id":"stop-1","content":"stopped"}]}}
"""
let stoppedSummary = LocalSessions.summarizeTranscriptTail(Data(stoppedJSON.utf8), droppingPartialFirstLine: false)
expectEqual(stoppedSummary.backgroundTasks, 0, "트랜스크립트: TaskStop 으로 멈춘 작업은 뺀다")

let monitorEventJSON = asyncJSON + "\n" + """
{"type":"queue-operation","operation":"enqueue","content":"<task-notification>\\n<task-id>m1</task-id>\\n<summary>Monitor event: build</summary>\\n</task-notification>"}
{"type":"user","message":{"content":"<task-notification>\\n<task-id>m1</task-id>\\n<summary>Monitor event: build</summary>\\n</task-notification>"}}
"""
let monitorEventSummary = LocalSessions.summarizeTranscriptTail(Data(monitorEventJSON.utf8), droppingPartialFirstLine: false)
expectEqual(monitorEventSummary.backgroundTasks, 3, "트랜스크립트: status 가 없는 모니터 이벤트 알림은 완료로 세지 않는다")

let monitorEndedJSON = monitorEventJSON + "\n" + """
{"type":"user","message":{"content":"<task-notification>\\n<task-id>m1</task-id>\\n<status>completed</status>\\n</task-notification>"}}
"""
let monitorEndedSummary = LocalSessions.summarizeTranscriptTail(Data(monitorEndedJSON.utf8), droppingPartialFirstLine: false)
expectEqual(monitorEndedSummary.backgroundTasks, 2, "트랜스크립트: 모니터 종료 알림이 오면 user 행의 task-id 로 뺀다")

let foreignTaskJSON = """
{"type":"assistant","message":{"content":[{"type":"tool_use","id":"other-1","name":"TaskCreate","input":{}}]}}
{"type":"user","toolUseResult":{"taskId":"t1"},"message":{"content":[{"type":"tool_result","tool_use_id":"other-1","content":"created"}]}}
"""
expectEqual(
    LocalSessions.summarizeTranscriptTail(Data(foreignTaskJSON.utf8), droppingPartialFirstLine: false).backgroundTasks,
    0,
    "트랜스크립트: Monitor 가 아닌 도구의 taskId 는 백그라운드 작업이 아니다"
)

let otherTagJSON = asyncJSON + "\n" + """
{"type":"queue-operation","operation":"enqueue","content":"<task-id>a1</task-id> 알림이 아닌 안내"}
"""
expectEqual(
    LocalSessions.summarizeTranscriptTail(Data(otherTagJSON.utf8), droppingPartialFirstLine: false).backgroundTasks,
    3,
    "트랜스크립트: 알림 블록 밖의 task-id 는 완료로 세지 않는다"
)

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

let noStops = PulseGlyph.stops(counts: GroupedSessions.Counts())
expect(noStops.isEmpty, "파형 색: 세션이 없으면 정지점 없음")
let oneStop = PulseGlyph.stops(counts: GroupedSessions.Counts(working: 3))
expectEqual(oneStop.map(\.group), [1], "파형 색: 한 그룹이면 그 그룹 하나")
expectEqual(oneStop.map(\.location), [0.5], "파형 색: 한 그룹은 가운데")
let threeStops = PulseGlyph.stops(counts: GroupedSessions.Counts(attention: 1, working: 2, done: 1))
expectEqual(threeStops.map(\.group), [0, 1, 2], "파형 색: 확인·진행·완료 순서")
expectEqual(threeStops.map(\.location), [0.125, 0.5, 0.875], "파형 색: 각 구간의 가운데")
let gapStops = PulseGlyph.stops(counts: GroupedSessions.Counts(attention: 1, done: 1))
expectEqual(gapStops.map(\.group), [0, 2], "파형 색: 빈 그룹은 건너뜀")
expectEqual(gapStops.map(\.location), [0.25, 0.75], "파형 색: 빈 그룹은 구간을 차지하지 않음")

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

// MARK: - 검색

let searchItem = DisplayItem(
    session: Session(
        sessionId: "search",
        bucket: "working",
        title: "결제 API 리팩터링",
        key: "API-120",
        since: now.addingTimeInterval(-120),
        place: Place(label: "web-dashboard", branch: "feature/checkout"),
        cwd: "/Users/dev/projects/api-server",
        orcaTerminal: "term-search",
        pr: PullRequestLink(number: 42, url: "https://example.com/pr/42", label: "#42"),
        extraPRs: [PullRequestLink(number: 43, url: "https://example.com/pr/43", label: "hotfix-43")],
        jiraKey: "PROJ-120",
        jiraHref: "https://example.com/PROJ-120"
    ),
    group: .working,
    now: now
)
expect(SessionSearch.matches(searchItem, query: "결제"), "검색: 제목 일치")
expect(SessionSearch.matches(searchItem, query: "web-dashboard"), "검색: 워크트리 일치")
expect(SessionSearch.matches(searchItem, query: "api-server"), "검색: cwd 마지막 요소 일치")
expect(!SessionSearch.matches(searchItem, query: "projects"), "검색: cwd 중간 요소는 보지 않는다")
expect(SessionSearch.matches(searchItem, query: "api-120"), "검색: 키 일치, 대소문자 무시")
expect(SessionSearch.matches(searchItem, query: "WEB"), "검색: 대소문자 무시")
expect(SessionSearch.matches(searchItem, query: "proj-120"), "검색: 지라 키 일치")
expect(SessionSearch.matches(searchItem, query: "#42"), "검색: PR 태그 일치")
expect(SessionSearch.matches(searchItem, query: "hotfix"), "검색: 추가 PR 라벨 일치")
expect(SessionSearch.matches(searchItem, query: "결제 api"), "검색: 두 낱말이 모두 있으면 일치")
expect(!SessionSearch.matches(searchItem, query: "결제 없는낱말"), "검색: 한 낱말이라도 없으면 불일치")
expect(SessionSearch.matches(searchItem, query: ""), "검색: 빈 검색어는 모두 일치")
expect(SessionSearch.matches(searchItem, query: "   "), "검색: 공백만 있는 검색어는 모두 일치")

let searchGrouped = Grouping.group(
    SessionsResponse(sessions: [
        Session(sessionId: "checkout", bucket: "working", title: "결제 화면",
                since: now.addingTimeInterval(-60), orcaTerminal: "t1"),
        Session(sessionId: "billing", bucket: "done", title: "정산 배치",
                since: now.addingTimeInterval(-120), orcaTerminal: "t2"),
        Session(sessionId: "unrelated", bucket: "working", title: "문서 정리",
                since: now.addingTimeInterval(-180), orcaTerminal: "t3"),
    ]),
    now: now
)
let searchSections = SessionFilter.all.sections(in: searchGrouped, query: "결제")
expectEqual(searchSections.flatMap { $0.items.map(\.sessionId) }, ["checkout"], "검색: 일치하는 행만 남는다")
expectEqual(searchSections.map(\.group), [.working], "검색: 일치가 없는 섹션은 빼 둔다")
expectEqual(SessionFilter.all.selectableItems(in: searchGrouped, query: "결제").map(\.sessionId), ["checkout"],
            "검색: 키 이동 대상도 화면과 같은 목록")
expect(SessionFilter.done.sections(in: searchGrouped, query: "결제").isEmpty,
       "검색: 칩 필터 밖은 찾지 않는다")
expectEqual(SessionFilter.done.sections(in: manyDone, query: "done6").first?.items.map(\.sessionId), ["done6"],
            "검색: 화면에 잘린 뒤쪽 항목도 찾는다")
expectEqual(SessionFilter.done.sections(in: manyDone, query: "done").first?.items.count, 7,
            "검색: 완료도 5개로 자르지 않는다")

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
expectEqual(KeyboardSelection.edge(up: true, count: 3), 0, "키보드: 처음으로는 첫 행")
expectEqual(KeyboardSelection.edge(up: false, count: 3), 2, "키보드: 끝으로는 마지막 행")
expectEqual(KeyboardSelection.edge(up: true, count: 0), nil, "키보드: 끝 이동도 행이 없으면 없음")

// MARK: - 단계 펼침 키

expect(StepDisclosure.collapsed < .window && StepDisclosure.window < .full, "단계 펼침: 접힘 < 세 단계 < 전체")
expectEqual(StepDisclosure.next(from: .collapsed, by: 1, toEnd: false, canShowFull: true), .window,
            "단계 펼침: 접힘에서 → 는 세 단계")
expectEqual(StepDisclosure.next(from: .collapsed, by: 1, toEnd: true, canShowFull: true), .full,
            "단계 펼침: 접힘에서 ⌥→ 는 전체")
expectEqual(StepDisclosure.next(from: .collapsed, by: -1, toEnd: false, canShowFull: true), .collapsed,
            "단계 펼침: 접힘에서 ← 는 그대로")
expectEqual(StepDisclosure.next(from: .collapsed, by: -1, toEnd: true, canShowFull: true), .collapsed,
            "단계 펼침: 접힘에서 ⌥← 는 그대로")
expectEqual(StepDisclosure.next(from: .window, by: 1, toEnd: false, canShowFull: true), .full,
            "단계 펼침: 세 단계에서 → 는 전체")
expectEqual(StepDisclosure.next(from: .window, by: 1, toEnd: true, canShowFull: true), .full,
            "단계 펼침: 세 단계에서 ⌥→ 는 전체")
expectEqual(StepDisclosure.next(from: .window, by: -1, toEnd: false, canShowFull: true), .collapsed,
            "단계 펼침: 세 단계에서 ← 는 접힘")
expectEqual(StepDisclosure.next(from: .window, by: -1, toEnd: true, canShowFull: true), .collapsed,
            "단계 펼침: 세 단계에서 ⌥← 는 접힘")
expectEqual(StepDisclosure.next(from: .full, by: 1, toEnd: false, canShowFull: true), .full,
            "단계 펼침: 전체에서 → 는 그대로")
expectEqual(StepDisclosure.next(from: .full, by: 1, toEnd: true, canShowFull: true), .full,
            "단계 펼침: 전체에서 ⌥→ 는 그대로")
expectEqual(StepDisclosure.next(from: .full, by: -1, toEnd: false, canShowFull: true), .window,
            "단계 펼침: 전체에서 ← 는 세 단계")
expectEqual(StepDisclosure.next(from: .full, by: -1, toEnd: true, canShowFull: true), .collapsed,
            "단계 펼침: 전체에서 ⌥← 는 접힘")
expectEqual(StepDisclosure.next(from: .window, by: 1, toEnd: false, canShowFull: false), .window,
            "단계 펼침: 전체 단계가 없으면 세 단계에서 → 는 그대로")
expectEqual(StepDisclosure.next(from: .window, by: 1, toEnd: true, canShowFull: false), .window,
            "단계 펼침: 전체 단계가 없으면 세 단계에서 ⌥→ 도 그대로")
expectEqual(StepDisclosure.next(from: .collapsed, by: 1, toEnd: false, canShowFull: false), .window,
            "단계 펼침: 전체 단계가 없으면 접힘에서 → 는 세 단계")
expectEqual(StepDisclosure.next(from: .collapsed, by: 1, toEnd: true, canShowFull: false), .window,
            "단계 펼침: 전체 단계가 없으면 접힘에서 ⌥→ 는 세 단계")

// MARK: - 단계 줄

let stepLineGrouped = Grouping.group(
    SessionsResponse(sessions: [
        Session(sessionId: "working", bucket: "working", dataPath: "/tmp/a.json",
                counts: SessionCounts(done: 1, left: 1, now: 1), total: 3,
                stepStates: ["done", "now", "left"]),
        Session(sessionId: "workingNoData", bucket: "working",
                counts: SessionCounts(done: 1, left: 1, now: 1), total: 3,
                stepStates: ["done", "now", "left"]),
        Session(sessionId: "wait", bucket: "wait", dataPath: "/tmp/a.json",
                counts: SessionCounts(done: 1, left: 1, now: 1), total: 3,
                stepStates: ["done", "now", "left"]),
        Session(sessionId: "done", bucket: "done", since: now, dataPath: "/tmp/a.json",
                counts: SessionCounts(done: 3), total: 3,
                stepStates: ["done", "done", "done"]),
    ]),
    now: now
)
expectEqual(stepLineGrouped.working.first { $0.sessionId == "working" }?.showsStepLine, true,
            "단계 줄: 진행 중이고 데이터 파일이 있으면 펼칠 수 있다")
expectEqual(stepLineGrouped.working.first { $0.sessionId == "workingNoData" }?.showsStepLine, false,
            "단계 줄: 데이터 파일이 없으면 펼칠 수 없다")
expectEqual(stepLineGrouped.attention.first { $0.sessionId == "wait" }?.showsStepLine, false,
            "단계 줄: 확인 필요 행은 펼칠 수 없다")
expectEqual(stepLineGrouped.done.first { $0.sessionId == "done" }?.showsStepLine, false,
            "단계 줄: 체크리스트를 다 끝낸 완료 행은 펼칠 수 없다")

let unfinishedDoneGrouped = Grouping.group(
    SessionsResponse(sessions: [
        Session(sessionId: "doneUnfinished", bucket: "done", since: now, dataPath: "/tmp/b.json",
                counts: SessionCounts(done: 8, left: 0, now: 0, blocked: 1), total: 9,
                stepStates: ["done", "done", "done", "done", "done", "done", "done", "done", "blocked"]),
        Session(sessionId: "doneUnfinishedNoData", bucket: "done", since: now,
                counts: SessionCounts(done: 1, left: 1), total: 2,
                stepStates: ["done", "left"]),
        Session(sessionId: "doneNoChecklist", bucket: "done", since: now, dataPath: "/tmp/c.json"),
    ]),
    now: now
)
let doneUnfinished = unfinishedDoneGrouped.done.first { $0.sessionId == "doneUnfinished" }
expectEqual(doneUnfinished?.hasUnfinishedChecklist, true, "완료 행: 9단계 중 8단계면 체크리스트가 남아 있다")
expectEqual(doneUnfinished?.showsStepLine, true, "단계 줄: 체크리스트가 남은 완료 행은 펼칠 수 있다")
expectEqual(unfinishedDoneGrouped.done.first { $0.sessionId == "doneUnfinishedNoData" }?.showsStepLine, false,
            "단계 줄: 체크리스트가 남아도 데이터 파일이 없는 완료 행은 펼칠 수 없다")
expectEqual(unfinishedDoneGrouped.done.first { $0.sessionId == "doneNoChecklist" }?.hasUnfinishedChecklist, false,
            "완료 행: 체크리스트가 없으면 남은 단계도 없다")
expectEqual(stepLineGrouped.done.first { $0.sessionId == "done" }?.hasUnfinishedChecklist, false,
            "완료 행: 모든 단계를 끝냈으면 남은 단계가 없다")

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
expectEqual(AppSettings.default.attentionAlert, .cardAndSound, "설정: 기본 확인 필요 알림은 카드와 소리")
expectEqual(AppSettings.default.doneAlert, .card, "설정: 기본 끝남 알림은 카드")

let storedSettings = AppSettings(densityRaw: "compact", themeRaw: "dark", attentionAlertRaw: "cardOnly")
expectEqual(storedSettings.density, .compact, "설정: 저장된 밀도를 읽는다")
expectEqual(storedSettings.theme, .dark, "설정: 저장된 테마를 읽는다")
expectEqual(storedSettings.attentionAlert, .cardOnly, "설정: 저장된 확인 필요 알림을 읽는다")
expectEqual(storedSettings.doneAlert, .card, "설정: 끝남 알림 키가 없으면 카드")

let storedDone = AppSettings(densityRaw: nil, themeRaw: nil, doneAlertRaw: "off")
expectEqual(storedDone.doneAlert, .off, "설정: 저장된 끝남 알림을 읽는다")

expectEqual(AppSettings.densityKey, "density", "설정: 밀도 키")
expectEqual(AppSettings.themeKey, "theme", "설정: 테마 키")
expectEqual(AppSettings.attentionAlertKey, "attentionAlert", "설정: 확인 필요 알림 키")
expectEqual(AppSettings.doneAlertKey, "doneAlert", "설정: 끝남 알림 키")
expectEqual(AppSettings.attentionNotificationsKey, "attentionNotifications", "설정: 이전 확인 필요 알림 키")
expectEqual(AppSettings.doneNotificationsKey, "doneNotifications", "설정: 이전 끝남 알림 키")

let unknownSettings = AppSettings(densityRaw: "dense", themeRaw: "sepia")
expectEqual(unknownSettings, AppSettings.default, "설정: 알 수 없는 값과 없는 값은 기본값")
expectEqual(AppSettings(densityRaw: "", themeRaw: " "), AppSettings.default,
            "설정: 빈 문자열과 공백은 기본값")

expectEqual(AttentionAlert.allCases.map(\.rawValue), ["cardAndSound", "cardOnly", "off"], "설정: 확인 필요 알림 저장값")
expectEqual(DoneAlert.allCases.map(\.rawValue), ["card", "off"], "설정: 끝남 알림 저장값")
expectEqual(Density.allCases.map(\.rawValue), ["rich", "compact"], "설정: 밀도 저장값")
expectEqual(ThemePreference.allCases.map(\.rawValue), ["system", "light", "dark"], "설정: 테마 저장값")
expectEqual(AppSettings(densityRaw: "light", themeRaw: nil).density, .rich,
            "설정: 밀도 키에 테마 값이 와도 기본값")

expectEqual(AppSettings(densityRaw: nil, themeRaw: nil, legacyAttention: true).attentionAlert, .cardAndSound,
            "설정: 이전 확인 필요 알림 true 는 카드와 소리")
expectEqual(AppSettings(densityRaw: nil, themeRaw: nil, legacyAttention: false).attentionAlert, .off,
            "설정: 이전 확인 필요 알림 false 는 끔")
expectEqual(AppSettings(densityRaw: nil, themeRaw: nil, legacyDone: true).doneAlert, .card,
            "설정: 이전 끝남 알림 true 는 카드")
expectEqual(AppSettings(densityRaw: nil, themeRaw: nil, legacyDone: false).doneAlert, .off,
            "설정: 이전 끝남 알림 false 는 끔")
expectEqual(AppSettings(densityRaw: nil, themeRaw: nil, attentionAlertRaw: "cardOnly", legacyAttention: false).attentionAlert,
            .cardOnly, "설정: 새 원문이 이전 불리언보다 우선")
expectEqual(AppSettings(densityRaw: nil, themeRaw: nil, attentionAlertRaw: "bogus", legacyAttention: false).attentionAlert,
            .off, "설정: 새 원문이 알 수 없는 값이면 이전 불리언")
expectEqual(AppSettings(densityRaw: nil, themeRaw: nil, attentionAlertRaw: "bogus").attentionAlert,
            .cardAndSound, "설정: 둘 다 없으면 기본값")

expectEqual(AttentionAlert.cardAndSound.showsCard, true, "설정: 카드와 소리는 카드를 띄운다")
expectEqual(AttentionAlert.cardOnly.showsCard, true, "설정: 카드만은 카드를 띄운다")
expectEqual(AttentionAlert.off.showsCard, false, "설정: 끔은 카드를 띄우지 않는다")
expectEqual(AttentionAlert.cardAndSound.soundName, "Tink", "설정: 카드와 소리만 소리를 낸다")
expectEqual(AttentionAlert.cardOnly.soundName, nil, "설정: 카드만은 소리가 없다")
expectEqual(AttentionAlert.off.soundName, nil, "설정: 끔은 소리가 없다")
expectEqual(DoneAlert.card.showsCard, true, "설정: 끝남 카드는 카드를 띄운다")
expectEqual(DoneAlert.off.showsCard, false, "설정: 끝남 끔은 카드를 띄우지 않는다")

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
expectEqual(notifier.notes(for: noteA, popoverVisible: false, panelVisible: false, enabled: true, isFirstUpdate: true).count, 0,
            "알림: 첫 갱신은 조용히 기록만 한다")
expectEqual(notifier.notes(for: noteA, popoverVisible: false, panelVisible: false, enabled: true, isFirstUpdate: false).count, 0,
            "알림: 이미 본 항목은 알리지 않는다")

let freshNotes = notifier.notes(for: noteA + noteB, popoverVisible: false, panelVisible: false, enabled: true, isFirstUpdate: false)
expectEqual(freshNotes.count, 1, "알림: 새 항목만 알린다")
expectEqual(freshNotes.first?.sessionId, "attn-b", "알림: sessionId")
expectEqual(freshNotes.first?.identifier, "attn-b", "알림: 식별자는 sessionId")
expectEqual(freshNotes.first?.title, "확인이 필요해요 · attn-b", "알림: 제목")
expectEqual(freshNotes.first?.body, "권한 승인을 기다려요", "알림: 답이 없으면 상태 문구")
expectEqual(notifier.notes(for: noteA + noteB, popoverVisible: false, panelVisible: false, enabled: true, isFirstUpdate: false).count, 0,
            "알림: 같은 키는 다시 알리지 않는다")
expectEqual(notifier.notes(for: noteAReborn, popoverVisible: false, panelVisible: false, enabled: true, isFirstUpdate: false).count, 1,
            "알림: since 가 바뀌면 새 항목이다")

expectEqual(AttentionNotifier.body(summary: "요약 문장", status: "상태"),
            "요약 문장", "알림: 본문은 요약이 먼저")
expectEqual(AttentionNotifier.body(summary: "   ", status: "상태"), "상태",
            "알림: 요약이 비면 상태 문구")
expectEqual(AttentionNotifier.body(summary: nil, status: String(repeating: "가", count: 300)),
            String(repeating: "가", count: 89) + "…", "알림: 긴 상태 문구는 90자로 자른다")
expectEqual(AttentionNotifier.body(summary: nil, status: String(repeating: "가", count: 300)).count, 90,
            "알림: 자른 본문은 90자")

var popoverNotifier = AttentionNotifier()
_ = popoverNotifier.notes(for: noteA, popoverVisible: false, panelVisible: false, enabled: true, isFirstUpdate: true)
expectEqual(popoverNotifier.notes(for: noteA + noteB, popoverVisible: true, panelVisible: false, enabled: true, isFirstUpdate: false).count,
            0, "알림: 팝오버가 열려 있으면 알리지 않는다")
expectEqual(popoverNotifier.notes(for: noteB, popoverVisible: false, panelVisible: false, enabled: true, isFirstUpdate: false).count,
            0, "알림: 열려 있는 동안 본 항목은 나중에도 알리지 않는다")

var offNotifier = AttentionNotifier()
_ = offNotifier.notes(for: [], popoverVisible: false, panelVisible: false, enabled: false, isFirstUpdate: true)
expectEqual(offNotifier.notes(for: noteA, popoverVisible: false, panelVisible: false, enabled: false, isFirstUpdate: false).count,
            0, "알림: 설정이 꺼져 있으면 알리지 않는다")
expectEqual(offNotifier.notes(for: noteA, popoverVisible: false, panelVisible: false, enabled: true, isFirstUpdate: false).count,
            0, "알림: 꺼져 있는 동안 본 항목은 켠 뒤에도 알리지 않는다")

var pruneNotifier = AttentionNotifier()
_ = pruneNotifier.notes(for: [], popoverVisible: false, panelVisible: false, enabled: true, isFirstUpdate: true)
expectEqual(pruneNotifier.notes(for: noteA, popoverVisible: false, panelVisible: false, enabled: true, isFirstUpdate: false).count, 1,
            "알림: 새 항목을 알린다")
_ = pruneNotifier.notes(for: [], popoverVisible: false, panelVisible: false, enabled: true, isFirstUpdate: false)
expectEqual(pruneNotifier.notes(for: noteA, popoverVisible: false, panelVisible: false, enabled: true, isFirstUpdate: false).count, 1,
            "알림: 응답에서 빠진 키는 지워 다시 새 항목이 된다")

var batchNotifier = AttentionNotifier()
let firstBatch = batchNotifier.evaluate(
    for: noteA,
    popoverVisible: false,
    panelVisible: false,
    enabled: true,
    isFirstUpdate: true
)
expectEqual(firstBatch.candidates, 1, "알림 후보: 첫 갱신에도 후보 수는 센다")
expectEqual(firstBatch.notes.count, 0, "알림 후보: 첫 갱신은 보내지 않는다")
expectEqual(firstBatch.suppression, NotificationSuppression.firstUpdate, "알림 후보: 억제 사유는 첫 갱신")
let openBatch = batchNotifier.evaluate(for: noteA + noteB, popoverVisible: true, panelVisible: false, enabled: true, isFirstUpdate: false)
expectEqual(openBatch.suppression, NotificationSuppression.popoverVisible, "알림 후보: 억제 사유는 팝오버 열림")
let offBatch = batchNotifier.evaluate(for: noteB, popoverVisible: false, panelVisible: false, enabled: false, isFirstUpdate: false)
expectEqual(offBatch.suppression, NotificationSuppression.disabled, "알림 후보: 억제 사유는 설정 꺼짐")
let sentBatch = batchNotifier.evaluate(for: noteA + noteB, popoverVisible: false, panelVisible: false, enabled: true, isFirstUpdate: false)
expectEqual(sentBatch.suppression, nil, "알림 후보: 보낼 때는 억제 사유가 없다")
expectEqual(sentBatch.notes.count, 1, "알림 후보: 새 항목 하나를 보낸다")

expectEqual(NotificationPermission.authorized.isAuthorized, true, "권한: 허용")
expectEqual(NotificationPermission.denied.isAuthorized, false, "권한: 거부")
expectEqual(NotificationPermission.notDetermined.isAuthorized, false, "권한: 아직 묻지 않음")
expectEqual(NotificationPermission.unknown.isAuthorized, false, "권한: 모름")

// MARK: - 완료 알림

let doneWorkItem = Grouping.group(
    SessionsResponse(sessions: [session("done-a", "working", minutesAgo: 4)]),
    now: now
).working
let doneDoneItem = Grouping.group(
    SessionsResponse(sessions: [session("done-a", "done", minutesAgo: 1, replySummary: "마무리했습니다")]),
    now: now
).done
let doneStatusItem = Grouping.group(
    SessionsResponse(sessions: [session("done-b", "done", minutesAgo: 1)]),
    now: now
).done
let doneWorkB = Grouping.group(
    SessionsResponse(sessions: [session("done-b", "working", minutesAgo: 4)]),
    now: now
).working
let doneStallItem = Grouping.group(
    SessionsResponse(sessions: [session("done-s", "stall", minutesAgo: 9)]),
    now: now
).attention

func doneNotes(
    _ notifier: inout DoneNotifier,
    done: [DisplayItem],
    working: [DisplayItem] = [],
    attention: [DisplayItem] = [],
    popoverVisible: Bool = false,
    panelVisible: Bool = false,
    enabled: Bool = true,
    isFirstUpdate: Bool = false
) -> [AttentionNote] {
    notifier.notes(
        done: done,
        working: working,
        attention: attention,
        popoverVisible: popoverVisible,
        panelVisible: panelVisible,
        enabled: enabled,
        isFirstUpdate: isFirstUpdate
    )
}

var doneNotifier = DoneNotifier()
expectEqual(doneNotes(&doneNotifier, done: doneDoneItem, isFirstUpdate: true).count, 0,
            "완료 알림: 첫 갱신에 이미 완료면 알리지 않는다")
expectEqual(doneNotes(&doneNotifier, done: doneDoneItem, isFirstUpdate: false).count, 0,
            "완료 알림: 첫 갱신에 이미 완료였던 세션은 나중에도 알리지 않는다")
_ = doneNotes(&doneNotifier, done: [], working: doneWorkItem)
let transitioned = doneNotes(&doneNotifier, done: doneDoneItem)
expectEqual(transitioned.count, 1, "완료 알림: 진행 중에서 완료로 바뀌면 알린다")
expectEqual(transitioned.first?.title, "끝났어요 · done-a", "완료 알림: 제목")
expectEqual(transitioned.first?.body, "마무리했습니다", "완료 알림: 본문은 요약 한 줄")
expectEqual(transitioned.first?.identifier, "done-a", "완료 알림: 식별자는 sessionId")
expectEqual(transitioned.first?.sessionId, "done-a", "완료 알림: sessionId")
expectEqual(doneNotes(&doneNotifier, done: doneDoneItem).count, 0, "완료 알림: 같은 키는 다시 알리지 않는다")

var doneStatusNotifier = DoneNotifier()
_ = doneNotes(&doneStatusNotifier, done: [], working: doneWorkB)
let statusOnly = doneNotes(&doneStatusNotifier, done: doneStatusItem)
expectEqual(statusOnly.count, 1, "완료 알림: 답이 없어도 알린다")
expectEqual(statusOnly.first?.body, doneStatusItem[0].status, "완료 알림: 답이 없으면 상태 문구")

var doneStallNotifier = DoneNotifier()
_ = doneNotes(&doneStallNotifier, done: [], attention: doneStallItem)
let stallDone = Grouping.group(
    SessionsResponse(sessions: [session("done-s", "done", minutesAgo: 1)]),
    now: now
).done
expectEqual(doneNotes(&doneStallNotifier, done: stallDone).count, 1, "완료 알림: stall 에서 완료로 바뀌어도 알린다")

var doneIdleNotifier = DoneNotifier()
_ = doneNotes(&doneIdleNotifier, done: [], attention: noteA)
let idleToDone = Grouping.group(
    SessionsResponse(sessions: [session("attn-a", "done", minutesAgo: 1)]),
    now: now
).done
expectEqual(doneNotes(&doneIdleNotifier, done: idleToDone).count, 0,
            "완료 알림: 진행 중을 거치지 않은 세션은 알리지 않는다")

var doneFreshNotifier = DoneNotifier()
expectEqual(doneNotes(&doneFreshNotifier, done: doneDoneItem).count, 0,
            "완료 알림: 처음부터 완료로 보인 세션은 알리지 않는다")

var doneFirstNotifier = DoneNotifier()
_ = doneNotes(&doneFirstNotifier, done: [], working: doneWorkItem)
let firstUpdateBatch = doneFirstNotifier.evaluate(
    done: doneDoneItem, working: [], attention: [],
    popoverVisible: false, panelVisible: false, enabled: true, isFirstUpdate: true
)
expectEqual(firstUpdateBatch.candidates, 1, "완료 알림 후보: 첫 갱신에도 후보 수는 센다")
expectEqual(firstUpdateBatch.suppression, NotificationSuppression.firstUpdate, "완료 알림 후보: 억제 사유는 첫 갱신")
expectEqual(firstUpdateBatch.notes.count, 0, "완료 알림: 첫 갱신에는 보내지 않는다")
expectEqual(doneNotes(&doneFirstNotifier, done: doneDoneItem).count, 0,
            "완료 알림: 첫 갱신에 본 완료는 나중에도 알리지 않는다")
let doneFirstBatch = doneFirstNotifier.evaluate(
    done: doneDoneItem, working: [], attention: [],
    popoverVisible: false, panelVisible: false, enabled: true, isFirstUpdate: false
)
expectEqual(doneFirstBatch.suppression, nil, "완료 알림: 기록된 항목은 후보가 아니다")
expectEqual(doneFirstBatch.candidates, 0, "완료 알림: 기록된 항목은 후보 수에도 없다")

var donePopoverNotifier = DoneNotifier()
_ = doneNotes(&donePopoverNotifier, done: [], working: doneWorkItem)
expectEqual(doneNotes(&donePopoverNotifier, done: doneDoneItem, popoverVisible: true).count, 0,
            "완료 알림: 팝오버가 열려 있으면 보내지 않는다")
expectEqual(doneNotes(&donePopoverNotifier, done: doneDoneItem).count, 0,
            "완료 알림: 열려 있는 동안 본 완료는 나중에도 알리지 않는다")

var doneOffNotifier = DoneNotifier()
_ = doneNotes(&doneOffNotifier, done: [], working: doneWorkItem)
expectEqual(doneNotes(&doneOffNotifier, done: doneDoneItem, enabled: false).count, 0,
            "완료 알림: 설정이 꺼져 있으면 보내지 않는다")
expectEqual(doneNotes(&doneOffNotifier, done: doneDoneItem).count, 0,
            "완료 알림: 꺼져 있는 동안 본 완료는 켠 뒤에도 알리지 않는다")

var doneSuppressNotifier = DoneNotifier()
_ = doneNotes(&doneSuppressNotifier, done: [], working: doneWorkItem)
let disabledBatch = doneSuppressNotifier.evaluate(
    done: doneDoneItem, working: [], attention: [],
    popoverVisible: false, panelVisible: false, enabled: false, isFirstUpdate: false
)
expectEqual(disabledBatch.candidates, 1, "완료 알림 후보: 후보 수")
expectEqual(disabledBatch.suppression, NotificationSuppression.disabled, "완료 알림 후보: 억제 사유")
expectEqual(disabledBatch.notes.count, 0, "완료 알림 후보: 보내지 않음")

// MARK: - 패널이 떠 있을 때 알림

var panelNotifier = AttentionNotifier()
_ = panelNotifier.evaluate(for: [], popoverVisible: false, panelVisible: false, enabled: true, isFirstUpdate: true)
let panelBatch = panelNotifier.evaluate(
    for: noteA, popoverVisible: false, panelVisible: true, enabled: true, isFirstUpdate: false
)
expectEqual(panelBatch.notes.count, 0, "알림: 플로팅 패널이 떠 있으면 알리지 않는다")
expectEqual(panelBatch.suppression, NotificationSuppression.panelVisible, "알림: 억제 사유는 패널 표시 중")
expectEqual(panelBatch.candidates, 1, "알림: 패널이 떠 있어도 후보 수는 센다")
expectEqual(panelNotifier.notes(for: noteA, popoverVisible: false, panelVisible: false, enabled: true, isFirstUpdate: false).count,
            0, "알림: 패널이 떠 있는 동안 들어온 항목은 닫힌 뒤에도 알리지 않는다")

var bothVisibleNotifier = AttentionNotifier()
_ = bothVisibleNotifier.evaluate(for: [], popoverVisible: false, panelVisible: false, enabled: true, isFirstUpdate: true)
let bothVisibleBatch = bothVisibleNotifier.evaluate(
    for: noteA, popoverVisible: true, panelVisible: true, enabled: true, isFirstUpdate: false
)
expectEqual(bothVisibleBatch.suppression, NotificationSuppression.popoverVisible,
            "알림: 팝오버와 패널이 모두 떠 있으면 팝오버가 먼저다")

var donePanelNotifier = DoneNotifier()
_ = doneNotes(&donePanelNotifier, done: [], working: doneWorkItem)
let donePanelBatch = donePanelNotifier.evaluate(
    done: doneDoneItem, working: [], attention: [],
    popoverVisible: false, panelVisible: true, enabled: true, isFirstUpdate: false
)
expectEqual(donePanelBatch.notes.count, 0, "완료 알림: 플로팅 패널이 떠 있으면 보내지 않는다")
expectEqual(donePanelBatch.suppression, NotificationSuppression.panelVisible, "완료 알림: 억제 사유는 패널 표시 중")

// MARK: - 알림 식별자와 버튼

let stallAlertItem = Grouping.group(
    SessionsResponse(sessions: [session("stall-note", "stall", minutesAgo: 7)]),
    now: now
).attention
let stallNote = AttentionNotifier.note(for: stallAlertItem[0])
expectEqual(stallNote.identifier, "stall-note", "알림: stall 식별자는 sessionId")
expectEqual(stallNote.snoozable, true, "알림: stall 막힘에는 10분 더를 단다")
let plainNote = AttentionNotifier.note(for: noteB[0])
expectEqual(plainNote.identifier, "attn-b", "알림: 식별자는 세션마다 하나")
expectEqual(plainNote.snoozable, false, "알림: stall 이 아닌 막힘에는 10분 더를 달지 않는다")
let doneNote = DoneNotifier.note(for: doneDoneItem[0])
expectEqual(doneNote.identifier, "done-a", "완료 알림: 식별자는 sessionId")
expectEqual(doneNote.snoozable, false, "완료 알림: 10분 더를 달지 않는다")

// MARK: - 알림 스타일

let snoozableStyle = NotificationStyle.of(kind: .attention, snoozable: true)
expectEqual(snoozableStyle.categoryIdentifier, "ATTENTION", "알림 스타일: stall 막힘 카테고리")
expectEqual(snoozableStyle.buttons, [.openInOrca, .snooze], "알림 스타일: stall 막힘 버튼")
expectEqual(snoozableStyle.interruption, .active, "알림 스타일: 막힘은 active")
expectEqual(snoozableStyle.playsSound, true, "알림 스타일: 막힘은 소리를 낸다")

let plainStyle = NotificationStyle.of(kind: .attention, snoozable: false)
expectEqual(plainStyle.categoryIdentifier, "ATTENTION_OPEN", "알림 스타일: 그 밖 막힘 카테고리")
expectEqual(plainStyle.buttons, [.openInOrca], "알림 스타일: 그 밖 막힘 버튼")
expectEqual(plainStyle.interruption, .active, "알림 스타일: 그 밖 막힘도 active")
expectEqual(plainStyle.playsSound, true, "알림 스타일: 그 밖 막힘도 소리를 낸다")

let doneStyle = NotificationStyle.of(kind: .done, snoozable: true)
expectEqual(doneStyle.categoryIdentifier, "DONE", "알림 스타일: 완료 카테고리")
expectEqual(doneStyle.buttons, [.acknowledge], "알림 스타일: 완료 버튼")
expectEqual(doneStyle.interruption, .passive, "알림 스타일: 완료는 passive")
expectEqual(doneStyle.playsSound, false, "알림 스타일: 완료는 무음")

let categoryIds = NotificationStyle.allCategories.map(\.categoryIdentifier)
expectEqual(categoryIds.sorted(), ["ATTENTION", "ATTENTION_OPEN", "DONE"], "알림 스타일: 카테고리 셋")
expectEqual(Set(categoryIds).count, categoryIds.count, "알림 스타일: 카테고리 identifier 는 겹치지 않는다")
expect(!NotificationStyle.allCategories.flatMap(\.buttons).contains { $0.rawValue == "LATER" },
       "알림 스타일: 「나중에」 버튼은 없다")
expectEqual(NotificationButton.snooze.title, "10분 더", "알림 스타일: 10분 더 제목")
expectEqual(NotificationButton.acknowledge.title, "확인", "알림 스타일: 확인 제목")
expectEqual(NotificationButton.openInOrca.title, "Orca 에서 열기", "알림 스타일: Orca 열기 제목")
expectEqual(NotificationButton.openInOrca.bringsAppForward, true, "알림 스타일: Orca 열기만 앱을 앞으로")
expectEqual(NotificationButton.snooze.bringsAppForward, false, "알림 스타일: 10분 더는 앱을 앞으로 가져오지 않는다")
expectEqual(NotificationButton.acknowledge.bringsAppForward, false, "알림 스타일: 확인은 앱을 앞으로 가져오지 않는다")

// MARK: - 알림이 거둬지는 키

let notifiedGroups = Grouping.group(
    SessionsResponse(sessions: [
        session("keep-a", "idle", minutesAgo: 3),
        session("keep-done", "done", minutesAgo: 1),
    ]),
    now: now
)
expectEqual(Set((notifiedGroups.attention + notifiedGroups.done).map(\.acknowledgeKey)).count, 2,
            "알림 키: 확인 필요와 완료를 함께 지킨다")
let acknowledgedNotified = Grouping.group(
    SessionsResponse(sessions: [session("keep-done", "done", minutesAgo: 1)]),
    now: now,
    acknowledgedDone: [DisplayItem.acknowledgeKey(sessionId: "keep-done", since: notifiedGroups.done[0].sortDate)]
)
expectEqual(acknowledgedNotified.done.count, 0, "알림 키: 확인한 완료는 키 집합에서 빠진다")
expectEqual(notifiedGroups.allItems.count, 2, "알림 키: 전체 항목에서 알림의 세션을 찾는다")

// MARK: - 전역 단축키

expectEqual(HotKeyRouting.action(popoverOpen: false, panelVisible: false, panelKey: false), .openPopover,
            "단축키: 팝오버와 패널이 모두 닫혀 있으면 팝오버를 연다")
expectEqual(HotKeyRouting.action(popoverOpen: false, panelVisible: true, panelKey: false), .focusPanel,
            "단축키: 패널만 떠 있고 키 창이 아니면 패널에 포커스를 준다")
expectEqual(HotKeyRouting.action(popoverOpen: false, panelVisible: true, panelKey: true), .hidePanel,
            "단축키: 패널이 키 창이면 패널을 숨긴다")
expectEqual(HotKeyRouting.action(popoverOpen: true, panelVisible: false, panelKey: false), .closePopoverAndShowPanel,
            "단축키: 팝오버가 열려 있으면 닫고 플로팅 패널을 띄운다")
expectEqual(HotKeyRouting.action(popoverOpen: true, panelVisible: true, panelKey: false), .closePopoverAndFocusPanel,
            "단축키: 팝오버가 열려 있고 패널이 떠 있으면 닫고 패널에 포커스를 준다")
expectEqual(HotKeyRouting.action(popoverOpen: true, panelVisible: true, panelKey: true), .closePopoverAndFocusPanel,
            "단축키: 팝오버가 열려 있으면 패널의 키 창 여부와 상관없이 닫고 포커스를 준다")

// MARK: - 머리글 뱃지

expectEqual(HeaderBadge.tone(for: .attention, count: 0), .muted, "머리글 뱃지: 빈 확인 필요는 흐리게")
expectEqual(HeaderBadge.tone(for: .attention, count: 2), .attention, "머리글 뱃지: 확인 필요")
expectEqual(HeaderBadge.tone(for: .working, count: 0), .working, "머리글 뱃지: 빈 진행 중도 그룹 색")
expectEqual(HeaderBadge.label(for: .attention, count: 1), "확인 1", "머리글 뱃지: 확인 라벨")
expectEqual(HeaderBadge.label(for: .working, count: 4), "진행 4", "머리글 뱃지: 진행 라벨")
expectEqual(HeaderBadge.label(for: .done, count: 3), "완료 3", "머리글 뱃지: 완료 라벨")

// MARK: - 스텝퍼

let stepperCounts = SessionCounts(done: 4, left: 4, now: 1)
expectEqual(
    Stepper.segments(counts: stepperCounts, total: 9),
    [.done, .done, .done, .done, .current, .left, .left, .left, .left],
    "스텝퍼: 완료 4 · 현재 1 · 남음 4"
)
expectEqual(
    Stepper.segments(counts: SessionCounts(done: 1, left: 1, now: 1, blocked: 1), total: 4),
    [.done, .current, .blocked, .left],
    "스텝퍼: 막힘 포함"
)
expectEqual(Stepper.segments(counts: nil, total: 9), [], "스텝퍼: 개수 없음")
expectEqual(Stepper.segments(counts: stepperCounts, total: 0), [], "스텝퍼: 전체 0")
expectEqual(
    Stepper.segments(counts: SessionCounts(done: 5, now: 3), total: 4),
    [.done, .done, .done, .done],
    "스텝퍼: 합이 전체를 넘으면 앞에서 자른다"
)
expectEqual(
    Stepper.segments(counts: SessionCounts(done: -2, left: 4, now: 3, blocked: -1), total: 4),
    [.current, .current, .current, .left],
    "스텝퍼: 음수는 0 으로 본다"
)
expectEqual(Stepper.position(counts: stepperCounts, total: 9), "5/9", "스텝퍼 위치: 완료 4 + 현재 1")
expectEqual(Stepper.position(counts: SessionCounts(done: 4, now: 0), total: 9), "4/9", "스텝퍼 위치: 현재 없음")
expectEqual(Stepper.position(counts: SessionCounts(done: 9, now: 2), total: 9), "9/9", "스텝퍼 위치: 전체에서 자른다")
expectEqual(Stepper.position(counts: nil, total: 9), nil, "스텝퍼 위치: 스텝퍼가 비면 nil")
expectEqual(
    Stepper.segments(states: ["done", "done", "blocked", "left", "left"], counts: nil, total: 5),
    [.done, .done, .blocked, .left, .left],
    "스텝퍼: 막힌 단계를 실제 위치에 그린다"
)
expectEqual(
    Stepper.segments(states: ["done", "side", "left"], counts: nil, total: 3),
    [.done, .current, .left],
    "스텝퍼: 병렬 진행도 현재로 그린다"
)
expectEqual(
    Stepper.segments(states: ["done", "now"], counts: stepperCounts, total: 4),
    Stepper.segments(counts: stepperCounts, total: 4),
    "스텝퍼: 상태 개수가 전체와 다르면 개수 기반"
)
expectEqual(
    Stepper.segments(states: nil, counts: stepperCounts, total: 9),
    Stepper.segments(counts: stepperCounts, total: 9),
    "스텝퍼: 상태가 없으면 개수 기반"
)

// MARK: - 체크리스트 단계

let checklistJSON = """
{
  "title": "제목",
  "items": [
    {"id": "a", "label": "준비", "state": "done", "sub": "완료", "doneAt": "2026-10-21T11:12:00+09:00"},
    {"id": "b", "title": "검증", "state": "now", "sub": "  "},
    {"id": "c", "label": "", "state": "weird"},
    {"id": "d", "state": "done"},
    {"state": "left"}
  ]
}
"""
let parsedSteps = Checklist.parse(Data(checklistJSON.utf8))
expectEqual(parsedSteps?.count, 5, "체크리스트: 단계 수")
expectEqual(parsedSteps?[0].label, "준비", "체크리스트: label 을 쓴다")
expectEqual(parsedSteps?[0].state, .done, "체크리스트: 완료")
expectEqual(parsedSteps?[0].sub, "완료", "체크리스트: sub")
expectEqual(parsedSteps?[0].doneAt, utcDate(2026, 10, 21, 2, 12), "체크리스트: 완료 시각")
expectEqual(parsedSteps?[1].label, "검증", "체크리스트: label 이 없으면 title")
expectEqual(parsedSteps?[1].state, .now, "체크리스트: 지금")
expectEqual(parsedSteps?[1].sub, nil, "체크리스트: 공백뿐인 sub 는 nil")
expectEqual(parsedSteps?[1].doneAt, nil, "체크리스트: 시각이 없으면 nil")
expectEqual(parsedSteps?[2].label, "c", "체크리스트: label 이 비면 id")
expectEqual(parsedSteps?[2].state, .left, "체크리스트: 알 수 없는 상태는 남음")
expectEqual(parsedSteps?[3].state, .done, "체크리스트: doneAt 없는 완료")
expectEqual(parsedSteps?[3].doneAt, nil, "체크리스트: doneAt 없는 완료는 시각이 없다")
expectEqual(parsedSteps?[4].label, "단계 5", "체크리스트: 이름이 없으면 순번")
expectEqual(Checklist.parse(Data("[]".utf8)), nil, "체크리스트: 최상위 배열은 버린다")
expectEqual(Checklist.parse(Data("not json".utf8)), nil, "체크리스트: 깨진 JSON 은 버린다")
expectEqual(Checklist.parse(Data("{\"title\":\"x\"}".utf8)), nil, "체크리스트: items 가 없으면 버린다")
let skippedItemSteps = Checklist.parse(Data("{\"items\":[1,{\"id\":\"ok\"}]}".utf8))
expectEqual(skippedItemSteps?.count, 1, "체크리스트: 객체가 아닌 항목은 건너뛴다")
expectEqual(skippedItemSteps?.first?.label, "ok", "체크리스트: 건너뛴 뒤에도 단계를 읽는다")

let sevenStates: [StepState] = [.done, .done, .done, .done, .done, .now, .left]
let sevenWindow = StepWindow.make(sevenStates)
expectEqual(sevenWindow.rows, [4, 5, 6], "단계 창: 직전 완료·지금·다음")
expectEqual(sevenWindow.hiddenBefore, 4, "단계 창: 앞에 숨은 수")
expectEqual(sevenWindow.hasHidden, true, "단계 창: 숨은 단계가 있다")
expectEqual(StepWindow.make([.now, .left, .left]).rows, [0, 1, 2], "단계 창: 첫 단계가 지금")
expectEqual(StepWindow.make(Array(repeating: StepState.done, count: 5)).rows, [2, 3, 4],
            "단계 창: 전부 완료면 끝 셋")
let twoWindow = StepWindow.make([.done, .now])
expectEqual(twoWindow.rows, [0, 1], "단계 창: 둘이면 둘 다")
expectEqual(twoWindow.hasHidden, false, "단계 창: 다 보이면 숨은 단계 없음")
let blockedLater = StepWindow.make(
    [.done, .done, .done, .now, .left, .left, .blocked, .left, .left]
)
expectEqual(blockedLater.rows, [2, 3, 6], "단계 창: 뒤쪽 막힘을 마지막 자리에 넣는다")
let blockedEarlier = StepWindow.make(
    [.blocked, .done, .done, .done, .done, .now, .left, .left, .left]
)
expectEqual(blockedEarlier.rows, [0, 5, 6], "단계 창: 앞쪽 막힘을 첫 자리에 넣는다")
expectEqual(
    StepWindow.make([.done, .done, .blocked, .now, .left]).rows,
    [2, 3, 4],
    "단계 창: 막힘이 이미 창 안이면 그대로"
)
expectEqual(
    StepWindow.make([.done, .done, .done, .done, .blocked, .left, .left]).rows,
    [3, 4, 5],
    "단계 창: 지금이 없으면 첫 막힘이 기준"
)
expectEqual(StepWindow.make([.done, .side, .left, .left]).rows, [0, 1, 2],
            "단계 창: 병렬 진행이 기준")
let emptyWindow = StepWindow.make([])
expectEqual(emptyWindow.rows, [], "단계 창: 빈 배열")
expectEqual(emptyWindow.hiddenBefore, 0, "단계 창: 빈 배열의 앞 수")
expectEqual(emptyWindow.hasHidden, false, "단계 창: 빈 배열은 숨은 단계 없음")

let seoul = TimeZone(identifier: "Asia/Seoul")!
func step(_ label: String, _ state: StepState, _ doneAt: String? = nil) -> ChecklistStep {
    ChecklistStep(label: label, state: state, doneAt: TimestampParser.parse(doneAt))
}
let headSteps = [
    step("a", .done, "2026-10-21T13:52:00+09:00"),
    step("b", .done, "2026-10-21T13:55:00+09:00"),
    step("c", .done, "2026-10-21T14:00:00+09:00"),
    step("d", .done, "2026-10-21T14:02:00+09:00"),
    step("e", .done),
    step("f", .now),
    step("g", .left),
]
let headWindow = StepWindow.make(headSteps.map(\.state))
expectEqual(
    StepWindow.headText(headSteps, window: headWindow, timeZone: seoul),
    "앞 4단계 완료 · 13:52 – 14:02",
    "단계 머리: 앞 단계 완료와 시각 범위"
)
let headNoTime = headSteps.map { ChecklistStep(label: $0.label, state: $0.state) }
expectEqual(
    StepWindow.headText(headNoTime, window: headWindow, timeZone: seoul),
    "앞 4단계 완료",
    "단계 머리: 완료 시각이 없으면 시각 없이"
)
let mixedHead = [
    step("a", .left),
    step("b", .done, "2026-10-21T13:52:00+09:00"),
    step("c", .done, "2026-10-21T13:55:00+09:00"),
    step("d", .done, "2026-10-21T14:02:00+09:00"),
    step("e", .done),
    step("f", .now),
    step("g", .left),
]
expectEqual(
    StepWindow.headText(mixedHead, window: StepWindow.make(mixedHead.map(\.state)), timeZone: seoul),
    "앞 4단계 · 완료 3",
    "단계 머리: 완료 아닌 단계가 섞이면 완료 수"
)
let startWindow = StepWindow.make(Array(repeating: StepState.left, count: 9))
expectEqual(startWindow.rows, [0, 1, 2], "단계 창: 지금이 첫 단계면 앞 없음")
expectEqual(
    StepWindow.headText(Array(repeating: ChecklistStep(label: "x", state: .left), count: 9),
                       window: startWindow, timeZone: seoul),
    "전체 9단계 보기",
    "단계 머리: 앞이 비면 전체 보기"
)
expectEqual(StepWindow.headText([], window: emptyWindow, timeZone: seoul), nil,
            "단계 머리: 숨은 단계가 없으면 nil")

let trailingSteps = [
    ChecklistStep(label: "a", state: .done, sub: "완료"),
    ChecklistStep(label: "b", state: .left, sub: "대기"),
]
expectEqual(StepWindow.trailingText(trailingSteps, index: 1), "대기 · 마지막",
            "단계 꼬리: 마지막 남은 단계")
expectEqual(StepWindow.trailingText([ChecklistStep(label: "a", state: .left)], index: 0), "마지막",
            "단계 꼬리: 마지막 남은 단계에 sub 가 없으면 마지막만")
expectEqual(StepWindow.trailingText(trailingSteps, index: 0), "완료",
            "단계 꼬리: 마지막이 아니면 sub")
expectEqual(
    StepWindow.trailingText([ChecklistStep(label: "a", state: .left, sub: "대기"),
                            ChecklistStep(label: "b", state: .done)], index: 0),
    "대기",
    "단계 꼬리: 중간 남은 단계는 sub 만"
)

// MARK: - 행 문구

expectEqual(RowText.waiting(since: nil, now: now), nil, "행 문구: 기준 없음")
expectEqual(RowText.waiting(since: now.addingTimeInterval(-60), now: now), "1분째 기다림", "행 문구: 기다린 시간")
expectEqual(RowText.question(detail: "질문", replyTail: "답", status: "상태"), "질문", "행 문구: 질문이 먼저")
expectEqual(RowText.question(detail: nil, replyTail: "답", status: "상태"), "답", "행 문구: 질문이 없으면 답")
expectEqual(RowText.question(detail: nil, replyTail: nil, status: "상태"), "상태", "행 문구: 둘 다 없으면 상태")
expectEqual(RowText.question(detail: nil, replyTail: "답", status: "상태", isStall: true), "상태",
            "행 문구: stall 은 마지막 답 대신 상태")
expectEqual(RowText.question(detail: "질문", replyTail: "답", status: "상태", isStall: true), "질문",
            "행 문구: stall 이어도 질문 전문이 있으면 질문")
expectEqual(RowText.activity(lastSentence: "문장", nowLine: "지금 줄"), "문장", "행 문구: 마지막 문장이 먼저")
expectEqual(RowText.activity(lastSentence: nil, nowLine: "▶ 검증"), nil, "행 문구: 단계 이름은 다시 쓰지 않는다")
expectEqual(RowText.activity(lastSentence: nil, nowLine: "도구 실행"), "도구 실행", "행 문구: 지금 줄")
expectEqual(RowText.trail(backgroundTasks: 2, lastTool: "Bash"), "bg 2 · Bash", "행 문구: 꼬리 둘 다")
expectEqual(RowText.trail(backgroundTasks: 2, lastTool: nil), "bg 2", "행 문구: 꼬리 bg 만")
expectEqual(RowText.trail(backgroundTasks: 0, lastTool: "Bash"), "Bash", "행 문구: bg 0 은 빼고")
expectEqual(RowText.trail(backgroundTasks: nil, lastTool: nil), nil, "행 문구: 꼬리 없음")
expectEqual(RowText.toolLabel("mcp__example_server__read_thread"), "read_thread",
            "행 문구: mcp 도구는 도구 이름만 남긴다")
expectEqual(RowText.toolLabel("Bash"), "Bash", "행 문구: mcp 가 아닌 도구는 그대로")
expectEqual(RowText.toolLabel("mcp__example_server"), "mcp__example_server",
            "행 문구: 구분자가 하나뿐이면 원문 유지")
expectEqual(RowText.toolLabel("mcp__example_server__"), "mcp__example_server__",
            "행 문구: 도구 부분이 비면 원문 유지")
expectEqual(RowText.trail(backgroundTasks: 2, lastTool: "mcp__example_server__read_thread"),
            "bg 2 · read_thread", "행 문구: 긴 mcp 도구 이름도 도구 이름만")
expectEqual(
    SessionActivity(backgroundTasks: 1,
                    lastTool: LastTool(name: "mcp__example_server__read_thread")).line(now: now),
    "백그라운드 1 · read_thread",
    "행 문구: 활동 줄의 mcp 도구도 도구 이름만"
)

// MARK: - 행 표시 값

let richSession = Session(
    sessionId: "rich",
    bucket: "working",
    title: "rich",
    since: now.addingTimeInterval(-120),
    counts: SessionCounts(done: 4, left: 4, now: 1),
    total: 9,
    eta: now.addingTimeInterval(102 * 60),
    activity: SessionActivity(backgroundTasks: 2, lastTool: LastTool(name: "Bash"))
)
let richItem = DisplayItem(session: richSession, group: .working, now: now)
expectEqual(richItem.counts, SessionCounts(done: 4, left: 4, now: 1), "행 표시: 체크리스트 개수")
expectEqual(richItem.etaText, "약 102분 남음", "행 표시: 남은 시간")
expectEqual(richItem.backgroundTaskCount, 2, "행 표시: 백그라운드 개수")
expectEqual(richItem.lastToolName, "Bash", "행 표시: 마지막 도구")
let zeroTotalItem = DisplayItem(
    session: Session(sessionId: "zero", bucket: "working", counts: SessionCounts(done: 1), total: 0),
    group: .working,
    now: now
)
expectEqual(zeroTotalItem.counts, nil, "행 표시: 전체가 0 이면 개수 없음")

// MARK: - 요약 한 줄

expectEqual(ReplySummary.firstSentence("첫 문장이야. 두 번째 문장이야."), "첫 문장이야.", "요약: 두 문장 중 첫 문장")
expectEqual(ReplySummary.firstSentence("v1.2 로 올렸어. 다음"), "v1.2 로 올렸어.", "요약: 소수점은 문장 끝이 아니다")
expectEqual(ReplySummary.firstSentence("```\nlet a = 1\n```\n코드 뒤 첫 문장이야. 둘째"), "코드 뒤 첫 문장이야.",
            "요약: 코드 블록 뒤 첫 문장")
expectEqual(ReplySummary.firstSentence("- 첫 항목\n- 둘째 항목"), "첫 항목", "요약: 목록만 있으면 첫 항목")
expectEqual(ReplySummary.firstSentence("결과는 다음과 같아:\n- a\n- b"), "결과는 다음과 같아:", "요약: 목록 앞 도입 문장")
expectEqual(ReplySummary.firstSentence("배포했어 https://x.y/z 확인해 줘."), "배포했어 확인해 줘.", "요약: 맨 URL 제거")
expectEqual(ReplySummary.firstSentence("PR 올렸어 https://g/3. 리뷰 부탁해."), "PR 올렸어.", "요약: URL 뒤 마침표는 남긴다")
expectEqual(ReplySummary.firstSentence("주소는 (https://a.b/c) 야. 다음"), "주소는 야.", "요약: 괄호 URL 은 빈 괄호까지 지운다")
expectEqual(ReplySummary.firstSentence("#123 머지했어. 다음"), "#123 머지했어.", "요약: #123 은 제목이 아니다")
expectEqual(ReplySummary.firstSentence("[PR #3](https://g/3) 을 열었어."), "PR #3 을 열었어.", "요약: 링크는 글자만")
let longSummarySentence = ReplySummary.firstSentence(String(repeating: "가", count: 100))
expectEqual(longSummarySentence?.count, 90, "요약: 90자")
expect(longSummarySentence?.hasSuffix("…") == true, "요약: 90자를 넘으면 말줄임")
expectEqual(ReplySummary.firstSentence("`a.swift` 를 고쳤어."), "a.swift 를 고쳤어.", "요약: 인라인 코드는 내용만")
expectEqual(ReplySummary.firstSentence(""), nil, "요약: 빈 문자열")
expectEqual(ReplySummary.firstSentence(nil), nil, "요약: nil")
expectEqual(ReplySummary.firstSentence("## 결과\n본문이야."), "본문이야.", "요약: 제목 줄 건너뜀")
expectEqual(ReplySummary.firstSentence("“좋아.” 그다음"), "“좋아.”", "요약: 닫는 따옴표까지")

// MARK: - 알림 카드

func cardItem(_ id: String, bucket: String, group: DisplayGroup, since: Date) -> DisplayItem {
    DisplayItem(
        session: Session(sessionId: id, bucket: bucket, title: id, since: since),
        group: group,
        now: now
    )
}

let cardAttentionA = cardItem("a", bucket: "idle", group: .attention, since: now)
let cardAttentionB = cardItem("b", bucket: "idle", group: .attention, since: now)
let cardDoneD = cardItem("d", bucket: "done", group: .done, since: now)

var orderDeck = CardDeck()
orderDeck.update(
    newAttention: [cardAttentionA],
    newDone: [cardDoneD],
    groups: GroupedSessions(attention: [cardAttentionA], done: [cardDoneD]),
    now: now
)
expectEqual(orderDeck.ordered.map(\.kind), [.attention, .done], "알림 카드: 확인 필요가 끝남보다 위")
orderDeck.update(
    newAttention: [cardAttentionB],
    newDone: [],
    groups: GroupedSessions(attention: [cardAttentionA, cardAttentionB], done: [cardDoneD]),
    now: now.addingTimeInterval(1)
)
expectEqual(orderDeck.ordered.map(\.sessionId), ["b", "a", "d"], "알림 카드: 같은 종류는 늦게 온 것이 위")

let cardStall = cardItem("s", bucket: "stall", group: .attention, since: now)
let cardFinished = cardItem("s", bucket: "done", group: .done, since: now.addingTimeInterval(840))
var replaceDeck = CardDeck()
replaceDeck.update(
    newAttention: [cardStall],
    newDone: [],
    groups: GroupedSessions(attention: [cardStall]),
    now: now
)
replaceDeck.update(
    newAttention: [],
    newDone: [cardFinished],
    groups: GroupedSessions(done: [cardFinished]),
    now: now
)
expectEqual(replaceDeck.cards.count, 1, "알림 카드: 막힘 → 끝남은 카드 한 장")
expectEqual(replaceDeck.cards.first?.kind, CardKind.done, "알림 카드: 끝남으로 대체")
expectEqual(replaceDeck.cards.first?.runDuration, 840, "알림 카드: 걸린 시간")

var expiryDeck = CardDeck()
expiryDeck.update(
    newAttention: [],
    newDone: [cardDoneD],
    groups: GroupedSessions(done: [cardDoneD]),
    now: now
)
expectEqual(expiryDeck.expire(now: now.addingTimeInterval(7.9)), false, "알림 카드: 8초 전에는 만료되지 않는다")
expectEqual(expiryDeck.cards.count, 1, "알림 카드: 만료 전에는 카드가 남는다")
expectEqual(expiryDeck.expire(now: now.addingTimeInterval(8)), true, "알림 카드: 8초 뒤 만료")
expectEqual(expiryDeck.cards.isEmpty, true, "알림 카드: 만료된 카드는 사라진다")

var pauseDeck = CardDeck()
pauseDeck.update(
    newAttention: [],
    newDone: [cardDoneD],
    groups: GroupedSessions(done: [cardDoneD]),
    now: now
)
pauseDeck.setPaused(true, now: now.addingTimeInterval(3))
expectEqual(pauseDeck.expire(now: now.addingTimeInterval(100)), false, "알림 카드: 멈춘 동안에는 만료되지 않는다")
pauseDeck.setPaused(false, now: now.addingTimeInterval(103))
expectEqual(pauseDeck.expire(now: now.addingTimeInterval(107.9)), false, "알림 카드: 재개 뒤 남은 시간 전")
expectEqual(pauseDeck.expire(now: now.addingTimeInterval(108)), true, "알림 카드: 재개 뒤 남은 시간이 지나면 만료")

var pausedNewDeck = CardDeck()
pausedNewDeck.setPaused(true, now: now)
pausedNewDeck.update(
    newAttention: [],
    newDone: [cardDoneD],
    groups: GroupedSessions(done: [cardDoneD]),
    now: now
)
expectEqual(pausedNewDeck.cards.first?.expiresAt, nil, "알림 카드: 멈춘 동안 들어온 끝남 카드는 만료 시각이 없다")
expectEqual(pausedNewDeck.cards.first?.pausedRemaining, 8, "알림 카드: 멈춘 동안 들어온 끝남 카드는 8초를 그대로 가진다")
pausedNewDeck.setPaused(false, now: now.addingTimeInterval(2))
expectEqual(pausedNewDeck.cards.first?.expiresAt, now.addingTimeInterval(10), "알림 카드: 재개하면 남은 시간만큼 이어간다")

var retireAttentionDeck = CardDeck()
retireAttentionDeck.update(
    newAttention: [cardAttentionA],
    newDone: [],
    groups: GroupedSessions(attention: [cardAttentionA]),
    now: now
)
retireAttentionDeck.update(newAttention: [], newDone: [], groups: GroupedSessions(), now: now)
expectEqual(retireAttentionDeck.cards.isEmpty, true, "알림 카드: 답해 확인 필요에서 빠지면 거둔다")

var retireDoneDeck = CardDeck()
retireDoneDeck.update(
    newAttention: [],
    newDone: [cardDoneD],
    groups: GroupedSessions(done: [cardDoneD]),
    now: now
)
retireDoneDeck.update(newAttention: [], newDone: [], groups: GroupedSessions(), now: now)
expectEqual(retireDoneDeck.cards.isEmpty, true, "알림 카드: 확인해 완료에서 빠지면 거둔다")

var runDeck = CardDeck()
let cardWorking = cardItem("w", bucket: "working", group: .working, since: now)
runDeck.update(newAttention: [], newDone: [], groups: GroupedSessions(working: [cardWorking]), now: now)
let cardStallLater = cardItem("w", bucket: "stall", group: .attention, since: now.addingTimeInterval(600))
runDeck.update(newAttention: [], newDone: [], groups: GroupedSessions(attention: [cardStallLater]), now: now)
let cardDoneLater = cardItem("w", bucket: "done", group: .done, since: now.addingTimeInterval(840))
runDeck.update(
    newAttention: [],
    newDone: [cardDoneLater],
    groups: GroupedSessions(done: [cardDoneLater]),
    now: now
)
expectEqual(runDeck.cards.first?.runDuration, 840, "알림 카드: 권한 대기로 since 가 바뀌어도 첫 시작을 지킨다")

expectEqual(CardDeck.headerText(attention: 0, done: 1), nil, "알림 카드: 한 장이면 머리글이 없다")
expectEqual(CardDeck.headerText(attention: 1, done: 3), "확인 1 · 끝남 3", "알림 카드: 머리글 확인·끝남")
expectEqual(CardDeck.headerText(attention: 0, done: 2), "끝남 2", "알림 카드: 머리글 끝남만")

var fractionDeck = CardDeck()
fractionDeck.update(
    newAttention: [],
    newDone: [cardDoneD],
    groups: GroupedSessions(done: [cardDoneD]),
    now: now
)
let fractionCard = fractionDeck.cards[0]
expectEqual(CardDeck.remainingFraction(of: fractionCard, paused: fractionDeck.paused, now: now), 1, "알림 카드: 새 카드의 남은 비율")
expectEqual(CardDeck.remainingFraction(of: fractionCard, paused: fractionDeck.paused, now: now.addingTimeInterval(4)), 0.5,
            "알림 카드: 4초 뒤 남은 비율")

var deadlineDeck = CardDeck()
let cardDoneE = cardItem("e", bucket: "done", group: .done, since: now)
deadlineDeck.update(
    newAttention: [],
    newDone: [cardDoneD],
    groups: GroupedSessions(done: [cardDoneD]),
    now: now
)
deadlineDeck.update(
    newAttention: [],
    newDone: [cardDoneE],
    groups: GroupedSessions(done: [cardDoneD, cardDoneE]),
    now: now.addingTimeInterval(3)
)
expectEqual(deadlineDeck.nextDeadline, now.addingTimeInterval(8), "알림 카드: 가장 이른 만료")
deadlineDeck.setPaused(true, now: now.addingTimeInterval(4))
expectEqual(deadlineDeck.nextDeadline, nil, "알림 카드: 멈춤 중에는 만료 예약이 없다")

var unpauseDeck = CardDeck()
unpauseDeck.update(
    newAttention: [],
    newDone: [cardDoneD],
    groups: GroupedSessions(done: [cardDoneD]),
    now: now
)
unpauseDeck.setPaused(true, now: now)
unpauseDeck.dismissAll()
expectEqual(unpauseDeck.paused, false, "알림 카드: 모두 거두면 멈춤이 풀린다")
unpauseDeck.update(
    newAttention: [],
    newDone: [cardDoneE],
    groups: GroupedSessions(done: [cardDoneE]),
    now: now.addingTimeInterval(1)
)
expectEqual(unpauseDeck.cards.first?.expiresAt, now.addingTimeInterval(9),
            "알림 카드: 멈춤이 풀린 뒤 들어온 끝남 카드는 만료 시각을 갖는다")
expectEqual(unpauseDeck.expire(now: now.addingTimeInterval(8.9)), false, "알림 카드: 풀린 뒤 새 카드는 8초 전 만료되지 않는다")
expectEqual(unpauseDeck.expire(now: now.addingTimeInterval(9)), true, "알림 카드: 풀린 뒤 새 카드는 8초 뒤 만료")
expectEqual(unpauseDeck.paused, false, "알림 카드: 만료로 비어도 멈춤이 없다")

var dismissLastDeck = CardDeck()
dismissLastDeck.update(
    newAttention: [],
    newDone: [cardDoneD],
    groups: GroupedSessions(done: [cardDoneD]),
    now: now
)
dismissLastDeck.setPaused(true, now: now)
dismissLastDeck.dismiss("d")
expectEqual(dismissLastDeck.paused, false, "알림 카드: 마지막 카드를 거두면 멈춤이 풀린다")

var dismissKindDeck = CardDeck()
dismissKindDeck.update(
    newAttention: [cardAttentionA],
    newDone: [cardDoneD],
    groups: GroupedSessions(attention: [cardAttentionA], done: [cardDoneD]),
    now: now
)
dismissKindDeck.setPaused(true, now: now)
dismissKindDeck.dismiss(kind: .attention)
expectEqual(dismissKindDeck.cards.map(\.kind), [.done], "알림 카드: 종류로 거두면 그 종류만 사라진다")
dismissKindDeck.dismiss(kind: .done)
expectEqual(dismissKindDeck.cards.isEmpty, true, "알림 카드: 남은 종류까지 거두면 빈다")
expectEqual(dismissKindDeck.paused, false, "알림 카드: 종류로 마저 거두면 멈춤이 풀린다")

var soundDeck = CardDeck()
let insertedNormal = soundDeck.update(
    newAttention: [cardAttentionA],
    newDone: [],
    groups: GroupedSessions(attention: [cardAttentionA]),
    now: now
)
expectEqual(insertedNormal, 1, "알림 카드: 자리에 있을 때 넣은 막힘 수를 돌려준다")

// MARK: - 자리 비움

var awayDeck = CardDeck()
awayDeck.beginAway(now: now)
expectEqual(awayDeck.isAway, true, "자리 비움: 시작하면 자리 비움 상태")
expectEqual(awayDeck.awaySince, now, "자리 비움: 시작 시각")
let awayAttentionItem = cardItem("x", bucket: "idle", group: .attention, since: now)
let awayDoneItem = cardItem("y", bucket: "done", group: .done, since: now)
let insertedWhileAway = awayDeck.update(
    newAttention: [awayAttentionItem],
    newDone: [awayDoneItem],
    groups: GroupedSessions(attention: [awayAttentionItem], done: [awayDoneItem]),
    now: now
)
expectEqual(insertedWhileAway, 0, "자리 비움: update 반환값은 0")
expectEqual(awayDeck.cards.isEmpty, true, "자리 비움: 모은 사건은 개별 카드로 뜨지 않는다")

var awayEmptyDeck = CardDeck()
awayEmptyDeck.beginAway(now: now)
expectEqual(awayEmptyDeck.endAway(now: now.addingTimeInterval(60)), AwayReturn.none, "자리 비움: 0건 복귀는 none")
expectEqual(awayEmptyDeck.cards.isEmpty, true, "자리 비움: 0건 복귀는 카드 변화 없음")

var awaySingleAttentionDeck = CardDeck()
awaySingleAttentionDeck.beginAway(now: now)
awaySingleAttentionDeck.update(
    newAttention: [cardAttentionA],
    newDone: [],
    groups: GroupedSessions(attention: [cardAttentionA]),
    now: now
)
let returnAt = now.addingTimeInterval(60)
expectEqual(awaySingleAttentionDeck.endAway(now: returnAt), AwayReturn.single(.attention),
            "자리 비움: 1건 막힘 복귀는 개별 카드")
expectEqual(awaySingleAttentionDeck.cards.map(\.kind), [.attention], "자리 비움: 1건 막힘은 카드 한 장")
expectEqual(awaySingleAttentionDeck.cards.first?.arrivedAt, returnAt, "자리 비움: 복귀 시각으로 들어온다")

var awaySingleDoneDeck = CardDeck()
awaySingleDoneDeck.beginAway(now: now)
awaySingleDoneDeck.update(
    newAttention: [],
    newDone: [cardDoneD],
    groups: GroupedSessions(done: [cardDoneD]),
    now: now
)
expectEqual(awaySingleDoneDeck.endAway(now: returnAt), AwayReturn.single(.done),
            "자리 비움: 1건 끝남 복귀는 개별 카드")
expectEqual(awaySingleDoneDeck.cards.first?.expiresAt, returnAt.addingTimeInterval(8),
            "자리 비움: 1건 끝남은 복귀 시각부터 8초")

var awaySummaryDeck = CardDeck()
awaySummaryDeck.beginAway(now: now)
awaySummaryDeck.update(
    newAttention: [cardAttentionA, cardAttentionB],
    newDone: [cardDoneD],
    groups: GroupedSessions(attention: [cardAttentionA, cardAttentionB], done: [cardDoneD]),
    now: now
)
expectEqual(awaySummaryDeck.endAway(now: returnAt), AwayReturn.summary(attention: 2, done: 1),
            "자리 비움: 2건 이상 복귀는 요약")
expectEqual(awaySummaryDeck.cards.count, 1, "자리 비움: 요약 카드 한 장")
expectEqual(awaySummaryDeck.cards.first?.kind, CardKind.away, "자리 비움: 요약 카드 종류")
expectEqual(awaySummaryDeck.cards.first?.sessionId, CardDeck.awayCardId, "자리 비움: 요약 카드 식별자")
expectEqual(awaySummaryDeck.cards.first?.awayAttention, 2, "자리 비움: 요약의 막힘 수")
expectEqual(awaySummaryDeck.cards.first?.awayDone, 1, "자리 비움: 요약의 끝남 수")

var awayTransitionDeck = CardDeck()
awayTransitionDeck.beginAway(now: now)
awayTransitionDeck.update(
    newAttention: [cardAttentionA, cardAttentionB],
    newDone: [],
    groups: GroupedSessions(attention: [cardAttentionA, cardAttentionB]),
    now: now
)
let transitionDone = cardItem("a", bucket: "done", group: .done, since: now.addingTimeInterval(5))
awayTransitionDeck.update(
    newAttention: [],
    newDone: [transitionDone],
    groups: GroupedSessions(attention: [cardAttentionB], done: [transitionDone]),
    now: now.addingTimeInterval(5)
)
expectEqual(awayTransitionDeck.endAway(now: now.addingTimeInterval(6)),
            AwayReturn.summary(attention: 1, done: 1), "자리 비움: 막혔다 끝난 세션은 끝남 하나로 센다")

var awayBackDeck = CardDeck()
awayBackDeck.beginAway(now: now)
awayBackDeck.update(
    newAttention: [cardAttentionA],
    newDone: [],
    groups: GroupedSessions(attention: [cardAttentionA]),
    now: now
)
awayBackDeck.update(
    newAttention: [],
    newDone: [],
    groups: GroupedSessions(working: [cardWorking]),
    now: now.addingTimeInterval(5)
)
expectEqual(awayBackDeck.endAway(now: now.addingTimeInterval(6)), AwayReturn.none,
            "자리 비움: 진행 중으로 돌아간 세션은 세지 않는다")

var awayStickyDeck = CardDeck()
awayStickyDeck.beginAway(now: now)
awayStickyDeck.update(
    newAttention: [cardAttentionA, cardAttentionB],
    newDone: [cardDoneD],
    groups: GroupedSessions(attention: [cardAttentionA, cardAttentionB], done: [cardDoneD]),
    now: now
)
awayStickyDeck.endAway(now: returnAt)
expectEqual(awayStickyDeck.nextDeadline, nil, "자리 비움: 막힘이 든 요약은 만료 예약이 없다")
expectEqual(awayStickyDeck.expire(now: returnAt.addingTimeInterval(10_000)), false,
            "자리 비움: 막힘이 든 요약은 오래 지나도 안 사라진다")
expectEqual(awayStickyDeck.cards.count, 1, "자리 비움: 막힘이 든 요약은 남는다")

let awayDoneOne = cardItem("p", bucket: "done", group: .done, since: now)
let awayDoneTwo = cardItem("q", bucket: "done", group: .done, since: now)
var awayDoneOnlyDeck = CardDeck()
awayDoneOnlyDeck.beginAway(now: now)
awayDoneOnlyDeck.update(
    newAttention: [],
    newDone: [awayDoneOne, awayDoneTwo],
    groups: GroupedSessions(done: [awayDoneOne, awayDoneTwo]),
    now: now
)
expectEqual(awayDoneOnlyDeck.endAway(now: returnAt), AwayReturn.summary(attention: 0, done: 2),
            "자리 비움: 끝남만 모으면 끝남 요약")
expectEqual(awayDoneOnlyDeck.nextDeadline, returnAt.addingTimeInterval(8),
            "자리 비움: 끝남만 든 요약은 8초 수명")
awayDoneOnlyDeck.setPaused(true, now: returnAt.addingTimeInterval(2))
expectEqual(awayDoneOnlyDeck.expire(now: returnAt.addingTimeInterval(100)), false,
            "자리 비움: 멈춘 동안 끝남 요약은 안 사라진다")
awayDoneOnlyDeck.setPaused(false, now: returnAt.addingTimeInterval(101))
expectEqual(awayDoneOnlyDeck.expire(now: returnAt.addingTimeInterval(106.9)), false,
            "자리 비움: 재개 뒤 남은 시간 전")
expectEqual(awayDoneOnlyDeck.expire(now: returnAt.addingTimeInterval(107)), true,
            "자리 비움: 끝남만 든 요약은 남은 시간이 지나면 사라진다")

var awayPausedDeck = CardDeck()
awayPausedDeck.beginAway(now: now)
awayPausedDeck.update(
    newAttention: [],
    newDone: [awayDoneOne, awayDoneTwo],
    groups: GroupedSessions(done: [awayDoneOne, awayDoneTwo]),
    now: now
)
awayPausedDeck.setPaused(true, now: returnAt)
awayPausedDeck.endAway(now: returnAt)
expectEqual(awayPausedDeck.cards.first?.expiresAt, nil, "자리 비움: 멈춘 덱에 복귀한 끝남 요약은 만료 시각이 없다")
expectEqual(awayPausedDeck.cards.first?.pausedRemaining, 8, "자리 비움: 멈춘 덱에 복귀한 끝남 요약은 8초를 그대로 가진다")

var awayOrderDeck = CardDeck()
awayOrderDeck.beginAway(now: now)
awayOrderDeck.update(
    newAttention: [cardAttentionA],
    newDone: [cardDoneD],
    groups: GroupedSessions(attention: [cardAttentionA], done: [cardDoneD]),
    now: now
)
awayOrderDeck.endAway(now: returnAt)
let orderAttention = cardItem("n", bucket: "idle", group: .attention, since: returnAt)
let orderDone = cardItem("m", bucket: "done", group: .done, since: returnAt)
awayOrderDeck.update(
    newAttention: [orderAttention],
    newDone: [orderDone],
    groups: GroupedSessions(attention: [cardAttentionA, orderAttention], done: [cardDoneD, orderDone]),
    now: returnAt.addingTimeInterval(1)
)
expectEqual(awayOrderDeck.ordered.map(\.kind), [.away, .attention, .done], "자리 비움: 요약 카드가 맨 위")
awayOrderDeck.dismissAll()
expectEqual(awayOrderDeck.cards.isEmpty, true, "자리 비움: 모두 거두면 요약도 사라진다")

var awayDismissKindDeck = CardDeck()
awayDismissKindDeck.beginAway(now: now)
awayDismissKindDeck.update(
    newAttention: [cardAttentionA],
    newDone: [],
    groups: GroupedSessions(attention: [cardAttentionA]),
    now: now
)
awayDismissKindDeck.dismiss(kind: .attention)
expectEqual(awayDismissKindDeck.endAway(now: returnAt), AwayReturn.none,
            "자리 비움: 끈 종류는 복귀 요약에 안 들어간다")

var awayTwiceDeck = CardDeck()
awayTwiceDeck.beginAway(now: now)
awayTwiceDeck.update(
    newAttention: [cardAttentionA],
    newDone: [],
    groups: GroupedSessions(attention: [cardAttentionA]),
    now: now
)
awayTwiceDeck.beginAway(now: now.addingTimeInterval(30))
expectEqual(awayTwiceDeck.awaySince, now, "자리 비움: 두 번째 시작은 처음 시각을 지킨다")
expectEqual(awayTwiceDeck.endAway(now: returnAt), AwayReturn.single(.attention),
            "자리 비움: 두 번째 시작은 모은 것을 지킨다")

var awayNotDeck = CardDeck()
expectEqual(awayNotDeck.endAway(now: now), AwayReturn.none, "자리 비움: 자리에 있을 때 복귀는 none")

var awayExistingDeck = CardDeck()
awayExistingDeck.update(
    newAttention: [cardAttentionA],
    newDone: [],
    groups: GroupedSessions(attention: [cardAttentionA]),
    now: now
)
awayExistingDeck.beginAway(now: now)
expectEqual(awayExistingDeck.cards.count, 1, "자리 비움: 이미 떠 있던 카드는 시작해도 남는다")

var awayPruneDeck = CardDeck()
awayPruneDeck.beginAway(now: now)
awayPruneDeck.update(
    newAttention: [cardAttentionA, cardAttentionB],
    newDone: [cardDoneD],
    groups: GroupedSessions(attention: [cardAttentionA, cardAttentionB], done: [cardDoneD]),
    now: now
)
awayPruneDeck.endAway(now: returnAt)
awayPruneDeck.update(
    newAttention: [],
    newDone: [],
    groups: GroupedSessions(attention: [cardAttentionB], done: [cardDoneD]),
    now: returnAt.addingTimeInterval(1)
)
expectEqual(awayPruneDeck.cards.first?.awayAttention, 1, "자리 비움: 목록에서 빠진 막힘 멤버는 요약에서 빠진다")
expectEqual(awayPruneDeck.cards.count, 1, "자리 비움: 막힘이 남은 요약은 남는다")
expectEqual(awayPruneDeck.nextDeadline, nil, "자리 비움: 막힘이 남은 요약은 만료 예약이 없다")

var awayPruneDoneDeck = CardDeck()
awayPruneDoneDeck.beginAway(now: now)
awayPruneDoneDeck.update(
    newAttention: [cardAttentionA],
    newDone: [cardDoneD],
    groups: GroupedSessions(attention: [cardAttentionA], done: [cardDoneD]),
    now: now
)
awayPruneDoneDeck.endAway(now: returnAt)
awayPruneDoneDeck.update(
    newAttention: [],
    newDone: [],
    groups: GroupedSessions(done: [cardDoneD]),
    now: returnAt.addingTimeInterval(1)
)
expectEqual(awayPruneDoneDeck.cards.first?.awayAttention, 0, "자리 비움: 막힘 멤버가 다 빠지면 막힘 수 0")
expectEqual(awayPruneDoneDeck.nextDeadline, returnAt.addingTimeInterval(9),
            "자리 비움: 막힘을 다 잃은 요약은 그 갱신 시각부터 8초 수명")
expectEqual(awayPruneDoneDeck.expire(now: returnAt.addingTimeInterval(8.9)), false,
            "자리 비움: 끝남만 남은 요약은 수명 전")
expectEqual(awayPruneDoneDeck.expire(now: returnAt.addingTimeInterval(9)), true,
            "자리 비움: 끝남만 남은 요약은 수명 뒤 사라진다")

var awayPrunePausedDeck = CardDeck()
awayPrunePausedDeck.beginAway(now: now)
awayPrunePausedDeck.update(
    newAttention: [cardAttentionA],
    newDone: [cardDoneD],
    groups: GroupedSessions(attention: [cardAttentionA], done: [cardDoneD]),
    now: now
)
awayPrunePausedDeck.endAway(now: returnAt)
awayPrunePausedDeck.setPaused(true, now: returnAt)
awayPrunePausedDeck.update(
    newAttention: [],
    newDone: [],
    groups: GroupedSessions(done: [cardDoneD]),
    now: returnAt.addingTimeInterval(1)
)
expectEqual(awayPrunePausedDeck.nextDeadline, nil, "자리 비움: 멈춘 채 막힘을 다 잃은 요약은 만료 예약이 없다")
let pausedPruneCard = awayPrunePausedDeck.cards[0]
expectEqual(CardDeck.remainingFraction(of: pausedPruneCard, paused: awayPrunePausedDeck.paused,
                                      now: returnAt.addingTimeInterval(1)), 1,
            "자리 비움: 멈춘 채 막힘을 다 잃은 요약은 8초를 그대로 가진다")

var awayPruneAllDeck = CardDeck()
awayPruneAllDeck.beginAway(now: now)
awayPruneAllDeck.update(
    newAttention: [cardAttentionA],
    newDone: [cardDoneD],
    groups: GroupedSessions(attention: [cardAttentionA], done: [cardDoneD]),
    now: now
)
awayPruneAllDeck.endAway(now: returnAt)
awayPruneAllDeck.update(
    newAttention: [],
    newDone: [],
    groups: GroupedSessions(),
    now: returnAt.addingTimeInterval(1)
)
expectEqual(awayPruneAllDeck.cards.isEmpty, true, "자리 비움: 멤버가 다 빠지면 요약 카드가 거둬진다")

var awayAgainDeck = CardDeck()
awayAgainDeck.beginAway(now: now)
awayAgainDeck.update(
    newAttention: [cardAttentionA],
    newDone: [cardDoneD],
    groups: GroupedSessions(attention: [cardAttentionA], done: [cardDoneD]),
    now: now
)
awayAgainDeck.endAway(now: returnAt)
awayAgainDeck.beginAway(now: returnAt.addingTimeInterval(10))
let awayAgainDone = cardItem("e", bucket: "done", group: .done, since: returnAt)
awayAgainDeck.update(
    newAttention: [],
    newDone: [awayAgainDone],
    groups: GroupedSessions(attention: [cardAttentionA], done: [cardDoneD, awayAgainDone]),
    now: returnAt.addingTimeInterval(10)
)
expectEqual(awayAgainDeck.endAway(now: returnAt.addingTimeInterval(20)),
            AwayReturn.summary(attention: 1, done: 2), "자리 비움: 떠 있는 요약에 다시 모은 사건을 합친다")
expectEqual(awayAgainDeck.cards.count, 1, "자리 비움: 다시 비웠다 와도 요약 한 장")
expectEqual(awayAgainDeck.cards.first?.awayAttention, 1, "자리 비움: 다시 비웠다 와도 남은 막힘은 그대로")
expectEqual(awayAgainDeck.cards.first?.awayDone, 2, "자리 비움: 다시 비웠다 오면 끝남이 요약에 더해진다")

var awayDismissSummaryDeck = CardDeck()
awayDismissSummaryDeck.beginAway(now: now)
awayDismissSummaryDeck.update(
    newAttention: [cardAttentionA],
    newDone: [cardDoneD],
    groups: GroupedSessions(attention: [cardAttentionA], done: [cardDoneD]),
    now: now
)
awayDismissSummaryDeck.endAway(now: returnAt)
awayDismissSummaryDeck.dismiss(kind: .attention, now: returnAt.addingTimeInterval(5))
expectEqual(awayDismissSummaryDeck.cards.first?.awayAttention, 0, "자리 비움: 종류로 끄면 요약의 막힘 멤버가 빠진다")
expectEqual(awayDismissSummaryDeck.cards.first?.awayDone, 1, "자리 비움: 종류로 끄면 끝남 멤버는 남는다")
expectEqual(awayDismissSummaryDeck.nextDeadline, returnAt.addingTimeInterval(13),
            "자리 비움: 막힘을 끈 요약은 그 시각부터 8초 수명")

var awayDismissMembersDeck = CardDeck()
awayDismissMembersDeck.beginAway(now: now)
awayDismissMembersDeck.update(
    newAttention: [cardAttentionA, cardAttentionB],
    newDone: [],
    groups: GroupedSessions(attention: [cardAttentionA, cardAttentionB]),
    now: now
)
awayDismissMembersDeck.endAway(now: returnAt)
awayDismissMembersDeck.dismiss(kind: .attention, now: returnAt)
expectEqual(awayDismissMembersDeck.cards.isEmpty, true,
            "자리 비움: 막힘만 든 요약에서 막힘을 끄면 카드가 거둬진다")

expectEqual(ScreenLockTransition.decide(locked: true, isAway: false), ScreenLockTransition.begin,
            "자리 비움: 잠김 + 자리에 있음 → begin")
expectEqual(ScreenLockTransition.decide(locked: false, isAway: true), ScreenLockTransition.end,
            "자리 비움: 안 잠김 + 자리 비움 → end")
expectEqual(ScreenLockTransition.decide(locked: true, isAway: true), ScreenLockTransition.none,
            "자리 비움: 잠김 + 자리 비움 → none")
expectEqual(ScreenLockTransition.decide(locked: false, isAway: false), ScreenLockTransition.none,
            "자리 비움: 안 잠김 + 자리에 있음 → none")
expectEqual(ScreenLockTransition.decide(locked: nil, isAway: false), ScreenLockTransition.none,
            "자리 비움: 읽기 실패 + 자리에 있음 → none")
expectEqual(ScreenLockTransition.decide(locked: nil, isAway: true), ScreenLockTransition.none,
            "자리 비움: 읽기 실패 + 자리 비움 → none")

expectEqual(CardText.awayTitle, "자리 비운 사이", "자리 비움: 제목")
expectEqual(CardText.awayHeadline(attention: 2, done: 0), "세션 2개가 기다려요", "자리 비움: 막힘만 있으면 기다린다")
expectEqual(CardText.awayHeadline(attention: 2, done: 3), "세션 2개가 기다려요", "자리 비움: 둘 다 있으면 막힘을 센다")
expectEqual(CardText.awayHeadline(attention: 0, done: 3), "세션 3개가 끝났어요", "자리 비움: 끝남만 있으면 끝났다")
expectEqual(CardText.awayDetail(attention: 2, done: 0), "누르면 목록이 열려요", "자리 비움: 막힘만 있으면 안내만")
expectEqual(CardText.awayDetail(attention: 2, done: 3), "3개 끝났어요 · 누르면 목록이 열려요",
            "자리 비움: 둘 다 있으면 끝남 수를 잇는다")
expectEqual(CardText.awayDetail(attention: 0, done: 3), "누르면 목록이 열려요", "자리 비움: 끝남만 있으면 안내만")
expectEqual(CardText.awayMeta(attention: 2, done: 3), "자리 비운 사이 · 3개 끝났어요 · 누르면 목록이 열려요",
            "자리 비움: 2행, 막힘과 끝남이 함께 있으면 끝남 수를 잇는다")
expectEqual(CardText.awayMeta(attention: 2, done: 0), "자리 비운 사이 · 누르면 목록이 열려요",
            "자리 비움: 2행, 막힘만 있으면 안내만")

let alwaysRoute = NotificationRoute.decide(policy: .always)
expect(alwaysRoute.cards && alwaysRoute.system, "알림 경로: always 는 둘 다")
let neverRoute = NotificationRoute.decide(policy: .never)
expect(neverRoute.cards && !neverRoute.system, "알림 경로: never 는 카드만")

expectEqual(CardText.doneTrail(runDuration: 840, finishedAt: now, now: now), "14분 걸림", "카드 문구: 걸린 시간")
expectEqual(CardText.doneTrail(runDuration: nil, finishedAt: now.addingTimeInterval(-660), now: now), "11분 전",
            "카드 문구: 완료 시각")
expectEqual(CardText.doneTrail(runDuration: nil, finishedAt: nil, now: now), nil, "카드 문구: 둘 다 없음")
expectEqual(CardText.doneMeta(title: "pulse-main", runDuration: 60), "pulse-main · 끝남 · 1분 걸림", "카드 문구: 2행")
expectEqual(CardText.doneMeta(title: "pulse-main", runDuration: nil), "pulse-main · 끝남", "카드 문구: 2행, 걸린 시간 모름")
expectEqual(CardText.doneSummary(summary: "요약", status: "끝났어요"), "요약", "카드 문구: 요약 먼저")
expectEqual(CardText.doneSummary(summary: "  ", status: "끝났어요"), "끝났어요", "카드 문구: 요약이 비면 상태")

// MARK: - 입력 경계

expectEqual(DeadhdState.pagePath("/tmp/deadhd-x.html"), "/tmp/deadhd-x.html", "경로: /tmp 아래 html")
expectEqual(DeadhdState.pagePath("/private/tmp/claude-501/a/b/scratchpad/x.html"),
            "/private/tmp/claude-501/a/b/scratchpad/x.html", "경로: /private/tmp 아래 html")
expectEqual(DeadhdState.dataPath("/tmp/deadhd-x.json"), "/tmp/deadhd-x.json", "경로: /tmp 아래 json")
expectEqual(DeadhdState.pagePath("/tmp/a/../x.html"), "/tmp/x.html", "경로: .. 를 접어 돌려준다")
expectEqual(DeadhdState.pagePath("/etc/x.html"), nil, "경로: /tmp 밖 거부")
expectEqual(DeadhdState.pagePath("/tmp/../Users/alex/x.html"), nil, "경로: .. 로 /tmp 밖으로 나가면 거부")
expectEqual(DeadhdState.pagePath("/tmp/x.txt"), nil, "경로: html 이 아니면 거부")
expectEqual(DeadhdState.pagePath("relative/x.html"), nil, "경로: 상대 경로 거부")
expectEqual(DeadhdState.pagePath("/tmpfoo/x.html"), nil, "경로: 접두사 유사 경로 거부")
expectEqual(DeadhdState.dataPath("/tmp/x.html"), nil, "경로: dataPath 는 json 만 받는다")
expectEqual(DeadhdState.pagePath(nil), nil, "경로: 값이 없으면 nil")

expectEqual(DeadhdSkillLocation.directories(configDirectory: "/c", installedPlugins: nil),
            ["/c/skills/deadhd"], "deadhd 위치: 플러그인 기록이 없으면 설정 디렉터리만")
expectEqual(
    DeadhdSkillLocation.directories(configDirectory: "/c", installedPlugins: Data(
        #"{"version":2,"plugins":{"deadhd@deadhd":[{"scope":"user","installPath":"/p/1.13.2"}]}}"#.utf8
    )),
    ["/c/skills/deadhd", "/p/1.13.2/skills/deadhd"],
    "deadhd 위치: 플러그인 설치 경로를 뒤에 붙인다"
)
expectEqual(
    DeadhdSkillLocation.directories(configDirectory: "/c", installedPlugins: Data(
        #"{"plugins":{"deadhd@other":[{"installPath":"/o"}],"deadhd@deadhd":[{"installPath":"/p"}]}}"#.utf8
    )),
    ["/c/skills/deadhd", "/p/skills/deadhd", "/o/skills/deadhd"],
    "deadhd 위치: deadhd@deadhd 를 먼저, 나머지 deadhd@ 키는 이름순"
)
expectEqual(
    DeadhdSkillLocation.directories(configDirectory: "/c", installedPlugins: Data(
        #"{"plugins":{"other@market":[{"installPath":"/x"}]}}"#.utf8
    )),
    ["/c/skills/deadhd"], "deadhd 위치: 다른 플러그인 키는 무시"
)
expectEqual(
    DeadhdSkillLocation.directories(configDirectory: "/c", installedPlugins: Data(
        #"{"plugins":{"deadhd@deadhd":[{"installPath":"plugins/x"},{"installPath":7},{"installPath":"/p"}]}}"#.utf8
    )),
    ["/c/skills/deadhd", "/p/skills/deadhd"],
    "deadhd 위치: 상대 경로와 문자열이 아닌 installPath 는 거른다"
)
expectEqual(DeadhdSkillLocation.directories(configDirectory: "/c", installedPlugins: Data("{".utf8)),
            ["/c/skills/deadhd"], "deadhd 위치: 깨진 JSON 이면 설정 디렉터리만")
expectEqual(DeadhdSkillLocation.directories(configDirectory: "/c", installedPlugins: Data(#"{"version":2}"#.utf8)),
            ["/c/skills/deadhd"], "deadhd 위치: plugins 가 없으면 설정 디렉터리만")
expectEqual(
    DeadhdSkillLocation.directories(configDirectory: "/c", installedPlugins: Data(
        #"{"plugins":{"deadhd@deadhd":[{"installPath":"/c"},{"installPath":"/p"},{"installPath":"/p"}]}}"#.utf8
    )),
    ["/c/skills/deadhd", "/p/skills/deadhd"],
    "deadhd 위치: 같은 경로는 한 번만"
)

let untrustedOutState = DeadhdState.parse(Data(
    #"{"sessionId":"s","out":"/Users/alex/x.html","data":"/tmp/x.json"}"#.utf8
))
expect(untrustedOutState != nil, "상태: 밖을 가리키는 out 이 있어도 상태는 읽는다")
expectEqual(untrustedOutState?.pagePath, nil, "상태: /tmp 밖 out 은 버린다")
expectEqual(untrustedOutState?.dataPath, "/tmp/x.json", "상태: 허용된 data 는 남긴다")

expect(SafeLink.httpURL("https://github.com/a/b/pull/1") != nil, "링크: https 통과")
expect(SafeLink.httpURL("http://example.com") != nil, "링크: http 통과")
expectEqual(SafeLink.httpURL("file:///etc/passwd"), nil, "링크: file 스킴 거부")
expectEqual(SafeLink.httpURL("javascript:alert(1)"), nil, "링크: javascript 스킴 거부")
expectEqual(SafeLink.httpURL("x-apple.systempreferences:com.apple.Notifications-Settings.extension"), nil,
            "링크: 설정 스킴 거부")
expectEqual(SafeLink.httpURL("http:"), nil, "링크: 호스트 없는 http 거부")
expectEqual(SafeLink.httpURL("http:///path"), nil, "링크: 빈 호스트 거부")
expectEqual(SafeLink.httpURL("ftp://example.com"), nil, "링크: ftp 거부")

let untrustedLinkState = DeadhdState.parse(Data(
    ##"{"sessionId":"s","summary":{"key":"ABC-1","keyHref":"file:///etc/passwd","pr":{"text":"#1","href":"javascript:alert(1)"}}}"##.utf8
))
expectEqual(untrustedLinkState?.keyHref, nil, "상태: file 스킴 keyHref 를 버린다")
expectEqual(untrustedLinkState?.pr, nil, "상태: javascript 스킴 PR 을 버린다")

expectEqual(LocalSessions.parseRecord(Data(#"{"sessionId":"../x","pid":2}"#.utf8)), nil,
            "세션 파일: 상위 경로를 가리키는 ID 거부")
expectEqual(
    LocalSessions.parseRecord(Data(#"{"sessionId":"c6c3102d-84cd-4ac5-bc38-b4363ee03304","pid":2}"#.utf8))?.sessionId,
    "c6c3102d-84cd-4ac5-bc38-b4363ee03304",
    "세션 파일: UUID 형태 통과"
)

expectEqual(
    LocalSessions.summarizeTranscriptTail(
        Data(#"{"type":"pr-link","prNumber":1,"prUrl":"file:///etc/passwd"}"#.utf8),
        droppingPartialFirstLine: false
    ).pullRequest,
    nil,
    "PR: http 가 아닌 주소는 버린다"
)

runDemoFixtureChecks()

var probedExecutables: [String] = []
expectEqual(
    ExecutablePath.firstExecutable(in: ["/a/python3", "/b/python3", "/c/python3"]) { path in
        probedExecutables.append(path)
        return path == "/a/python3" || path == "/b/python3"
    },
    "/a/python3",
    "실행 파일: 첫 후보가 있으면 첫 후보를 고른다"
)
expectEqual(
    ExecutablePath.firstExecutable(in: ["/a/python3", "/b/python3", "/c/python3"]) { $0 == "/b/python3" },
    "/b/python3",
    "실행 파일: 첫 후보가 없으면 둘째 후보를 고른다"
)
expectEqual(
    ExecutablePath.firstExecutable(in: ["/a/python3", "/b/python3", "/c/python3"]) { _ in false },
    nil,
    "실행 파일: 모두 없으면 nil"
)
expectEqual(
    ExecutablePath.firstExecutable(in: ["python3", "/b/python3"]) { _ in true },
    "/b/python3",
    "실행 파일: 절대 경로가 아닌 후보는 건너뛴다"
)
expectEqual(
    ExecutablePath.firstExecutable(in: []) { _ in true },
    nil,
    "실행 파일: 후보가 없으면 nil"
)
expect(!probedExecutables.contains("/c/python3"), "실행 파일: 첫 통과에서 멈춘다")

// MARK: - 영어 문구

L10n.language = .en

expectEqual(Language.resolve(environment: ["PULSE_LANG": "en"], preferredLanguages: ["ko-KR"]), .en,
            "언어: PULSE_LANG=en 은 한국어 시스템에서도 영어")
expectEqual(Language.resolve(environment: ["PULSE_LANG": "ko"], preferredLanguages: ["en-US"]), .ko,
            "언어: PULSE_LANG=ko 는 영어 시스템에서도 한국어")
expectEqual(Language.resolve(environment: ["PULSE_LANG": "EN"], preferredLanguages: ["ko-KR"]), .en,
            "언어: PULSE_LANG 대소문자를 가리지 않는다")
expectEqual(Language.resolve(environment: ["PULSE_LANG": "fr"], preferredLanguages: ["en-US"]), .en,
            "언어: 모르는 PULSE_LANG 은 시스템 언어로 돌아간다")
expectEqual(Language.resolve(environment: [:], preferredLanguages: ["en-US"]), .en,
            "언어: 시스템 선호 언어가 en-US 면 영어")
expectEqual(Language.resolve(environment: [:], preferredLanguages: ["en"]), .en,
            "언어: 시스템 선호 언어가 en 이면 영어")
expectEqual(Language.resolve(environment: [:], preferredLanguages: ["ko-KR", "en-US"]), .ko,
            "언어: 첫 선호 언어가 한국어면 한국어")
expectEqual(Language.resolve(environment: [:], preferredLanguages: ["ja-JP"]), .ko,
            "언어: 영어가 아닌 시스템 언어는 한국어")
expectEqual(Language.resolve(environment: [:], preferredLanguages: []), .ko,
            "언어: 선호 언어가 없으면 한국어")

expectEqual(TimePhrase.elapsed(from: now.addingTimeInterval(-30), to: now), "just now", "영어 시간: 30초")
expectEqual(TimePhrase.elapsed(from: now.addingTimeInterval(-60), to: now), "1 minute", "영어 시간: 1분")
expectEqual(TimePhrase.elapsed(from: now.addingTimeInterval(-120), to: now), "2 minutes", "영어 시간: 2분")
expectEqual(TimePhrase.elapsed(from: now.addingTimeInterval(-3600), to: now), "1 hour", "영어 시간: 1시간")
expectEqual(TimePhrase.elapsed(from: now.addingTimeInterval(-7200), to: now), "2 hours", "영어 시간: 2시간")
expectEqual(TimePhrase.duration(from: now.addingTimeInterval(-10), to: now), "1 minute", "영어 시간: 10초는 1분")
expectEqual(TimePhrase.duration(from: now.addingTimeInterval(-720), to: now), "12 minutes", "영어 시간: 12분")
expectEqual(TimePhrase.relative(from: now.addingTimeInterval(-30), to: now), "just now", "영어 시간: 방금은 단위 없이")
expectEqual(TimePhrase.relative(from: now.addingTimeInterval(-420), to: now), "7 minutes ago", "영어 시간: 분 전")
expectEqual(TimePhrase.ago(from: now.addingTimeInterval(-1), to: now), "1 second ago", "영어 시간: 1초 전")
expectEqual(TimePhrase.ago(from: now.addingTimeInterval(-12), to: now), "12 seconds ago", "영어 시간: 12초 전")
expectEqual(TimePhrase.ago(from: now.addingTimeInterval(-3600), to: now), "1 hour ago", "영어 시간: 1시간 전")
expectEqual(TimePhrase.ago(from: now.addingTimeInterval(-86_400 * 3), to: now), "3 days ago", "영어 시간: 3일 전")

let enGroups = Grouping.group(SessionsResponse(sessions: allBuckets), now: now)
let enById = Dictionary(uniqueKeysWithValues: enGroups.items(for: .attention).map { ($0.sessionId, $0) })
    .merging(enGroups.items(for: .working).map { ($0.sessionId, $0) }) { a, _ in a }
    .merging(enGroups.items(for: .done).map { ($0.sessionId, $0) }) { a, _ in a }
expectEqual(enById["wait"]?.status, "Please grant permission", "영어 문구: wait 기본")
expectEqual(enById["idle"]?.status, "Waiting for your reply", "영어 문구: idle")
expectEqual(enById["stall"]?.status, "Background task for 7 minutes · npm test", "영어 문구: stall 백그라운드")
expectEqual(enById["working"]?.status, "Running for 3 minutes · 테스트 실행", "영어 문구: working")
expectEqual(enById["untracked"]?.status, "In progress", "영어 문구: untracked")
expectEqual(enById["done"]?.status, "Finished", "영어 문구: done")
expectEqual(enById["ended"]?.status, "Finished 5 minutes ago", "영어 문구: ended")

let enStallGroup = Grouping.group(
    SessionsResponse(sessions: [session("s", "stall", minutesAgo: 12)]),
    now: now
)
expectEqual(enStallGroup.attention.first?.status, "Working for 12 minutes · check if it's stuck",
            "영어 문구: stall 기본")
let enEndedRecent = Grouping.group(
    SessionsResponse(sessions: [session("e", "ended", minutesAgo: 0.5)]),
    now: now
)
expectEqual(enEndedRecent.done.first?.status, "Just finished", "영어 문구: ended 방금")

let enEtaOne = DisplayItem(
    session: Session(sessionId: "eta1", bucket: "working", since: now, eta: now.addingTimeInterval(60)),
    group: .working,
    now: now
)
expectEqual(enEtaOne.etaText, "~1 min left", "영어 문구: 남은 1분")
let enEtaThree = DisplayItem(
    session: Session(sessionId: "eta3", bucket: "working", since: now, eta: now.addingTimeInterval(180)),
    group: .working,
    now: now
)
expectEqual(enEtaThree.etaText, "~3 min left", "영어 문구: 남은 3분")
expectEqual(L10n.lockedAlertsGrouped, "Locked-screen alerts arrive as one card", "영어 문구: 잠긴 사이 알림 묶음")
expectEqual(L10n.shortcutHint, "Once: popover · Twice: floating panel", "영어 문구: 단축키 설명")
expectEqual(L10n.reduceTransparencyOn, "Reduce transparency is on, so Pulse uses a solid background instead of glass", "영어 문구: 투명도 줄이기 안내")
expectEqual(L10n.openDisplaySettings, "Open Settings", "영어 문구: 설정 열기")
expectEqual(L10n.starOnGitHub, "Star on GitHub", "영어 문구: GitHub 별 버튼")
expectEqual(L10n.progressPageNotOpened, "Could not open the progress page", "영어 문구: 진행 페이지 열기 실패")
expectEqual(L10n.noReplySession, "No session is waiting for your reply", "영어 문구: 답할 세션 없음")
expectEqual(L10n.noDoneSession, "No finished session to check", "영어 문구: 열 완료 세션 없음")
expectEqual(L10n.unknownOption("--x"), "pulse: unknown option --x", "영어 문구: 알 수 없는 옵션")
expectEqual(L10n.usage.hasPrefix("Usage: pulse [option]"), true, "영어 문구: 도움말 첫 줄")
let enEmptyTitled = DisplayItem(session: Session(sessionId: "untitled", bucket: "working"), group: .working, now: now)
expectEqual(enEmptyTitled.title, "Untitled session", "영어 문구: 제목 없는 세션")

expectEqual(DisplayGroup.attention.title, "Needs attention", "영어 그룹: 확인 필요")
expectEqual(DisplayGroup.working.title, "In progress", "영어 그룹: 진행중")
expectEqual(DisplayGroup.done.title, "Done", "영어 그룹: 완료")
expectEqual(SessionFilter.all.title, "All", "영어 필터: 전체")
expectEqual(SessionFilter.title(for: .attention), "Needs attention", "영어 필터: 확인 필요")
expectEqual(SessionFilter.title(for: .working), "In progress", "영어 필터: 진행 중")
expectEqual(SessionFilter.title(for: .done), "Done", "영어 필터: 완료")
expectEqual(manyDone.doneOverflowText, "2 more", "영어 그룹: 남은 완료 개수")

expectEqual(HeaderBadge.label(for: .attention, count: 1), "1 waiting", "영어 머리글 뱃지: 확인")
expectEqual(HeaderBadge.label(for: .working, count: 4), "4 running", "영어 머리글 뱃지: 진행")
expectEqual(HeaderBadge.label(for: .done, count: 3), "3 done", "영어 머리글 뱃지: 완료")
expectEqual(CardDeck.headerText(attention: 1, done: 3), "1 waiting · 3 done", "영어 카드: 머리글 확인·끝남")
expectEqual(CardDeck.headerText(attention: 0, done: 2), "2 done", "영어 카드: 머리글 끝남만")

expectEqual(RowText.waiting(since: now.addingTimeInterval(-60), now: now), "Waiting for 1 minute",
            "영어 행 문구: 기다린 1분")
expectEqual(RowText.waiting(since: now.addingTimeInterval(-720), now: now), "Waiting for 12 minutes",
            "영어 행 문구: 기다린 12분")

expectEqual(StepWindow.trailingText(trailingSteps, index: 1), "대기 · Last", "영어 단계 꼬리: 마지막 남은 단계")
expectEqual(StepWindow.trailingText([ChecklistStep(label: "a", state: .left)], index: 0), "Last",
            "영어 단계 꼬리: sub 가 없는 마지막")
expectEqual(StepWindow.headText(headNoTime, window: headWindow, timeZone: seoul), "4 earlier steps done",
            "영어 단계 머리: 앞 단계 완료")
expectEqual(StepWindow.headText(mixedHead, window: StepWindow.make(mixedHead.map(\.state)), timeZone: seoul),
            "4 earlier steps · 3 done", "영어 단계 머리: 완료 아닌 단계가 섞이면 완료 수")
expectEqual(
    StepWindow.headText(Array(repeating: ChecklistStep(label: "x", state: .left), count: 9),
                       window: startWindow, timeZone: seoul),
    "Show all 9 steps",
    "영어 단계 머리: 앞이 비면 전체 보기"
)
expectEqual(Checklist.parse(Data("{\"items\":[{}]}".utf8))?.first?.label, "Step 1",
            "영어 체크리스트: 이름이 없으면 순번")

expectEqual(SessionActivity(compactions: 1, backgroundTasks: 2,
                            lastTool: LastTool(name: "Bash", at: utcDate(2026, 10, 20, 11, 59, 48)))
        .line(now: now),
    "1 compaction · 2 in background · Bash 12 seconds ago", "영어 활동 줄: 세 값을 가운뎃점으로 잇는다")
expectEqual(SessionActivity(compactions: 2, backgroundTasks: 0, lastTool: LastTool(name: "Read", at: nil))
        .line(now: now), "2 compactions · Read", "영어 활동 줄: 복수형과 도구 이름만")

expectEqual(NotificationButton.openInOrca.title, "Open in Orca", "영어 알림 스타일: Orca 열기 제목")
expectEqual(NotificationButton.snooze.title, "Snooze 10 min", "영어 알림 스타일: 10분 더 제목")
expectEqual(L10n.durationSoFar(minutes: 12), "12m", "영어 카드 메타: 경과 분")
expectEqual(L10n.durationSoFar(minutes: 125), "2h", "영어 카드 메타: 경과 시간")
expectEqual(TimePhrase.soFar(from: now.addingTimeInterval(-20), to: now), "1m", "영어 카드 메타: 1분 미만은 1m")
expectEqual(NotificationButton.acknowledge.title, "Dismiss", "영어 알림 스타일: 확인 제목")
expectEqual(AttentionNotifier.titlePrefix, "Needs your attention", "영어 알림: 확인 필요 제목 접두어")
expectEqual(DoneNotifier.titlePrefix, "Finished", "영어 알림: 끝남 제목 접두어")

expectEqual(CardText.doneTrail(runDuration: 840, finishedAt: now, now: now), "Took 14 minutes",
            "영어 카드 문구: 걸린 시간")
expectEqual(CardText.doneTrail(runDuration: nil, finishedAt: now.addingTimeInterval(-660), now: now),
            "11 minutes ago", "영어 카드 문구: 끝난 뒤 흐른 시간")
expectEqual(CardText.doneMeta(title: "pulse-main", runDuration: 60), "pulse-main · Finished · took 1 minute",
            "영어 카드 문구: 2행")
expectEqual(CardText.doneMeta(title: "pulse-main", runDuration: nil), "pulse-main · Finished",
            "영어 카드 문구: 2행, 걸린 시간 모름")
expectEqual(CardText.awayTitle, "While you were away", "영어 자리 비움: 제목")
expectEqual(CardText.awayHeadline(attention: 1, done: 0), "1 session is waiting", "영어 자리 비움: 한 세션 기다림")
expectEqual(CardText.awayHeadline(attention: 2, done: 0), "2 sessions are waiting", "영어 자리 비움: 여러 세션 기다림")
expectEqual(CardText.awayHeadline(attention: 2, done: 3), "2 sessions are waiting", "영어 자리 비움: 둘 다 있으면 막힘을 센다")
expectEqual(CardText.awayHeadline(attention: 0, done: 3), "3 sessions finished", "영어 자리 비움: 끝남만 있으면 끝났다")
expectEqual(CardText.awayDetail(attention: 2, done: 0), "Click to open the list", "영어 자리 비움: 막힘만 있으면 안내만")
expectEqual(CardText.awayDetail(attention: 2, done: 3), "3 finished · click to open the list",
            "영어 자리 비움: 끝남 수도 센다")
expectEqual(CardText.awayMeta(attention: 2, done: 3), "While you were away · 3 finished · click to open the list",
            "영어 자리 비움: 2행 메타")
expectEqual(CardText.awayMeta(attention: 2, done: 0), "While you were away · Click to open the list",
            "영어 자리 비움: 끝남이 없으면 안내만")

expectEqual(LocalSessions.nowActionLabel(toolName: "Edit", input: ["file_path": "/a/b/App.swift"]),
            "Edit file · App.swift", "영어 현재 동작: Edit")
expectEqual(LocalSessions.nowActionLabel(toolName: "Edit", input: [:]), "Edit file",
            "영어 현재 동작: 파일 이름이 없으면 동작만")
expectEqual(LocalSessions.nowActionLabel(toolName: "Read", input: ["file_path": "/a/b/App.swift"]),
            "Read file · App.swift", "영어 현재 동작: Read")
expectEqual(LocalSessions.nowActionLabel(toolName: "Grep", input: [:]), "Search", "영어 현재 동작: Grep")
expectEqual(LocalSessions.nowActionLabel(toolName: "WebFetch", input: [:]), "Web fetch", "영어 현재 동작: WebFetch")
expectEqual(localSession(status: "waiting", waitingFor: "permission prompt").message,
            "Waiting for permission approval", "영어 상태 표: 권한 대기 문구")
expectEqual(localSession(status: "waiting", waitingFor: "input needed").message,
            "Waiting for your reply", "영어 상태 표: 입력 대기 문구")

L10n.language = .ko
expectEqual(TimePhrase.soFar(from: now.addingTimeInterval(-720), to: now), "12분째", "카드 메타: 경과 분")
expectEqual(TimePhrase.soFar(from: now.addingTimeInterval(-7500), to: now), "2시간째", "카드 메타: 경과 시간")
expectEqual(TimePhrase.soFar(from: nil, to: now), nil, "카드 메타: 기준 시각 없음")
expectEqual(L10n.reduceTransparencyOn, "시스템의 투명도 줄이기가 켜져 있어 유리 대신 단색 배경으로 보여요", "문구: 투명도 줄이기 안내")
expectEqual(L10n.openDisplaySettings, "설정 열기", "문구: 설정 열기")
expectEqual(L10n.starOnGitHub, "Star on GitHub", "문구: GitHub 별 버튼은 한국어 화면에서도 영어")
expectEqual(L10n.progressPageNotCreated.hasPrefix("진행 페이지를 만들지 못했어요"), true, "문구: 진행 페이지 생성 실패")
expectEqual(L10n.progressPageNotOpened, "진행 페이지를 열지 못했어요", "문구: 진행 페이지 열기 실패")
expectEqual(L10n.noReplySession, "답을 기다리는 세션이 없어요", "문구: 답할 세션 없음")
expectEqual(L10n.noDoneSession, "확인할 완료 세션이 없어요", "문구: 열 완료 세션 없음")
expectEqual(L10n.unknownOption("--x"), "pulse: 알 수 없는 옵션 --x", "문구: 알 수 없는 옵션")
expectEqual(L10n.usage.contains("--help"), true, "문구: 도움말에 --help")

func procArgs(argc: Int32, _ parts: [String], padding: Int = 3) -> Data {
    var data = withUnsafeBytes(of: argc.littleEndian) { Data($0) }
    data.append(contentsOf: Array(parts[0].utf8) + [0] + [UInt8](repeating: 0, count: padding))
    for part in parts.dropFirst() { data.append(contentsOf: Array(part.utf8) + [0]) }
    data.append(0)
    return data
}
let orcaArgs = procArgs(argc: 2, ["/bin/claude", "claude", "--resume", "PWD=/a", "ORCA_TERMINAL_HANDLE=term_1", "X=1"])
expectEqual(ProcessEnvironment.value("ORCA_TERMINAL_HANDLE", inProcArgs: orcaArgs), "term_1", "프로세스 환경: Orca 핸들")
expectEqual(ProcessEnvironment.value("PWD", inProcArgs: orcaArgs), "/a", "프로세스 환경: 첫 변수")
expectEqual(ProcessEnvironment.value("ORCA_TERMINAL", inProcArgs: orcaArgs), nil, "프로세스 환경: 이름 앞부분만 같으면 아님")
expectEqual(ProcessEnvironment.value("ORCA_TERMINAL_HANDLE", inProcArgs: procArgs(argc: 3, ["/bin/claude", "claude", "ORCA_TERMINAL_HANDLE=arg", "-c", "X=1"])), nil, "프로세스 환경: 인자는 변수로 읽지 않음")
expectEqual(ProcessEnvironment.value("ORCA_TERMINAL_HANDLE", inProcArgs: procArgs(argc: 1, ["/bin/zsh", "zsh", "PWD=/a"])), nil, "프로세스 환경: Orca 밖에서 띄운 프로세스")
expectEqual(ProcessEnvironment.value("ORCA_TERMINAL_HANDLE", inProcArgs: Data([1, 0])), nil, "프로세스 환경: 잘린 버퍼")
expectEqual(ProcessEnvironment.value("ORCA_TERMINAL_HANDLE", inProcArgs: procArgs(argc: 9, ["/bin/claude", "claude"])), nil, "프로세스 환경: 인자 수보다 짧은 버퍼")
expectEqual(
    LocalSessions.makeSession(
        record: LocalSessionRecord(pid: 1, sessionId: "s", cwd: "/a", status: "idle"),
        summary: TranscriptSummary(),
        now: now,
        orcaTerminal: "term_1"
    ).orcaTerminal,
    "term_1",
    "로컬 세션: 환경 변수 핸들이 있으면 cwd 매칭 대신 핸들로 이동"
)

let herdrProcArgs = procArgs(
    argc: 1,
    [
        "/bin/claude", "claude", "HERDR_ENV=1", "HERDR_PANE_ID=w1:p30", "HERDR_TAB_ID=w1:t2",
        "HERDR_WORKSPACE_ID=w1", "HERDR_SOCKET_PATH=/tmp/herdr.sock",
    ]
)
expectEqual(
    Multiplexer.pane(inProcArgs: herdrProcArgs),
    MultiplexerPane(
        kind: .herdr, paneId: "w1:p30", socketPath: "/tmp/herdr.sock",
        workspaceId: "w1", tabId: "w1:t2"
    ),
    "멀티플렉서: herdr 패널 감지"
)
expectEqual(
    Multiplexer.pane(inProcArgs: procArgs(
        argc: 1,
        ["/bin/claude", "claude", "TMUX=/tmp/tmux-501/default,123,0", "TMUX_PANE=%3"]
    )),
    MultiplexerPane(kind: .tmux, paneId: "%3", socketPath: "/tmp/tmux-501/default"),
    "멀티플렉서: tmux 패널 감지"
)
expectEqual(
    Multiplexer.pane(inProcArgs: procArgs(
        argc: 1,
        ["/bin/claude", "claude", "HERDR_PANE_ID=w1:p30", "TMUX=/tmp/s,1,0", "TMUX_PANE=%3"]
    )),
    MultiplexerPane(kind: .tmux, paneId: "%3", socketPath: "/tmp/s"),
    "멀티플렉서: 둘 다 있으면 tmux"
)
expectEqual(
    Multiplexer.pane(inProcArgs: procArgs(argc: 1, ["/bin/claude", "claude", "PWD=/a"])),
    nil,
    "멀티플렉서: 둘 다 없으면 없음"
)
expectEqual(Multiplexer.socketPath(fromTMUX: "/tmp/s,123,0"), "/tmp/s", "멀티플렉서: TMUX 소켓 파싱")
expectEqual(Multiplexer.socketPath(fromTMUX: ",123,0"), nil, "멀티플렉서: 빈 소켓 경로")
expectEqual(Multiplexer.socketPath(fromTMUX: nil), nil, "멀티플렉서: TMUX 없음")
expectEqual(
    ProcessEnvironment.arguments(inProcArgs: procArgs(
        argc: 3, ["/bin/herdr", "herdr", "session", "attach", "X=1"]
    )),
    ["herdr", "session", "attach"],
    "프로세스 인자: argv 추출"
)
let herdrClientCases: [(arguments: [String], expected: Bool)] = [
    (["herdr"], true),
    (["/opt/homebrew/bin/herdr"], true),
    (["herdr", "--session", "a"], true),
    (["herdr", "session", "attach", "a"], true),
    (["herdr", "server"], false),
    (["herdr", "pane", "list"], false),
    (["herdr", "session", "list"], false),
    (["tmux"], false),
    ([], false),
]
for testCase in herdrClientCases {
    expectEqual(
        Multiplexer.isHerdrClient(arguments: testCase.arguments),
        testCase.expected,
        "멀티플렉서: herdr 클라이언트 판정 \(testCase.arguments)"
    )
}

let herdrSessionNameCases: [(arguments: [String], expected: String?)] = [
    (["herdr"], nil),
    (["/opt/homebrew/bin/herdr", "--session", "a"], "a"),
    (["herdr", "session", "attach", "b"], "b"),
    (["herdr", "--session"], nil),
    (["herdr", "server"], nil),
]
for testCase in herdrSessionNameCases {
    expectEqual(
        Multiplexer.herdrSessionName(arguments: testCase.arguments),
        testCase.expected,
        "멀티플렉서: 세션 이름 \(testCase.arguments)"
    )
}

let herdrListJSON = """
{"sessions":[{"default":true,"name":"default","running":true,"session_dir":"/Users/x/.config/herdr","socket_path":"/Users/x/.config/herdr/herdr.sock"},{"default":false,"name":"pulse-test","running":true,"session_dir":"/Users/x/.config/herdr/sessions/pulse-test","socket_path":"/Users/x/.config/herdr/sessions/pulse-test/herdr.sock"}]}
"""
let parsedSessions = Multiplexer.herdrSessions(fromListJSON: herdrListJSON)
expectEqual(parsedSessions?.count, 2, "멀티플렉서: 세션 목록 개수")
expectEqual(parsedSessions?.last?.name, "pulse-test", "멀티플렉서: 세션 목록 이름")
expectEqual(parsedSessions?.last?.isDefault, false, "멀티플렉서: 세션 목록 기본 여부")
expectEqual(Multiplexer.herdrSessions(fromListJSON: "not json"), nil, "멀티플렉서: 세션 목록 JSON 아님")
expectEqual(Multiplexer.herdrSessions(fromListJSON: #"{"x":1}"#), nil, "멀티플렉서: 세션 목록 sessions 없음")

let defaultSession = HerdrSession(
    name: "default", isDefault: true, socketPath: "/Users/x/.config/herdr/herdr.sock"
)
let testSession = HerdrSession(
    name: "pulse-test",
    isDefault: false,
    socketPath: "/Users/x/.config/herdr/sessions/pulse-test/herdr.sock"
)
let herdrSessionList = [defaultSession, testSession]
expectEqual(
    Multiplexer.herdrSession(
        forSocket: "/Users/x/.config/herdr/sessions/pulse-test/herdr.sock", in: herdrSessionList
    )?.name,
    "pulse-test",
    "멀티플렉서: 소켓으로 세션 찾기"
)
expectEqual(
    Multiplexer.herdrSession(
        forSocket: "/Users/x/.config/herdr/sessions/pulse-test/../pulse-test/herdr.sock",
        in: herdrSessionList
    )?.name,
    "pulse-test",
    "멀티플렉서: 소켓 경로 정규화"
)
expectEqual(
    Multiplexer.herdrSession(
        forSocket: "~/.config/herdr/herdr.sock",
        in: [HerdrSession(
            name: "default",
            isDefault: true,
            socketPath: NSHomeDirectory() + "/.config/herdr/herdr.sock"
        )]
    )?.name,
    "default",
    "멀티플렉서: 소켓 경로의 ~ 펼침"
)
expectEqual(
    Multiplexer.herdrSession(forSocket: "/nope.sock", in: herdrSessionList),
    nil,
    "멀티플렉서: 맞는 세션 없음"
)

let herdrAttachCases: [(arguments: [String], session: HerdrSession, expected: Bool)] = [
    (["herdr"], defaultSession, true),
    (["herdr", "--session", "pulse-test"], defaultSession, false),
    (["herdr", "--session", "pulse-test"], testSession, true),
    (["herdr", "session", "attach", "pulse-test"], testSession, true),
    (["herdr"], testSession, false),
    (["herdr", "pane", "list"], testSession, false),
]
for testCase in herdrAttachCases {
    expectEqual(
        Multiplexer.herdrClient(arguments: testCase.arguments, attachesTo: testCase.session),
        testCase.expected,
        "멀티플렉서: 세션에 붙는 클라이언트 \(testCase.arguments)"
    )
}

func focusRequestObject(_ line: String) -> [String: Any]? {
    guard let data = line.data(using: .utf8),
          let object = try? JSONSerialization.jsonObject(with: data) else {
        return nil
    }
    return object as? [String: Any]
}

let focusLines = Multiplexer.focusRequestLines(workspaceId: "w1", tabId: "w1:t2", paneId: "w1:p30")
expectEqual(focusLines.count, 3, "멀티플렉서: 포커스 요청 세 줄")
expectEqual(focusRequestObject(focusLines[0])?["method"] as? String, "workspace.focus", "멀티플렉서: 첫 요청은 workspace")
expectEqual(focusRequestObject(focusLines[1])?["method"] as? String, "tab.focus", "멀티플렉서: 둘째 요청은 tab")
expectEqual(focusRequestObject(focusLines[2])?["method"] as? String, "pane.focus", "멀티플렉서: 셋째 요청은 pane")
expectEqual(focusRequestObject(focusLines[2])?["id"] as? String, "pulse-pane.focus", "멀티플렉서: 요청 id 접두사")
expectEqual(
    (focusRequestObject(focusLines[2])?["params"] as? [String: String])?["pane_id"],
    "w1:p30",
    "멀티플렉서: pane 요청 값"
)
expectEqual(
    Multiplexer.focusRequestLines(workspaceId: nil, tabId: nil, paneId: "w1:p30").count,
    1,
    "멀티플렉서: id 가 없으면 건너뜀"
)
expectEqual(Multiplexer.isSuccessResponse(#"{"id":"x","result":{}}"#), true, "멀티플렉서: 결과 응답")
expectEqual(Multiplexer.isSuccessResponse(#"{"id":"x","error":{"message":"no"}}"#), false, "멀티플렉서: 오류 응답")
expectEqual(Multiplexer.isSuccessResponse(#"{"id":"x"}"#), false, "멀티플렉서: result 없는 응답")
expectEqual(Multiplexer.isSuccessResponse("not json"), false, "멀티플렉서: 깨진 응답")
expectEqual(
    Multiplexer.host(inProcArgs: procArgs(
        argc: 1,
        ["/bin/herdr", "herdr", "ORCA_TERMINAL_HANDLE=term_1", "__CFBundleIdentifier=com.stablyai.orca"]
    )),
    .orca("term_1"),
    "멀티플렉서 호스트: Orca 앱이면 터미널 핸들"
)
expectEqual(
    Multiplexer.host(inProcArgs: procArgs(
        argc: 1,
        ["/bin/herdr", "herdr", "ORCA_TERMINAL_HANDLE=term_1", "__CFBundleIdentifier=com.example.term"]
    )),
    .app("com.example.term"),
    "멀티플렉서 호스트: 다른 앱이 물려받은 Orca 핸들은 무시"
)
expectEqual(
    Multiplexer.host(inProcArgs: procArgs(argc: 1, ["/bin/herdr", "herdr", "ORCA_TERMINAL_HANDLE=term_1"])),
    .orca("term_1"),
    "멀티플렉서 호스트: 번들 id 없이 핸들만"
)
expectEqual(
    Multiplexer.host(inProcArgs: procArgs(
        argc: 1, ["/bin/herdr", "herdr", "__CFBundleIdentifier=com.example.term"]
    )),
    .app("com.example.term"),
    "멀티플렉서 호스트: 번들 id"
)
expectEqual(
    Multiplexer.host(inProcArgs: procArgs(argc: 1, ["/bin/herdr", "herdr", "PWD=/a"])),
    nil,
    "멀티플렉서 호스트: 알 수 없음"
)

let multiplexerPane = MultiplexerPane(kind: .tmux, paneId: "%3", socketPath: "/tmp/t")
expectEqual(
    SessionClick.resolve(orcaTerminal: "term_1", cwd: "/a", multiplexer: multiplexerPane),
    .multiplexer(multiplexerPane),
    "클릭: 멀티플렉서가 Orca·cwd 보다 먼저"
)
expectEqual(
    SessionClick.resolve(orcaTerminal: "term_1", cwd: "/a"),
    .orca("term_1"),
    "클릭: 멀티플렉서가 없으면 Orca"
)
expectEqual(
    DisplayItem(
        session: Session(sessionId: "m", bucket: "working", cwd: "/a", multiplexer: multiplexerPane),
        group: .working,
        now: now
    ).clickAction,
    .multiplexer(multiplexerPane),
    "화면 행: 멀티플렉서 패널로 이동"
)
expectEqual(
    LocalSessions.makeSession(
        record: LocalSessionRecord(pid: 1, sessionId: "s", cwd: "/a", status: "idle"),
        summary: TranscriptSummary(),
        now: now,
        multiplexer: multiplexerPane
    ).multiplexer,
    multiplexerPane,
    "로컬 세션: 멀티플렉서 패널 전달"
)
let multiplexerJSON = #"""
{"sessionId":"s1","bucket":"working","multiplexer":{"kind":"herdr","paneId":"w1:p30","socketPath":"/tmp/h.sock","tabId":"w1:t2","workspaceId":"w1"}}
"""#
expectEqual(
    (try? JSONDecoder().decode(Session.self, from: Data(multiplexerJSON.utf8)))?.multiplexer,
    MultiplexerPane(
        kind: .herdr, paneId: "w1:p30", socketPath: "/tmp/h.sock",
        workspaceId: "w1", tabId: "w1:t2"
    ),
    "세션 JSON: multiplexer 읽기"
)
let plainSessionJSON = #"{"sessionId":"s2","bucket":"working"}"#
expectEqual(
    (try? JSONDecoder().decode(Session.self, from: Data(plainSessionJSON.utf8)))?.multiplexer,
    nil,
    "세션 JSON: multiplexer 가 없으면 nil"
)
expectEqual(
    L10n.multiplexerBadgeHelp("herdr").contains("herdr"),
    true,
    "문구: 배지 툴팁에 kind"
)
expectEqual(
    L10n.multiplexerPanelMissing("tmux").contains("tmux"),
    true,
    "문구: 패널 없음에 kind"
)
expectEqual(
    L10n.multiplexerClientMissing("herdr").contains("herdr"),
    true,
    "문구: 클라이언트 없음에 kind"
)
expectEqual(
    L10n.multiplexerHostUnknown("herdr").contains("herdr"),
    true,
    "문구: 호스트 모름에 kind"
)
expectEqual(
    L10n.multiplexerTimedOut("tmux").contains("tmux"),
    true,
    "문구: 응답 없음에 kind"
)
expectEqual(
    L10n.multiplexerExecutableMissing.hasPrefix("tmux"),
    true,
    "문구: 실행 파일 없음"
)

expectEqual(LaunchCommand.parse(["pulse"]), .run, "실행 인자: 없으면 앱 실행")
expectEqual(LaunchCommand.parse(["pulse", "--version"]), .version, "실행 인자: --version")
expectEqual(LaunchCommand.parse(["pulse", "--help"]), .help, "실행 인자: --help")
expectEqual(LaunchCommand.parse(["pulse", "-h"]), .help, "실행 인자: -h")
expectEqual(LaunchCommand.parse(["pulse", "--bogus"]), .unknown("--bogus"), "실행 인자: 모르는 -- 옵션")
expectEqual(LaunchCommand.parse(["pulse", "-theme", "light"]), .run, "실행 인자: 인자 도메인은 앱에 넘김")
expectEqual(LaunchCommand.parse(["pulse", "-psn_0_12345"]), .run, "실행 인자: Finder 의 -psn 인자는 무시")
expectEqual(LaunchCommand.parse(["pulse", "-panelWidth", "440", "--version"]), .version, "실행 인자: 인자 도메인 뒤의 --version")

// MARK: - 페이지 알림

let fullPageJSON = #"""
{"version":1,"page_id":"p1","worktree":"repo::/Users/x/My Repo","url":"file:///tmp/a.html","label":"배포 안내","created_at":"2026-10-30T08:08:04Z","terminal_handle":"h1","session_id":"s1","session_name":"alpha"}
"""#
let fullPage = PageAlerts.parse(data: Data(fullPageJSON.utf8), fileName: "full.json")
expectEqual(fullPage?.version, 1, "페이지: version")
expectEqual(fullPage?.pageId, "p1", "페이지: page_id")
expectEqual(fullPage?.worktree, "repo::/Users/x/My Repo", "페이지: worktree 의 공백")
expectEqual(fullPage?.url, "file:///tmp/a.html", "페이지: url")
expectEqual(fullPage?.label, "배포 안내", "페이지: label")
expectEqual(fullPage?.terminalHandle, "h1", "페이지: terminal_handle")
expectEqual(fullPage?.sessionId, "s1", "페이지: session_id")
expectEqual(fullPage?.sessionName, "alpha", "페이지: session_name")
expectEqual(fullPage?.fileName, "full.json", "페이지: fileName")
expect(fullPage?.createdAt == utcDate(2026, 10, 30, 8, 8, 4), "페이지: created_at")

let minimalPageJSON = #"""
{"page_id":"p2","worktree":"repo::/a","url":"file:///b.html","label":"둘째","created_at":"2026-10-30T08:09:04Z"}
"""#
let minimalPage = PageAlerts.parse(data: Data(minimalPageJSON.utf8), fileName: "minimal.json")
expectEqual(minimalPage?.version, 1, "페이지: version 이 없으면 1")
expectEqual(minimalPage?.terminalHandle, nil, "페이지: terminal_handle 없음")
expectEqual(minimalPage?.sessionId, nil, "페이지: session_id 없음")
expectEqual(minimalPage?.sessionName, nil, "페이지: session_name 없음")
expectEqual(PageAlerts.parse(
    data: Data(#"{"page_id":"p3","worktree":"w","url":"file:///x"}"#.utf8),
    fileName: "no-label.json"
), nil, "페이지: label 이 없으면 읽지 못한 파일")
expectEqual(PageAlerts.parse(
    data: Data(#"{"page_id":"p4","worktree":"w","url":"file:///x","label":"L"}"#.utf8),
    fileName: "no-date.json"
), nil, "페이지: created_at 이 없으면 읽지 못한 파일")
expectEqual(
    PageAlerts.parse(data: Data("{ nope".utf8), fileName: "broken.json"),
    nil,
    "페이지: 깨진 JSON 은 읽지 못한 파일"
)

let pageDirectoryPath = (NSTemporaryDirectory() as NSString)
    .appendingPathComponent("pulse-pages-\(UUID().uuidString)")
try? FileManager.default.createDirectory(atPath: pageDirectoryPath, withIntermediateDirectories: true)
func writePageFile(_ name: String, _ contents: String) {
    try? contents.write(
        toFile: (pageDirectoryPath as NSString).appendingPathComponent(name),
        atomically: true,
        encoding: .utf8
    )
}
writePageFile("late.json", #"""
{"page_id":"p9","worktree":"w","url":"file:///late.html","label":"늦은","created_at":"2026-10-30T09:00:00Z"}
"""#)
writePageFile("early.json", #"""
{"page_id":"p1","worktree":"w","url":"file:///early.html","label":"이른","created_at":"2026-10-30T07:00:00Z"}
"""#)
writePageFile(".hidden.json", #"""
{"page_id":"p5","worktree":"w","url":"file:///hidden.html","label":"숨김","created_at":"2026-10-30T06:00:00Z"}
"""#)
writePageFile("draft.json.tmp", #"""
{"page_id":"p6","worktree":"w","url":"file:///draft.html","label":"임시","created_at":"2026-10-30T06:00:00Z"}
"""#)
writePageFile("missing.json", #"{"page_id":"p7"}"#)
writePageFile("broken.json", "{")

let loadedPages = PageAlerts.load(directory: URL(fileURLWithPath: pageDirectoryPath))
expectEqual(loadedPages.alerts.map(\.fileName), ["early.json", "late.json"], "페이지: 오래된 순 정렬, 숨김·tmp 무시")
expectEqual(loadedPages.unreadableFiles, ["broken.json", "missing.json"], "페이지: 읽지 못한 파일 목록")
expectEqual(loadedPages.directoryUnreadable, false, "페이지: 디렉터리 읽음")

let missingPages = PageAlerts.load(
    directory: URL(fileURLWithPath: pageDirectoryPath + "-missing")
)
expectEqual(missingPages.alerts.count, 0, "페이지: 디렉터리가 없으면 0건")
expectEqual(missingPages.unreadableFiles.count, 0, "페이지: 디렉터리가 없으면 오류 아님")
expectEqual(missingPages.directoryUnreadable, false, "페이지: 없는 디렉터리는 읽기 실패가 아니다")

let sameTimeJSON = #"""
{"page_id":"%PAGE_ID%","worktree":"w","url":"file:///x.html","label":"%LABEL%","created_at":"2026-10-30T08:00:00Z"%EXTRA%}
"""#
func pageAlert(_ pageId: String, _ label: String, _ extra: String, fileName: String) -> PageAlert? {
    let json = sameTimeJSON
        .replacingOccurrences(of: "%PAGE_ID%", with: pageId)
        .replacingOccurrences(of: "%LABEL%", with: label)
        .replacingOccurrences(of: "%EXTRA%", with: extra)
    return PageAlerts.parse(data: Data(json.utf8), fileName: fileName)
}
let pageItem = DisplayItem(
    session: Session(sessionId: "s1", bucket: "working", orcaTerminal: "h1"),
    group: .working,
    now: utcDate(2026, 10, 30)
)
let matchAlerts = [
    pageAlert("m2", "둘째 페이지", #","session_id":"s1","terminal_handle":"h1""#, fileName: "m2.json"),
    pageAlert("m1", "첫 페이지", #","session_id":"s1""#, fileName: "m1.json"),
    pageAlert("m3", "셋째 페이지", #","terminal_handle":"h1""#, fileName: "m3.json"),
    pageAlert("m4", "다른 세션", #","session_id":"s2","terminal_handle":"h1""#, fileName: "m4.json"),
    pageAlert("m5", "다른 터미널", #","terminal_handle":"h2""#, fileName: "m5.json"),
].compactMap { $0 }
let matchedPages = PageAlerts.alerts(for: pageItem, in: matchAlerts)
expectEqual(matchedPages.map(\.pageId), ["m1", "m2", "m3"], "페이지: session_id 우선, 없으면 terminal_handle")
expectEqual(PageAlerts.rowText(for: matchedPages), "첫 페이지 +2", "페이지: 행 문구")
expectEqual(PageAlerts.rowText(for: [matchedPages[0]]), "첫 페이지", "페이지: 한 장이면 문구만")
expectEqual(PageAlerts.tabTarget(in: matchAlerts)?.pageId, "m1", "페이지: Tab 대상은 가장 오래된 항목")
expectEqual(PageAlerts.tabTarget(in: [])?.pageId, nil, "페이지: 비면 Tab 대상 없음")

func pageAlertAt(
    _ pageId: String,
    _ label: String,
    worktree: String,
    url: String,
    createdAt: String,
    fileName: String
) -> PageAlert? {
    let json = #"""
    {"page_id":"\#(pageId)","worktree":"\#(worktree)","url":"\#(url)","label":"\#(label)","created_at":"\#(createdAt)","session_id":"s1"}
    """#
    return PageAlerts.parse(data: Data(json.utf8), fileName: fileName)
}
let samePageAlerts = [
    pageAlertAt("old", "오래된 페이지", worktree: "w1", url: "file:///same.html",
                createdAt: "2026-10-30T07:00:00Z", fileName: "old.json"),
    pageAlertAt("new", "새 페이지", worktree: "w1", url: "file:///same.html",
                createdAt: "2026-10-30T09:00:00Z", fileName: "new.json"),
    pageAlertAt("other-wt", "다른 작업트리", worktree: "w2", url: "file:///same.html",
                createdAt: "2026-10-30T08:00:00Z", fileName: "other-wt.json"),
    pageAlertAt("other-url", "다른 주소", worktree: "w1", url: "file:///other.html",
                createdAt: "2026-10-30T08:00:00Z", fileName: "other-url.json"),
].compactMap { $0 }
let dedupedPages = PageAlerts.sorted(PageAlerts.merged(samePageAlerts))
expectEqual(dedupedPages.count, 3, "페이지 합치기: 같은 worktree+url 만 하나로")
let mergedSamePage = dedupedPages.first { $0.worktree == "w1" && $0.url == "file:///same.html" }
expectEqual(mergedSamePage?.pageId, "new", "페이지 합치기: 대표는 가장 최근 page_id")
expectEqual(mergedSamePage?.label, "새 페이지", "페이지 합치기: 대표의 label")
expectEqual(mergedSamePage?.fileNames, ["old.json", "new.json"], "페이지 합치기: fileNames 는 그룹 전부")
expect(mergedSamePage?.oldestCreatedAt == utcDate(2026, 10, 30, 7, 0, 0),
       "페이지 합치기: 정렬 시각은 그룹에서 가장 오래된 created_at")
expectEqual(dedupedPages.first?.pageId, "new", "페이지 합치기: 대표가 최신이어도 오래 기다린 그룹이 먼저")
expectEqual(PageAlerts.tabTarget(in: dedupedPages)?.pageId, "new", "페이지 합치기: Tab 대상도 가장 오래된 그룹")
expectEqual(
    PageAlerts.rowText(for: PageAlerts.alerts(for: pageItem, in: dedupedPages)),
    "새 페이지 +2",
    "페이지 합치기: 행 문구의 +N 은 합친 뒤 개수"
)

expectEqual(
    PageAlerts.directory(environment: ["PULSE_PAGES_DIR": "/tmp/pulse-pages"]).path,
    "/tmp/pulse-pages",
    "페이지: PULSE_PAGES_DIR 경로"
)
let defaultPagePath = ("~/.pulse/pages" as NSString).expandingTildeInPath
expectEqual(PageAlerts.directory(environment: [:]).path, defaultPagePath, "페이지: 기본 디렉터리")
expectEqual(PageAlerts.directory(environment: ["PULSE_PAGES_DIR": " "]).path, defaultPagePath,
            "페이지: 빈 PULSE_PAGES_DIR 은 기본값")
expectEqual(
    PageAlerts.directory(environment: ["PULSE_PAGES_DIR": "~/pages"]).path,
    ("~/pages" as NSString).expandingTildeInPath,
    "페이지: 물결표 확장"
)

expectEqual(SafeLink.fileURL("file:///tmp/a%20b.html")?.path, "/tmp/a b.html", "페이지 링크: file 주소")
expectEqual(SafeLink.fileURL("https://example.com/a"), nil, "페이지 링크: https 는 기본 앱 경로가 아니다")
expectEqual(SafeLink.fileURL("javascript:alert(1)"), nil, "페이지 링크: 다른 스킴 거부")

try? FileManager.default.removeItem(atPath: pageDirectoryPath)

L10n.language = .ko
expectEqual(L10n.pagesToRead(3), "읽을 페이지 3", "문구: 읽을 페이지 수")
expectEqual(L10n.unreadablePageFile("x.json"), "읽지 못한 페이지 파일: x.json", "문구: 읽지 못한 파일")
expectEqual(L10n.pageOpenFailed, "Orca 에서 이 페이지를 열지 못했어요", "문구: 페이지 열기 실패")
expectEqual(L10n.dismissPage("배포"), "닫기: 배포", "문구: 페이지 닫기")
expectEqual(L10n.dismissAllPages, "모두 닫기", "문구: 페이지 모두 닫기")
expectEqual(L10n.dismissSessionPages, "이 세션 페이지 모두 닫기", "문구: 세션 페이지 모두 닫기")
expectEqual(L10n.shortcutOpen, "↩ 열기", "문구: 열기 힌트")
expectEqual(L10n.shortcutOrca, "⌥↩ Orca", "문구: Orca 힌트")
expectEqual(L10n.shortcutMultiplexer("herdr"), "⌥↩ herdr 패널", "문구: 멀티플렉서 힌트")
expectEqual(L10n.shortcutPage, "⇧↩ 페이지", "문구: 페이지 힌트")
expectEqual(L10n.shortcutDismiss, "⌫ 확인", "문구: 확인 힌트")
expectEqual(L10n.keyTab, "Tab", "문구: Tab 키캡")

L10n.language = .en
expectEqual(L10n.pagesToRead(1), "1 to read", "영어 페이지: 읽을 페이지 수")
expectEqual(L10n.unreadablePageFile("x.json"), "Unreadable page file: x.json", "영어 페이지: 읽지 못한 파일")
expectEqual(L10n.pageOpenFailed, "Couldn't open this page in Orca", "영어 페이지: 열기 실패")
expectEqual(L10n.dismissPage("Deploy"), "Dismiss: Deploy", "영어 페이지: 닫기")
expectEqual(L10n.dismissAllPages, "Dismiss all", "영어 페이지: 모두 닫기")
expectEqual(L10n.dismissSessionPages, "Dismiss this session's pages", "영어 페이지: 세션 페이지 모두 닫기")
expectEqual(L10n.shortcutPage, "⇧↩ Page", "영어 페이지: 페이지 힌트")
L10n.language = .ko

print("selftest: \(checks) checks, \(failures) failures")
exit(failures == 0 ? 0 : 1)
