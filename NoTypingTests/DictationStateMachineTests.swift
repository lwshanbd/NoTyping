import XCTest
@testable import NoTyping

final class DictationStateMachineTests: XCTestCase {
    func testAllowedTransitionPath() async throws {
        let machine = DictationStateMachine()
        try await machine.transition(to: DictationLifecycleState(stage: .ready, detail: nil))
        try await machine.transition(to: DictationLifecycleState(stage: .recording, detail: nil))
        try await machine.transition(to: DictationLifecycleState(stage: .segmentFinalizing, detail: nil))
        try await machine.transition(to: DictationLifecycleState(stage: .normalizingVocabulary, detail: nil))
        let stage = await machine.state.stage
        XCTAssertEqual(stage, .normalizingVocabulary)
    }

    func testInvalidTransitionThrows() async {
        let machine = DictationStateMachine()
        do {
            try await machine.transition(to: DictationLifecycleState(stage: .rewriting, detail: nil))
            XCTFail("Expected invalid transition to throw.")
        } catch {
            XCTAssertTrue(true)
        }
    }
}
