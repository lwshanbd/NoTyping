import ApplicationServices
import AppKit
import Foundation

struct FocusedElementContext {
    let element: AXUIElement?
    let bundleIdentifier: String?
    let isEditable: Bool
    let isSecureTextField: Bool
    let pid: pid_t?
}

struct FocusedElementInspector {
    func inspect() -> FocusedElementContext {
        let systemWide = AXUIElementCreateSystemWide()

        // Get the focused application
        var focusedAppRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedApplicationAttribute as CFString, &focusedAppRef) == .success,
              let focusedAppRef,
              CFGetTypeID(focusedAppRef) == AXUIElementGetTypeID()
        else {
            return FocusedElementContext(element: nil, bundleIdentifier: nil, isEditable: false, isSecureTextField: false, pid: nil)
        }

        let appElement = focusedAppRef as! AXUIElement

        // Get the PID from the focused app element
        var appPid: pid_t = 0
        AXUIElementGetPid(appElement, &appPid)

        // Get bundle identifier from the running application
        let bundleIdentifier = NSRunningApplication(processIdentifier: appPid)?.bundleIdentifier

        // Get the focused UI element
        var focusedElementRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedElementRef) == .success,
              let focusedElementRef,
              CFGetTypeID(focusedElementRef) == AXUIElementGetTypeID()
        else {
            return FocusedElementContext(element: nil, bundleIdentifier: bundleIdentifier, isEditable: false, isSecureTextField: false, pid: appPid)
        }

        let element = focusedElementRef as! AXUIElement

        // Get role and subrole
        let role = copyStringAttribute(kAXRoleAttribute, from: element)
        let subrole = copyStringAttribute(kAXSubroleAttribute, from: element)

        // Determine if it's a secure text field
        let isSecure = (role == kAXTextFieldRole as String) &&
            (subrole == NSAccessibility.Subrole.secureTextField.rawValue)

        // Determine if the element is editable
        let isEditable: Bool
        if role == kAXTextFieldRole as String || role == kAXTextAreaRole as String || role == kAXComboBoxRole as String {
            var settable: DarwinBoolean = false
            let result = AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &settable)
            isEditable = (result == .success) && settable.boolValue
        } else {
            isEditable = false
        }

        return FocusedElementContext(
            element: element,
            bundleIdentifier: bundleIdentifier,
            isEditable: isEditable,
            isSecureTextField: isSecure,
            pid: appPid
        )
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
}
