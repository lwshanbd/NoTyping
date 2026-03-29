import Foundation

enum WAVEncoder {
    static func encode(pcmData: Data, sampleRate: Int = 24000, channels: Int = 1, bitsPerSample: Int = 16) -> Data {
        let dataSize = UInt32(pcmData.count)
        let byteRate = UInt32(sampleRate * channels * bitsPerSample / 8)
        let blockAlign = UInt16(channels * bitsPerSample / 8)
        let fileSize = 36 + dataSize  // total file size minus 8 bytes for "RIFF" + size field

        var header = Data(capacity: 44 + pcmData.count)

        // RIFF header
        header.append(contentsOf: [0x52, 0x49, 0x46, 0x46]) // "RIFF"
        header.appendLittleEndian(fileSize)
        header.append(contentsOf: [0x57, 0x41, 0x56, 0x45]) // "WAVE"

        // fmt sub-chunk
        header.append(contentsOf: [0x66, 0x6D, 0x74, 0x20]) // "fmt "
        header.appendLittleEndian(UInt32(16))                 // PCM chunk size
        header.appendLittleEndian(UInt16(1))                  // PCM format
        header.appendLittleEndian(UInt16(channels))           // channels
        header.appendLittleEndian(UInt32(sampleRate))         // sample rate
        header.appendLittleEndian(byteRate)                   // byte rate
        header.appendLittleEndian(blockAlign)                 // block align
        header.appendLittleEndian(UInt16(bitsPerSample))      // bits per sample

        // data sub-chunk
        header.append(contentsOf: [0x64, 0x61, 0x74, 0x61]) // "data"
        header.appendLittleEndian(dataSize)

        // PCM data
        header.append(pcmData)

        return header
    }
}

private extension Data {
    mutating func appendLittleEndian(_ value: UInt16) {
        var le = value.littleEndian
        append(UnsafeBufferPointer(start: &le, count: 1))
    }

    mutating func appendLittleEndian(_ value: UInt32) {
        var le = value.littleEndian
        append(UnsafeBufferPointer(start: &le, count: 1))
    }
}
