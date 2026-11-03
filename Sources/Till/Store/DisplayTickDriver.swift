import Foundation

/// Decides when the store's `tick()` runs (design `2026-11-03-tick-store-seam.md`). The one
/// thing that varies is the mechanism: a task loop at runtime, a manual step in tests.
/// Everything the driver reads (popover state, chips, clock) stays store state, behind the
/// `interval` closure it is given.
@MainActor
protocol DisplayTickDriving: AnyObject {
    var isRunning: Bool { get }
    /// Idempotent. Ticks once immediately, then on the driver's own schedule.
    func start()
    /// Idempotent.
    func stop()
    /// The interval's inputs changed (the popover opened or closed, a chip changed): read the
    /// interval again now. Restarts a running driver; does nothing when stopped.
    func cadenceInputsChanged()
}

/// The display tick loop, moved verbatim out of `TimerStore`: tick, sleep for the current
/// interval, repeat. The task holds the driver weakly and never across the sleep.
@MainActor
final class TaskDisplayTickDriver: DisplayTickDriving {
    private let interval: @MainActor () -> TimeInterval
    private let tick: @MainActor () -> Void
    private let sleep: @MainActor (TimeInterval) async throws -> Void
    private var task: Task<Void, Never>?

    init(
        interval: @escaping @MainActor () -> TimeInterval,
        tick: @escaping @MainActor () -> Void,
        sleep: @escaping @MainActor (TimeInterval) async throws -> Void = {
            try await Task.sleep(for: .seconds($0))
        }
    ) {
        self.interval = interval
        self.tick = tick
        self.sleep = sleep
    }

    var isRunning: Bool { task != nil }

    func start() {
        guard task == nil else { return }
        tick()
        let sleep = self.sleep
        task = Task { [weak self] in
            while !Task.isCancelled {
                guard let interval = self?.interval() else { return }
                do { try await sleep(interval) } catch { return }
                guard let driver = self else { return }
                driver.tick()
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    func cadenceInputsChanged() {
        guard task != nil else { return }
        stop()
        start()
    }
}
