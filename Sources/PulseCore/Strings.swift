import Foundation

/// 화면 문구의 언어. 기본은 한국어다.
public enum Language: String {
    case ko
    case en

    /// `PULSE_LANG=en|ko` 가 있으면 그것을, 없으면 시스템 선호 언어 첫 항목이 en 으로 시작할 때만 영어를 고른다.
    public static func resolve(environment: [String: String], preferredLanguages: [String]) -> Language {
        if let raw = environment["PULSE_LANG"]?.trimmingCharacters(in: .whitespaces).lowercased(),
           let language = Language(rawValue: raw) {
            return language
        }
        return preferredLanguages.first?.lowercased().hasPrefix("en") == true ? .en : .ko
    }
}

/// 화면 문구 사전. 항목마다 한국어와 영어를 나란히 둔다. 로그 문구는 여기에 넣지 않는다.
public enum L10n {
    public static var language: Language = .resolve(
        environment: ProcessInfo.processInfo.environment,
        preferredLanguages: Locale.preferredLanguages
    )

    private static func pick(_ ko: String, _ en: String) -> String {
        language == .en ? en : ko
    }

    private static func plural(_ count: Int, _ singular: String, _ plural: String) -> String {
        "\(count) \(count == 1 ? singular : plural)"
    }

    // MARK: - 시간

    public static var justNow: String { pick("방금", "just now") }

    public static func minutes(_ count: Int) -> String {
        pick("\(count)분", plural(count, "minute", "minutes"))
    }

    public static func hours(_ count: Int) -> String {
        pick("\(count)시간", plural(count, "hour", "hours"))
    }

    /// 「7분」 같은 경과 문구에 「전」을 붙인다.
    public static func ago(_ elapsed: String) -> String {
        pick("\(elapsed) 전", "\(elapsed) ago")
    }

    public static func secondsAgo(_ count: Int) -> String {
        pick("\(count)초 전", "\(plural(count, "second", "seconds")) ago")
    }

    public static func minutesAgo(_ count: Int) -> String {
        pick("\(count)분 전", "\(plural(count, "minute", "minutes")) ago")
    }

    public static func hoursAgo(_ count: Int) -> String {
        pick("\(count)시간 전", "\(plural(count, "hour", "hours")) ago")
    }

    public static func daysAgo(_ count: Int) -> String {
        pick("\(count)일 전", "\(plural(count, "day", "days")) ago")
    }

    // MARK: - 그룹과 배지

    public static var groupAttention: String { pick("확인 필요", "Needs attention") }
    public static var groupWorking: String { pick("진행 중", "In progress") }
    /// `DisplayGroup.title` 은 띄어 쓰지 않은 「진행중」을 쓴다.
    public static var groupWorkingCompact: String { pick("진행중", "In progress") }
    public static var groupDone: String { pick("완료", "Done") }
    public static var groupAll: String { pick("전체", "All") }

    public static func badgeAttention(_ count: Int) -> String { pick("확인 \(count)", "\(count) waiting") }
    public static func badgeWorking(_ count: Int) -> String { pick("진행 \(count)", "\(count) running") }
    public static func badgeDone(_ count: Int) -> String { pick("완료 \(count)", "\(count) done") }

    public static var untitledSession: String { pick("제목 없는 세션", "Untitled session") }
    public static func moreHidden(_ count: Int) -> String { pick("그 밖에 \(count)개", "\(count) more") }

    // MARK: - 검색

    public static var searchSessions: String { pick("세션 검색", "Search sessions") }
    public static var noSearchResults: String { pick("일치하는 세션이 없어요", "No matching sessions") }
    public static var clearSearch: String { pick("검색 지우기", "Clear search") }

    // MARK: - 상태 문구

    public static var grantPermission: String { pick("권한을 허락해 주세요", "Please grant permission") }
    public static var waitingForPermission: String { pick("권한 승인을 기다려요", "Waiting for permission approval") }
    public static var waitingForReply: String { pick("답을 기다리고 있어요", "Waiting for your reply") }
    public static var needsAttention: String { pick("확인이 필요해요", "Needs your attention") }
    public static var checkIfStuck: String { pick("멈췄는지 확인해 보세요", "Check if it's stuck") }
    public static var inProgress: String { pick("진행 중이에요", "In progress") }
    public static var finished: String { pick("끝났어요", "Finished") }
    public static var justFinished: String { pick("방금 끝났어요", "Just finished") }

    /// `elapsed` 는 「12분」 같은 경과 문구다.
    public static func finishedAgo(_ elapsed: String) -> String {
        pick("\(elapsed) 전 끝남", "Finished \(elapsed) ago")
    }

    public static func backgroundTaskFor(_ duration: String, _ name: String) -> String {
        pick("백그라운드 작업 \(duration)째 · \(name)", "Background task for \(duration) · \(name)")
    }

    public static func backgroundTaskCheckStuck(_ duration: String) -> String {
        pick("백그라운드 작업 \(duration)째 · 멈췄는지 확인해 보세요", "Background task for \(duration) · check if it's stuck")
    }

    public static func workingForCheckStuck(_ duration: String) -> String {
        pick("작업 \(duration)째 · 멈췄는지 확인해 보세요", "Working for \(duration) · check if it's stuck")
    }

    /// 확인 필요 카드 메타의 「· 12분째」. 영어는 카드 폭에 맞춰 「12m」 으로 줄인다.
    public static func durationSoFar(minutes: Int) -> String {
        if minutes < 60 { return pick("\(minutes)분째", "\(minutes)m") }
        return pick("\(minutes / 60)시간째", "\(minutes / 60)h")
    }

    /// 진행 중 행 상태의 「12분째」.
    public static func runningFor(_ duration: String) -> String {
        pick("\(duration)째", "Running for \(duration)")
    }

    public static func waitingFor(_ duration: String) -> String {
        pick("\(duration)째 기다림", "Waiting for \(duration)")
    }

    public static func minutesLeft(_ count: Int) -> String {
        pick("약 \(count)분 남음", "~\(count) min left")
    }

    // MARK: - 도구 이름

    public static var editFile: String { pick("파일 편집", "Edit file") }
    public static var readFile: String { pick("파일 읽기", "Read file") }
    public static var search: String { pick("검색", "Search") }
    public static var webFetch: String { pick("웹 조회", "Web fetch") }

    // MARK: - deadhd 단계와 활동 줄

    public static func stepFallback(_ number: Int) -> String { pick("단계 \(number)", "Step \(number)") }
    public static func showAllSteps(_ total: Int) -> String {
        pick("전체 \(total)단계 보기", "Show all \(plural(total, "step", "steps"))")
    }
    public static func earlierStepsPartlyDone(_ hidden: Int, done: Int) -> String {
        pick("앞 \(hidden)단계 · 완료 \(done)", "\(plural(hidden, "earlier step", "earlier steps")) · \(done) done")
    }
    public static func earlierStepsDone(_ hidden: Int) -> String {
        pick("앞 \(hidden)단계 완료", "\(plural(hidden, "earlier step", "earlier steps")) done")
    }
    public static var lastStep: String { pick("마지막", "Last") }
    public static func allStepsCollapse(_ total: Int) -> String {
        pick("전체 \(total)단계 · 접기", "All \(plural(total, "step", "steps")) · collapse")
    }
    public static var showThreeSteps: String { pick("세 단계만 보기 (←)", "Show only three steps (←)") }
    public static var showAllStepsHelp: String { pick("전체 단계 보기 (→)", "Show all steps (→)") }
    public static var noStepsYet: String { pick("단계가 아직 없어요", "No steps yet") }
    public static var stepsUnreadable: String { pick("단계 목록을 읽지 못했어요", "Couldn't read the step list") }
    public static var collapseSteps: String { pick("단계 접기 (←)", "Collapse steps (←)") }
    public static var expandSteps: String { pick("단계 펼치기 (→)", "Expand steps (→)") }
    public static var stepsCollapsed: String { pick("접힘", "Collapsed") }
    public static var stepsThree: String { pick("세 단계", "Three steps") }
    public static var stepsAll: String { pick("전체 단계", "All steps") }
    public static func deadhdUpdated(_ time: String) -> String {
        pick("deadhd · \(time) 갱신", "deadhd · updated \(time)")
    }
    public static func compactions(_ count: Int) -> String {
        pick("압축 \(count)", plural(count, "compaction", "compactions"))
    }
    public static func backgroundTasks(_ count: Int) -> String {
        pick("백그라운드 \(count)", "\(count) in background")
    }

    // MARK: - 카드와 알림

    public static var notifyAttentionTitle: String { pick("확인이 필요해요", "Needs your attention") }
    public static var notifyDoneTitle: String { pick("끝났어요", "Finished") }
    public static func cardHeaderAttention(_ count: Int) -> String { pick("확인 \(count)", "\(count) waiting") }
    public static func cardHeaderDone(_ count: Int) -> String { pick("끝남 \(count)", "\(count) done") }
    public static func took(_ duration: String) -> String { pick("\(duration) 걸림", "Took \(duration)") }
    public static func doneMeta(_ title: String) -> String { pick("\(title) · 끝남", "\(title) · Finished") }
    public static func doneMeta(_ title: String, took duration: String) -> String {
        pick("\(title) · 끝남 · \(duration) 걸림", "\(title) · Finished · took \(duration)")
    }
    public static var awayTitle: String { pick("자리 비운 사이", "While you were away") }
    public static func awaySessionsWaiting(_ count: Int) -> String {
        pick("세션 \(count)개가 기다려요", count == 1 ? "1 session is waiting" : "\(count) sessions are waiting")
    }
    public static func awaySessionsFinished(_ count: Int) -> String {
        pick("세션 \(count)개가 끝났어요", count == 1 ? "1 session finished" : "\(count) sessions finished")
    }
    public static func awayFinishedAndOpen(_ done: Int) -> String {
        pick("\(done)개 끝났어요 · 누르면 목록이 열려요", "\(done) finished · click to open the list")
    }
    public static var awayOpenList: String { pick("누르면 목록이 열려요", "Click to open the list") }

    // MARK: - 버튼과 도움말

    public static var openInOrca: String { pick("Orca 에서 열기", "Open in Orca") }
    public static var snoozeTenMinutes: String { pick("10분 더", "Snooze 10 min") }
    public static var acknowledge: String { pick("확인", "Dismiss") }
    public static var acknowledgeAll: String { pick("모두 확인", "Dismiss all") }
    public static var reply: String { pick("답하기", "Reply") }
    public static var open: String { pick("열기", "Open") }
    public static var waitTenMoreMinutes: String { pick("10분 더 기다리기", "Wait 10 more minutes") }
    public static var cannotSnoozeQuestion: String {
        pick("질문·권한 대기는 미룰 수 없어요", "Questions and permission requests can't be snoozed")
    }
    public static var replyInOrca: String { pick("답하기 · Orca 에서 터미널 열기", "Reply · open the terminal in Orca") }
    public static var replyInOrcaShortcut: String {
        pick("답하기 · Orca 에서 터미널 열기 (⌥↩)", "Reply · open the terminal in Orca (⌥↩)")
    }
    public static var openShortcut: String { pick("열기 (↩)", "Open (↩)") }
    public static var acknowledgeShortcut: String { pick("확인 (⌫)", "Dismiss (⌫)") }
    public static var openProgressPage: String { pick("브라우저에서 진행 페이지 열기", "Open the progress page in the browser") }
    public static var progressPageNotCreated: String {
        pick(
            "진행 페이지를 만들지 못했어요. deadhd 의 render.py 를 찾지 못했거나 실행에 실패했어요",
            "Could not create the progress page. deadhd's render.py was not found or failed to run"
        )
    }
    public static var progressPageNotOpened: String {
        pick("진행 페이지를 열지 못했어요", "Could not open the progress page")
    }

    // MARK: - 명령줄

    public static var usage: String {
        pick(
            """
            사용법: pulse [옵션]

            옵션 없이 실행하면 메뉴 막대 앱을 띄웁니다.

              --version   버전을 출력하고 끝냅니다
              -h, --help  이 도움말을 출력하고 끝냅니다
            """,
            """
            Usage: pulse [option]

            Without an option, Pulse starts the menu bar app.

              --version   Print the version and exit
              -h, --help  Print this help and exit
            """
        )
    }

    public static func unknownOption(_ option: String) -> String {
        pick("pulse: 알 수 없는 옵션 \(option)", "pulse: unknown option \(option)")
    }
    public static var goToOrcaShortcut: String { pick("Orca 로 이동 (⌥↩)", "Go to Orca (⌥↩)") }
    public static var goToOrcaArrow: String { pick("→ Orca 로 이동", "→ Go to Orca") }
    public static func openPR(_ label: String) -> String { pick("PR \(label) 열기", "Open PR \(label)") }
    public static func openKey(_ key: String) -> String { pick("\(key) 열기", "Open \(key)") }
    public static var noTerminal: String { pick("터미널 없음", "No terminal") }
    public static var undo: String { pick("되돌리기", "Undo") }
    public static func acknowledgedDone(_ count: Int) -> String {
        pick("완료 \(count)개를 확인했어요", "Dismissed \(count) finished")
    }
    public static var expand: String { pick("펼치기", "Expand") }
    public static var collapse: String { pick("접기", "Collapse") }
    public static var close: String { pick("닫기", "Close") }
    public static var hideFloatingWindow: String { pick("플로팅 창 숨기기", "Hide floating window") }
    public static var showFloatingWindow: String { pick("플로팅 창 보기", "Show floating window") }
    public static var viewSettingsShortcut: String { pick("보기 설정 (⌘,)", "View settings (⌘,)") }
    public static var quit: String { pick("종료", "Quit") }
    public static func updated(_ relative: String) -> String { pick("\(relative) 갱신", "Updated \(relative)") }
    public static var notUpdatedYet: String { pick("갱신 전", "Not updated yet") }
    public static var retryNow: String { pick("지금 재시도", "Retry now") }

    // MARK: - 빈 화면과 오류

    public static var sessionsUnreadable: String { pick("Claude 세션을 읽지 못했어요", "Couldn't read Claude sessions") }
    public static var allQuiet: String { pick("지금은 조용해요", "All quiet for now") }
    public static var nothingToDo: String { pick("할 일이 비었어요", "Nothing to do") }
    public static var willNotifyNewSession: String {
        pick("새 세션이 시작되면 바로 알려 드릴게요.", "You'll hear about new sessions as soon as they start.")
    }
    public static var readFailed: String { pick("읽기 실패", "Read failed") }
    public static var terminalClosed: String { pick("터미널이 닫혔어요", "The terminal was closed") }
    public static var noOrcaTerminal: String {
        pick("Orca 에 이 세션의 터미널이 없어요", "Orca has no terminal for this session")
    }

    // MARK: - 설정 시트

    public static var density: String { pick("밀도", "Density") }
    public static var densityRich: String { pick("풍부", "Detailed") }
    public static var densityCompact: String { pick("간결", "Compact") }
    public static var theme: String { pick("테마", "Theme") }
    public static var themeSystem: String { pick("시스템", "System") }
    public static var themeLight: String { pick("라이트", "Light") }
    public static var themeDark: String { pick("다크", "Dark") }
    public static var reduceTransparencyOn: String {
        pick(
            "시스템의 투명도 줄이기가 켜져 있어 유리 대신 단색 배경으로 보여요",
            "Reduce transparency is on, so Pulse uses a solid background instead of glass"
        )
    }
    public static var openDisplaySettings: String { pick("설정 열기", "Open Settings") }
    /// 한국어 화면에서도 영어로 둔다. GitHub 의 버튼 이름과 같게 보이도록 한 의도다.
    public static var starOnGitHub: String { "Star on GitHub" }
    public static var notifications: String { pick("알림", "Notifications") }
    public static var whenAttentionNeeded: String { pick("확인이 필요할 때", "When attention is needed") }
    public static var whenTaskFinishes: String { pick("작업이 끝났을 때", "When a task finishes") }
    public static var alertCardAndSound: String { pick("카드와 소리", "Card and sound") }
    public static var alertCardOnly: String { pick("카드만", "Card only") }
    public static var alertCard: String { pick("카드", "Card") }
    public static var alertOff: String { pick("끔", "Off") }
    public static var quietWhileLooking: String {
        pick("Pulse 를 보고 있을 때는 알리지 않아요", "No alerts while you're looking at Pulse")
    }
    public static var lockedAlertsGrouped: String {
        pick(
            "화면이 잠긴 사이의 알림은 돌아오면 한 장으로 묶어요",
            "Locked-screen alerts arrive as one card"
        )
    }
    public static var shortcut: String { pick("단축키", "Shortcut") }
    public static var shortcutTaken: String { pick("단축키 ⌃⌥P 를 다른 앱이 쓰고 있어요", "Another app is using ⌃⌥P") }
    public static var shortcutHint: String {
        pick("한 번: 팝오버 · 열린 채로 한 번 더: 플로팅 패널", "Once: popover · Twice: floating panel")
    }
}
