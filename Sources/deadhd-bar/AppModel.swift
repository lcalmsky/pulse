import AppKit
import Combine
import Foundation
import DeadhdBarCore

protocol DetailPresenting: AnyObject {
    func showDetail(for item: DisplayItem)
}

final class AppModel: ObservableObject {
    @Published private(set) var groups = GroupedSessions.empty
    @Published private(set) var serverOff = true
    @Published private(set) var errorMessage: String?
    @Published private(set) var panelVisible = false
    @Published var collapsed = false
    @Published private(set) var hiddenDoneCount = 0
    @Published private(set) var recentAcknowledgedCount = 0

    weak var detailPresenter: DetailPresenting?

    private static let acknowledgedKey = "acknowledgedDoneKeys"
    private static let defaultSkillDir = "~/.claude/skills/deadhd"

    private let defaults = UserDefaults.standard
    private let port: String
    private let offGrace: TimeInterval = 15
    private let pollInterval: TimeInterval = 3
    private let recentUndoWindow: TimeInterval = 10

    private var response: SessionsResponse?
    private var lastSuccess: Date?
    private var timer: Timer?
    private var snoozes: [String: Date] = [:]
    private var acknowledgements: DoneAcknowledgements
    private var errorGeneration = 0
    private var recentAcknowledgedGeneration = 0
    private var polling = false

    init() {
        port = ProcessInfo.processInfo.environment["DEADHD_PORT"] ?? "47320"
        acknowledgements = DoneAcknowledgements(
            keys: Set(defaults.stringArray(forKey: Self.acknowledgedKey) ?? [])
        )
    }

    func start() {
        poll()
        let timer = Timer(timeInterval: pollInterval, repeats: true) { [weak self] _ in
            self?.poll()
        }
        timer.tolerance = 0.5
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    // MARK: - 폴링

    private var sessionURL: URL? {
        URL(string: "http://127.0.0.1:\(port)/sessions.json")
    }

    func poll() {
        guard !polling, let url = sessionURL else { return }
        polling = true
        var request = URLRequest(url: url)
        request.timeoutInterval = 2
        request.cachePolicy = .reloadIgnoringLocalCacheData
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.polling = false
                self.handle(data: data, response: response, error: error)
            }
        }.resume()
    }

    private func handle(data: Data?, response: URLResponse?, error: Error?) {
        guard error == nil,
              let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              let data,
              let decoded = try? JSONDecoder().decode(SessionsResponse.self, from: data)
        else {
            markFailure()
            return
        }
        self.response = decoded
        lastSuccess = Date()
        serverOff = false
        // 응답을 받은 동안에만 지금 목록에 없는 세션의 키를 버린다.
        let before = acknowledgements
        acknowledgements.prune(keeping: decoded)
        if acknowledgements != before {
            persistAcknowledgements()
        }
        refresh()
    }

    private func markFailure() {
        if let lastSuccess, Date().timeIntervalSince(lastSuccess) < offGrace {
            refresh()
            return
        }
        serverOff = true
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
        recentAcknowledgedCount = count
        recentAcknowledgedGeneration += 1
        let generation = recentAcknowledgedGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + recentUndoWindow) { [weak self] in
            guard let self, self.recentAcknowledgedGeneration == generation else { return }
            self.recentAcknowledgedCount = 0
        }
        refresh()
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

    func startServer() {
        let configured = defaults.string(forKey: "skillDir") ?? Self.defaultSkillDir
        let directory = NSString(string: configured).expandingTildeInPath
        let script = (directory as NSString).appendingPathComponent("serve.py")
        guard FileManager.default.fileExists(atPath: script) else {
            showError("deadhd 스킬을 찾을 수 없어요")
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["python3", script, "--ensure"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                try process.run()
                process.waitUntilExit()
            } catch {
                DispatchQueue.main.async { self?.showError("서버를 시작하지 못했어요") }
                return
            }
            DispatchQueue.main.async {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self?.poll() }
            }
        }
    }
}
