import Foundation

public enum HotKeyAction: Equatable {
    case openPopover
    case closePopoverAndShowPanel
    case closePopover
    case hidePanel
}

public enum HotKeyRouting {
    public static func action(popoverOpen: Bool, panelVisible: Bool) -> HotKeyAction {
        if popoverOpen {
            return panelVisible ? .closePopover : .closePopoverAndShowPanel
        }
        return panelVisible ? .hidePanel : .openPopover
    }
}
