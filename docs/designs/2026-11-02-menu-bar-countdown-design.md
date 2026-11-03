# Till — menu bar countdown monitor

**Date:** 2026-11-02 (gate-eligible r1, formalized same day) · **Status:** Gate-eligible design — ready for spec pass
**Owner:** Zane Robinson · **Lane:** `cofounder-macos-development` · **Ship as:** Crossed Keys Co.
**Card:** 1859 · **Provenance:** formalized from the operator-approved seed @ `1cc1b28` (idea `4a3ed107`); the ten settled decisions and the chip UI form are unchanged. Deltas from the seed are listed in §12 and reasoned inline.

Evidence labels: **MEASURED** = probed on this host or against the live service on 2026-11-02/03. **READ** = read from the cited primary documentation, not executed. Unlabeled platform facts are design decisions.

## 1. Constraints (named before solutions)

**Technical**
- macOS 26 deployment target, built with Xcode 27.2 / macOS SDK 27.2 / Swift 6.4.2 — **MEASURED** on this host (`xcodebuild -version`, `xcrun --sdk macosx --show-sdk-version`, `swift --version`).
- Single target, single process, agent app (`LSUIElement: true`): no Dock icon, no app-switcher entry. `MenuBarExtra` as the sole `Scene` — **READ**, Apple: "a scene that renders itself as a persistent control in the system menu bar," macOS 13+, and the utility-app pattern (MenuBarExtra as primary scene) is documented with `LSUIElement` as the no-Dock flag. `info.properties.LSUIElement: true` via xcodegen — **MEASURED** (xcodegen 2.45.4 generated the plist key; probe in run log).
- Swift 6 strict concurrency: one main-actor mutable owner (`TimerStore`); every unit below is either pure or main-actor-isolated; nothing global.
- Zero third-party runtime dependencies (mac-lane default: Apple frameworks + vendored/pinned assets only). No SPM packages, no backend, no accounts, no always-on server.
- **No network calls after chip creation.** Icon fetch + render happens once, at creation; everything after is local. This is a settled invariant and a testable one.
- Swift 6, SwiftUI throughout. No AppKit *UI* bridging. Two deliberate AppKit touches remain, both data/event APIs rather than UI: `NSImage` (the only image type SwiftUI on macOS can hold as a template asset) and `NSWorkspace.didWakeNotification` for wake detection (Swift-concurrency form: `NSWorkspace.DidWakeMessage`) — **READ**, Apple docs, macOS.

**Organizational**
- Solo developer; every always-on dependency is a pager Zane carries alone. The design minimizes runtime dependencies to Apple frameworks + a creation-time-only public API call.
- Repo: `~/Repositories/till`, xcodegen `project.yml` as source of truth (`.xcodeproj` generated, never hand-edited), Forgejo-hosted.
- Mac-lane conventions: tests run `CODE_SIGNING_ALLOWED=NO` with a custom `-derivedDataPath`; a build/test/notarization run is "passed" only with captured exit status and logs.

**Political**
- Direct distribution requires Apple Developer ID signing + notarization (Gatekeeper); notarization is a release-gate dependency on Apple's service, not a runtime one.
- Iconify is a free public service with documented rate limits; it is self-hostable (open source) — **READ**, `iconify.design/docs/api/`. Till's usage profile (2 calls per chip creation, zero afterward) is squarely inside its intended "load icons on demand" use case.
- Per-icon-set licenses (Apache-2.0, MIT, etc., returned by the search API per collection — **READ** + observed in API response). The picker shows the collection's license at pick time; an About line credits icon sources.

## 2. Verified external claims (evidence table)

| # | Claim | Status | Source |
|---|---|---|---|
| V1 | `MenuBarExtra` + `.menuBarExtraStyle(.window)` gives a popover-like window from the menu bar icon; macOS 13+; `LSUIElement=true` hides Dock/app-switcher; utility-app pattern where MenuBarExtra is the primary scene; app auto-terminates if the user removes the extra (use `isInserted` binding) | READ (docs) | developer.apple.com/documentation/swiftui/menubarextra |
| V2 | `SMAppService.mainApp` register()/unregister() is the modern login-item API, macOS 13+; `status`, `openSystemSettingsLoginItems()` | READ (docs) | developer.apple.com/documentation/servicemanagement/smappservice |
| V3 | `UNUserNotificationCenter.requestAuthorization(options:)` prompts once, stores the answer; async variant available; macOS 10.14+ | READ (docs) | developer.apple.com/documentation/usernotifications/unusernotificationcenter/requestauthorization(options:completionhandler:) |
| V4 | SwiftData `ModelContainer` manages schema + persistent storage; macOS 14+; CloudKit sync only if entitled (we are not) | READ (docs) | developer.apple.com/documentation/swiftdata/modelcontainer |
| V5 | Iconify public API serves `/{prefix}/{name}.svg` with `color` (`%23`-encoded), `width`/`height` params; `search?query=&limit=&prefix=` returns `icons[]` + collection metadata incl. license and `palette` flag | MEASURED (live: SVG 200, 262 B, `image/svg+xml`, fill honored; search docs + script usage) | iconify.design/docs/api/svg.html, /docs/api/search.html, live curl |
| V6 | Iconify public API does **not** render PNG: `/{prefix}/{name}.png` → HTTP 404 | MEASURED (live curl, 2026-11-03) | live probe |
| V7 | SVG→PNG rasterization works locally on this host (sips/ImageIO path) | MEASURED (96×96 RGBA PNG from fetched SVG) | local `sips` probe |
| V8 | xcodegen 2.45.4 emits `info.properties.LSUIElement` and honors `options.deploymentTarget.macOS` | MEASURED (generated plist inspected) | local probe |
| V9 | Host toolchain: Xcode 27.2, macOS SDK 27.2, Swift 6.4.2 — supports macOS 26 target | MEASURED | local probes |
| V10 | `NSWorkspace.didWakeNotification` / `NSWorkspace.DidWakeMessage` posts on wake from sleep | READ (docs) | developer.apple.com/documentation/appkit/nsworkspace/didwakenotification |

**Claims carried as READ-with-build-verification** (cannot be verified without running code; each has a named fallback):
- R1: `NSImage(data: svgData)` loads SVG on macOS 11+ and template-tinting (`isTemplate = true`, then SwiftUI tint) renders correctly. Fallback: rasterize via ImageIO/`CGImageSource` at fetch time and store PNG (V7 proves the host rasterization path).
- R2: missed `UNCalendarNotificationTrigger` deliveries land when the Mac wakes (standard system behavior). Fallback if false at test: the relaunch/wake reconciliation pass (§7.4) already covers it — one notification, at most one re-fire, flag-guarded.
- R3: MenuBarExtra label with glyph + small count text renders acceptably as the bar icon with badge. Fallback: `NSStatusItem` title-style count next to the glyph.

## 3. Function

Till is a prospective-memory offload: every open deadline is one glance away.
A single menu bar icon; the dropdown shows named timer chips side by side,
each with a unique icon, the time remaining until its deadline, and optionally
a label. Two inputs feed it — quick timers in minutes and dated deadlines in
hours/days — through one natural-language field. Overdue deadlines stay
visible until explicitly dismissed, and the bar icon itself escalates when any
chip is close or overdue.

Not a timer app: timers set-and-forget elsewhere fail precisely because nobody
reopens them. Till makes the deadline ambient.

## 4. Form (settled, unchanged)

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

Hero time format (normative, all digits monospaced, swap-per-tick):
- remaining ≥ 24 h → `3d 14h`
- 1 h ≤ remaining < 24 h → `14h 32m`
- remaining < 1 h → `32:41` (M:SS)
- overdue → `+2h overdue` (`+41m overdue` below one hour; floor at minutes)

## 5. Icons (pipeline corrected against measured evidence)

Any Iconify icon is fair game. The **seed's "fetch + PNG render via API" is corrected** (V6: the public API returns 404 for `.png`; the iOS lane's `ios-icon-gen` rasterizes locally, which is what "vendored" meant). The pipeline, all at creation time only:

1. **Search** — `GET https://api.iconify.design/search?query=<q>&limit=64[&prefix=<p>]`; results rendered in the picker with collection name + license. (V5)
2. **Fetch** — `GET https://api.iconify.design/{prefix}/{name}.svg?color=%23ffffff&height=256` — white-filled SVG, monotone icons honor the color param (V5). For monotone icons the returned SVG's fills are all `#ffffff`/`currentColor`; palette icons keep their own fills — **monotone-ness is detected by parsing the tiny SVG string's fill values** (measured 262 B), no extra API call.
3. **Render + cache** — monotone: rasterize the white SVG to PNG (V7 host path), store at `~/Library/Application Support/Till/icons/{prefix}--{name}.png`, load as `NSImage` with `isTemplate = true`, tint per-chip via SwiftUI foreground style (R1, fallback in §2). Palette icons: render as-is in their own colors, no template flag, no tint (accent brightening then applies to the time text only). Cache is content-keyed by icon id and shared across chips; an icon file is evicted when no chip references it.
4. **Offline fallback set** — a small bundle of template glyphs (SF Symbols renders, pinned in the repo) is offered when the API is unreachable, so chip creation never hard-fails on network. A fallback-icon chip can be re-picked later.
5. After creation the app makes **no network calls** — settled, and now structurally true: the only networked unit is the picker path.

Failure at any step: inline error in the add field, no chip persisted, retry by the user. No dialogs.

A custom art pass later is a pure asset swap — no code change.

## 6. State model (table verbatim from seed; normative rules beneath)

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

**Normative state rules (resolve the table's overlaps mechanically):**
- `approachWindow` is captured per chip at creation — 30 min for quick-timer input, 2 h for dated input — and persisted. This reconciles "quick timers and dated deadlines are indistinguishable after creation" (true for countdown, notification, and dismissal semantics) with the table's two thresholds: the only surviving distinction is this one display parameter.
- Precedence: **Dismissed → not rendered. Paused → Paused** (frozen remaining, dimmed, excluded from escalation and badging). Else **deadline ≤ now → Overdue**. Else **remaining ≤ approachWindow → Approaching**. Else **Clean**.
- Paused semantics: pause records `pausedAt`; frozen remaining = `deadline − pausedAt`; a paused chip never crosses to Overdue (its countdown is suspended, which is what "frozen" and "excluded from badging" require). Resume shifts the deadline: `deadline' = now + frozenRemaining`. Deadline is stored absolute; pause/resume is a store-level deadline mutation, so the state machine stays a pure function of `(deadline, now, paused, dismissed, approachWindow)`.
- Bar aggregation: worst active (non-paused) chip wins — Overdue > Approaching > Clean; ties broken by nearest deadline. Badge = count of active overdue chips. All paused (or none active) → dimmed glyph, no badge.

**Overdue semantics:** an overdue chip stays `+overdue` until the user clicks
Done on it. No auto-archival, no grace period in v1 (a fade-after-N-hours is
an additive later release if wanted).

**Zero crossing:** one local notification fires per overdue chip
(`UNUserNotificationCenter`), app-level toggle, default ON. The notification
is **pre-scheduled at creation** as a `UNCalendarNotificationTrigger` for the
absolute deadline (mechanism changed from the seed's "fire from the tick loop
on crossing" — reasoning in §7.4; the user-visible contract is unchanged: one
notification per chip, fires when due, survives app death and sleep) and is
removed on Done, on pause, and when the toggle is switched OFF.

## 7. Units and ownership record

Six units, independently testable. `~10–12` source files total. Per the mac-lane intake contract, each persistent/asynchronous feature names: owner of mutable state, isolation domain, creation point, teardown, error recipient, recovery policy.

### 7.1 `NaturalDeadline` — parser (pure)
- **Signature:** `parse(_ input: String, now: Date, calendar: Calendar, timeZone: TimeZone) throws -> ParsedDeadline` where `ParsedDeadline = { deadline: Date, approachWindow: TimeInterval, kind: quick|dated }` and errors are typed with user-facing inline-hint text.
- **Ownership:** stateless; no mutable state; no isolation domain. Pure function — the entire unit is table-testable.
- **Grammar (v1, normative):**
  - Quick: `in <N> <unit>` — unit ∈ `min|m|mins|minutes`, `h|hr|hour|hours`, `d|day|days`. Single term; compound (`in 1h30m`) is a v1 parse error with hint.
  - Weekday/clock: `(mon|tue|…|sun|weekday-full-names) <time>` and `(today|tomorrow) <time>`, `<time>` = `[H][:[MM]] (am|pm)` (e.g. `Fri 5pm`, `Fri 5:30pm`, `tomorrow 9am`). Time is required in this form; missing time → inline error.
  - Plain date: `Mon D` (`Nov 15`, `Feb 29`) — resolves to **09:00 local** on that date, next occurrence if already past this year (rolls to next year). The 09:00 default is a reasoned choice (a morning deadline is visible all of that day), flagged for the critic — it is the one seed-silent decision in the grammar.
  - Next-occurrence rule: any computed moment ≤ now rolls forward (weekday → next week; date → next year; `today 5pm` already past → inline error "already passed").
  - All resolution via `Calendar.date(byAdding:/.date(from: DateComponents)` in the user's current calendar/time zone; DST-nonexistent times use `Calendar`'s standard disambiguation; DST and leap-day edges are pinned in the test suite.
- **Errors:** typed, inline-hint text, no dialogs. Unparseable input stays in the field.
- **Teardown/recovery:** none needed (pure).

### 7.2 `IconProvider` — icon pipeline (network + disk, creation-time only)
- **Ownership:** `TimerStore` (main actor) owns the provider; the provider itself performs search/fetch/rasterize/cache and returns `IconAsset` values. It is the **only** unit that may touch the network.
- **Isolation:** network + rasterization off the main actor; results returned to the main actor as `Sendable` values (icon id, monotone flag, cached-file URL).
- **Creation point:** chip-creation flow only. **Teardown:** none (request-scoped `URLSession` tasks, cancelled if the popover/editor is dismissed mid-flight).
- **Errors recipient:** the add field (inline). **Recovery:** bundled offline fallback set; retry.
- **Invariants:** (1) no network after a chip exists — enforced by the unit's API surface (fetch only from the creation flow) and pinned by an offline round-trip test; (2) cache keyed by icon id, shared, evicted only when unreferenced; (3) monotone icons only get `isTemplate`; palette icons never get template rendering.

### 7.3 `DeadlineState` — state machine (pure)
- **Signature:** `state(of chip: ChipSnapshot, at now: Date) -> DeadlineState` plus `barEscalation(activeChips:, now:) -> BarIconState` (worst-active + badge count). Pure functions of `(deadline, now, pausedAt, dismissed, approachWindow)` — table-driven tests cover every row of §6 and the precedence list.
- **Ownership:** none (pure). No clocks inside — `now` is always injected.

### 7.4 `TimerStore` — the one mutable owner (main actor, `@Observable`)
- **Ownership:** single main-actor owner of the chip list and all mutations (create/edit/pause/resume/done/toggle). Views never mutate `ChipEntity` directly; they call store methods. No globals, no environment-mutating views.
- **Persistence:** SwiftData, one `ModelContainer` (in-memory in tests), one model `ChipEntity`: `id: UUID`, `iconId: String`, `iconMonotone: Bool`, `label: String?`, `accentHex: String`, `deadline: Date`, `approachWindow: TimeInterval`, `kind: String`, `createdDate: Date`, `acknowledgedAt: Date?` (reserved, written at Done), `pausedAt: Date?`, `zeroCrossingHandled: Bool`, `eventIdentifier: String?` (reserved, unused v1). No CloudKit, no sync, no export. Schema v1; no shipped versions → no migration (V4: automatic lightweight migration available later).
- **Tick loop (display only):** remaining time derives from `deadline − Date.now` each tick, never from accumulated durations — sleep, display sleep, and drift self-correct on wake. Cadence: 1 s while the popover is open, 30 s otherwise. The store owns the timer and reschedules on popover open/close.
- **Notifications (mechanism — adjusted from seed, contract unchanged):** at creation (if the toggle is ON and authorization granted) the store schedules one `UNCalendarNotificationTrigger` per chip via `UNUserNotificationCenter`, and sets `zeroCrossingHandled = true`. Pre-scheduling rather than tick-firing means the notification fires **even if the app process is not running** at the crossing, and missed-during-sleep deliveries land on wake (R2) — this subsumes the seed's "catch-up on wake" with strictly fewer failure modes. Removal on: Done, pause, toggle-off, deadline edit (reschedule). Authorization is requested on first timer creation, not at launch (settled).
- **Reconciliation pass (the catch-up backstop):** on launch and on `NSWorkspace.DidWakeMessage`, for each active chip with `deadline ≤ now && !zeroCrossingHandled`: fire one immediate notification, set the flag. This covers triggers never scheduled (toggle was off at creation and enabled later, authorization granted late, scheduling failure) and any R2 shortfall — the flag is the exactly-once guard across both mechanisms.
- **Pause/resume:** as §6 — record `pausedAt`, remove pending trigger; resume recomputes `deadline' = now + (deadline − pausedAt)`, reschedule trigger, clear `pausedAt`.
- **Creation point:** app start (composed in the `App` scene, injected into `MenuBarExtra` content). **Teardown:** timer invalidated on app termination; nothing persistent to tear down beyond the container.
- **Error recipient:** inline (creation path) / settings row (notification authorization states). **Recovery:** every mutation is a SwiftData save; a failed save surfaces inline and the in-memory state rolls back.

### 7.5 Chips view + bar icon (SwiftUI, immutable views)
- **Ownership:** no view state beyond local edit/picker sheets-in-popover; everything observable comes from `TimerStore`. Chips grid = `LazyVGrid` two columns inside the `MenuBarExtra` `.window`-style content. Chip card per §4 recipe; context menu (right-click) for Edit / Pause/Resume / Done; Edit loads the chip's fields back into the header field.
- **Bar icon:** `MenuBarExtra` label = static glyph with one of four template tints (normal/amber/red/dimmed) + overdue count as small adjacent text (R3). Driven by `barEscalation`.
- **Settings:** a footer row in the same popover (no secondary windows — settled): notification toggle (default ON), launch-at-login toggle (default OFF) via `SMAppService.mainApp` register/unregister with `status` displayed and `openSystemSettingsLoginItems()` offered when registration requires it (V2). Settings persist in `UserDefaults` (app settings, not domain data).

### 7.6 Settings + notification policy
Covered in 7.4/7.5: app-level toggle default ON; when toggled ON after creation, the store schedules triggers for all active future chips; when OFF, all pending triggers are removed. Denied authorization → toggle disabled with an explanatory line and a link to System Settings; the ambient bar-icon channel is unaffected.

## 8. System probes

**Failure modes (what breaks, symptom, detection, recovery):**
- *App not running at a crossing* (force-quit, logout, or the documented MenuBarExtra auto-terminate on user removal — V1): pre-scheduled triggers still fire (the reason for §7.4's mechanism). The bar icon is dark — accepted limitation; mitigated by launch-at-login. Detection: none needed; the notification is the evidence.
- *Machine asleep at crossing:* trigger delivery lands on wake (R2) + reconciliation pass as backstop (§7.4). Exactly one notification.
- *Notification permission denied / Focus suppresses delivery:* bar icon red + badge is the primary ambient channel by design; the notification is the backstop (seed's data-loss mode, kept). No data is lost — the chips persist.
- *Iconify unreachable at creation:* inline error; bundled fallback icons allow creation; no network dependency for any existing chip.
- *Icon cache corrupt/missing:* provider re-rasterizes from… nothing (SVG is not retained by design — cache holds the raster). Recovery: chip renders the bundled fallback glyph for that icon id until re-picked. (Cache is user-data-adjacent, not user data; chips never reference it for correctness.)
- *SwiftData store corruption:* worst case is losing chips — accepted for v1 (no sync, no export; the store lives next to app support). No migration risk in v1 (first schema).
- *Clock changes (NTP jump, manual change):* everything is absolute-deadline arithmetic; a clock jump shifts display instantaneously but triggers follow wall-clock via calendar triggers. DST pinned by tests.

**3 AM pager:** nobody gets paged. No server, no always-on service, no telemetry. The only wake-capable event is the user's own deadline notification. The operator-side 3 AM risk is notarization outage during a release — release-blocked, not user-facing; retry later.

**Dependency disappearance (what if X vanishes tomorrow):** see §9 — each external dependency has a named fallback; the app's ambient function degrades gracefully and never loses data.

## 9. External dependencies (each with a fallback)

| Dependency | Used for | When | Fallback if it disappears |
|---|---|---|---|
| Iconify public API (`api.iconify.design`) | icon search + SVG fetch | creation only | (a) bundled template glyph set — creation still works offline; (b) all existing chips unaffected (zero post-creation calls); (c) long-term: Iconify API is open source and self-hostable (V5 docs) — a future Till release can pin/self-host or vendor a set |
| Apple notarization service | release signing | release only | unsigned dev builds keep working locally; release waits for the service |
| `xcodegen` (2.45.4, dev tool) | project generation | dev only | committed generated `.xcodeproj` remains buildable; project.yml regenerates it |
| Apple OS frameworks (SwiftUI MenuBarExtra, SwiftData, UserNotifications, ServiceManagement, NSWorkspace) | everything | runtime | platform-stable within the deployment target; these are floor APIs (13+/14+) far below macOS 26, with no deprecation flags; no action |
| Forgejo | repo hosting | dev only | repo is local-first; any git host |

No other runtime dependencies exist. That is the point of the architecture.

## 10. Distribution

Developer ID + notarized direct distribution (Crossed Keys Co.). No Mac App
Store, no auto-updater in v1 (manual re-download; Sparkle is a later
release). Launch-at-login off by default, toggle in settings via
`SMAppService`. Hardened runtime + entitlements kept minimal (no network
entitlement beyond the default outgoing-sockets; no sandbox in v1 — direct
distribution, not App Store; documented as a deliberate choice).

## 11. Testing (mapped to units)

| Unit | Suite | Coverage that must exist |
|---|---|---|
| `NaturalDeadline` | `NaturalDeadlineTests` | grammar positives (every form above), every typed error + inline hint, next-occurrence rolls (weekday, date-to-next-year, today-past), `Nov 15` 09:00 default, DST spring-forward + fall-back edges, Feb 29 leap day, `in 1d` across month boundary, whitespace/case tolerance |
| `DeadlineState` | `DeadlineStateTests` | table-driven over every §6 row + full precedence list; bar aggregation: worst-active ordering, nearest-deadline tie-break, badge count, all-paused dimming; overdue display formats |
| `TimerStore` | `TimerStoreTests` | create→persist→reload round-trip (in-memory container); pause/resume deadline arithmetic exact; trigger schedule/remove/reschedule per mutation (mocked center); reconciliation: fires once (flag), never for dismissed, never when toggle off, wake-after-crossing single fire; toggle-on-late schedules all futures; edit re-parses and reschedules |
| `IconProvider` | `IconProviderTests` | monotone detection (white-fill SVG → template; palette SVG → non-template); cache round-trip + eviction-on-last-reference; fetch failure → typed error + fallback set; **offline invariant**: creation of a chip with cached icon makes zero network calls (URLProtocol mock) |
| Chips view / bar icon | build + manual checklist | popover layout per §4 recipe, two-per-row, context menu actions, static swap behavior (no transitions), bar tint/badge per escalation table; snapshot tests later if wanted |
| Whole app | acceptance | `xcodebuild test CODE_SIGNING_ALLOWED=NO -derivedDataPath <custom>` green with captured exit + logs (mac-lane evidence rule) |

swift-testing framework for unit suites (ships with the toolchain); no third-party test deps.

## 12. Deltas from the approved seed (HOW only; the ten settled decisions and the form are untouched)

1. **Icon PNG claim corrected:** public Iconify API does not render PNG (V6, measured). Pipeline is now fetch-SVG → local template rasterize → cache, monotone detection by SVG fill parsing, palette icons render untinted. Honors "any icon, fetched at creation, cached, template-rendered, no network after creation."
2. **Notification mechanism adjusted (catch-up strategy — explicitly delegated to this pass):** pre-scheduled `UNCalendarNotificationTrigger` at creation replaces tick-fired delivery. User contract unchanged (one notification per chip, default-ON toggle, catch-up on wake) — but it now also survives the app not running, which the seed's mechanism could not. Flag-guarded reconciliation pass keeps exactly-once semantics.
3. **`approachWindow` per chip** reconciles the table's 30 min / 2 h thresholds with "indistinguishable after creation" (the one display-level distinction that survives).
4. **Pause mechanics made precise:** `pausedAt` + deadline-shift-on-resume; paused chips cannot go overdue (frozen + excluded from badging required it).
5. **"No AppKit bridging" narrowed to no AppKit *UI* bridging;** `NSImage` and `NSWorkspace` (data/event APIs) are the two deliberate, documented exceptions.
6. **Overdue display formats and hero time formats made normative** (the seed was silent on the <1 h and ≥24 h formats).
7. **Offline fallback icon set** added (creation never hard-fails on network) — additive, consistent with settled #7.
8. **Done = delete row** (acknowledgedAt written first, reserved for a future archive view). No dead rows, no archive in v1.

## 13. Open questions for the design critic

1. **`Nov 15` → 09:00 default:** seed-silent; I chose 09:00 local. Alternatives: 17:00, or require an explicit time. Operator taste call — surface it.
2. R1/R2/R3 are READ-not-measured; each has a named fallback, but the critic should confirm the fallbacks are cheap enough to be real.
3. Monotone-vs-palette rendering: is "palette icons render untinted" acceptable, or should v1 restrict the picker to monotone collections (contradicts "any icon" — I chose to honor any icon)?
4. Badge-as-adjacent-text in the MenuBarExtra label (R3) vs. a title-string count — which reads better at 1 glance?
5. No-sandbox-for-direct-distribution (§10): deliberate; confirm the critic agrees it's the right v1 posture for a non-App-Store agent app.

## 14. Explicitly out of scope (v1)

- EventKit / calendar reading (design reserves `eventIdentifier`; additive later)
- Any animation
- Recurring deadlines
- Sync, export, sharing
- Sparkle auto-update

## 15. Repo

`~/Repositories/till`, xcodegen (`project.yml` is source of truth), pushed to
Forgejo after the design lands.
