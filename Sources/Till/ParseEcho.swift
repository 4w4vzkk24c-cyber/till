import Foundation

/// Human readback of the deadline field, shown under it while typing (spec A2). Pure:
/// it reuses `NaturalDeadline.parse` and returns nil for anything that does not parse,
/// so a past or unrecognised input shows nothing (the error still appears on submit).
enum ParseEcho {
    static func text(for input: String, now: Date, calendar: Calendar, timeZone: TimeZone) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let parsed = try? NaturalDeadline.parse(
                trimmed, now: now, calendar: calendar, timeZone: timeZone)
        else { return nil }

        var cal = calendar
        cal.timeZone = timeZone

        if parsed.timePromptRequired {
            return "\(dayLabel(parsed.deadline, now: now, calendar: cal, allowRelative: false)), then you pick a time"
        }
        let day = dayLabel(parsed.deadline, now: now, calendar: cal, allowRelative: true)
        let time = clock(parsed.deadline, calendar: cal)
        return "\(day) \(time), \(relative(parsed.deadline.timeIntervalSince(now)))"
    }

    private static func dayLabel(_ date: Date, now: Date, calendar cal: Calendar, allowRelative: Bool) -> String {
        let days = cal.dateComponents(
            [.day], from: cal.startOfDay(for: now), to: cal.startOfDay(for: date)).day ?? 0
        if allowRelative {
            if days == 0 { return "Today" }
            if days == 1 { return "Tomorrow" }
            if (2...6).contains(days) {
                return cal.weekdaySymbols[cal.component(.weekday, from: date) - 1]
            }
        }
        let parts = cal.dateComponents([.month, .day], from: date)
        return "\(cal.shortMonthSymbols[(parts.month ?? 1) - 1]) \(parts.day ?? 1)"
    }

    private static func clock(_ date: Date, calendar cal: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = cal
        formatter.timeZone = cal.timeZone
        formatter.locale = cal.locale ?? .current
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        // Recent macOS puts a narrow no-break space before AM/PM; keep the text plain.
        return formatter.string(from: date)
            .replacingOccurrences(of: "\u{202F}", with: " ")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
    }

    private static func relative(_ interval: TimeInterval) -> String {
        let total = Int(interval.rounded(.down))
        if total >= 86_400 {
            let (d, h) = (total / 86_400, (total % 86_400) / 3_600)
            return h == 0 ? "in \(d) d" : "in \(d) d \(h) h"
        }
        if total >= 3_600 {
            let (h, m) = (total / 3_600, (total % 3_600) / 60)
            return m == 0 ? "in \(h) h" : "in \(h) h \(m) min"
        }
        return "in \(max(1, total / 60)) min"
    }
}
