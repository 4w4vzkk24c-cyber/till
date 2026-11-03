import Foundation
import Testing
@testable import Till

/// A test double for the tick driver: records calls and fires the tick on demand. It needs
/// neither a database nor a notification scheduler.
@MainActor
final class ManualTickDriver: DisplayTickDriving {
    private let onTick: @MainActor () -> Void
    private(set) var isRunning = false
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private(set) var cadenceInputChanges = 0

    init(onTick: @escaping @MainActor () -> Void = {}) { self.onTick = onTick }

    func start() { isRunning = true; startCount += 1 }
    func stop() { isRunning = false; stopCount += 1 }
    func cadenceInputsChanged() { cadenceInputChanges += 1 }
    func step() { onTick() }
}

/// The driver alone: no `ModelContainer`, no `NotificationScheduling`, no store.
@MainActor
@Suite struct DisplayTickDriverTests {
    private final class Rig {
        var interval: TimeInterval = 30
        var ticks = 0
        var sleeps: [TimeInterval] = []
    }

    private func make(_ rig: Rig) -> TaskDisplayTickDriver {
        TaskDisplayTickDriver(
            interval: { rig.interval },
            tick: { rig.ticks += 1 },
            sleep: { seconds in
                rig.sleeps.append(seconds)
                try await Task.sleep(for: .seconds(1000))
            })
    }

    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<200 {
            if condition() { return }
            await Task.yield()
        }
    }

    @Test func startTicksOnceImmediatelyAndStartAndStopAreIdempotent() {
        let rig = Rig()
        let driver = make(rig)
        driver.start()
        driver.start()
        #expect(driver.isRunning)
        #expect(rig.ticks == 1)
        driver.stop()
        driver.stop()
        #expect(!driver.isRunning)
    }

    @Test func itSleepsForTheCurrentInterval() async {
        let rig = Rig()
        let driver = make(rig)
        driver.start()
        defer { driver.stop() }
        await waitUntil { rig.sleeps.count >= 1 }
        #expect(rig.sleeps == [30])
    }

    @Test func changedInputsMakeItReadTheIntervalAgain() async {
        let rig = Rig()
        let driver = make(rig)
        driver.start()
        defer { driver.stop() }
        await waitUntil { rig.sleeps.count >= 1 }

        rig.interval = 1
        driver.cadenceInputsChanged()
        await waitUntil { rig.sleeps.count >= 2 }
        rig.interval = 30
        driver.cadenceInputsChanged()
        await waitUntil { rig.sleeps.count >= 3 }
        #expect(rig.sleeps == [30, 1, 30])
    }

    @Test func aRestartTicksAgainAsTheOldLoopDid() async {
        let rig = Rig()
        let driver = make(rig)
        driver.start()
        defer { driver.stop() }
        await waitUntil { rig.sleeps.count >= 1 }
        driver.cadenceInputsChanged()
        #expect(rig.ticks == 2)
    }

    @Test func aStoppedDriverIgnoresInputChanges() async {
        let rig = Rig()
        let driver = make(rig)
        driver.cadenceInputsChanged()
        await Task.yield()
        #expect(!driver.isRunning)
        #expect(rig.ticks == 0 && rig.sleeps.isEmpty)
    }

    @Test func theManualDriverRecordsCallsAndStepsOnDemand() {
        var ticks = 0
        let driver = ManualTickDriver(onTick: { ticks += 1 })
        driver.start()
        driver.cadenceInputsChanged()
        driver.step()
        driver.stop()
        #expect(driver.startCount == 1 && driver.stopCount == 1)
        #expect(driver.cadenceInputChanges == 1 && ticks == 1)
        #expect(!driver.isRunning)
    }
}
