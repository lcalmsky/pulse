import Foundation

/// Claude 응답 원문에 섞여 들어오는 마크다운 표기를 화면에 보일 평문으로 바꾼다.
public enum PlainText {
    public static func markdown(_ value: String) -> String {
        let kept = value
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                return !trimmed.hasPrefix("```") && !trimmed.hasPrefix("~~~")
            }
            .map(stripLinePrefix)

        var text = kept.joined(separator: " ")
        text = replace(#"\[([^\]]*)\]\([^)]*\)"#, in: text, template: "$1")
        text = text.replacingOccurrences(of: "`", with: "")
        text = replace(#"\*\*([^\s*](?:[^*]*[^\s*])?)\*\*"#, in: text, template: "$1")
        text = replace(#"__([^\s_](?:[^_]*[^\s_])?)__"#, in: text, template: "$1")
        text = replace(#"(?<![\p{L}\p{N}])_([^\s_](?:[^_]*[^\s_])?)_(?![\p{L}\p{N}])"#, in: text, template: "$1")
        text = replace(#"\*([^\s*](?:[^*]*[^\s*])?)\*"#, in: text, template: "$1")

        return text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    private static func stripLinePrefix(_ line: Substring) -> Substring {
        var text = line
        while true {
            let trimmed = text.drop(while: { $0 == " " || $0 == "\t" })
            if trimmed.first == ">" {
                text = trimmed.dropFirst().drop(while: { $0 == " " || $0 == "\t" })
                continue
            }
            if trimmed.first == "#" {
                let hashes = trimmed.prefix(while: { $0 == "#" })
                let rest = trimmed.dropFirst(hashes.count)
                if hashes.count <= 6, rest.first?.isWhitespace == true {
                    text = rest
                    continue
                }
            }
            if let first = trimmed.first, "-*+".contains(first),
               trimmed.dropFirst().first?.isWhitespace == true {
                text = trimmed.dropFirst()
                continue
            }
            return trimmed
        }
    }

    private static func replace(_ pattern: String, in text: String, template: String) -> String {
        guard let regex = RegexCache.regex(pattern) else { return text }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: template)
    }
}
