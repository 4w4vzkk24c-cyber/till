import Foundation

/// Fixed calendar/time zone so tests are independent of the host. US Central:
/// 2026 DST starts Sun Mar 8 and ends Sun Nov 1.
enum TestClock {
    static let zone = TimeZone(identifier: "America/Chicago")!

    static var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = zone
        c.locale = Locale(identifier: "en_US_POSIX")
        return c
    }

    static func at(_ y: Int, _ mo: Int, _ d: Int, _ h: Int = 0, _ mi: Int = 0, _ s: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi, second: s))!
    }

    static func parts(_ date: Date) -> DateComponents {
        calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
    }

    /// Tue 2026-11-03 10:00 local.
    static var now: Date { at(2026, 11, 3, 10, 0) }
}
