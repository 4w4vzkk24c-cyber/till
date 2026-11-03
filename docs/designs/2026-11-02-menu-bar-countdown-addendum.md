# Till — design addendum A1 (additive to r3.1)

**Applies to:** `docs/designs/2026-11-02-menu-bar-countdown-design.md` (r3.1, critic-approved) · **Card:** 1859
**Status:** Proposed — additive only. The settled decisions and the r3.1 form are untouched; nothing here changes a user-visible contract. Where an item adds behavior the design did not specify, it is marked **[new behavior]** so the operator can veto it. Items marked **[open]** need an operator decision.

**Provenance:** derived from the `cofounder-macos-development` reference pack (build-and-test, capabilities, diagnostics, intake-and-architecture, native-ui, swift6, swiftdata, tahoe) read against r3.1. Those references were supplied as documentation and are cited here by name; no claim below was executed. No Mac toolchain was available when this was written, so every Apple-framework statement is **READ**, not **MEASURED**.

## A1.1 Behavior the code must have (gaps in r3.1)

1. **Reconciliation revalidates after every suspension** (§7.4). The pass awaits `getPendingNotificationRequests()` and `getDeliveredNotifications()` before acting. After the awaits, and before firing or setting `zeroCrossingHandled`, the store re-fetches the chip by `ChipEntity.id` and re-checks `deadline ≤ now && !zeroCrossingHandled && pausedAt == nil`. A chip that was marked Done, paused or edited during the awaits is skipped. Actions target the stable `id`, never a grid index.
2. **Reconciliation is single-flight** (§7.4). Launch, `NSWorkspace.DidWakeMessage` and `didBecomeActive` can overlap. At most one pass runs; a trigger arriving mid-pass sets a rerun flag and the pass runs once more on completion. Without this, two overlapping passes can both observe "absent from both" and both fire — a duplicate outside the bound disclosed in §2/§7.4/§8.
3. **Grid order is deterministic** (§7.5) **[new behavior]**. Chips are ordered by `deadline` ascending, ties broken by `id`. Paused chips order by their frozen `deadline` like any other chip. The design did not specify an order.
4. **Quit is reachable** (§7.5) **[new behavior]**. A windowless agent app must expose a discoverable Quit. The popover footer gets a Quit button beside the settings toggles.
5. **Chip actions have non-pointer equivalents** (§7.5). Edit, Pause/Resume and Done are today only on a right-click context menu. Each chip also exposes them as named accessibility actions, and the add field and chip actions are keyboard-reachable. Each chip's accessibility label includes its state, e.g. "Dentist, 3 hours 12 minutes remaining, approaching". No visual change.
6. **Save/rollback invariant** (§7.4). "A failed save rolls back in-memory state" is only safe if every `TimerStore` mutation saves immediately and nothing else leaves edits pending on the shared main `ModelContext`, because `rollback()` discards all pending edits on the context. This is stated as an invariant of the store. `ModelContext.reset()` is not used.
7. **Launch-at-login status is re-read** (§7.5) when the popover opens, on `didBecomeActive`, and after relaunch, so `requiresApproval` and an externally disabled login item display correctly. Registration is attempted only when the user turns the toggle on.
8. **Icon fetch results are generation-checked** (§5 step 3, §7.2). Each creation attempt carries a request/generation ID. A result from a dismissed or superseded attempt is dropped and can never create a chip. Cancellation is cooperative, so the check is required in addition to cancelling.
9. **Task ownership** (§7.4). The tick loop is a stored task owned by `TimerStore` with an explicit stop (app termination, cadence reschedule). It does not rely on `deinit` to cancel, and does not hold strong `self` across the whole loop. Delegate callbacks from `UNUserNotificationCenter` enter the main-actor store through a deliberate `nonisolated` entry point; any continuation wrapping a completion-handler API resolves exactly once.
10. **Where `IconProvider` work runs** (§7.2). "Off the main actor" is made true by construction: `IconProvider` is its own actor, or its heavy methods are `@concurrent`. Under Swift 6.2's opt-in settings a nonisolated `async` function can otherwise stay on the caller's actor. `project.yml` records `SWIFT_VERSION`, `SWIFT_STRICT_CONCURRENCY` and default-isolation settings explicitly.

## A1.2 Platform notes

- **No availability gating.** The deployment floor is macOS 26, so there is no `#available(macOS 26, *)` and no fallback branch for 26-only APIs.
- **No Liquid Glass on chips.** The settled form is solid dark warm-gray cards with no animation. `glassEffect` is not used. System chrome around the `.window` popover is not controlled by the app.
- **No Foundation Models.** The parser is the deterministic grammar of §7.1.
- **Toolchain facts** in r3.1 §1 (Xcode 27.2, SDK 27.2, Swift 6.4.2) were measured on the operator's host and are carried as-is; they are not re-verifiable from a cloud session.
- **Diagnostics:** `Logger` with subsystem and categories, read with `/usr/bin/log show`. `xclog` is not applicable (simulator/companion targets only); `xcprof` only if a performance question arises. Logs never contain chip labels.

## A1.3 Persistence

- `ChipEntity` is declared inside a `VersionedSchema` (SchemaV1) from the first commit so a later `SchemaMigrationPlan` has a defined baseline. Verified on the Mac before relying on it.
- When v1 ships, an on-disk v1 store fixture (empty, ordinary, large) is committed and every later schema must open a copy of it.
- If any query filters by time, `now` is captured outside the predicate and translation is tested against an on-disk store. `DeadlineState` remains the single source of truth for state; no query re-derives it.

## A1.4 Additional test and evidence requirements (extend §11)

| Area | Added coverage |
|---|---|
| `TimerStore` | reconciliation: chip Done / paused / edited during the awaits is skipped; two overlapping triggers produce one pass plus one rerun and ≤ the disclosed bound of notifications; ordering (deadline, id tie-break); failed-save injection leaves no pending edits and in-memory state matches the store |
| SwiftData (on-disk) | fresh install; create → close → reopen round-trip on a real store; failed-save path; delete-by-id; fixture reopen once a v1 fixture exists |
| Concurrency | stale icon-fetch result dropped by generation; cancel while suspended releases resources; tick task stops on termination; continuation resolves once under racing callbacks |
| Accessibility (manual, on a Mac) | VoiceOver reads state-bearing labels and exposes Edit/Pause/Done actions; keyboard-only create and Done; contrast of red, amber and gray text on the card fill in light and dark, with Increase Contrast and Reduce Transparency; Reduce Motion (trivially satisfied — no animation) |
| Signed-app (manual) | agent-app activation and popover focus on the actual signed build; behavior when the user removes the extra (documented auto-terminate); login-item state after relaunch and after System Settings changes |
| Release | real archive and export; signed entitlements inspected; notarize, staple, Gatekeeper check on the downloaded artifact |
| Evidence | every build/test run captured with exit status and logs (`capture-build.sh`); missing evidence is not success |

## A1.5 Open question for the operator

- **[open] Initial focus.** Focus the add field when the popover opens (`.accessibilityDefaultFocus`, available at the floor) or leave focus to the system. r3.1 is silent. Default until decided: focus the add field.

## A1.6 Parser and display interpretations made in the first code pass

The grammar in §7.1 and the formats in §4 leave these cases open. The code takes the following readings; each is pinned by a test and is **[open]** for operator veto.

1. **Attached single term** `in 20m` is accepted alongside `in 20 min`; `in 1h30m`, `in 1h 30m` and `in 1 h 30 m` were the compound error (superseded 2026-11-03: see A2 parser note, compound durations are now accepted). Singular `minute`/`hour`/`day` units are accepted.
2. **Plain date on today's date** (`Nov 3` typed on Nov 3) stays this year rather than rolling to next year. The 09:00 suggestion may already be past, so the time prompt's result is validated by `NaturalDeadline.applyingTime`, which rejects a moment ≤ now with "already passed". Dates before today roll to next year; Feb 29 resolves to the next leap year; impossible dates (`Feb 30`, `Apr 31`) are an inline error.
3. **Weekday equal to today:** later today stays today; a time ≤ now rolls to next week.
4. **Overdue ≥ 24 h** renders in hours (`+50h overdue`); §4 specifies only `+2h` and `+41m` forms.
5. **Seconds floor** in `M:SS`; at remaining 0 < r < 1 s the display is `0:00` and the chip is not yet overdue (overdue begins at deadline ≤ now).
6. **Tie-break "nearest deadline"** means the smallest `deadline` value (for overdue chips, the longest overdue), then `id`. It affects only which chip is the bar's driver, not the bar's tint or badge.
7. **`barEscalation` takes all chips** and excludes paused ones itself, rather than receiving a pre-filtered active list, so "all paused" cannot be mishandled by a caller.

## A1.7 TimerStore decisions made in the first store pass

Each is **[open]** for operator veto and is pinned by a test.

1. **Delivered wins when a request is in both lists.** The pass reads pending, then delivered. If a chip's id is in both (the request moved pending → delivered between the two non-atomic reads), the chip is treated as delivered: pending is removed, nothing fires, the flag is set. This closes the pending→delivered re-fire window named in §2/§7.4/§8; the delivered-and-dismissed-before-observation window remains and is still bounded at one re-fire.
2. **Editing a paused chip keeps it paused.** The edited deadline becomes its frozen remaining time measured from the moment of the edit (`pausedAt = now`, `deadline = new value`); no trigger is scheduled until resume. §7.5 says Edit covers label and deadline but does not say what that means for a paused chip.
3. **Edit and resume reset `zeroCrossingHandled`** (a new deadline is a new crossing).
4. **Failed notification delivery in reconciliation leaves the flag false** and stops the pass, so the next pass retries; a failed save after a successful delivery would therefore re-fire once. The alternative (save the flag first) risks a lost notification, which the seed forbids.
5. **Notification text:** title is the chip label, or "Timer" when blank; body "Time’s up".
6. **Not in this pass:** the display tick loop (§7.4), the `UNUserNotificationCenter` delegate wiring (it must call `TimerStore.handleDeliveryObserved`), the `DidWakeMessage` / `didBecomeActive` observers that call `reconcile()` / `refreshAuthorization()`, and all views.

## A1.8 Tick loop and views — decisions the design left open

All **[open]** for operator veto; each is isolated to one place so reversing it is local.

1. **Label entry.** §4/§7.5 call for an optional label but the single NL field has no syntax for one. The header has a second optional "Label" field beside the deadline field. (`ChipsPopover`, `CreationFlow.label`)
2. **Edit.** Right-click Edit (and the "Edit" accessibility action) loads only the label; the deadline field is blank with the placeholder "New deadline (optional)". Blank deadline = keep it (label-only edit, still rescheduled so the notification title matches). Typing a deadline replaces it; a date-only entry goes through the same time prompt. The original natural-language text is not reconstructed. (`CreationFlow.beginEdit`, `TimerStore.edit(deadline: nil)`)
3. **Card layout reading.** §4 lists "label (caption, gray)" before the hero time and "optional text label" after it. The code renders one optional caption (the chip's label) between icon and hero, then the pause control. (`ChipCardView`)
4. **Overdue chips show a visible Done** where the pause control would be (Done is the only exit; right-click alone is not discoverable). Pause/Resume stay in the context menu and accessibility actions.
5. **Popover-open signal.** SwiftUI gives `MenuBarExtra` content no documented open/closed callback, so `popoverOpen` is driven by view `onAppear`/`onDisappear` **and** app active/resign. If either signal misfires the failure mode is a 1 s tick while closed (wasteful, never wrong), to be checked by the manual wake-rate test.
6. **Icons until `IconProvider` exists.** New chips get the bundled `sf:timer` glyph and a rotating accent from a fixed six-colour palette; a non-`sf:` id reads the future raster cache (memoized, no per-tick I/O) and falls back to the glyph. Icon pick is not offered yet. (`FallbackIcons`, `ChipIconView`)
7. **Bar icon colour (R3).** Amber/red are palette-coloured non-template `NSImage`s (the menu bar strips SwiftUI foreground colour from template images); normal/dimmed are template (dimmed at 0.45 opacity). The count is adjacent `Text`. Cheap fallbacks per §2 R3 remain: drop the count, or tint only.
8. **Footer.** Notifications toggle (disabled with an explanation when the state is denied; the System Settings deep link `x-apple.systempreferences:com.apple.Notifications-Settings.extension` is unverified), "Open at login" toggle re-read on open/active/launch with a requires-approval note, and **Quit Till** (⌘Q).
9. **Startup safety.** If the on-disk store cannot be opened the app runs from memory with a visible banner and never deletes or overwrites the store. Under XCTest the app (as test host) uses an in-memory store and starts no observers or ticking.
10. **Notification presentation.** The delegate shows banner + sound even while the app is active, and treats both presentation and user interaction as "delivery observed" (sets `zeroCrossingHandled`).

## A1.9 IconProvider and picker — decisions and deviations

All **[open]** for operator veto.

1. **Icon fetch timing.** Following §5's creation sequence literally, the chosen icon is fetched (or read from cache) **after** the time prompt and **before** persist; Enter is inert, a static "Fetching icon…" caption shows, and dismissing the popover cancels it (`CreationFlow.cancelInFlight`, generation-checked). Picking an icon in the picker does not by itself create a chip.
2. **Picker previews are extra network calls.** The search API returns ids only, so each *visible* result cell fetches its white SVG through the same cached path (`IconPreviewCell`). This is the picker path and still creation-time-only; no call is made once a chip exists. Previews that are never used are evicted after a 5-minute grace period. Cost: up to ~one request per visible result per search.
3. **Cache sidecar.** The cache holds `{prefix}--{name}.png` (the path `IconCache` already reads) plus `{prefix}--{name}.json` containing `{"monotone": Bool}`. §5 describes only the PNG, but a PNG alone cannot say whether the source was single-colour, and a second chip reusing a cached icon needs that flag. A cache entry needs both files; a missing sidecar is a miss and refetches.
4. **Eviction.** Triggered by `TimerStore.onChipsReloaded` (every reload) with the icon ids chips reference; unreferenced entries younger than 300 s are kept so an icon fetched for an in-progress creation is never evicted underneath it. §5 says only "evicted when no chip references it".
5. **Rasterization path.** `NSImage(data:)` decodes the SVG, `cgImage(forProposedRect:)` renders it at ≤256 px on the long side, ImageIO writes the PNG; no `NSGraphicsContext` drawing. This is the §2 R1 assumption and is exercised by exactly one test (`SVGRasterizerTests`); every other icon test uses a fake rasterizer. If it fails the documented fallback chain applies (§2 R1).
6. **AppKit surface.** `NSImage` use in the rasterizer and cache/preview views is the existing "NSImage" exception (§1); no new AppKit category.
7. **Id and URL safety.** Icon ids must be `prefix:name` of lowercase ASCII letters, digits and single hyphens (no `--`), which makes them safe in URL paths and keeps the file-name mapping reversible. Anything else never reaches the network. Request: `GET /{prefix}/{name}.svg?color=%23ffffff&height=256`; response must be HTTP 200, ≤ 256 KiB, UTF-8, containing `<svg`.
8. **Search.** `GET /search?query=…&limit=≤64[&prefix=…]`; only `icons` is required in the response, collection name / license / `palette` degrade to nil if absent or oddly typed. Search runs on Enter, not per keystroke.
9. **Built-in set always offered** in the picker (including when the service is unreachable); a fetch failure leaves the selection and input intact for retry, with no chip persisted.
10. **Not covered.** Live behaviour against api.iconify.design (the cloud container's proxy blocks it; tests use an injected `IconNetworking` mock, which pins request count and URLs the same way the design's URLProtocol mock would). Real `URLSessionIconNetworking` is unexercised until run on the Mac.
