import AppKit
import Combine
import CoreGraphics
import Foundation
import OSLog
import PulseCore

/// 펼친 행이 보여 줄 체크리스트. `steps` 가 nil 이면 읽기 실패다.
struct ChecklistSnapshot: Equatable {
    let steps: [ChecklistStep]?
    let modifiedAt: Date?
}

final class AppModel: ObservableObject {
    @Published private(set) var groups = GroupedSessions.empty
    @Published private(set) var sessionsUnavailable = true
    @Published private(set) var errorMessage: String?
    /// 목록 패널만 뜻한다. 카드 패널이 떠 있어도 새 알림은 억제하지 않는다.
    @Published private(set) var panelVisible = false
    @Published private(set) var cards: [NotificationCard] = []
    @Published private(set) var cardPanelVisible = false
    /// 뷰가 남은 시간 선 애니메이션을 멈추는 데 쓴다. `deck.paused` 와 같다.
    @Published private(set) var cardsPaused = false
    @Published var collapsed = false
    @Published private(set) var hiddenDoneCount = 0
    @Published private(set) var recentAcknowledgedCount = 0
    @Published private(set) var recentAcknowledgedGeneration = 0
    @Published private(set) var notice: String?
    private var noticeGeneration = 0
    @Published private(set) var lastSuccess: Date?
    @Published private(set) var density: Density
    @Published private(set) var theme: ThemePreference
    @Published private(set) var attentionAlert: AttentionAlert
    @Published private(set) var doneAlert: DoneAlert
    @Published private(set) var notificationPermission: NotificationPermission = .unknown
    @Published private(set) var hotKeyUnavailable = false
    /// 단계를 펼친 세션. 팝오버와 플로팅 패널이 같은 펼침을 본다.
    @Published private(set) var expandedSteps: Set<String> = []
    /// 세 줄 창을 넘겨 전체 단계를 보는 세션.
    @Published private(set) var fullSteps: Set<String> = []
    @Published private(set) var checklists: [String: ChecklistSnapshot] = [:]

    private static let acknowledgedKey = "acknowledgedDoneKeys"

    private static let checklistFileLimit = 1024 * 1024

    private static let logger = Logger(subsystem: "io.github.lcalmsky.pulse", category: "notify")
    private static let pageLogger = Logger(subsystem: "io.github.lcalmsky.pulse", category: "page")

    private let defaults = UserDefaults.standard
    private let failureGrace: TimeInterval = 15
    private let pollInterval: TimeInterval = 3
    private let localSource = LocalSessionSource()
    private let localQueue = DispatchQueue(label: "dev.pulse.local-sessions", qos: .userInitiated)
    private lazy var notificationCenter = AttentionNotificationCenter(model: self)

    /// 앱은 집중 모드 상태를 읽을 수 없어(INFocusStatusCenter 의 isFocused 가 켜짐에서도 false) 시스템 알림 보조 경로를 쓰지 않는다.
    static let systemNotificationPolicy: SystemNotificationPolicy = .never

    private var attentionNotifier = AttentionNotifier()
    private var doneNotifier = DoneNotifier()
    /// 재생하는 동안 해제되지 않도록 잡아 둔다.
    private var cardSound: NSSound?
    private var deck = CardDeck()
    private var cardExpiry: DispatchWorkItem?
    private var screenLockObservers: [NSObjectProtocol] = []
    private var popoverVisible = false
    private var hasHandledFirstUpdate = false

    private var response: SessionsResponse?
    private var timer: Timer?
    private var snoozes: [String: Date] = [:]
    private var acknowledgements: DoneAcknowledgements
    private var errorGeneration = 0
    private var localReading = false

    /// 패널 컨트롤러가 생긴 뒤 AppDelegate 가 넣는다. 바닥글에서 패널을 띄울 때 키보드 포커스를 준다.
    var onPanelFocusRequest: (() -> Void)?

    init() {
        let settings = AppSettings(
            densityRaw: defaults.string(forKey: AppSettings.densityKey),
            themeRaw: defaults.string(forKey: AppSettings.themeKey),
            attentionAlertRaw: defaults.string(forKey: AppSettings.attentionAlertKey),
            doneAlertRaw: defaults.string(forKey: AppSettings.doneAlertKey),
            legacyAttention: defaults.object(forKey: AppSettings.attentionNotificationsKey) as? Bool,
            legacyDone: defaults.object(forKey: AppSettings.doneNotificationsKey) as? Bool
        )
        density = settings.density
        theme = settings.theme
        attentionAlert = settings.attentionAlert
        doneAlert = settings.doneAlert

        acknowledgements = DoneAcknowledgements(
            keys: Set(defaults.stringArray(forKey: Self.acknowledgedKey) ?? [])
        )
    }

    // MARK: - 설정

    func setDensity(_ value: Density) {
        guard density != value else { return }
        density = value
        defaults.set(value.rawValue, forKey: AppSettings.densityKey)
    }

    func setTheme(_ value: ThemePreference) {
        guard theme != value else { return }
        theme = value
        defaults.set(value.rawValue, forKey: AppSettings.themeKey)
    }

    func setAttentionAlert(_ value: AttentionAlert) {
        guard attentionAlert != value else { return }
        attentionAlert = value
        defaults.set(value.rawValue, forKey: AppSettings.attentionAlertKey)
        defaults.removeObject(forKey: AppSettings.attentionNotificationsKey)
        if value.showsCard {
            if Self.systemNotificationPolicy == .always {
                notificationCenter.requestAuthorizationIfNeeded()
            }
        } else {
            deck.dismiss(kind: .attention)
            publishCards()
            notificationCenter.removeDelivered(kind: .attention)
        }
    }

    func setDoneAlert(_ value: DoneAlert) {
        guard doneAlert != value else { return }
        doneAlert = value
        defaults.set(value.rawValue, forKey: AppSettings.doneAlertKey)
        defaults.removeObject(forKey: AppSettings.doneNotificationsKey)
        if value.showsCard {
            if Self.systemNotificationPolicy == .always {
                notificationCenter.requestAuthorizationIfNeeded()
            }
        } else {
            deck.dismiss(kind: .done)
            publishCards()
            notificationCenter.removeDelivered(kind: .done)
        }
    }

    func updateNotificationPermission(_ value: NotificationPermission) {
        guard notificationPermission != value else { return }
        notificationPermission = value
    }

    func refreshNotificationPermission() {
        notificationCenter.refreshPermission()
    }

    func requestNotificationAuthorization() {
        notificationCenter.requestAuthorization(force: true)
    }

    func openNotificationSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=io.github.lcalmsky.pulse"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    func setPopoverVisible(_ visible: Bool) {
        popoverVisible = visible
        if visible {
            deck.dismissAll()
        }
        publishCards()
    }

    func setHotKeyUnavailable(_ unavailable: Bool) {
        hotKeyUnavailable = unavailable
    }

    func start() {
        notificationCenter.logStartupState()
        if Self.systemNotificationPolicy == .always && (attentionAlert.showsCard || doneAlert.showsCard) {
            notificationCenter.requestAuthorizationIfNeeded()
        }
        observeScreenLock()
        poll()
        let timer = Timer(timeInterval: pollInterval, repeats: true) { [weak self] _ in
            self?.poll()
        }
        timer.tolerance = 0.5
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    // MARK: - 자리 비움

    private func observeScreenLock() {
        let center = DistributedNotificationCenter.default()
        screenLockObservers.append(center.addObserver(
            forName: Notification.Name("com.apple.screenIsLocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.beginAway(path: "signal")
        })
        screenLockObservers.append(center.addObserver(
            forName: Notification.Name("com.apple.screenIsUnlocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.endAway(path: "signal")
        })
    }

    private func beginAway(path: String) {
        guard !deck.isAway else { return }
        deck.beginAway(now: Date())
        Self.logger.notice("자리 비움 시작 경로=\(path, privacy: .public)")
        publishCards()
    }

    private func endAway(path: String) {
        guard deck.isAway else { return }
        let result = deck.endAway(now: Date())
        let counts: (attention: Int, done: Int)
        let label: String
        switch result {
        case .none:
            counts = (0, 0)
            label = "none"
        case let .single(kind):
            counts = kind == .attention ? (1, 0) : (0, 1)
            label = "single"
        case let .summary(attention, done):
            counts = (attention, done)
            label = "summary"
        }
        Self.logger.notice(
            "자리 비움 끝 경로=\(path, privacy: .public) 결과=\(label, privacy: .public) 확인=\(counts.attention) 끝남=\(counts.done)"
        )
        publishCards()
    }

    /// 잠김 알림을 놓치거나 잠긴 채 시작하면 덱이 자리 비움에 머물러 모든 카드를 삼킨다. 그래서 폴링마다 실제 잠김 값과 맞춘다.
    private func syncAwayWithScreenLock() {
        switch ScreenLockTransition.decide(locked: screenIsLocked(), isAway: deck.isAway) {
        case .begin: beginAway(path: "poll")
        case .end: endAway(path: "poll")
        case .none: break
        }
    }

    /// 키가 없으면 잠기지 않은 것이고, 사전을 못 읽으면 nil 이다.
    private func screenIsLocked() -> Bool? {
        guard let dictionary = CGSessionCopyCurrentDictionary() as? [String: Any] else { return nil }
        guard let value = dictionary["CGSSessionScreenIsLocked"] else { return false }
        return (value as? NSNumber)?.boolValue ?? false
    }

    func openAwaySummary() {
        showPanel()
    }

    // MARK: - 폴링

    func poll() {
        readLocal()
    }

    private func readLocal() {
        guard !localReading else { return }
        localReading = true
        localQueue.async { [weak self] in
            guard let self else { return }
            let result = Result { try self.localSource.read(now: Date()) }
            DispatchQueue.main.async {
                self.localReading = false
                self.applyLocal(result)
            }
        }
    }

    private func applyLocal(_ result: Result<[Session], Error>) {
        guard case let .success(active) = result else {
            markFailure()
            return
        }
        lastSuccess = Date()
        if sessionsUnavailable {
            sessionsUnavailable = false
        }

        let before = acknowledgements
        acknowledgements.prune(keeping: SessionsResponse(sessions: active))
        if acknowledgements != before {
            persistAcknowledgements()
        }
        response = SessionsResponse(sessions: active)
        refresh()
        syncAwayWithScreenLock()
        deliverAttentionNotes(isFirstUpdate: !hasHandledFirstUpdate)
        hasHandledFirstUpdate = true
    }

    private func markFailure() {
        if let lastSuccess, Date().timeIntervalSince(lastSuccess) < failureGrace {
            refresh()
            return
        }
        if !sessionsUnavailable {
            sessionsUnavailable = true
        }
        refresh()
    }

    func refresh(now: Date = Date()) {
        snoozes = snoozes.filter { $0.value > now }
        let newGroups = Grouping.group(
            response,
            now: now,
            acknowledgedDone: acknowledgements.keys,
            snoozedUntil: snoozes
        )
        if newGroups != groups {
            groups = newGroups
        }
        let newHiddenDoneCount = acknowledgements.hiddenCount(in: response, now: now)
        if newHiddenDoneCount != hiddenDoneCount {
            hiddenDoneCount = newHiddenDoneCount
        }
        pruneStepState()
        // 완료 알림도 확인(숨김)하거나 진행 중으로 돌아가면 이 집합에서 빠져 알림 센터에서 거둬진다.
        // 정책이 never 면 새로 보내는 알림이 없다. 이전 버전이 남긴 알림은 첫 갱신에서 한 번 거둔다.
        if Self.systemNotificationPolicy != .never || !hasHandledFirstUpdate {
            notificationCenter.syncDelivered(
                keeping: Set((groups.attention + groups.done).map(\.sessionId))
            )
        }
    }

    private func deliverAttentionNotes(isFirstUpdate: Bool) {
        let attention = attentionNotifier.evaluate(
            for: groups.attention,
            popoverVisible: popoverVisible,
            panelVisible: panelVisible,
            enabled: attentionAlert.showsCard,
            isFirstUpdate: isFirstUpdate
        )
        let done = doneNotifier.evaluate(
            done: groups.done,
            working: groups.working,
            attention: groups.attention,
            popoverVisible: popoverVisible,
            panelVisible: panelVisible,
            enabled: doneAlert.showsCard,
            isFirstUpdate: isFirstUpdate
        )
        Self.logBatch("확인 필요", attention)
        Self.logBatch("완료", done)

        let route = NotificationRoute.decide(policy: Self.systemNotificationPolicy)
        if route.system {
            notificationCenter.post(attention.notes, kind: .attention)
            notificationCenter.post(done.notes, kind: .done)
        }
        let newAttention = route.cards ? items(for: attention.notes, in: groups.attention) : []
        let newDone = route.cards ? items(for: done.notes, in: groups.done) : []
        // 카드를 보내지 않는 경로에서도 거두기와 턴 시작 시각은 갱신한다.
        let inserted = deck.update(
            newAttention: newAttention,
            newDone: newDone,
            groups: groups,
            now: Date()
        )
        publishCards()
        if route.cards, inserted > 0, let soundName = attentionAlert.soundName {
            playCardSound(named: soundName)
        }
        if newAttention.count + newDone.count > 0 {
            let path: String
            switch (route.cards, route.system) {
            case (true, true): path = "both"
            case (true, false): path = "cards"
            case (false, true): path = "system"
            case (false, false): path = "none"
            }
            Self.logger.notice(
                "카드 추가 확인=\(newAttention.count) 끝남=\(newDone.count) 떠 있음=\(self.deck.cards.count) 경로=\(path, privacy: .public)"
            )
        }
    }

    /// 재생 중 해제되지 않도록 인스턴스를 잡아 두고, 이름이 바뀌면 다시 만든다.
    private func playCardSound(named name: String) {
        if cardSound?.name != name {
            cardSound = NSSound(named: name)
        }
        cardSound?.play()
    }

    private func items(for notes: [AttentionNote], in items: [DisplayItem]) -> [DisplayItem] {
        let ids = Set(notes.map(\.sessionId))
        return items.filter { ids.contains($0.sessionId) }
    }

    private func publishCards() {
        let ordered = deck.ordered
        if cards != ordered { cards = ordered }
        if cardsPaused != deck.paused { cardsPaused = deck.paused }
        let visible = !ordered.isEmpty && !popoverVisible && !panelVisible
        if cardPanelVisible != visible { cardPanelVisible = visible }
        scheduleCardExpiry()
    }

    private func scheduleCardExpiry() {
        cardExpiry?.cancel()
        guard let deadline = deck.nextDeadline else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if self.deck.expire(now: Date()) {
                self.publishCards()
            }
        }
        cardExpiry = work
        DispatchQueue.main.asyncAfter(
            deadline: .now() + max(0, deadline.timeIntervalSinceNow + 0.01),
            execute: work
        )
    }

    func setCardHover(_ hovering: Bool) {
        deck.setPaused(hovering, now: Date())
        publishCards()
    }

    func openCard(_ item: DisplayItem) {
        open(item)
        deck.dismiss(item.sessionId)
        publishCards()
    }

    func answerCard(_ item: DisplayItem) {
        openInOrca(item)
        deck.dismiss(item.sessionId)
        publishCards()
    }

    func snoozeCard(_ item: DisplayItem) {
        snooze(item)
        deck.dismiss(item.sessionId)
        publishCards()
    }

    func acknowledgeCard(_ item: DisplayItem) {
        acknowledge(item)
        deck.dismiss(item.sessionId)
        publishCards()
    }

    /// 끝남 카드의 항목을 한 번에 확인 처리하고 토스트는 한 번만 띄운다.
    func acknowledgeAllCards() {
        let doneItems = cards
            .filter { $0.kind == .done }
            .compactMap { card in groups.done.first { $0.sessionId == card.sessionId } }
        let count = acknowledgements.acknowledge(doneItems)
        if count > 0 {
            persistAcknowledgements()
            showUndoToast(count: count)
            refresh()
        }
        deck.dismissAll()
        publishCards()
    }

    /// 후보가 있는 갱신에만 후보 수와 억제 사유를 info 와 기본 로그로 남긴다.
    private static func logBatch(_ label: String, _ batch: NotificationBatch) {
        guard batch.candidates > 0 else { return }
        let line = "\(label) 후보=\(batch.candidates) 전송=\(batch.notes.count) 억제=\(batch.suppression?.rawValue ?? "없음")"
        logger.info("\(line, privacy: .public)")
        logger.notice("\(line, privacy: .public)")
    }

    // MARK: - 동작

    func open(_ item: DisplayItem) {
        switch item.clickAction {
        case .orca(let handle):
            switchTerminal(handle, fallbackCwd: item.cwd, name: item.key ?? item.title)
        case .cwd(let cwd):
            switchToCwd(cwd, name: item.key ?? item.title)
        case .none:
            break
        }
    }

    /// HTML 이 아직 없으면 render.py 로 만든 뒤 브라우저로 연다.
    /// deadhd 의 serve.py 주소 규칙을 먼저 시도하고, 실패하면 file:// 로 연다.
    /// 서버 확인이 파일 IO 라서 화면을 붙잡지 않도록 백그라운드에서 돈다.
    func openPageInBrowser(_ item: DisplayItem) {
        guard let path = item.pagePath else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            guard DeadhdPage.ensurePage(path: path, dataPath: item.dataPath) else {
                Self.pageLogger.error("진행 페이지를 만들지 못해 열지 않았다: \(path, privacy: .public)")
                DispatchQueue.main.async { self.showNotice(L10n.progressPageNotCreated) }
                return
            }
            guard let url = DeadhdPage.url(for: path) else {
                Self.pageLogger.error("진행 페이지를 열 주소를 만들지 못해 열지 않았다: \(path, privacy: .public)")
                DispatchQueue.main.async { self.showNotice(L10n.progressPageNotOpened) }
                return
            }
            DispatchQueue.main.async {
                if !NSWorkspace.shared.open(url) {
                    Self.pageLogger.error("진행 페이지를 열지 못했다: \(url.absoluteString, privacy: .public)")
                    self.showNotice(L10n.progressPageNotOpened)
                }
            }
        }
    }

    // MARK: - 단계 펼침

    func toggleSteps(_ item: DisplayItem) {
        let id = item.sessionId
        if expandedSteps.contains(id) {
            expandedSteps.remove(id)
            fullSteps.remove(id)
            checklists[id] = nil
        } else {
            expandedSteps.insert(id)
            loadChecklist(item)
        }
    }

    /// 키보드로 단계 펼침을 한 칸 옮긴다. 단계가 실제로 바뀌었으면 true 를 돌려준다.
    @discardableResult
    func stepDisclosure(_ item: DisplayItem, by step: Int, toEnd: Bool) -> Bool {
        let id = item.sessionId
        let from = disclosure(of: item)
        // 접힘에서 펼칠 때만 체크리스트를 먼저 읽어야 전체 단계 가능 여부를 알 수 있다.
        if from == .collapsed, step > 0 {
            expandedSteps.insert(id)
            loadChecklist(item)
        }
        let target = StepDisclosure.next(
            from: from,
            by: step,
            toEnd: toEnd,
            canShowFull: canShowFullSteps(item)
        )
        applyDisclosure(target, to: item)
        return target != from
    }

    private func disclosure(of item: DisplayItem) -> StepDisclosure {
        guard expandedSteps.contains(item.sessionId) else { return .collapsed }
        return fullSteps.contains(item.sessionId) ? .full : .window
    }

    private func canShowFullSteps(_ item: DisplayItem) -> Bool {
        guard let steps = checklists[item.sessionId]?.steps else { return false }
        return StepWindow.make(steps.map(\.state)).hasHidden
    }

    private func applyDisclosure(_ value: StepDisclosure, to item: DisplayItem) {
        let id = item.sessionId
        switch value {
        case .collapsed:
            expandedSteps.remove(id)
            fullSteps.remove(id)
            checklists[id] = nil
        case .window:
            expandedSteps.insert(id)
            fullSteps.remove(id)
        case .full:
            expandedSteps.insert(id)
            fullSteps.insert(id)
        }
    }

    func toggleFullSteps(_ item: DisplayItem) {
        if fullSteps.contains(item.sessionId) {
            fullSteps.remove(item.sessionId)
        } else {
            fullSteps.insert(item.sessionId)
        }
    }

    /// 파일 상한이 1MB 라 메인 스레드에서 동기로 읽는다.
    private func loadChecklist(_ item: DisplayItem) {
        guard let path = item.dataPath else {
            checklists[item.sessionId] = ChecklistSnapshot(steps: nil, modifiedAt: nil)
            return
        }
        let url = URL(fileURLWithPath: path)
        let modifiedAt = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate
        if let modifiedAt, let existing = checklists[item.sessionId], existing.modifiedAt == modifiedAt {
            return
        }
        let attributes = try? FileManager.default.attributesOfItem(atPath: path)
        let readable = (attributes?[.type] as? FileAttributeType) == .typeRegular
            && ((attributes?[.size] as? NSNumber)?.intValue ?? Int.max) <= Self.checklistFileLimit
        checklists[item.sessionId] = ChecklistSnapshot(
            steps: readable ? (try? Data(contentsOf: url)).flatMap { Checklist.parse($0) } : nil,
            modifiedAt: modifiedAt
        )
    }

    /// 목록에서 사라진 세션의 펼침·캐시를 버리고, 펼쳐진 세션은 파일이 바뀌었는지 본다.
    private func pruneStepState() {
        let ids = Set(groups.allItems.map(\.sessionId))
        let keptExpandedSteps = expandedSteps.intersection(ids)
        if keptExpandedSteps != expandedSteps {
            expandedSteps = keptExpandedSteps
        }
        let keptFullSteps = fullSteps.intersection(ids)
        if keptFullSteps != fullSteps {
            fullSteps = keptFullSteps
        }
        let keptChecklists = checklists.filter { ids.contains($0.key) }
        if keptChecklists != checklists {
            checklists = keptChecklists
        }
        for item in groups.allItems where expandedSteps.contains(item.sessionId) {
            loadChecklist(item)
        }
    }

    func openLink(_ urlString: String) {
        guard let url = SafeLink.httpURL(urlString) else { return }
        NSWorkspace.shared.open(url)
    }

    func openPullRequest(_ urlString: String) {
        openLink(urlString)
    }

    func openInOrca(_ item: DisplayItem) {
        switch item.clickAction {
        case .orca(let handle):
            switchTerminal(handle, fallbackCwd: item.cwd, name: item.key ?? item.title)
        case .cwd(let cwd):
            switchToCwd(cwd, name: item.key ?? item.title)
        case .none:
            break
        }
    }

    private func switchTerminal(_ handle: String, fallbackCwd: String?, name: String) {
        OrcaLauncher.switchTerminal(handle: handle) { [weak self] ok in
            guard !ok else { return }
            if let fallbackCwd {
                self?.switchToCwd(fallbackCwd, name: name)
            } else {
                self?.showError(L10n.terminalClosed)
            }
        }
    }

    private func switchToCwd(_ cwd: String, name: String) {
        OrcaLauncher.switchToCwd(cwd, name: name) { [weak self] ok in
            if !ok { self?.showError(L10n.noOrcaTerminal) }
        }
    }

    func snooze(_ item: DisplayItem) {
        snoozes[item.sessionId] = Date().addingTimeInterval(600)
        refresh()
    }

    func acknowledgeAllDone() {
        let count = acknowledgements.acknowledge(groups.done)
        guard count > 0 else { return }
        persistAcknowledgements()
        showUndoToast(count: count)
        refresh()
    }

    func acknowledge(_ item: DisplayItem) {
        switch PopoverRowAction.resolve(item) {
        case .hideDone:
            let count = acknowledgements.acknowledge(item)
            guard count > 0 else { return }
            persistAcknowledgements()
            showUndoToast(count: count)
            refresh()
        case .snooze:
            snooze(item)
        case .none:
            break
        }
    }

    private func showNotice(_ message: String) {
        notice = message
        noticeGeneration += 1
        let generation = noticeGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + NoticeToast.duration) { [weak self] in
            guard let self, self.noticeGeneration == generation else { return }
            self.notice = nil
        }
    }

    private func showUndoToast(count: Int) {
        recentAcknowledgedCount = count
        recentAcknowledgedGeneration += 1
        let generation = recentAcknowledgedGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + UndoToast.duration) { [weak self] in
            guard let self, self.recentAcknowledgedGeneration == generation else { return }
            self.recentAcknowledgedCount = 0
        }
    }

    func restoreAcknowledgedDone() {
        acknowledgements.undoAll()
        persistAcknowledgements()
        clearRecentAcknowledged()
        refresh()
    }

    func undoRecentAcknowledge() {
        guard recentAcknowledgedCount > 0 else { return }
        acknowledgements.undoRecent()
        persistAcknowledgements()
        clearRecentAcknowledged()
        refresh()
    }

    private func clearRecentAcknowledged() {
        recentAcknowledgedGeneration += 1
        recentAcknowledgedCount = 0
    }

    private func persistAcknowledgements() {
        defaults.set(Array(acknowledgements.keys).sorted(), forKey: Self.acknowledgedKey)
    }

    func togglePanel() {
        panelVisible.toggle()
        if panelVisible {
            deck.dismissAll()
            onPanelFocusRequest?()
        }
        publishCards()
    }

    func showPanel() {
        panelVisible = true
        deck.dismissAll()
        publishCards()
    }

    func hidePanel() {
        panelVisible = false
        publishCards()
    }

    func showError(_ text: String) {
        NSSound.beep()
        errorGeneration += 1
        let generation = errorGeneration
        errorMessage = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            guard let self, self.errorGeneration == generation else { return }
            self.errorMessage = nil
        }
    }
}
