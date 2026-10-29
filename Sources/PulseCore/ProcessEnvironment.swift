import Darwin
import Foundation

/// `sysctl(KERN_PROCARGS2)` 가 돌려주는 버퍼에서 환경 변수와 인자를 읽는다.
/// 버퍼 모양은 argc(Int32) · 실행 경로 · NUL 채움 · 인자 argc 개 · 환경 변수들 · 빈 문자열 순이다.
public enum ProcessEnvironment {
    /// Orca 가 자기 터미널에서 띄운 프로세스에 넣어 주는 터미널 핸들 변수.
    public static let orcaTerminalHandleKey = "ORCA_TERMINAL_HANDLE"

    /// herdr 패널 안의 프로세스에 herdr 가 넣어 주는 변수들.
    public static let herdrPaneIdKey = "HERDR_PANE_ID"
    public static let herdrTabIdKey = "HERDR_TAB_ID"
    public static let herdrWorkspaceIdKey = "HERDR_WORKSPACE_ID"
    public static let herdrSocketPathKey = "HERDR_SOCKET_PATH"

    /// tmux 패널 안의 프로세스에 tmux 가 넣어 주는 변수들. `TMUX` 는 소켓 경로로 시작한다.
    public static let tmuxPaneKey = "TMUX_PANE"
    public static let tmuxKey = "TMUX"

    /// 프로세스의 procargs 버퍼를 읽는다. 이미 끝난 프로세스나 권한이 없는 프로세스면 nil.
    public static func procArgs(_ pid: Int) -> Data? {
        guard pid > 0 else { return nil }
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, Int32(pid)]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0 else { return nil }
        return Data(buffer.prefix(size))
    }

    public static func value(_ key: String, inProcArgs data: Data) -> String? {
        let bytes = [UInt8](data)
        guard bytes.count > 4 else { return nil }
        let argc = bytes[0..<4].withUnsafeBytes { Int(Int32(littleEndian: $0.loadUnaligned(as: Int32.self))) }
        guard argc >= 0 else { return nil }

        var index = 4
        index = skipString(bytes, from: index)
        while index < bytes.count, bytes[index] == 0 { index += 1 }
        for _ in 0..<argc {
            guard index < bytes.count else { return nil }
            index = skipString(bytes, from: index)
        }

        let prefix = Array((key + "=").utf8)
        while index < bytes.count, bytes[index] != 0 {
            let end = skipString(bytes, from: index) - 1
            let entry = bytes[index..<min(end, bytes.count)]
            if entry.starts(with: prefix) {
                let value = String(decoding: entry.dropFirst(prefix.count), as: UTF8.self)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return value.isEmpty ? nil : value
            }
            index = end + 1
        }
        return nil
    }

    /// 버퍼 앞부분의 인자 argc 개를 argv 배열로 꺼낸다.
    public static func arguments(inProcArgs data: Data) -> [String] {
        let bytes = [UInt8](data)
        guard bytes.count > 4 else { return [] }
        let argc = bytes[0..<4].withUnsafeBytes { Int(Int32(littleEndian: $0.loadUnaligned(as: Int32.self))) }
        guard argc >= 0 else { return [] }

        var index = 4
        index = skipString(bytes, from: index)
        while index < bytes.count, bytes[index] == 0 { index += 1 }
        var arguments: [String] = []
        for _ in 0..<argc {
            guard index < bytes.count else { return arguments }
            let end = skipString(bytes, from: index)
            arguments.append(String(decoding: bytes[index..<min(end - 1, bytes.count)], as: UTF8.self))
            index = end
        }
        return arguments
    }

    /// `from` 에서 시작하는 문자열의 NUL 다음 위치를 돌려준다.
    private static func skipString(_ bytes: [UInt8], from start: Int) -> Int {
        var index = start
        while index < bytes.count, bytes[index] != 0 { index += 1 }
        return index + 1
    }
}
