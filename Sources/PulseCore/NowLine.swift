import Foundation

/// 진행 중 행의 상태 줄 아래에 붙는 「지금 뭐 하는지」 한 줄.
/// 체크리스트 단계 → 실행 중인 도구 → 마지막 답의 마지막 문장 순서로 고르고,
/// 이미 상태 줄에 있는 문구는 중복으로 그리지 않는다.
public enum NowLine {
    static let stagePrefix = "▶ "
    private static let sentenceEndings: Set<Character> = [".", "!", "?", "。", "！", "？", "…"]

    public static func resolve(
        stage: String?,
        currentAction: String?,
        reply: String?,
        statusLine: String
    ) -> String? {
        if let stage = Grouping.clean(stage), !statusLine.contains(stage) {
            return stagePrefix + stage
        }
        if let action = Grouping.clean(currentAction), !statusLine.contains(action) {
            return action
        }
        if let sentence = lastSentence(reply), !statusLine.contains(sentence) {
            return sentence
        }
        return nil
    }

    static func lastSentence(_ value: String?) -> String? {
        guard let text = Grouping.clean(value) else { return nil }
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
        return sentences.last
    }
}
