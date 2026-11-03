import Foundation
import Testing
@testable import Till

@Suite struct TickCadenceTests {
    typealias C = TestClock
    let now = C.at(2026, 11, 3, 10, 0)

    private func chip(in seconds: TimeInterval, window: TimeInterval = 1800, paused: Bool = false) -> ChipSnapshot {
        ChipSnapshot(
            id: UUID(), deadline: now.addingTimeInterval(seconds),
            pausedAt: paused ? now : nil, approachWindow: window)
    }

    @Test func popoverOpenIsOneSecond() {
        #expect(TickCadence.interval(popoverOpen: true, chips: [], now: now) == 1)
        #expect(TickCadence.interval(popoverOpen: true, chips: [chip(in: 7200)], now: now) == 1)
    }

    @Test func closedAndEmptyIsThirtySeconds() {
        #expect(TickCadence.interval(popoverOpen: false, chips: [], now: now) == 30)
    }

    @Test func approachingChipForcesOneSecondWhileClosed() {
        #expect(TickCadence.interval(popoverOpen: false, chips: [chip(in: 600)], now: now) == 1)
        #expect(TickCadence.interval(popoverOpen: false, chips: [chip(in: 7200), chip(in: 1800)], now: now) == 1)
    }

    @Test func cleanOverdueAndPausedStayAtThirtySeconds() {
        #expect(TickCadence.interval(popoverOpen: false, chips: [chip(in: 3600)], now: now) == 30)
        #expect(TickCadence.interval(popoverOpen: false, chips: [chip(in: -60)], now: now) == 30)
        #expect(TickCadence.interval(popoverOpen: false, chips: [chip(in: 600, paused: true)], now: now) == 30)
    }
}

@MainActor
@Suite struct StoreTickTests {

    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<200 {
            if condition() { return }
            await Task.yield()
        }
    }

    @Test func tickUpdatesDisplayClock() async throws {
        let h = try Harness()
        let before = h.store.now
        h.clock.now = h.clock.now.addingTimeInterval(45)
        #expect(h.store.now == before)
        h.store.tick()
        #expect(h.store.now == h.clock.now)
    }

    @Test func tickIntervalFollowsThePopoverAndTheChips() async throws {
        let h = try Harness()
        #expect(h.store.tickInterval == TickCadence.idle)
        h.store.popoverOpen = true
        #expect(h.store.tickInterval == TickCadence.active)
        h.store.popoverOpen = false
        try await h.create(in: 600)                     // inside its 30 min window
        #expect(h.store.tickInterval == TickCadence.active)
    }

    @Test func aPopoverChangeTellsTheDriver() async throws {
        let h = try Harness()
        let changes = Box(0)
        h.store.onCadenceInputsChanged = { changes.value += 1 }
        h.store.popoverOpen = true
        #expect(changes.value == 1)
        h.store.popoverOpen = true                      // no change, no notification
        #expect(changes.value == 1)
        h.store.popoverOpen = false
        #expect(changes.value == 2)
    }

    @Test func aChipMutationTellsTheDriver() async throws {
        let h = try Harness()
        let changes = Box(0)
        h.store.onCadenceInputsChanged = { changes.value += 1 }
        try await h.create(in: 3600)
        #expect(changes.value >= 1)
    }

    /// The old loop tests, migrated: the real driver wired to the store the way `AppModel`
    /// wires it, with a recording sleep in place of the real one.
    @Test func theWiredDriverFollowsThePopoverState() async throws {
        let intervals = Box<[TimeInterval]>([])
        let h = try Harness()
        let driver = TaskDisplayTickDriver(
            interval: { h.store.tickInterval }, tick: { h.store.tick() },
            sleep: { interval in
                intervals.value.append(interval)
                try await Task.sleep(for: .seconds(1000))
            })
        h.store.onCadenceInputsChanged = { driver.cadenceInputsChanged() }
        driver.start()
        defer { driver.stop() }
        await waitUntil { intervals.value.count >= 1 }
        #expect(intervals.value == [30])

        h.store.popoverOpen = true
        await waitUntil { intervals.value.count >= 2 }
        #expect(intervals.value == [30, 1])

        h.store.popoverOpen = false
        await waitUntil { intervals.value.count >= 3 }
        #expect(intervals.value == [30, 1, 30])
    }

    @Test func theWiredDriverSpeedsUpWhenAChipEntersItsFinalStretch() async throws {
        let intervals = Box<[TimeInterval]>([])
        let h = try Harness()
        let driver = TaskDisplayTickDriver(
            interval: { h.store.tickInterval }, tick: { h.store.tick() },
            sleep: { interval in
                intervals.value.append(interval)
                try await Task.sleep(for: .seconds(1000))
            })
        h.store.onCadenceInputsChanged = { driver.cadenceInputsChanged() }
        driver.start()
        defer { driver.stop() }
        await waitUntil { intervals.value.count >= 1 }
        #expect(intervals.value == [30])
        try await h.create(in: 600)                     // enters its final stretch immediately
        await waitUntil { intervals.value.count >= 2 }
        #expect(intervals.value.last == 1)
    }
}
