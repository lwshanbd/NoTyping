import Combine
import Foundation

@MainActor
final class VocabularyStore: ObservableObject {
    @Published var entries: [VocabularyEntry] = []
    private let fileURL: URL

    init() {
        self.fileURL = FileLocations.vocabularyFile
        load()
    }

    func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([VocabularyEntry].self, from: data)
        else { return }
        entries = decoded
    }

    func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(entries) else { return }
        try? data.write(to: fileURL, options: [.atomic])
    }

    func add(_ entry: VocabularyEntry) {
        entries.append(entry)
        save()
    }

    func remove(at offsets: IndexSet) {
        entries.remove(atOffsets: offsets)
        save()
    }

    func update(_ entry: VocabularyEntry) {
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        entries[index] = entry
        save()
    }

    func exportJSON() -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try? encoder.encode(entries)
    }

    func importJSON(_ data: Data) throws {
        let incoming = try JSONDecoder().decode([VocabularyEntry].self, from: data)
        let existingForms = Set(entries.map(\.writtenForm))
        let newEntries = incoming.filter { !existingForms.contains($0.writtenForm) }
        entries.append(contentsOf: newEntries)
        save()
    }
}
