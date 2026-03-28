import SwiftUI

enum SettingsTab: String, CaseIterable, Identifiable {
    case general, api, vocabulary, history, about
    var id: String { rawValue }
    var title: String {
        switch self {
        case .general: "General"
        case .api: "API"
        case .vocabulary: "Vocabulary"
        case .history: "History"
        case .about: "About"
        }
    }
}

struct SettingsRootView: View {
    @State private var selectedTab: SettingsTab = .general

    var body: some View {
        TabView(selection: $selectedTab) {
            GeneralSettingsView().tabItem { Text("General") }.tag(SettingsTab.general)
            APISettingsView().tabItem { Text("API") }.tag(SettingsTab.api)
            VocabularySettingsView().tabItem { Text("Vocabulary") }.tag(SettingsTab.vocabulary)
            HistorySettingsView().tabItem { Text("History") }.tag(SettingsTab.history)
            Text("NoTyping V2\nVersion 0.1.0").tabItem { Text("About") }.tag(SettingsTab.about)
        }
        .padding(20)
    }
}
