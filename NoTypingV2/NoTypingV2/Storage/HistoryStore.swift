import Combine
import Foundation

struct HistoryEntry: Codable, Identifiable {
    var id: UUID = UUID()
    let timestamp: Date
    let rawText: String
    let polishedText: String?
    let targetApp: String?
    let wasInserted: Bool
}

@MainActor
final class HistoryStore: ObservableObject {
    @Published var entries: [HistoryEntry] = []
    private let fileURL: URL
    private let maxEntries = 1000

    init() {
        self.fileURL = FileLocations.historyFile
        load()
    }

    func load() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? decoder.decode([HistoryEntry].self, from: data)
        else { return }
        entries = decoded
    }

    func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(entries) else { return }
        try? data.write(to: fileURL, options: [.atomic])
    }

    func add(_ entry: HistoryEntry) {
        entries.insert(entry, at: 0)
        prune()
        save()
    }

    func search(_ query: String) -> [HistoryEntry] {
        let lowered = query.lowercased()
        return entries.filter { entry in
            entry.rawText.localizedCaseInsensitiveContains(lowered)
                || (entry.polishedText?.localizedCaseInsensitiveContains(lowered) ?? false)
        }
    }

    func prune() {
        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        entries = entries.filter { $0.timestamp > cutoff }
        if entries.count > maxEntries {
            entries = Array(entries.prefix(maxEntries))
        }
    }
}
