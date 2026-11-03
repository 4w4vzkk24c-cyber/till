import Foundation
import Testing
@testable import Till

@Suite struct ParseEchoTests {
    // TestClock.now is Tue 2026-11-03 10:00 America/Chicago.
    private func echo(_ s: String) -> String? {
        ParseEcho.text(for: s, now: TestClock.now, calendar: TestClock.calendar, timeZone: TestClock.zone)
    }

    @Test func quickTimer() { #expect(echo("in 20 min") == "Today 10:20 AM, in 20 min") }

    @Test func weekdayAndClock() { #expect(echo("Fri 5pm") == "Friday 5:00 PM, in 3 d 7 h") }

    @Test func tomorrowUnderADay() { #expect(echo("tomorrow 9am") == "Tomorrow 9:00 AM, in 23 h") }

    @Test func hoursAndMinutes() { #expect(echo("in 90 min") == "Today 11:30 AM, in 1 h 30 min") }

    @Test func dateOnlyAsksForATimeNext() { #expect(echo("Nov 15") == "Nov 15, then you pick a time") }

    @Test func hostileInputShowsNothing() {                    // Review Focus 3
        for s in ["", "   ", "gibberish", "today 9am", "in 0 min", "yesterday 5pm"] {
            #expect(echo(s) == nil)
        }
    }
}
