import Foundation

enum VoiceActivityEvent: Equatable {
    case silence(level: Float)
    case speech(level: Float)
    case boundary(level: Float)
}

final class VoiceActivityDetector {
    private var noiseFloor: Float = 0.004
    private var speechFrames = 0
    private var silenceFrames = 0
    private var speechDetected = false

    func reset() {
        noiseFloor = 0.004
        speechFrames = 0
        silenceFrames = 0
        speechDetected = false
    }

    func process(samples: [Int16]) -> VoiceActivityEvent {
        guard !samples.isEmpty else { return .silence(level: 0) }
        let rms = sqrt(samples.reduce(Float.zero) { partial, sample in
            let normalized = Float(sample) / Float(Int16.max)
            return partial + normalized * normalized
        } / Float(samples.count))

        if !speechDetected {
            noiseFloor = (noiseFloor * 0.95) + (rms * 0.05)
        }
        let threshold = max(noiseFloor * 3.3, 0.012)

        if rms >= threshold {
            speechDetected = true
            speechFrames += 1
            silenceFrames = 0
            return .speech(level: rms)
        }

        if speechDetected {
            silenceFrames += 1
            if silenceFrames >= 8, speechFrames >= 6 {
                speechDetected = false
                speechFrames = 0
                silenceFrames = 0
                return .boundary(level: rms)
            }
        }

        return .silence(level: rms)
    }
}
