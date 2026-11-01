import AppKit
import PulseCore

/// 팝오버와 목록 패널의 공용 키 처리. 선택·검색 상태는 각자 가진 `PopoverState` 하나만 본다.
struct ListKeyboard {
    let model: AppModel
    let state: PopoverState
    /// 설정 시트와 녹화는 팝오버만 쓴다.
    let handlesSettings: Bool
    /// Esc 로 닫을 때 할 일. 패널은 선택만 지우고 숨기지 않는다.
    let close: () -> Void

    func handle(_ event: NSEvent) -> Bool {
        // 녹화 중에는 다른 단축키가 끼어들지 않도록 모든 키를 여기서 가져간다.
        if handlesSettings, let target = state.recordingTarget {
            if event.keyCode == 53 {
                state.stopShortcutRecording()
                return true
            }
            let binding = HotKeyBinding(
                keyCode: HotKeyBinding.normalizedKeyCode(UInt32(event.keyCode)),
                modifiers: HotKeyBinding.carbonModifiers(cocoaFlags: event.modifierFlags.rawValue)
            )
            switch target {
            case .globalHotKey:
                if binding.isValid {
                    model.setHotKey(binding)
                    state.stopShortcutRecording()
                } else {
                    state.markShortcutNeedsModifier()
                }
            case .action(let action):
                if binding.isValidListKey {
                    model.setKeyBinding(binding, for: action)
                    state.stopShortcutRecording()
                }
            }
            return true
        }

        let keyCode = HotKeyBinding.normalizedKeyCode(UInt32(event.keyCode))
        let modifiers = HotKeyBinding.carbonModifiers(cocoaFlags: event.modifierFlags.rawValue)
        let action = model.keyMap.action(keyCode: UInt32(event.keyCode), modifiers: modifiers)

        if event.keyCode == 53 {
            if !state.query.isEmpty || state.searchFocused {
                state.clearSearch()
                state.syncSelection(to: model.groups)
            } else if handlesSettings, state.settingsOpen {
                state.settingsOpen = false
            } else {
                close()
            }
            return true
        }

        if handlesSettings, state.settingsOpen {
            guard let action else { return false }
            if action == .toggleSettings {
                state.settingsOpen.toggle()
            }
            return true
        }

        // 검색어 지우기는 동작 바인딩과 상관없이 실제 ⌫ 키에 붙어 있다.
        if keyCode == 51,
           modifiers & searchModifiers == 0,
           !state.query.isEmpty {
            // 필드가 포커스를 가졌으면 한글 조합을 살리도록 필드가 직접 지운다.
            if state.searchFocused { return false }
            if event.isARepeat { return true }
            state.query = String(state.query.dropLast())
            state.syncSelection(to: model.groups)
            return true
        }

        guard let action else {
            return typeSearchText(event)
        }
        if KeyMap.yieldsToSearch(model.keyMap.binding(for: action)),
           !state.query.isEmpty || state.searchFocused {
            return false
        }

        let items = state.filter.selectableItems(in: model.groups, query: state.query)
        switch action {
        case .selectPrevious:
            state.selectedIndex = KeyboardSelection.move(
                from: state.selectedIndex, by: -1, count: items.count
            )
        case .selectNext:
            state.selectedIndex = KeyboardSelection.move(
                from: state.selectedIndex, by: 1, count: items.count
            )
        case .selectFirst:
            state.selectedIndex = KeyboardSelection.edge(up: true, count: items.count)
        case .selectLast:
            state.selectedIndex = KeyboardSelection.edge(up: false, count: items.count)
        case .open:
            guard let item = selectedItem(in: items) else { return true }
            model.open(item)
        case .openInTerminal:
            guard let item = selectedItem(in: items) else { return true }
            let hasOrca = item.orcaTerminal != nil || item.cwd != nil || item.multiplexer != nil
            if hasOrca {
                model.openInOrca(item)
            } else {
                model.open(item)
            }
        case .openRowPage:
            guard let item = selectedItem(in: items) else { return true }
            if let alert = model.pages(for: item).first {
                model.openPage(alert)
            } else {
                NSSound.beep()
            }
        case .expandSteps, .collapseSteps, .expandAllSteps, .collapseAllSteps:
            guard let item = selectedItem(in: items), item.showsStepLine else { return true }
            let expand = action == .expandSteps || action == .expandAllSteps
            let toEnd = action == .expandAllSteps || action == .collapseAllSteps
            let changed = model.stepDisclosure(item, by: expand ? 1 : -1, toEnd: toEnd)
            if changed { state.revealRequest += 1 }
        case .jumpToReply:
            model.jumpToPriority(.reply, state: state)
        case .jumpToDone:
            model.jumpToPriority(.done, state: state)
        case .openOldestPage:
            guard let alert = model.oldestPageAlert else {
                NSSound.beep()
                return true
            }
            model.openPage(alert)
        case .acknowledge:
            // 검색어를 다 지운 뒤 한 번 더 누른 ⌫ 와 키 반복이 확인 처리로 새지 않게 한다.
            if event.isARepeat || state.searchFocused { return true }
            guard let item = selectedItem(in: items) else { return true }
            model.acknowledge(item)
        case .toggleSettings:
            guard handlesSettings else { return typeSearchText(event) }
            state.settingsOpen.toggle()
        }
        return true
    }

    private var searchModifiers: UInt32 {
        HotKeyBinding.commandModifier | HotKeyBinding.controlModifier | HotKeyBinding.optionModifier
    }

    private func typeSearchText(_ event: NSEvent) -> Bool {
        // ⌘·⌃ 없이 친 글자는 검색어가 된다. 필드가 포커스를 받은 뒤로는 조합 입력을 위해 필드에 넘긴다.
        guard let text = typedText(event), !state.searchFocused else { return false }
        if state.query.isEmpty, text.trimmingCharacters(in: .whitespaces).isEmpty { return false }
        state.query += text
        state.syncSelection(to: model.groups)
        state.searchFocusRequest += 1
        return true
    }

    private func selectedItem(in items: [DisplayItem]) -> DisplayItem? {
        guard let index = state.selectedIndex, items.indices.contains(index) else { return nil }
        return items[index]
    }

    private func typedText(_ event: NSEvent) -> String? {
        if event.modifierFlags.contains(.command) || event.modifierFlags.contains(.control) {
            return nil
        }
        if event.specialKey != nil { return nil }
        // ⌥Space 는 특수 공백을 만든다. 예전처럼 검색어에 넣지 않는다.
        if event.keyCode == 49, event.modifierFlags.contains(.option) { return nil }
        guard let characters = event.characters, !characters.isEmpty else { return nil }
        guard characters.unicodeScalars.contains(where: { !CharacterSet.controlCharacters.contains($0) }) else {
            return nil
        }
        return characters
    }
}
