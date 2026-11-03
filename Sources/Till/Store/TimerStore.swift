import Foundation
import Observation
import SwiftData

enum TimerStoreError: Error, Equatable {
    case notFound
    case deadlineInPast
    case cannotPauseOverdue
    case alreadyPaused
    case notPaused
}

struct NewChip: Sendable {
    let iconId: String
    let iconMonotone: Bool
    let label: String?
    let accentHex: String
    let parsed: ParsedDeadline
}

/// The one mutable owner of chips (design §7.4). Main actor.
///
/// Invariants (addendum A1.1):
/// - every mutation saves immediately via `commit()`; autosave is off, so a failed save
///   can `rollback()` without discarding unrelated pending edits;
/// - actions target `ChipEntity.id` and re-fetch after every suspension;
/// - reconciliation is single-flight (a trigger arriving mid-pass requests one rerun).
///
/// Not in this pass: the display tick loop, the UNUserNotificationCenter delegate wiring
/// (call `handleDeliveryObserved` from it), and the creation-flow UI.
@MainActor
@Observable
final class TimerStore {
    private(set) var chips: [ChipEntity] = []
    private(set) var notificationsEnabled: Bool

    @ObservationIgnored private let context: ModelContext
    @ObservationIgnored private let scheduler: any NotificationScheduling
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let clock: @MainActor () -> Date
    @ObservationIgnored private let persist: @MainActor (ModelContext) throws -> Void
    @ObservationIgnored private let sleep: @MainActor (TimeInterval) async throws -> Void
    @ObservationIgnored private var tickTask: Task<Void, Never>?
    /// True while the popover is visible. Drives the 1 s cadence (design §7.4).
    @ObservationIgnored var popoverOpen = false {
        didSet { if oldValue != popoverOpen { restartTickingIfRunning() } }
    }

    /// Last notification authorization state this store observed (footer reads it).
    private(set) var authorization: NotificationAuthorization?
    /// Display clock. Updated by `tick()`; views read this, never `Date()`.
    private(set) var now: Date
    @ObservationIgnored private var isReconciling = false
    @ObservationIgnored private var rerunRequested = false
    @ObservationIgnored private(set) var reconcilePassCount = 0
    @ObservationIgnored private(set) var lastReconciliationError: Error?

    static let notificationsEnabledKey = "till.notificationsEnabled"

    init(
        container: ModelContainer,
        scheduler: any NotificationScheduling,
        defaults: UserDefaults = .standard,
        clock: @escaping @MainActor () -> Date = { Date() },
        persist: @escaping @MainActor (ModelContext) throws -> Void = { try $0.save() },
        sleep: @escaping @MainActor (TimeInterval) async throws -> Void = {
            try await Task.sleep(for: .seconds($0))
        }
    ) {
        self.context = container.mainContext
        self.scheduler = scheduler
        self.defaults = defaults
        self.clock = clock
        self.persist = persist
        self.sleep = sleep
        self.now = clock()
        self.notificationsEnabled =
            defaults.object(forKey: Self.notificationsEnabledKey) as? Bool ?? true
        // Explicit save checkpoints only (addendum A1.1 item 6).
        context.autosaveEnabled = false
    }

    // MARK: - Lifecycle

    /// Launch: load chips, learn the current authorization state, run a reconciliation pass.
    func start() async throws {
        try reload()
        authorization = await scheduler.authorizationStatus()
        await reconcile()
    }

    // MARK: - Display tick loop (design §7.4; seed cadence verbatim)

    /// Remaining time always derives from `deadline - now`, never from accumulated ticks,
    /// so sleep and drift self-correct on the next tick.
    func tick() {
        now = clock()
    }

    func nextTickInterval() -> TimeInterval {
        TickCadence.interval(popoverOpen: popoverOpen, chips: chips.map(\.snapshot), now: clock())
    }

    /// Idempotent. The task is owned here and stopped by `stopTicking()` (or restarted by
    /// `restartTickingIfRunning()`); it holds `self` weakly and never across the sleep.
    func startTicking() {
        guard tickTask == nil else { return }
        tick()
        let sleep = self.sleep
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let interval = self?.nextTickInterval() else { return }
                do { try await sleep(interval) } catch { return }
                guard let store = self else { return }
                store.tick()
            }
        }
    }

    func stopTicking() {
        tickTask?.cancel()
        tickTask = nil
    }

    var isTicking: Bool { tickTask != nil }

    private func restartTickingIfRunning() {
        guard tickTask != nil else { return }
        stopTicking()
        startTicking()
    }

    // MARK: - Mutations

    @discardableResult
    func createChip(_ new: NewChip) async throws -> UUID {
        guard new.parsed.deadline > clock() else { throw TimerStoreError.deadlineInPast }
        let entity = ChipEntity(
            iconId: new.iconId, iconMonotone: new.iconMonotone, label: new.label,
            accentHex: new.accentHex, deadline: new.parsed.deadline,
            approachWindow: new.parsed.approachWindow, kind: new.parsed.kind.rawValue,
            createdDate: clock())
        context.insert(entity)
        try commit()                       // persist BEFORE schedule (design §5)
        let id = entity.id
        await scheduleIfPossible(id: id, requestAuthorizationIfNeeded: true)
        return id
    }

    func markDone(id: UUID) throws {
        guard let chip = fetchEntity(id) else { throw TimerStoreError.notFound }
        context.delete(chip)
        try commit()
        scheduler.removePending(ids: [id])
    }

    func pause(id: UUID) throws {
        guard let chip = fetchEntity(id) else { throw TimerStoreError.notFound }
        guard chip.pausedAt == nil else { throw TimerStoreError.alreadyPaused }
        let now = clock()
        guard DeadlineState.state(of: chip.snapshot, at: now) != .overdue else {
            throw TimerStoreError.cannotPauseOverdue
        }
        chip.pausedAt = now
        try commit()
        scheduler.removePending(ids: [id])
    }

    func resume(id: UUID) async throws {
        guard let chip = fetchEntity(id) else { throw TimerStoreError.notFound }
        guard let pausedAt = chip.pausedAt else { throw TimerStoreError.notPaused }
        let frozenRemaining = chip.deadline.timeIntervalSince(pausedAt)
        chip.deadline = clock().addingTimeInterval(frozenRemaining)
        chip.pausedAt = nil
        chip.zeroCrossingHandled = false
        try commit()
        await scheduleIfPossible(id: id, requestAuthorizationIfNeeded: false)
    }

    /// Edit covers label and deadline only (design §7.5). `deadline == nil` keeps the
    /// deadline (label-only edit). A paused chip stays paused and a new deadline becomes
    /// its frozen remaining time measured from now.
    func edit(id: UUID, label: String?, deadline parsed: ParsedDeadline?) async throws {
        guard let chip = fetchEntity(id) else { throw TimerStoreError.notFound }
        let now = clock()
        if let parsed, parsed.deadline <= now { throw TimerStoreError.deadlineInPast }
        chip.label = label
        let stillPaused = chip.pausedAt != nil
        if let parsed {
            chip.deadline = parsed.deadline
            chip.approachWindow = parsed.approachWindow
            chip.kind = parsed.kind.rawValue
            chip.zeroCrossingHandled = false
            if stillPaused { chip.pausedAt = now }
        }
        try commit()
        // Reschedule so the pending trigger carries the new label and/or deadline.
        scheduler.removePending(ids: [id])
        if !stillPaused {
            await scheduleIfPossible(id: id, requestAuthorizationIfNeeded: false)
        }
    }

    func setNotificationsEnabled(_ enabled: Bool) async {
        notificationsEnabled = enabled
        defaults.set(enabled, forKey: Self.notificationsEnabledKey)
        if enabled {
            await scheduleAllActiveFutures()
        } else {
            scheduler.removePending(ids: chips.map(\.id))
        }
    }

    /// Delegate / reconciliation hook: a delivery for this chip was actually observed.
    func handleDeliveryObserved(chipID: UUID) throws {
        guard let chip = fetchEntity(chipID), !chip.zeroCrossingHandled else { return }
        chip.zeroCrossingHandled = true
        try commit()
    }

    // MARK: - Authorization watcher (design §7.4, FR-01)

    func refreshAuthorization() async {
        let status = await scheduler.authorizationStatus()
        let previous = authorization
        authorization = status
        if previous == .denied, status == .authorized, notificationsEnabled {
            await scheduleAllActiveFutures()
        }
    }

    // MARK: - Reconciliation (single-flight)

    func reconcile() async {
        if isReconciling {
            rerunRequested = true
            return
        }
        isReconciling = true
        repeat {
            rerunRequested = false
            reconcilePassCount += 1
            await reconcileOnce()
        } while rerunRequested
        isReconciling = false
    }

    private func reconcileOnce() async {
        await refreshAuthorization()
        guard notificationsEnabled else { return }

        let candidates = chips.filter { needsNotification($0, at: clock()) }.map(\.id)
        guard !candidates.isEmpty else { return }

        // Pending first, then delivered, and delivered wins when a request is in both
        // (it moved pending -> delivered between the two non-atomic reads). This closes
        // that window of the disclosed re-fire bound (addendum A1.7).
        let pending = await scheduler.pendingIDs()
        let delivered = await scheduler.deliveredIDs()

        for id in candidates {
            // Revalidate after the suspensions above (addendum A1.1 item 1).
            guard notificationsEnabled, let chip = fetchEntity(id),
                  needsNotification(chip, at: clock()) else { continue }
            let payload = content(for: chip)
            do {
                if pending.contains(id) { scheduler.removePending(ids: [id]) }
                if !delivered.contains(id) {
                    try await scheduler.fireNow(id: id, content: payload)
                }
                guard let current = fetchEntity(id) else { continue }
                current.zeroCrossingHandled = true
                try commit()
            } catch {
                lastReconciliationError = error
                return
            }
        }
    }

    // MARK: - Scheduling

    private func scheduleAllActiveFutures() async {
        let now = clock()
        let ids = chips.filter { $0.pausedAt == nil && $0.deadline > now }.map(\.id)
        for id in ids {
            await scheduleIfPossible(id: id, requestAuthorizationIfNeeded: false)
        }
    }

    private func scheduleIfPossible(id: UUID, requestAuthorizationIfNeeded: Bool) async {
        guard notificationsEnabled else { return }
        var status = await scheduler.authorizationStatus()
        if status == .notDetermined && requestAuthorizationIfNeeded {
            status = await scheduler.requestAuthorization() ? .authorized : .denied
        }
        authorization = status
        guard status == .authorized else { return }
        guard notificationsEnabled, let chip = fetchEntity(id), chip.pausedAt == nil,
              chip.deadline > clock() else { return }
        do {
            try await scheduler.schedule(id: id, content: content(for: chip), at: chip.deadline)
        } catch {
            // A scheduling failure does not fail creation; the flag stays false and
            // reconciliation catches the chip at its crossing (design §5 step 5).
            return
        }
        // The world may have changed while scheduling was in flight: do not leave an
        // orphaned trigger for a chip that was finished, paused, or switched off.
        if !notificationsEnabled || fetchEntity(id)?.pausedAt != nil || fetchEntity(id) == nil {
            scheduler.removePending(ids: [id])
        }
    }

    private func needsNotification(_ chip: ChipEntity, at now: Date) -> Bool {
        chip.pausedAt == nil && chip.deadline <= now && !chip.zeroCrossingHandled
    }

    private func content(for chip: ChipEntity) -> NotificationContent {
        let trimmed = chip.label?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return NotificationContent(title: trimmed.isEmpty ? "Timer" : trimmed, body: "Time’s up")
    }

    // MARK: - Persistence

    private func fetchEntity(_ id: UUID) -> ChipEntity? {
        var descriptor = FetchDescriptor<ChipEntity>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    private func reload() throws {
        let all = try context.fetch(FetchDescriptor<ChipEntity>())
        let byID = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        chips = DeadlineState.displayOrder(all.map(\.snapshot)).compactMap { byID[$0.id] }
        restartTickingIfRunning()
    }

    /// Save now; on failure roll back the context and restore the in-memory list.
    private func commit() throws {
        do {
            try persist(context)
        } catch {
            context.rollback()
            try? reload()
            throw error
        }
        try reload()
    }
}
