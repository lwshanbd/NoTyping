import Foundation

struct NormalizedResult {
    let text: String
    let appliedReplacements: [(spoken: String, written: String)]
}

struct TextNormalizer {
    func normalize(text: String, vocabulary: [VocabularyEntry]) -> NormalizedResult {
        var result = text
        var appliedReplacements: [(spoken: String, written: String)] = []

        for entry in vocabulary where entry.enabled {
            for spokenForm in entry.spokenForms {
                guard !spokenForm.isEmpty else { continue }

                let range = result.range(of: spokenForm, options: [.caseInsensitive])
                if range != nil {
                    // Replace all occurrences case-insensitively
                    var searchRange = result.startIndex..<result.endIndex
                    while let found = result.range(of: spokenForm, options: [.caseInsensitive], range: searchRange) {
                        result.replaceSubrange(found, with: entry.writtenForm)
                        appliedReplacements.append((spoken: spokenForm, written: entry.writtenForm))
                        // Advance search range past the replacement
                        let newStart = result.index(found.lowerBound, offsetBy: entry.writtenForm.count, limitedBy: result.endIndex) ?? result.endIndex
                        searchRange = newStart..<result.endIndex
                    }
                }
            }
        }

        // Collapse multiple whitespace to single space
        result = result.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        // Trim leading/trailing whitespace
        result = result.trimmingCharacters(in: .whitespacesAndNewlines)

        return NormalizedResult(text: result, appliedReplacements: appliedReplacements)
    }
}
