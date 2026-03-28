import Foundation

actor DictationPipeline {
    private var state: PipelineState = .idle
    private var isProcessing = false
    private let eventContinuation: AsyncStream<PipelineEvent>.Continuation
    let events: AsyncStream<PipelineEvent>

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

    init(audioRecorder: AudioRecorder, sttProvider: any TranscriptionProvider, rewriteProvider: (any RewriteProvider)?, normalizer: TextNormalizer, validationGate: ValidationGate, insertionService: TextInsertionService, inspector: FocusedElementInspector, historyStore: HistoryStore, settings: AppSettings) {
        self.audioRecorder = audioRecorder
        self.sttProvider = sttProvider
        self.rewriteProvider = rewriteProvider
        self.normalizer = normalizer
        self.validationGate = validationGate
        self.insertionService = insertionService
        self.inspector = inspector
        self.historyStore = historyStore
        self.settings = settings
        var continuation: AsyncStream<PipelineEvent>.Continuation!
        self.events = AsyncStream { continuation = $0 }
        self.eventContinuation = continuation
    }

    func hotkeyPressed() { fatalError("TODO") }
    func hotkeyReleased() { fatalError("TODO") }
    func toggleRecording() { fatalError("TODO") }
    private func startRecording() { fatalError("TODO") }
    private func stopRecording() { fatalError("TODO") }
    private func runPipeline(audioData: Data) async { fatalError("TODO") }
}
