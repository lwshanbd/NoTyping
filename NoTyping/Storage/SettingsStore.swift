import Combine
import Foundation

@MainActor
final class SettingsStore: ObservableObject {
    @Published var settings: AppSettings
    private let fileURL: URL
    private let keychainStore: KeychainStore

    init(keychainStore: KeychainStore = KeychainStore()) {
        self.keychainStore = keychainStore
        self.fileURL = FileLocations.settingsFile
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) {
            self.settings = decoded
        } else {
            self.settings = AppSettings()
        }
    }

    func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(settings) else { return }
        try? data.write(to: fileURL, options: [.atomic])
    }
    func loadAPIKey(for account: String) -> String? { keychainStore.load(account: account) }
    func saveAPIKey(_ key: String, account: String) throws { try keychainStore.save(key, account: account) }
}
