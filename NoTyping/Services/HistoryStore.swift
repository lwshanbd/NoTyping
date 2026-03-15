import Combine
import Foundation

@MainActor
final class HistoryStore: ObservableObject {
    @Published private(set) var entries: [HistoryEntry] = []

    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    init() {
        decoder.dateDecodingStrategy = .iso8601
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? Data(contentsOf: FileLocations.historyURL),
           let stored = try? decoder.decode([HistoryEntry].self, from: data) {
            entries = stored
        }
    }

    func append(_ entry: HistoryEntry, enabled: Bool) {
        guard enabled else { return }
        entries.insert(entry, at: 0)
        if entries.count > 200 {
            entries = Array(entries.prefix(200))
        }
        persist()
    }

    func clear() {
        entries.removeAll()
        try? FileManager.default.removeItem(at: FileLocations.historyURL)
    }

    private func persist() {
        guard let data = try? encoder.encode(entries) else { return }
        try? data.write(to: FileLocations.historyURL, options: [.atomic])
    }
}
