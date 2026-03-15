@preconcurrency import AVFoundation
import Foundation

protocol AudioCaptureManagerDelegate: AnyObject {
    func audioCaptureManagerDidCapturePCMChunk(_ data: Data)
    func audioCaptureManagerDidUpdateVoiceActivity(_ event: VoiceActivityEvent)
}

final class AudioCaptureManager {
    weak var delegate: AudioCaptureManagerDelegate?

    private let engine = AVAudioEngine()
    private let vad = VoiceActivityDetector()
    private var converter: AVAudioConverter?
    private let targetFormat: AVAudioFormat

    init() {
        targetFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 24_000, channels: 1, interleaved: true)!
    }

    func start() throws {
        stop()
        vad.reset()
        let inputNode = engine.inputNode
        let inputFormat = inputNode.inputFormat(forBus: 0)
        converter = AVAudioConverter(from: inputFormat, to: targetFormat)

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 2048, format: inputFormat) { [weak self] buffer, _ in
            self?.handle(buffer: buffer)
        }

        engine.prepare()
        try engine.start()
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        if engine.isRunning {
            engine.stop()
        }
    }

    private func handle(buffer: AVAudioPCMBuffer) {
        guard let converter else { return }

        let frameCapacity = AVAudioFrameCount(Double(buffer.frameLength) * (targetFormat.sampleRate / buffer.format.sampleRate) + 256)
        guard let converted = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: frameCapacity) else { return }

        var error: NSError?
        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            outStatus.pointee = .haveData
            return buffer
        }

        converter.convert(to: converted, error: &error, withInputFrom: inputBlock)
        guard error == nil, let pointer = converted.int16ChannelData else { return }

        let sampleCount = Int(converted.frameLength)
        let samples = Array(UnsafeBufferPointer(start: pointer[0], count: sampleCount))
        let event = vad.process(samples: samples)
        let data = Data(bytes: pointer[0], count: sampleCount * MemoryLayout<Int16>.size)
        delegate?.audioCaptureManagerDidUpdateVoiceActivity(event)
        delegate?.audioCaptureManagerDidCapturePCMChunk(data)
    }
}
