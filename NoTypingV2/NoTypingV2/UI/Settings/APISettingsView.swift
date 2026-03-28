import SwiftUI

struct APISettingsView: View {
    @EnvironmentObject private var settingsStore: SettingsStore

    @State private var sttAPIKey: String = ""
    @State private var llmAPIKey: String = ""
    @State private var sttTestStatus: TestStatus = .idle
    @State private var llmTestStatus: TestStatus = .idle

    private enum TestStatus: Equatable {
        case idle
        case testing
        case success
        case failure(String)
    }

    var body: some View {
        Form {
            Section {
                sttSection
            } header: {
                Text("Speech-to-Text")
            } footer: {
                if sttAPIKey.isEmpty {
                    Label("Enter your API key to get started", systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.blue)
                }
            }

            Section {
                llmSection
            } header: {
                Text("LLM Polish")
            } footer: {
                if llmAPIKey.isEmpty {
                    Label("Enter your API key to enable text polishing", systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.blue)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { loadKeys() }
        .onChange(of: settingsStore.settings) { _, _ in
            settingsStore.save()
        }
    }

    // MARK: - STT Section

    @ViewBuilder
    private var sttSection: some View {
        // Provider picker is locked to OpenAI for now
        LabeledContent("Provider") {
            Text(settingsStore.settings.sttConfig.provider.displayName)
                .foregroundStyle(.secondary)
        }

        SecureField("API Key", text: $sttAPIKey)
            .textFieldStyle(.roundedBorder)
            .onChange(of: sttAPIKey) { _, newValue in
                saveKey(newValue, account: settingsStore.settings.sttConfig.apiKeyAccount)
            }

        TextField("Base URL", text: $settingsStore.settings.sttConfig.baseURL)
            .textFieldStyle(.roundedBorder)

        TextField("Model", text: $settingsStore.settings.sttConfig.model)
            .textFieldStyle(.roundedBorder)

        HStack {
            testButton(status: sttTestStatus) {
                await testSTTConnection()
            }
            testStatusView(sttTestStatus)
        }
    }

    // MARK: - LLM Section

    @ViewBuilder
    private var llmSection: some View {
        Picker("Provider", selection: $settingsStore.settings.llmConfig.provider) {
            ForEach([ProviderType.openai, .claude, .gemini]) { provider in
                Text(provider.displayName).tag(provider)
            }
        }
        .onChange(of: settingsStore.settings.llmConfig.provider) { _, newProvider in
            updateLLMDefaults(for: newProvider)
        }

        SecureField("API Key", text: $llmAPIKey)
            .textFieldStyle(.roundedBorder)
            .onChange(of: llmAPIKey) { _, newValue in
                saveKey(newValue, account: settingsStore.settings.llmConfig.apiKeyAccount)
            }

        TextField("Base URL", text: $settingsStore.settings.llmConfig.baseURL)
            .textFieldStyle(.roundedBorder)

        TextField("Model", text: $settingsStore.settings.llmConfig.model)
            .textFieldStyle(.roundedBorder)

        Toggle("Enable LLM polishing", isOn: $settingsStore.settings.llmEnabled)

        HStack {
            testButton(status: llmTestStatus) {
                await testLLMConnection()
            }
            testStatusView(llmTestStatus)
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func testButton(status: TestStatus, action: @escaping () async -> Void) -> some View {
        Button {
            Task { await action() }
        } label: {
            HStack(spacing: 4) {
                if status == .testing {
                    ProgressView().controlSize(.small).scaleEffect(0.7)
                }
                Text("Test Connection")
            }
        }
        .disabled(status == .testing)
    }

    @ViewBuilder
    private func testStatusView(_ status: TestStatus) -> some View {
        switch status {
        case .idle:
            EmptyView()
        case .testing:
            EmptyView()
        case .success:
            Label("Connected", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.caption)
        case .failure(let msg):
            Label(msg, systemImage: "xmark.circle.fill")
                .foregroundStyle(.red)
                .font(.caption)
                .lineLimit(2)
        }
    }

    private func loadKeys() {
        sttAPIKey = settingsStore.loadAPIKey(for: settingsStore.settings.sttConfig.apiKeyAccount) ?? ""
        llmAPIKey = settingsStore.loadAPIKey(for: settingsStore.settings.llmConfig.apiKeyAccount) ?? ""
    }

    private func saveKey(_ key: String, account: String) {
        guard !key.isEmpty else { return }
        try? settingsStore.saveAPIKey(key, account: account)
    }

    private func updateLLMDefaults(for provider: ProviderType) {
        switch provider {
        case .openai:
            settingsStore.settings.llmConfig.baseURL = "https://api.openai.com"
            settingsStore.settings.llmConfig.model = "gpt-4o-mini"
            settingsStore.settings.llmConfig.apiKeyAccount = "llm.openai"
        case .claude:
            settingsStore.settings.llmConfig.baseURL = "https://api.anthropic.com"
            settingsStore.settings.llmConfig.model = "claude-sonnet-4-20250514"
            settingsStore.settings.llmConfig.apiKeyAccount = "llm.claude"
        case .gemini:
            settingsStore.settings.llmConfig.baseURL = "https://generativelanguage.googleapis.com"
            settingsStore.settings.llmConfig.model = "gemini-2.0-flash"
            settingsStore.settings.llmConfig.apiKeyAccount = "llm.gemini"
        }
        // Reload key for new provider account
        llmAPIKey = settingsStore.loadAPIKey(for: settingsStore.settings.llmConfig.apiKeyAccount) ?? ""
    }

    // MARK: - Connection Tests

    private func testSTTConnection() async {
        sttTestStatus = .testing
        let key = sttAPIKey
        let baseURL = settingsStore.settings.sttConfig.baseURL

        guard !key.isEmpty else {
            sttTestStatus = .failure("No API key")
            return
        }

        do {
            let url = URL(string: "\(baseURL)/v1/models")!
            var request = URLRequest(url: url)
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            request.timeoutInterval = 10
            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                sttTestStatus = .success
            } else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                sttTestStatus = .failure("HTTP \(code)")
            }
        } catch {
            sttTestStatus = .failure(error.localizedDescription)
        }
    }

    private func testLLMConnection() async {
        llmTestStatus = .testing
        let key = llmAPIKey
        let config = settingsStore.settings.llmConfig

        guard !key.isEmpty else {
            llmTestStatus = .failure("No API key")
            return
        }

        do {
            let result = try await testProviderConnection(provider: config.provider, baseURL: config.baseURL, apiKey: key)
            if result {
                llmTestStatus = .success
            } else {
                llmTestStatus = .failure("Connection failed")
            }
        } catch {
            llmTestStatus = .failure(error.localizedDescription)
        }
    }

    private func testProviderConnection(provider: ProviderType, baseURL: String, apiKey: String) async throws -> Bool {
        let url: URL
        var request: URLRequest

        switch provider {
        case .openai:
            url = URL(string: "\(baseURL)/v1/models")!
            request = URLRequest(url: url)
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        case .claude:
            url = URL(string: "\(baseURL)/v1/messages")!
            request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let body: [String: Any] = [
                "model": "claude-sonnet-4-20250514",
                "max_tokens": 1,
                "messages": [["role": "user", "content": "test"]],
            ]
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        case .gemini:
            url = URL(string: "\(baseURL)/v1beta/models?key=\(apiKey)")!
            request = URLRequest(url: url)
        }

        request.timeoutInterval = 10
        let (_, response) = try await URLSession.shared.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        return statusCode >= 200 && statusCode < 300
    }
}
