# Till — menu bar countdown monitor

**Date:** 2026-11-02 (r1 formalized; r2 revised same day) · **Status:** Design r2 — round-1 critic findings (request-changes) addressed; ready for re-critique
**Owner:** Zane Robinson · **Lane:** `cofounder-macos-development` · **Ship as:** Crossed Keys Co.
**Card:** 1859 · **Provenance:** formalized from the operator-approved seed @ `1cc1b28` (idea `4a3ed107`); the ten settled decisions and the chip UI form are unchanged. Deltas from the seed are listed in §12 and reasoned inline. **r2 folds in:** two operator decisions (palette icons untinted; date-only deadlines prompt for a time — both approved 2026-11-02 18:32), two parent directives (icon change = delete-and-recreate; tick cadence reverted to the seed verbatim), and all six round-1 critic findings (FEAS-01, FR-01, CON-01, AMB-01, SUF-01, FEAS-02).

Evidence labels: **MEASURED** = probed on this host or against the live service on 2026-11-02/03. **READ** = read from the cited primary documentation, not executed. Unlabeled platform facts are design decisions.

## 1. Constraints (named before solutions)

**Technical**
- macOS 26 deployment target, built with Xcode 27.2 / macOS SDK 27.2 / Swift 6.4.2 — **MEASURED** on this host (`xcodebuild -version`, `xcrun --sdk macosx --show-sdk-version`, `swift --version`).
- Single target, single process, agent app (`LSUIElement: true`): no Dock icon, no app-switcher entry. `MenuBarExtra` as the sole `Scene` — **READ**, Apple: "a scene that renders itself as a persistent control in the system menu bar," macOS 13+, and the utility-app pattern (MenuBarExtra as primary scene) is documented with `LSUIElement` as the no-Dock flag. `info.properties.LSUIElement: true` via xcodegen — **MEASURED** (xcodegen 2.45.4 generated the plist key; probe in run log).
- Swift 6 strict concurrency: one main-actor mutable owner (`TimerStore`); every unit below is either pure or main-actor-isolated; nothing global.
- Zero third-party runtime dependencies (mac-lane default: Apple frameworks + vendored/pinned assets only). No SPM packages, no backend, no accounts, no always-on server.
- **No network calls after chip creation.** Icon fetch + render happens once, at creation; everything after is local. This is a settled invariant and a testable one.
- Swift 6, SwiftUI throughout. No AppKit *UI* bridging. Three deliberate AppKit touches remain (r2 adds the third), all data/event APIs rather than UI: `NSImage` (the only image type SwiftUI on macOS can hold as a template asset), `NSWorkspace.didWakeNotification` for wake detection (Swift-concurrency form: `NSWorkspace.DidWakeMessage`), and `NSApplication.didBecomeActiveNotification` for the notification-authorization re-check (§7.4) — **READ**, Apple docs, macOS.

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

**Claims carried as READ-with-build-verification** (cannot be verified without running code; each has a named fallback, decomposed and cost-graded per FEAS-02):
- R1: `NSImage(data: svgData)` loads SVG on macOS 11+ and template-tinting (`isTemplate = true`, then SwiftUI tint) renders correctly. Fallbacks, decomposed: if decode works but template tinting renders wrong, rasterize the decoded `NSImage` to PNG at fetch time via `NSBitmapImageRep` and cache the PNG — in-app SVG decode on macOS is an `NSImage` path, not bare `CGImageSource`, and this fallback stays on that same path (V7 proves host SVG→PNG rasterization is achievable); if SVG decode itself fails, the bundled fallback glyph set (§5 step 4) covers it.
- R2: missed `UNCalendarNotificationTrigger` deliveries land when the Mac wakes (standard system behavior). Fallback if false at test — re-derived from the fixed mechanism (§7.4, FEAS-01): the reconciliation pass detects scheduled-but-undelivered state directly. A trigger still pending past its fire date is removed and replaced with one immediate notification; a trigger dropped without delivering is absent from both pending and delivered state and gets one immediate notification. Either way the chip receives exactly one notification from that point, guarded by a flag set only on observed delivery — disclosed bound: at most one re-fire, only if the original delivered and was dismissed before any observation.
- R3: MenuBarExtra label with glyph + small count text renders acceptably as the bar icon with badge. Fallbacks, cost-graded: (1) cheap — drop the count text, glyph-only with tint escalation and no badge; (2) last resort, an architecture swap — `NSStatusItem` title-style count next to the glyph.

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

1. **Search** — `GET https://api.iconify.design/search?query=<q>&limit=64[&prefix=<p>]`; results rendered in the picker with collection name + license. (V5) The picker **discloses the conditional tint at pick time** (operator-approved 2026-11-02 18:32): monotone icons render template + accent tint, palette (multicolor) icons render as-is, untinted. The disclosure uses the search API's collection-level `palette` flag (V5); the authoritative monotone-ness is still detected at fetch time (step 2), and on mismatch the fetched asset wins.
2. **Fetch** — `GET https://api.iconify.design/{prefix}/{name}.svg?color=%23ffffff&height=256` — white-filled SVG, monotone icons honor the color param (V5). For monotone icons the returned SVG's fills are all `#ffffff`/`currentColor`; palette icons keep their own fills — **monotone-ness is detected by parsing the tiny SVG string's fill values** (measured 262 B), no extra API call.
3. **Render + cache** — monotone: rasterize the white SVG to PNG (V7 host path), store at `~/Library/Application Support/Till/icons/{prefix}--{name}.png`, load as `NSImage` with `isTemplate = true`, tint per-chip via SwiftUI foreground style (R1, fallback in §2). Palette icons: render as-is in their own colors, no template flag, no tint (accent brightening then applies to the time text only). Cache is content-keyed by icon id and shared across chips; an icon file is evicted when no chip references it.
4. **Offline fallback set** — a small bundle of template glyphs (SF Symbols renders, pinned in the repo) is offered when the API is unreachable, so chip creation never hard-fails on network. A chip created with a fallback icon keeps it: **changing a chip's icon is delete-and-recreate, not an edit** (parent directive, r2). There is no post-creation re-pick path, so "no network after creation" holds with no exception. Recreating with the same icon id is served from the shared cache; recreating with a different icon id is a fresh creation-time fetch, which the invariant allows.
5. After creation the app makes **no network calls** — settled, and now structurally true: the only networked unit is the picker path.

Failure at any step: inline error in the add field, no chip persisted, retry by the user. No dialogs.

**Creation sequence (normative, ordered — SUF-01, r2): parse → time prompt (date-only input only) → icon fetch → persist → schedule.**
1. **Parse** (instant). Typed inline error if unparseable — nothing later runs.
2. **Time prompt** — only when the parser returns `timePromptRequired: true` (plain-date input, §7.1): the field presents an inline time prompt pre-filled with 09:00 local, one tap to accept (operator-approved 2026-11-02 18:32 — no silent default). Cancel aborts creation; nothing is persisted.
3. **Icon fetch** (the only network step). While it is in flight the add field shows a static pending caption (no spinner — no animation, §4), Enter is inert, and dismissing the popover cancels the in-flight request — no chip exists yet at this stage.
4. **Persist** — `ChipEntity` saved to SwiftData. The order is deliberate: persist before schedule, so a scheduling failure leaves a live chip that the reconciliation pass (§7.4) can backstop — never an orphaned trigger without a chip.
5. **Schedule** — the notification trigger (§7.4) if the toggle is ON and authorization is granted. A scheduling failure does not fail creation: the flag stays false and reconciliation catches the chip at its crossing.

A custom art pass later is a pure asset swap — no code change.

## 6. State model (table illustrative, retained verbatim from seed; the precedence list below is the sole normative definition)

Each deadline chip (owned by a main-actor `TimerStore`, persisted as one
`ChipEntity` in SwiftData: icon id, label, deadline, accent, created date,
paused flag, `eventIdentifier` reserved for later
EventKit):

| State | Source | Chip shows | Bar icon |
|---|---|---|---|
| Clean | nearest > 1h away | normal time | normal glyph |
| Approaching | nearest within final stretch (≤ 30 min for timers; ≤ 2h for dated) | normal time, accent brightens | amber-tinted glyph |
| Overdue | deadline passed, not dismissed | `+2h overdue`, red | red-tinted glyph + overdue count badge |
| Paused | user paused | frozen remaining time, dimmed | excluded from badging; dimmed glyph if nothing active |

Bar-icon badge counts overdue chips; one static glyph, four tint variants.
Escalation is driven by the worst active chip, nearest deadline wins ties.

**Normative state rules — this list, not the table, is the sole normative state definition (CON-01, r2). The table above is illustrative, kept verbatim from the seed; any case no row names is decided here — e.g. a 45-minute quick timer is Clean (45 m > its 30 m approachWindow) although no illustrative row names it:**
- `approachWindow` is captured per chip at creation — 30 min for quick-timer input, 2 h for dated input — and persisted. This reconciles "quick timers and dated deadlines are indistinguishable after creation" (true for countdown, notification, and dismissal semantics) with the table's two thresholds: the only surviving distinction is this one display parameter.
- Precedence (Done deletes the row, so the seed's "Dismissed → not rendered" is vacuous in v1 — a chip is either in the store or it is gone): **Paused → Paused** (frozen remaining, dimmed, excluded from escalation and badging). Else **deadline ≤ now → Overdue**. Else **remaining ≤ approachWindow → Approaching**. Else **Clean**.
- Paused semantics: pause records `pausedAt`; frozen remaining = `deadline − pausedAt`; a paused chip never crosses to Overdue (its countdown is suspended, which is what "frozen" and "excluded from badging" require). Resume shifts the deadline: `deadline' = now + frozenRemaining`. Deadline is stored absolute; pause/resume is a store-level deadline mutation, so the state machine stays a pure function of `(deadline, now, paused, approachWindow)`.
- Overdue cannot be paused (AMB-01, r2): the pause control is unavailable on an overdue chip — Done is the only exit from Overdue (settled #3). This closes the paused-while-overdue edge (frozen negative remaining) by excluding the action, not by specifying a frozen `+…overdue` paused display.
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
- **Signature:** `parse(_ input: String, now: Date, calendar: Calendar, timeZone: TimeZone) throws -> ParsedDeadline` where `ParsedDeadline = { deadline: Date, approachWindow: TimeInterval, kind: quick|dated, timePromptRequired: Bool }` and errors are typed with user-facing inline-hint text. `timePromptRequired` is true only for plain-date input (below): `deadline` then carries the resolved date at the suggested 09:00 local time, and the creation flow must prompt for the time (§5 creation sequence) before anything is persisted; it is false for every other form.
- **Ownership:** stateless; no mutable state; no isolation domain. Pure function — the entire unit is table-testable.
- **Grammar (v1, normative):**
  - Quick: `in <N> <unit>` — unit ∈ `min|m|mins|minutes`, `h|hr|hour|hours`, `d|day|days`. Single term; compound (`in 1h30m`) is a v1 parse error with hint.
  - Weekday/clock: `(mon|tue|…|sun|weekday-full-names) <time>` and `(today|tomorrow) <time>`, `<time>` = `[H][:[MM]] (am|pm)` (e.g. `Fri 5pm`, `Fri 5:30pm`, `tomorrow 9am`). Time is required in this form; missing time → inline error.
  - Plain date: `Mon D` (`Nov 15`, `Feb 29`) — resolves the date (next occurrence if already past this year, rolls to next year) and returns `timePromptRequired: true`: the creation flow prompts for a time, pre-filled with **09:00 local** as the suggestion, one tap to accept (operator-approved 2026-11-02 18:32 — no silent default; the 09:00 suggestion keeps a morning deadline visible all of that day).
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
- **Signature:** `state(of chip: ChipSnapshot, at now: Date) -> DeadlineState` plus `barEscalation(activeChips:, now:) -> BarIconState` (worst-active + badge count). Pure functions of `(deadline, now, pausedAt, approachWindow)` — Done deletes the row, so there is no dismissed state to model — table-driven tests cover every row of §6 and the precedence list.
- **Ownership:** none (pure). No clocks inside — `now` is always injected.

### 7.4 `TimerStore` — the one mutable owner (main actor, `@Observable`)
- **Ownership:** single main-actor owner of the chip list and all mutations (create/edit/pause/resume/done/toggle). Views never mutate `ChipEntity` directly; they call store methods. No globals, no environment-mutating views.
- **Persistence:** SwiftData, one `ModelContainer` (in-memory in tests), one model `ChipEntity`: `id: UUID`, `iconId: String`, `iconMonotone: Bool`, `label: String?`, `accentHex: String`, `deadline: Date`, `approachWindow: TimeInterval`, `kind: String`, `createdDate: Date`, `acknowledgedAt: Date?` (schema-reserved for a future archive view only — never written in v1; Done deletes the row, AMB-01), `pausedAt: Date?`, `zeroCrossingHandled: Bool` (set at first observed delivery, not at scheduling — §7.4 notifications), `eventIdentifier: String?` (reserved, unused v1). No CloudKit, no sync, no export. Schema v1; no shipped versions → no migration (V4: automatic lightweight migration available later).
- **Tick loop (display only):** remaining time derives from `deadline − Date.now` each tick, never from accumulated durations — sleep, display sleep, and drift self-correct on wake. **Cadence (seed, verbatim — r2 reverts the r1 change): "1s while a chip is visible or within its final stretch, 30s otherwise."** "Visible" = the popover is open; "final stretch" = the chip's persisted `approachWindow` (the term the seed's own table uses for the 30 min / 2 h thresholds). The store owns the timer and reschedules when the popover opens or closes, when a chip enters or leaves its final stretch, and on chip mutations.
- **Notifications (mechanism — adjusted from seed, contract unchanged):** at creation (if the toggle is ON and authorization granted) the store schedules one `UNCalendarNotificationTrigger` per chip via `UNUserNotificationCenter`. **The flag is NOT set at scheduling (FEAS-01, r2): `zeroCrossingHandled` means "delivery observed" and is set only when delivery is actually observed** — by the delegate on user interaction, or by the reconciliation pass confirming delivery state. The store is the center's delegate (main actor), so a user interaction with a delivered notification sets the flag at first observed delivery. Pre-scheduling rather than tick-firing means the notification fires **even if the app process is not running** at the crossing, and missed-during-sleep deliveries land on wake (R2) — this subsumes the seed's "catch-up on wake" with strictly fewer failure modes. Removal on: Done, pause, toggle-off, deadline edit (reschedule). Authorization is requested on first timer creation, not at launch (settled).
- **Reconciliation pass (the catch-up backstop — checks pending/delivered state, not just the flag):** on launch and on `NSWorkspace.DidWakeMessage`, for each chip in the store with `deadline ≤ now && !zeroCrossingHandled` (Done deletes the row and overdue chips cannot be paused, so every such chip is active), the store reads `getPendingNotificationRequests()` and `getDeliveredNotifications()`:
  - trigger **still pending past its fire date** (scheduled, undelivered — the R2-false case): remove the stale request, fire one immediate notification, set the flag;
  - trigger **absent from pending, present in delivered**: delivered — set the flag, fire nothing;
  - trigger **absent from both**: never scheduled (toggle off or authorization denied at creation, scheduling failure) or delivered-then-dismissed before any observation — fire one immediate notification, set the flag. Disclosed bound: this is the one window in which a chip can see a second notification (at most one re-fire, only if the user dismissed the original before the app next observed it); the alternative — never firing for never-scheduled chips — is the data-loss mode the seed forbids.

  The flag now guards mechanisms that can actually distinguish scheduled-but-undelivered from delivered, so the R2 fallback (§2) is derived from a real backstop rather than one sharing its guard with the failure it covers. Toggle currently OFF → reconciliation fires nothing.
- **Authorization watcher (FR-01, r2):** on `NSApplication.didBecomeActiveNotification` and on each launch/wake reconciliation, the store re-reads `getNotificationSettings()`; on a denied→granted transition (toggle ON) it schedules triggers for all chips with `deadline > now` — chips created while authorization was denied get their triggers without waiting to cross first and be caught by reconciliation. Owned by `TimerStore` (main actor); tested via a mocked settings provider.
- **Pause/resume:** as §6 — record `pausedAt`, remove pending trigger; resume recomputes `deadline' = now + (deadline − pausedAt)`, reschedule trigger, clear `pausedAt`.
- **Creation point:** app start (composed in the `App` scene, injected into `MenuBarExtra` content). **Teardown:** timer invalidated on app termination; nothing persistent to tear down beyond the container.
- **Error recipient:** inline (creation path) / settings row (notification authorization states). **Recovery:** every mutation is a SwiftData save; a failed save surfaces inline and the in-memory state rolls back.

### 7.5 Chips view + bar icon (SwiftUI, immutable views)
- **Ownership:** no view state beyond local edit/picker sheets-in-popover; everything observable comes from `TimerStore`. Chips grid = `LazyVGrid` two columns inside the `MenuBarExtra` `.window`-style content. Chip card per §4 recipe; context menu (right-click) for Edit / Pause/Resume / Done; Edit loads the chip's fields back into the header field. Edit covers label and deadline only (both local); the pause control is unavailable on overdue chips (§6); an icon change is delete-and-recreate (§5 step 4) — there is no icon edit path.
- **Bar icon:** `MenuBarExtra` label = static glyph with one of four template tints (normal/amber/red/dimmed) + overdue count as small adjacent text (R3). Driven by `barEscalation`.
- **Settings:** a footer row in the same popover (no secondary windows — settled): notification toggle (default ON), launch-at-login toggle (default OFF) via `SMAppService.mainApp` register/unregister with `status` displayed and `openSystemSettingsLoginItems()` offered when registration requires it (V2). Settings persist in `UserDefaults` (app settings, not domain data).

### 7.6 Settings + notification policy
Covered in 7.4/7.5: app-level toggle default ON; when toggled ON after creation, the store schedules triggers for all active future chips; when OFF, all pending triggers are removed. Denied authorization → toggle disabled with an explanatory line and a link to System Settings; the ambient bar-icon channel is unaffected. **Authorization granted later (FR-01, r2):** the authorization watcher (§7.4) reschedules active futures on the denied→granted transition, so a chip created while denied still gets its notification without waiting to cross.

## 8. System probes

**Failure modes (what breaks, symptom, detection, recovery):**
- *App not running at a crossing* (force-quit, logout, or the documented MenuBarExtra auto-terminate on user removal — V1): pre-scheduled triggers still fire (the reason for §7.4's mechanism). The bar icon is dark — accepted limitation; mitigated by launch-at-login. Detection: none needed; the notification is the evidence.
- *Machine asleep at crossing:* trigger delivery lands on wake (R2); if it does not, the reconciliation pass detects pending-past-fire-date or dropped state directly and fires exactly one (§7.4). At most one re-fire, only in the delivered-and-dismissed-before-observation window (disclosed, §7.4).
- *Notification permission denied / Focus suppresses delivery:* bar icon red + badge is the primary ambient channel by design; the notification is the backstop (seed's data-loss mode, kept). No data is lost — the chips persist. Permission granted later → the authorization watcher reschedules active futures (§7.4).
- *Iconify unreachable at creation:* inline error; bundled fallback icons allow creation; no network dependency for any existing chip.
- *Icon cache corrupt/missing:* provider re-rasterizes from… nothing (SVG is not retained by design — cache holds the raster). Recovery: the chip renders the bundled fallback glyph for that icon id; getting the real icon back is delete-and-recreate (§5 step 4) — a recreate with the same icon id re-fetches at creation time, which the invariant allows. (Cache is user-data-adjacent, not user data; chips never reference it for correctness.)
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
| `NaturalDeadline` | `NaturalDeadlineTests` | grammar positives (every form above), every typed error + inline hint, next-occurrence rolls (weekday, date-to-next-year, today-past), `Nov 15` → date resolved + `timePromptRequired: true` with the 09:00 suggestion (operator-approved prompt contract), DST spring-forward + fall-back edges, Feb 29 leap day, `in 1d` across month boundary, whitespace/case tolerance |
| `DeadlineState` | `DeadlineStateTests` | table-driven over every §6 row + full precedence list; bar aggregation: worst-active ordering, nearest-deadline tie-break, badge count, all-paused dimming; overdue display formats |
| `TimerStore` | `TimerStoreTests` | create→persist→reload round-trip (in-memory container); creation-sequence order (persist before schedule) and date-only prompt accept/cancel paths; pause/resume deadline arithmetic exact; pause unavailable/rejected for overdue chips; trigger schedule/remove/reschedule per mutation (mocked center); flag NOT set at scheduling, set at observed delivery (mocked delegate interaction); reconciliation against mocked pending/delivered state: pending-past-fire-date → remove + fire once, delivered → flag only + no fire, absent-from-both → fire once, never for dismissed, never when toggle off, wake-after-crossing single fire; toggle-on-late schedules all futures; authorization denied→granted (mocked settings) reschedules active futures; edit re-parses and reschedules |
| `IconProvider` | `IconProviderTests` | monotone detection (white-fill SVG → template; palette SVG → non-template); cache round-trip + eviction-on-last-reference; fetch failure → typed error + fallback set; **offline invariant**: creation of a chip with cached icon makes zero network calls (URLProtocol mock) |
| Chips view / bar icon | build + manual checklist | popover layout per §4 recipe, two-per-row, context menu actions, static swap behavior (no transitions), bar tint/badge per escalation table; snapshot tests later if wanted |
| Whole app | acceptance | `xcodebuild test CODE_SIGNING_ALLOWED=NO -derivedDataPath <custom>` green with captured exit + logs (mac-lane evidence rule) |

swift-testing framework for unit suites (ships with the toolchain); no third-party test deps.

## 12. Deltas from the approved seed (HOW only; the ten settled decisions and the form are untouched — one operator-approved exception: settled #7's template tint is scoped to monotone icons, delta 1)

1. **Icon PNG claim corrected:** public Iconify API does not render PNG (V6, measured). Pipeline is now fetch-SVG → local template rasterize → cache, monotone detection by SVG fill parsing at fetch time, palette icons render untinted — settled #7's tint re-scoped to monotone-only and **operator-approved 2026-11-02 18:32**, with the conditional tint disclosed in the picker UI (§5 step 1). Honors "any icon, fetched at creation, cached, no network after creation."
2. **Notification mechanism adjusted (catch-up strategy — explicitly delegated to this pass; refined r2 per FEAS-01):** pre-scheduled `UNCalendarNotificationTrigger` at creation replaces tick-fired delivery. User contract unchanged (one notification per chip, default-ON toggle, catch-up on wake) — but it now also survives the app not running, which the seed's mechanism could not. Exactly-once is now guarded by a flag set **at first observed delivery** (delegate interaction or reconciliation's delivered-state confirmation), never at scheduling, and the reconciliation pass checks pending/delivered notification state to distinguish scheduled-but-undelivered from delivered (§7.4) — disclosed bound: at most one re-fire, only in the delivered-and-dismissed-before-observation window.
3. **`approachWindow` per chip** reconciles the table's 30 min / 2 h thresholds with "indistinguishable after creation" (the one display-level distinction that survives).
4. **Pause mechanics made precise:** `pausedAt` + deadline-shift-on-resume; paused chips cannot go overdue (frozen + excluded from badging required it); overdue chips cannot be paused — Done is the only exit from Overdue (r2, AMB-01).
5. **"No AppKit bridging" narrowed to no AppKit *UI* bridging;** `NSImage`, `NSWorkspace`, and `NSApplication.didBecomeActive` (data/event APIs) are the three deliberate, documented exceptions (r2 adds the third for the authorization re-check).
6. **Overdue display formats and hero time formats made normative** (the seed was silent on the <1 h and ≥24 h formats).
7. **Offline fallback icon set** added (creation never hard-fails on network) — additive, consistent with settled #7.
8. **Done = delete row, definitively** (r2, AMB-01): `acknowledgedAt` is schema-reserved only, never written in v1. No dead rows, no archive in v1.
9. **Date-only deadlines prompt for a time (r2, operator-approved 2026-11-02 18:32):** plain-date input resolves the date and prompts for a time (09:00 pre-filled, one tap to accept) instead of any silent default — the seed specified no behavior for date-without-time.

## 13. Open items — r2 status

1. ~~`Nov 15` → 09:00 default~~ **Resolved (operator, 2026-11-02 18:32):** no silent default — the creation flow prompts for a time, 09:00 pre-filled as the suggestion, one tap to accept (§7.1, §5 creation sequence).
2. R1/R2/R3 remain READ-not-measured; fallbacks are now decomposed and cost-graded (§2, FEAS-02): R1 tint failure → `NSBitmapImageRep` raster on the same `NSImage` decode path; R1 decode failure → bundled glyphs; R2 shortfall → the fixed reconciliation mechanism; R3's cheap fallback → glyph-only, badge omitted, with `NSStatusItem` regraded to a last-resort architecture swap. Resolved empirically at build verification.
3. ~~Monotone-vs-palette rendering~~ **Resolved (operator, 2026-11-02 18:32):** any icon stands; monotone renders template + accent tint, palette renders untinted, disclosed in the picker (§5 step 1).
4. Badge-as-adjacent-text vs. a title-string count — remains empirical; the R3 render check at build verification resolves it, with the graded fallback list behind it.
5. No-sandbox-for-direct-distribution (§10) — round-1 critic corroborated; closed.

## 14. Explicitly out of scope (v1)

- EventKit / calendar reading (design reserves `eventIdentifier`; additive later)
- Any animation
- Recurring deadlines
- Sync, export, sharing
- Sparkle auto-update

## 15. Repo

`~/Repositories/till`, xcodegen (`project.yml` is source of truth), pushed to
Forgejo after the design lands.
