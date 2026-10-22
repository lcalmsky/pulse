import Foundation

/// 세션 검색. 검색어를 공백으로 나눈 낱말이 모두 어느 한 표시 필드에 들어 있으면 일치한다.
public enum SessionSearch {
    public static func matches(_ item: DisplayItem, query: String) -> Bool {
        let tokens = query.split(whereSeparator: { $0.isWhitespace })
        guard !tokens.isEmpty else { return true }
        let fields = searchableFields(item)
        return tokens.allSatisfy { token in
            fields.contains { $0.localizedStandardContains(String(token)) }
        }
    }

    static func searchableFields(_ item: DisplayItem) -> [String] {
        var fields = [item.title]
        if let placeText = item.placeText { fields.append(placeText) }
        if let cwd = item.cwd {
            let last = (cwd as NSString).lastPathComponent
            if !last.isEmpty { fields.append(last) }
        }
        if let key = item.key { fields.append(key) }
        if let keyTag = item.keyTag { fields.append(keyTag) }
        if let jiraKey = item.jiraKey { fields.append(jiraKey) }
        if let prTag = item.prTag { fields.append(prTag) }
        for link in item.extraPRs {
            fields.append(link.label ?? "#\(link.number)")
        }
        return fields
    }
}
