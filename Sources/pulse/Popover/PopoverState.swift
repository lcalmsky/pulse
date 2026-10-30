import Combine
import Foundation
import PulseCore

final class PopoverState: ObservableObject {
    @Published var filter: SessionFilter = .all
    @Published var selectedIndex: Int?
    @Published var optionDown = false
    @Published var shortcutHintsVisible = false
    @Published var settingsOpen = false
    /// 키보드로 단계 펼침을 바꾼 뒤 선택 행을 다시 보이게 하라는 요청. 값이 커지면 팝오버가 최소한으로 스크롤한다.
    @Published var revealRequest = 0
    @Published var query = ""
    /// 검색 필드가 실제로 포커스를 가졌는지. 키 처리가 글자를 직접 넣을지 필드에 넘길지 가른다.
    @Published var searchFocused = false
    /// 값이 커질 때마다 검색 필드에 포커스를 준다.
    @Published var searchFocusRequest = 0
    /// Space 로 마지막에 연 답 대기 세션. 다음 Space 가 그다음 후보로 가게 한다.
    var lastReplyJumpSessionId: String?
    private var optionHoldWork: DispatchWorkItem?

    func reset() {
        selectedIndex = nil
        setOptionDown(false)
        settingsOpen = false
        query = ""
        searchFocused = false
        lastReplyJumpSessionId = nil
    }

    func setOptionDown(_ down: Bool) {
        if optionDown != down {
            optionDown = down
        }
        optionHoldWork?.cancel()
        optionHoldWork = nil
        guard down else {
            if shortcutHintsVisible { shortcutHintsVisible = false }
            return
        }
        guard !shortcutHintsVisible else { return }
        let work = DispatchWorkItem { [weak self] in
            self?.shortcutHintsVisible = true
        }
        optionHoldWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    func select(_ filter: SessionFilter) {
        self.filter = filter
        selectedIndex = nil
    }

    /// 검색어가 바뀌면 일치 목록의 첫 행으로 선택을 옮긴다.
    func syncSelection(to groups: GroupedSessions) {
        selectedIndex = filter.selectableItems(in: groups, query: query).isEmpty ? nil : 0
    }

    func clearSearch() {
        query = ""
        searchFocused = false
    }
}
