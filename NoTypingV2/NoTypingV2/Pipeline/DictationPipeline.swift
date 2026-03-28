import Foundation

/// Sendable snapshot of the focus context for cross-isolation comparison.
/// AXUIElement is not Sendable, so we capture only the identity fields.
struct FocusSnapshot: Sendable {
    let bundleIdentifier: String?
    let pid: pid_t?
    let isEditable: Bool
    let isSecureTextField: Bool
}

actor DictationPipeline {
    private var state: PipelineState = .idle
    private var isProcessing = false
    private let eventContinuation: AsyncStream<PipelineEvent>.Continuation
    let events: AsyncStream<PipelineEvent>

    /// Saved focus context captured when recording starts.
    private var savedFocusSnapshot: FocusSnapshot?

    // Services (injected)
    private let audioRecorder: AudioRecorder
    private let sttProvider: any TranscriptionProvider
    private let rewriteProvider: (any RewriteProvider)?
    private let normalizer: TextNormalizer
    private let validationGate: ValidationGate
    private let insertionService: TextInsertionService
    private let inspector: FocusedElementInspector
    private let historyStore: HistoryStore
    private let settings: AppSettings
    private let vocabularyTerms: [String]
    private let vocabularyEntries: [VocabularyEntry]

    init(audioRecorder: AudioRecorder, sttProvider: any TranscriptionProvider, rewriteProvider: (any RewriteProvider)?, normalizer: TextNormalizer, validationGate: ValidationGate, insertionService: TextInsertionService, inspector: FocusedElementInspector, historyStore: HistoryStore, settings: AppSettings, vocabularyTerms: [String] = [], vocabularyEntries: [VocabularyEntry] = []) {
        self.audioRecorder = audioRecorder
        self.sttProvider = sttProvider
        self.rewriteProvider = rewriteProvider
        self.normalizer = normalizer
        self.validationGate = validationGate
        self.insertionService = insertionService
        self.inspector = inspector
        self.historyStore = historyStore
        self.settings = settings
        self.vocabularyTerms = vocabularyTerms
        self.vocabularyEntries = vocabularyEntries
        var continuation: AsyncStream<PipelineEvent>.Continuation!
        self.events = AsyncStream { continuation = $0 }
        self.eventContinuation = continuation
    }

    // MARK: - Public API

    /// Push-to-talk: start recording on key down.
    func hotkeyPressed() {
        guard !isProcessing else { return }
        if state == .ready || state == .idle {
            startRecording()
        }
    }

    /// Push-to-talk: stop recording on key up, then process.
    func hotkeyReleased() {
        guard state == .recording else { return }
        stopRecording()
    }

    /// Toggle mode: start or stop recording.
    func toggleRecording() {
        if state == .recording {
            stopRecording()
        } else if !isProcessing && (state == .ready || state == .idle) {
            startRecording()
        }
    }

    // MARK: - Recording Control

    private func startRecording() {
        // Capture focus context on the main actor before starting
        let inspectorRef = inspector
        let recorderRef = audioRecorder

        transition(to: .recording)

        Task { @MainActor in
            let context = inspectorRef.inspect()
            let snapshot = FocusSnapshot(
                bundleIdentifier: context.bundleIdentifier,
                pid: context.pid,
                isEditable: context.isEditable,
                isSecureTextField: context.isSecureTextField
            )
            await self.saveFocusSnapshot(snapshot)

            do {
                try recorderRef.start()
            } catch {
                await self.emitError(.sttError("Failed to start recording: \(error.localizedDescription)"))
            }
        }
    }

    private func saveFocusSnapshot(_ snapshot: FocusSnapshot) {
        self.savedFocusSnapshot = snapshot
    }

    private func stopRecording() {
        let recording = audioRecorder.stop()

        // Check minimum duration
        if recording.duration < 0.3 {
            emitError(.recordingTooShort)
            return
        }

        isProcessing = true

        // Encode PCM to WAV
        let wavData = WAVEncoder.encode(pcmData: recording.pcmData)

        Task {
            await runPipeline(audioData: wavData)
        }
    }

    // MARK: - Pipeline Processing

    private func runPipeline(audioData: Data) async {
        defer {
            isProcessing = false
            transition(to: .ready)
        }

        do {
            // Step 1: Transcribe
            transition(to: .transcribing)

            let rawText = try await withThrowingTimeout(seconds: 30) {
                try await self.sttProvider.transcribe(audioData: audioData, vocabulary: self.vocabularyTerms)
            }

            let trimmedRaw = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedRaw.isEmpty {
                emit(.error(.sttEmpty))
                return
            }

            // Step 2: Normalize
            transition(to: .normalizing)

            let normalizedResult = normalizer.normalize(text: trimmedRaw, vocabulary: vocabularyEntries)
            var finalText = normalizedResult.text
            let originalText = trimmedRaw

            // Step 3: Polish with LLM (optional)
            if settings.llmEnabled, let rewriter = rewriteProvider {
                transition(to: .polishing)

                do {
                    let textForRewrite = finalText
                    let polished = try await withThrowingTimeout(seconds: 15) {
                        try await rewriter.rewrite(text: textForRewrite, vocabulary: self.vocabularyTerms)
                    }

                    // Validate the LLM output
                    let validationResult = validationGate.validate(original: finalText, polished: polished)
                    if validationResult.passed {
                        finalText = validationResult.text
                    } else {
                        // Validation failed: use normalized text, emit event
                        emit(.error(.validationFailed(validationResult.failureReason ?? "unknown")))
                    }
                } catch is TimeoutError {
                    // LLM timeout: use normalized text
                    emit(.error(.llmTimeout))
                } catch let pipelineError as PipelineError {
                    emit(.error(pipelineError))
                } catch {
                    emit(.error(.llmError(error.localizedDescription)))
                }
            }

            // Step 4: Insert text
            transition(to: .inserting)

            // Check if focus target is still valid
            let currentSnapshot = await captureCurrentFocus()
            let focusStillValid = isFocusValid(saved: savedFocusSnapshot, current: currentSnapshot)

            if !focusStillValid {
                // Focus lost: show result panel instead
                emit(.focusLost(text: finalText))
                await saveHistory(rawText: originalText, polishedText: finalText, targetApp: savedFocusSnapshot?.bundleIdentifier, wasInserted: false)
                return
            }

            // Insert text via main actor
            let insertionSvc = insertionService
            let insertionError: PipelineError? = await MainActor.run {
                do {
                    try insertionSvc.insert(text: finalText)
                    return nil
                } catch let err as PipelineError {
                    return err
                } catch {
                    return .insertionFailed(error.localizedDescription)
                }
            }

            if let insertionError {
                emit(.error(insertionError))
                // Still save to history even if insertion failed
                await saveHistory(rawText: originalText, polishedText: finalText, targetApp: savedFocusSnapshot?.bundleIdentifier, wasInserted: false)
                return
            }

            // Step 5: Save to history and emit result
            await saveHistory(rawText: originalText, polishedText: finalText, targetApp: savedFocusSnapshot?.bundleIdentifier, wasInserted: true)
            emit(.transcriptionResult(original: originalText, final: finalText))

        } catch is TimeoutError {
            emit(.error(.sttTimeout))
        } catch let pipelineError as PipelineError {
            emit(.error(pipelineError))
        } catch {
            emit(.error(.sttError(error.localizedDescription)))
        }
    }

    // MARK: - Helpers

    private func transition(to newState: PipelineState) {
        state = newState
        emit(.stateChanged(newState))
    }

    private func emit(_ event: PipelineEvent) {
        eventContinuation.yield(event)
    }

    private func emitError(_ error: PipelineError) {
        emit(.error(error))
        transition(to: .ready)
        isProcessing = false
    }

    private func captureCurrentFocus() async -> FocusSnapshot {
        let inspectorRef = inspector
        return await MainActor.run {
            let ctx = inspectorRef.inspect()
            return FocusSnapshot(
                bundleIdentifier: ctx.bundleIdentifier,
                pid: ctx.pid,
                isEditable: ctx.isEditable,
                isSecureTextField: ctx.isSecureTextField
            )
        }
    }

    private func isFocusValid(saved: FocusSnapshot?, current: FocusSnapshot) -> Bool {
        guard let saved else { return false }
        // Same app (by PID) is still focused
        return saved.pid == current.pid && saved.pid != nil
    }

    private func saveHistory(rawText: String, polishedText: String, targetApp: String?, wasInserted: Bool) async {
        let entry = HistoryEntry(
            timestamp: Date(),
            rawText: rawText,
            polishedText: polishedText,
            targetApp: targetApp,
            wasInserted: wasInserted
        )
        let store = historyStore
        await MainActor.run {
            store.add(entry)
        }
    }
}

// MARK: - Timeout Utility

private struct TimeoutError: Error {}

/// Runs an async closure with a deadline. Throws `TimeoutError` if the deadline is exceeded.
private func withThrowingTimeout<T: Sendable>(seconds: TimeInterval, operation: @escaping @Sendable () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask {
            try await operation()
        }
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw TimeoutError()
        }
        // The first task to finish wins; cancel the other.
        guard let result = try await group.next() else {
            throw TimeoutError()
        }
        group.cancelAll()
        return result
    }
}
