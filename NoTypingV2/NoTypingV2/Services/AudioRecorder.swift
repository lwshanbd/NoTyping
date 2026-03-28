import AVFoundation
import Foundation

struct AudioRecording: Sendable {
    let pcmData: Data
    let duration: TimeInterval
}

final class AudioRecorder: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private var buffer = Data()
    private var startTime: Date?
    private let lock = NSLock()
    private var converter: AVAudioConverter?

    private static let targetSampleRate: Double = 24_000
    private static let targetChannels: AVAudioChannelCount = 1

    private var targetFormat: AVAudioFormat {
        AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: Self.targetSampleRate, channels: Self.targetChannels, interleaved: true)!
    }

    var currentLevel: Float = 0

    func start() throws {
        stop()

        lock.lock()
        buffer = Data()
        startTime = nil
        lock.unlock()

        let inputNode = engine.inputNode
        let inputFormat = inputNode.inputFormat(forBus: 0)
        let outputFormat = targetFormat

        converter = AVAudioConverter(from: inputFormat, to: outputFormat)

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 2048, format: inputFormat) { [weak self] pcmBuffer, _ in
            self?.handleTapBuffer(pcmBuffer)
        }

        engine.prepare()
        try engine.start()

        lock.lock()
        startTime = Date()
        lock.unlock()
    }

    func stop() -> AudioRecording {
        engine.inputNode.removeTap(onBus: 0)
        if engine.isRunning {
            engine.stop()
        }

        lock.lock()
        let pcmData = buffer
        let duration: TimeInterval
        if let start = startTime {
            duration = Date().timeIntervalSince(start)
        } else {
            duration = 0
        }
        buffer = Data()
        startTime = nil
        lock.unlock()

        return AudioRecording(pcmData: pcmData, duration: duration)
    }

    private func handleTapBuffer(_ inputBuffer: AVAudioPCMBuffer) {
        guard let converter else { return }

        // Calculate capacity for the converted buffer
        let ratio = targetFormat.sampleRate / inputBuffer.format.sampleRate
        let frameCapacity = AVAudioFrameCount(Double(inputBuffer.frameLength) * ratio + 256)
        guard let convertedBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: frameCapacity) else { return }

        var error: NSError?
        var hasData = true
        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            if hasData {
                hasData = false
                outStatus.pointee = .haveData
                return inputBuffer
            }
            outStatus.pointee = .noDataNow
            return nil
        }

        converter.convert(to: convertedBuffer, error: &error, withInputFrom: inputBlock)
        guard error == nil else { return }
        guard let int16Data = convertedBuffer.int16ChannelData else { return }

        let sampleCount = Int(convertedBuffer.frameLength)
        guard sampleCount > 0 else { return }

        // Calculate RMS volume level
        let samples = UnsafeBufferPointer(start: int16Data[0], count: sampleCount)
        var sumSquares: Float = 0
        for sample in samples {
            let normalized = Float(sample) / Float(Int16.max)
            sumSquares += normalized * normalized
        }
        let rms = sqrt(sumSquares / Float(sampleCount))

        let data = Data(bytes: int16Data[0], count: sampleCount * MemoryLayout<Int16>.size)

        lock.lock()
        currentLevel = rms
        buffer.append(data)
        lock.unlock()
    }
}
