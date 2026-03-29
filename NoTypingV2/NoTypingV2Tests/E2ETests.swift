import XCTest
@testable import NoTypingV2

// MARK: - Mock Providers (E2E-specific, prefixed to avoid collision with PipelineStateTests)

private final class E2EMockSTT: TranscriptionProvider, @unchecked Sendable {
    var result: String = "hello world"
    var shouldFail = false
    var failError: PipelineError = .sttError("mock STT error")

    func transcribe(audioData: Data, vocabulary: [String]) async throws -> String {
        if shouldFail { throw failError }
        return result
    }
}

private final class E2EMockLLM: RewriteProvider, @unchecked Sendable {
    var result: String = ""
    var shouldFail = false
    var failError: PipelineError = .llmError("mock LLM error")

    func rewrite(text: String, vocabulary: [String]) async throws -> String {
        if shouldFail { throw failError }
        return result.isEmpty ? text : result
    }
}

// MARK: - E2E Pipeline Logic Tests
//
// DictationPipeline's data path:
//   raw audio -> STT transcription -> TextNormalizer -> LLM rewrite -> ValidationGate -> insert
//
// Since DictationPipeline takes concrete (non-protocol) dependencies for AudioRecorder,
// TextInsertionService, FocusedElementInspector, and HistoryStore, and those require
// hardware/Accessibility entitlements, we test the composable data-processing pipeline
// end-to-end by driving the same sequence of transforms the actor performs internally.

final class E2ETests: XCTestCase {

    private var mockSTT: E2EMockSTT!
    private var mockLLM: E2EMockLLM!
    private var normalizer: TextNormalizer!
    private var validationGate: ValidationGate!

    override func setUp() {
        super.setUp()
        mockSTT = E2EMockSTT()
        mockLLM = E2EMockLLM()
        normalizer = TextNormalizer()
        validationGate = ValidationGate()
    }

    // MARK: - 1. Happy Path

    /// Simulates: STT returns raw text -> normalizer cleans it -> LLM polishes it
    /// -> validation passes -> final polished text is the output.
    func testHappyPath_STTThenNormalizeThenPolishThenValidate() async throws {
        // Arrange
        mockSTT.result = "um so I want to use Xcode to build the app"
        mockLLM.result = "I want to use Xcode to build the app."

        let vocabulary = [
            VocabularyEntry(writtenForm: "Xcode", spokenForms: ["x code", "xcode"], enabled: true),
        ]
        let vocabTerms = ["Xcode"]

        // Act: step 1 - transcribe
        let rawText = try await mockSTT.transcribe(audioData: Data(), vocabulary: vocabTerms)

        // Act: step 2 - normalize
        let normalizedResult = normalizer.normalize(text: rawText, vocabulary: vocabulary)

        // Act: step 3 - polish with LLM
        let polished = try await mockLLM.rewrite(text: normalizedResult.text, vocabulary: vocabTerms)

        // Act: step 4 - validate
        let validationResult = validationGate.validate(original: normalizedResult.text, polished: polished)

        // Assert
        XCTAssertTrue(validationResult.passed, "Validation should pass for a well-formed LLM output")
        XCTAssertEqual(validationResult.text, "I want to use Xcode to build the app.")
        XCTAssertNil(validationResult.failureReason)
    }

    // MARK: - 2. STT Failure

    /// Simulates: STT throws an error -> pipeline should propagate the error.
    func testSTTFailure_PropagatesError() async {
        // Arrange
        mockSTT.shouldFail = true
        mockSTT.failError = .sttError("Connection refused")

        // Act
        do {
            _ = try await mockSTT.transcribe(audioData: Data(), vocabulary: [])
            XCTFail("Should have thrown an error")
        } catch let error as PipelineError {
            // Assert
            switch error {
            case .sttError(let msg):
                XCTAssertEqual(msg, "Connection refused")
            default:
                XCTFail("Expected sttError, got: \(error)")
            }
        } catch {
            XCTFail("Expected PipelineError, got: \(error)")
        }
    }

    // MARK: - 3. LLM Failure Fallback

    /// Simulates: STT succeeds -> normalize succeeds -> LLM throws -> pipeline
    /// falls back to the normalized text (graceful degradation).
    func testLLMFailure_FallsBackToNormalizedText() async throws {
        // Arrange
        mockSTT.result = "um I need to um configure the settings"
        mockLLM.shouldFail = true
        mockLLM.failError = .llmError("Service unavailable")

        let vocabulary = [
            VocabularyEntry(writtenForm: "settings", spokenForms: ["setting"], enabled: true),
        ]
        let vocabTerms = ["settings"]

        // Act: step 1 - transcribe succeeds
        let rawText = try await mockSTT.transcribe(audioData: Data(), vocabulary: vocabTerms)
        XCTAssertEqual(rawText, "um I need to um configure the settings")

        // Act: step 2 - normalize succeeds
        let normalizedResult = normalizer.normalize(text: rawText, vocabulary: vocabulary)

        // Act: step 3 - LLM fails
        var finalText = normalizedResult.text
        var llmFailed = false
        do {
            let polished = try await mockLLM.rewrite(text: normalizedResult.text, vocabulary: vocabTerms)
            let validationResult = validationGate.validate(original: normalizedResult.text, polished: polished)
            if validationResult.passed {
                finalText = validationResult.text
            }
        } catch {
            // Graceful degradation: use normalized text
            llmFailed = true
        }

        // Assert: LLM did fail, but we still have usable text
        XCTAssertTrue(llmFailed, "LLM should have failed")
        XCTAssertEqual(finalText, normalizedResult.text, "Should fall back to normalized text")
        XCTAssertFalse(finalText.isEmpty, "Fallback text should not be empty")
    }

    // MARK: - 4. Validation Gate Rejection

    /// Simulates: LLM returns a response that looks like prompt injection
    /// (prefixed with "Here is...") -> validation rejects it -> original text is used.
    func testValidationGateRejectsInjectedResponse() async throws {
        // Arrange
        mockSTT.result = "please update the database configuration for production"
        mockLLM.result = "Here is the updated database configuration for production."

        let vocabulary: [VocabularyEntry] = []
        let vocabTerms: [String] = []

        // Act: step 1 - transcribe
        let rawText = try await mockSTT.transcribe(audioData: Data(), vocabulary: vocabTerms)

        // Act: step 2 - normalize
        let normalizedResult = normalizer.normalize(text: rawText, vocabulary: vocabulary)

        // Act: step 3 - LLM returns injected-looking response
        let polished = try await mockLLM.rewrite(text: normalizedResult.text, vocabulary: vocabTerms)
        XCTAssertEqual(polished, "Here is the updated database configuration for production.")

        // Act: step 4 - validation detects injection prefix
        let validationResult = validationGate.validate(original: normalizedResult.text, polished: polished)

        // Assert: validation failed, original text is returned
        XCTAssertFalse(validationResult.passed, "Validation should reject LLM response with injection prefix")
        XCTAssertEqual(validationResult.failureReason, "detected LLM response prefix")
        XCTAssertEqual(validationResult.text, normalizedResult.text,
                       "On validation failure, the original (normalized) text should be returned")
    }
}
