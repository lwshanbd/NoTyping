import Foundation

struct DependencyContainer {
    var settingsStore: SettingsStore
    var keychainStore: KeychainStore
    var permissionManager: PermissionManager
    var vocabularyService: VocabularyService
    var transcriptNormalizer: TranscriptNormalizer
    var appContextClassifier: AppContextClassifier
    var focusedElementInspector: FocusedElementInspector
    var textInsertionService: TextInsertionServiceProtocol
    var rewriteServiceFactory: RewriteServiceFactory
    var transcriptionServiceFactory: RealtimeTranscriptionServiceFactory
    var historyStore: HistoryStore
    var diagnosticStore: DiagnosticStore
    var launchAtLoginManager: LaunchAtLoginManager
    var providerConnectionTester: ProviderConnectionTesting

    @MainActor
    static func live() -> DependencyContainer {
        let keychainStore = KeychainStore()
        let settingsStore = SettingsStore(keychainStore: keychainStore)
        let diagnosticStore = DiagnosticStore(settingsStore: settingsStore)
        let vocabularyService = VocabularyService()

        return DependencyContainer(
            settingsStore: settingsStore,
            keychainStore: keychainStore,
            permissionManager: PermissionManager(),
            vocabularyService: vocabularyService,
            transcriptNormalizer: TranscriptNormalizer(),
            appContextClassifier: AppContextClassifier(),
            focusedElementInspector: FocusedElementInspector(),
            textInsertionService: TextInsertionService(diagnosticStore: diagnosticStore),
            rewriteServiceFactory: RewriteServiceFactory(keychainStore: keychainStore, diagnosticStore: diagnosticStore),
            transcriptionServiceFactory: RealtimeTranscriptionServiceFactory(keychainStore: keychainStore, diagnosticStore: diagnosticStore),
            historyStore: HistoryStore(),
            diagnosticStore: diagnosticStore,
            launchAtLoginManager: LaunchAtLoginManager(),
            providerConnectionTester: ProviderConnectionTester(keychainStore: keychainStore)
        )
    }
}
