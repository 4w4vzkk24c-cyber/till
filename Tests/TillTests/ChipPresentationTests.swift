import Foundation
import Testing
@testable import Till

@Suite struct ChipPresentationTests {
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
        #expect(p.hero == "+41m" && p.surface == .overdue)
    }
}

@Suite struct ChipGridLayoutTests {
    @Test func theTileIsCompact() { #expect(ChipGridLayout.tileHeight == 112) }

    @Test func noChipsNeedNoGrid() { #expect(ChipGridLayout.height(forChips: 0) == 0) }

    @Test func oneRowHoldsOneOrTwoChips() {
        #expect(ChipGridLayout.height(forChips: 1) == ChipGridLayout.tileHeight)
        #expect(ChipGridLayout.height(forChips: 2) == ChipGridLayout.tileHeight)
    }

    @Test func rowsAddTileHeightPlusGap() {
        #expect(ChipGridLayout.height(forChips: 3) == 2 * ChipGridLayout.tileHeight + ChipGridLayout.gap)
        #expect(ChipGridLayout.height(forChips: 4) == 2 * ChipGridLayout.tileHeight + ChipGridLayout.gap)
        #expect(ChipGridLayout.height(forChips: 5) == 3 * ChipGridLayout.tileHeight + 2 * ChipGridLayout.gap)
    }

    @Test func threeRowsFitWithoutScrolling() {
        #expect(ChipGridLayout.height(forChips: 6) == 3 * ChipGridLayout.tileHeight + 2 * ChipGridLayout.gap)
    }

    @Test func longerListsAreCappedAndScroll() {
        #expect(ChipGridLayout.height(forChips: 7) == ChipGridLayout.maxHeight)
        #expect(ChipGridLayout.height(forChips: 40) == ChipGridLayout.maxHeight)
    }

    @Test func theCapShowsThreeFullRows() {
        #expect(ChipGridLayout.maxHeight >= 3 * ChipGridLayout.tileHeight + 2 * ChipGridLayout.gap)
    }
}
