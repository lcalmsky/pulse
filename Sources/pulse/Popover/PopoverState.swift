import Combine
import PulseCore

final class PopoverState: ObservableObject {
    @Published var filter: SessionFilter = .all
    @Published var selectedIndex: Int?
    @Published var optionDown = false
    @Published var settingsOpen = false
    /// 키보드로 단계 펼침을 바꾼 뒤 선택 행을 다시 보이게 하라는 요청. 값이 커지면 팝오버가 최소한으로 스크롤한다.
    @Published var revealRequest = 0

    func reset() {
        selectedIndex = nil
        optionDown = false
        settingsOpen = false
    }

    func select(_ filter: SessionFilter) {
        self.filter = filter
        selectedIndex = nil
    }
}
