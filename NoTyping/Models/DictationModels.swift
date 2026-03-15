import Foundation

struct TranscriptSegment: Identifiable, Equatable {
    var id: String
    var previousItemID: String?
    var rawText: String
    var averageLogProbability: Double?
}

enum RealtimeConnectionStatus: Equatable {
    case connecting
    case connected(resumedAfterReconnect: Bool)
    case reconnecting(attempt: Int, maximumAttempts: Int, retryDelayMilliseconds: Int)
    case stopped

    var title: String {
        switch self {
        case .connecting:
            "Connecting"
        case let .connected(resumedAfterReconnect):
            resumedAfterReconnect ? "Reconnected" : "Connected"
        case .reconnecting:
            "Reconnecting"
        case .stopped:
            "Stopped"
        }
    }

    var detail: String {
        switch self {
        case .connecting:
            "Opening realtime transcription session."
        case let .connected(resumedAfterReconnect):
            resumedAfterReconnect ? "Realtime transcription resumed after a transient disconnect." : "Realtime transcription session is ready."
        case let .reconnecting(attempt, maximumAttempts, retryDelayMilliseconds):
            "Retrying realtime connection (\(attempt)/\(maximumAttempts)) in \(Self.formatDelay(milliseconds: retryDelayMilliseconds))."
        case .stopped:
            "Realtime transcription session is not active."
        }
    }

    var isRecovering: Bool {
        if case .reconnecting = self {
            return true
        }
        return false
    }

    var shouldAnnotateActiveSession: Bool {
        switch self {
        case .reconnecting:
            true
        case let .connected(resumedAfterReconnect):
            resumedAfterReconnect
        case .connecting, .stopped:
            false
        }
    }

    private static func formatDelay(milliseconds: Int) -> String {
        if milliseconds % 1000 == 0 {
            return "\(milliseconds / 1000)s"
        }
        return String(format: "%.2fs", Double(milliseconds) / 1000.0)
    }
}

enum TranscriptionEvent: Equatable {
    case connectionStatus(RealtimeConnectionStatus)
    case sessionCreated
    case partial(itemID: String, previousItemID: String?, text: String)
    case completed(itemID: String, previousItemID: String?, text: String, averageLogProbability: Double?)
    case failed(itemID: String?, message: String)
    case bufferCommitted(itemID: String?)
}

struct RewriteContext: Equatable {
    var appCategory: AppCategory
    var fieldType: FieldType
    var operation: InsertionOperation
    var aggressiveness: RewriteAggressiveness
    var languageMode: LanguageMode
    var profile: DictationProfile
    var protectedTerms: [ProtectedTerm]
    var recentContext: String?
}

struct RewriteResult: Equatable {
    var text: String
    var usedFallback: Bool
}

struct FocusedElementContext: Equatable {
    var bundleIdentifier: String?
    var applicationName: String?
    var role: String?
    var subrole: String?
    var fieldType: FieldType
    var operation: InsertionOperation
    var selectedRange: NSRange?
    var value: String?
    var isSecureTextField: Bool
    var isEditable: Bool
}

enum InsertionStrategy: String, Equatable {
    case accessibilityValueReplacement
    case accessibilitySelectionReplacement
    case unicodeTyping
    case pasteboard
}

struct InsertionOutcome: Equatable {
    var strategy: InsertionStrategy
    var insertedText: String
}

struct HistoryEntry: Identifiable, Codable, Equatable {
    var id = UUID()
    var createdAt: Date
    var appName: String
    var rawText: String
    var insertedText: String
}

struct DiagnosticEntry: Identifiable, Codable, Equatable {
    var id = UUID()
    var timestamp: Date
    var subsystem: String
    var message: String
}

enum DictationLifecycleStage: String, Codable, Equatable, CaseIterable, Identifiable {
    case idle
    case requestingPermissions
    case ready
    case recording
    case receivingPartialTranscript
    case segmentFinalizing
    case normalizingVocabulary
    case rewriting
    case inserting
    case error

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .idle:
            "Idle"
        case .requestingPermissions:
            "Permissions"
        case .ready:
            "Ready"
        case .recording:
            "Listening"
        case .receivingPartialTranscript:
            "Transcribing"
        case .segmentFinalizing:
            "Finalizing"
        case .normalizingVocabulary:
            "Normalizing Vocabulary"
        case .rewriting:
            "Polishing"
        case .inserting:
            "Inserting"
        case .error:
            "Error"
        }
    }
}

struct DictationLifecycleState: Equatable {
    var stage: DictationLifecycleStage
    var detail: String?

    static let idle = DictationLifecycleState(stage: .idle, detail: nil)
    static let ready = DictationLifecycleState(stage: .ready, detail: nil)
}

enum DictationError: LocalizedError, Equatable {
    case missingMicrophonePermission
    case missingAccessibilityPermission
    case providerConfiguration(String)
    case transcription(String)
    case rewrite(String)
    case insertion(String)
    case unsupportedFocusedElement
    case network(String)

    var errorDescription: String? {
        switch self {
        case .missingMicrophonePermission:
            "Microphone permission is required before dictation can start."
        case .missingAccessibilityPermission:
            "Accessibility permission is required to inspect and insert text into other apps."
        case let .providerConfiguration(message):
            "Provider configuration error: \(message)"
        case let .transcription(message):
            "Transcription failed: \(message)"
        case let .rewrite(message):
            "Polish step failed: \(message)"
        case let .insertion(message):
            "Insertion failed: \(message)"
        case .unsupportedFocusedElement:
            "The focused field could not be edited safely."
        case let .network(message):
            "Network error: \(message)"
        }
    }
}

struct RealtimeTranscriptionConfiguration: Equatable {
    var provider: ProviderSettings
    var languageMode: LanguageMode
    var prompt: String
    var useServerVAD: Bool
}
