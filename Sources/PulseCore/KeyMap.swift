import Foundation

/// 팝오버와 플로팅 패널의 목록 키. `HotKeyBinding` 을 그대로 쓴다.
public enum KeyAction: String, CaseIterable {
    case selectPrevious
    case selectNext
    case selectFirst
    case selectLast
    case expandSteps
    case collapseSteps
    case expandAllSteps
    case collapseAllSteps
    case open
    case openInTerminal
    case openRowPage
    case jumpToReply
    case jumpToDone
    case openOldestPage
    case acknowledge
    case toggleSettings

    public var defaultBinding: HotKeyBinding {
        switch self {
        case .selectPrevious: return HotKeyBinding(keyCode: 126, modifiers: 0)
        case .selectNext: return HotKeyBinding(keyCode: 125, modifiers: 0)
        case .selectFirst: return HotKeyBinding(keyCode: 126, modifiers: HotKeyBinding.optionModifier)
        case .selectLast: return HotKeyBinding(keyCode: 125, modifiers: HotKeyBinding.optionModifier)
        case .expandSteps: return HotKeyBinding(keyCode: 124, modifiers: 0)
        case .collapseSteps: return HotKeyBinding(keyCode: 123, modifiers: 0)
        case .expandAllSteps: return HotKeyBinding(keyCode: 124, modifiers: HotKeyBinding.optionModifier)
        case .collapseAllSteps: return HotKeyBinding(keyCode: 123, modifiers: HotKeyBinding.optionModifier)
        case .open: return HotKeyBinding(keyCode: 36, modifiers: 0)
        case .openInTerminal: return HotKeyBinding(keyCode: 36, modifiers: HotKeyBinding.optionModifier)
        case .openRowPage: return HotKeyBinding(keyCode: 36, modifiers: HotKeyBinding.shiftModifier)
        case .jumpToReply: return HotKeyBinding(keyCode: 49, modifiers: 0)
        case .jumpToDone: return HotKeyBinding(keyCode: 49, modifiers: HotKeyBinding.shiftModifier)
        case .openOldestPage: return HotKeyBinding(keyCode: 48, modifiers: 0)
        case .acknowledge: return HotKeyBinding(keyCode: 51, modifiers: 0)
        case .toggleSettings: return HotKeyBinding(keyCode: 43, modifiers: HotKeyBinding.commandModifier)
        }
    }
}

public enum ShortcutTarget: Equatable {
    case globalHotKey
    case action(KeyAction)
}

public enum ShortcutConflict: Equatable {
    case action(KeyAction)
    case globalHotKey
}

public struct KeyMap: Equatable {
    public let bindings: [KeyAction: HotKeyBinding]

    public static let `default` = KeyMap(bindings: [:])

    /// 빠진 동작은 기본값으로 채운다.
    public init(bindings: [KeyAction: HotKeyBinding]) {
        var merged: [KeyAction: HotKeyBinding] = [:]
        for action in KeyAction.allCases {
            merged[action] = action.defaultBinding
        }
        for (action, binding) in bindings {
            merged[action] = binding
        }
        self.bindings = merged
    }

    public init(rawDictionary: [String: String]?) {
        var merged: [KeyAction: HotKeyBinding] = [:]
        for action in KeyAction.allCases {
            merged[action] = action.defaultBinding
        }
        for (rawAction, rawValue) in rawDictionary ?? [:] {
            guard let action = KeyAction(rawValue: rawAction),
                  let binding = HotKeyBinding(listRawValue: rawValue) else { continue }
            merged[action] = binding
        }
        self.bindings = merged
    }

    public func binding(for action: KeyAction) -> HotKeyBinding {
        bindings[action] ?? action.defaultBinding
    }

    public func action(keyCode: UInt32, modifiers: UInt32) -> KeyAction? {
        let normalized = HotKeyBinding.normalizedKeyCode(keyCode)
        return KeyAction.allCases.first { action in
            let binding = binding(for: action)
            return binding.keyCode == normalized && binding.modifiers == modifiers
        }
    }

    public func setting(_ binding: HotKeyBinding, for action: KeyAction) -> KeyMap {
        var updated = bindings
        updated[action] = HotKeyBinding(
            keyCode: HotKeyBinding.normalizedKeyCode(binding.keyCode),
            modifiers: binding.modifiers
        )
        return KeyMap(bindings: updated)
    }

    public func resetting(_ action: KeyAction) -> KeyMap {
        setting(action.defaultBinding, for: action)
    }

    public var isDefault: Bool { self == .default }

    /// 기본값과 다른 항목만 저장한다.
    public var rawDictionary: [String: String] {
        var stored: [String: String] = [:]
        for action in KeyAction.allCases {
            let binding = binding(for: action)
            if binding != action.defaultBinding {
                stored[action.rawValue] = binding.rawValue
            }
        }
        return stored
    }

    /// `assigningTo` 가 nil 이면 전역 단축키를 바꾸는 중이라 목록 동작과만 견준다.
    public func conflict(
        for binding: HotKeyBinding,
        assigningTo action: KeyAction?,
        globalHotKey: HotKeyBinding
    ) -> ShortcutConflict? {
        if let other = KeyAction.allCases.first(where: {
            $0 != action && Self.matches(self.binding(for: $0), binding)
        }) {
            return .action(other)
        }
        if action != nil, Self.matches(globalHotKey, binding) {
            return .globalHotKey
        }
        return nil
    }

    /// ⌘⌃⌥ 없이 글자·Space·Tab·⌫ 에 묶인 동작은 검색 중에는 입력으로 넘긴다. 방향키·↩·F 키는 검색 결과를 다루므로 넘기지 않는다.
    public static func yieldsToSearch(_ binding: HotKeyBinding) -> Bool {
        let actionModifiers = HotKeyBinding.commandModifier | HotKeyBinding.controlModifier | HotKeyBinding.optionModifier
        guard binding.modifiers & actionModifiers == 0 else { return false }
        return !navigationKeyCodes.contains(HotKeyBinding.normalizedKeyCode(binding.keyCode))
    }

    private static let navigationKeyCodes: Set<UInt32> = [
        36, 123, 124, 125, 126, 96, 97, 98, 99, 100, 101, 103, 109, 111, 118, 120, 122
    ]

    private static func matches(_ lhs: HotKeyBinding, _ rhs: HotKeyBinding) -> Bool {
        HotKeyBinding.normalizedKeyCode(lhs.keyCode) == HotKeyBinding.normalizedKeyCode(rhs.keyCode)
            && lhs.modifiers == rhs.modifiers
    }
}
