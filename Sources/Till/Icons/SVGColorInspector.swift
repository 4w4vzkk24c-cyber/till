import Foundation

/// Detects whether an SVG is single-colour ("monotone") by reading its colour values
/// (design §5 step 2). The SVG is fetched with `color=#ffffff`, so a monotone icon has only
/// white / currentColor / none; a palette icon keeps its own non-white fills. Pure.
enum SVGColorInspector {
    private static let properties = ["stop-color", "flood-color", "lighting-color", "stroke", "fill"]
    private static let whites: Set<String> = [
        "#fff", "#ffff", "#ffffff", "#ffffffff", "white", "rgb(255,255,255)",
    ]
    private static let ignorable: Set<String> = [
        "", "none", "currentcolor", "inherit", "transparent", "initial", "unset",
        "context-fill", "context-stroke",
    ]

    static func isMonotone(_ svg: String) -> Bool {
        for raw in colorValues(in: svg) {
            let value = raw.replacingOccurrences(of: " ", with: "")
            if ignorable.contains(value) || value.hasPrefix("url(") { continue }
            if whites.contains(value) { continue }
            return false
        }
        return true
    }

    /// Values of colour-bearing attributes and CSS declarations, lowercased and trimmed.
    static func colorValues(in svg: String) -> [String] {
        let s = Array(svg.lowercased())
        var out: [String] = []
        var i = 0
        while i < s.count {
            var matched = false
            for property in properties {
                let name = Array(property)
                guard i + name.count <= s.count, Array(s[i..<(i + name.count)]) == name,
                      boundaryBefore(s, i) else { continue }
                var j = i + name.count
                while j < s.count, s[j].isWhitespace { j += 1 }
                guard j < s.count, s[j] == "=" || s[j] == ":" else { continue }
                let isAttribute = s[j] == "="
                j += 1
                while j < s.count, s[j].isWhitespace { j += 1 }
                var value = ""
                if isAttribute, j < s.count, s[j] == "\"" || s[j] == "'" {
                    let quote = s[j]
                    j += 1
                    while j < s.count, s[j] != quote { value.append(s[j]); j += 1 }
                } else {
                    while j < s.count, !";\"'}".contains(s[j]) { value.append(s[j]); j += 1 }
                }
                out.append(value.trimmingCharacters(in: .whitespacesAndNewlines))
                i = j
                matched = true
                break
            }
            if !matched { i += 1 }
        }
        return out
    }

    private static func boundaryBefore(_ s: [Character], _ i: Int) -> Bool {
        guard i > 0 else { return true }
        let previous = s[i - 1]
        return !(previous.isLetter || previous.isNumber || previous == "-")
    }
}
