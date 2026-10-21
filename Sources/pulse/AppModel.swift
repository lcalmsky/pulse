import AppKit
import Combine
import Foundation
import OSLog
import PulseCore

protocol DetailPresenting: AnyObject {
    func showDetail(for item: DisplayItem)
}

final class AppModel: ObservableObject {
    @Published private(set) var groups = GroupedSessions.empty
    @Published private(set) var sessionsUnavailable = true
    @Published private(set) var errorMessage: String?
    @Published private(set) var panelVisible = false
    @Published var collapsed = false
    @Published private(set) var hiddenDoneCount = 0
    @Published private(set) var recentAcknowledgedCount = 0
    @Published private(set) var recentAcknowledgedGeneration = 0
    @Published private(set) var lastSuccess: Date?
    @Published private(set) var density: Density
    @Published private(set) var theme: ThemePreference
    @Published private(set) var attentionNotifications: Bool
    @Published private(set) var doneNotifications: Bool
    @Published private(set) var notificationPermission: NotificationPermission = .unknown
    @Published private(set) var hotKeyUnavailable = false

    weak var detailPresenter: DetailPresenting?

    private static let acknowledgedKey = "acknowledgedDoneKeys"

    private static let logger = Logger(subsystem: "io.github.lcalmsky.pulse", category: "notify")

    private let defaults = UserDefaults.standard
    private let port: String
    private let failureGrace: TimeInterval = 15
    private let pollInterval: TimeInterval = 3
    private let localSource = LocalSessionSource()
    private let localQueue = DispatchQueue(label: "dev.pulse.local-sessions", qos: .userInitiated)
    private lazy var notificationCenter = AttentionNotificationCenter(model: self)

    private var attentionNotifier = AttentionNotifier()
    private var doneNotifier = DoneNotifier()
    private var popoverVisible = false
    private var hasHandledFirstUpdate = false

    private var response: SessionsResponse?
    private var localSessions: [Session]?
    private var remoteSessions: [Session]?
    private var endedTracker = EndedSessionTracker()
    private var timer: Timer?
    private var snoozes: [String: Date] = [:]
    private var acknowledgements: DoneAcknowledgements
    private var errorGeneration = 0
    private var localReading = false
    private var remoteFetching = false

    init() {
        let settings = AppSettings(
            densityRaw: defaults.string(forKey: AppSettings.densityKey),
            themeRaw: defaults.string(forKey: AppSettings.themeKey),
            attentionNotifications: defaults.object(forKey: AppSettings.attentionNotificationsKey) as? Bool,
            doneNotifications: defaults.object(forKey: AppSettings.doneNotificationsKey) as? Bool
        )
        density = settings.density
        theme = settings.theme
        attentionNotifications = settings.attentionNotifications
        doneNotifications = settings.doneNotifications

        port = ProcessInfo.processInfo.environment["DEADHD_PORT"] ?? "47320"
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

    func setAttentionNotifications(_ enabled: Bool) {
        guard attentionNotifications != enabled else { return }
        attentionNotifications = enabled
        defaults.set(enabled, forKey: AppSettings.attentionNotificationsKey)
        if enabled {
            notificationCenter.requestAuthorizationIfNeeded()
        } else {
            notificationCenter.removeDelivered(kind: .attention)
        }
    }

    func setDoneNotifications(_ enabled: Bool) {
        guard doneNotifications != enabled else { return }
        doneNotifications = enabled
        defaults.set(enabled, forKey: AppSettings.doneNotificationsKey)
        if enabled {
            notificationCenter.requestAuthorizationIfNeeded()
        } else {
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
    }

    func setHotKeyUnavailable(_ unavailable: Bool) {
        hotKeyUnavailable = unavailable
    }

    func start() {
        notificationCenter.logStartupState()
        if attentionNotifications || doneNotifications {
            notificationCenter.requestAuthorizationIfNeeded()
        }
        poll()
        let timer = Timer(timeInterval: pollInterval, repeats: true) { [weak self] _ in
            self?.poll()
        }
        timer.tolerance = 0.5
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    // MARK: - 폴링

    private var deadhdSessionsURL: URL? {
        URL(string: "http://127.0.0.1:\(port)/sessions.json")
    }

    func poll() {
        readLocal()
        fetchRemote()
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
        let ended = endedTracker.reconcile(active: active, at: Date())
        let local = active + ended
        localSessions = local
        lastSuccess = Date()
        sessionsUnavailable = false

        // 로컬 출처를 읽은 응답을 기준으로 정리한다. deadhd 응답은 보강일 뿐이다.
        let before = acknowledgements
        acknowledgements.prune(keeping: SessionsResponse(sessions: local))
        if acknowledgements != before {
            persistAcknowledgements()
        }
        applyOverlay()
        deliverAttentionNotes(isFirstUpdate: !hasHandledFirstUpdate)
        hasHandledFirstUpdate = true
    }

    /// deadhd 응답이 오면 같은 sessionId 의 보강 값만 덧입힌다. 실패해도 화면은 그대로 둔다.
    private func applyOverlay() {
        guard let localSessions else { return }
        response = SessionsResponse(
            sessions: SessionOverlay.apply(local: localSessions, remote: remoteSessions ?? [])
        )
        refresh()
    }

    private func fetchRemote() {
        guard !remoteFetching, let url = deadhdSessionsURL else { return }
        remoteFetching = true
        var request = URLRequest(url: url)
        request.timeoutInterval = 2
        request.cachePolicy = .reloadIgnoringLocalCacheData
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.remoteFetching = false
                guard error == nil,
                      let http = response as? HTTPURLResponse,
                      (200..<300).contains(http.statusCode),
                      let data,
                      let decoded = try? JSONDecoder().decode(SessionsResponse.self, from: data)
                else {
                    self.remoteSessions = nil
                    self.applyOverlay()
                    return
                }
                self.remoteSessions = decoded.sessions
                self.applyOverlay()
            }
        }.resume()
    }

    private func markFailure() {
        if let lastSuccess, Date().timeIntervalSince(lastSuccess) < failureGrace {
            refresh()
            return
        }
        sessionsUnavailable = true
        refresh()
    }

    func refresh(now: Date = Date()) {
        snoozes = snoozes.filter { $0.value > now }
        groups = Grouping.group(
            response,
            now: now,
            acknowledgedDone: acknowledgements.keys,
            snoozedUntil: snoozes
        )
        hiddenDoneCount = acknowledgements.hiddenCount(in: response, now: now)
        // 완료 알림도 확인(숨김)하거나 진행 중으로 돌아가면 이 집합에서 빠져 알림 센터에서 거둬진다.
        notificationCenter.syncDelivered(
            keeping: Set((groups.attention + groups.done).map(\.acknowledgeKey))
        )
    }

    private func deliverAttentionNotes(isFirstUpdate: Bool) {
        let attention = attentionNotifier.evaluate(
            for: groups.attention,
            popoverVisible: popoverVisible,
            enabled: attentionNotifications,
            isFirstUpdate: isFirstUpdate
        )
        let done = doneNotifier.evaluate(
            done: groups.done,
            working: groups.working,
            attention: groups.attention,
            popoverVisible: popoverVisible,
            enabled: doneNotifications,
            isFirstUpdate: isFirstUpdate
        )
        Self.logBatch("확인 필요", attention)
        Self.logBatch("완료", done)
        notificationCenter.post(attention.notes, kind: .attention)
        notificationCenter.post(done.notes, kind: .done)
    }

    /// 갱신마다 후보 수와 억제 사유를 남긴다. 후보가 있으면 기본 로그로도 남긴다.
    private static func logBatch(_ label: String, _ batch: NotificationBatch) {
        let line = "\(label) 후보=\(batch.candidates) 전송=\(batch.notes.count) 억제=\(batch.suppression?.rawValue ?? "없음")"
        logger.info("\(line, privacy: .public)")
        guard batch.candidates > 0 else { return }
        logger.notice("\(line, privacy: .public)")
    }

    // MARK: - 동작

    func open(_ item: DisplayItem) {
        switch item.clickAction {
        case .detail(let href):
            if let presenter = detailPresenter {
                presenter.showDetail(for: item)
            } else if let url = URL(string: href) {
                NSWorkspace.shared.open(url)
            }
        case .orca(let handle):
            switchTerminal(handle)
        case .cwd(let cwd):
            switchToCwd(cwd, name: item.title)
        case .none:
            break
        }
    }

    func openPullRequest(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }

    func openInOrca(_ item: DisplayItem) {
        if let handle = item.orcaTerminal, !handle.isEmpty {
            switchTerminal(handle)
        } else if let cwd = item.cwd, !cwd.isEmpty {
            switchToCwd(cwd, name: item.title)
        }
    }

    private func switchTerminal(_ handle: String) {
        OrcaLauncher.switchTerminal(handle: handle) { [weak self] ok in
            if !ok { self?.showError("터미널이 닫혔어요") }
        }
    }

    private func switchToCwd(_ cwd: String, name: String) {
        OrcaLauncher.switchToCwd(cwd, name: name) { [weak self] ok in
            if !ok { self?.showError("Orca 에 이 세션의 터미널이 없어요") }
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
    }

    func showPanel() {
        panelVisible = true
    }

    func hidePanel() {
        panelVisible = false
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
