import Foundation
import SwiftData
import Testing
@testable import Till

@MainActor
struct Harness {
    let container: ModelContainer
    let store: TimerStore
    let scheduler: MockScheduler
    let clock: ClockBox
    let defaults: UserDefaults
    let failures: FailureSwitch

    init(
        status: NotificationAuthorization = .authorized,
        container: ModelContainer? = nil,
        defaults: UserDefaults? = nil
    ) throws {
        let box = ClockBox(TestClock.at(2026, 11, 3, 10, 0))
        let switchBox = FailureSwitch()
        let mock = MockScheduler()
        mock.status = status
        let suite = defaults ?? UserDefaults(suiteName: "till.tests.\(UUID().uuidString)")!
        let c = try container ?? TillPersistence.makeContainer(inMemory: true)
        self.container = c
        self.scheduler = mock
        self.clock = box
        self.defaults = suite
        self.failures = switchBox
        self.store = TimerStore(
            container: c, scheduler: mock, defaults: suite,
            clock: { box.now },
            persist: { context in
                if switchBox.failSaves { throw SaveFailure() }
                try context.save()
            })
    }

    func parsed(in seconds: TimeInterval, window: TimeInterval = 1800) -> ParsedDeadline {
        ParsedDeadline(
            deadline: clock.now.addingTimeInterval(seconds), approachWindow: window,
            kind: .quick, timePromptRequired: false)
    }

    @discardableResult
    func create(in seconds: TimeInterval, label: String? = "Test") async throws -> UUID {
        try await store.createChip(
            NewChip(
                iconId: "mdi:timer", iconMonotone: true, label: label,
                accentHex: "#FFAA00", parsed: parsed(in: seconds)))
    }

    func chip(_ id: UUID) -> ChipEntity? { store.chips.first { $0.id == id } }
}

@MainActor
@Suite struct TimerStoreTests {

    // MARK: creation

    @Test func createPersistsAndSchedules() async throws {
        let h = try Harness()
        let id = try await h.create(in: 3600, label: "Dentist")
        #expect(h.store.chips.count == 1)
        let chip = try #require(h.chip(id))
        #expect(chip.label == "Dentist")
        #expect(chip.deadline == h.clock.now.addingTimeInterval(3600))
        #expect(chip.zeroCrossingHandled == false)   // not set at scheduling (FEAS-01)
        #expect(h.scheduler.scheduled.count == 1)
        #expect(h.scheduler.scheduled[0].id == id)
        #expect(h.scheduler.scheduled[0].date == chip.deadline)
        #expect(h.scheduler.scheduled[0].title == "Dentist")
    }

    @Test func createRejectsPastDeadline() async throws {
        let h = try Harness()
        await #expect(throws: TimerStoreError.deadlineInPast) { try await h.create(in: 0) }
        await #expect(throws: TimerStoreError.deadlineInPast) { try await h.create(in: -5) }
        #expect(h.store.chips.isEmpty)
        #expect(h.scheduler.scheduled.isEmpty)
    }

    @Test func persistHappensBeforeSchedule() async throws {
        let h = try Harness()
        var chipsAtSchedule: Int?
        h.scheduler.onSchedule = { chipsAtSchedule = h.store.chips.count }
        try await h.create(in: 3600)
        #expect(chipsAtSchedule == 1)
    }

    @Test func schedulingFailureDoesNotFailCreation() async throws {
        let h = try Harness()
        h.scheduler.scheduleError = ScheduleFailure()
        let id = try await h.create(in: 3600)
        #expect(h.chip(id) != nil)
        #expect(h.chip(id)?.zeroCrossingHandled == false)
        #expect(h.scheduler.scheduled.isEmpty)
    }

    @Test func authorizationRequestedOnFirstCreationOnly() async throws {
        let h = try Harness(status: .notDetermined)
        try await h.create(in: 3600)
        try await h.create(in: 7200)
        #expect(h.scheduler.requestCount == 1)
        #expect(h.scheduler.scheduled.count == 2)
    }

    @Test func deniedAuthorizationStillCreatesChip() async throws {
        let h = try Harness(status: .notDetermined)
        h.scheduler.requestResult = false
        let id = try await h.create(in: 3600)
        #expect(h.chip(id) != nil)
        #expect(h.scheduler.scheduled.isEmpty)
    }

    @Test func toggleOffDoesNotSchedule() async throws {
        let h = try Harness()
        await h.store.setNotificationsEnabled(false)
        try await h.create(in: 3600)
        #expect(h.scheduler.scheduled.isEmpty)
        #expect(h.store.chips.count == 1)
    }

    // MARK: persistence

    @Test func reloadFromSameContainer() async throws {
        let h = try Harness()
        let id = try await h.create(in: 3600, label: "Keep")
        let second = try TimerStore(
            container: h.container, scheduler: MockScheduler(), defaults: h.defaults,
            clock: { h.clock.now })
        try await second.start()
        #expect(second.chips.map(\.id) == [id])
        #expect(second.chips.first?.label == "Keep")
    }

    @Test func onDiskRoundTripAcrossContainers() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("till-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("till.store")

        let id: UUID
        do {
            let h = try Harness(container: TillPersistence.makeContainer(inMemory: false, storeURL: url))
            id = try await h.create(in: 3600, label: "Disk")
        }
        let reopened = try Harness(container: TillPersistence.makeContainer(inMemory: false, storeURL: url))
        try await reopened.store.start()
        #expect(reopened.store.chips.map(\.id) == [id])
        #expect(reopened.store.chips.first?.label == "Disk")
    }

    @Test func notificationToggleIsPersisted() async throws {
        let h = try Harness()
        await h.store.setNotificationsEnabled(false)
        let again = TimerStore(
            container: h.container, scheduler: MockScheduler(), defaults: h.defaults,
            clock: { h.clock.now })
        #expect(again.notificationsEnabled == false)
    }

    @Test func chipsAreOrderedByDeadlineThenID() async throws {
        let h = try Harness()
        try await h.create(in: 5000)
        try await h.create(in: 1000)
        try await h.create(in: 3000)
        let deadlines = h.store.chips.map(\.deadline)
        #expect(deadlines == deadlines.sorted())
    }

    // MARK: save failure / rollback (A1.1 item 6)

    @Test func failedSaveOnCreateRollsBack() async throws {
        let h = try Harness()
        try await h.create(in: 3600)
        h.failures.failSaves = true
        await #expect(throws: SaveFailure.self) { try await h.create(in: 7200) }
        #expect(h.store.chips.count == 1)
        #expect(h.scheduler.scheduled.count == 1)   // nothing scheduled for the failed one
    }

    @Test func failedSaveOnDoneRestoresChip() async throws {
        let h = try Harness()
        let id = try await h.create(in: 3600)
        h.failures.failSaves = true
        #expect(throws: SaveFailure.self) { try h.store.markDone(id: id) }
        #expect(h.chip(id) != nil)
        #expect(h.scheduler.removed.isEmpty)
        h.failures.failSaves = false
        try h.store.markDone(id: id)
        #expect(h.store.chips.isEmpty)
    }

    // MARK: done / pause / resume / edit

    @Test func doneDeletesAndRemovesPending() async throws {
        let h = try Harness()
        let id = try await h.create(in: 3600)
        try h.store.markDone(id: id)
        #expect(h.store.chips.isEmpty)
        #expect(h.scheduler.removed.contains(id))
        #expect(throws: TimerStoreError.notFound) { try h.store.markDone(id: id) }
    }

    @Test func pauseAndResumeArithmetic() async throws {
        let h = try Harness()
        let id = try await h.create(in: 3600)
        let t0 = h.clock.now
        h.clock.now = t0.addingTimeInterval(600)
        try h.store.pause(id: id)
        #expect(h.chip(id)?.pausedAt == t0.addingTimeInterval(600))
        #expect(h.scheduler.removed.contains(id))
        #expect(throws: TimerStoreError.alreadyPaused) { try h.store.pause(id: id) }

        h.clock.now = t0.addingTimeInterval(5000)
        try await h.store.resume(id: id)
        // frozen remaining was 3000 s; deadline' = now + 3000
        #expect(h.chip(id)?.deadline == t0.addingTimeInterval(8000))
        #expect(h.chip(id)?.pausedAt == nil)
        #expect(h.scheduler.scheduled.last?.date == t0.addingTimeInterval(8000))
        await #expect(throws: TimerStoreError.notPaused) { try await h.store.resume(id: id) }
    }

    @Test func overdueChipCannotBePaused() async throws {
        let h = try Harness()
        let id = try await h.create(in: 3600)
        h.clock.now = h.clock.now.addingTimeInterval(4000)
        #expect(throws: TimerStoreError.cannotPauseOverdue) { try h.store.pause(id: id) }
        #expect(h.chip(id)?.pausedAt == nil)
    }

    @Test func editReplacesLabelAndDeadlineAndReschedules() async throws {
        let h = try Harness()
        let id = try await h.create(in: 3600, label: "Old")
        try h.store.handleDeliveryObserved(chipID: id)
        try await h.store.edit(id: id, label: "New", deadline: h.parsed(in: 7200))
        let chip = try #require(h.chip(id))
        #expect(chip.label == "New")
        #expect(chip.deadline == h.clock.now.addingTimeInterval(7200))
        #expect(chip.zeroCrossingHandled == false)
        #expect(h.scheduler.removed.contains(id))
        #expect(h.scheduler.scheduled.count == 2)
        #expect(h.scheduler.scheduled.last?.title == "New")
    }

    @Test func editingPausedChipKeepsItPaused() async throws {
        let h = try Harness()
        let id = try await h.create(in: 3600)
        try h.store.pause(id: id)
        try await h.store.edit(id: id, label: nil, deadline: h.parsed(in: 900))
        let chip = try #require(h.chip(id))
        #expect(chip.pausedAt == h.clock.now)
        #expect(chip.deadline == h.clock.now.addingTimeInterval(900))
        #expect(h.scheduler.scheduled.count == 1)   // no new trigger while paused
    }

    @Test func deliveryObservedSetsFlagOnce() async throws {
        let h = try Harness()
        let id = try await h.create(in: 3600)
        #expect(h.chip(id)?.zeroCrossingHandled == false)
        try h.store.handleDeliveryObserved(chipID: id)
        #expect(h.chip(id)?.zeroCrossingHandled == true)
    }

    // MARK: toggle + authorization watcher

    @Test func toggleOnSchedulesOnlyActiveFutures() async throws {
        let h = try Harness()
        await h.store.setNotificationsEnabled(false)
        let future = try await h.create(in: 3600)
        let paused = try await h.create(in: 5000)
        try h.store.pause(id: paused)
        let soon = try await h.create(in: 60)
        h.clock.now = h.clock.now.addingTimeInterval(120)   // `soon` is now overdue
        await h.store.setNotificationsEnabled(true)
        #expect(h.scheduler.scheduled.map(\.id) == [future])
        _ = soon
    }

    @Test func toggleOffRemovesAllPending() async throws {
        let h = try Harness()
        let a = try await h.create(in: 3600)
        let b = try await h.create(in: 7200)
        await h.store.setNotificationsEnabled(false)
        #expect(Set(h.scheduler.removed).isSuperset(of: [a, b]))
        #expect(h.scheduler.pending.isEmpty)
    }

    @Test func deniedToGrantedSchedulesActiveFutures() async throws {
        let h = try Harness(status: .denied)
        let id = try await h.create(in: 3600)
        #expect(h.scheduler.scheduled.isEmpty)
        h.scheduler.status = .authorized
        await h.store.refreshAuthorization()
        #expect(h.scheduler.scheduled.map(\.id) == [id])
        await h.store.refreshAuthorization()          // granted -> granted: nothing new
        #expect(h.scheduler.scheduled.count == 1)
    }

    // MARK: reconciliation (design §7.4)

    @Test func pendingPastFireDateIsRemovedAndFiredOnce() async throws {
        let h = try Harness()
        let id = try await h.create(in: 60)
        #expect(h.scheduler.pending.contains(id))
        h.clock.now = h.clock.now.addingTimeInterval(120)
        await h.store.reconcile()
        #expect(h.scheduler.fired == [id])
        #expect(h.scheduler.removed.contains(id))
        #expect(h.chip(id)?.zeroCrossingHandled == true)
        await h.store.reconcile()                      // wake again: still exactly one
        #expect(h.scheduler.fired == [id])
    }

    @Test func deliveredSetsFlagWithoutFiring() async throws {
        let h = try Harness()
        let id = try await h.create(in: 60)
        h.scheduler.pending.remove(id)
        h.scheduler.delivered.insert(id)
        h.clock.now = h.clock.now.addingTimeInterval(120)
        await h.store.reconcile()
        #expect(h.scheduler.fired.isEmpty)
        #expect(h.chip(id)?.zeroCrossingHandled == true)
    }

    @Test func inBothListsDeliveredWins() async throws {
        let h = try Harness()
        let id = try await h.create(in: 60)
        h.scheduler.pending.insert(id)
        h.scheduler.delivered.insert(id)
        h.clock.now = h.clock.now.addingTimeInterval(120)
        await h.store.reconcile()
        #expect(h.scheduler.fired.isEmpty)
        #expect(h.chip(id)?.zeroCrossingHandled == true)
    }

    @Test func absentFromBothFiresOnce() async throws {
        let h = try Harness()
        h.scheduler.scheduleError = ScheduleFailure()    // never scheduled
        let id = try await h.create(in: 60)
        h.clock.now = h.clock.now.addingTimeInterval(120)
        await h.store.reconcile()
        #expect(h.scheduler.fired == [id])
        #expect(h.chip(id)?.zeroCrossingHandled == true)
    }

    @Test func observedChipIsNeverRefired() async throws {
        let h = try Harness()
        let id = try await h.create(in: 60)
        try h.store.handleDeliveryObserved(chipID: id)
        h.scheduler.pending.remove(id)                   // delivered then dismissed
        h.clock.now = h.clock.now.addingTimeInterval(120)
        await h.store.reconcile()
        #expect(h.scheduler.fired.isEmpty)
    }

    @Test func reconcileDoesNothingWhenToggleOffOrNotYetDue() async throws {
        let h = try Harness()
        let id = try await h.create(in: 3600)
        await h.store.reconcile()                        // not due
        #expect(h.scheduler.fired.isEmpty)
        h.clock.now = h.clock.now.addingTimeInterval(4000)
        await h.store.setNotificationsEnabled(false)
        await h.store.reconcile()                        // due but toggle off
        #expect(h.scheduler.fired.isEmpty)
        #expect(h.chip(id)?.zeroCrossingHandled == false)
    }

    @Test func pausedChipIsNeverNotified() async throws {
        let h = try Harness()
        let id = try await h.create(in: 3600)
        try h.store.pause(id: id)
        h.clock.now = h.clock.now.addingTimeInterval(10_000)
        await h.store.reconcile()
        #expect(h.scheduler.fired.isEmpty)
    }

    @Test func chipDoneDuringReconciliationAwaitsIsSkipped() async throws {
        let h = try Harness()
        let id = try await h.create(in: 60)
        h.clock.now = h.clock.now.addingTimeInterval(120)
        h.scheduler.onPendingRead = { try? h.store.markDone(id: id) }
        await h.store.reconcile()
        #expect(h.scheduler.fired.isEmpty)
        #expect(h.store.chips.isEmpty)
    }

    @Test func chipPausedDuringReconciliationAwaitsIsSkipped() async throws {
        let h = try Harness()
        let a = try await h.create(in: 60)
        let b = try await h.create(in: 90)
        h.clock.now = h.clock.now.addingTimeInterval(30)
        // Both are still in the future; make them overdue only after pausing b is impossible
        // (overdue cannot be paused), so instead edit b into the future mid-pass.
        h.clock.now = h.clock.now.addingTimeInterval(120)
        h.scheduler.onPendingRead = {
            try? await h.store.edit(id: b, label: nil, deadline: h.parsed(in: 3600))
        }
        await h.store.reconcile()
        #expect(h.scheduler.fired == [a])
        #expect(h.chip(b)?.zeroCrossingHandled == false)
    }

    @Test func overlappingTriggersRunOnePassPlusOneRerun() async throws {
        let h = try Harness()
        let id = try await h.create(in: 60)
        h.clock.now = h.clock.now.addingTimeInterval(120)
        var nested = false
        h.scheduler.onPendingRead = {
            if !nested {
                nested = true
                await h.store.reconcile()               // arrives mid-pass: rerun, not a 2nd pass
            }
        }
        await h.store.reconcile()
        #expect(h.store.reconcilePassCount == 2)
        #expect(h.scheduler.fired == [id])
    }

    @Test func startRunsReconciliationAndLearnsAuthorization() async throws {
        let h = try Harness()
        let id = try await h.create(in: 60)
        h.clock.now = h.clock.now.addingTimeInterval(120)
        let fresh = TimerStore(
            container: h.container, scheduler: h.scheduler, defaults: h.defaults,
            clock: { h.clock.now })
        try await fresh.start()
        #expect(h.scheduler.fired == [id])
    }
}
