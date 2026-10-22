import Foundation

public enum HotKeyAction: Equatable {
    case openPopover
    case closePopoverAndShowPanel
    case closePopoverAndFocusPanel
    case focusPanel
    case hidePanel
}

public enum HotKeyRouting {
    public static func action(popoverOpen: Bool, panelVisible: Bool, panelKey: Bool) -> HotKeyAction {
        if popoverOpen {
            return panelVisible ? .closePopoverAndFocusPanel : .closePopoverAndShowPanel
        }
        guard panelVisible else { return .openPopover }
        return panelKey ? .hidePanel : .focusPanel
    }
}
