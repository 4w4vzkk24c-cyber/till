import Foundation

/// Spoken (VoiceOver) text for chips (addendum A1.1 item 5). Pure.
enum Spoken {
    static func duration(seconds: Int) -> String {
        func unit(_ n: Int, _ word: String) -> String { "\(n) \(word)\(n == 1 ? "" : "s")" }
        let total = max(0, seconds)
        if total >= 86_400 {
            let d = total / 86_400
            let h = (total % 86_400) / 3_600
            return h == 0 ? unit(d, "day") : "\(unit(d, "day")) \(unit(h, "hour"))"
        }
        if total >= 3_600 {
            let h = total / 3_600
            let m = (total % 3_600) / 60
            return m == 0 ? unit(h, "hour") : "\(unit(h, "hour")) \(unit(m, "minute"))"
        }
        if total >= 60 {
            let m = total / 60
            let s = total % 60
            return s == 0 ? unit(m, "minute") : "\(unit(m, "minute")) \(unit(s, "second"))"
        }
        return unit(total, "second")
    }

    static func label(title: String?, state: ChipState, remaining: TimeInterval) -> String {
        let trimmed = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let name = trimmed.isEmpty ? "Timer" : trimmed
        switch state {
        case .overdue:
            let over = Int((-remaining).rounded(.down))
            let phrase = over < 60 ? "less than a minute overdue" : "\(duration(seconds: over)) overdue"
            return "\(name), \(phrase)"
        case .paused:
            return "\(name), paused, \(duration(seconds: Int(max(0, remaining).rounded(.down)))) remaining"
        case .approaching:
            return "\(name), \(duration(seconds: Int(max(0, remaining).rounded(.down)))) remaining, approaching"
        case .clean:
            return "\(name), \(duration(seconds: Int(max(0, remaining).rounded(.down)))) remaining"
        }
    }
}
