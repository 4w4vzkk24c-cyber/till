import Foundation
import Testing
@testable import Till

@MainActor
@Suite struct CreationFlowTests {

    private func make() throws -> (Harness, CreationFlow) {
        let h = try Harness()
        let f = CreationFlow(
            store: h.store, clock: { h.clock.now },
            calendar: TestClock.calendar, timeZone: TestClock.zone)
        return (h, f)
    }

    private func isAwaitingTime(_ f: CreationFlow) -> Bool {
        if case .awaitingTime = f.phase { return true }
        return false
    }

    @Test func quickInputCreatesChipAndResets() async throws {
        let (h, f) = try make()
        f.input = "in 20 min"
        await f.submit()
        #expect(h.store.chips.count == 1)
        let chip = try #require(h.store.chips.first)
        #expect(chip.deadline == h.clock.now.addingTimeInterval(1200))
        #expect(chip.iconId == FallbackIcons.defaultID)
        #expect(f.input == "")
        #expect(f.errorHint == nil)
        #expect(f.phase == .idle)
    }

    @Test func unparseableInputStaysInlineWithHint() async throws {
        let (h, f) = try make()
        f.input = "blah"
        await f.submit()
        #expect(f.errorHint == NaturalDeadlineError.unrecognized.hint)
        #expect(f.input == "blah")
        #expect(h.store.chips.isEmpty)
    }

    @Test func emptyInputGivesHint() async throws {
        let (h, f) = try make()
        await f.submit()
        #expect(f.errorHint == NaturalDeadlineError.empty.hint)
        #expect(h.store.chips.isEmpty)
    }

    @Test func dateOnlyInputPromptsForTimeThenCreates() async throws {
        let (h, f) = try make()
        f.input = "Nov 15"
        await f.submit()
        #expect(isAwaitingTime(f))
        #expect(f.promptHour == 9 && f.promptMinute == 0)
        #expect(h.store.chips.isEmpty)            // nothing persisted before the time is chosen

        await f.confirmTime()                     // one tap to accept 09:00
        let chip = try #require(h.store.chips.first)
        #expect(chip.deadline == TestClock.at(2026, 11, 15, 9, 0))
        #expect(f.phase == .idle)
    }

    @Test func chosenTimeIsUsed() async throws {
        let (h, f) = try make()
        f.input = "Nov 15"
        await f.submit()
        f.promptHour = 14
        f.promptMinute = 30
        await f.confirmTime()
        #expect(h.store.chips.first?.deadline == TestClock.at(2026, 11, 15, 14, 30))
    }

    @Test func pastTimeOnTodayStaysInPromptUntilFixed() async throws {
        let (h, f) = try make()
        f.input = "nov 3"                         // today; now is 10:00
        await f.submit()
        await f.confirmTime()                     // 09:00 has passed
        #expect(f.errorHint == NaturalDeadlineError.alreadyPassed.hint)
        #expect(isAwaitingTime(f))
        #expect(h.store.chips.isEmpty)
        f.promptHour = 15
        await f.confirmTime()
        #expect(h.store.chips.first?.deadline == TestClock.at(2026, 11, 3, 15, 0))
        #expect(f.errorHint == nil)
    }

    @Test func cancelAbortsThePrompt() async throws {
        let (h, f) = try make()
        f.input = "Nov 15"
        await f.submit()
        f.cancel()
        #expect(f.phase == .idle)
        #expect(f.input == "")
        #expect(h.store.chips.isEmpty)
    }

    @Test func blankDeadlineWhileEditingShowsTheEmptyHintAndStaysEditing() async throws {
        let (h, f) = try make()
        let id = try await h.create(in: 3600)
        let deadline = h.chip(id)?.deadline
        f.beginEdit(id: id)
        #expect(f.editingID == id)
        await f.submit()
        #expect(f.errorHint == NaturalDeadlineError.empty.hint)
        #expect(f.editingID == id)
        #expect(h.chip(id)?.deadline == deadline)
    }

    @Test func editWithNewDeadlineReplacesIt() async throws {
        let (h, f) = try make()
        let id = try await h.create(in: 3600)
        f.beginEdit(id: id)
        f.input = "in 2 hours"
        await f.submit()
        #expect(h.chip(id)?.deadline == h.clock.now.addingTimeInterval(7200))
        #expect(h.store.chips.count == 1)
    }

    @Test func editingAChipThatWasFinishedReportsIt() async throws {
        let (h, f) = try make()
        let id = try await h.create(in: 3600)
        f.beginEdit(id: id)
        try h.store.markDone(id: id)
        f.input = "in 2 hours"
        await f.submit()
        #expect(f.errorHint == "That timer no longer exists.")
        #expect(f.editingID == nil)
    }

    @Test func performSurfacesStoreErrorsInline() async throws {
        let (h, f) = try make()
        let id = try await h.create(in: 60)
        h.clock.now = h.clock.now.addingTimeInterval(120)
        await f.perform { try h.store.pause(id: id) }
        #expect(f.errorHint == "An overdue timer can’t be paused. Mark it Done.")
        await f.perform { try h.store.markDone(id: id) }
        #expect(f.errorHint == nil)
        #expect(h.store.chips.isEmpty)
    }

    @Test func accentsCycle() async throws {
        let (h, f) = try make()
        f.input = "in 5 min"
        await f.submit()
        f.input = "in 6 min"
        await f.submit()
        let accents = h.store.chips.map(\.accentHex)
        #expect(accents.count == 2)
        #expect(accents[0] != accents[1])
    }
}
