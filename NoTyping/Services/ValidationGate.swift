import Foundation

struct ValidationResult {
    let text: String
    let passed: Bool
    let failureReason: String?
}

struct ValidationGate {
    static let shortTextThreshold = 20
    static let upperLengthMultiplier = 1.5
    static let lowerLengthMultiplier = 0.3
    static let minimumTokenOverlap = 0.3
    static let injectionPrefixes = [
        "Here is", "Here's", "Sure", "Of course", "Certainly",
        "好的", "以下是", "当然", "没问题",
    ]

    func validate(original: String, polished: String) -> ValidationResult {
        // 1. Length check (skip for short texts)
        if original.count >= Self.shortTextThreshold {
            if polished.count > Int(Double(original.count) * Self.upperLengthMultiplier) {
                return ValidationResult(text: original, passed: false, failureReason: "output too long")
            }
            if polished.count < Int(Double(original.count) * Self.lowerLengthMultiplier) {
                return ValidationResult(text: original, passed: false, failureReason: "output too short")
            }
        }

        // 2. Token overlap check
        let originalTokens = Set(tokenize(original))
        if !originalTokens.isEmpty {
            let polishedTokens = Set(tokenize(polished))
            let overlapCount = originalTokens.intersection(polishedTokens).count
            let overlap = Double(overlapCount) / Double(originalTokens.count)
            if overlap < Self.minimumTokenOverlap {
                return ValidationResult(text: original, passed: false, failureReason: "token overlap too low")
            }
        }

        // 3. Prefix detection
        let lowercasedPolished = polished.lowercased()
        let trimmedPolished = polished.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in Self.injectionPrefixes {
            let lowercasedPrefix = prefix.lowercased()
            // For English prefixes, case-insensitive
            if lowercasedPolished.hasPrefix(lowercasedPrefix) {
                return ValidationResult(text: original, passed: false, failureReason: "detected LLM response prefix")
            }
            // For Chinese prefixes, check with trailing punctuation stripped
            if trimmedPolished.hasPrefix(prefix) {
                return ValidationResult(text: original, passed: false, failureReason: "detected LLM response prefix")
            }
            // Check prefix followed by common trailing punctuation (Chinese)
            let chinesePunctuation: [Character] = ["：", ":", "，", ",", "、", "！", "!", "。", "."]
            for punct in chinesePunctuation {
                if trimmedPolished.hasPrefix("\(prefix)\(punct)") {
                    return ValidationResult(text: original, passed: false, failureReason: "detected LLM response prefix")
                }
            }
        }

        // 4. All checks passed
        return ValidationResult(text: polished, passed: true, failureReason: nil)
    }

    private func tokenize(_ text: String) -> [String] {
        var tokens: [String] = []
        var currentWord: [Character] = []

        for scalar in text.unicodeScalars {
            let value = scalar.value
            // CJK Unified Ideographs (0x4E00-0x9FFF) and Extension A (0x3400-0x4DBF)
            if (0x4E00...0x9FFF).contains(value) || (0x3400...0x4DBF).contains(value) {
                // Flush any accumulated Latin word
                if !currentWord.isEmpty {
                    tokens.append(String(currentWord).lowercased())
                    currentWord.removeAll()
                }
                tokens.append(String(scalar))
            } else if scalar.properties.isAlphabetic && scalar.value < 0x3000 {
                // Latin alphabetic characters
                currentWord.append(Character(scalar))
            } else if scalar == " " || scalar == "\t" || scalar == "\n" {
                // Whitespace: flush current word
                if !currentWord.isEmpty {
                    tokens.append(String(currentWord).lowercased())
                    currentWord.removeAll()
                }
            } else {
                // Digits and punctuation: skip, but flush current word
                if !currentWord.isEmpty {
                    tokens.append(String(currentWord).lowercased())
                    currentWord.removeAll()
                }
            }
        }

        // Flush remaining word
        if !currentWord.isEmpty {
            tokens.append(String(currentWord).lowercased())
        }

        return tokens
    }
}
