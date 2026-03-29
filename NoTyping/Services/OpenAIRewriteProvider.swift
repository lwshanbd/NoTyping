import Foundation

final class OpenAIRewriteProvider: RewriteProvider {
    private let apiKey: String
    private let baseURL: String
    private let model: String

    init(apiKey: String, baseURL: String = "https://api.openai.com", model: String = "gpt-4o-mini") {
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.model = model
    }

    func rewrite(text: String, vocabulary: [String]) async throws -> String {
        guard let url = URL(string: "\(baseURL)/v1/chat/completions") else {
            throw PipelineError.llmError("Invalid base URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15

        var systemContent = RewritePrompt.system
        if !vocabulary.isEmpty {
            systemContent += "\n\nVocabulary terms (preserve these exactly): \(vocabulary.joined(separator: ", "))"
        }

        let payload: [String: Any] = [
            "model": model,
            "temperature": 0,
            "max_tokens": max(text.count * 2, 256),
            "messages": [
                ["role": "system", "content": systemContent],
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

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String
        else {
            throw PipelineError.llmError("Unexpected response format")
        }

        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            throw PipelineError.llmError("Empty response from model")
        }

        return trimmed
    }
}
