import XCTest
@testable import NoTyping

final class VocabularyNormalizationTests: XCTestCase {
    func testSpokenAliasMapsToPreferredWrittenForm() {
        let normalizer = TranscriptNormalizer()
        let entries = [VocabularyEntry(writtenForm: "PyTorch", spokenForms: ["pytorch"], languageScope: .both)]
        let normalized = normalizer.normalize(transcript: "pytorch is great", entries: entries, languageMode: .english)
        XCTAssertEqual(normalized.text, "PyTorch is great")
        XCTAssertTrue(normalized.protectedTerms.contains(ProtectedTerm(value: "PyTorch")))
    }

    func testAcronymCollapseUsesConfiguredEntry() {
        let normalizer = TranscriptNormalizer()
        let entries = [VocabularyEntry(writtenForm: "NCCL", spokenForms: ["N C C L"], languageScope: .both)]
        let normalized = normalizer.normalize(transcript: "We use N C C L for all reduce", entries: entries, languageMode: .english)
        XCTAssertEqual(normalized.text, "We use NCCL for all reduce")
    }

    func testTechnicalProtectedTermsDetectFlagsPathsAndIdentifiers() {
        let normalizer = TranscriptNormalizer()
        let terms = normalizer.technicalProtectedTerms(
            in: "run ./train.py --max-tokens=256 with NCCL all-reduce and https://example.com/docs",
            profile: .codeAware,
            appCategory: .code
        )

        XCTAssertTrue(terms.contains(ProtectedTerm(value: "./train.py")))
        XCTAssertTrue(terms.contains(ProtectedTerm(value: "--max-tokens=256")))
        XCTAssertTrue(terms.contains(ProtectedTerm(value: "NCCL")))
        XCTAssertTrue(terms.contains(ProtectedTerm(value: "all-reduce")))
        XCTAssertTrue(terms.contains(ProtectedTerm(value: "https://example.com/docs")))
    }

    func testTechnicalProtectionDisabledForNonCodeContexts() {
        let normalizer = TranscriptNormalizer()
        let terms = normalizer.technicalProtectedTerms(
            in: "visit https://example.com and mention NCCL",
            profile: .smart,
            appCategory: .chat
        )

        XCTAssertTrue(terms.isEmpty)
    }

    func testLiteralRewriteBypassSuggestedForShellLikeText() {
        let normalizer = TranscriptNormalizer()
        let shouldBypass = normalizer.suggestsLiteralRewriteBypass(
            text: "python ./train.py --max-tokens=256 | tee output.log",
            protectedTerms: [
                ProtectedTerm(value: "./train.py"),
                ProtectedTerm(value: "--max-tokens=256"),
                ProtectedTerm(value: "output.log"),
                ProtectedTerm(value: "python")
            ],
            profile: .codeAware,
            appCategory: .terminal
        )

        XCTAssertTrue(shouldBypass)
    }
}
