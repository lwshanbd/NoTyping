import XCTest
@testable import NoTyping

final class SegmentJoinerTests: XCTestCase {
    func testEnglishSegmentsInsertSpaces() {
        XCTAssertEqual(SegmentJoiner.join(["Hello", "world."]), "Hello world.")
    }

    func testChineseSegmentsDoNotInsertSpaces() {
        XCTAssertEqual(SegmentJoiner.join(["你好，", "今天怎么样？"]), "你好，今天怎么样？")
    }
}
