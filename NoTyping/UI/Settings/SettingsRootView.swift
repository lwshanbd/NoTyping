import SwiftUI

enum SettingsTab: String, CaseIterable, Identifiable {
    case general, api, vocabulary, history, about
    var id: String { rawValue }
    var title: String {
        switch self {
        case .general:    "General"
        case .api:        "API"
        case .vocabulary: "Vocabulary"
        case .history:    "History"
        case .about:      "About"
        }
    }
    var systemImage: String {
        switch self {
        case .general:    "gear"
        case .api:        "key"
        case .vocabulary: "book"
        case .history:    "clock"
        case .about:      "info.circle"
        }
    }
}

struct SettingsRootView: View {
    @State private var selectedTab: SettingsTab = .general

    var body: some View {
        NavigationSplitView {
            List(SettingsTab.allCases, selection: $selectedTab) { tab in
                Label(tab.title, systemImage: tab.systemImage)
                    .tag(tab)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 160, ideal: 180, max: 220)
        } detail: {
            detailView(for: selectedTab)
                .padding(20)
        }
    }

    @ViewBuilder
    private func detailView(for tab: SettingsTab) -> some View {
        switch tab {
        case .general:    GeneralSettingsView()
        case .api:        APISettingsView()
        case .vocabulary: VocabularySettingsView()
        case .history:    HistorySettingsView()
        case .about:      Text("NoTyping V2\nVersion 0.1.0")
        }
    }
}
