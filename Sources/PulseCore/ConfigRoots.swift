import Foundation

/// 세션을 읽을 설정 디렉터리 목록을 만든다.
public enum ConfigRoots {
    /// 주 루트를 뺀 나머지는 처음 본 순서를 지키고, `~` 를 `home` 으로 펼친 뒤 표준화한 경로로 중복을 지운다.
    public static func merge(primary: String, discovered: [String], home: String) -> [String] {
        var roots: [String] = []
        var seen: Set<String> = []
        for raw in [primary] + discovered {
            let path = standardized(raw, home: home)
            guard !path.isEmpty, seen.insert(path).inserted else { continue }
            roots.append(path)
        }
        return roots
    }

    private static func standardized(_ raw: String, home: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        let expanded: String
        if trimmed == "~" {
            expanded = home
        } else if trimmed.hasPrefix("~/") {
            expanded = home + String(trimmed.dropFirst())
        } else {
            expanded = trimmed
        }
        return NSString(string: expanded).standardizingPath
    }
}
