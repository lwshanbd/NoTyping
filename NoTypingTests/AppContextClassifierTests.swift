import XCTest
@testable import NoTyping

final class AppContextClassifierTests: XCTestCase {
    func testClassifierUsesRuleOverrides() {
        let classifier = AppContextClassifier()
        let context = FocusedElementContext(
            bundleIdentifier: "com.example.terminal",
            applicationName: "Example",
            role: nil,
            subrole: nil,
            fieldType: .multiLine,
            operation: .insert,
            selectedRange: nil,
            value: nil,
            isSecureTextField: false,
            isEditable: true
        )
        let rule = AppRule(bundleIdentifierPattern: "com.example", category: .terminal, preferredProfile: .codeAware, aggressivenessOverride: .low, disableRewrite: false)
        XCTAssertEqual(classifier.classify(bundleIdentifier: "com.example.terminal", focusedElement: context, rules: [rule]), .terminal)
    }

    func testResolutionAppliesRuleOverrides() {
        let classifier = AppContextClassifier()
        let context = FocusedElementContext(
            bundleIdentifier: "com.example.mailclient",
            applicationName: "Mail",
            role: "AXTextArea",
            subrole: nil,
            fieldType: .multiLine,
            operation: .insert,
            selectedRange: nil,
            value: nil,
            isSecureTextField: false,
            isEditable: true
        )
        var settings = AppSettings()
        settings.defaultProfile = .smart
        settings.rewriteAggressiveness = .medium
        settings.appRules = [
            AppRule(
                bundleIdentifierPattern: "com.example",
                category: .email,
                preferredProfile: .email,
                aggressivenessOverride: .high,
                disableRewrite: true
            )
        ]

        let resolution = classifier.resolve(bundleIdentifier: "com.example.mailclient", focusedElement: context, settings: settings)

        XCTAssertEqual(resolution.category, .email)
        XCTAssertEqual(resolution.profile, .email)
        XCTAssertEqual(resolution.aggressiveness, .high)
        XCTAssertTrue(resolution.disableRewrite)
    }

    func testResolutionFallsBackToCategoryDefaults() {
        let classifier = AppContextClassifier()
        let context = FocusedElementContext(
            bundleIdentifier: "com.apple.dt.Xcode",
            applicationName: "Xcode",
            role: "AXTextArea",
            subrole: nil,
            fieldType: .multiLine,
            operation: .insert,
            selectedRange: nil,
            value: nil,
            isSecureTextField: false,
            isEditable: true
        )

        let resolution = classifier.resolve(bundleIdentifier: "com.apple.dt.Xcode", focusedElement: context, settings: AppSettings())

        XCTAssertEqual(resolution.category, .code)
        XCTAssertEqual(resolution.profile, .codeAware)
        XCTAssertEqual(resolution.aggressiveness, .medium)
        XCTAssertFalse(resolution.disableRewrite)
    }
}
