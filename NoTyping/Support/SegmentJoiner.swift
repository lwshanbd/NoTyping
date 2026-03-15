import Foundation

enum SegmentJoiner {
    static func join(_ segments: [String]) -> String {
        var result = ""

        for rawSegment in segments {
            let segment = rawSegment.trimmed
            guard !segment.isEmpty else { continue }

            if result.isEmpty {
                result = segment
                continue
            }

            if shouldJoinWithoutSpace(previous: result, next: segment) {
                result += segment
            } else {
                result += " " + segment
            }
        }

        return result
    }

    private static func shouldJoinWithoutSpace(previous: String, next: String) -> Bool {
        guard let last = previous.last, let first = next.first else { return true }
        if last == "\n" || first == "\n" { return true }
        if previous.containsCJK || next.containsCJK { return true }
        if CharacterSet.punctuationCharacters.contains(first.unicodeScalars.first!) { return true }
        if last == "(" || last == "[" || last == "{" || first == ")" || first == "]" || first == "}" {
            return true
        }
        return false
    }
}
