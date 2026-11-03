import Foundation
import Testing
@testable import Till

@Suite struct ChipPresentationTests {
    @Test func captionsSayTheState() {
        #expect(ChipPresentation(state: .clean, heroText: "12:40").caption == nil)
        #expect(ChipPresentation(state: .approaching, heroText: "4:12").caption == "due soon")
        #expect(ChipPresentation(state: .overdue, heroText: "+41m overdue").caption == "overdue")
        #expect(ChipPresentation(state: .paused, heroText: "14h 32m").caption == "paused")
    }

    @Test func surfaceAndControlFollowState() {
        let cases: [(ChipState, ChipPresentation.Surface, ChipPresentation.Control)] = [
            (.clean, .neutral, .pause), (.approaching, .dueSoon, .pause),
            (.overdue, .overdue, .done), (.paused, .paused, .resume),
        ]
        for (state, surface, control) in cases {
            let p = ChipPresentation(state: state, heroText: "1h 05m")
            #expect(p.surface == surface && p.control == control)
        }
    }

    @Test func overdueHeroDropsTheWordOverdue() {              // Review Focus 2
        #expect(ChipPresentation(state: .overdue, heroText: "+41m overdue").hero == "+41m")
        #expect(ChipPresentation(state: .overdue, heroText: "+50h overdue").hero == "+50h")
        #expect(ChipPresentation(state: .overdue, heroText: "+0m overdue").hero == "+0m")
    }

    @Test func otherHeroTextPassesThrough() {
        for text in ["3d 14h", "14h 32m", "4:12"] {
            #expect(ChipPresentation(state: .clean, heroText: text).hero == text)
        }
    }

    @Test func agreesWithHeroTimeForARealChip() {
        let now = TestClock.now
        let chip = ChipSnapshot(
            id: UUID(), deadline: now.addingTimeInterval(-(41 * 60 + 5)), approachWindow: 1800)
        let p = ChipPresentation(
            state: DeadlineState.state(of: chip, at: now), heroText: HeroTime.format(chip: chip, at: now))
        #expect(p.hero == "+41m" && p.caption == "overdue")
    }
}
