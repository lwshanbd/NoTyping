import XCTest
@testable import NoTyping

final class TextNormalizerTests: XCTestCase {
    let normalizer = TextNormalizer()

    /// A spoken form should be replaced with its written form.
    func testSpokenFormReplacement() {
        let vocab = [VocabularyEntry(writtenForm: "PyTorch", spokenForms: ["pytorch", "pie torch"])]
        let result = normalizer.normalize(text: "I'm using pytorch for training", vocabulary: vocab)
        XCTAssertEqual(result.text, "I'm using PyTorch for training")
        XCTAssertEqual(result.appliedReplacements.count, 1)
        XCTAssertEqual(result.appliedReplacements[0].spoken, "pytorch")
        XCTAssertEqual(result.appliedReplacements[0].written, "PyTorch")
    }

    /// Matching should be case-insensitive.
    func testCaseInsensitiveMatching() {
        let vocab = [VocabularyEntry(writtenForm: "NVIDIA", spokenForms: ["nvidia", "Nvidia"])]
        let result = normalizer.normalize(text: "nvidia makes great GPUs", vocabulary: vocab)
        XCTAssertEqual(result.text, "NVIDIA makes great GPUs")
    }

    /// Multiple vocabulary entries should all be applied.
    func testMultipleReplacements() {
        let vocab = [
            VocabularyEntry(writtenForm: "PyTorch", spokenForms: ["pytorch"]),
            VocabularyEntry(writtenForm: "TensorFlow", spokenForms: ["tensorflow"]),
        ]
        let result = normalizer.normalize(text: "pytorch and tensorflow are popular", vocabulary: vocab)
        XCTAssertTrue(result.text.contains("PyTorch"))
        XCTAssertTrue(result.text.contains("TensorFlow"))
        XCTAssertEqual(result.appliedReplacements.count, 2)
    }

    /// Entries with enabled == false should not produce replacements.
    func testDisabledEntrySkipped() {
        let vocab = [VocabularyEntry(writtenForm: "PyTorch", spokenForms: ["pytorch"], enabled: false)]
        let result = normalizer.normalize(text: "pytorch is great", vocabulary: vocab)
        XCTAssertEqual(result.text, "pytorch is great")
        XCTAssertTrue(result.appliedReplacements.isEmpty)
    }

    /// Multiple consecutive whitespace characters should be collapsed to a single space.
    func testWhitespaceCollapse() {
        let result = normalizer.normalize(text: "hello    world   test", vocabulary: [])
        XCTAssertEqual(result.text, "hello world test")
    }

    /// When no vocabulary matches, the text should pass through unchanged (aside from whitespace normalization).
    func testNoMatchPassthrough() {
        let vocab = [VocabularyEntry(writtenForm: "PyTorch", spokenForms: ["pytorch"])]
        let result = normalizer.normalize(text: "hello world", vocabulary: vocab)
        XCTAssertEqual(result.text, "hello world")
        XCTAssertTrue(result.appliedReplacements.isEmpty)
    }
}
