import Foundation

protocol TranscriptionProvider: Sendable {
    func transcribe(audioData: Data, vocabulary: [String]) async throws -> String
}
