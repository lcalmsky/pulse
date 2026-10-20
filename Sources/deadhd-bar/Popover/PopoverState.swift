import Combine
import DeadhdBarCore

final class PopoverState: ObservableObject {
    @Published var filter: SessionFilter = .all
    @Published var selectedIndex: Int?
    @Published var optionDown = false

    func reset() {
        selectedIndex = nil
        optionDown = false
    }

    func select(_ filter: SessionFilter) {
        self.filter = filter
        selectedIndex = nil
    }
}
