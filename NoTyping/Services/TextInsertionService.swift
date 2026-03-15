import Carbon
import ApplicationServices
import AppKit
import Foundation

enum InsertionStrategyPlanner {
    static func preferredAccessibilityStrategies(for context: FocusedElementContext) -> [InsertionStrategy] {
        guard context.isEditable, context.isSecureTextField == false else { return [] }

        if context.operation == .replaceSelection {
            return [.accessibilitySelectionReplacement, .accessibilityValueReplacement]
        }

        if context.value != nil {
            return [.accessibilityValueReplacement]
        }

        return []
    }
}

@MainActor
protocol TextInsertionServiceProtocol: AnyObject {
    func insert(text: String, context: FocusedElementContext, focusedElement: AXUIElement?) throws -> InsertionOutcome
}

@MainActor
final class TextInsertionService: TextInsertionServiceProtocol {
    private let diagnosticStore: DiagnosticStore

    init(diagnosticStore: DiagnosticStore) {
        self.diagnosticStore = diagnosticStore
    }

    func insert(text: String, context: FocusedElementContext, focusedElement: AXUIElement?) throws -> InsertionOutcome {
        guard context.isSecureTextField == false else {
            throw DictationError.insertion("Secure text fields are intentionally excluded.")
        }

        if let focusedElement {
            for strategy in InsertionStrategyPlanner.preferredAccessibilityStrategies(for: context) {
                let outcome: InsertionOutcome?
                switch strategy {
                case .accessibilitySelectionReplacement:
                    outcome = try attemptAccessibilitySelectionReplacement(text: text, context: context, focusedElement: focusedElement)
                case .accessibilityValueReplacement:
                    outcome = try attemptAccessibilityValueReplacement(text: text, context: context, focusedElement: focusedElement)
                case .unicodeTyping, .pasteboard:
                    outcome = nil
                }

                if let outcome {
                    return outcome
                }
            }
        }

        if let outcome = try attemptUnicodeTyping(text: text) {
            return outcome
        }

        if let outcome = try attemptPasteboardFallback(text: text) {
            return outcome
        }

        throw DictationError.insertion("All insertion strategies failed for the focused app.")
    }

    private func attemptAccessibilitySelectionReplacement(
        text: String,
        context: FocusedElementContext,
        focusedElement: AXUIElement
    ) throws -> InsertionOutcome? {
        guard context.operation == .replaceSelection else { return nil }
        guard isAttributeSettable(kAXSelectedTextAttribute as CFString, on: focusedElement) else {
            diagnosticStore.record(subsystem: "insertion", message: "AX selected text replacement unavailable for focused element")
            return nil
        }

        let status = AXUIElementSetAttributeValue(focusedElement, kAXSelectedTextAttribute as CFString, text as CFTypeRef)
        guard status == .success else {
            diagnosticStore.record(subsystem: "insertion", message: "AX selected text replacement failed with status \(status.rawValue)")
            return nil
        }

        return InsertionOutcome(strategy: .accessibilitySelectionReplacement, insertedText: text)
    }

    private func attemptAccessibilityValueReplacement(
        text: String,
        context: FocusedElementContext,
        focusedElement: AXUIElement
    ) throws -> InsertionOutcome? {
        guard let value = context.value else { return nil }
        let selection = context.selectedRange ?? NSRange(location: value.utf16.count, length: 0)
        guard let stringRange = Range(selection, in: value) else { return nil }

        var updated = value
        updated.replaceSubrange(stringRange, with: text)

        let status = AXUIElementSetAttributeValue(focusedElement, kAXValueAttribute as CFString, updated as CFTypeRef)
        guard status == .success else {
            diagnosticStore.record(subsystem: "insertion", message: "AX value replacement failed with status \(status.rawValue)")
            return nil
        }

        let caretLocation = selection.location + text.utf16.count
        var range = CFRange(location: caretLocation, length: 0)
        if let axRange = AXValueCreate(.cfRange, &range) {
            AXUIElementSetAttributeValue(focusedElement, kAXSelectedTextRangeAttribute as CFString, axRange)
        }

        return InsertionOutcome(strategy: .accessibilityValueReplacement, insertedText: text)
    }

    private func isAttributeSettable(_ attribute: CFString, on element: AXUIElement) -> Bool {
        var settable: DarwinBoolean = false
        let status = AXUIElementIsAttributeSettable(element, attribute, &settable)
        return status == .success && settable.boolValue
    }

    private func attemptUnicodeTyping(text: String) throws -> InsertionOutcome? {
        guard let source = CGEventSource(stateID: .hidSystemState) else { return nil }
        let characters = Array(text.utf16)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
        else {
            return nil
        }
        down.keyboardSetUnicodeString(stringLength: characters.count, unicodeString: characters)
        up.keyboardSetUnicodeString(stringLength: characters.count, unicodeString: characters)
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        return InsertionOutcome(strategy: .unicodeTyping, insertedText: text)
    }

    private func attemptPasteboardFallback(text: String) throws -> InsertionOutcome? {
        let pasteboard = NSPasteboard.general
        let previousChangeCount = pasteboard.changeCount
        let previousItems = pasteboard.pasteboardItems

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        guard let source = CGEventSource(stateID: .hidSystemState),
              let vDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true),
              let vUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false)
        else {
            return nil
        }

        vDown.flags = CGEventFlags.maskCommand
        vUp.flags = CGEventFlags.maskCommand
        vDown.post(tap: CGEventTapLocation.cghidEventTap)
        vUp.post(tap: CGEventTapLocation.cghidEventTap)

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            if pasteboard.changeCount == previousChangeCount + 1 {
                pasteboard.clearContents()
                previousItems?.forEach { item in
                    for type in item.types {
                        if let value = item.data(forType: type) {
                            pasteboard.setData(value, forType: type)
                        }
                    }
                }
            }
        }

        return InsertionOutcome(strategy: .pasteboard, insertedText: text)
    }
}
