import Foundation

extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var collapsedWhitespace: String {
        replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmed
    }

    func foldedForVocabulary(caseSensitive: Bool) -> String {
        let base = caseSensitive ? self : lowercased()
        return base
            .replacingOccurrences(of: "[\\s\\-_.]+", with: "", options: .regularExpression)
            .folding(options: [.diacriticInsensitive, .widthInsensitive], locale: .current)
    }

    var containsCJK: Bool {
        unicodeScalars.contains { scalar in
            (0x4E00...0x9FFF).contains(Int(scalar.value)) ||
            (0x3400...0x4DBF).contains(Int(scalar.value)) ||
            (0x3000...0x303F).contains(Int(scalar.value))
        }
    }
}
