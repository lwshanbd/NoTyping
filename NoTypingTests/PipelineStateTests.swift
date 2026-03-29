import XCTest
@testable import NoTyping

// MARK: - Mock Transcription Provider

private final class MockTranscriptionProvider: TranscriptionProvider, @unchecked Sendable {
    var cannedResult: String = "hello world"
    var shouldThrow: Error?
    var delay: TimeInterval = 0

    func transcribe(audioData: Data, vocabulary: [String]) async throws -> String {
        if delay > 0 {
            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }
        if let error = shouldThrow {
            throw error
        }
        return cannedResult
    }
}

// MARK: - Mock Rewrite Provider

private final class MockRewriteProvider: RewriteProvider, @unchecked Sendable {
    var cannedResult: String = ""
    var shouldThrow: Error?

    func rewrite(text: String, vocabulary: [String]) async throws -> String {
        if let error = shouldThrow {
            throw error
        }
        return cannedResult.isEmpty ? text : cannedResult
    }
}

// MARK: - Event collection helper

/// Collects pipeline events for a limited time, returning all received events.
private func collectEvents(
    from stream: AsyncStream<PipelineEvent>,
    timeout: TimeInterval = 2.0,
    stopAfter count: Int = 20
) async -> [PipelineEvent] {
    var events: [PipelineEvent] = []
    let deadline = Date().addingTimeInterval(timeout)

    for await event in stream {
        events.append(event)
        if events.count >= count || Date() > deadline {
            break
        }
    }
    return events
}

/// Extracts only the state-change events from a list of pipeline events.
private func stateChanges(from events: [PipelineEvent]) -> [PipelineState] {
    events.compactMap { event in
        if case .stateChanged(let state) = event {
            return state
        }
        return nil
    }
}

/// Extracts error events from a list of pipeline events.
private func errors(from events: [PipelineEvent]) -> [PipelineError] {
    events.compactMap { event in
        if case .error(let error) = event {
            return error
        }
        return nil
    }
}

// MARK: - Tests

final class PipelineStateTests: XCTestCase {

    /// Creates a DictationPipeline with mock/default services suitable for testing.
    /// In a test environment, AudioRecorder.start() will fail (no audio hardware),
    /// which exercises the error recovery path.
    private func makePipeline(
        sttProvider: (any TranscriptionProvider)? = nil,
        rewriteProvider: (any RewriteProvider)? = nil,
        llmEnabled: Bool = false
    ) async -> DictationPipeline {
        let recorder = AudioRecorder()
        let stt = sttProvider ?? MockTranscriptionProvider()
        let normalizer = TextNormalizer()
        let validationGate = ValidationGate()
        let insertionService = TextInsertionService()
        let inspector = FocusedElementInspector()
        let historyStore = await MainActor.run { HistoryStore() }
        var settings = AppSettings()
        settings.llmEnabled = llmEnabled

        return DictationPipeline(
            audioRecorder: recorder,
            sttProvider: stt,
            rewriteProvider: rewriteProvider,
            normalizer: normalizer,
            validationGate: validationGate,
            insertionService: insertionService,
            inspector: inspector,
            historyStore: historyStore,
            settings: settings
        )
    }

    // MARK: 1. Happy path: hotkeyPressed transitions to .recording

    /// When the pipeline is in its initial state (idle), calling hotkeyPressed()
    /// should transition to .recording. The recording itself will fail in a test
    /// environment (no audio device), but the state transition should still fire.
    func testHotkeyPressedTransitionsToRecording() async throws {
        let pipeline = await makePipeline()
        let eventsStream = await pipeline.events

        // Collect events in background
        let collectTask = Task {
            await collectEvents(from: eventsStream, timeout: 2.0, stopAfter: 5)
        }

        // Small delay to let collection start
        try await Task.sleep(nanoseconds: 50_000_000)

        await pipeline.hotkeyPressed()

        // Give time for the async state transition
        try await Task.sleep(nanoseconds: 500_000_000)

        collectTask.cancel()
        let events = await collectTask.value
        let states = stateChanges(from: events)

        // The first state change should be .recording
        XCTAssertFalse(states.isEmpty, "Should have received at least one state change")
        if let first = states.first {
            XCTAssertEqual(first, .recording, "First state transition should be .recording")
        }
    }

    // MARK: 2. hotkeyPressed while recording/processing is rejected

    /// Calling hotkeyPressed() a second time while already recording/processing
    /// should not trigger a new recording cycle. The guard in hotkeyPressed checks
    /// state == .ready || .idle and !isProcessing.
    func testDoubleHotkeyPressedIsRejected() async throws {
        let pipeline = await makePipeline()
        let eventsStream = await pipeline.events

        let collectTask = Task {
            await collectEvents(from: eventsStream, timeout: 2.0, stopAfter: 10)
        }

        try await Task.sleep(nanoseconds: 50_000_000)

        // First press
        await pipeline.hotkeyPressed()
        try await Task.sleep(nanoseconds: 100_000_000)

        // Second press while in recording/processing
        await pipeline.hotkeyPressed()
        try await Task.sleep(nanoseconds: 500_000_000)

        collectTask.cancel()
        let events = await collectTask.value
        let states = stateChanges(from: events)

        // Count how many times we transitioned to .recording
        let recordingCount = states.filter { $0 == .recording }.count
        XCTAssertEqual(recordingCount, 1, "Should only transition to .recording once despite double press")
    }

    // MARK: 3. Short recording is discarded (< 0.3s)

    /// When hotkeyReleased() is called immediately after hotkeyPressed(),
    /// the recording duration will be < 0.3s (actually 0 in tests since the
    /// audio engine never starts). This should emit .recordingTooShort error
    /// and return to .ready state.
    func testShortRecordingDiscarded() async throws {
        let pipeline = await makePipeline()
        let eventsStream = await pipeline.events

        let collectTask = Task {
            await collectEvents(from: eventsStream, timeout: 2.0, stopAfter: 10)
        }

        try await Task.sleep(nanoseconds: 50_000_000)

        // Press and release immediately
        await pipeline.hotkeyPressed()
        try await Task.sleep(nanoseconds: 100_000_000)
        await pipeline.hotkeyReleased()

        try await Task.sleep(nanoseconds: 500_000_000)

        collectTask.cancel()
        let events = await collectTask.value

        let errs = errors(from: events)
        let hasRecordingTooShort = errs.contains { error in
            if case .recordingTooShort = error { return true }
            return false
        }
        XCTAssertTrue(hasRecordingTooShort, "Should emit .recordingTooShort for immediate release")

        // Should also transition back to .ready
        let states = stateChanges(from: events)
        if let lastState = states.last {
            XCTAssertEqual(lastState, .ready, "Should return to .ready after short recording discard")
        }
    }

    // MARK: 4. toggleRecording starts recording from idle

    /// toggleRecording() from idle should transition to recording, same as hotkeyPressed().
    func testToggleRecordingStartsFromIdle() async throws {
        let pipeline = await makePipeline()
        let eventsStream = await pipeline.events

        let collectTask = Task {
            await collectEvents(from: eventsStream, timeout: 2.0, stopAfter: 5)
        }

        try await Task.sleep(nanoseconds: 50_000_000)

        await pipeline.toggleRecording()

        try await Task.sleep(nanoseconds: 500_000_000)

        collectTask.cancel()
        let events = await collectTask.value
        let states = stateChanges(from: events)

        XCTAssertFalse(states.isEmpty, "Should have received state changes")
        if let first = states.first {
            XCTAssertEqual(first, .recording, "toggleRecording from idle should go to .recording")
        }
    }

    // MARK: 5. toggleRecording stops recording when already recording

    /// Calling toggleRecording() while in .recording state should stop recording.
    /// Since the recording duration is 0 in tests, it will trigger the short recording
    /// discard path and return to .ready.
    func testToggleRecordingStopsWhenRecording() async throws {
        let pipeline = await makePipeline()
        let eventsStream = await pipeline.events

        let collectTask = Task {
            await collectEvents(from: eventsStream, timeout: 3.0, stopAfter: 10)
        }

        try await Task.sleep(nanoseconds: 50_000_000)

        // Start recording
        await pipeline.toggleRecording()
        try await Task.sleep(nanoseconds: 200_000_000)

        // Toggle again to stop
        await pipeline.toggleRecording()
        try await Task.sleep(nanoseconds: 500_000_000)

        collectTask.cancel()
        let events = await collectTask.value
        let states = stateChanges(from: events)

        // Should have gone to .recording then back to .ready (via short-recording discard)
        XCTAssertTrue(states.contains(.recording), "Should have transitioned to .recording")
        if let lastState = states.last {
            XCTAssertEqual(lastState, .ready, "Should return to .ready after toggle stop")
        }
    }

    // MARK: 6. hotkeyReleased ignored when not recording

    /// Calling hotkeyReleased() when not in .recording state should be a no-op.
    func testHotkeyReleasedIgnoredWhenNotRecording() async throws {
        let pipeline = await makePipeline()
        let eventsStream = await pipeline.events

        let collectTask = Task {
            await collectEvents(from: eventsStream, timeout: 1.0, stopAfter: 5)
        }

        try await Task.sleep(nanoseconds: 50_000_000)

        // Release without pressing first
        await pipeline.hotkeyReleased()

        try await Task.sleep(nanoseconds: 500_000_000)

        collectTask.cancel()
        let events = await collectTask.value

        // Should have received no events at all
        XCTAssertTrue(events.isEmpty, "hotkeyReleased when not recording should produce no events")
    }
}
