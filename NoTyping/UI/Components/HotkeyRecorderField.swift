import AppKit
import Carbon
import SwiftUI

struct HotkeyRecorderField: NSViewRepresentable {
    @Binding var hotkey: HotkeyDescriptor

    func makeNSView(context: Context) -> RecorderField {
        let field = RecorderField()
        field.onUpdate = { hotkey in
            self.hotkey = hotkey
        }
        field.hotkey = hotkey
        return field
    }

    func updateNSView(_ nsView: RecorderField, context: Context) {
        nsView.hotkey = hotkey
    }
}

final class RecorderField: NSTextField {
    var onUpdate: ((HotkeyDescriptor) -> Void)?
    var hotkey: HotkeyDescriptor = .default {
        didSet {
            stringValue = hotkey.displayString
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isEditable = false
        isBordered = true
        drawsBackground = true
        focusRingType = .default
        alignment = .center
        font = .systemFont(ofSize: 13, weight: .medium)
        stringValue = hotkey.displayString
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let carbonModifiers = RecorderField.carbonFlags(for: modifiers)
        let descriptor = HotkeyDescriptor(keyCode: UInt32(event.keyCode), carbonModifiers: carbonModifiers)
        hotkey = descriptor
        onUpdate?(descriptor)
    }

    private static func carbonFlags(for flags: NSEvent.ModifierFlags) -> UInt32 {
        var value: UInt32 = 0
        if flags.contains(.command) { value |= UInt32(cmdKey) }
        if flags.contains(.option) { value |= UInt32(optionKey) }
        if flags.contains(.control) { value |= UInt32(controlKey) }
        if flags.contains(.shift) { value |= UInt32(shiftKey) }
        return value
    }
}
