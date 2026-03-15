import ApplicationServices
import AppKit
import Foundation

final class FocusedElementInspector {
    func inspectFocusedElement() -> FocusedElementContext {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedObject: CFTypeRef?
        let focusedResult = AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedObject)
        let app = NSWorkspace.shared.frontmostApplication
        guard focusedResult == .success, let focusedObject, CFGetTypeID(focusedObject) == AXUIElementGetTypeID() else {
            return FocusedElementContext(
                bundleIdentifier: app?.bundleIdentifier,
                applicationName: app?.localizedName,
                role: nil,
                subrole: nil,
                fieldType: .unknown,
                operation: .insert,
                selectedRange: nil,
                value: nil,
                isSecureTextField: false,
                isEditable: false
            )
        }

        let element = unsafeDowncast(focusedObject, to: AXUIElement.self)
        let role = copyStringAttribute(kAXRoleAttribute, from: element)
        let subrole = copyStringAttribute(kAXSubroleAttribute, from: element)
        let value = copyStringAttribute(kAXValueAttribute, from: element)
        let selectedRange = copyRangeAttribute(kAXSelectedTextRangeAttribute, from: element)
        let selectedText = copyStringAttribute(kAXSelectedTextAttribute, from: element)

        let fieldType: FieldType
        switch role {
        case kAXTextAreaRole:
            fieldType = .multiLine
        case kAXTextFieldRole, kAXComboBoxRole:
            fieldType = .singleLine
        default:
            fieldType = subrole == NSAccessibility.Subrole.searchField.rawValue ? .singleLine : .unknown
        }

        let operation: InsertionOperation
        if let selectedRange, selectedRange.length > 0 || !(selectedText ?? "").isEmpty {
            operation = .replaceSelection
        } else if let value, let selectedRange, selectedRange.location == value.utf16.count {
            operation = .append
        } else {
            operation = .insert
        }

        let secure = subrole == NSAccessibility.Subrole.secureTextField.rawValue
        let editable = isAttributeSettable(kAXValueAttribute, on: element) || isAttributeSettable(kAXSelectedTextRangeAttribute, on: element)

        return FocusedElementContext(
            bundleIdentifier: app?.bundleIdentifier,
            applicationName: app?.localizedName,
            role: role,
            subrole: subrole,
            fieldType: fieldType,
            operation: operation,
            selectedRange: selectedRange,
            value: value,
            isSecureTextField: secure,
            isEditable: editable
        )
    }

    func focusedElement() -> AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedObject: CFTypeRef?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedObject) == .success,
              let focusedObject,
              CFGetTypeID(focusedObject) == AXUIElementGetTypeID()
        else {
            return nil
        }
        return unsafeDowncast(focusedObject, to: AXUIElement.self)
    }

    private func copyStringAttribute(_ attribute: String, from element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value
        else {
            return nil
        }
        return value as? String
    }

    private func copyBoolAttribute(_ attribute: CFString, from element: AXUIElement) -> Bool? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else {
            return nil
        }
        return value as? Bool
    }

    private func copyRangeAttribute(_ attribute: String, from element: AXUIElement) -> NSRange? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let axValue = value,
              CFGetTypeID(axValue) == AXValueGetTypeID()
        else {
            return nil
        }
        let valueRef = unsafeDowncast(axValue, to: AXValue.self)
        guard AXValueGetType(valueRef) == .cfRange else { return nil }
        var range = CFRange()
        AXValueGetValue(valueRef, .cfRange, &range)
        return NSRange(location: range.location, length: range.length)
    }

    private func isAttributeSettable(_ attribute: String, on element: AXUIElement) -> Bool {
        var settable: DarwinBoolean = false
        let result = AXUIElementIsAttributeSettable(element, attribute as CFString, &settable)
        return result == .success && settable.boolValue
    }
}
