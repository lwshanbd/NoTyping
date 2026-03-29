import XCTest
@testable import NoTypingV2

final class WhisperProviderTests: XCTestCase {

    // MARK: - Multipart Body Structure

    func testMultipartFormDataStructure() async throws {
        let responseJSON: [String: Any] = ["text": "Hello world"]

        let server = try LocalMockServer(port: 18_091, responseJSON: responseJSON)
        server.start()
        defer { server.stop() }

        let provider = WhisperTranscriptionProvider(apiKey: "sk-whisper-test", baseURL: "http://127.0.0.1:18091")
        let audioData = Data([0x00, 0x01, 0x02, 0x03])

        let result = try await provider.transcribe(audioData: audioData, vocabulary: ["Xcode", "SwiftUI"])
        server.waitForRequest()

        // Response parsed
        XCTAssertEqual(result, "Hello world")

        // Request line
        XCTAssertTrue(server.lastRequestLine.contains("/v1/audio/transcriptions"))
        XCTAssertTrue(server.lastRequestLine.hasPrefix("POST"))

        // Content-Type should be multipart/form-data with boundary
        let contentType = server.lastHeaders["content-type"] ?? ""
        XCTAssertTrue(contentType.hasPrefix("multipart/form-data; boundary="),
                       "Content-Type should be multipart/form-data, got: \(contentType)")

        // Extract boundary
        let boundary = contentType.replacingOccurrences(of: "multipart/form-data; boundary=", with: "")
        XCTAssertFalse(boundary.isEmpty, "Boundary should not be empty")

        // Check body fields (binary data so use lossyConversion for the text parts)
        let bodyString = String(data: server.lastRequestData, encoding: .utf8)
            ?? String(data: server.lastRequestData, encoding: .ascii)
            ?? ""

        // File field
        XCTAssertTrue(bodyString.contains("name=\"file\""), "Body should contain file field")
        XCTAssertTrue(bodyString.contains("filename=\"audio.wav\""), "Body should contain audio.wav filename")
        XCTAssertTrue(bodyString.contains("Content-Type: audio/wav"), "Body should declare audio/wav content type")

        // Model field
        XCTAssertTrue(bodyString.contains("name=\"model\""), "Body should contain model field")
        XCTAssertTrue(bodyString.contains("whisper-1"), "Body should contain whisper-1 model value")

        // Response format
        XCTAssertTrue(bodyString.contains("name=\"response_format\""), "Body should contain response_format field")

        // Vocabulary prompt
        XCTAssertTrue(bodyString.contains("name=\"prompt\""), "Body should contain prompt field for vocabulary")
        XCTAssertTrue(bodyString.contains("Xcode SwiftUI"), "Prompt should contain vocabulary joined by space")

        // Closing boundary
        XCTAssertTrue(bodyString.contains("--\(boundary)--"), "Body should end with closing boundary")
    }

    // MARK: - Auth Header

    func testAuthorizationHeaderFormat() async throws {
        let responseJSON: [String: Any] = ["text": "test"]

        let server = try LocalMockServer(port: 18_092, responseJSON: responseJSON)
        server.start()
        defer { server.stop() }

        let provider = WhisperTranscriptionProvider(apiKey: "sk-my-secret-key", baseURL: "http://127.0.0.1:18092")
        _ = try await provider.transcribe(audioData: Data([0x00]), vocabulary: [])
        server.waitForRequest()

        let authHeader = server.lastHeaders["authorization"] ?? ""
        XCTAssertEqual(authHeader, "Bearer sk-my-secret-key", "Authorization header should be 'Bearer <apiKey>'")
    }

    // MARK: - Error Response Handling

    func testErrorResponseHandling401() async throws {
        let errorJSON: [String: Any] = ["error": "invalid_api_key"]

        let server = try LocalMockServer(port: 18_093, responseJSON: errorJSON, statusCode: 401)
        server.start()
        defer { server.stop() }

        let provider = WhisperTranscriptionProvider(apiKey: "sk-invalid", baseURL: "http://127.0.0.1:18093")

        do {
            _ = try await provider.transcribe(audioData: Data([0xFF]), vocabulary: [])
            XCTFail("Should have thrown an error for 401 response")
        } catch let error as PipelineError {
            switch error {
            case .sttError(let msg):
                XCTAssertTrue(msg.contains("API key invalid"),
                              "Error message should indicate invalid API key, got: \(msg)")
            default:
                XCTFail("Expected sttError, got: \(error)")
            }
        }
    }
}
