import Foundation

actor DictationStateMachine {
    private(set) var state: DictationLifecycleState = .idle

    func transition(to newState: DictationLifecycleState) throws {
        guard Self.allowedTransitions[state.stage, default: []].contains(newState.stage) || state.stage == newState.stage else {
            throw DictationError.providerConfiguration("Invalid state transition \(state.stage.rawValue) -> \(newState.stage.rawValue)")
        }
        state = newState
    }

    func forceTransition(to newState: DictationLifecycleState) {
        state = newState
    }

    static let allowedTransitions: [DictationLifecycleStage: Set<DictationLifecycleStage>] = [
        .idle: [.requestingPermissions, .ready, .error],
        .requestingPermissions: [.ready, .error, .idle],
        .ready: [.recording, .requestingPermissions, .error, .idle],
        .recording: [.receivingPartialTranscript, .segmentFinalizing, .ready, .error],
        .receivingPartialTranscript: [.recording, .segmentFinalizing, .ready, .error],
        .segmentFinalizing: [.normalizingVocabulary, .ready, .error],
        .normalizingVocabulary: [.rewriting, .inserting, .ready, .error],
        .rewriting: [.inserting, .ready, .error],
        .inserting: [.recording, .ready, .error],
        .error: [.ready, .requestingPermissions, .idle]
    ]
}
