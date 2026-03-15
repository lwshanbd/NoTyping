import XCTest
@testable import NoTyping

final class RewritePromptTests: XCTestCase {
    func testMockRewriteCleansFillers() async throws {
        let service = MockRewriteService()
        let result = try await service.rewrite(
            transcript: "um hello world",
            context: RewriteContext(appCategory: .chat, fieldType: .singleLine, operation: .insert, aggressiveness: .medium, languageMode: .english, profile: .smart, protectedTerms: [], recentContext: nil),
            provider: .default,
            apiKey: nil
        )
        XCTAssertEqual(result.text, "hello world")
    }

    func testPromptBuilderIncludesRecentContextBlockWhenPresent() {
        let payload = RewritePromptBuilder.userPayload(
            transcript: "Current sentence.",
            context: RewriteContext(
                appCategory: .email,
                fieldType: .multiLine,
                operation: .append,
                aggressiveness: .medium,
                languageMode: .english,
                profile: .email,
                protectedTerms: [ProtectedTerm(value: "PyTorch")],
                recentContext: "Previous sentence."
            )
        )

        XCTAssertTrue(payload.contains("<recent_context>"))
        XCTAssertTrue(payload.contains("Previous sentence."))
        XCTAssertTrue(payload.contains("Current sentence."))
        XCTAssertTrue(payload.contains("protected_terms: PyTorch"))
    }

    func testPromptBuilderOmitsRecentContextBlockWhenAbsent() {
        let payload = RewritePromptBuilder.userPayload(
            transcript: "Current sentence.",
            context: RewriteContext(
                appCategory: .chat,
                fieldType: .singleLine,
                operation: .insert,
                aggressiveness: .low,
                languageMode: .english,
                profile: .smart,
                protectedTerms: [],
                recentContext: nil
            )
        )

        XCTAssertFalse(payload.contains("<recent_context>"))
    }
}
