import Foundation

final class GeminiRewriteProvider: RewriteProvider {
    private let apiKey: String
    private let model: String

    init(apiKey: String, model: String = "gemini-2.0-flash") {
        self.apiKey = apiKey
        self.model = model
    }

    func rewrite(text: String, vocabulary: [String]) async throws -> String {
        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(apiKey)") else {
            throw PipelineError.llmError("Invalid Gemini URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15

        var systemContent = RewritePrompt.system
        if !vocabulary.isEmpty {
            systemContent += "\n\nVocabulary terms (preserve these exactly): \(vocabulary.joined(separator: ", "))"
        }

        let payload: [String: Any] = [
            "contents": [
                ["parts": [["text": text]]],
            ],
            "systemInstruction": [
                "parts": [["text": systemContent]],
            ],
            "generationConfig": [
                "temperature": 0,
                "maxOutputTokens": max(text.count * 2, 256),
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

        // Parse response: candidates[0].content.parts[0].text
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let firstCandidate = candidates.first,
              let content = firstCandidate["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let firstPart = parts.first,
              let resultText = firstPart["text"] as? String
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
