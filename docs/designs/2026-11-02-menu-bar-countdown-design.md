# Till — menu bar countdown monitor

**Date:** 2026-11-02 · **Status:** Approved design, pending implementation plan
**Owner:** Zane Robinson · **Lane:** `cofounder-macos-development` · **Ship as:** Crossed Keys Co.

## Function

Till is a prospective-memory offload: every open deadline is one glance away.
A single menu bar icon; the dropdown shows named timer chips side by side,
each with a unique icon, the time remaining until its deadline, and optionally
a label. Two inputs feed it — quick timers in minutes and dated deadlines in
hours/days — through one natural-language field. Overdue deadlines stay
visible until explicitly dismissed, and the bar icon itself escalates when any
chip is close or overdue.

Not a timer app: timers set-and-forget elsewhere fail precisely because nobody
reopens them. Till makes the deadline ambient.

## Form (final, no animation)

- **One menu bar item.** No Dock presence, no main window, no secondary windows.
- **Dropdown = `MenuBarExtra` (windowed style)** popover: a header with the add
  field, then a grid of chips, two per row.
- **Chip:** unique icon (40–48pt, accent-tinted) → label (caption, gray) →
  remaining time as the hero element (large, rounded design, monospaced
  digits) → optional text label → minimal pause control. Rounded-rectangle
  card (~16pt corner, dark warm-gray fill), ~140–160pt wide, 10pt gutters,
  generous top padding above the icon.
- **No animation anywhere.** Static glyphs and static chips; state changes are
  swaps, never transitions.
- **`+overdue` state:** time text swaps to `+2h overdue` in red; icon stays.

## Icons

Any Iconify icon is fair game. At creation time the app fetches the chosen
icon via the Iconify API (same pipeline as the iOS lane's `ios-icon-gen`,
vendored), converts to a template image, and caches it locally. After
creation the app makes no network calls. Per-timer accent color tints the
template. A custom art pass later is a pure asset swap — no code change.

## State model

Each deadline chip (owned by a main-actor `TimerStore`, persisted as one
`ChipEntity` in SwiftData: icon id, label, deadline, accent, created /
acknowledged dates, paused flag, `eventIdentifier` reserved for later
EventKit):

| State | Source | Chip shows | Bar icon |
|---|---|---|---|
| Clean | nearest > 1h away | normal time | normal glyph |
| Approaching | nearest within final stretch (≤ 30 min for timers; ≤ 2h for dated) | normal time, accent brightens | amber-tinted glyph |
| Overdue | deadline passed, not dismissed | `+2h overdue`, red | red-tinted glyph + overdue count badge |
| Paused | user paused | frozen remaining time, dimmed | excluded from badging; dimmed glyph if nothing active |

Bar-icon badge counts overdue chips; one static glyph, four tint variants.
Escalation is driven by the worst active chip, nearest deadline wins ties.

**Overdue semantics:** an overdue chip stays `+overdue` until the user clicks
Done on it. No auto-archival, no grace period in v1 (a fade-after-N-hours is
an additive later release if wanted).

**Zero crossing:** one local notification fires per overdue chip
(`UNUserNotificationCenter`), app-level toggle in settings, default ON.
Re-fires only when the app returns from being unreachable mid-deadline (see
Reliability).

## Input

One parser field covers both kinds of deadline. v1 grammar:

- Quick timers: `in 20 min`, `in 1 hour`, `in 3d`
- Weekday + clock time: `Fri 5pm`, `tomorrow 9am`
- Plain dates: `Nov 15` (next occurrence)

Parsing converts everything to an absolute deadline at creation; quick timers
and dated deadlines are indistinguishable thereafter. The parser is one
isolated unit (`NaturalDeadline`) with its own test suite. Unparseable input
stays in the field with an inline hint — no error dialogs.

Chip creation: type the deadline, pick an Iconify icon + accent, optionally
add a label, Enter. Edit/pause/done live on a per-chip context menu
(long-press or right-click).

## Architecture

- **Single target, native macOS menu-bar app.** Swift 6, SwiftUI throughout,
  no AppKit bridging. Deployment target macOS 26.
- **Composition root:** `MenuBarExtra` + `TimerStore` (`@Observable`, one
  main-actor mutable owner; no globals).
- **Ticks:** remaining time derives from `deadline − Date.now` on each tick,
  never from accumulated durations — sleep, display sleep, and drift
  self-correct on wake. Quick timers convert to absolute deadlines at
  creation. Tick cadence: 1s while a chip is visible or within its final
  stretch, 30s otherwise.
- **Persistence:** SwiftData, one model (`ChipEntity`). No CloudKit, no
  sync, no export in v1.
- **Notifications:** `UNUserNotificationCenter` with provisional-free
  authorized flow; authorization requested on first timer creation, not at
  launch.
- **Units:** parser (`NaturalDeadline`), icon pipeline (`IconProvider`),
  state machine (`DeadlineState`), store, chips view, settings. Independent
  and testable; ~8–10 source files.

## Reliability

- The tick loop is owned by the store and survives app sleep/wake cycles by
  recomputing, never accumulating.
- If the machine was asleep at a deadline's crossing, the notification fires
  on wake (single catch-up, and only if still undismissed).
- Missed-notification data-loss mode: the bar icon's red + badge is the
  primary signal, the notification is the backstop — so a notification
  failure still leaves the ambient channel intact.

## Distribution

Developer ID + notarized direct distribution (Crossed Keys Co.). No Mac App
Store, no auto-updater in v1 (manual re-download; Sparkle is a later
release). Launch-at-login off by default, toggle in settings via
`SMAppService`.

## Explicitly out of scope (v1)

- EventKit / calendar reading (design reserves `eventIdentifier`; additive later)
- Any animation
- Recurring deadlines
- Sync, export, sharing
- Sparkle auto-update

## Testing

- Parser: full unit suite (grammar cases, error cases, leap/dst edges)
- State machine: pure function of (deadline, now, paused, dismissed) — table-driven tests
- Persistence: store round-trip, migration-free v1
- UI: build + manual verification against the chip recipe; snapshot later if needed
- Acceptance: `CODE_SIGNING_ALLOWED=NO` test run green + captured xcodebuild evidence

## Repo

`~/Repositories/till`, xcodegen (`project.yml` is source of truth), pushed to
Forgejo after the design lands.