import XCTest
@testable import NoTyping

final class ValidationGateTests: XCTestCase {
    let gate = ValidationGate()

    // MARK: - Length checks

    /// Short text (<20 chars) should skip the length check entirely.
    /// "嗯" -> "嗯。" is a 100% length increase but under the threshold.
    func testShortTextSkipsLengthCheck() {
        let result = gate.validate(original: "嗯", polished: "嗯。")
        XCTAssertTrue(result.passed)
    }

    /// Output that exceeds 1.5x the original length (for originals >= 20 chars) should fail.
    func testOutputTooLong() {
        let original = "我想问一下这个功能怎么用比较好有没有什么推荐"  // >20 chars
        let tooLong = original + "这是一段完全多余的补充内容加上很多不需要的信息来测试长度超标的情况还有更多更多"
        let result = gate.validate(original: original, polished: tooLong)
        XCTAssertFalse(result.passed)
        XCTAssertNotNil(result.failureReason)
        XCTAssertEqual(result.failureReason, "output too long")
    }

    /// Output shorter than 0.3x the original length (for originals >= 20 chars) should fail.
    func testOutputTooShort() {
        let original = "我今天去了超市买了一些水果和蔬菜然后回家做了一顿饭"
        let result = gate.validate(original: original, polished: "买菜")
        XCTAssertFalse(result.passed)
        XCTAssertEqual(result.failureReason, "output too short")
    }

    /// A normal polish that removes filler words but stays within length bounds should pass.
    func testNormalLengthChangePass() {
        let original = "嗯我今天呢就是去了一下那个超市买了点东西"
        let polished = "我今天去了超市买了点东西"
        let result = gate.validate(original: original, polished: polished)
        XCTAssertTrue(result.passed)
    }

    /// Exactly at the 20-char boundary, length validation is applied.
    func testExactlyAtLengthThreshold() {
        // 20 CJK characters
        let original = "一二三四五六七八九十一二三四五六七八九十"
        XCTAssertEqual(original.count, 20)
        // Polished is within bounds (same length)
        let result = gate.validate(original: original, polished: original)
        XCTAssertTrue(result.passed)
    }

    // MARK: - Token overlap checks

    /// High overlap (normal filler removal) should pass.
    func testHighOverlapPass() {
        let original = "um so I went to the store and bought some stuff"
        let polished = "I went to the store and bought some stuff."
        let result = gate.validate(original: original, polished: polished)
        XCTAssertTrue(result.passed)
    }

    /// Low overlap means the LLM generated entirely new content. Should fail.
    func testLowOverlapFail() {
        let original = "我想问Claude怎么煎牛排用什么火候比较好"
        // LLM answered the question instead of formatting
        let polished = "煎牛排需要先将锅预热到高温，放入黄油，将牛排两面各煎三分钟"
        let result = gate.validate(original: original, polished: polished)
        XCTAssertFalse(result.passed)
        XCTAssertEqual(result.failureReason, "token overlap too low")
    }

    /// CJK characters should be tokenized per-character, so adding punctuation does not reduce overlap.
    func testCJKTokenOverlap() {
        let original = "今天天气很好我想出去走走"
        let polished = "今天天气很好，我想出去走走。"
        let result = gate.validate(original: original, polished: polished)
        XCTAssertTrue(result.passed)
    }

    /// Mixed CJK + English text should tokenize both correctly and measure overlap.
    func testMixedLanguageOverlap() {
        let original = "我想用 PyTorch 来训练一个 model"
        let polished = "我想用 PyTorch 来训练一个 model。"
        let result = gate.validate(original: original, polished: polished)
        XCTAssertTrue(result.passed)
    }

    // MARK: - Prefix detection

    /// English prefix "Here is" should be detected as an LLM response.
    func testEnglishPrefixDetection() {
        // Keep output within 1.5x length so length check passes and prefix check runs
        let original = "how to grill a steak nice and good"
        let polished = "Here is how to grill a steak nice and good"
        let result = gate.validate(original: original, polished: polished)
        XCTAssertFalse(result.passed)
        XCTAssertTrue(result.failureReason?.contains("prefix") == true)
    }

    /// English prefix "Sure" should be detected.
    func testSurePrefixDetection() {
        let original = "what is the best way to learn Swift programming"
        let polished = "Sure! The best way to learn Swift programming."
        let result = gate.validate(original: original, polished: polished)
        XCTAssertFalse(result.passed)
        XCTAssertTrue(result.failureReason?.contains("prefix") == true)
    }

    /// Chinese prefix "以下是" should be detected.
    func testChinesePrefixDetection() {
        let original = "怎么煎牛排"
        let polished = "以下是煎牛排的方法：首先准备一块好的牛排"
        let result = gate.validate(original: original, polished: polished)
        XCTAssertFalse(result.passed)
        XCTAssertEqual(result.failureReason, "detected LLM response prefix")
    }

    /// Chinese prefix "好的" followed by punctuation "，" should be detected.
    func testChinesePrefixWithPunctuation() {
        let original = "帮我写一个邮件回复"
        let polished = "好的，以下是邮件回复的内容：Dear..."
        let result = gate.validate(original: original, polished: polished)
        XCTAssertFalse(result.passed)
        XCTAssertEqual(result.failureReason, "detected LLM response prefix")
    }

    /// "Certainly" prefix should be detected (case-insensitive).
    func testCertainlyPrefixCaseInsensitive() {
        let original = "explain the bug to me in this function please"
        let polished = "certainly, the bug is in this function please"
        let result = gate.validate(original: original, polished: polished)
        XCTAssertFalse(result.passed)
        XCTAssertTrue(result.failureReason?.contains("prefix") == true)
    }

    // MARK: - Combined / realistic scenarios

    /// Identical input and output should always pass.
    func testIdenticalPassThrough() {
        let text = "The meeting is at 3 PM tomorrow."
        let result = gate.validate(original: text, polished: text)
        XCTAssertTrue(result.passed)
        XCTAssertEqual(result.text, text)
    }

    /// A realistic prompt injection scenario: user dictates a question, LLM answers it.
    func testRealisticInjectionScenario() {
        let original = "嗯我想问一下Claude怎么煎牛排用什么火候比较好"
        // LLM answers instead of formatting
        let polished = "煎牛排的最佳方法是使用中高火。首先将平底锅加热，放入适量黄油或橄榄油，当油温达到冒烟点时放入牛排。"
        let result = gate.validate(original: original, polished: polished)
        XCTAssertFalse(result.passed, "Should detect injection: LLM answered the question instead of formatting")
    }

    /// Both empty strings should pass (no content to validate).
    func testEmptyInput() {
        let result = gate.validate(original: "", polished: "")
        XCTAssertTrue(result.passed)
    }

    /// When validation passes, the returned text should be the polished version.
    func testPassedResultContainsPolishedText() {
        let original = "um hello world"
        let polished = "Hello world."
        let result = gate.validate(original: original, polished: polished)
        XCTAssertTrue(result.passed)
        XCTAssertEqual(result.text, polished)
    }

    /// When validation fails, the returned text should be the original (fallback).
    func testFailedResultContainsOriginalText() {
        let original = "我今天去了超市买了一些水果和蔬菜然后回家做了一顿饭"
        let polished = "买菜"
        let result = gate.validate(original: original, polished: polished)
        XCTAssertFalse(result.passed)
        XCTAssertEqual(result.text, original, "Failed validation should return the original text")
    }
}
