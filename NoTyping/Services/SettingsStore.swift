import Combine
import Foundation

@MainActor
final class SettingsStore: ObservableObject {
    @Published var settings: AppSettings {
        didSet { save() }
    }

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let keychainStore: KeychainStore

    init(keychainStore: KeychainStore) {
        self.keychainStore = keychainStore
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        decoder.dateDecodingStrategy = .iso8601
        encoder.dateEncodingStrategy = .iso8601

        if let data = try? Data(contentsOf: FileLocations.settingsURL),
           let stored = try? decoder.decode(AppSettings.self, from: data) {
            settings = stored
        } else {
            settings = AppSettings()
        }
    }

    func update(_ mutate: (inout AppSettings) -> Void) {
        mutate(&settings)
    }

    func loadAPIKey() -> String? {
        keychainStore.load(account: settings.provider.apiKeyAccount)
    }

    func saveAPIKey(_ key: String) throws {
        try keychainStore.save(value: key, account: settings.provider.apiKeyAccount)
        objectWillChange.send()
    }

    private func save() {
        guard let data = try? encoder.encode(settings) else { return }
        try? data.write(to: FileLocations.settingsURL, options: [.atomic])
    }
}
