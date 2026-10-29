import AppKit
import Foundation
import PulseCore
import os

/// 패널을 옮긴 뒤 어디까지 갔는지.
enum MultiplexerMoveResult: Equatable {
    case success
    case panelMissing
    case executableMissing
    case clientMissing
    case hostUnknown
    case timedOut
}

/// herdr·tmux 패널로 이동하고, 그 클라이언트가 떠 있는 터미널 앱을 앞으로 꺼낸다.
enum MultiplexerLauncher {
    private static let logger = Logger(subsystem: "io.github.lcalmsky.pulse", category: "multiplexer")
    private static let defaultHerdrSocket = "~/.config/herdr/herdr.sock"
    private static let requestTimeoutSeconds = 2
    private static let commandTimeoutSeconds = 3
    private static let hostSwitchWaitSeconds = 5

    /// 완료 콜백은 메인 스레드에서 호출된다.
    static func focus(_ pane: MultiplexerPane, completion: @escaping (MultiplexerMoveResult) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let result: MultiplexerMoveResult
            switch pane.kind {
            case .herdr: result = moveHerdr(pane)
            case .tmux: result = moveTmux(pane)
            }
            DispatchQueue.main.async { completion(result) }
        }
    }

    // MARK: - herdr

    private static func moveHerdr(_ pane: MultiplexerPane) -> MultiplexerMoveResult {
        guard focusHerdr(pane) else {
            logger.error("herdr 패널 포커스 실패: \(pane.paneId, privacy: .public)")
            return .panelMissing
        }
        guard let client = herdrClient(for: pane) else {
            logger.error("herdr 클라이언트 프로세스 없음")
            return .clientMissing
        }
        guard let host = client.host else {
            logger.error("herdr 클라이언트의 터미널 앱을 모름: pid \(client.pid, privacy: .public)")
            return .hostUnknown
        }
        return bringForward(host)
    }

    private static func herdrSocketPath(_ pane: MultiplexerPane) -> String {
        let configured = pane.socketPath ?? defaultHerdrSocket
        return NSString(string: configured).expandingTildeInPath
    }

    private static func focusHerdr(_ pane: MultiplexerPane) -> Bool {
        let path = herdrSocketPath(pane)
        // herdr 서버는 응답 한 줄을 보낸 뒤 연결을 닫으므로 요청마다 새로 연결한다.
        for line in Multiplexer.focusRequestLines(for: pane) {
            guard let fd = connectUnixSocket(path) else { return false }
            defer { close(fd) }
            guard send(line + "\n", to: fd), let response = readLine(from: fd),
                  Multiplexer.isSuccessResponse(response) else {
                return false
            }
        }
        return true
    }

    private static func connectUnixSocket(_ path: String) -> Int32? {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Array(path.utf8)
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        guard !pathBytes.isEmpty, pathBytes.count < capacity else { return nil }
        withUnsafeMutableBytes(of: &address.sun_path) { raw in
            raw.copyBytes(from: pathBytes)
            raw[pathBytes.count] = 0
        }

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        var timeout = timeval(tv_sec: requestTimeoutSeconds, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        // 닫힌 연결에 쓰면 SIGPIPE 로 앱이 통째로 꺼지므로 EPIPE 오류로 받는다.
        var noSigPipe: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))

        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard result == 0 else {
            logger.error("herdr 소켓 연결 실패: \(path, privacy: .public)")
            close(fd)
            return nil
        }
        return fd
    }

    private static func send(_ text: String, to fd: Int32) -> Bool {
        let bytes = Array(text.utf8)
        return bytes.withUnsafeBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return true }
            var written = 0
            while written < bytes.count {
                let count = write(fd, base + written, bytes.count - written)
                if count < 0, errno == EINTR { continue }
                guard count > 0 else { return false }
                written += count
            }
            return true
        }
    }

    private static func readLine(from fd: Int32) -> String? {
        var data = Data()
        var byte: UInt8 = 0
        while true {
            let count = read(fd, &byte, 1)
            if count < 0, errno == EINTR { continue }
            guard count == 1 else { return nil }
            if byte == 0x0A { break }
            data.append(byte)
            if data.count > 1 << 20 { return nil }
        }
        return String(data: data, encoding: .utf8)
    }

    /// 패널의 소켓 경로가 가리키는 herdr 세션에 붙은 TUI 클라이언트 중 가장 최근 것.
    /// 세션 목록을 읽지 못하면 전체 클라이언트 중 가장 최근 것으로 물러선다.
    /// host 가 nil 이면 클라이언트는 찾았지만 앱을 모른다.
    private static func herdrClient(for pane: MultiplexerPane) -> (pid: pid_t, host: MultiplexerHost?)? {
        var clients: [(pid: pid_t, arguments: [String])] = []
        for pid in allPids() where pid > 0 {
            guard let args = ProcessEnvironment.procArgs(Int(pid)) else { continue }
            let arguments = ProcessEnvironment.arguments(inProcArgs: args)
            guard Multiplexer.isHerdrClient(arguments: arguments) else { continue }
            clients.append((pid, arguments))
        }
        guard !clients.isEmpty else { return nil }

        let chosen: (pid: pid_t, arguments: [String])?
        let sessions = herdrExecutable(for: clients).flatMap { herdrSessions(executable: $0) }
        if let sessions,
           let session = Multiplexer.herdrSession(forSocket: herdrSocketPath(pane), in: sessions) {
            chosen = clients
                .filter { Multiplexer.herdrClient(arguments: $0.arguments, attachesTo: session) }
                .max { $0.pid < $1.pid }
            // 그 세션에 붙은 클라이언트가 없으면 다른 세션의 클라이언트로 옮기지 않는다.
            guard chosen != nil else { return nil }
        } else {
            if sessions == nil {
                logger.error("herdr 세션 목록을 읽지 못해 가장 최근 클라이언트로 이동")
            } else {
                logger.error("herdr 세션 목록에 패널 소켓이 없어 가장 최근 클라이언트로 이동: \(herdrSocketPath(pane), privacy: .public)")
            }
            chosen = clients.max { $0.pid < $1.pid }
        }
        guard let chosen else { return nil }
        logChosen(chosen)
        guard let args = ProcessEnvironment.procArgs(Int(chosen.pid)) else { return nil }
        return (chosen.pid, Multiplexer.host(inProcArgs: args))
    }

    private static func logChosen(_ client: (pid: pid_t, arguments: [String])) {
        let name = Multiplexer.herdrSessionName(arguments: client.arguments) ?? "default"
        logger.info("herdr 클라이언트 선택: pid \(client.pid, privacy: .public) 세션 \(name, privacy: .public)")
    }

    private static func herdrExecutable(for clients: [(pid: pid_t, arguments: [String])]) -> String? {
        for client in clients {
            if let path = executablePath(forPid: client.pid) { return path }
        }
        let candidates = ["~/.local/bin/herdr", "/opt/homebrew/bin/herdr", "/usr/local/bin/herdr"]
            .map { NSString(string: $0).expandingTildeInPath }
        return ExecutablePath.firstExecutable(in: candidates) {
            FileManager.default.isExecutableFile(atPath: $0)
        }
    }

    private static func herdrSessions(executable: String) -> [HerdrSession]? {
        let result = run(executable, ["session", "list", "--json"])
        guard !result.timedOut, result.status == 0 else { return nil }
        return Multiplexer.herdrSessions(fromListJSON: result.output)
    }

    private static func executablePath(forPid pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        return String(cString: buffer)
    }

    private static func allPids() -> [pid_t] {
        let estimate = proc_listallpids(nil, 0)
        guard estimate > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(estimate) + 64)
        let count = proc_listallpids(&pids, Int32(MemoryLayout<pid_t>.stride * pids.count))
        guard count > 0 else { return [] }
        return Array(pids.prefix(Int(count)))
    }

    // MARK: - tmux

    private static func moveTmux(_ pane: MultiplexerPane) -> MultiplexerMoveResult {
        guard let executable = tmuxExecutable() else {
            logger.error("tmux 실행 파일 없음")
            return .executableMissing
        }
        guard let socket = pane.socketPath else {
            logger.error("tmux 소켓 경로 없음: \(pane.paneId, privacy: .public)")
            return .panelMissing
        }
        let listing = run(
            executable,
            ["-S", socket, "list-clients", "-F", "#{client_activity}\t#{client_pid}\t#{client_tty}"]
        )
        guard !listing.timedOut else { return .timedOut }
        guard listing.status == 0 else {
            logger.error("tmux list-clients 실패: \(listing.status, privacy: .public)")
            return .panelMissing
        }
        guard let client = newestTmuxClient(listing.output) else {
            logger.error("tmux 에 붙은 클라이언트 없음: \(pane.paneId, privacy: .public)")
            return .clientMissing
        }
        let switching = run(
            executable,
            ["-S", socket, "switch-client", "-c", client.tty, "-t", pane.paneId]
        )
        guard !switching.timedOut else { return .timedOut }
        guard switching.status == 0 else {
            logger.error("tmux switch-client 실패: \(pane.paneId, privacy: .public)")
            return .panelMissing
        }
        _ = run(executable, ["-S", socket, "select-window", "-t", pane.paneId])
        _ = run(executable, ["-S", socket, "select-pane", "-t", pane.paneId])

        guard let args = ProcessEnvironment.procArgs(Int(client.pid)),
              let host = Multiplexer.host(inProcArgs: args) else {
            logger.error("tmux 클라이언트의 터미널 앱을 모름: pid \(client.pid, privacy: .public)")
            return .hostUnknown
        }
        return bringForward(host)
    }

    private static func tmuxExecutable() -> String? {
        ExecutablePath.firstExecutable(
            in: ["/opt/homebrew/bin/tmux", "/usr/local/bin/tmux", "/usr/bin/tmux"]
        ) { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private static func newestTmuxClient(_ output: String) -> (activity: Int, pid: pid_t, tty: String)? {
        let clients = output.split(separator: "\n").compactMap { line -> (Int, pid_t, String)? in
            let parts = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard parts.count >= 3, let activity = Int(parts[0]), let pid = pid_t(parts[1]) else {
                return nil
            }
            return (activity, pid, String(parts[2]))
        }
        guard let client = clients.max(by: { $0.0 < $1.0 }) else { return nil }
        return (client.0, client.1, client.2)
    }

    // MARK: - 공통

    private static func bringForward(_ host: MultiplexerHost) -> MultiplexerMoveResult {
        switch host {
        case .orca(let handle):
            let semaphore = DispatchSemaphore(value: 0)
            var moved = false
            OrcaLauncher.switchTerminal(handle: handle) { succeeded in
                moved = succeeded
                semaphore.signal()
            }
            _ = semaphore.wait(timeout: .now() + .seconds(hostSwitchWaitSeconds))
            if !moved {
                logger.error("Orca 터미널 전환 실패: \(handle, privacy: .public)")
            }
            return moved ? .success : .hostUnknown
        case .app(let bundleIdentifier):
            var activated = false
            DispatchQueue.main.sync {
                activated = NSRunningApplication
                    .runningApplications(withBundleIdentifier: bundleIdentifier)
                    .first?
                    .activate(options: []) ?? false
            }
            if !activated {
                logger.error("터미널 앱 활성화 실패: \(bundleIdentifier, privacy: .public)")
            }
            return activated ? .success : .hostUnknown
        }
    }

    private static func run(
        _ executable: String,
        _ arguments: [String]
    ) -> (status: Int32, output: String, timedOut: Bool) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardError = FileHandle.nullDevice
        let pipe = Pipe()
        process.standardOutput = pipe
        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }
        do {
            try process.run()
        } catch {
            logger.error("실행 실패: \(executable, privacy: .public) \(error.localizedDescription, privacy: .public)")
            return (1, "", false)
        }
        // 출력은 파이프가 닫혀야 끝나므로 종료와 따로 기다린다.
        let output = OutputBuffer()
        let read = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            output.data = pipe.fileHandleForReading.readDataToEndOfFile()
            read.signal()
        }
        guard exited.wait(timeout: .now() + .seconds(commandTimeoutSeconds)) == .success else {
            logger.error(
                "명령 시간 초과: \(([executable] + arguments).joined(separator: " "), privacy: .public)"
            )
            process.terminate()
            if exited.wait(timeout: .now() + .seconds(1)) == .timedOut {
                kill(process.processIdentifier, SIGKILL)
                _ = exited.wait(timeout: .now() + .seconds(1))
            }
            return (1, "", true)
        }
        // 자손이 파이프를 쥐어 읽기가 안 끝났으면 읽는 중인 버퍼를 건드리지 않는다.
        guard read.wait(timeout: .now() + .seconds(1)) == .success else {
            return (process.terminationStatus, "", false)
        }
        return (process.terminationStatus, String(data: output.data, encoding: .utf8) ?? "", false)
    }
}

/// `run` 이 백그라운드 큐에서 읽은 출력을 메인 흐름으로 넘기는 상자.
private final class OutputBuffer: @unchecked Sendable {
    var data = Data()
}
