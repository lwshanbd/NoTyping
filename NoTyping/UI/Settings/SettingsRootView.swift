import SwiftUI

enum SettingsTab: String, CaseIterable, Identifiable {
    case general
    case dictation
    case provider
    case vocabulary
    case privacy
    case permissions
    case debug

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general:
            "General"
        case .dictation:
            "Dictation"
        case .provider:
            "Provider"
        case .vocabulary:
            "Vocabulary"
        case .privacy:
            "Privacy"
        case .permissions:
            "Permissions"
        case .debug:
            "Debug"
        }
    }
}

struct SettingsRootView: View {
    @EnvironmentObject private var coordinator: AppCoordinator

    var body: some View {
        TabView(selection: $coordinator.selectedSettingsTab) {
            GeneralSettingsView()
                .tabItem { Text("General") }
                .tag(SettingsTab.general)

            DictationSettingsView()
                .tabItem { Text("Dictation") }
                .tag(SettingsTab.dictation)

            ProviderSettingsView()
                .tabItem { Text("Provider") }
                .tag(SettingsTab.provider)

            VocabularyManagementView()
                .tabItem { Text("Vocabulary") }
                .tag(SettingsTab.vocabulary)

            PrivacySettingsView()
                .tabItem { Text("Privacy") }
                .tag(SettingsTab.privacy)

            PermissionsSettingsView()
                .tabItem { Text("Permissions") }
                .tag(SettingsTab.permissions)

            DebugSettingsView()
                .tabItem { Text("Debug") }
                .tag(SettingsTab.debug)
        }
        .padding(20)
    }
}

private struct GeneralSettingsView: View {
    @EnvironmentObject private var coordinator: AppCoordinator

    var body: some View {
        Form {
            Section("Hotkey") {
                HotkeyRecorderField(hotkey: Binding(
                    get: { coordinator.settings.hotkey },
                    set: { coordinator.updateHotkey($0) }
                ))
                .frame(width: 180, height: 28)

                Picker("Hotkey mode", selection: Binding(
                    get: { coordinator.settings.hotkeyMode },
                    set: { coordinator.updateHotkeyMode($0) }
                )) {
                    ForEach(HotkeyMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }

                Toggle("Launch at login", isOn: Binding(
                    get: { coordinator.settings.launchAtLoginEnabled },
                    set: { coordinator.setLaunchAtLogin($0) }
                ))
            }

            Section("Defaults") {
                Picker("Language mode", selection: Binding(
                    get: { coordinator.settings.languageMode },
                    set: { coordinator.updateLanguageMode($0) }
                )) {
                    ForEach(LanguageMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }

                Picker("Profile", selection: Binding(
                    get: { coordinator.settings.defaultProfile },
                    set: { coordinator.updateProfile($0) }
                )) {
                    ForEach(DictationProfile.allCases) { profile in
                        Text(profile.displayName).tag(profile)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct DictationSettingsView: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @State private var editingRule: AppRule?

    var body: some View {
        Form {
            Section("Rewrite") {
                Picker("Aggressiveness", selection: Binding(
                    get: { coordinator.settings.rewriteAggressiveness },
                    set: { coordinator.updateRewriteAggressiveness($0) }
                )) {
                    ForEach(RewriteAggressiveness.allCases) { value in
                        Text(value.rawValue.capitalized).tag(value)
                    }
                }

                Picker("Insertion cadence", selection: Binding(
                    get: { coordinator.settings.insertionCadence },
                    set: { coordinator.updateInsertionCadence($0) }
                )) {
                    Text("Staged on hotkey release").tag(InsertionCadence.stagedOnRelease)
                    Text("Live per finalized segment").tag(InsertionCadence.livePerSegment)
                }

                Toggle("Fallback to normalized raw transcript if rewrite fails", isOn: Binding(
                    get: { coordinator.settings.fallbackToRawTranscript },
                    set: { coordinator.updateFallbackToRawTranscript($0) }
                ))
            }

            Section("App-specific rules") {
                if coordinator.settings.appRules.isEmpty {
                    Text("No app-specific rules yet. Add one to override category, rewrite mode, or aggressiveness for a specific app.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(coordinator.settings.appRules) { rule in
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(rule.bundleIdentifierPattern)
                                Text(appRuleSummary(rule))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Edit") {
                                editingRule = rule
                            }
                            Button("Delete", role: .destructive) {
                                coordinator.deleteAppRule(id: rule.id)
                            }
                        }
                    }
                }

                Button("New Rule") {
                    var rule = AppRule.sample
                    rule.id = UUID()
                    rule.bundleIdentifierPattern = ""
                    editingRule = rule
                }
            }
        }
        .formStyle(.grouped)
        .sheet(item: $editingRule) { rule in
            AppRuleEditorSheet(rule: rule) { updated in
                coordinator.saveAppRule(updated)
                editingRule = nil
            }
        }
    }

    private func appRuleSummary(_ rule: AppRule) -> String {
        let profile = rule.preferredProfile?.displayName ?? "Automatic profile"
        let aggressiveness = rule.aggressivenessOverride?.rawValue.capitalized ?? "Default aggressiveness"
        let rewrite = rule.disableRewrite ? "Rewrite disabled" : "Rewrite enabled"
        return "\(rule.category.rawValue) · \(profile) · \(aggressiveness) · \(rewrite)"
    }
}

private struct AppRuleEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var rule: AppRule
    @State private var overrideProfile: Bool
    @State private var overrideAggressiveness: Bool
    let onSave: (AppRule) -> Void

    init(rule: AppRule, onSave: @escaping (AppRule) -> Void) {
        _rule = State(initialValue: rule)
        _overrideProfile = State(initialValue: rule.preferredProfile != nil)
        _overrideAggressiveness = State(initialValue: rule.aggressivenessOverride != nil)
        self.onSave = onSave
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Bundle identifier pattern", text: $rule.bundleIdentifierPattern)

            Picker("Category", selection: $rule.category) {
                ForEach(AppCategory.allCases) { category in
                    Text(category.rawValue).tag(category)
                }
            }

            Toggle("Override profile", isOn: $overrideProfile)
            if overrideProfile {
                Picker("Preferred profile", selection: Binding(
                    get: { rule.preferredProfile ?? .smart },
                    set: { rule.preferredProfile = $0 }
                )) {
                    ForEach(DictationProfile.allCases) { profile in
                        Text(profile.displayName).tag(profile)
                    }
                }
            }

            Toggle("Override aggressiveness", isOn: $overrideAggressiveness)
            if overrideAggressiveness {
                Picker("Aggressiveness", selection: Binding(
                    get: { rule.aggressivenessOverride ?? .medium },
                    set: { rule.aggressivenessOverride = $0 }
                )) {
                    ForEach(RewriteAggressiveness.allCases) { aggressiveness in
                        Text(aggressiveness.rawValue.capitalized).tag(aggressiveness)
                    }
                }
            }

            Toggle("Disable rewrite and insert normalized raw transcript", isOn: $rule.disableRewrite)

            Text("Rules match the frontmost app bundle identifier. Examples: `com.apple.dt.Xcode`, `com.microsoft.VSCode`, `com.apple.mail`.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") {
                    rule.bundleIdentifierPattern = rule.bundleIdentifierPattern.trimmed
                    rule.preferredProfile = overrideProfile ? (rule.preferredProfile ?? .smart) : nil
                    rule.aggressivenessOverride = overrideAggressiveness ? (rule.aggressivenessOverride ?? .medium) : nil
                    onSave(rule)
                    dismiss()
                }
                .disabled(rule.bundleIdentifierPattern.trimmed.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 460)
        .onChange(of: overrideProfile) { _, enabled in
            if !enabled {
                rule.preferredProfile = nil
            } else if rule.preferredProfile == nil {
                rule.preferredProfile = .smart
            }
        }
        .onChange(of: overrideAggressiveness) { _, enabled in
            if !enabled {
                rule.aggressivenessOverride = nil
            } else if rule.aggressivenessOverride == nil {
                rule.aggressivenessOverride = .medium
            }
        }
    }
}

private struct ProviderSettingsView: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @State private var draftAPIKey = ""

    var body: some View {
        Form {
            Section("Provider") {
                Picker("Profile", selection: Binding(
                    get: { coordinator.settings.provider.profile },
                    set: { coordinator.updateProviderProfile($0) }
                )) {
                    ForEach(ProviderProfile.allCases) { profile in
                        Text(profile.displayName).tag(profile)
                    }
                }

                TextField("Base URL", text: Binding(
                    get: { coordinator.settings.provider.baseURL },
                    set: { coordinator.updateProviderBaseURL($0) }
                ))
                .disabled(coordinator.settings.provider.profile == .mock)

                TextField("Transcription model", text: Binding(
                    get: { coordinator.settings.provider.transcriptionModel },
                    set: { coordinator.updateTranscriptionModel($0) }
                ))
                .disabled(coordinator.settings.provider.profile == .mock)

                TextField("Rewrite model", text: Binding(
                    get: { coordinator.settings.provider.rewriteModel },
                    set: { coordinator.updateRewriteModel($0) }
                ))
                .disabled(coordinator.settings.provider.profile == .mock)

                TextField("Realtime session token endpoint (optional)", text: Binding(
                    get: { coordinator.settings.provider.sessionTokenEndpoint },
                    set: { coordinator.updateSessionTokenEndpoint($0) }
                ))
                .disabled(coordinator.settings.provider.profile == .mock)

                SecureField("API key", text: $draftAPIKey)
                    .onAppear {
                        draftAPIKey = coordinator.apiKeyPlaceholder
                    }

                HStack {
                    Button("Save API Key") {
                        coordinator.saveAPIKey(draftAPIKey)
                    }
                    .disabled(coordinator.settings.provider.profile == .mock)

                    Button("Test Connection") {
                        coordinator.testProviderConnection()
                    }

                    if let providerTestMessage = coordinator.providerTestMessage {
                        Text(providerTestMessage)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Capabilities") {
                Toggle("Realtime transcription", isOn: Binding(
                    get: { coordinator.settings.provider.capabilities.supportsRealtimeTranscription },
                    set: { enabled in
                        coordinator.updateProviderCapabilities { capabilities in
                            capabilities.supportsRealtimeTranscription = enabled
                        }
                    }
                ))
                Toggle("Session token endpoint supported", isOn: Binding(
                    get: { coordinator.settings.provider.capabilities.supportsTranscriptionClientSecrets },
                    set: { enabled in
                        coordinator.updateProviderCapabilities { capabilities in
                            capabilities.supportsTranscriptionClientSecrets = enabled
                        }
                    }
                ))
                Toggle("Responses rewrite", isOn: Binding(
                    get: { coordinator.settings.provider.capabilities.supportsResponsesRewrite },
                    set: { enabled in
                        coordinator.updateProviderCapabilities { capabilities in
                            capabilities.supportsResponsesRewrite = enabled
                        }
                    }
                ))
                Toggle("Transcription prompt hints", isOn: Binding(
                    get: { coordinator.settings.provider.capabilities.supportsTranscriptionPromptHints },
                    set: { enabled in
                        coordinator.updateProviderCapabilities { capabilities in
                            capabilities.supportsTranscriptionPromptHints = enabled
                        }
                    }
                ))
            }
        }
        .formStyle(.grouped)
    }
}

private struct VocabularyManagementView: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @State private var search = ""
    @State private var selected: VocabularyEntry?
    @State private var previewInput = "nccl and pytorch"
    @State private var importPreview: VocabularyImportPreview?

    private var filteredEntries: [VocabularyEntry] {
        let entries = coordinator.vocabularyEntries
        guard !search.trimmed.isEmpty else { return entries }
        return entries.filter { $0.searchableText.contains(search.lowercased()) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                TextField("Search vocabulary", text: $search)
                Button("New Entry") {
                    selected = VocabularyEntry(writtenForm: "", spokenForms: [], languageScope: .both)
                }
                Button("Import") {
                    coordinator.importVocabularyPreview { preview in
                        importPreview = preview
                    }
                }
                Button("Export JSON") {
                    coordinator.exportVocabularyJSON()
                }
                Button("Export CSV") {
                    coordinator.exportVocabularyCSV()
                }
            }

            Table(filteredEntries) {
                TableColumn("Enabled") { entry in
                    Toggle("", isOn: Binding(
                        get: { entry.enabled },
                        set: { coordinator.toggleVocabularyEntry(entry, enabled: $0) }
                    ))
                }
                TableColumn("Written Form", value: \.writtenForm)
                TableColumn("Spoken Forms") { entry in
                    Text(entry.spokenForms.joined(separator: ", "))
                }
                TableColumn("Scope") { entry in
                    Text(entry.languageScope.rawValue)
                }
            }
            .frame(minHeight: 260)
            .contextMenu(forSelectionType: VocabularyEntry.ID.self) { selectedIDs in
                Button("Edit") {
                    if let id = selectedIDs.first, let entry = coordinator.vocabularyEntries.first(where: { $0.id == id }) {
                        selected = entry
                    }
                }
                Button("Delete", role: .destructive) {
                    coordinator.deleteVocabularyEntries(ids: selectedIDs)
                }
            }

            GroupBox("Normalization Preview") {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("Spoken text preview", text: $previewInput)
                    Text(coordinator.previewVocabularyNormalization(previewInput))
                        .textSelection(.enabled)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .sheet(item: $selected) { entry in
            VocabularyEditorSheet(entry: entry) { updated in
                coordinator.saveVocabularyEntry(updated)
                selected = nil
            }
        }
        .sheet(isPresented: Binding(
            get: { importPreview != nil },
            set: { if !$0 { importPreview = nil } }
        )) {
            if let importPreview {
                VocabularyImportPreviewSheet(preview: importPreview) {
                    coordinator.applyVocabularyImportPreview(importPreview)
                    self.importPreview = nil
                }
            }
        }
    }
}

private struct VocabularyEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var entry: VocabularyEntry
    var onSave: (VocabularyEntry) -> Void

    init(entry: VocabularyEntry, onSave: @escaping (VocabularyEntry) -> Void) {
        _entry = State(initialValue: entry)
        self.onSave = onSave
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Written form", text: $entry.writtenForm)
            TextField("Spoken forms (comma separated)", text: Binding(
                get: { entry.spokenForms.joined(separator: ", ") },
                set: { entry.spokenForms = $0.split(separator: ",").map { String($0).trimmed } }
            ))
            Picker("Language scope", selection: $entry.languageScope) {
                ForEach(LanguageScope.allCases) { scope in
                    Text(scope.rawValue).tag(scope)
                }
            }
            Toggle("Enabled", isOn: $entry.enabled)
            Toggle("Case sensitive", isOn: $entry.caseSensitive)
            Stepper("Priority: \(entry.priority)", value: $entry.priority, in: 0...1000)
            TextField("Notes", text: $entry.notes)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") {
                    entry.updatedAt = .now
                    onSave(entry)
                    dismiss()
                }
                .disabled(entry.writtenForm.trimmed.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 420)
    }
}

private struct VocabularyImportPreviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    let preview: VocabularyImportPreview
    let onApply: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Import Preview")
                .font(.headline)
            List(preview.decisions) { decision in
                HStack {
                    Text(decision.entry.writtenForm)
                    Spacer()
                    Text(decision.action.rawValue)
                        .foregroundStyle(.secondary)
                }
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Apply") {
                    onApply()
                    dismiss()
                }
            }
        }
        .padding(20)
        .frame(width: 460, height: 360)
    }
}

private struct PrivacySettingsView: View {
    @EnvironmentObject private var coordinator: AppCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Form {
                Section("Privacy") {
                    Toggle("Save transcript history locally", isOn: Binding(
                        get: { coordinator.settings.saveTranscriptHistory },
                        set: { coordinator.updateSaveHistory($0) }
                    ))
                    Text("Settings and vocabulary stay local. Transcript history remains off by default. API requests send audio and rewrite prompts only to the configured provider.")
                        .foregroundStyle(.secondary)

                    Button("Clear History") {
                        coordinator.clearHistory()
                    }
                }
            }
            .formStyle(.grouped)

            GroupBox("Recent Local History") {
                if coordinator.historyEntries.isEmpty {
                    Text("No local transcript history has been saved.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    List(coordinator.historyEntries.prefix(12)) { entry in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(entry.insertedText)
                                .textSelection(.enabled)
                            Text("\(entry.appName) · \(entry.createdAt.formatted())")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(minHeight: 180)
                }
            }
        }
    }
}

private struct PermissionsSettingsView: View {
    @EnvironmentObject private var coordinator: AppCoordinator

    var body: some View {
        Form {
            Section("Current Build") {
                LabeledContent("Bundle") {
                    Text(coordinator.appBundleText)
                        .textSelection(.enabled)
                }
                LabeledContent("Signing") {
                    Text(coordinator.appIdentityText)
                        .textSelection(.enabled)
                }
                Text("macOS privacy permissions are tied to this signed app identity. If the signing certificate changes, System Settings can treat the rebuilt app as a different app.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Microphone") {
                Text(coordinator.microphoneStatusText)
                Text(coordinator.microphoneStatusDetailText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Button("Request Access") {
                        coordinator.requestMicrophonePermission()
                    }
                    Button("Refresh Status") {
                        coordinator.refreshPermissionStatus()
                    }
                    Button("Open System Settings") {
                        coordinator.openSystemSettings(for: .microphone)
                    }
                }
            }

            Section("Accessibility") {
                Text(coordinator.accessibilityStatusText)
                Text(coordinator.accessibilityStatusDetailText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Button("Prompt Again") {
                        coordinator.requestAccessibilityPermission()
                    }
                    Button("Refresh Status") {
                        coordinator.refreshPermissionStatus()
                    }
                    Button("Open System Settings") {
                        coordinator.openSystemSettings(for: .accessibility)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct DebugSettingsView: View {
    @EnvironmentObject private var coordinator: AppCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Persist debug log to disk", isOn: Binding(
                get: { coordinator.settings.debugLoggingEnabled },
                set: { coordinator.updateDebugLogging($0) }
            ))

            Text("Current state: \(coordinator.lifecycleState.stage.displayName)")
            Text("Realtime: \(coordinator.realtimeConnectionStatusText)")
            Text("Focused app: \(coordinator.currentFocusedAppIdentifier ?? "Unknown")")
            Text("Field type: \(coordinator.currentFocusedFieldType.rawValue)")
            Text("Insertion strategy: \(coordinator.lastInsertionStrategy?.rawValue ?? "None")")
            Text("Protected terms: \(coordinator.protectedTermsSummary)")
            Text("Last rewrite timing: \(coordinator.lastRewriteTiming)")

            List(coordinator.diagnostics) { entry in
                VStack(alignment: .leading, spacing: 4) {
                    Text("[\(entry.subsystem)] \(entry.message)")
                    Text(entry.timestamp.formatted())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                Button("Clear Diagnostics") {
                    coordinator.clearDiagnostics()
                }
                Spacer()
            }
        }
    }
}
