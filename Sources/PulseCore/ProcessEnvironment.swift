import Foundation

/// `sysctl(KERN_PROCARGS2)` 가 돌려주는 버퍼에서 환경 변수를 읽는다.
/// 버퍼 모양은 argc(Int32) · 실행 경로 · NUL 채움 · 인자 argc 개 · 환경 변수들 · 빈 문자열 순이다.
public enum ProcessEnvironment {
    /// Orca 가 자기 터미널에서 띄운 프로세스에 넣어 주는 터미널 핸들 변수.
    public static let orcaTerminalHandleKey = "ORCA_TERMINAL_HANDLE"

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

    /// `from` 에서 시작하는 문자열의 NUL 다음 위치를 돌려준다.
    private static func skipString(_ bytes: [UInt8], from start: Int) -> Int {
        var index = start
        while index < bytes.count, bytes[index] != 0 { index += 1 }
        return index + 1
    }
}
