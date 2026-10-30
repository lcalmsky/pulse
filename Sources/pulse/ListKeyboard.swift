import AppKit
import PulseCore

/// 팝오버와 목록 패널의 공용 키 처리. 선택·검색 상태는 각자 가진 `PopoverState` 하나만 본다.
struct ListKeyboard {
    let model: AppModel
    let state: PopoverState
    /// ⌘, 와 설정 시트 분기는 팝오버만 쓴다.
    let handlesSettings: Bool
    /// Esc 로 닫을 때 할 일. 패널은 선택만 지우고 숨기지 않는다.
    let close: () -> Void

    func handle(_ event: NSEvent) -> Bool {
        if handlesSettings,
           event.modifierFlags.contains(.command),
           event.charactersIgnoringModifiers == "," {
            state.settingsOpen.toggle()
            return true
        }

        switch event.keyCode {
        case 53:
            if !state.query.isEmpty || state.searchFocused {
                state.clearSearch()
                state.syncSelection(to: model.groups)
            } else if handlesSettings, state.settingsOpen {
                state.settingsOpen = false
            } else {
                close()
            }
            return true
        case 126, 125, 36, 76, 51, 117, 123, 124, 49, 48:
            // 설정 시트가 열려 있는 동안에는 목록 단축키를 넘기지 않는다.
            if handlesSettings, state.settingsOpen { return true }
        default:
            break
        }
        if handlesSettings, state.settingsOpen {
            return false
        }

        let items = state.filter.selectableItems(in: model.groups, query: state.query)
        switch event.keyCode {
        case 126, 125:
            if event.modifierFlags.contains(.option) {
                state.selectedIndex = KeyboardSelection.edge(up: event.keyCode == 126, count: items.count)
            } else {
                let step = event.keyCode == 126 ? -1 : 1
                state.selectedIndex = KeyboardSelection.move(
                    from: state.selectedIndex, by: step, count: items.count
                )
            }
            return true
        case 36, 76:
            guard let item = selectedItem(in: items) else { return true }
            if event.modifierFlags.contains(.shift) {
                if let alert = model.pages(for: item).first {
                    model.openPage(alert)
                } else {
                    NSSound.beep()
                }
                return true
            }
            let hasOrca = item.orcaTerminal != nil || item.cwd != nil || item.multiplexer != nil
            if event.modifierFlags.contains(.option), hasOrca {
                model.openInOrca(item)
            } else {
                model.open(item)
            }
            return true
        case 51, 117:
            if !state.query.isEmpty {
                // 필드가 포커스를 가졌으면 한글 조합을 살리도록 필드가 직접 지운다.
                if state.searchFocused { return false }
                if event.isARepeat { return true }
                state.query = String(state.query.dropLast())
                state.syncSelection(to: model.groups)
                return true
            }
            // 검색어를 다 지운 뒤 한 번 더 누른 ⌫ 와 키 반복이 확인 처리로 새지 않게 한다.
            if event.isARepeat || state.searchFocused { return true }
            guard let item = selectedItem(in: items) else { return true }
            model.acknowledge(item)
            return true
        case 49:
            guard state.query.isEmpty, !state.searchFocused else { return false }
            // ⌃⌥Space 는 시스템 입력 소스 전환이다.
            if !event.modifierFlags.intersection([.command, .control, .option]).isEmpty { return false }
            model.jumpToPriority(
                event.modifierFlags.contains(.shift) ? .done : .reply,
                state: state
            )
            return true
        case 48:
            guard state.query.isEmpty, !state.searchFocused else { return false }
            if !event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty { return false }
            guard let alert = model.oldestPageAlert else {
                NSSound.beep()
                return true
            }
            model.openPage(alert)
            return true
        case 123, 124:
            guard let item = selectedItem(in: items), item.showsStepLine else { return true }
            let changed = model.stepDisclosure(
                item,
                by: event.keyCode == 124 ? 1 : -1,
                toEnd: event.modifierFlags.contains(.option)
            )
            if changed { state.revealRequest += 1 }
            return true
        default:
            break
        }

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
        guard let characters = event.characters, !characters.isEmpty else { return nil }
        guard characters.unicodeScalars.contains(where: { !CharacterSet.controlCharacters.contains($0) }) else {
            return nil
        }
        return characters
    }
}
