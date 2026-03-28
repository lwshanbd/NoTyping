import Foundation

struct VocabularyEntry: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var writtenForm: String
    var spokenForms: [String]
    var enabled: Bool = true

    var searchableText: String {
        ([writtenForm] + spokenForms).joined(separator: " ").lowercased()
    }
}
