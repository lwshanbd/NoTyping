import Foundation

final class TranscriptNormalizer {
    func normalize(
        transcript: String,
        entries: [VocabularyEntry],
        languageMode: LanguageMode
    ) -> NormalizedTranscript {
        let activeEntries = entries
            .filter(\.enabled)
            .sorted { lhs, rhs in
                if lhs.priority == rhs.priority {
                    return lhs.writtenForm.count > rhs.writtenForm.count
                }
                return lhs.priority > rhs.priority
            }

        var text = transcript
        var decisions: [String] = []
        var protectedTerms = Set<ProtectedTerm>()

        for entry in activeEntries where matches(languageMode: languageMode, scope: entry.languageScope) {
            let aliases = Array(Set(entry.spokenForms + [entry.writtenForm]))
                .filter { !$0.trimmed.isEmpty }
                .sorted { $0.count > $1.count }

            for alias in aliases {
                if alias.count == 1, alias.range(of: "[A-Za-z]", options: .regularExpression) != nil {
                    continue
                }
                let replacementCount = replace(alias: alias, with: entry.writtenForm, in: &text, caseSensitive: entry.caseSensitive)
                if replacementCount > 0 {
                    decisions.append("Mapped '\(alias)' -> '\(entry.writtenForm)' x\(replacementCount)")
                    protectedTerms.insert(ProtectedTerm(value: entry.writtenForm))
                }
            }
        }

        text = collapseKnownAcronyms(in: text, entries: activeEntries, protectedTerms: &protectedTerms, decisions: &decisions)
        return NormalizedTranscript(text: text.collapsedWhitespace, protectedTerms: Array(protectedTerms).sorted { $0.value < $1.value }, decisions: decisions)
    }

    func preview(text: String, entries: [VocabularyEntry], languageMode: LanguageMode) -> String {
        normalize(transcript: text, entries: entries, languageMode: languageMode).text
    }

    func technicalProtectedTerms(
        in text: String,
        profile: DictationProfile,
        appCategory: AppCategory
    ) -> [ProtectedTerm] {
        guard shouldProtectTechnicalTokens(profile: profile, appCategory: appCategory) else { return [] }

        let patterns = [
            "https?://\\S+",
            "(?<![A-Za-z0-9])(?:~|\\.{1,2}|/)[^\\s]+",
            "(?<!\\w)--?[A-Za-z0-9][A-Za-z0-9_-]*(?:=[^\\s]+)?",
            "\\b[A-Za-z_][A-Za-z0-9_]*_[A-Za-z0-9_]+\\b",
            "\\b[a-z]+(?:[A-Z][A-Za-z0-9]+)+\\b",
            "\\b[A-Za-z0-9]+-[A-Za-z0-9-]+\\b",
            "\\b[A-Z]{2,}[A-Z0-9]*\\b",
            "\\b\\d+(?:[./:-]\\d+)+\\b"
        ]

        let terms = Set(patterns.flatMap { matches(for: $0, in: text) })
            .filter { shouldKeepTechnicalToken($0) }
            .map(ProtectedTerm.init(value:))
            .sorted { $0.value < $1.value }

        return terms
    }

    func suggestsLiteralRewriteBypass(
        text: String,
        protectedTerms: [ProtectedTerm],
        profile: DictationProfile,
        appCategory: AppCategory
    ) -> Bool {
        guard shouldProtectTechnicalTokens(profile: profile, appCategory: appCategory) else { return false }
        if text.contains("`") || text.contains("&&") || text.contains("||") || text.contains("::") {
            return true
        }
        if text.contains("|") || text.contains(">") || text.contains("<") {
            return true
        }
        if text.contains("{") || text.contains("}") || text.contains("[") || text.contains("]") {
            return true
        }
        return protectedTerms.count >= 4
    }

    private func replace(alias: String, with replacement: String, in text: inout String, caseSensitive: Bool) -> Int {
        let escaped = NSRegularExpression.escapedPattern(for: alias)
        let relaxed = escaped.replacingOccurrences(of: "\\ ", with: "[\\\\s._-]+")
        let pattern = alias.contains(where: \.isLetter) ? "(?<![A-Za-z0-9])\(relaxed)(?![A-Za-z0-9])" : relaxed
        guard let regex = try? NSRegularExpression(pattern: pattern, options: caseSensitive ? [] : [.caseInsensitive]) else {
            return 0
        }
        let range = NSRange(location: 0, length: text.utf16.count)
        let matches = regex.matches(in: text, options: [], range: range)
        guard !matches.isEmpty else { return 0 }
        text = regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: replacement)
        return matches.count
    }

    private func collapseKnownAcronyms(
        in text: String,
        entries: [VocabularyEntry],
        protectedTerms: inout Set<ProtectedTerm>,
        decisions: inout [String]
    ) -> String {
        let lookup = Dictionary(uniqueKeysWithValues: entries.map { ($0.writtenForm.uppercased(), $0) })
        guard let regex = try? NSRegularExpression(pattern: "(?<![A-Za-z])(?:[A-Za-z](?:\\s+|[-_.])?){2,}(?![A-Za-z])", options: []) else {
            return text
        }

        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length)).reversed()
        var output = text

        for match in matches {
            let candidate = nsText.substring(with: match.range)
            let collapsed = candidate.replacingOccurrences(of: "[\\s._-]+", with: "", options: .regularExpression).uppercased()
            guard let entry = lookup[collapsed] else { continue }
            let range = Range(match.range, in: output)!
            output.replaceSubrange(range, with: entry.writtenForm)
            protectedTerms.insert(ProtectedTerm(value: entry.writtenForm))
            decisions.append("Collapsed acronym '\(candidate)' -> '\(entry.writtenForm)'")
        }

        return output
    }

    private func matches(languageMode: LanguageMode, scope: LanguageScope) -> Bool {
        switch (languageMode, scope) {
        case (.auto, _), (_, .both):
            true
        case (.english, .english), (.simplifiedChinese, .simplifiedChinese):
            true
        default:
            false
        }
    }

    private func shouldProtectTechnicalTokens(profile: DictationProfile, appCategory: AppCategory) -> Bool {
        profile == .codeAware || appCategory == .code || appCategory == .terminal
    }

    private func matches(for pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return [] }
        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)
        return regex.matches(in: text, options: [], range: range).compactMap {
            guard let matchRange = Range($0.range, in: text) else { return nil }
            return sanitizeTechnicalToken(String(text[matchRange]))
        }
    }

    private func shouldKeepTechnicalToken(_ token: String) -> Bool {
        guard token.count > 1 else { return false }
        if token.range(of: "\\s", options: .regularExpression) != nil { return false }
        if token.allSatisfy(\.isNumber) { return false }
        return true
    }

    private func sanitizeTechnicalToken(_ token: String) -> String {
        let trailingPunctuation = CharacterSet(charactersIn: ",.;:!?)]}\"\u{3002}\u{FF0C}\u{FF01}\u{FF1F}\u{FF1B}")
        var scalars = Array(token.unicodeScalars)
        while let last = scalars.last, trailingPunctuation.contains(last) {
            scalars.removeLast()
        }
        return String(String.UnicodeScalarView(scalars))
    }
}
