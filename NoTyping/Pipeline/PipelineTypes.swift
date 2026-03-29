import Foundation

enum PipelineState: String, Sendable {
    case idle
    case ready
    case recording
    case transcribing
    case normalizing
    case polishing
    case inserting
    case error
}

enum PipelineEvent: Sendable {
    case stateChanged(PipelineState)
    case volumeLevel(Float)
    case transcriptionResult(original: String, final: String)
    case error(PipelineError)
    case focusLost(text: String)
}

enum PipelineError: Error, LocalizedError, Sendable {
    case noMicrophonePermission
    case noAccessibilityPermission
    case recordingTooShort
    case recordingTooLong
    case sttTimeout
    case sttError(String)
    case sttEmpty
    case llmTimeout
    case llmError(String)
    case validationFailed(String)
    case insertionFailed(String)
    case networkUnavailable

    var errorDescription: String? {
        switch self {
        case .noMicrophonePermission: "需要麦克风权限"
        case .noAccessibilityPermission: "需要辅助功能权限"
        case .recordingTooShort: "录音太短"
        case .recordingTooLong: "录音过长，已截断"
        case .sttTimeout: "转写超时，请重试"
        case .sttError(let msg): "转写错误: \(msg)"
        case .sttEmpty: "未识别到语音"
        case .llmTimeout: "润色超时"
        case .llmError(let msg): "润色错误: \(msg)"
        case .validationFailed(let msg): "验证失败: \(msg)"
        case .insertionFailed(let msg): "插入失败: \(msg)"
        case .networkUnavailable: "无网络连接"
        }
    }
}
