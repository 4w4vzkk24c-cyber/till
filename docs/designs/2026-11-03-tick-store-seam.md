# Design: extract the display-tick driver from TimerStore

**Date:** 2026-11-03 · **Status:** IMPLEMENTED 2026-11-03 (unbuilt until the operator's test run; see Implementation notes) · **Card:** none filed yet
**Origin:** codebase-design pass (module inventory + seam survey, all MEASURED against `Sources/` this date)
**Sequencing guard:** was "do NOT build until card #1859 lands"; the operator lifted it after PR #1 (card 1859's work) was merged.

## Problem

`TimerStore` is two modules sharing one interface. Measured (2026-11-03, `Sources/Till/Store/TimerStore.swift`):
23 funcs, of which the **chip-mutation vocabulary** is 5 (`createChip/markDone/pause/resume/edit`) plus
queries, and the **display-tick vocabulary** is 6 (`tick/nextTickInterval/startTicking/stopTicking/isTicking`
+ the `popoverOpen` write path) plus notification authorization. Consequences, in the codebase-design sense:

- **Interface learns the wrong things.** A caller calling `createChip` must know ticking exists; a tick-cadence
  test must construct the full persistence harness (container, context, scheduler, defaults, clock, persist, sleep).
- **Locality suffers in tests.** Every cadence test pays harness setup for behaviour that touches none of it.

The deletion test confirms `TimerStore` earns its keep — container lifetime ownership, single-flight
reconciliation, commit/rollback discipline reappear at every caller if deleted. The problem is width, not shallowness.

## Goal

One module, one vocabulary: `TimerStore` keeps ~17 funcs, all chip-shaped. The tick lifecycle moves behind
its own small interface. Test surface separates without changing any runtime behaviour.

## Non-goals

- No cadence change: `TickCadence.interval(popoverOpen:chips:now:)` stays the single authority (READ: design §7.4, TRC-01).
- No reconciliation change: single-flight rerun stays store-owned; the wake path (`SystemEventObserver` → `tick()` + `reconcile()`) is untouched.
- No view changes: `popoverOpen` remains store state driving the 1 s/30 s choice (MEASURED: `TimerStore.swift`, `SystemEvents.swift`).

## What actually varies across this seam

The **driver mechanism**: who decides *when* `store.tick()` runs — a Task tick loop, a display-link, or a
test stepping deterministically. That is the only variation. Everything the driver reads (chips, popoverOpen,
now) is already store state; everything it writes is already `tick()`. Per codebase-design: a real seam, not a
hypothetical one (it already has two consumers — the runtime loop and the test harness's manual step).

## Proposed shape

```swift
/// Reads the inputs the cadence needs, calls back when it's time. 2 methods.
@MainActor protocol DisplayTickDriving: AnyObject {
    /// Called once; the conformer owns its own task lifetime.
    func start(_ tickNow: @MainActor () -> Void)
    func stop()
}
```

Two adapters (real seam):

- `TaskDisplayTickDriver` — the existing loop verbatim: schedules on `TickCadence.interval(...)`,
  cancels on stop; constructed with a read closure `(popoverOpen, chips, now) -> TimeInterval` that
  delegates to `TickCadence.interval`.
- `ManualTickDriver` (tests) — collects ticks; tests assert on call counts and step explicitly,
  constructing neither container nor scheduler.

`TimerStore` loses `nextTickInterval/startTicking/stopTicking/isTicking/tickTask`; keeps `tick()`
(the reconciliation step, deep) and `popoverOpen` (chip-visible state the views and observers already set).
`AppModel` composes: creates the driver, wires it to the store.

**Alternative rejected — keep one TimerStore but split test files:** leaves every tick test still
constructing the persistence harness; the interface still teaches ticking to chip callers. Cost of the
split is one protocol + two small types, all movement, no new logic.

## Acceptance (mutation-shaped, not assertion-count)

- Deleting the driver module's branch makes tick behaviour vanish (no silent pass-through).
- A tick-cadence test exists that constructs **neither** `ModelContainer` nor `NotificationScheduling`.
- Existing cadence tests (READ: `Tests/TillTests/`, 20 files, several exercising tick through harness)
  pass unmodified or migrate mechanically; no test asserts on `tickTask` internals.
- `TimerStore` func count drops by ≥5 and every remaining func is chip- or authorization-shaped
  (MEASURED baseline: 23 funcs, `grep -c "func " TimerStore.swift`).

## Risks

- `AppModel.start()` ordering (store start vs driver start) — the loop's first tick must not race
  container readiness. Mitigation: driver starts only after `store.start()` completes; unchanged ordering from today.
- Swift 6 MainActor isolation of the read closure — same-isolation closure, no new Sendability surface.

## Implementation notes (2026-11-03)

What differs from the proposal above, and what was measured:

- **Three methods and a property, not two.** The loop used to restart when `popoverOpen` flipped and on every chip reload; with only `start`/`stop` nothing would re-read the interval after the extraction. `DisplayTickDriving` is `isRunning`, `start()`, `stop()` and `cadenceInputsChanged()` (restarts a running driver, no-op when stopped).
- **How the store tells the driver.** `TimerStore.onCadenceInputsChanged` (same pattern as `onChipsReloaded`) fires from the `popoverOpen` change and from `reload()`. `AppModel` wires it to the driver. The store never learns the driver exists.
- **Interval.** The store keeps the inputs and exposes `tickInterval` (a property wrapping `TickCadence.interval`); the driver is given it as a closure. `TickCadence` stays the single authority.
- **Removed from `TimerStore`:** `tickTask`, `nextTickInterval`, `startTicking`, `stopTicking`, `isTicking`, `restartTickingIfRunning`, and the injected `sleep`. Kept: `tick()`, `popoverOpen`.
- **Func count, measured with `grep -c "func "`:** 23 before, 20 after. Four removed, one added (`isActiveFuture`, the shared "not paused and not yet due" predicate used by `scheduleAllActiveFutures` and `scheduleIfPossible`). The acceptance line "drops by at least 5" counted a property (`isTicking`); the true drop is 4 gross, 3 net.
- **Tests.** The driver alone is tested with no container and no scheduler (`DisplayTickDriverTests`, plus `ManualTickDriver`). The old loop tests were migrated to wire the real driver to the store the way `AppModel` does; `Harness` no longer has a `sleep` parameter.
- **Not run.** The cloud has no Swift toolchain; the operator's run is the evidence. Behaviour is meant to be identical: tiles tick every second with the popover open or an approaching chip, every 30 seconds otherwise.

