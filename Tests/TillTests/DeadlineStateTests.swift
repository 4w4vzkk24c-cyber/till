import Foundation
import Testing
@testable import Till

@Suite struct DeadlineStateTests {
    typealias C = TestClock
    let now = C.at(2026, 11, 3, 10, 0)

    private func chip(
        in seconds: TimeInterval, window: TimeInterval = 1800, pausedAt: Date? = nil,
        id: UUID = UUID()
    ) -> ChipSnapshot {
        ChipSnapshot(id: id, deadline: now.addingTimeInterval(seconds), pausedAt: pausedAt, approachWindow: window)
    }

    // MARK: per-chip state (design §6 precedence)

    @Test func quickTimerThresholds() {
        #expect(DeadlineState.state(of: chip(in: 45 * 60), at: now) == .clean)
        #expect(DeadlineState.state(of: chip(in: 30 * 60 + 1), at: now) == .clean)
        #expect(DeadlineState.state(of: chip(in: 30 * 60), at: now) == .approaching)
        #expect(DeadlineState.state(of: chip(in: 29 * 60), at: now) == .approaching)
        #expect(DeadlineState.state(of: chip(in: 1), at: now) == .approaching)
    }

    @Test func datedThresholds() {
        #expect(DeadlineState.state(of: chip(in: 2 * 3600 + 1, window: 7200), at: now) == .clean)
        #expect(DeadlineState.state(of: chip(in: 2 * 3600, window: 7200), at: now) == .approaching)
    }

    @Test func overdueAtAndAfterDeadline() {
        #expect(DeadlineState.state(of: chip(in: 0), at: now) == .overdue)
        #expect(DeadlineState.state(of: chip(in: -1), at: now) == .overdue)
        #expect(DeadlineState.state(of: chip(in: -86_400), at: now) == .overdue)
    }

    @Test func pausedWinsOverEverything() {
        #expect(DeadlineState.state(of: chip(in: 600, pausedAt: now), at: now) == .paused)
        #expect(DeadlineState.state(of: chip(in: 7200, pausedAt: now), at: now) == .paused)
        // A paused chip never crosses to overdue.
        #expect(DeadlineState.state(of: chip(in: -10, pausedAt: now.addingTimeInterval(-100)), at: now) == .paused)
    }

    // MARK: bar aggregation

    @Test func emptyAndAllPausedAreDimmed() {
        #expect(DeadlineState.barEscalation(of: [], at: now) == .dimmed)
        let paused = [chip(in: 600, pausedAt: now), chip(in: -5, pausedAt: now)]
        #expect(DeadlineState.barEscalation(of: paused, at: now) == .dimmed)
        #expect(DeadlineState.driver(of: paused, at: now) == nil)
    }

    @Test func worstActiveWins() {
        #expect(DeadlineState.barEscalation(of: [chip(in: 7200)], at: now) == .normal)
        #expect(DeadlineState.barEscalation(of: [chip(in: 7200), chip(in: 600)], at: now) == .amber)
        #expect(DeadlineState.barEscalation(of: [chip(in: 7200), chip(in: 600), chip(in: -1)], at: now)
                == .red(overdueCount: 1))
    }

    @Test func badgeCountsOnlyActiveOverdue() {
        let chips = [chip(in: -1), chip(in: -3600), chip(in: -5, pausedAt: now.addingTimeInterval(-60)), chip(in: 7200)]
        #expect(DeadlineState.barEscalation(of: chips, at: now) == .red(overdueCount: 2))
    }

    @Test func pausedChipsDoNotEscalate() {
        let chips = [chip(in: 7200), chip(in: -1, pausedAt: now.addingTimeInterval(-60))]
        #expect(DeadlineState.barEscalation(of: chips, at: now) == .normal)
    }

    @Test func driverIsWorstThenNearestDeadlineThenId() {
        let lowID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let highID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let nearApproach = chip(in: 100)
        let farApproach = chip(in: 900)
        let overdueRecent = chip(in: -60)
        let overdueOlder = chip(in: -3600)
        #expect(DeadlineState.driver(of: [farApproach, nearApproach], at: now) == nearApproach)
        #expect(DeadlineState.driver(of: [nearApproach, overdueRecent], at: now) == overdueRecent)
        #expect(DeadlineState.driver(of: [overdueRecent, overdueOlder], at: now) == overdueOlder)
        let a = chip(in: 100, id: highID)
        let b = chip(in: 100, id: lowID)
        #expect(DeadlineState.driver(of: [a, b], at: now)?.id == lowID)
        #expect(DeadlineState.driver(of: [b, a], at: now)?.id == lowID)
    }

    @Test func displayOrderIsDeadlineThenId() {
        let lowID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let highID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let later = chip(in: 500)
        let tieHigh = chip(in: 100, id: highID)
        let tieLow = chip(in: 100, id: lowID)
        let overdue = chip(in: -50)
        let ordered = DeadlineState.displayOrder([later, tieHigh, overdue, tieLow])
        #expect(ordered.map(\.id) == [overdue.id, lowID, highID, later.id])
    }
}

@Suite struct HeroTimeTests {
    @Test func daysAndHours() {
        #expect(HeroTime.format(remaining: 3 * 86_400 + 14 * 3_600 + 59) == "3d 14h")
        #expect(HeroTime.format(remaining: 86_400) == "1d 0h")
        #expect(HeroTime.format(remaining: 86_399) == "23h 59m")
    }

    @Test func hoursAndMinutes() {
        #expect(HeroTime.format(remaining: 14 * 3_600 + 32 * 60 + 41) == "14h 32m")
        #expect(HeroTime.format(remaining: 3_600) == "1h 0m")
    }

    @Test func minutesAndSeconds() {
        #expect(HeroTime.format(remaining: 32 * 60 + 41) == "32:41")
        #expect(HeroTime.format(remaining: 3_599.9) == "59:59")
        #expect(HeroTime.format(remaining: 5) == "0:05")
        #expect(HeroTime.format(remaining: 0.4) == "0:00")
    }

    @Test func overdue() {
        #expect(HeroTime.format(remaining: -(2 * 3_600 + 10)) == "+2h overdue")
        #expect(HeroTime.format(remaining: -(41 * 60 + 59)) == "+41m overdue")
        #expect(HeroTime.format(remaining: 0) == "+0m overdue")
        #expect(HeroTime.format(remaining: -30) == "+0m overdue")
        #expect(HeroTime.format(remaining: -3_600) == "+1h overdue")
        // Spec is silent beyond a day; hours continue.
        #expect(HeroTime.format(remaining: -50 * 3_600) == "+50h overdue")
    }

    @Test func pausedShowsFrozenRemaining() {
        let now = TestClock.at(2026, 11, 3, 10, 0)
        let pausedAt = now.addingTimeInterval(-3_600)
        let chip = ChipSnapshot(
            id: UUID(), deadline: pausedAt.addingTimeInterval(32 * 60 + 41),
            pausedAt: pausedAt, approachWindow: 1800)
        // Frozen: unaffected by how long ago it was paused.
        #expect(HeroTime.format(chip: chip, at: now) == "32:41")
        #expect(HeroTime.format(chip: chip, at: now.addingTimeInterval(86_400)) == "32:41")
    }

    @Test func activeChipUsesLiveRemaining() {
        let now = TestClock.at(2026, 11, 3, 10, 0)
        let chip = ChipSnapshot(id: UUID(), deadline: now.addingTimeInterval(125), approachWindow: 1800)
        #expect(HeroTime.format(chip: chip, at: now) == "2:05")
        #expect(HeroTime.format(chip: chip, at: now.addingTimeInterval(125)) == "+0m overdue")
    }
}
