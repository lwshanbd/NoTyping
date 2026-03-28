import Foundation

final class WhisperTranscriptionProvider: TranscriptionProvider {
    private let apiKey: String
    private let baseURL: String
    private let model: String

    init(apiKey: String, baseURL: String = "https://api.openai.com", model: String = "whisper-1") {
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.model = model
    }

    func transcribe(audioData: Data, vocabulary: [String]) async throws -> String {
        let boundary = UUID().uuidString

        guard let url = URL(string: "\(baseURL)/v1/audio/transcriptions") else {
            throw PipelineError.sttError("Invalid base URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        var body = Data()

        // Field: file
        body.appendMultipartField(boundary: boundary, name: "file", filename: "audio.wav", contentType: "audio/wav", data: audioData)

        // Field: model
        body.appendMultipartTextField(boundary: boundary, name: "model", value: model)

        // Field: response_format
        body.appendMultipartTextField(boundary: boundary, name: "response_format", value: "json")

        // Field: prompt (vocabulary hints)
        if !vocabulary.isEmpty {
            body.appendMultipartTextField(boundary: boundary, name: "prompt", value: vocabulary.joined(separator: " "))
        }

        // Closing boundary
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch let error as URLError where error.code == .timedOut {
            throw PipelineError.sttTimeout
        } catch {
            throw PipelineError.sttError(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw PipelineError.sttError("No HTTP response")
        }

        switch http.statusCode {
        case 200..<300:
            break
        case 401:
            throw PipelineError.sttError("API key invalid")
        case 429:
            throw PipelineError.sttError("Rate limited")
        case 500...599:
            throw PipelineError.sttError("Server error")
        default:
            let body = String(data: data, encoding: .utf8) ?? "<non-utf8>"
            throw PipelineError.sttError("HTTP \(http.statusCode): \(body)")
        }

        // Parse JSON response: { "text": "..." }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = json["text"] as? String
        else {
            throw PipelineError.sttError("Unexpected response format")
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            throw PipelineError.sttEmpty
        }

        return trimmed
    }
}

// MARK: - Multipart Helpers

private extension Data {
    mutating func appendMultipartTextField(boundary: String, name: String, value: String) {
        append("--\(boundary)\r\n".data(using: .utf8)!)
        append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
        append("\(value)\r\n".data(using: .utf8)!)
    }

    mutating func appendMultipartField(boundary: String, name: String, filename: String, contentType: String, data: Data) {
        append("--\(boundary)\r\n".data(using: .utf8)!)
        append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        append("Content-Type: \(contentType)\r\n\r\n".data(using: .utf8)!)
        append(data)
        append("\r\n".data(using: .utf8)!)
    }
}
