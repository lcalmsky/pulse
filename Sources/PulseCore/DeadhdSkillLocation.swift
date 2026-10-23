import Foundation

/// deadhd 스킬 디렉터리 후보를 찾는 순서. 직접 설치한 스킬을 먼저, 플러그인 설치 경로를 다음에 본다.
public enum DeadhdSkillLocation {
    private static let pluginKey = "deadhd@deadhd"

    public static func directories(configDirectory: String, installedPlugins: Data?) -> [String] {
        var candidates = [
            (configDirectory as NSString).appendingPathComponent("skills/deadhd"),
        ]
        for installPath in installPaths(in: installedPlugins) {
            candidates.append((installPath as NSString).appendingPathComponent("skills/deadhd"))
        }

        var seen = Set<String>()
        return candidates.filter { seen.insert($0).inserted }
    }

    private static func installPaths(in data: Data?) -> [String] {
        guard let data,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let plugins = root["plugins"] as? [String: Any]
        else { return [] }

        let keys = plugins.keys
            .filter { $0.hasPrefix("deadhd@") }
            .sorted { lhs, rhs in
                if lhs == pluginKey { return true }
                if rhs == pluginKey { return false }
                return lhs < rhs
            }

        return keys.flatMap { key -> [String] in
            guard let entries = plugins[key] as? [Any] else { return [] }
            return entries.compactMap { entry in
                guard let entry = entry as? [String: Any],
                      let path = entry["installPath"] as? String,
                      path.hasPrefix("/")
                else { return nil }
                return path
            }
        }
    }
}
