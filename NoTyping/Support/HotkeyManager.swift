import AppKit
import Carbon
import Foundation

@MainActor
protocol HotkeyManagerDelegate: AnyObject {
    func hotkeyPressed()
    func hotkeyReleased()
}

@MainActor
final class HotkeyManager {
    weak var delegate: HotkeyManagerDelegate?
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?

    private static let signature: OSType = 0x4E545950 // "NTYP"

    func register(hotkey: HotkeyDescriptor) throws {
        unregister()
        installHandler()

        let hotKeyID = EventHotKeyID(signature: Self.signature, id: 1)
        print("[HotkeyManager] Registering hotkey: keyCode=\(hotkey.keyCode) modifiers=\(hotkey.carbonModifiers) display=\(hotkey.displayString)")
        let status = RegisterEventHotKey(
            hotkey.keyCode,
            hotkey.carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        guard status == noErr else {
            print("[HotkeyManager] RegisterEventHotKey FAILED with status \(status)")
            throw NSError(
                domain: NSOSStatusErrorDomain,
                code: Int(status),
                userInfo: [NSLocalizedDescriptionKey: "RegisterEventHotKey failed with status \(status)"]
            )
        }
        print("[HotkeyManager] Hotkey registered successfully")
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }
    }

    private func installHandler() {
        guard eventHandlerRef == nil else { return }

        var eventTypes = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]

        let selfPtr = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())

        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData -> OSStatus in
                guard let userData else { return OSStatus(eventNotHandledErr) }
                let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
                let kind = GetEventKind(event)
                MainActor.assumeIsolated {
                    if kind == UInt32(kEventHotKeyPressed) {
                        print("[HotkeyManager] Carbon event: hotkey PRESSED")
                        manager.delegate?.hotkeyPressed()
                    } else if kind == UInt32(kEventHotKeyReleased) {
                        print("[HotkeyManager] Carbon event: hotkey RELEASED")
                        manager.delegate?.hotkeyReleased()
                    }
                }
                return noErr
            },
            eventTypes.count,
            &eventTypes,
            selfPtr,
            &eventHandlerRef
        )
    }
}
