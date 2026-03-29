import Foundation

enum HotkeyMode: String, Codable, CaseIterable, Identifiable {
    case toggle
    case pushToTalk
    var id: String { rawValue }
}

enum LanguageMode: String, Codable, CaseIterable, Identifiable {
    case auto
    case english
    case simplifiedChinese
    var id: String { rawValue }
}

enum ProviderType: String, Codable, CaseIterable, Identifiable {
    case openai
    case claude
    case gemini
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .openai: "OpenAI"
        case .claude: "Claude"
        case .gemini: "Gemini"
        }
    }
}

struct ProviderConfig: Codable, Equatable {
    var provider: ProviderType
    var baseURL: String
    var model: String
    var apiKeyAccount: String

    static let defaultSTT = ProviderConfig(provider: .openai, baseURL: "https://api.openai.com", model: "whisper-1", apiKeyAccount: "stt.openai")
    static let defaultLLM = ProviderConfig(provider: .openai, baseURL: "https://api.openai.com", model: "gpt-4o-mini", apiKeyAccount: "llm.openai")
}

struct AppSettings: Codable, Equatable {
    var hotkey: HotkeyDescriptor = .default
    var hotkeyMode: HotkeyMode = .toggle
    var launchAtLogin: Bool = false
    var languageMode: LanguageMode = .auto
    var sttConfig: ProviderConfig = .defaultSTT
    var llmConfig: ProviderConfig = .defaultLLM
    var llmEnabled: Bool = true
}
