import Foundation

struct VocabularyEntry: Identifiable, Codable, Equatable {
    var id: UUID
    var writtenForm: String
    var spokenForms: [String]
    var languageScope: LanguageScope
    var enabled: Bool
    var caseSensitive: Bool
    var priority: Int
    var notes: String
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        writtenForm: String,
        spokenForms: [String],
        languageScope: LanguageScope,
        enabled: Bool = true,
        caseSensitive: Bool = true,
        priority: Int = 100,
        notes: String = "",
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.writtenForm = writtenForm
        self.spokenForms = spokenForms
        self.languageScope = languageScope
        self.enabled = enabled
        self.caseSensitive = caseSensitive
        self.priority = priority
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var searchableText: String {
        ([writtenForm] + spokenForms + [notes]).joined(separator: " ").lowercased()
    }
}

struct ProtectedTerm: Equatable, Hashable {
    var value: String
}

struct VocabularyImportDecision: Identifiable, Equatable {
    enum Action: String, Equatable {
        case create
        case update
        case skip
    }

    var id = UUID()
    var entry: VocabularyEntry
    var action: Action
}

struct VocabularyImportPreview: Equatable {
    var decisions: [VocabularyImportDecision]
}

struct NormalizedTranscript: Equatable {
    var text: String
    var protectedTerms: [ProtectedTerm]
    var decisions: [String]
}
