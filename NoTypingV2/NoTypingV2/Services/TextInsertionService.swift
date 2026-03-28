import AppKit
import ApplicationServices
import Carbon
import Foundation

struct TextInsertionService {
    func insert(text: String) throws {
        // Strategy 1: AX selected text replacement
        if let outcome = tryAccessibilitySelectionReplacement(text: text) {
            _ = outcome
            return
        }

        // Strategy 2: AX value replacement
        if let outcome = tryAccessibilityValueReplacement(text: text) {
            _ = outcome
            return
        }

        // Strategy 3: CGEvent keyboard typing (only for short text)
        if text.count < 100 {
            if tryUnicodeKeyboardTyping(text: text) {
                return
            }
        }

        // Strategy 4: Paste fallback with clipboard protection
        if tryPasteFallback(text: text) {
            return
        }

        throw PipelineError.insertionFailed("All insertion strategies failed.")
    }

    // MARK: - Strategy 1: AX Selected Text Replacement

    private func tryAccessibilitySelectionReplacement(text: String) -> Bool? {
        let systemWide = AXUIElementCreateSystemWide()

        // Get focused application
        var focusedAppRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedApplicationAttribute as CFString, &focusedAppRef) == .success,
              let focusedAppRef, CFGetTypeID(focusedAppRef) == AXUIElementGetTypeID()
        else { return nil }

        let appElement = focusedAppRef as! AXUIElement

        // Get focused UI element
        var focusedElementRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedElementRef) == .success,
              let focusedElementRef, CFGetTypeID(focusedElementRef) == AXUIElementGetTypeID()
        else { return nil }

        let element = focusedElementRef as! AXUIElement

        // Check role is not secure text field
        let role = copyStringAttribute(kAXRoleAttribute, from: element)
        let subrole = copyStringAttribute(kAXSubroleAttribute, from: element)
        if role == (kAXTextFieldRole as String) && subrole == NSAccessibility.Subrole.secureTextField.rawValue {
            return nil
        }

        // Check if we can get selected text range (confirms cursor position exists)
        var rangeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeRef) == .success else {
            return nil
        }

        // Try setting selected text
        let status = AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, text as CFTypeRef)
        guard status == .success else { return nil }

        return true
    }

    // MARK: - Strategy 2: AX Value Replacement

    private func tryAccessibilityValueReplacement(text: String) -> Bool? {
        let systemWide = AXUIElementCreateSystemWide()

        var focusedAppRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedApplicationAttribute as CFString, &focusedAppRef) == .success,
              let focusedAppRef, CFGetTypeID(focusedAppRef) == AXUIElementGetTypeID()
        else { return nil }

        let appElement = focusedAppRef as! AXUIElement

        var focusedElementRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedElementRef) == .success,
              let focusedElementRef, CFGetTypeID(focusedElementRef) == AXUIElementGetTypeID()
        else { return nil }

        let element = focusedElementRef as! AXUIElement

        // Get current value
        guard let currentValue = copyStringAttribute(kAXValueAttribute, from: element) else { return nil }

        // Get selected text range to find cursor position
        var rangeRef: CFTypeRef?
        let cursorLocation: Int
        if AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeRef) == .success,
           let rangeRef, CFGetTypeID(rangeRef) == AXValueGetTypeID() {
            let axValue = rangeRef as! AXValue
            var cfRange = CFRange()
            AXValueGetValue(axValue, .cfRange, &cfRange)
            cursorLocation = cfRange.location
        } else {
            // Default: append at end
            cursorLocation = currentValue.utf16.count
        }

        // Compute new value by inserting text at cursor position
        let utf16 = Array(currentValue.utf16)
        let clampedLocation = min(cursorLocation, utf16.count)
        let prefix = String(utf16[..<clampedLocation].map { Character(UnicodeScalar($0)!) })
        let suffix = String(utf16[clampedLocation...].map { Character(UnicodeScalar($0)!) })
        let newValue = prefix + text + suffix

        // Set the new value
        let status = AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, newValue as CFTypeRef)
        guard status == .success else { return nil }

        // Move caret to after inserted text
        let newCaretLocation = clampedLocation + text.utf16.count
        var range = CFRange(location: newCaretLocation, length: 0)
        if let axRange = AXValueCreate(.cfRange, &range) {
            AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, axRange)
        }

        return true
    }

    // MARK: - Strategy 3: CGEvent Unicode Typing

    private func tryUnicodeKeyboardTyping(text: String) -> Bool {
        guard let source = CGEventSource(stateID: .hidSystemState) else { return false }

        let utf16Chars = Array(text.utf16)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
        else { return false }

        down.keyboardSetUnicodeString(stringLength: utf16Chars.count, unicodeString: utf16Chars)
        up.keyboardSetUnicodeString(stringLength: utf16Chars.count, unicodeString: utf16Chars)
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)

        return true
    }

    // MARK: - Strategy 4: Paste Fallback

    private func tryPasteFallback(text: String) -> Bool {
        let pasteboard = NSPasteboard.general
        let savedChangeCount = pasteboard.changeCount

        // Save current pasteboard items
        let savedItems = pasteboard.pasteboardItems?.compactMap { item -> [(NSPasteboard.PasteboardType, Data)]? in
            let pairs = item.types.compactMap { type -> (NSPasteboard.PasteboardType, Data)? in
                guard let data = item.data(forType: type) else { return nil }
                return (type, data)
            }
            return pairs.isEmpty ? nil : pairs
        }

        // Set pasteboard to our text
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // Simulate Cmd+V
        guard let source = CGEventSource(stateID: .hidSystemState),
              let vDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true),
              let vUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false)
        else { return false }

        vDown.flags = .maskCommand
        vUp.flags = .maskCommand
        vDown.post(tap: .cghidEventTap)
        vUp.post(tap: .cghidEventTap)

        // Restore pasteboard after a delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            // Only restore if the pasteboard hasn't been modified externally
            if pasteboard.changeCount == savedChangeCount + 1 {
                pasteboard.clearContents()
                if let savedItems {
                    for itemPairs in savedItems {
                        let newItem = NSPasteboardItem()
                        for (type, data) in itemPairs {
                            newItem.setData(data, forType: type)
                        }
                        pasteboard.writeObjects([newItem])
                    }
                }
            }
        }

        return true
    }

    // MARK: - Helpers

    private func copyStringAttribute(_ attribute: String, from element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value
        else { return nil }
        return value as? String
    }
}
