import AppKit
import Combine
import Foundation
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

    weak var detailPresenter: DetailPresenting?

    private static let acknowledgedKey = "acknowledgedDoneKeys"

    private let defaults = UserDefaults.standard
    private let port: String
    private let failureGrace: TimeInterval = 15
    private let pollInterval: TimeInterval = 3
    private let localSource = LocalSessionSource()
    private let localQueue = DispatchQueue(label: "dev.pulse.local-sessions", qos: .userInitiated)
    private lazy var notificationCenter = AttentionNotificationCenter(model: self)

    private var attentionNotifier = AttentionNotifier()
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
            attentionNotifications: defaults.object(forKey: AppSettings.attentionNotificationsKey) as? Bool
        )
        density = settings.density
        theme = settings.theme
        attentionNotifications = settings.attentionNotifications

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
            notificationCenter.removeAllDelivered()
        }
    }

    func setPopoverVisible(_ visible: Bool) {
        popoverVisible = visible
    }

    func start() {
        if attentionNotifications {
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
        notificationCenter.syncDelivered(keeping: Set(groups.attention.map(\.acknowledgeKey)))
    }

    private func deliverAttentionNotes(isFirstUpdate: Bool) {
        let notes = attentionNotifier.notes(
            for: groups.attention,
            popoverVisible: popoverVisible,
            enabled: attentionNotifications,
            isFirstUpdate: isFirstUpdate
        )
        notificationCenter.post(notes)
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
            switchToCwd(cwd)
        case .none:
            break
        }
    }

    func openInOrca(_ item: DisplayItem) {
        if let handle = item.orcaTerminal, !handle.isEmpty {
            switchTerminal(handle)
        } else if let cwd = item.cwd, !cwd.isEmpty {
            switchToCwd(cwd)
        }
    }

    private func switchTerminal(_ handle: String) {
        OrcaLauncher.switchTerminal(handle: handle) { [weak self] ok in
            if !ok { self?.showError("터미널이 닫혔어요") }
        }
    }

    private func switchToCwd(_ cwd: String) {
        OrcaLauncher.switchToCwd(cwd) { [weak self] ok in
            if !ok { self?.showError("Orca 에서 이 세션의 터미널을 찾지 못했어요") }
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
