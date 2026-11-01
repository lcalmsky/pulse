import Foundation

/// 전역 단축키 조합. Carbon 가상 키 코드와 Carbon 수식키 마스크를 그대로 담는다.
public struct HotKeyBinding: Equatable {
    public static let commandModifier: UInt32 = 0x100
    public static let shiftModifier: UInt32 = 0x200
    public static let optionModifier: UInt32 = 0x800
    public static let controlModifier: UInt32 = 0x1000

    private static let supportedModifiers =
        commandModifier | shiftModifier | optionModifier | controlModifier
    private static let actionModifiers = commandModifier | optionModifier | controlModifier

    public let keyCode: UInt32
    public let modifiers: UInt32

    public static let `default` = HotKeyBinding(
        keyCode: 35,
        modifiers: controlModifier | optionModifier
    )

    public init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// 저장된 원문 `"<keyCode>:<modifiers>"`. 형식이나 값이 틀리면 nil.
    public init?(rawValue: String) {
        let parts = rawValue.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2,
              let keyCode = UInt32(parts[0]),
              let modifiers = UInt32(parts[1]) else { return nil }
        self.init(keyCode: keyCode, modifiers: modifiers)
        guard isValid else { return nil }
    }

    /// 목록 단축키 저장 원문. 전역 단축키와 달리 수식키가 없어도 된다.
    public init?(listRawValue: String) {
        let parts = listRawValue.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2,
              let keyCode = UInt32(parts[0]),
              let modifiers = UInt32(parts[1]) else { return nil }
        self.init(keyCode: Self.normalizedKeyCode(keyCode), modifiers: modifiers)
        guard isValidListKey else { return nil }
    }

    public var rawValue: String { "\(keyCode):\(modifiers)" }

    /// ⇧ 만으로는 단축키가 되지 않는다. 등록할 수 없는 조합은 저장하지 않는다.
    public var isValid: Bool {
        modifiers & ~Self.supportedModifiers == 0
            && modifiers & Self.actionModifiers != 0
            && Self.keyName(for: keyCode) != nil
    }

    /// 목록 키는 수식키 없이도 되고 Esc 는 쓰지 않는다.
    public var isValidListKey: Bool {
        let normalized = Self.normalizedKeyCode(keyCode)
        return modifiers & ~Self.supportedModifiers == 0
            && normalized != 53
            && Self.keyName(for: normalized) != nil
    }

    /// 키패드 Enter 와 Forward Delete 는 기존 목록 키 처리와 같은 동작으로 맞춘다.
    public static func normalizedKeyCode(_ keyCode: UInt32) -> UInt32 {
        switch keyCode {
        case 76: return 36
        case 117: return 51
        default: return keyCode
        }
    }

    public var displayString: String {
        var text = ""
        if modifiers & Self.controlModifier != 0 { text += "⌃" }
        if modifiers & Self.optionModifier != 0 { text += "⌥" }
        if modifiers & Self.shiftModifier != 0 { text += "⇧" }
        if modifiers & Self.commandModifier != 0 { text += "⌘" }
        return text + (Self.keyName(for: keyCode) ?? "?")
    }

    /// NSEvent.ModifierFlags 원값을 Carbon 마스크로 바꾼다. 관계없는 비트는 버린다.
    public static func carbonModifiers(cocoaFlags: UInt) -> UInt32 {
        var result: UInt32 = 0
        if cocoaFlags & (1 << 17) != 0 { result |= shiftModifier }
        if cocoaFlags & (1 << 18) != 0 { result |= controlModifier }
        if cocoaFlags & (1 << 19) != 0 { result |= optionModifier }
        if cocoaFlags & (1 << 20) != 0 { result |= commandModifier }
        return result
    }

    /// US ANSI 기준 표시 이름. Esc 와 수식키처럼 단독으로 뜻이 없는 코드는 nil 이다.
    public static func keyName(for keyCode: UInt32) -> String? {
        switch keyCode {
        case 0: return "A"
        case 1: return "S"
        case 2: return "D"
        case 3: return "F"
        case 4: return "H"
        case 5: return "G"
        case 6: return "Z"
        case 7: return "X"
        case 8: return "C"
        case 9: return "V"
        case 11: return "B"
        case 12: return "Q"
        case 13: return "W"
        case 14: return "E"
        case 15: return "R"
        case 16: return "Y"
        case 17: return "T"
        case 18: return "1"
        case 19: return "2"
        case 20: return "3"
        case 21: return "4"
        case 22: return "6"
        case 23: return "5"
        case 24: return "="
        case 25: return "9"
        case 26: return "7"
        case 27: return "-"
        case 28: return "8"
        case 29: return "0"
        case 30: return "]"
        case 31: return "O"
        case 32: return "U"
        case 33: return "["
        case 34: return "I"
        case 35: return "P"
        case 36: return "↩"
        case 37: return "L"
        case 38: return "J"
        case 39: return "'"
        case 40: return "K"
        case 41: return ";"
        case 42: return "\\"
        case 43: return ","
        case 44: return "/"
        case 45: return "N"
        case 46: return "M"
        case 47: return "."
        case 48: return "Tab"
        case 49: return "Space"
        case 50: return "`"
        case 51: return "⌫"
        case 96: return "F5"
        case 97: return "F6"
        case 98: return "F7"
        case 99: return "F3"
        case 100: return "F8"
        case 101: return "F9"
        case 103: return "F11"
        case 109: return "F10"
        case 111: return "F12"
        case 118: return "F4"
        case 120: return "F2"
        case 122: return "F1"
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        default: return nil
        }
    }
}

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
