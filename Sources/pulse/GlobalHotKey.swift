import Carbon.HIToolbox
import Foundation
import os

final class GlobalHotKey {
    // 'PULS'
    private static let signature: OSType = 0x50554C53
    private static let identifier: UInt32 = 1

    private let log = Logger(subsystem: "io.github.lcalmsky.pulse", category: "hotkey")
    private let action: () -> Void
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    init(action: @escaping () -> Void) {
        self.action = action
    }

    deinit {
        unregister()
    }

    @discardableResult
    func register() -> Bool {
        guard hotKeyRef == nil else { return true }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let installStatus = InstallEventHandler(
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
        guard installStatus == noErr else {
            log.error("단축키 이벤트 핸들러 등록 실패: \(installStatus, privacy: .public)")
            return false
        }

        let hotKeyID = EventHotKeyID(signature: Self.signature, id: Self.identifier)
        let status = RegisterEventHotKey(
            UInt32(kVK_ANSI_P),
            UInt32(controlKey | optionKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        guard status == noErr else {
            log.error("단축키 ⌃⌥P 등록 실패: \(status, privacy: .public)")
            removeHandler()
            return false
        }

        log.notice("단축키 ⌃⌥P 등록 완료: \(status, privacy: .public)")
        return true
    }

    private func fire() {
        DispatchQueue.main.async { [weak self] in
            self?.action()
        }
    }

    private func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        removeHandler()
    }

    private func removeHandler() {
        if let handlerRef {
            RemoveEventHandler(handlerRef)
            self.handlerRef = nil
        }
    }
}
