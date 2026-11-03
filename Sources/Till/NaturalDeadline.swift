import Foundation

public struct ParsedDeadline: Sendable, Equatable {
    public enum Kind: String, Sendable { case quick, dated }

    public let deadline: Date
    public let approachWindow: TimeInterval
    public let kind: Kind
    /// True only for plain-date input: `deadline` is then the date at the suggested
    /// 09:00 local time and the creation flow must prompt for a time (design §5, §7.1).
    public let timePromptRequired: Bool

    public init(deadline: Date, approachWindow: TimeInterval, kind: Kind, timePromptRequired: Bool) {
        self.deadline = deadline
        self.approachWindow = approachWindow
        self.kind = kind
        self.timePromptRequired = timePromptRequired
    }
}

public enum NaturalDeadlineError: Error, Equatable, Sendable {
    case empty
    case unrecognized
    case repeatedUnit
    case nonPositiveAmount
    case amountTooLarge
    case missingTime
    case invalidTime
    case invalidDate
    case alreadyPassed

    /// Inline hint text shown in the add field. No dialogs.
    public var hint: String {
        switch self {
        case .empty: return "Try “in 20 min”, “Fri 5pm” or “Nov 15”."
        case .unrecognized: return "Try “in 20 min”, “Fri 5pm” or “Nov 15”."
        case .repeatedUnit: return "Use each unit once, e.g. “1 day 2 hours”."
        case .nonPositiveAmount: return "Use an amount of 1 or more."
        case .amountTooLarge: return "That amount is too large."
        case .missingTime: return "Add a time, e.g. “Fri 5pm” or “tomorrow 9am”."
        case .invalidTime: return "Use a time like 5pm, 5:30pm or 12am."
        case .invalidDate: return "That date doesn’t exist, e.g. “Nov 15”."
        case .alreadyPassed: return "That time has already passed."
        }
    }
}

/// Pure natural-language deadline parser (design §7.1). Stateless, no clock inside.
public enum NaturalDeadline {
    public static let quickApproachWindow: TimeInterval = 30 * 60
    public static let datedApproachWindow: TimeInterval = 2 * 60 * 60
    public static let suggestedHour = 9
    static let maxAmount = 100_000

    public static func parse(
        _ input: String, now: Date, calendar: Calendar, timeZone: TimeZone
    ) throws -> ParsedDeadline {
        var cal = calendar
        cal.timeZone = timeZone

        let tokens = input.lowercased()
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
        guard let first = tokens.first else { throw NaturalDeadlineError.empty }
        let rest = Array(tokens.dropFirst())

        if first == "in" {
            return try parseQuick(rest, now: now, calendar: cal)
        }
        // "in" is optional: input that starts with a digit is a duration ("90 min",
        // "1 day 2 hours", "1h30m").
        if first.first.map(isDigit) == true {
            return try parseQuick(tokens, now: now, calendar: cal)
        }
        if first == "today" || first == "tomorrow" {
            let (hour, minute) = try parseClock(rest)
            let offset = first == "today" ? 0 : 1
            guard let moment = resolveMoment(dayOffset: offset, hour: hour, minute: minute, now: now, calendar: cal) else {
                throw NaturalDeadlineError.unrecognized
            }
            guard moment > now else { throw NaturalDeadlineError.alreadyPassed }
            return dated(moment)
        }
        if let weekday = weekdayNumber(first) {
            let (hour, minute) = try parseClock(rest)
            let today = cal.startOfDay(for: now)
            let current = cal.component(.weekday, from: today)
            let delta = (weekday - current + 7) % 7
            guard var moment = resolveMoment(dayOffset: delta, hour: hour, minute: minute, now: now, calendar: cal) else {
                throw NaturalDeadlineError.unrecognized
            }
            if moment <= now {
                guard let next = resolveMoment(dayOffset: delta + 7, hour: hour, minute: minute, now: now, calendar: cal) else {
                    throw NaturalDeadlineError.unrecognized
                }
                moment = next
            }
            return dated(moment)
        }
        if let month = monthNumber(first) {
            return try parsePlainDate(month: month, rest: rest, now: now, calendar: cal)
        }
        throw NaturalDeadlineError.unrecognized
    }

    /// Applies the user's chosen time to a plain-date result (the creation flow's time
    /// prompt). The result must be in the future.
    public static func applyingTime(
        hour: Int, minute: Int, to parsed: ParsedDeadline,
        now: Date, calendar: Calendar, timeZone: TimeZone
    ) throws -> ParsedDeadline {
        guard (0...23).contains(hour), (0...59).contains(minute) else {
            throw NaturalDeadlineError.invalidTime
        }
        var cal = calendar
        cal.timeZone = timeZone
        var comps = cal.dateComponents([.year, .month, .day], from: parsed.deadline)
        comps.hour = hour
        comps.minute = minute
        comps.second = 0
        guard let moment = cal.date(from: comps) else { throw NaturalDeadlineError.invalidTime }
        guard moment > now else { throw NaturalDeadlineError.alreadyPassed }
        return ParsedDeadline(
            deadline: moment, approachWindow: datedApproachWindow, kind: .dated,
            timePromptRequired: false)
    }

    // MARK: - Quick: [in] <N> <unit> [<N> <unit> ...]

    /// One or more amount/unit pairs, each unit at most once, in any order: "20 min",
    /// "1h30m", "1 day 2 hours", "1 hour and 30 minutes", "1 hour, 30 minutes". The pairs
    /// are added in one calendar step, so days keep wall-clock time across DST.
    private static func parseQuick(_ args: [String], now: Date, calendar cal: Calendar) throws -> ParsedDeadline {
        let text = args.filter { $0 != "and" }
            .joined(separator: " ")
            .replacingOccurrences(of: ",", with: " ")
        let chars = Array(text)
        var i = 0
        func skipSpaces() { while i < chars.count, chars[i].isWhitespace { i += 1 } }

        var components = DateComponents()
        var seen = Set<Calendar.Component>()
        skipSpaces()
        guard i < chars.count else { throw NaturalDeadlineError.unrecognized }

        while i < chars.count {
            guard isDigit(chars[i]) else { throw NaturalDeadlineError.unrecognized }
            var digits = ""
            while i < chars.count, isDigit(chars[i]) { digits.append(chars[i]); i += 1 }
            skipSpaces()
            var unit = ""
            while i < chars.count, chars[i].isLetter { unit.append(chars[i]); i += 1 }
            guard !unit.isEmpty else { throw NaturalDeadlineError.unrecognized }

            guard digits.count <= 6, let amount = Int(digits) else {
                throw NaturalDeadlineError.amountTooLarge
            }
            guard amount > 0 else { throw NaturalDeadlineError.nonPositiveAmount }
            guard amount <= maxAmount else { throw NaturalDeadlineError.amountTooLarge }

            let component: Calendar.Component
            switch unit {
            case "min", "m", "mins", "minute", "minutes": component = .minute
            case "h", "hr", "hour", "hours": component = .hour
            case "d", "day", "days": component = .day
            default: throw NaturalDeadlineError.unrecognized
            }
            guard seen.insert(component).inserted else { throw NaturalDeadlineError.repeatedUnit }
            components.setValue(amount, for: component)
            skipSpaces()
        }

        guard let deadline = cal.date(byAdding: components, to: now) else {
            throw NaturalDeadlineError.unrecognized
        }
        return ParsedDeadline(
            deadline: deadline, approachWindow: quickApproachWindow, kind: .quick,
            timePromptRequired: false)
    }

    // MARK: - Plain date: Mon D

    private static func parsePlainDate(
        month: Int, rest: [String], now: Date, calendar cal: Calendar
    ) throws -> ParsedDeadline {
        guard rest.count == 1, rest[0].allSatisfy(isDigit), rest[0].count <= 2,
              let day = Int(rest[0]) else {
            throw NaturalDeadlineError.unrecognized
        }
        guard (1...31).contains(day) else { throw NaturalDeadlineError.invalidDate }

        let today = cal.startOfDay(for: now)
        let currentYear = cal.component(.year, from: now)
        // Next occurrence: this year if the day is today or later, else next year.
        // Searches ahead so Feb 29 lands on the next leap year; Calendar is lenient and
        // rolls impossible dates over, so the components are verified.
        for year in currentYear...(currentYear + 8) {
            var comps = DateComponents()
            comps.year = year
            comps.month = month
            comps.day = day
            comps.hour = suggestedHour
            comps.minute = 0
            comps.second = 0
            guard let date = cal.date(from: comps) else { continue }
            let back = cal.dateComponents([.year, .month, .day], from: date)
            guard back.year == year, back.month == month, back.day == day else { continue }
            guard cal.startOfDay(for: date) >= today else { continue }
            return ParsedDeadline(
                deadline: date, approachWindow: datedApproachWindow, kind: .dated,
                timePromptRequired: true)
        }
        throw NaturalDeadlineError.invalidDate
    }

    // MARK: - Clock

    /// `[H][:MM] am|pm`, optionally with a space before am/pm ("5 pm").
    private static func parseClock(_ tokens: [String]) throws -> (hour: Int, minute: Int) {
        let joined = tokens.joined()
        guard !joined.isEmpty else { throw NaturalDeadlineError.missingTime }
        let isPM: Bool
        if joined.hasSuffix("pm") {
            isPM = true
        } else if joined.hasSuffix("am") {
            isPM = false
        } else {
            throw NaturalDeadlineError.invalidTime
        }
        let body = joined.dropLast(2)
        let parts = body.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 1 || parts.count == 2 else { throw NaturalDeadlineError.invalidTime }
        guard !parts[0].isEmpty, parts[0].count <= 2, parts[0].allSatisfy(isDigit),
              let hour12 = Int(parts[0]), (1...12).contains(hour12) else {
            throw NaturalDeadlineError.invalidTime
        }
        var minute = 0
        if parts.count == 2 {
            guard parts[1].count == 2, parts[1].allSatisfy(isDigit),
                  let m = Int(parts[1]), (0...59).contains(m) else {
                throw NaturalDeadlineError.invalidTime
            }
            minute = m
        }
        return (hour12 % 12 + (isPM ? 12 : 0), minute)
    }

    // MARK: - Helpers

    private static func dated(_ moment: Date) -> ParsedDeadline {
        ParsedDeadline(
            deadline: moment, approachWindow: datedApproachWindow, kind: .dated,
            timePromptRequired: false)
    }

    private static func resolveMoment(
        dayOffset: Int, hour: Int, minute: Int, now: Date, calendar cal: Calendar
    ) -> Date? {
        guard let day = cal.date(byAdding: .day, value: dayOffset, to: cal.startOfDay(for: now)) else {
            return nil
        }
        var comps = cal.dateComponents([.year, .month, .day], from: day)
        comps.hour = hour
        comps.minute = minute
        comps.second = 0
        return cal.date(from: comps)
    }

    private static func isDigit(_ c: Character) -> Bool { c.isASCII && c.isNumber }

    /// Calendar weekday numbers: 1 = Sunday ... 7 = Saturday.
    private static func weekdayNumber(_ s: String) -> Int? {
        switch s {
        case "sun", "sunday": return 1
        case "mon", "monday": return 2
        case "tue", "tuesday": return 3
        case "wed", "wednesday": return 4
        case "thu", "thursday": return 5
        case "fri", "friday": return 6
        case "sat", "saturday": return 7
        default: return nil
        }
    }

    private static func monthNumber(_ s: String) -> Int? {
        switch s {
        case "jan", "january": return 1
        case "feb", "february": return 2
        case "mar", "march": return 3
        case "apr", "april": return 4
        case "may": return 5
        case "jun", "june": return 6
        case "jul", "july": return 7
        case "aug", "august": return 8
        case "sep", "sept", "september": return 9
        case "oct", "october": return 10
        case "nov", "november": return 11
        case "dec", "december": return 12
        default: return nil
        }
    }
}
