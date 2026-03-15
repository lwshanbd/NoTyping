import AppKit
import Combine
import SwiftUI

private struct StagedInsertionSegment: Equatable {
    var id: String
    var rawText: String
    var finalText: String
}

@MainActor
final class AppCoordinator: NSObject, ObservableObject {
    @Published private(set) var settings: AppSettings
    @Published private(set) var lifecycleState: DictationLifecycleState = .idle
    @Published private(set) var vocabularyEntries: [VocabularyEntry] = []
    @Published private(set) var diagnostics: [DiagnosticEntry] = []
    @Published private(set) var historyEntries: [HistoryEntry] = []
    @Published var selectedSettingsTab: SettingsTab = .general
    @Published private(set) var providerTestMessage: String?
    @Published private(set) var realtimeConnectionStatus: RealtimeConnectionStatus = .stopped
    @Published private(set) var microphonePermissionStatus: PermissionManager.PermissionStatus
    @Published private(set) var accessibilityPermissionStatus: PermissionManager.PermissionStatus

    private let container: DependencyContainer
    private let stateMachine = DictationStateMachine()
    private let hotkeyManager = HotkeyManager()
    private let audioCaptureManager = AudioCaptureManager()
    private let transcriptAssembler = TranscriptAssembler()
    private let hudController = HUDOverlayController()
    private let menuBarController = MenuBarController()
    private let settingsWindowController = SettingsWindowController()
    private var transcriptionService: RealtimeTranscriptionServiceProtocol?
    private var activeRewriteService: RewriteServiceProtocol?
    private var cancellables: Set<AnyCancellable> = []
    private var isDictationActive = false
    private var pendingStopTask: Task<Void, Never>?
    private var pendingSegmentWorkCount = 0
    private var stagedSegments: [StagedInsertionSegment] = []
    private var focusedElementContext = FocusedElementContext(
        bundleIdentifier: nil,
        applicationName: nil,
        role: nil,
        subrole: nil,
        fieldType: .unknown,
        operation: .insert,
        selectedRange: nil,
        value: nil,
        isSecureTextField: false,
        isEditable: false
    )
    private var protectedTerms: [ProtectedTerm] = []
    @Published private(set) var appIdentity = AppIdentitySnapshot.placeholder

    var apiKeyPlaceholder: String {
        container.settingsStore.loadAPIKey().map { _ in "••••••••" } ?? ""
    }

    var microphoneStatusText: String {
        "Status: \(microphonePermissionStatus.rawValue)"
    }

    var accessibilityStatusText: String {
        "Status: \(accessibilityPermissionStatus.rawValue)"
    }

    var microphoneStatusDetailText: String {
        container.permissionManager.microphoneStatusDetail
    }

    var accessibilityStatusDetailText: String {
        container.permissionManager.accessibilityStatusDetail
    }

    var appIdentityText: String {
        appIdentity.summary
    }

    var appBundleText: String {
        "\(appIdentity.bundleIdentifier) · \(appIdentity.bundlePath)"
    }

    var currentFocusedAppIdentifier: String? {
        focusedElementContext.bundleIdentifier
    }

    var currentFocusedFieldType: FieldType {
        focusedElementContext.fieldType
    }

    var realtimeConnectionStatusText: String {
        "\(realtimeConnectionStatus.title): \(realtimeConnectionStatus.detail)"
    }

    var lastInsertionStrategy: InsertionStrategy?
    var protectedTermsSummary: String { protectedTerms.map(\.value).joined(separator: ", ") }
    var lastRewriteTiming = "N/A"

    init(container: DependencyContainer) {
        self.container = container
        self.settings = container.settingsStore.settings
        self.vocabularyEntries = container.vocabularyService.entries
        self.diagnostics = container.diagnosticStore.entries
        self.historyEntries = container.historyStore.entries
        self.microphonePermissionStatus = container.permissionManager.microphoneStatus
        self.accessibilityPermissionStatus = container.permissionManager.accessibilityStatus
        super.init()
        hotkeyManager.delegate = self
        audioCaptureManager.delegate = self
    }

    func start() {
        bindStores()
        hotkeyManager.register(hotkey: settings.hotkey)
        Task { [weak self] in
            let identity = await Task.detached(priority: .utility) {
                AppIdentityInspector.current()
            }.value
            self?.appIdentity = identity
        }
        menuBarController.onToggleDictation = { [weak self] in
            self?.toggleDictation()
        }
        menuBarController.onOpenSettings = { [weak self] destination in
            self?.openSettings(destination: destination)
        }
        menuBarController.onQuit = {
            NSApplication.shared.terminate(nil)
        }
        refreshMenuAndHUD()

        Task {
            await stateMachine.forceTransition(to: .ready)
            await refreshLifecycleState()
        }
    }

    func stop() {
        hotkeyManager.unregister()
        Task { @MainActor in
            await self.transcriptionService?.stop()
        }
    }

    func toggleDictation() {
        if settings.hotkeyMode == .toggle {
            isDictationActive ? stopDictation() : startDictation()
        } else {
            if isDictationActive {
                stopDictation()
            } else {
                startDictation()
            }
        }
    }

    func updateHotkey(_ hotkey: HotkeyDescriptor) {
        container.settingsStore.update { $0.hotkey = hotkey }
        hotkeyManager.register(hotkey: hotkey)
    }

    func updateHotkeyMode(_ mode: HotkeyMode) {
        container.settingsStore.update { $0.hotkeyMode = mode }
    }

    func updateLanguageMode(_ mode: LanguageMode) {
        container.settingsStore.update { $0.languageMode = mode }
    }

    func updateProfile(_ profile: DictationProfile) {
        container.settingsStore.update { $0.defaultProfile = profile }
    }

    func updateRewriteAggressiveness(_ aggressiveness: RewriteAggressiveness) {
        container.settingsStore.update { $0.rewriteAggressiveness = aggressiveness }
    }

    func updateInsertionCadence(_ cadence: InsertionCadence) {
        container.settingsStore.update { $0.insertionCadence = cadence }
    }

    func updateFallbackToRawTranscript(_ enabled: Bool) {
        container.settingsStore.update { $0.fallbackToRawTranscript = enabled }
    }

    func updateSaveHistory(_ enabled: Bool) {
        container.settingsStore.update { $0.saveTranscriptHistory = enabled }
    }

    func updateDebugLogging(_ enabled: Bool) {
        container.settingsStore.update { $0.debugLoggingEnabled = enabled }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try container.launchAtLoginManager.setEnabled(enabled)
            container.settingsStore.update { $0.launchAtLoginEnabled = enabled }
        } catch {
            handle(error: .providerConfiguration(error.localizedDescription))
        }
    }

    func addAppRule(_ rule: AppRule) {
        container.settingsStore.update { $0.appRules.append(rule) }
    }

    func saveAppRule(_ rule: AppRule) {
        container.settingsStore.update { settings in
            if let index = settings.appRules.firstIndex(where: { $0.id == rule.id }) {
                settings.appRules[index] = rule
            } else {
                settings.appRules.append(rule)
            }
        }
    }

    func deleteAppRule(at offsets: IndexSet) {
        container.settingsStore.update { settings in
            settings.appRules.remove(atOffsets: offsets)
        }
    }

    func deleteAppRule(id: AppRule.ID) {
        container.settingsStore.update { settings in
            settings.appRules.removeAll { $0.id == id }
        }
    }

    func updateProviderProfile(_ profile: ProviderProfile) {
        container.settingsStore.update {
            $0.provider.profile = profile
            switch profile {
            case .openAI:
                $0.provider.baseURL = "https://api.openai.com"
                $0.provider.capabilities = .openAI
            case .customCompatible:
                $0.provider.capabilities = .compatible
            case .mock:
                $0.provider.capabilities = .mock
            }
        }
    }

    func updateProviderBaseURL(_ value: String) {
        container.settingsStore.update { $0.provider.baseURL = value.trimmed }
    }

    func updateTranscriptionModel(_ value: String) {
        container.settingsStore.update { $0.provider.transcriptionModel = value.trimmed }
    }

    func updateRewriteModel(_ value: String) {
        container.settingsStore.update { $0.provider.rewriteModel = value.trimmed }
    }

    func updateSessionTokenEndpoint(_ value: String) {
        container.settingsStore.update { $0.provider.sessionTokenEndpoint = value.trimmed }
    }

    func updateProviderCapabilities(_ mutate: (inout ProviderCapabilities) -> Void) {
        container.settingsStore.update { settings in
            mutate(&settings.provider.capabilities)
        }
    }

    func saveAPIKey(_ key: String) {
        guard settings.provider.profile != .mock else { return }
        do {
            try container.settingsStore.saveAPIKey(key)
            providerTestMessage = "API key saved."
        } catch let error as DictationError {
            handle(error: error)
        } catch {
            handle(error: .providerConfiguration(error.localizedDescription))
        }
    }

    func testProviderConnection() {
        providerTestMessage = "Testing..."
        Task {
            do {
                let result = try await container.providerConnectionTester.test(provider: settings.provider, apiKey: container.settingsStore.loadAPIKey())
                await MainActor.run {
                    self.providerTestMessage = result
                }
            } catch let error as DictationError {
                await MainActor.run {
                    self.handle(error: error)
                }
            } catch {
                await MainActor.run {
                    self.handle(error: .network(error.localizedDescription))
                }
            }
        }
    }

    func requestMicrophonePermission() {
        Task {
            let granted = await container.permissionManager.requestMicrophonePermission()
            if !granted {
                handle(error: .missingMicrophonePermission)
            }
        }
    }

    func requestAccessibilityPermission() {
        let granted = container.permissionManager.requestAccessibilityPermission()
        if !granted {
            handle(error: .missingAccessibilityPermission)
        }
    }

    func refreshPermissionStatus() {
        container.permissionManager.refresh()
        // Sync immediately; the Combine pipeline (.receive(on: .main)) delivers asynchronously,
        // so callers that read these right after refresh() would see stale values.
        microphonePermissionStatus = container.permissionManager.microphoneStatus
        accessibilityPermissionStatus = container.permissionManager.accessibilityStatus
        refreshMenuAndHUD()
    }

    func openSystemSettings(for permission: PermissionManager.PermissionKind) {
        container.permissionManager.openSystemSettings(for: permission)
    }

    func saveVocabularyEntry(_ entry: VocabularyEntry) {
        container.vocabularyService.upsert(entry)
    }

    func toggleVocabularyEntry(_ entry: VocabularyEntry, enabled: Bool) {
        var updated = entry
        updated.enabled = enabled
        updated.updatedAt = .now
        container.vocabularyService.upsert(updated)
    }

    func deleteVocabularyEntries(ids: Set<VocabularyEntry.ID>) {
        ids.compactMap { id in container.vocabularyService.entries.first(where: { $0.id == id }) }
            .forEach(container.vocabularyService.delete)
    }

    func previewVocabularyNormalization(_ input: String) -> String {
        container.transcriptNormalizer.preview(text: input, entries: container.vocabularyService.snapshot(), languageMode: settings.languageMode)
    }

    func importVocabularyPreview(completion: @escaping (VocabularyImportPreview) -> Void) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json, .commaSeparatedText]
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                let preview = try self.container.vocabularyService.importPreview(from: url)
                completion(preview)
            } catch {
                self.handle(error: .providerConfiguration("Vocabulary import failed: \(error.localizedDescription)"))
            }
        }
    }

    func applyVocabularyImportPreview(_ preview: VocabularyImportPreview) {
        container.vocabularyService.apply(preview: preview)
    }

    func exportVocabularyJSON() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "vocabulary.json"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try self.container.vocabularyService.exportJSON(to: url)
            } catch {
                self.handle(error: .providerConfiguration("Vocabulary export failed: \(error.localizedDescription)"))
            }
        }
    }

    func exportVocabularyCSV() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "vocabulary.csv"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try self.container.vocabularyService.exportCSV(to: url)
            } catch {
                self.handle(error: .providerConfiguration("Vocabulary export failed: \(error.localizedDescription)"))
            }
        }
    }

    func clearHistory() {
        container.historyStore.clear()
    }

    func clearDiagnostics() {
        container.diagnosticStore.clear()
    }

    func openSettings(destination: MenuBarController.SettingsDestination) {
        switch destination {
        case .general:
            selectedSettingsTab = .general
        case .vocabulary:
            selectedSettingsTab = .vocabulary
        case .permissions:
            selectedSettingsTab = .permissions
        case .provider:
            selectedSettingsTab = .provider
        case .debug:
            selectedSettingsTab = .debug
        }
        settingsWindowController.show(for: self)
    }

    private func startDictation() {
        Task {
            do {
                try await ensurePermissions()
                try await stateMachine.transition(to: DictationLifecycleState(stage: .recording, detail: "Listening"))
                await refreshLifecycleState()

                transcriptAssembler.reset()
                stagedSegments.removeAll()
                pendingSegmentWorkCount = 0
                protectedTerms.removeAll()
                realtimeConnectionStatus = .connecting
                focusedElementContext = container.focusedElementInspector.inspectFocusedElement()
                isDictationActive = true
                refreshMenuAndHUD()

                let prompt = buildTranscriptionPrompt()
                let config = RealtimeTranscriptionConfiguration(
                    provider: settings.provider,
                    languageMode: settings.languageMode,
                    prompt: prompt,
                    useServerVAD: settings.hotkeyMode == .toggle
                )
                let transcriptionService = container.transcriptionServiceFactory.make(for: settings.provider)
                transcriptionService.delegate = self
                self.transcriptionService = transcriptionService
                activeRewriteService = container.rewriteServiceFactory.make(for: settings.provider)
                try await transcriptionService.start(configuration: config)
                try audioCaptureManager.start()
            } catch let error as DictationError {
                handle(error: error)
            } catch {
                handle(error: .network(error.localizedDescription))
            }
        }
    }

    private func stopDictation() {
        pendingStopTask?.cancel()
        pendingStopTask = Task {
            audioCaptureManager.stop()
            do {
                try await transcriptionService?.commitCurrentBuffer()
            } catch {
                handle(error: .transcription(error.localizedDescription))
            }
            try? await Task.sleep(for: .milliseconds(600))
            await waitForPendingSegments(timeout: .seconds(2))
            if shouldStageInsertionUntilRelease {
                flushStagedSegmentsIfNeeded()
            }
            await transcriptionService?.stop()
            transcriptionService = nil
            isDictationActive = false
            realtimeConnectionStatus = .stopped
            try? await stateMachine.transition(to: .ready)
            await refreshLifecycleState()
            refreshMenuAndHUD()
            hudController.hide(after: .milliseconds(600))
        }
    }

    private func ensurePermissions() async throws {
        refreshPermissionStatus()

        switch microphonePermissionStatus {
        case .authorized:
            break
        case .notDetermined:
            try await stateMachine.transition(to: DictationLifecycleState(stage: .requestingPermissions, detail: "Microphone permission"))
            await refreshLifecycleState()
            if await container.permissionManager.requestMicrophonePermission() == false {
                throw DictationError.missingMicrophonePermission
            }
        case .denied:
            openSettings(destination: .permissions)
            throw DictationError.missingMicrophonePermission
        }

        switch accessibilityPermissionStatus {
        case .authorized:
            break
        case .notDetermined:
            try await stateMachine.transition(to: DictationLifecycleState(stage: .requestingPermissions, detail: "Accessibility permission"))
            await refreshLifecycleState()
            if !container.permissionManager.requestAccessibilityPermission() {
                throw DictationError.missingAccessibilityPermission
            }
        case .denied:
            openSettings(destination: .permissions)
            container.permissionManager.openSystemSettings(for: .accessibility)
            throw DictationError.missingAccessibilityPermission
        }
    }

    private func buildTranscriptionPrompt() -> String {
        let entries = container.vocabularyService.snapshot()
            .filter(\.enabled)
            .prefix(12)
        guard !entries.isEmpty else { return "Transcribe faithfully. Preserve technical terms and casing." }
        let hints = entries.map { "\($0.writtenForm): \($0.spokenForms.joined(separator: ", "))" }.joined(separator: "; ")
        return "Transcribe faithfully. Preserve technical terms and casing. Preferred vocabulary: \(hints)"
    }

    private func processFinalizedSegment(_ segment: TranscriptSegment) {
        pendingSegmentWorkCount += 1
        Task {
            defer { pendingSegmentWorkCount = max(0, pendingSegmentWorkCount - 1) }
            do {
                try await stateMachine.transition(to: DictationLifecycleState(stage: .segmentFinalizing, detail: segment.rawText))
                await refreshLifecycleState()

                try await stateMachine.transition(to: DictationLifecycleState(stage: .normalizingVocabulary, detail: segment.id))
                await refreshLifecycleState()

                var normalized = container.transcriptNormalizer.normalize(
                    transcript: segment.rawText,
                    entries: container.vocabularyService.snapshot(),
                    languageMode: settings.languageMode
                )
                let appContext = container.appContextClassifier.resolve(
                    bundleIdentifier: focusedElementContext.bundleIdentifier,
                    focusedElement: focusedElementContext,
                    settings: settings
                )
                let technicalTerms = container.transcriptNormalizer.technicalProtectedTerms(
                    in: normalized.text,
                    profile: appContext.profile,
                    appCategory: appContext.category
                )
                if !technicalTerms.isEmpty {
                    let mergedTerms = Set(normalized.protectedTerms).union(technicalTerms)
                    normalized.protectedTerms = mergedTerms.sorted { $0.value < $1.value }
                    normalized.decisions.append("Protected technical tokens: \(technicalTerms.map(\.value).joined(separator: ", "))")
                }

                protectedTerms = normalized.protectedTerms
                container.diagnosticStore.record(subsystem: "normalizer", message: normalized.decisions.joined(separator: " | "))

                let context = RewriteContext(
                    appCategory: appContext.category,
                    fieldType: focusedElementContext.fieldType,
                    operation: focusedElementContext.operation,
                    aggressiveness: appContext.aggressiveness,
                    languageMode: settings.languageMode,
                    profile: appContext.profile,
                    protectedTerms: normalized.protectedTerms,
                    recentContext: recentRewriteContext(for: appContext.category, currentSegment: segment)
                )

                let finalText: String
                if appContext.disableRewrite || appContext.profile == .raw || shouldBypassRewrite(for: segment, normalized: normalized, profile: appContext.profile, appCategory: appContext.category) {
                    finalText = normalized.text
                } else {
                    try await stateMachine.transition(to: DictationLifecycleState(stage: .rewriting, detail: normalized.text))
                    await refreshLifecycleState()
                    let started = Date()
                    do {
                        let result = try await activeRewriteService?.rewrite(
                            transcript: normalized.text,
                            context: context,
                            provider: settings.provider,
                            apiKey: container.settingsStore.loadAPIKey()
                        )
                        let elapsed = Date().timeIntervalSince(started)
                        lastRewriteTiming = String(format: "%.2fs", elapsed)
                        let rewritten = result?.text ?? normalized.text
                        finalText = validateProtectedTerms(rewritten, normalized: normalized) ? rewritten : normalized.text
                    } catch {
                        if settings.fallbackToRawTranscript {
                            finalText = normalized.text
                        } else {
                            throw DictationError.rewrite(error.localizedDescription)
                        }
                    }
                }

                guard !finalText.trimmed.isEmpty else {
                    try await stateMachine.transition(to: .ready)
                    await refreshLifecycleState()
                    return
                }

                if shouldStageInsertionUntilRelease {
                    stageSegmentForRelease(segmentID: segment.id, rawText: segment.rawText, finalText: finalText)
                } else {
                    try insertTextNow(finalText, rawText: segment.rawText, segmentIDs: [segment.id])
                }

                if isDictationActive {
                    try await stateMachine.transition(to: DictationLifecycleState(stage: .recording, detail: "Listening"))
                } else {
                    try await stateMachine.transition(to: .ready)
                }
                await refreshLifecycleState()
                refreshMenuAndHUD()
            } catch let error as DictationError {
                handle(error: error)
            } catch {
                handle(error: .insertion(error.localizedDescription))
            }
        }
    }

    private func handleCapturedPCMChunk(_ data: Data) {
        Task {
            do {
                try await transcriptionService?.appendAudio(data)
            } catch {
                handle(error: .transcription(error.localizedDescription))
            }
        }
    }

    private func handleVoiceActivityUpdate(_ event: VoiceActivityEvent) {
        if settings.hotkeyMode == .pushToTalk, case .boundary = event {
            Task {
                try? await transcriptionService?.commitCurrentBuffer()
            }
        }
    }

    private func shouldBypassRewrite(
        for segment: TranscriptSegment,
        normalized: NormalizedTranscript,
        profile: DictationProfile,
        appCategory: AppCategory
    ) -> Bool {
        if segment.averageLogProbability ?? 0 < -1.25 {
            return true
        }
        return container.transcriptNormalizer.suggestsLiteralRewriteBypass(
            text: normalized.text,
            protectedTerms: normalized.protectedTerms,
            profile: profile,
            appCategory: appCategory
        )
    }

    private func validateProtectedTerms(_ rewritten: String, normalized: NormalizedTranscript) -> Bool {
        for term in normalized.protectedTerms where normalized.text.contains(term.value) {
            if rewritten.contains(term.value) == false {
                return false
            }
        }
        return true
    }

    private func recentRewriteContext(for category: AppCategory, currentSegment: TranscriptSegment) -> String? {
        let shouldIncludeRecentContext = focusedElementContext.fieldType == .multiLine || category == .email || category == .notes || category == .document
        guard shouldIncludeRecentContext else { return nil }

        let recentRawContext = transcriptAssembler.recentContext(limit: 2)
        guard !recentRawContext.trimmed.isEmpty, recentRawContext.trimmed != currentSegment.rawText.trimmed else {
            return nil
        }

        let normalizedRecentContext = container.transcriptNormalizer.preview(
            text: recentRawContext,
            entries: container.vocabularyService.snapshot(),
            languageMode: settings.languageMode
        )
        return normalizedRecentContext.trimmed.isEmpty ? nil : normalizedRecentContext
    }

    private func bindStores() {
        container.settingsStore.$settings
            .receive(on: DispatchQueue.main)
            .sink { [weak self] settings in
                self?.settings = settings
                self?.refreshMenuAndHUD()
            }
            .store(in: &cancellables)

        container.vocabularyService.$entries
            .receive(on: DispatchQueue.main)
            .sink { [weak self] entries in
                self?.vocabularyEntries = entries
            }
            .store(in: &cancellables)

        container.diagnosticStore.$entries
            .receive(on: DispatchQueue.main)
            .sink { [weak self] entries in
                self?.diagnostics = entries
            }
            .store(in: &cancellables)

        container.historyStore.$entries
            .receive(on: DispatchQueue.main)
            .sink { [weak self] entries in
                self?.historyEntries = entries
            }
            .store(in: &cancellables)

        container.permissionManager.$microphoneStatus
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                self?.microphonePermissionStatus = status
            }
            .store(in: &cancellables)

        container.permissionManager.$accessibilityStatus
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                self?.accessibilityPermissionStatus = status
            }
            .store(in: &cancellables)
    }

    private func refreshMenuAndHUD() {
        let status = formattedMenuStatus()
        menuBarController.update(status: status, isRecording: isDictationActive, recentError: diagnostics.first?.message)
        if isDictationActive {
            let shouldHighlightRealtimeStatus = realtimeConnectionStatus.shouldAnnotateActiveSession
            let hudState = shouldHighlightRealtimeStatus ? realtimeConnectionStatus.title : lifecycleState.stage.displayName
            let hudDetail = shouldHighlightRealtimeStatus ? realtimeConnectionStatus.detail : (lifecycleState.detail ?? realtimeConnectionStatus.detail)
            hudController.show(state: hudState, detail: hudDetail)
        }
    }

    private func refreshLifecycleState() async {
        lifecycleState = await stateMachine.state
        refreshMenuAndHUD()
    }

    private func handle(error: DictationError) {
        Task {
            await stateMachine.forceTransition(to: DictationLifecycleState(stage: .error, detail: error.localizedDescription))
            await refreshLifecycleState()
        }
        isDictationActive = false
        realtimeConnectionStatus = .stopped
        container.diagnosticStore.record(subsystem: "error", message: error.localizedDescription)
        providerTestMessage = error.localizedDescription
        hudController.show(state: "Error", detail: error.localizedDescription, dismissible: true)
        hudController.hide(after: .seconds(4))
        if error == .missingMicrophonePermission || error == .missingAccessibilityPermission {
            openSettings(destination: .permissions)
        }
        refreshMenuAndHUD()
    }

    private func formattedMenuStatus() -> String {
        var parts: [String] = [lifecycleState.stage.displayName]
        if let detail = lifecycleState.detail, !detail.trimmed.isEmpty {
            parts[0] += ": \(detail)"
        }
        if isDictationActive, realtimeConnectionStatus.shouldAnnotateActiveSession {
            parts.append(realtimeConnectionStatus.title)
        }
        return parts.joined(separator: " · ")
    }

    private var shouldStageInsertionUntilRelease: Bool {
        settings.hotkeyMode == .pushToTalk && settings.insertionCadence == .stagedOnRelease
    }

    private func stageSegmentForRelease(segmentID: String, rawText: String, finalText: String) {
        guard stagedSegments.contains(where: { $0.id == segmentID }) == false else { return }
        stagedSegments.append(StagedInsertionSegment(id: segmentID, rawText: rawText, finalText: finalText))
        let preview = stagedSegments.map(\.finalText).suffix(2).joined(separator: " ")
        hudController.show(state: "Staged", detail: "Release hotkey to insert. \(preview)")
    }

    private func flushStagedSegmentsIfNeeded() {
        guard stagedSegments.isEmpty == false else { return }
        let refreshedContext = container.focusedElementInspector.inspectFocusedElement()
        focusedElementContext = refreshedContext
        let finalText = SegmentJoiner.join(stagedSegments.map(\.finalText))
        let rawText = SegmentJoiner.join(stagedSegments.map(\.rawText))
        do {
            try insertTextNow(finalText, rawText: rawText, segmentIDs: stagedSegments.map(\.id))
            stagedSegments.removeAll()
        } catch let error as DictationError {
            handle(error: error)
        } catch {
            handle(error: .insertion(error.localizedDescription))
        }
    }

    private func insertTextNow(_ finalText: String, rawText: String, segmentIDs: [String]) throws {
        guard !finalText.trimmed.isEmpty else { return }
        let focusedElement = container.focusedElementInspector.focusedElement()
        lastInsertionStrategy = nil
        let outcome = try container.textInsertionService.insert(text: finalText, context: focusedElementContext, focusedElement: focusedElement)
        lastInsertionStrategy = outcome.strategy
        segmentIDs.forEach(transcriptAssembler.markInserted(segmentID:))
        hudController.show(state: "Inserted", detail: finalText)
        container.historyStore.append(
            HistoryEntry(createdAt: .now, appName: focusedElementContext.applicationName ?? "Unknown", rawText: rawText, insertedText: finalText),
            enabled: settings.saveTranscriptHistory
        )
    }

    private func waitForPendingSegments(timeout: Duration) async {
        let started = ContinuousClock.now
        while pendingSegmentWorkCount > 0 {
            if ContinuousClock.now - started > timeout {
                break
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
    }
}

@MainActor
extension AppCoordinator: HotkeyManagerDelegate {
    func hotkeyManagerDidPress() {
        if settings.hotkeyMode == .pushToTalk {
            if !isDictationActive {
                startDictation()
            }
        } else if !isDictationActive {
            startDictation()
        }
    }

    func hotkeyManagerDidRelease() {
        if settings.hotkeyMode == .pushToTalk, isDictationActive {
            stopDictation()
        }
    }
}

extension AppCoordinator: AudioCaptureManagerDelegate {
    nonisolated func audioCaptureManagerDidCapturePCMChunk(_ data: Data) {
        Task { @MainActor in
            self.handleCapturedPCMChunk(data)
        }
    }

    nonisolated func audioCaptureManagerDidUpdateVoiceActivity(_ event: VoiceActivityEvent) {
        Task { @MainActor in
            self.handleVoiceActivityUpdate(event)
        }
    }
}

@MainActor
extension AppCoordinator: RealtimeTranscriptionServiceDelegate {
    func transcriptionService(_ service: RealtimeTranscriptionServiceProtocol, didReceive event: TranscriptionEvent) {
        let update = transcriptAssembler.apply(event)
        switch event {
        case let .connectionStatus(status):
            realtimeConnectionStatus = status
            refreshMenuAndHUD()
        case let .failed(_, message):
            realtimeConnectionStatus = .stopped
            handle(error: .transcription(message))
        case .sessionCreated:
            if case .connecting = realtimeConnectionStatus {
                realtimeConnectionStatus = .connected(resumedAfterReconnect: false)
            }
        default:
            break
        }

        if let partial = update.partialText, !partial.trimmed.isEmpty {
            Task {
                try? await stateMachine.transition(to: DictationLifecycleState(stage: .receivingPartialTranscript, detail: partial))
                await refreshLifecycleState()
            }
        }

        if let segment = update.finalizedSegment {
            processFinalizedSegment(segment)
        }
    }
}
