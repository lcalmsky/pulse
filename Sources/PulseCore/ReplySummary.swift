import Foundation

/// 알림 카드 본문에 쓰는 답변 요약 한 문장. 코드·목록·표·제목은 본문에서 빼고 첫 문장만 남긴다.
public enum ReplySummary {
    public static let limit = 90

    /// 답변 원문(마크다운)에서 첫 문장 하나를 고른다. 코드 블록·목록·표·제목 줄은 건너뛰고, URL 은 지운다.
    public static func firstSentence(_ raw: String?) -> String? {
        guard let paragraph = firstParagraph(raw) else { return nil }
        return clip(sentence(in: clean(paragraph)))
    }

    // MARK: - 첫 문단

    private static func firstParagraph(_ raw: String?) -> String? {
        guard let raw else { return nil }
        var body: [String] = []
        var started = false
        var inFence = false
        var firstListItem: String?

        for line in raw.split(separator: "\n", omittingEmptySubsequences: false) {
            let original = String(line)
            let trimmed = original.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                inFence.toggle()
                if started { break }
                continue
            }
            if inFence { continue }
            if original.hasPrefix("    ") || original.hasPrefix("\t") {
                if started { break }
                continue
            }
            if trimmed.isEmpty {
                if started { break }
                continue
            }
            if let item = listItemText(trimmed) {
                if firstListItem == nil { firstListItem = item }
                if started { break }
                continue
            }
            if isSkipped(trimmed) {
                if started { break }
                continue
            }
            let text = stripQuote(trimmed)
            if text.isEmpty {
                if started { break }
                continue
            }
            body.append(text)
            started = true
        }

        if body.isEmpty { return firstListItem }
        return body.joined(separator: " ")
    }

    private static func isSkipped(_ line: String) -> Bool {
        if line.hasPrefix("|") { return true }
        if line.range(of: #"^#{1,6}(\s|$)"#, options: .regularExpression) != nil { return true }
        guard let first = line.first, "-*_".contains(first) else { return false }
        return line.count >= 3 && line.allSatisfy { $0 == first }
    }

    private static func listItemText(_ line: String) -> String? {
        for marker in ["- ", "* ", "+ "] where line.hasPrefix(marker) {
            return line.dropFirst(marker.count).trimmingCharacters(in: .whitespaces)
        }
        guard let match = line.range(of: #"^\d+[.)]\s"#, options: .regularExpression) else { return nil }
        return line[match.upperBound...].trimmingCharacters(in: .whitespaces)
    }

    private static func stripQuote(_ line: String) -> String {
        var value = line
        while value.hasPrefix(">") {
            value = value.dropFirst().trimmingCharacters(in: .whitespaces)
        }
        return value
    }

    // MARK: - 문장

    private static func clean(_ text: String) -> String {
        var value = replace(#"!\[[^\]]*\]\([^)]*\)"#, in: text, template: "")
        value = PlainText.markdown(value)
        value = replace(#"<?https?://[^\s>]*[^\s>.,;:!?)\]]>?"#, in: value, template: "")
        value = replace(#"\s+([.,;:!?。])"#, in: value, template: "$1")
        value = replace(#"\(\s*\)"#, in: value, template: "")
        return value.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    private static func sentence(in text: String) -> String {
        let characters = Array(text)
        let endings: Set<Character> = [".", "!", "?", "。"]
        let closers: Set<Character> = ["\"", "'", "”", "’", ")", "]"]

        var index = 0
        while index < characters.count {
            guard endings.contains(characters[index]) else {
                index += 1
                continue
            }
            // 소수점(v1.2)은 문장 끝이 아니다.
            if characters[index] == ".", index > 0, index + 1 < characters.count,
               characters[index - 1].isNumber, characters[index + 1].isNumber {
                index += 1
                continue
            }
            var end = index + 1
            while end < characters.count, endings.contains(characters[end]) {
                end += 1
            }
            while end < characters.count, closers.contains(characters[end]) {
                end += 1
            }
            if end == characters.count || characters[end].isWhitespace {
                return String(characters[0..<end])
            }
            index = end
        }
        return text
    }

    private static func clip(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard trimmed.count > limit else { return trimmed }
        return trimmed.prefix(limit - 1).trimmingCharacters(in: .whitespaces) + "…"
    }

    private static func replace(_ pattern: String, in text: String, template: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: template)
    }
}
