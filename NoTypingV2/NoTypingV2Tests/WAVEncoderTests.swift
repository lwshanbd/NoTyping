import XCTest
@testable import NoTypingV2

final class WAVEncoderTests: XCTestCase {

    func testWAVHeaderStructure() {
        let pcmData = Data(repeating: 0, count: 100)
        let wav = WAVEncoder.encode(pcmData: pcmData)

        // RIFF magic
        XCTAssertEqual(String(data: wav[0..<4], encoding: .ascii), "RIFF")
        // File size field = total - 8
        let fileSize = wav[4..<8].withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }
        XCTAssertEqual(fileSize, UInt32(wav.count - 8))
        // WAVE identifier
        XCTAssertEqual(String(data: wav[8..<12], encoding: .ascii), "WAVE")
        // fmt sub-chunk
        XCTAssertEqual(String(data: wav[12..<16], encoding: .ascii), "fmt ")
        // PCM format tag = 1
        let format = wav[20..<22].withUnsafeBytes { $0.load(as: UInt16.self).littleEndian }
        XCTAssertEqual(format, 1)
        // Mono channel
        let channels = wav[22..<24].withUnsafeBytes { $0.load(as: UInt16.self).littleEndian }
        XCTAssertEqual(channels, 1)
        // Default sample rate = 24000
        let sampleRate = wav[24..<28].withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }
        XCTAssertEqual(sampleRate, 24000)
        // data sub-chunk
        XCTAssertEqual(String(data: wav[36..<40], encoding: .ascii), "data")
        // data size matches input
        let dataSize = wav[40..<44].withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }
        XCTAssertEqual(dataSize, UInt32(pcmData.count))
    }

    func testEmptyPCMData() {
        let wav = WAVEncoder.encode(pcmData: Data())
        // Header-only: 44 bytes
        XCTAssertEqual(wav.count, 44)
        XCTAssertEqual(String(data: wav[0..<4], encoding: .ascii), "RIFF")
        let dataSize = wav[40..<44].withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }
        XCTAssertEqual(dataSize, 0)
    }

    func testLargePCMData() {
        // 1 second of 24 kHz 16-bit mono audio = 48 000 bytes
        let pcmData = Data(repeating: 0xAB, count: 48_000)
        let wav = WAVEncoder.encode(pcmData: pcmData)
        XCTAssertEqual(wav.count, 44 + pcmData.count)
        let dataSize = wav[40..<44].withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }
        XCTAssertEqual(dataSize, UInt32(pcmData.count))
    }

    func testCustomSampleRate() {
        let wav = WAVEncoder.encode(pcmData: Data(count: 100), sampleRate: 44100)
        let sampleRate = wav[24..<28].withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }
        XCTAssertEqual(sampleRate, 44100)
        // Byte rate should reflect the custom sample rate: 44100 * 1 * 16/8 = 88200
        let byteRate = wav[28..<32].withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }
        XCTAssertEqual(byteRate, 88200)
    }
}
