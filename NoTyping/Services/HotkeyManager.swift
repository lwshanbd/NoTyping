import AppKit
import Carbon
import Foundation

@MainActor
protocol HotkeyManagerDelegate: AnyObject {
    func hotkeyManagerDidPress()
    func hotkeyManagerDidRelease()
}

@MainActor
final class HotkeyManager {
    weak var delegate: HotkeyManagerDelegate?

    private var hotkeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var currentHotkey: HotkeyDescriptor = .default

    init() {
        installHandler()
    }

    func register(hotkey: HotkeyDescriptor) {
        unregister()
        currentHotkey = hotkey
        let hotKeyID = EventHotKeyID(signature: OSType(0x4E545950), id: UInt32(1))
        RegisterEventHotKey(hotkey.keyCode, hotkey.carbonModifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotkeyRef)
    }

    func unregister() {
        if let hotkeyRef {
            UnregisterEventHotKey(hotkeyRef)
            self.hotkeyRef = nil
        }
    }

    private func installHandler() {
        var eventTypes = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))
        ]

        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let userData else { return noErr }
            let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
            let kind = GetEventKind(event)
            if kind == UInt32(kEventHotKeyPressed) {
                MainActor.assumeIsolated {
                    manager.delegate?.hotkeyManagerDidPress()
                }
            } else if kind == UInt32(kEventHotKeyReleased) {
                MainActor.assumeIsolated {
                    manager.delegate?.hotkeyManagerDidRelease()
                }
            }
            return noErr
        }, 2, &eventTypes, UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()), &eventHandler)
    }
}
