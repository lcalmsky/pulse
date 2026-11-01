import Carbon.HIToolbox
import Foundation
import PulseCore
import os

final class GlobalHotKey {
    // 'PULS'
    private static let signature: OSType = 0x50554C53
    private static let identifier: UInt32 = 1

    private let log = Logger(subsystem: "io.github.lcalmsky.pulse", category: "hotkey")
    private let action: () -> Void
    private var binding: HotKeyBinding
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    /// 설정에서 새 조합을 받는 동안 핫키만 내려 둔 상태. 핫키가 살아 있으면 현재 조합을 눌렀을 때 팝오버가 닫힌다.
    private var suspended = false

    init(binding: HotKeyBinding, action: @escaping () -> Void) {
        self.binding = binding
        self.action = action
    }

    deinit {
        unregister()
    }

    @discardableResult
    func register() -> Bool {
        guard hotKeyRef == nil else { return true }
        guard installHandler() else { return false }
        return registerCurrent()
    }

    /// 이벤트 핸들러는 그대로 두고 등록된 조합만 바꾼다. 실패하면 이전 조합을 되살리고 false.
    @discardableResult
    func update(to newBinding: HotKeyBinding) -> Bool {
        guard newBinding != binding else { return true }
        let previous = binding
        unbind()
        binding = newBinding
        guard installHandler() else {
            binding = previous
            if !suspended { _ = registerCurrent() }
            return false
        }
        // 녹화 중에도 한 번 등록해 다른 앱과 겹치는지 확인하고, 확인했으면 다시 내린다.
        guard registerCurrent() else {
            binding = previous
            if !suspended { _ = registerCurrent() }
            return false
        }
        if suspended { unbind() }
        return true
    }

    func suspend() {
        guard !suspended else { return }
        suspended = true
        unbind()
    }

    /// 녹화를 끝내고 현재 조합을 다시 등록한다. 등록되어 있으면 true.
    @discardableResult
    func resume() -> Bool {
        guard suspended else { return hotKeyRef != nil }
        suspended = false
        guard installHandler() else { return false }
        return registerCurrent()
    }

    private func fire() {
        DispatchQueue.main.async { [weak self] in
            self?.action()
        }
    }

    private func installHandler() -> Bool {
        guard handlerRef == nil else { return true }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData in
                guard let userData else { return noErr }
                let hotKey = Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue()
                hotKey.fire()
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &handlerRef
        )
        guard status == noErr else {
            log.error("단축키 이벤트 핸들러 등록 실패: \(status, privacy: .public)")
            return false
        }
        return true
    }

    private func registerCurrent() -> Bool {
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: Self.identifier)
        let status = RegisterEventHotKey(
            binding.keyCode,
            binding.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        guard status == noErr else {
            let keys = binding.displayString
            log.error("단축키 \(keys, privacy: .public) 등록 실패: \(status, privacy: .public)")
            return false
        }
        let keys = binding.displayString
        log.notice("단축키 \(keys, privacy: .public) 등록 완료: \(status, privacy: .public)")
        return true
    }

    private func unbind() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
    }

    private func unregister() {
        unbind()
        if let handlerRef {
            RemoveEventHandler(handlerRef)
            self.handlerRef = nil
        }
    }
}
