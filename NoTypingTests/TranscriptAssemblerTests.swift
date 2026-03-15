import XCTest
@testable import NoTyping

final class TranscriptAssemblerTests: XCTestCase {
    func testAssemblerSuppressesDuplicateCompletedEvents() {
        let assembler = TranscriptAssembler()
        let first = assembler.apply(.completed(itemID: "1", previousItemID: nil, text: "Hello", averageLogProbability: -0.2))
        let duplicate = assembler.apply(.completed(itemID: "1", previousItemID: nil, text: "Hello", averageLogProbability: -0.2))
        XCTAssertEqual(first.finalizedSegment?.rawText, "Hello")
        XCTAssertNil(duplicate.finalizedSegment)
    }

    func testAssemblerBuildsVisibleText() {
        let assembler = TranscriptAssembler()
        _ = assembler.apply(.partial(itemID: "1", previousItemID: nil, text: "Hello"))
        let update = assembler.apply(.partial(itemID: "2", previousItemID: "1", text: "world"))
        XCTAssertEqual(update.partialText, "Hello world")
    }

    func testReconnectPlannerUsesBoundedBackoff() {
        XCTAssertEqual(RealtimeReconnectPlanner.maxAttempts, 3)
        XCTAssertEqual(RealtimeReconnectPlanner.delayMilliseconds(forAttempt: 1), 250)
        XCTAssertEqual(RealtimeReconnectPlanner.delayMilliseconds(forAttempt: 2), 750)
        XCTAssertEqual(RealtimeReconnectPlanner.delayMilliseconds(forAttempt: 3), 2_000)
        XCTAssertEqual(RealtimeReconnectPlanner.delay(forAttempt: 1), .milliseconds(250))
        XCTAssertEqual(RealtimeReconnectPlanner.delay(forAttempt: 2), .milliseconds(750))
        XCTAssertEqual(RealtimeReconnectPlanner.delay(forAttempt: 3), .seconds(2))
        XCTAssertEqual(RealtimeReconnectPlanner.delay(forAttempt: 99), .seconds(2))
    }

    func testAssemblerIgnoresConnectionStatusEvents() {
        let assembler = TranscriptAssembler()
        _ = assembler.apply(.partial(itemID: "1", previousItemID: nil, text: "Hello"))
        let update = assembler.apply(.connectionStatus(.reconnecting(
            attempt: 1,
            maximumAttempts: RealtimeReconnectPlanner.maxAttempts,
            retryDelayMilliseconds: 250
        )))
        XCTAssertEqual(update.partialText, "Hello")
        XCTAssertNil(update.finalizedSegment)
    }

    func testRealtimeConnectionStatusFormatting() {
        let reconnecting = RealtimeConnectionStatus.reconnecting(
            attempt: 2,
            maximumAttempts: 3,
            retryDelayMilliseconds: 750
        )
        XCTAssertEqual(reconnecting.title, "Reconnecting")
        XCTAssertEqual(reconnecting.detail, "Retrying realtime connection (2/3) in 0.75s.")
        XCTAssertTrue(reconnecting.isRecovering)
        XCTAssertTrue(reconnecting.shouldAnnotateActiveSession)

        let resumed = RealtimeConnectionStatus.connected(resumedAfterReconnect: true)
        XCTAssertEqual(resumed.title, "Reconnected")
        XCTAssertEqual(resumed.detail, "Realtime transcription resumed after a transient disconnect.")
        XCTAssertFalse(resumed.isRecovering)
        XCTAssertTrue(resumed.shouldAnnotateActiveSession)

        let initial = RealtimeConnectionStatus.connected(resumedAfterReconnect: false)
        XCTAssertFalse(initial.shouldAnnotateActiveSession)
    }
}
