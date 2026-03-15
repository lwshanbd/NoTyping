import Combine
import Foundation

@MainActor
protocol VocabularyServiceProtocol: AnyObject {
    var entries: [VocabularyEntry] { get }
    func snapshot() -> [VocabularyEntry]
}

@MainActor
final class VocabularyService: ObservableObject, VocabularyServiceProtocol {
    @Published private(set) var entries: [VocabularyEntry] = []
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    init() {
        decoder.dateDecodingStrategy = .iso8601
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        load()
    }

    func snapshot() -> [VocabularyEntry] {
        entries
    }

    func upsert(_ entry: VocabularyEntry) {
        if let index = entries.firstIndex(where: { $0.id == entry.id }) {
            entries[index] = entry
        } else {
            entries.append(entry)
        }
        persist()
    }

    func delete(_ entry: VocabularyEntry) {
        entries.removeAll { $0.id == entry.id }
        persist()
    }

    func replaceAll(with entries: [VocabularyEntry]) {
        self.entries = entries.sorted { $0.writtenForm.localizedCaseInsensitiveCompare($1.writtenForm) == .orderedAscending }
        persist()
    }

    func importPreview(from url: URL) throws -> VocabularyImportPreview {
        let imported: [VocabularyEntry]
        if url.pathExtension.lowercased() == "json" {
            let data = try Data(contentsOf: url)
            imported = try decoder.decode([VocabularyEntry].self, from: data)
        } else {
            imported = try parseCSV(url: url)
        }

        let decisions = imported.map { entry in
            if entries.contains(where: {
                $0.writtenForm.caseInsensitiveCompare(entry.writtenForm) == .orderedSame &&
                $0.languageScope == entry.languageScope
            }) {
                VocabularyImportDecision(entry: entry, action: .update)
            } else {
                VocabularyImportDecision(entry: entry, action: .create)
            }
        }
        return VocabularyImportPreview(decisions: decisions)
    }

    func apply(preview: VocabularyImportPreview) {
        var next = entries
        for decision in preview.decisions where decision.action != .skip {
            if let index = next.firstIndex(where: {
                $0.writtenForm.caseInsensitiveCompare(decision.entry.writtenForm) == .orderedSame &&
                $0.languageScope == decision.entry.languageScope
            }) {
                next[index] = decision.entry
            } else {
                next.append(decision.entry)
            }
        }
        replaceAll(with: next)
    }

    func exportJSON(to url: URL) throws {
        let data = try encoder.encode(entries)
        try data.write(to: url, options: [.atomic])
    }

    func exportCSV(to url: URL) throws {
        let header = "writtenForm,spokenForms,languageScope,enabled,caseSensitive,priority,notes\n"
        let rows = entries.map { entry in
            [
                quote(entry.writtenForm),
                quote(entry.spokenForms.joined(separator: "|")),
                quote(entry.languageScope.rawValue),
                quote(String(entry.enabled)),
                quote(String(entry.caseSensitive)),
                quote(String(entry.priority)),
                quote(entry.notes)
            ].joined(separator: ",")
        }
        let csv = header + rows.joined(separator: "\n")
        try csv.write(to: url, atomically: true, encoding: .utf8)
    }

    private func load() {
        if let data = try? Data(contentsOf: FileLocations.vocabularyURL),
           let stored = try? decoder.decode([VocabularyEntry].self, from: data) {
            entries = stored
        } else {
            entries = [
                VocabularyEntry(writtenForm: "NCCL", spokenForms: ["N C C L", "nccl"], languageScope: .both, priority: 100),
                VocabularyEntry(writtenForm: "CUDA", spokenForms: ["cue duh", "cuda"], languageScope: .both, priority: 100),
                VocabularyEntry(writtenForm: "PyTorch", spokenForms: ["pytorch", "pie torch"], languageScope: .both, priority: 100),
                VocabularyEntry(writtenForm: "LLaMA", spokenForms: ["llama"], languageScope: .both, priority: 100)
            ]
            persist()
        }
    }

    private func persist() {
        guard let data = try? encoder.encode(entries) else { return }
        try? data.write(to: FileLocations.vocabularyURL, options: [.atomic])
    }

    private func parseCSV(url: URL) throws -> [VocabularyEntry] {
        let contents = try String(contentsOf: url, encoding: .utf8)
        let lines = contents.split(whereSeparator: \.isNewline)
        return lines.dropFirst().compactMap { line in
            let fields = splitCSVLine(String(line))
            guard fields.count >= 7 else { return nil }
            return VocabularyEntry(
                writtenForm: fields[0],
                spokenForms: fields[1].split(separator: "|").map { String($0) },
                languageScope: LanguageScope(rawValue: fields[2]) ?? .both,
                enabled: Bool(fields[3]) ?? true,
                caseSensitive: Bool(fields[4]) ?? true,
                priority: Int(fields[5]) ?? 100,
                notes: fields[6]
            )
        }
    }

    private func splitCSVLine(_ line: String) -> [String] {
        var result: [String] = []
        var current = ""
        var inQuotes = false
        for character in line {
            switch character {
            case "\"":
                inQuotes.toggle()
            case "," where !inQuotes:
                result.append(current)
                current = ""
            default:
                current.append(character)
            }
        }
        result.append(current)
        return result
    }

    private func quote(_ value: String) -> String {
        "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}
