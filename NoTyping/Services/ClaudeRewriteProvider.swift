import Foundation

final class ClaudeRewriteProvider: RewriteProvider {
    private let apiKey: String
    private let baseURL: String
    private let model: String

    init(apiKey: String, baseURL: String = "https://api.anthropic.com", model: String = "claude-sonnet-4-20250514") {
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.model = model
    }

    func rewrite(text: String, vocabulary: [String]) async throws -> String {
        guard let url = URL(string: "\(baseURL)/v1/messages") else {
            throw PipelineError.llmError("Invalid base URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.timeoutInterval = 15

        var systemContent = RewritePrompt.system
        if !vocabulary.isEmpty {
            systemContent += "\n\nVocabulary terms (preserve these exactly): \(vocabulary.joined(separator: ", "))"
        }

        let payload: [String: Any] = [
            "model": model,
            "max_tokens": max(text.count * 2, 256),
            "system": systemContent,
            "messages": [
                ["role": "user", "content": text],
            ],
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch let error as URLError where error.code == .timedOut {
            throw PipelineError.llmTimeout
        } catch {
            throw PipelineError.llmError(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw PipelineError.llmError("No HTTP response")
        }

        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "<non-utf8>"
            throw PipelineError.llmError("HTTP \(http.statusCode): \(body)")
        }

        // Parse response: content[0].text
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let contentArray = json["content"] as? [[String: Any]],
              let firstContent = contentArray.first,
              let resultText = firstContent["text"] as? String
        else {
            throw PipelineError.llmError("Unexpected response format")
        }

        let trimmed = resultText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            throw PipelineError.llmError("Empty response from model")
        }

        return trimmed
    }
}
