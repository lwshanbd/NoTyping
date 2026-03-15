import Foundation

@MainActor
protocol RewriteServiceProtocol: AnyObject {
    func rewrite(transcript: String, context: RewriteContext, provider: ProviderSettings, apiKey: String?) async throws -> RewriteResult
}

@MainActor
protocol ProviderConnectionTesting {
    func test(provider: ProviderSettings, apiKey: String?) async throws -> String
}

struct RewriteServiceFactory {
    private let keychainStore: KeychainStore
    private let diagnosticStore: DiagnosticStore

    init(keychainStore: KeychainStore, diagnosticStore: DiagnosticStore) {
        self.keychainStore = keychainStore
        self.diagnosticStore = diagnosticStore
    }

    @MainActor
    func make(for provider: ProviderSettings) -> RewriteServiceProtocol {
        switch provider.profile {
        case .mock:
            MockRewriteService()
        case .openAI, .customCompatible:
            OpenAIResponsesRewriteService(diagnosticStore: diagnosticStore)
        }
    }
}

final class ProviderConnectionTester: ProviderConnectionTesting {
    private let keychainStore: KeychainStore

    init(keychainStore: KeychainStore) {
        self.keychainStore = keychainStore
    }

    func test(provider: ProviderSettings, apiKey: String?) async throws -> String {
        if provider.profile == .mock {
            return "Mock provider is ready."
        }

        guard let url = URL(string: provider.baseURL + "/v1/models") else {
            throw DictationError.providerConfiguration("Invalid base URL.")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        if let apiKey, !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw DictationError.network("The provider did not return an HTTP response.")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw DictationError.network("Provider test failed with HTTP \(http.statusCode).")
        }
        return "Provider connection succeeded."
    }
}

enum RewritePromptBuilder {
    static let systemPrompt = """
    You are a real-time dictation rewriter for a macOS voice typing app.

    Your job is to convert spoken transcript into polished insertion-ready text.

    Rules:
    - Preserve meaning exactly.
    - Do not add facts, explanations, or opinions.
    - Remove filler words, false starts, and repeated fragments.
    - Fix punctuation, capitalization, and obvious grammar issues.
    - Keep the result concise and natural.
    - Prefer light editing over aggressive rewriting.
    - Preserve names, technical terms, acronyms, code tokens, URLs, and numbers.
    - Respect protected vocabulary terms exactly.
    - Preserve the original language of the transcript.
    - Output only the final text.
    - Never wrap the output in quotes.
    """

    static func userPayload(transcript: String, context: RewriteContext) -> String {
        var payload = """
        <context>
        app_category: \(context.appCategory.rawValue)
        field_type: \(context.fieldType.rawValue)
        operation: \(context.operation.rawValue)
        rewrite_aggressiveness: \(context.aggressiveness.rawValue)
        language_mode: \(context.languageMode.rawValue)
        profile: \(context.profile.rawValue)
        protected_terms: \(context.protectedTerms.map(\.value).joined(separator: ", "))
        </context>
        """

        if let recentContext = context.recentContext?.trimmed, !recentContext.isEmpty {
            payload += """

            <recent_context>
            \(recentContext)
            </recent_context>
            """
        }

        payload += """

        <transcript>
        \(transcript)
        </transcript>
        """
        return payload
    }
}

final class OpenAIResponsesRewriteService: RewriteServiceProtocol {
    private let diagnosticStore: DiagnosticStore

    init(diagnosticStore: DiagnosticStore) {
        self.diagnosticStore = diagnosticStore
    }

    func rewrite(transcript: String, context: RewriteContext, provider: ProviderSettings, apiKey: String?) async throws -> RewriteResult {
        guard let apiKey, !apiKey.isEmpty else {
            throw DictationError.providerConfiguration("An API key is required for the selected provider.")
        }

        guard let url = URL(string: provider.baseURL + "/v1/responses") else {
            throw DictationError.providerConfiguration("Invalid rewrite base URL.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let payload: [String: Any] = [
            "model": provider.rewriteModel,
            "input": [
                [
                    "role": "system",
                    "content": [
                        ["type": "input_text", "text": RewritePromptBuilder.systemPrompt]
                    ]
                ],
                [
                    "role": "user",
                    "content": [
                        ["type": "input_text", "text": RewritePromptBuilder.userPayload(transcript: transcript, context: context)]
                    ]
                ]
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])

        let started = Date()
        let (data, response) = try await URLSession.shared.data(for: request)
        let elapsed = Date().timeIntervalSince(started)
        diagnosticStore.record(subsystem: "rewrite", message: "Responses call completed in \(String(format: "%.2f", elapsed))s")

        guard let http = response as? HTTPURLResponse else {
            throw DictationError.network("The rewrite provider did not return an HTTP response.")
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "<non-utf8>"
            throw DictationError.rewrite("Provider returned HTTP \(http.statusCode): \(body)")
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        if let text = json?["output_text"] as? String, !text.trimmed.isEmpty {
            return RewriteResult(text: text.trimmed, usedFallback: false)
        }
        if let outputs = json?["output"] as? [[String: Any]] {
            for output in outputs {
                guard let content = output["content"] as? [[String: Any]] else { continue }
                for item in content {
                    if let text = item["text"] as? String, !text.trimmed.isEmpty {
                        return RewriteResult(text: text.trimmed, usedFallback: false)
                    }
                }
            }
        }

        throw DictationError.rewrite("The rewrite provider returned an empty result.")
    }
}

final class MockRewriteService: RewriteServiceProtocol {
    func rewrite(transcript: String, context: RewriteContext, provider: ProviderSettings, apiKey: String?) async throws -> RewriteResult {
        let cleaned = transcript
            .replacingOccurrences(of: "(?i)\\b(um|uh|er|ah)\\b", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmed

        let output: String
        switch context.profile {
        case .raw, .codeAware:
            output = cleaned
        case .email:
            output = cleaned.hasSuffix(".") || cleaned.hasSuffix("。") ? cleaned : cleaned + "."
        default:
            output = cleaned
        }
        return RewriteResult(text: output, usedFallback: false)
    }
}
