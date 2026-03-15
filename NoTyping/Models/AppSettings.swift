import Carbon
import Foundation

enum HotkeyMode: String, Codable, CaseIterable, Identifiable {
    case pushToTalk
    case toggle

    var id: String { rawValue }
}

enum RewriteAggressiveness: String, Codable, CaseIterable, Identifiable {
    case low
    case medium
    case high

    var id: String { rawValue }
}

enum DictationProfile: String, Codable, CaseIterable, Identifiable {
    case raw
    case smart
    case email
    case notes
    case codeAware

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .raw:
            "Raw Dictation"
        case .smart:
            "Smart Dictation"
        case .email:
            "Email Mode"
        case .notes:
            "Notes Mode"
        case .codeAware:
            "Code-Aware Dictation"
        }
    }
}

enum LanguageMode: String, Codable, CaseIterable, Identifiable {
    case auto
    case english
    case simplifiedChinese

    var id: String { rawValue }

    var transcriptionLanguageHint: String? {
        switch self {
        case .auto:
            nil
        case .english:
            "en"
        case .simplifiedChinese:
            "zh"
        }
    }

    var displayName: String {
        switch self {
        case .auto:
            "Auto-detect"
        case .english:
            "English"
        case .simplifiedChinese:
            "Simplified Chinese"
        }
    }
}

enum InsertionCadence: String, Codable, CaseIterable, Identifiable {
    case stagedOnRelease
    case livePerSegment

    var id: String { rawValue }
}

enum AppCategory: String, Codable, CaseIterable, Identifiable {
    case chat
    case email
    case document
    case notes
    case browser
    case code
    case terminal
    case unknown

    var id: String { rawValue }
}

enum FieldType: String, Codable, CaseIterable, Identifiable {
    case singleLine
    case multiLine
    case unknown

    var id: String { rawValue }
}

enum InsertionOperation: String, Codable, CaseIterable, Identifiable {
    case insert
    case replaceSelection
    case append

    var id: String { rawValue }
}

enum LanguageScope: String, Codable, CaseIterable, Identifiable {
    case english
    case simplifiedChinese
    case both

    var id: String { rawValue }
}

struct HotkeyDescriptor: Codable, Equatable {
    var keyCode: UInt32
    var carbonModifiers: UInt32

    static let `default` = HotkeyDescriptor(
        keyCode: UInt32(kVK_Space),
        carbonModifiers: UInt32(cmdKey | optionKey)
    )

    var displayString: String {
        let parts = modifierDisplayParts + [HotkeyDescriptor.keyDisplayName(for: keyCode)]
        return parts.joined()
    }

    private var modifierDisplayParts: [String] {
        var parts: [String] = []
        if carbonModifiers & UInt32(cmdKey) != 0 { parts.append("⌘") }
        if carbonModifiers & UInt32(optionKey) != 0 { parts.append("⌥") }
        if carbonModifiers & UInt32(controlKey) != 0 { parts.append("⌃") }
        if carbonModifiers & UInt32(shiftKey) != 0 { parts.append("⇧") }
        return parts
    }

    static func keyDisplayName(for keyCode: UInt32) -> String {
        switch Int(keyCode) {
        case kVK_Space:
            return "Space"
        case kVK_Return:
            return "Return"
        case kVK_Tab:
            return "Tab"
        case kVK_ANSI_A...kVK_ANSI_Z:
            let scalar = UnicodeScalar(Int(keyCode) - kVK_ANSI_A + 65)
            return String(Character(scalar!))
        case kVK_ANSI_0...kVK_ANSI_9:
            let scalar = UnicodeScalar(Int(keyCode) - kVK_ANSI_0 + 48)
            return String(Character(scalar!))
        default:
            return "Key \(keyCode)"
        }
    }
}

struct AppRule: Identifiable, Codable, Equatable {
    var id = UUID()
    var bundleIdentifierPattern: String
    var category: AppCategory
    var preferredProfile: DictationProfile?
    var aggressivenessOverride: RewriteAggressiveness?
    var disableRewrite: Bool

    static let sample = AppRule(
        bundleIdentifierPattern: "com.apple.dt.Xcode",
        category: .code,
        preferredProfile: .codeAware,
        aggressivenessOverride: .low,
        disableRewrite: false
    )
}

struct ProviderCapabilities: Codable, Equatable {
    var supportsRealtimeTranscription: Bool
    var supportsTranscriptionClientSecrets: Bool
    var supportsResponsesRewrite: Bool
    var supportsTranscriptionPromptHints: Bool

    static let openAI = ProviderCapabilities(
        supportsRealtimeTranscription: true,
        supportsTranscriptionClientSecrets: true,
        supportsResponsesRewrite: true,
        supportsTranscriptionPromptHints: true
    )

    static let compatible = ProviderCapabilities(
        supportsRealtimeTranscription: true,
        supportsTranscriptionClientSecrets: false,
        supportsResponsesRewrite: true,
        supportsTranscriptionPromptHints: true
    )

    static let mock = ProviderCapabilities(
        supportsRealtimeTranscription: true,
        supportsTranscriptionClientSecrets: false,
        supportsResponsesRewrite: true,
        supportsTranscriptionPromptHints: false
    )
}

enum ProviderProfile: String, Codable, CaseIterable, Identifiable {
    case openAI
    case customCompatible
    case mock

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .openAI:
            "OpenAI"
        case .customCompatible:
            "Custom Compatible"
        case .mock:
            "Mock"
        }
    }
}

struct ProviderSettings: Codable, Equatable {
    var profile: ProviderProfile
    var baseURL: String
    var transcriptionModel: String
    var rewriteModel: String
    var sessionTokenEndpoint: String
    var apiKeyAccount: String
    var capabilities: ProviderCapabilities

    static let `default` = ProviderSettings(
        profile: .openAI,
        baseURL: "https://api.openai.com",
        transcriptionModel: "gpt-4o-transcribe",
        rewriteModel: "gpt-5-mini",
        sessionTokenEndpoint: "",
        apiKeyAccount: "default",
        capabilities: .openAI
    )
}

struct AppSettings: Codable, Equatable {
    var hotkey = HotkeyDescriptor.default
    var hotkeyMode: HotkeyMode = .pushToTalk
    var launchAtLoginEnabled = false
    var insertionCadence: InsertionCadence = .stagedOnRelease
    var rewriteAggressiveness: RewriteAggressiveness = .medium
    var defaultProfile: DictationProfile = .smart
    var languageMode: LanguageMode = .auto
    var saveTranscriptHistory = false
    var debugLoggingEnabled = false
    var fallbackToRawTranscript = true
    var provider = ProviderSettings.default
    var appRules: [AppRule] = []
}
