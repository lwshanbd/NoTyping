import XCTest
@testable import NoTyping

final class InsertionStrategyTests: XCTestCase {
    func testAccessibilityContextMarksReplaceSelection() {
        let context = FocusedElementContext(
            bundleIdentifier: "com.apple.TextEdit",
            applicationName: "TextEdit",
            role: "AXTextArea",
            subrole: nil,
            fieldType: .multiLine,
            operation: .replaceSelection,
            selectedRange: NSRange(location: 3, length: 4),
            value: "hello world",
            isSecureTextField: false,
            isEditable: true
        )
        XCTAssertEqual(context.operation, .replaceSelection)
    }

    func testPlannerPrefersSelectedTextReplacementWhenSelectionExists() {
        let context = FocusedElementContext(
            bundleIdentifier: "com.apple.TextEdit",
            applicationName: "TextEdit",
            role: "AXTextArea",
            subrole: nil,
            fieldType: .multiLine,
            operation: .replaceSelection,
            selectedRange: NSRange(location: 2, length: 5),
            value: "hello world",
            isSecureTextField: false,
            isEditable: true
        )

        XCTAssertEqual(
            InsertionStrategyPlanner.preferredAccessibilityStrategies(for: context),
            [.accessibilitySelectionReplacement, .accessibilityValueReplacement]
        )
    }

    func testPlannerUsesValueReplacementForEditableCaretInsertion() {
        let context = FocusedElementContext(
            bundleIdentifier: "com.apple.TextEdit",
            applicationName: "TextEdit",
            role: "AXTextArea",
            subrole: nil,
            fieldType: .multiLine,
            operation: .append,
            selectedRange: NSRange(location: 11, length: 0),
            value: "hello world",
            isSecureTextField: false,
            isEditable: true
        )

        XCTAssertEqual(
            InsertionStrategyPlanner.preferredAccessibilityStrategies(for: context),
            [.accessibilityValueReplacement]
        )
    }

    func testPlannerSkipsAccessibilityForSecureFields() {
        let context = FocusedElementContext(
            bundleIdentifier: "com.apple.loginwindow",
            applicationName: "Login",
            role: "AXTextField",
            subrole: "AXSecureTextField",
            fieldType: .singleLine,
            operation: .insert,
            selectedRange: nil,
            value: nil,
            isSecureTextField: true,
            isEditable: true
        )

        XCTAssertTrue(InsertionStrategyPlanner.preferredAccessibilityStrategies(for: context).isEmpty)
    }
}
