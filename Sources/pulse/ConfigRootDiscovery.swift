import Darwin
import Foundation
import PulseCore

/// 실행 중인 프로세스의 환경에서 `CLAUDE_CONFIG_DIR` 값을 모은다.
final class ConfigRootDiscovery {
    private static let configDirKey = "CLAUDE_CONFIG_DIR"

    /// pid 마다 한 번만 읽는다. 읽기에 실패한 pid 는 `scanned` 에만 남겨 다시 읽지 않는다.
    private var values: [pid_t: String] = [:]
    private var scanned: Set<pid_t> = []

    func discoveredRoots() -> [String] {
        let pids = Self.allPids()
        let live = Set(pids)
        scanned.formIntersection(live)
        values = values.filter { live.contains($0.key) }

        var discovered: [String] = []
        for pid in pids {
            if scanned.insert(pid).inserted {
                values[pid] = ProcessEnvironment.procArgs(Int(pid)).flatMap {
                    ProcessEnvironment.value(Self.configDirKey, inProcArgs: $0)
                }
            }
            if let value = values[pid] {
                discovered.append(value)
            }
        }
        return discovered
    }

    private static func allPids() -> [pid_t] {
        let estimate = proc_listallpids(nil, 0)
        guard estimate > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(estimate) + 64)
        let count = proc_listallpids(&pids, Int32(MemoryLayout<pid_t>.stride * pids.count))
        guard count > 0 else { return [] }
        return Array(pids.prefix(Int(count))).filter { $0 > 0 }
    }
}
