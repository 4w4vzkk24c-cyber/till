import Foundation
import Testing
@testable import Till

@Suite struct NaturalDeadlineTests {
    typealias C = TestClock

    private func parse(_ s: String, now: Date = C.now) throws -> ParsedDeadline {
        try NaturalDeadline.parse(s, now: now, calendar: C.calendar, timeZone: C.zone)
    }

    // MARK: quick

    @Test func quickMinutes() throws {
        let p = try parse("in 20 min")
        #expect(p.deadline == C.now.addingTimeInterval(20 * 60))
        #expect(p.kind == .quick)
        #expect(p.approachWindow == 1800)
        #expect(p.timePromptRequired == false)
    }

    @Test(arguments: ["in 20m", "IN  20   Minutes", "in 20 mins", "  in 20 min  ", "in 20min"])
    func quickSpellings(_ input: String) throws {
        #expect(try parse(input).deadline == C.now.addingTimeInterval(20 * 60))
    }

    @Test func quickHoursAndDays() throws {
        #expect(try parse("in 2 hours").deadline == C.now.addingTimeInterval(2 * 3600))
        #expect(try parse("in 3 days").deadline == C.at(2026, 11, 6, 10, 0))
        #expect(try parse("in 3 d").kind == .quick)
    }

    @Test func quickDaysAcrossMonthBoundary() throws {
        let now = C.at(2026, 1, 31, 10, 0)
        #expect(try parse("in 1d", now: now).deadline == C.at(2026, 2, 1, 10, 0))
    }

    @Test func quickDayAcrossSpringForwardKeepsWallClock() throws {
        let now = C.at(2026, 3, 7, 12, 0)
        let p = try parse("in 1 day", now: now)
        #expect(p.deadline == C.at(2026, 3, 8, 12, 0))
        #expect(p.deadline.timeIntervalSince(now) == 23 * 3600)
    }

    @Test func quickDayAcrossFallBackKeepsWallClock() throws {
        let now = C.at(2026, 10, 31, 12, 0)
        let p = try parse("in 1 day", now: now)
        #expect(p.deadline == C.at(2026, 11, 1, 12, 0))
        #expect(p.deadline.timeIntervalSince(now) == 25 * 3600)
    }

    @Test(arguments: ["in 1h30m", "in 1h 30m", "in 1 h 30 m"])
    func compoundIsAnError(_ input: String) {
        #expect(throws: NaturalDeadlineError.compoundDuration) { try parse(input) }
    }

    @Test func quickErrors() {
        #expect(throws: NaturalDeadlineError.nonPositiveAmount) { try parse("in 0 min") }
        #expect(throws: NaturalDeadlineError.unrecognized) { try parse("in 5 fortnights") }
        #expect(throws: NaturalDeadlineError.unrecognized) { try parse("in") }
        #expect(throws: NaturalDeadlineError.unrecognized) { try parse("in soon") }
        #expect(throws: NaturalDeadlineError.amountTooLarge) { try parse("in 9999999 min") }
        #expect(throws: NaturalDeadlineError.amountTooLarge) { try parse("in 100001 min") }
    }

    @Test func emptyInput() {
        #expect(throws: NaturalDeadlineError.empty) { try parse("") }
        #expect(throws: NaturalDeadlineError.empty) { try parse("   ") }
    }

    @Test func everyErrorHasAHint() {
        let all: [NaturalDeadlineError] = [
            .empty, .unrecognized, .compoundDuration, .nonPositiveAmount, .amountTooLarge,
            .missingTime, .invalidTime, .invalidDate, .alreadyPassed,
        ]
        for e in all { #expect(!e.hint.isEmpty) }
    }

    // MARK: weekday / clock (now = Tue 2026-11-03 10:00)

    @Test func weekdayClock() throws {
        let p = try parse("Fri 5pm")
        #expect(p.deadline == C.at(2026, 11, 6, 17, 0))
        #expect(p.kind == .dated)
        #expect(p.approachWindow == 7200)
        #expect(p.timePromptRequired == false)
        #expect(try parse("fri 5:30pm").deadline == C.at(2026, 11, 6, 17, 30))
        #expect(try parse("Friday 5 pm").deadline == C.at(2026, 11, 6, 17, 0))
        #expect(try parse("fri 12am").deadline == C.at(2026, 11, 6, 0, 0))
        #expect(try parse("fri 12pm").deadline == C.at(2026, 11, 6, 12, 0))
        #expect(try parse("FRI 9:05AM").deadline == C.at(2026, 11, 6, 9, 5))
    }

    @Test func sameWeekdayLaterTodayStaysToday() throws {
        #expect(try parse("tue 11am").deadline == C.at(2026, 11, 3, 11, 0))
    }

    @Test func sameWeekdayAlreadyPastRollsToNextWeek() throws {
        #expect(try parse("tue 9am").deadline == C.at(2026, 11, 10, 9, 0))
        #expect(try parse("tue 10am").deadline == C.at(2026, 11, 10, 10, 0)) // == now rolls
    }

    @Test func todayAndTomorrow() throws {
        #expect(try parse("today 5pm").deadline == C.at(2026, 11, 3, 17, 0))
        #expect(try parse("tomorrow 9am").deadline == C.at(2026, 11, 4, 9, 0))
        #expect(throws: NaturalDeadlineError.alreadyPassed) { try parse("today 9am") }
        #expect(throws: NaturalDeadlineError.alreadyPassed) { try parse("today 10am") }
    }

    @Test func missingAndInvalidTime() {
        #expect(throws: NaturalDeadlineError.missingTime) { try parse("fri") }
        #expect(throws: NaturalDeadlineError.missingTime) { try parse("tomorrow") }
        #expect(throws: NaturalDeadlineError.invalidTime) { try parse("fri 17:00") }
        #expect(throws: NaturalDeadlineError.invalidTime) { try parse("fri 13pm") }
        #expect(throws: NaturalDeadlineError.invalidTime) { try parse("fri 0am") }
        #expect(throws: NaturalDeadlineError.invalidTime) { try parse("fri 5:60pm") }
        #expect(throws: NaturalDeadlineError.invalidTime) { try parse("fri 5:3pm") }
        #expect(throws: NaturalDeadlineError.invalidTime) { try parse("fri noon") }
        #expect(throws: NaturalDeadlineError.invalidTime) { try parse("fri 5pm please") }
    }

    @Test func springForwardGapStillResolvesToThatDay() throws {
        // 02:30 does not exist on Sun 2026-03-08; Calendar's standard disambiguation applies.
        let now = C.at(2026, 3, 6, 12, 0)
        let p = try parse("sun 2:30am", now: now)
        #expect(p.deadline > now)
        #expect(C.parts(p.deadline).day == 8)
        #expect(C.parts(p.deadline).month == 3)
    }

    @Test func fallBackRepeatedHourStaysOnThatDay() throws {
        // 01:30 happens twice on Sun 2026-11-01.
        let now = C.at(2026, 10, 30, 12, 0)
        let p = try parse("sun 1:30am", now: now)
        let c = C.parts(p.deadline)
        #expect(c.month == 11 && c.day == 1 && c.hour == 1 && c.minute == 30)
    }

    // MARK: plain date

    @Test func plainDateRequiresTimePrompt() throws {
        let p = try parse("Nov 15")
        #expect(p.deadline == C.at(2026, 11, 15, 9, 0))
        #expect(p.timePromptRequired == true)
        #expect(p.kind == .dated)
        #expect(p.approachWindow == 7200)
        #expect(try parse("november 15").deadline == C.at(2026, 11, 15, 9, 0))
        #expect(try parse("  NOV   15 ").timePromptRequired == true)
    }

    @Test func plainDateRollsToNextYear() throws {
        #expect(try parse("Nov 2").deadline == C.at(2027, 11, 2, 9, 0))
        #expect(try parse("jan 1", now: C.at(2026, 12, 31, 10, 0)).deadline == C.at(2027, 1, 1, 9, 0))
    }

    @Test func plainDateTodayStaysThisYear() throws {
        // Interpretation: same-day input keeps this year; the time prompt validates the
        // final moment (see applyingTime tests).
        let p = try parse("nov 3")
        #expect(p.deadline == C.at(2026, 11, 3, 9, 0))
        #expect(p.timePromptRequired == true)
    }

    @Test func leapDay() throws {
        #expect(try parse("Feb 29").deadline == C.at(2028, 2, 29, 9, 0))
        #expect(try parse("Feb 29", now: C.at(2028, 3, 1, 10, 0)).deadline == C.at(2032, 2, 29, 9, 0))
        #expect(try parse("Feb 29", now: C.at(2028, 2, 29, 8, 0)).deadline == C.at(2028, 2, 29, 9, 0))
    }

    @Test func impossibleDates() {
        #expect(throws: NaturalDeadlineError.invalidDate) { try parse("Feb 30") }
        #expect(throws: NaturalDeadlineError.invalidDate) { try parse("Apr 31") }
        #expect(throws: NaturalDeadlineError.invalidDate) { try parse("Nov 32") }
        #expect(throws: NaturalDeadlineError.invalidDate) { try parse("Nov 0") }
    }

    @Test func malformedDates() {
        #expect(throws: NaturalDeadlineError.unrecognized) { try parse("nov") }
        #expect(throws: NaturalDeadlineError.unrecognized) { try parse("nov fifteen") }
        #expect(throws: NaturalDeadlineError.unrecognized) { try parse("nov 15 5pm") }
        #expect(throws: NaturalDeadlineError.unrecognized) { try parse("blah") }
        #expect(throws: NaturalDeadlineError.unrecognized) { try parse("5pm") }
    }

    // MARK: time prompt

    @Test func applyingChosenTime() throws {
        let date = try parse("Nov 15")
        let p = try NaturalDeadline.applyingTime(
            hour: 14, minute: 30, to: date, now: C.now, calendar: C.calendar, timeZone: C.zone)
        #expect(p.deadline == C.at(2026, 11, 15, 14, 30))
        #expect(p.timePromptRequired == false)
        #expect(p.kind == .dated)
    }

    @Test func applyingTimeRejectsPastAndInvalid() throws {
        let today = try parse("nov 3")
        #expect(throws: NaturalDeadlineError.alreadyPassed) {
            try NaturalDeadline.applyingTime(
                hour: 9, minute: 0, to: today, now: C.now, calendar: C.calendar, timeZone: C.zone)
        }
        let later = try NaturalDeadline.applyingTime(
            hour: 15, minute: 0, to: today, now: C.now, calendar: C.calendar, timeZone: C.zone)
        #expect(later.deadline == C.at(2026, 11, 3, 15, 0))
        #expect(throws: NaturalDeadlineError.invalidTime) {
            try NaturalDeadline.applyingTime(
                hour: 24, minute: 0, to: today, now: C.now, calendar: C.calendar, timeZone: C.zone)
        }
    }
}
