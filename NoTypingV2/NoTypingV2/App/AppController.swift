import AppKit
import Combine
import SwiftUI

@MainActor
final class AppController: NSObject, ObservableObject, HotkeyManagerDelegate {
    let settingsStore: SettingsStore
    let vocabularyStore: VocabularyStore
    let historyStore: HistoryStore
    let permissionManager: PermissionManager

    private let hotkeyManager = HotkeyManager()
    private let hudController = HUDController()
    private let resultPanelController = ResultPanelController()
    private let menuBarController = MenuBarController()
    private let settingsWindowController = SettingsWindowController()
    private var pipeline: DictationPipeline?
    private var eventTask: Task<Void, Never>?

    override init() {
        self.settingsStore = SettingsStore()
        self.vocabularyStore = VocabularyStore()
        self.historyStore = HistoryStore()
        self.permissionManager = PermissionManager()
        super.init()
    }

    // MARK: - Lifecycle

    func start() {
        // 1. Setup menu bar
        menuBarController.onSettingsClicked = { [weak self] in
            self?.openSettings()
        }
        menuBarController.onQuitClicked = {
            NSApplication.shared.terminate(nil)
        }
        menuBarController.setup()

        // 2. Check permissions
        permissionManager.refresh()

        // 3. If no API key configured, show settings on API tab
        let sttKey = settingsStore.loadAPIKey(for: settingsStore.settings.sttConfig.apiKeyAccount)
        if sttKey == nil || sttKey?.isEmpty == true {
            openSettings()
        }

        // 4. Register hotkey
        do {
            try hotkeyManager.register(hotkey: settingsStore.settings.hotkey)
        } catch {
            print("[AppController] Failed to register hotkey: \(error.localizedDescription)")
        }

        // 5. Set delegate
        hotkeyManager.delegate = self

        // 6. Build and start the pipeline
        rebuildPipeline()
    }

    func stop() {
        eventTask?.cancel()
        eventTask = nil
        hotkeyManager.unregister()
        pipeline = nil
    }

    // MARK: - Pipeline Construction

    private func rebuildPipeline() {
        // Cancel previous event listener
        eventTask?.cancel()
        eventTask = nil

        let settings = settingsStore.settings

        // Build STT provider
        let sttAPIKey = settingsStore.loadAPIKey(for: settings.sttConfig.apiKeyAccount) ?? ""
        let sttProvider = WhisperTranscriptionProvider(
            apiKey: sttAPIKey,
            baseURL: settings.sttConfig.baseURL,
            model: settings.sttConfig.model
        )

        // Build LLM rewrite provider (optional)
        let rewriteProvider: (any RewriteProvider)?
        if settings.llmEnabled {
            let llmAPIKey = settingsStore.loadAPIKey(for: settings.llmConfig.apiKeyAccount) ?? ""
            if !llmAPIKey.isEmpty {
                switch settings.llmConfig.provider {
                case .openai:
                    rewriteProvider = OpenAIRewriteProvider(
                        apiKey: llmAPIKey,
                        baseURL: settings.llmConfig.baseURL,
                        model: settings.llmConfig.model
                    )
                case .claude:
                    rewriteProvider = ClaudeRewriteProvider(
                        apiKey: llmAPIKey,
                        baseURL: settings.llmConfig.baseURL,
                        model: settings.llmConfig.model
                    )
                case .gemini:
                    rewriteProvider = GeminiRewriteProvider(
                        apiKey: llmAPIKey,
                        model: settings.llmConfig.model
                    )
                }
            } else {
                rewriteProvider = nil
            }
        } else {
            rewriteProvider = nil
        }

        // Gather vocabulary
        let vocabTerms = vocabularyStore.entries.filter(\.enabled).map(\.writtenForm)
        let vocabEntries = vocabularyStore.entries

        // Create the pipeline
        let newPipeline = DictationPipeline(
            audioRecorder: AudioRecorder(),
            sttProvider: sttProvider,
            rewriteProvider: rewriteProvider,
            normalizer: TextNormalizer(),
            validationGate: ValidationGate(),
            insertionService: TextInsertionService(),
            inspector: FocusedElementInspector(),
            historyStore: historyStore,
            settings: settings,
            vocabularyTerms: vocabTerms,
            vocabularyEntries: vocabEntries
        )
        self.pipeline = newPipeline

        // Start listening to pipeline events
        eventTask = Task { [weak self] in
            for await event in newPipeline.events {
                guard let self, !Task.isCancelled else { break }
                self.handlePipelineEvent(event)
            }
        }
    }

    // MARK: - Event Handling

    private func handlePipelineEvent(_ event: PipelineEvent) {
        switch event {
        case .stateChanged(let state):
            menuBarController.updateStatus(state)
            switch state {
            case .recording:
                hudController.show(state: "Recording...")
            case .transcribing:
                hudController.show(state: "Transcribing...")
            case .normalizing:
                // Brief phase, no HUD update needed
                break
            case .polishing:
                hudController.show(state: "Polishing...")
            case .inserting:
                // Brief phase, no HUD update needed
                break
            case .ready:
                // Pipeline returned to ready; HUD will be hidden by result/error handlers
                break
            case .idle, .error:
                break
            }

        case .volumeLevel(let level):
            hudController.updateVolume(level)

        case .transcriptionResult(_, let finalText):
            let preview = finalText.count > 40 ? String(finalText.prefix(40)) + "..." : finalText
            hudController.show(state: "\u{2713}", detail: preview)
            hudController.hide(after: 1.5)

        case .focusLost(let text):
            hudController.dismiss()
            resultPanelController.show(text: text)

        case .error(let err):
            hudController.show(state: "\u{26A0}", detail: err.errorDescription ?? "Unknown error", isError: true)
            hudController.hide(after: 3.0)
        }
    }

    // MARK: - HotkeyManagerDelegate

    func hotkeyPressed() {
        guard let pipeline else { return }
        switch settingsStore.settings.hotkeyMode {
        case .toggle:
            Task { await pipeline.toggleRecording() }
        case .pushToTalk:
            Task { await pipeline.hotkeyPressed() }
        }
    }

    func hotkeyReleased() {
        guard let pipeline else { return }
        switch settingsStore.settings.hotkeyMode {
        case .pushToTalk:
            Task { await pipeline.hotkeyReleased() }
        case .toggle:
            break // No action on release in toggle mode
        }
    }

    // MARK: - Menu Actions

    private func openSettings() {
        settingsWindowController.show(
            rootView: SettingsRootView()
                .environmentObject(settingsStore)
                .environmentObject(vocabularyStore)
                .environmentObject(historyStore)
                .environmentObject(permissionManager)
                .frame(minWidth: 600, minHeight: 400)
        )
    }
}
