import Foundation

/// 진행 중 행의 상태 줄 아래에 붙는 「지금 뭐 하는지」 한 줄.
/// 체크리스트 단계 → 실행 중인 도구 → 마지막 답의 마지막 문장 순서로 고르고,
/// 이미 상태 줄에 있는 문구는 중복으로 그리지 않는다.
public enum NowLine {
    static let stagePrefix = "▶ "
    public static let sentenceLimit = 120
    private static let sentenceEndings: Set<Character> = [".", "!", "?", "。", "！", "？", "…"]
    private static let listMarkers: Set<Character> = ["-", "*", "+", "•", "·", "–", "—"]

    public static func resolve(
        stage: String?,
        currentAction: String?,
        lastSentence: String?,
        statusLine: String
    ) -> String? {
        if let stage = Grouping.clean(stage), !statusLine.contains(stage) {
            return stagePrefix + stage
        }
        if let action = Grouping.clean(currentAction), !statusLine.contains(action) {
            return action
        }
        if let sentence = Grouping.clean(lastSentence), !statusLine.contains(sentence) {
            return sentence
        }
        return nil
    }

    /// 잘리지 않은 답변 평문에서 한 줄로 보여 줄 마지막 문장을 고른다.
    public static func lastSentence(_ value: String?) -> String? {
        guard let value else { return nil }
        let text = value.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        guard !text.isEmpty else { return nil }
        var sentences: [String] = []
        var start = text.startIndex
        var index = text.startIndex
        while index < text.endIndex {
            guard sentenceEndings.contains(text[index]) else {
                index = text.index(after: index)
                continue
            }
            var end = index
            var next = text.index(after: end)
            while next < text.endIndex, sentenceEndings.contains(text[next]) {
                end = next
                next = text.index(after: end)
            }
            // 소수점(`v1.2`)은 문장 끝으로 보지 않는다.
            if index > text.startIndex, text[text.index(before: index)].isNumber,
               next < text.endIndex, text[next].isNumber {
                index = next
                continue
            }
            let sentence = text[start...end].trimmingCharacters(in: .whitespaces)
            if !sentence.isEmpty {
                sentences.append(sentence)
            }
            start = next
            index = next
        }
        let tail = text[start...].trimmingCharacters(in: .whitespaces)
        if !tail.isEmpty {
            sentences.append(tail)
        }
        return sentences.last(where: { !isFragment($0) }).map { clipped($0) }
    }

    /// 표 행·코드 펜스·목록 기호만 남은 조각은 한 줄로 그리지 않는다.
    static func isFragment(_ sentence: String) -> Bool {
        let trimmed = sentence.trimmingCharacters(in: .whitespaces)
        guard let first = trimmed.first else { return true }
        if trimmed.contains("|") || trimmed.contains("```") || trimmed.contains("~~~") {
            return true
        }
        if listMarkers.contains(first) {
            return true
        }
        let digits = trimmed.prefix(while: { $0.isNumber })
        if !digits.isEmpty {
            let rest = trimmed.dropFirst(digits.count)
            if rest.first == "." || rest.first == ")" {
                return true
            }
        }
        return false
    }

    /// 자를 때는 문장 앞쪽을 남기고 끝에 `…` 를 붙여 상한을 넘지 않는다.
    static func clipped(_ sentence: String) -> String {
        guard sentence.count > sentenceLimit else { return sentence }
        return String(sentence.prefix(sentenceLimit - 1)) + "…"
    }
}
