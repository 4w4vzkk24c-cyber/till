# Evidence record — first code pass (static review only)

**Card:** 1859 · **Date:** 2026-11-03 · **Branch:** `claude/zealous-einstein-uwu5oe`
**Verdict at time of writing (cloud session):** NOT BUILT, NOT RUN. The sections below describe that state and are kept as written.

## Update — Mac run (operator-reported, same day)
Run by the operator on their Mac from a checkout of this branch: `xcodegen generate`, then `capture-build.sh` with `xcodebuild ... CODE_SIGNING_ALLOWED=NO test` (evidence dir `artifacts/test-002`, result bundle `artifacts/test-002.xcresult`).
- `xcodebuild` exit status **0**, `** TEST SUCCEEDED **`.
- `Test run with 41 tests in 3 suites passed` (`NaturalDeadlineTests`, `DeadlineStateTests`, `HeroTimeTests`), including the DST spring-forward/fall-back, leap-day and time-prompt cases.
- The first attempt (`test-001`, exit 66) failed only because the checkout lacked this branch (no `project.yml`); it is not a code result.
- **Evidence limits:** I (the cloud session) have seen only the last 60 lines of `build.log` as pasted, not the full log or the xcresult. The retained full log and bundle on the Mac are the authoritative record. Compiler warnings, if any, were not visible to me.
- **Still unverified:** the generated `Info.plist` carries `LSUIElement`, hardened-runtime setting, that the placeholder `MenuBarExtra` app launches, and everything listed under "Not covered at all". The parser tests passing confirms the pure units, not the app.
- **Build settings (operator-reported, `xcodebuild -showBuildSettings`, Debug):** `EFFECTIVE_SWIFT_VERSION = 6`, `SWIFT_VERSION = 6.0`, `SWIFT_STRICT_CONCURRENCY = complete`, `ENABLE_HARDENED_RUNTIME = YES`, `MACOSX_DEPLOYMENT_TARGET = 26.0`. `SWIFT_DEFAULT_ACTOR_ISOLATION` did not appear in the output, i.e. it is unset (nonisolated default) — matches the "deliberately unset" note below.
- **Launch (operator-reported):** `open -n …/Till.app` then `pgrep -lx Till` returned `76801 Till` — the placeholder app starts and stays running for at least 2 s.
- **`LSUIElement` (operator-reported):** the operator confirmed `LSUIElement` is `true` in the built `Info.plist`. The reply ("yes, true") answered a combined question about the plist value, the menu bar icon/popover, and the absent Dock/Cmd-Tab entry; only the plist value is explicit, so the two visual checks are recorded as reported-yes, not itemized.
- **Not reported / still unchecked:** itemized visual confirmation (see above). Hardened runtime is confirmed only as a build setting; the test build was unsigned (`CODE_SIGNING_ALLOWED=NO`), so no signed-entitlements check has happened.
- The loosely-asserted DST disambiguation tests passed on macOS 26 Foundation; the exact resolved wall-clock for the nonexistent `02:30` is still not pinned.

## Environment
- Cloud Linux container (Ubuntu 24.04). No `swift`, `swiftc`, `xcodebuild` or `xcodegen`.
- A Swift toolchain download from `download.swift.org` was refused by the egress proxy (HTTP 403). No workaround was attempted.
- Consequence: per the pack's build-and-test rule, this is a labeled static review. No claim is made that the code compiles or that any test passes.

## What was written
| File | Purpose | State |
|---|---|---|
| `project.yml` | xcodegen source of truth; macOS 26, Swift 6 mode, strict concurrency complete, `LSUIElement`, hardened runtime | not generated |
| `Sources/Till/NaturalDeadline.swift` | pure parser (§7.1) | not compiled |
| `Sources/Till/DeadlineState.swift` | pure state machine, bar escalation, hero-time format (§7.3, §4) | not compiled |
| `Sources/Till/TillApp.swift` | placeholder `MenuBarExtra` scene so the target has an entry point | not compiled |
| `Tests/TillTests/*` | swift-testing suites for the two pure units | not run |
| `docs/designs/…-addendum.md` | design addendum A1 | prose only |

Expected values in the tests were derived by hand (US Central; 2026 DST: Mar 8 and Nov 1), not by running code.

## Assumptions to confirm
- Bundle identifier prefix `com.crossedkeys` is a placeholder; the real Crossed Keys Co. identifier is unknown.
- `SWIFT_VERSION: "6.0"` is language mode; default-isolation and upcoming-feature settings are deliberately unset (A1.1 item 10 asks that they be recorded explicitly once chosen).
- Parser/format interpretations in addendum A1.6.
- Calendar behavior for nonexistent/ambiguous DST local times is asserted loosely (day/month only; `01:30` on the fall-back day). Foundation's disambiguation must be confirmed on the Mac.

## Not covered at all
`TimerStore`, `IconProvider`, views, SwiftData model, notifications, settings, accessibility, signed-app behavior, notarization.

## Commands to run on the Mac
```bash
xcodegen generate
bash "$HOME/.agents/skills/cofounder-macos-development/scripts/capture-build.sh" "$PWD/artifacts/test-001" -- \
  -project Till.xcodeproj -scheme Till -destination 'platform=macOS' \
  -derivedDataPath "$PWD/artifacts/DerivedData" \
  -resultBundlePath "$PWD/artifacts/test-001.xcresult" \
  CODE_SIGNING_ALLOWED=NO test
```
The result is "passed" only with the captured exit status and logs. A failure in the first compile is expected to be possible: this code has never seen a compiler.

## Update 2 — TimerStore pass (cloud session, NOT compiled, NOT run)
Added after the Mac run above; none of the following has been compiled or tested anywhere yet.

| File | Purpose |
|---|---|
| `Sources/Till/Store/ChipEntity.swift` | `@Model ChipEntity`, `TillSchemaV1`, `TillPersistence.makeContainer` (in-memory / on-disk) |
| `Sources/Till/Store/NotificationScheduling.swift` | main-actor protocol seam + `SystemNotificationScheduler` (real `UNUserNotificationCenter`; no tests, no delegate wiring) |
| `Sources/Till/Store/TimerStore.swift` | `@MainActor @Observable` store: create/done/pause/resume/edit, toggle, authorization watcher, single-flight reconciliation |
| `Tests/TillTests/TimerStoreTests.swift`, `MockScheduler.swift` | 33 swift-testing cases against an in-memory SwiftData container and a mock scheduler, plus one on-disk reopen test |

Highest-risk guesses (most likely first compile/test failures): SwiftData `rollback()` restoring a pending delete/insert (tests `failedSaveOn*`), `TillSchemaV1.versionIdentifier` as `static let` under Swift 6, `#expect(throws:)` with async main-actor closures, on-disk store reopen in one process, and Swift 6 Sendable diagnostics around the `@MainActor` closure properties. Failures in these are expected to be informative, not necessarily bugs in the design.

**Result (operator-reported, `artifacts/test-004`):** compiled with no `error:` lines; `failedSaveOnCreateRollsBack` and `failedSaveOnDoneRestoresChip` passed (SwiftData `rollback()` restores a pending insert/delete); operator reported "all passed". Exit status and the `Test run with N tests` line were not pasted to the cloud session, so the exact count is not recorded here (expected 41 + 33 = 74). Only warnings seen: AppIntents metadata-extraction skipped, and `com.apple.linkd.autoShortcut` connection errors from launching the app as test host — neither from Till code.

## Update 3 — tick loop and views (cloud session, NOT compiled, NOT run)
New: `TickCadence`, store tick loop (`now`, `startTicking/stopTicking`, injected `sleep`), `CreationFlow`, `ChipCardView`, `ChipsPopover`, `BarIcon` (+ `BarIconPresentation`), `ChipViewData`/`FallbackIcons`/`IconCache`/`HexColor`, `Spoken`, `LoginItemController`, `SystemEventObserver`, `NotificationDelegate`, `AppModel`, real `TillApp`. `TimerStore.edit` now takes `deadline: ParsedDeadline?`; `lastKnownAuthorization` is now the observable `authorization`.
New tests: `TickTests` (cadence + loop with injected sleep), `CreationFlowTests`, `PresentationTests` (bar icon, spoken labels, hex, fallback ids, login item). The 74 earlier tests are unchanged apart from `Harness` gaining an optional `sleep`.

**Highest-risk guesses (likely first-compile/run failures):** `@MainActor` class + `nonisolated async` UN delegate methods under Swift 6; `@Observable` init ordering in `AppModel`; `Task`-based tick loop timing in `StoreTickTests` (uses `Task.yield` polling, could be flaky); `private func run<T>` closure capture in `CreationFlow`; `MenuBarExtra` label behaviour (R3).

**Manual checks required on the Mac (none can be claimed from the cloud):**
1. Menu bar icon appears; no Dock / Cmd-Tab entry; popover opens; Quit works.
2. Add `in 1 min`, `Fri 5pm`, `Nov 15` (time prompt shows 09:00, one tap to accept); chips two per row; changes are swaps, not animations.
3. Bar icon: amber when a chip is inside its window, red + count when overdue, dimmed when none active/all paused. **R3: confirm colour and count text actually render in the menu bar.**
4. Notification fires at zero with the app closed; after sleep/wake a missed one appears exactly once; denied state shows the footer explanation.
5. Done / Pause / Resume / Edit via buttons, right-click, and VoiceOver actions; spoken label reads state.
6. Closed-popover CPU/wake rate is ~30 s cadence (Activity Monitor / `log`), confirming the popover-open signals do not stick on.
7. Open-at-login toggle incl. requires-approval flow.
8. Increase Contrast / Reduce Transparency / light and dark: contrast of red, amber and gray on the card fill.

**Result of Update 3 (operator-reported, `artifacts/test-005`):** `Test run with 108 tests in 11 suites passed after 0.137 seconds`, `** TEST SUCCEEDED **`; the grep for `error:` / `✘` matched only the `com.apple.linkd.autoShortcut` connection log lines (test-host noise, as in earlier runs). This is the first measured full-suite count (108); the earlier "74" figure in this record was an estimate, not a measurement. `xcodebuild` exit status line was not in the pasted output. The tick-loop tests (which poll with `Task.yield`) passed in this run; flakiness across repeated runs is not yet assessed.

**Still unverified (manual checklist above, items 1–8):** nothing about the running UI has been confirmed — menu-bar rendering of amber/red tint and count (R3), popover open/closed signals, real notification delivery and wake catch-up, VoiceOver, contrast, login-item flow.

## Defect found by the first real launch — missing menu bar icon (operator-reported)
Symptom: after test-005 passed, the manually launched app showed no menu bar icon and was not running. Evidence: three `Till-*.ips` crash reports; newest `Till-2026-11-02-202652.ips`: `EXC_BREAKPOINT / SIGTRAP`, main thread, SwiftData frames above `TimerStore.reload()` (`TimerStore.swift:333`) ← `TimerStore.start()` ← startup `Task` in `AppModel.init`.
Cause (from the stack plus code reading; not independently reproduced here): `AppModel.init` kept the `ModelContainer` only in a local; `TimerStore` retained just `container.mainContext`, which does not keep the container alive, so the first fetch ran against a deallocated container. The test `Harness` holds its own container reference, which is why 108 tests passed. Fix: `TimerStore` now retains its container; regression test `storeKeepsItsContainerAlive` drops all other references first. Not yet verified on the Mac.
Lesson for the evidence rule: green logic tests did not cover composition-root lifetime; the manual launch check caught it.

**Fix verified (operator-reported):** after `54f205d` the operator relaunched the app and reported "there we go it worked" — the menu bar icon now appears and the app stays running. The `test-006` suite result and the `pgrep` output were not pasted, so the post-fix test count and exit status are not recorded here. Manual checklist items 2–8 above remain unconfirmed.

**Manual checklist (operator-reported, blanket):** after the launch fix the operator reported "everythings good" in response to the 5-step list (bar tint/count R3, `Nov 15` time prompt, notification incl. quit-and-relaunch, Done/Pause/Resume/Edit, idle cadence). This is a single summary statement, not itemized observations: no screenshots, no Activity Monitor/`log` readings, and no notification-after-relaunch detail were provided to the cloud session. Treat R3 (menu-bar colour and count rendering), the popover-open heuristic (idle wake rate), and wake/relaunch notification dedupe as "reported fine, not independently evidenced" until measured. Still not exercised: VoiceOver, Increase Contrast / Reduce Transparency, login-item approval flow, signed/notarized build.

## Update 4 — IconProvider and picker (cloud session, NOT compiled, NOT run)
New: `Icons/IconModels.swift` (id validation, protocols, errors), `SVGColorInspector`, `SVGRasterizer`, `IconProvider` (actor: search, fetch, cache, eviction), `Views/IconPicker.swift` (model, view, preview cell); `CreationFlow` now fetches the chosen icon at creation (generation-checked, cancellable, `startSubmit`/`cancelInFlight`); `TimerStore.onChipsReloaded`; `AppModel` creates the provider/picker (never under test).
New tests: `IconProviderTests.swift` (ids, colour inspector, search, fetch, offline invariant, eviction, one real-rasterizer test), `IconFlowTests.swift` (creation-flow icon behaviour, picker model).

**Expected first-run risks:** `NSImage(data:)` SVG decode and `cgImage(forProposedRect:)` size/alpha (`SVGRasterizerTests` is the only real-Apple-SVG test); `NSLock.withLock` / `@unchecked Sendable` mocks under Swift 6; `NSBitmapImageRep.colorAt` colour-space assertions; the `guard let provider = madeProvider` flow in `AppModel`.

**Manual checks required on the Mac (live service, not reachable from the cloud):**
1. Picker: search `coffee` → results appear with previews; hovering/accessibility hint shows collection · license · tint note.
2. Pick a monotone icon → chip shows it tinted with the chip accent; pick a multicolor one (e.g. a `logos:` icon) → chip shows its own colours, untinted.
3. With Wi-Fi off: search shows the inline hint; built-in icons still create chips; an already-cached icon still works.
4. After a chip with a fetched icon exists, no further requests to api.iconify.design (Little Snitch / `nettop` / proxy log) — the offline invariant in practice.
5. Delete the chip, wait > 5 min, mutate any chip: its cached PNG and `.json` disappear from `~/Library/Application Support/Till/icons`.
6. Dismiss the popover mid-fetch (throttle the network): no chip appears and the field is usable next time.

**Result of Update 4, first run (operator-reported, `artifacts/test-008`, exit 65):** after the raw-string fix the whole target compiled; `Test run with 149 tests in 19 suites failed ... with 1 issue`. 148 passed, including every `IconProvider` fetch/cache/eviction/offline-invariant test, the creation-flow icon tests and the picker model tests. The one failure was `SVGRasterizerTests.rendersAWhiteSquareWithTransparentSurroundings`: `Expectation failed: rep.pixelsWide == 256 && rep.pixelsHigh == 256 → false` (actual dimensions were not printed). Only that one issue was recorded, so the centre-opaque-white and corner-transparent checks in the same test passed, i.e. **R1 held for decode and render** (`NSImage(data:)` decodes the SVG; the rendered pixels are correct); only the output pixel size was wrong. Cause is inferred, not measured: `cgImage(forProposedRect:)` does not guarantee pixel dimensions (likely the display backing scale). Fix: always redraw into a CGContext of exactly the requested size; the test now reports the real dimensions on failure and a second test pins the aspect ratio and a 32 px size. Fix not yet verified on the Mac.

## Update 5 — Popover rework and Iconify diagnostics (cloud session, UNBUILT, NOT RUN)
Static review only: the cloud container has no Swift toolchain, so nothing below has been compiled or executed. No test result is claimed.

**What changed (plan `docs/superpowers/plans/2026-11-03-popover-rework.md`, spec `docs/designs/2026-11-03-popover-rework.md`):**
- Task 1: `IconError` gains `.offline/.tls/.timedOut` with specific hints; `IconFailure.classify`; `IconLog` (`os.Logger`, subsystem `com.crossedkeys.till`, category `icons`; logs operation, error domain/code, HTTP status only, never query/URL); `TestHostSignals` and a launch log line (category `launch`) showing which test-host signal fired. Two existing assertions in `IconProviderTests` changed from `.network` to `.offline`.
- Task 2: `Contrast`, `HexColor.hue/adjusted`, new cool accent palette, `Theme` tokens.
- Tasks 3/5/7 (views) plus Task 4 (`ParseEcho`): `ChipPresentation`, rewritten `ChipCardView`, `SettingsMenu` + `SettingsAttention`, `ComposerView` + `ComposerStatus`, new `ChipsPopover` (empty state, 470 pt cap, tray tint).
- Task 6 (picker rework): **not done**, held until the live Iconify diagnostics (handoff §7.3) are back.

**Measured in the cloud (labelled as such):** the numeric assertions in `ColorSystemTests` were checked against a Python replica of `HexColor.adjusted`/`Contrast` (all adjusted accents >= 3.0 on both reference tiles, hue change < 0.3 degrees, white on `#CF2F36` 5.11:1, amber caption on the light tile 4.53:1). The contrast figures quoted in the spec (4.8:1, 7.7:1, 5.6:1, 8.3:1, 3.5:1) were sampled from the rendered HTML mock on a blue gradient, **not from the real window**. Reference guidance says contrast must be tested against actual rendered backgrounds: UNVERIFIED in the app.

**Expected first-compile risks:** `Menu` with `.menuStyle(.button)` inside a window-style `MenuBarExtra`; `ParseEcho` time text (`DateFormatter` short style under `en_US_POSIX` on macOS 26); `@ViewBuilder` functions returning differently typed shapes in `ChipCardView.surface`; `TextField` placeholder contrast; `FocusState<Bool>.Binding` passing; Swift 6 strict-concurrency diagnostics in the moved bindings.

**UNVERIFIED on the Mac:** window corner radius vs `Theme.Radius.tile`; tray tint strength over the macOS 26 window material; light appearance (derived, never mocked); Reduce Transparency; Increase Contrast; Reduce Motion (no animation exists); VoiceOver and keyboard-only operation (Tab order across pill, gear and tiles; Esc on the time prompt); gear badge behaviour; every manual checklist item below.

**Operator run (test-010) and manual checklist:** see the plan, Task 8. Record the full `Test run with N tests` line and exit status here once pasted.

**Diagnostics capture:** use the bounded form in the handoff addendum (`log show --info --debug`, raw output and exit status kept under `artifacts/diag-001/`). Bounded retention means an empty capture is not evidence that nothing failed. `xclog` does not apply to this native Mac app.

**Result of Update 5, first compile (operator-reported, `artifacts/test-010`):** `** TEST FAILED **` from a single compile error: `IconDiagnosticsTests.swift:35:24: cannot find 'NSURLErrorFailingURLStringKey' in scope` (the final static review had called this symbol fine; it was wrong). Nothing else in the grep output was an error, so the rest of the target compiled as far as the compiler got, but no tests ran. Fix: the test now uses the literal key `"NSErrorFailingURLStringKey"` (the constant's value). Not yet re-run.

**Result of Update 5, second run (operator-reported, `artifacts/test-011`):** `Test run with 189 tests in 26 suites passed after 0.194 seconds.` and `** TEST SUCCEEDED **` (MEASURED: pasted grep output). The `xcodebuild` exit status line was not pasted. The count is consistent with the earlier expectation: 150 expected before this work plus the 39 tests written in Update 5 (IconFailure 7, TestHostSignals 2, TLS provider test 1, ColorSystem 8, ParseEcho 6, ChipPresentation 5, SettingsAttention 5, ComposerStatus 5) is 189. That arithmetic is an inference, not a per-test listing, and the 150 baseline was never itself measured.

**What this does and does not establish:** all new and existing logic tests compile and pass on the Mac, including the colour/contrast assertions, `ParseEcho` (so the `DateFormatter` assumption held under the test calendar), `ChipPresentation`, `SettingsAttention`, `ComposerStatus` and the typed icon errors. It does **not** exercise any SwiftUI view: the tile, gear menu, composer, empty state and tray tint compiled but have never been looked at. Still UNVERIFIED: `Menu` inside the `MenuBarExtra` window, Quit reachability, light appearance, Reduce Transparency, Increase Contrast, VoiceOver and keyboard-only use, contrast against the real window, and the live Iconify diagnostics.


**Diagnostics capture `artifacts/diag-001` (operator-reported):** this window caught the **test host**, not a normal launch. The single `launch` line reads `testing=true configurationFile=true sessionIdentifier=true xctestClass=true`, and the `icons` lines (`search status 500`, `search failed: NSURLErrorDomain -1009`, `search decode failed`, `search failed: NSURLErrorDomain -1200`, `fetch failed -1009`, `fetch status 404`, `fetch decode failed` x3) match `IconProviderTests`' mocked failures in order. What it shows: the logger, subsystem and categories work; no query text or URL appears; offline and TLS map to -1009 and -1200 as designed. What it does **not** show: any live Iconify search, or a `testing=false` launch line. H1 is neither confirmed nor ruled out. A fresh capture (`artifacts/diag-002`) after relaunching the app and searching `coffee` is needed.

## Update 6 — Iconify search blank-results defect (operator-reported live run)
**Symptom (reported):** after a search, no results show; a blip, then the default view.
**`artifacts/diag-004` (MEASURED, pasted):** every search logged `picker: search submitted` -> `search ok: N ids` -> `picker: search finished, N results` (N = 7, 1, 64). The popover did not disappear during any search and `picker open=true` held. So the real app builds the picker (`testing=false`), Return reaches the field, the service answers, the response decodes, and the model holds the results. Hypotheses H1-H4 are ruled out by this log.
**Fix attempt (`8beff61`, picker rework):** results drawn as a fixed grid of up to 12 with no nested scroll view, plus a status line and preview breadcrumbs.
**`artifacts/diag-005` (MEASURED, pasted) and operator report ("successful", REPORTED, no screenshot):** one search of 64 results logged 12 `preview: start` and 12 `preview: ok, image=true`; results display. The test-host portion of the same capture shows the new `IconPickerStateTests` ran. The `test-012` pass/fail line was not pasted: UNVERIFIED.
**Root cause: not isolated.** The rework changed several things at once (removed the `ScrollView` with a 170 pt cap, capped results at 12, redrew the cells with theme tints). Evidence is consistent with the old nested scroll view collapsing in the menu-bar window, but no run isolated that. The `preview:` and picker breadcrumb log lines are temporary and should be removed after acceptance.

## Update 7 — Menu-bar glyph changed to `fa-solid:seedling` (cloud session, UNBUILT, NOT RUN)
Operator request. The cloud cannot reach api.iconify.design, so the glyph data came from the `@iconify-json/fa-solid` npm package (v1.2.2, Font Awesome 5.15.4, CC BY 4.0), the same collection Iconify serves: one path on a 512x512 grid. Embedded in `BarGlyph.swift` as white-filled SVG; `BarIconImage` rasterizes it once through `SVGRasterizer` (72 px, shown at 18 pt), uses it as a template image for normal/dimmed and a source-in tinted copy for amber/red. Tests: `BarGlyphTests` (self-contained SVG, name, exact-size rasterization with a transparent corner) and two updated `BarIconPresentationTests` assertions. **Not compiled or run.** UNVERIFIED on the Mac: how the seedling looks at menu-bar size and in light/dark bars, the amber and red tint rendering (R3), the dimmed state. Attribution (CC BY 4.0) is recorded in `THIRD_PARTY_NOTICES.md` but not yet shown anywhere users can see it.

## Update 8 — Compound durations, `in` optional (cloud session, UNBUILT, NOT RUN)
Operator request: write `1 day 2 hours`, and `in` must not be required. `NaturalDeadline.parseQuick` now scans amount/unit pairs (any order, each unit once, `and` and commas allowed, attached forms like `1h30m` still work) and input starting with a digit routes to it. The old `compoundDuration` error is replaced by `repeatedUnit`; the test that pinned the old rule (`compoundIsAnError`) is replaced by compound, `in`-optional, repeated-unit, malformed and per-amount tests, plus one `ParseEcho` test. Hand-traced against every parser test; **not compiled or run**. Overrides design §7.1 "single term" and A1.6 item 1 (recorded in the A2 spec).

**Result of Update 6 picker rework, run `artifacts/test-012` (operator-reported, MEASURED):** `Test run with 194 tests in 27 suites passed after 0.188 seconds.` and `** TEST SUCCEEDED **`. Consistent with 189 plus the 5 `IconPickerStateTests` (one added suite). Exit status line not pasted. This run predates the seedling glyph (Update 7) and the compound-duration parser (Update 8).
**Numbering:** the operator ran the glyph and parser build as `artifacts/test-014` (test-013 was already taken on their machine). Its result has **not** been pasted: Updates 7 and 8 remain UNBUILT/UNVERIFIED. Next free directory: `test-015`.

**Result of Updates 7 and 8, run `artifacts/test-014` (operator-reported, MEASURED, first run with a pasted exit status):** `xcodebuild exit: 0`; `Test run with 204 tests in 28 suites passed after 0.186 seconds.`; `** TEST SUCCEEDED **`. Consistent with 194 plus the new tests (3 `BarGlyphTests`, 4 single-case parser/echo tests, and a net +3 from replacing one parameterized parser test with four). So the seedling glyph code, the compound-duration parser and everything before it compile and pass their logic tests on the Mac.
**Still UNVERIFIED (no test can establish these):** how the seedling looks in the menu bar (light and dark bars, the amber and red tints, the dimmed state); typing `1 day 2 hours` in the running app; the gear menu opening and Quit; light appearance; Reduce Transparency and Increase Contrast; VoiceOver and keyboard-only use; chip creation with a fetched icon (tinted monotone, untinted multicolor); Wi-Fi-off behaviour. CC BY 4.0 attribution for the glyph is not yet shown to users.

## Update 9 — Popover clipped after the composer (operator screenshot, REPORTED)
Symptom: the menu-bar window stopped just below the composer; the tiles were cut off with a scroll bar at the right; the seedling glyph and the compound-duration input were reported working. Hypothesis (not proven): a `ScrollView` given only a maximum height has almost no natural height, and the window sizes from natural height. Change: the grid now has an explicit height from the chip count (`ChipGridLayout`, tile 152 pt, gap 8 pt, cap 480 pt). The previous 470 pt cap was an arithmetic slip (three rows need 472 pt). Tests first (`ChipGridLayoutTests`); **not compiled or run**; the visual fix is UNVERIFIED until the operator relaunches.

**Operator report after the grid-height fix (REPORTED, "all yes"):** all timers are visible and long lists scroll; the window grows for the picker; the gear menu opens. No screenshots and no `test-015` result were pasted, so the height tests are UNVERIFIED as run. The gear menu opening resolves the earlier risk that `Menu` would not work inside the `MenuBarExtra` window (REPORTED; Quit reachability and the Notifications/Open-at-login toggles were not itemized).
**Cleanup:** the temporary breadcrumbs (`picker: search submitted/finished`, `preview: start/ok/failed`, `popover appeared/disappeared`, `picker open=`) are removed. Kept: error logging, the `search ok: N ids` count, and the `launch` signals line. Unbuilt.

## Update 10 — Compact tile, no captions (operator request after a screenshot, UNBUILT)
The operator's screenshot (REPORTED, image) showed all tiles in the live app with the amber outline and `due soon` caption; they asked to remove `due soon`, compact the tile height, and put the optional label under the pause control. Change: tile order is now icon, hero, control, label; no caption row in any state (a uniform height keeps `ChipGridLayout`'s computed grid height correct, so overdue and paused lost their captions too: a ruling, easy to restore); tile height 152 -> 128 pt, grid cap 480 -> 408 pt (three full rows = 400 pt). The `caption` property and its test are removed from `ChipPresentation`. **Not compiled or run.** Approaching is now amber outline plus amber digits only (not colour-alone in the strict sense only for VoiceOver, which still says "approaching"). UNVERIFIED on the Mac: the new tile proportions and whether the label under the control reads well.

## Update 11 — Label feature removed, schema v2 (operator request, UNBUILT, NOT RUN)
Plan `/root/.claude/plans/remove-the-label-feature-hazy-hickey.md` (approved). The `label` field is gone from the stored model (`TillSchemaV2`, `TillSchemaV1.ChipEntity` kept as the legacy shape, `TillMigrationPlan` with one lightweight stage), `NewChip`, `TimerStore.edit(id:deadline:)`, `CreationFlow`, the composer, the tile (112 pt tall, grid cap 360 pt), `ChipViewData` and `Spoken` (every chip reads `Timer, ...`; notification title `Timer`). Tests were updated first, plus the new `MigrationTests` (opens a v1 on-disk store with a label through `makeContainer`; fresh install). **Not compiled or run.** The migration on the operator's real store is the main UNVERIFIED item: if the `Couldn't open your saved timers` banner appears, move `~/Library/Application Support/Till/till.store*` aside (do not delete) and send the log.

## Update 12 — Glassier (operator request, UNBUILT, NOT RUN)
Tokens only (spec "Glass pass"): lighter tray tint, clearer tile fill, 1 pt glass edge gradient on tiles, pill and picker. UNVERIFIED: how it looks on the Mac, and legibility of the white digits over bright wallpapers now that the tray is more see-through.

**Result of Updates 11 and 12, run `artifacts/test-018` (operator-reported, MEASURED):** `xcodebuild exit: 65`; `Test run with 210 tests in 29 suites failed after 0.173 seconds with 1 issue`; `** TEST FAILED **`. The single failure was `TimerStoreTests.createPersistsAndSchedules()` at line 77: `Expectation failed: h.scheduler.scheduled[0].title == "Dentist"`. Cause: a stale assertion left over from before labels were removed (my read of that region stopped two lines short). The whole target compiled, including the new `MigrationTests`, which is not among the failures. Fix: the assertion now expects `"Timer"`. Not yet re-run. Runs `test-015` to `test-017` were not pasted.

## Update 13 — Tile padding (operator request, UNBUILT)
Operator reported the label removal and glass pass working ("it works", REPORTED, no test result pasted for that run) and asked for more top and bottom padding on the cards. Tile padding top 8 -> 12 pt and bottom 6 -> 10 pt; tile height 112 -> 120 pt; grid cap 360 -> 384 pt (three rows = 376 pt). `ChipGridLayoutTests` updated first. Not compiled or run.

## Update 14 — More padding, seedling as the default icon (operator request, UNBUILT)
Tile padding top 12 -> 16 and bottom 10 -> 14 (tile 128 pt, grid cap 408 pt). The default chip icon is now the bundled seedling (`builtin:seedling`): `FallbackIcons.isBuiltIn` treats `sf:` and `builtin:` ids as offline built-ins (so creation never fetches it), `BundledIcons` rasterizes it from `BarGlyph`, and it leads the picker's built-in row (nine built-ins, 282 pt in a 304 pt row). Tests first (`theSeedlingIsTheDefaultBuiltIn`, `BundledIconsTests`, tile height). Not compiled or run. UNVERIFIED: how it reads at 40 pt in a tile, and the built-in row fit. Operator-reported `test-019`/`test-020` results were not pasted.

## Update 15 — Default icons: hugeicons:bio-energy plus the AI-company set (operator request, UNBUILT)
Replaces Update 14's seedling default. The cloud cannot reach Iconify, so each icon was found in the `@iconify-json/*` npm packages and checked: `hugeicons:bio-energy`, `withicons:peacock-feather-sketch`, `at-icons:lightning-bolt`, `emojione-monotone:tomato` exist as named; the AI marks are in `logos` (`z-ai` exists exactly; `claude`, `openai`, `opencode` also have compact `-icon` variants, which were chosen for the square tile). Embedded as SVG in a generated `BundledIconCatalog` (9 icons plus `builtin:seedling` for compatibility; 17 KB). `FallbackIcons.isBuiltIn` now covers `sf:`, `builtin:` and catalog ids so picking one never fetches; chips store the real Iconify id. Tests first: `BundledIconCatalogTests`, updated `FallbackIcons` and `BundledIcons` tests, and a no-network creation test. **Not compiled or run.** UNVERIFIED: how each icon renders at 40 pt and 16 pt (the tall `ollama` and `opencode-icon`, the dark-on-dark `z-ai` and `opencode-icon` on the glass tile), and `NSImage` decoding of these SVGs. Licensing needs a release decision: CC BY credits and MIT notices must ship with the app, and the five company logos are trademarks (see THIRD_PARTY_NOTICES.md).

## Update 16 — Tighter space between time units (operator request, UNBUILT)
The hero text (for example `14h 32m`) draws the space between units 5 pt tighter (`ChipHero.unitSpaceKern = -5`, from about 16 pt at 26 pt). The `HeroTime` string, the tile's VoiceOver text and every parser/format test are unchanged; only rendering differs. Tests first (`ChipHeroTests`). Not compiled or run. UNVERIFIED: how it looks, and `AttributedString.kern` on a macOS 26 `Text`. Adjust the one constant to taste.

**Result of Updates 15 and 16, run `artifacts/test-022` (operator-reported, MEASURED):** `xcodebuild exit: 65`, `** TEST FAILED **`, `Testing failed: Cannot find 'BundledIconCatalog' in scope` (x3), "Testing cancelled because the build failed." No test ran. Probable cause (not yet confirmed): the run block I gave omitted `xcodegen generate`, so the new files `BundledIconCatalog.swift` and `BundledIconTests.swift` were not in the generated project; both are committed and the enum is defined (`git ls-files`, `grep`). Re-run as `test-023` with `xcodegen generate` first. If the error persists it is a real defect.

**Result of Updates 15 and 16, re-run `artifacts/test-023` with `xcodegen generate` first (operator-reported "success", REPORTED):** no test count, exit status or grep output was pasted, so this is a report, not a measurement. Taken at face value it confirms the `test-022` failure was the missing `xcodegen generate` step, not a code defect. Still UNVERIFIED by any test run: nothing visual. Open for the operator: how the nine built-in icons, the dark `z-ai` and `opencode-icon` marks, the tighter time spacing and the glass edge look; and the release decisions on CC BY credits, MIT notices and the company logos (THIRD_PARTY_NOTICES.md).

## Update 17 — About Till in the gear menu (operator request, UNBUILT)
`About Till` opens the standard About panel (`AboutPanel.show()`, `NSApp.orderFrontStandardAboutPanel` with `Credits.text()` as the credits). `Credits.entries` lists author, license and link per bundled collection; `CreditsTests` require a credit for every bundled collection, matching licenses, every author name, the CC BY link, icon names, the company-mark trademark disclaimer and the Iconify note. Not compiled or run. UNVERIFIED: whether the panel appears in front for this agent-style app and reads well; MIT notice wording for Hugeicons, with icons and @icons is **missing** (not available in the npm data, not invented).

**Result of Update 17, run `artifacts/test-024` (operator-reported, MEASURED):** `xcodebuild exit: 65`, `** TEST FAILED **`, two compile errors in the test target: `Cannot convert value of type 'String' to expected argument type 'Comment?'` (x2), in `CreditsTests.swift`; the app target compiled and linked. Cause: `#expect(_, message)` takes a literal; two messages were `String` variables (`id`, `name`). Fix: interpolated literals (`"\(id)"`, `"\(name)"`). No test ran. Re-run as `test-025`.

**Operator screenshot of the About panel (REPORTED, image, no `test-025` result pasted yet):** `About Till` opens the standard panel in front of other windows from this agent-style app; the credits text shows ("Icons bundled with Till", Huge Icons by Hugeicons, MIT: bio-energy, with icons by Evergrow, MIT: peacock-feather-sketch, and the links), scrollable. Two observations from the same image: the panel shows **Version 1.0 (1)** although `project.yml` sets `MARKETING_VERSION` 0.1.0 (the generated Info.plist, which is git-ignored, carries the xcodegen default `1.0` and does not reference the build setting), and the app icon is the system placeholder (no icon asset exists). Neither is fixed yet. The About panel itself is now VERIFIED to appear and read (operator image), closing the earlier UNVERIFIED item for it.

**Correction to the previous entry (operator, REPORTED):** the About panel opened **behind** another window, not in front. The earlier line "appears in front" and "VERIFIED to appear and read" were wrong and are withdrawn: it appears, it reads, but it was not raised. Cause (hypothesis): for an agent-style app a plain activation can lose to the active app. Fix (unbuilt): `NSApp.activate()` then, after `orderFrontStandardAboutPanel`, `makeKeyAndOrderFront` + `orderFrontRegardless` on visible titled windows (`AboutPanel.shouldRaise`, unit-tested; the raising itself is not). UNVERIFIED until the operator reopens it.

**About panel, second operator screenshot (REPORTED, image):** after the raise fix the panel is in front of the other app's window, but the open Till popover is still on top of it and covers its top edge. Cause (hypothesis): the MenuBarExtra window is on a higher layer than an ordinary window. Fix (unbuilt): the panel's level is set to one above the window it was opened from (`AboutPanel.raisedLevel(above:)`, unit-tested); the popover is deliberately not closed from code (risk of desynchronising its menu-bar item). UNVERIFIED until reopened.

**Operator report after the About-panel layering fix (REPORTED, "success", no output or screenshot pasted):** taken to mean the `test-026` run succeeded and the About panel is no longer covered by the popover. No test count or exit status was pasted, so the run is a report, not a measurement, and the panel result is not itself evidenced by an image. Not yet resolved: Version shows `1.0 (1)` instead of the build setting `0.1.0`; the app icon is the system placeholder; exact MIT license text for Hugeicons, with icons and @icons is still missing; the CC BY credit is in the About panel but not yet on a download page; the five company logos are used as trademarks-bearing artwork on the operator's say-so. No pull request is open.

## Update 18 — App icon (operator request, UNBUILT)
The operator supplied a 512 px transparent PNG of a seedling (checked here: palette PNG with a transparency channel, corners and edges fully transparent, about half the canvas transparent, anti-aliased edges, artwork filling pixels 8 to 504) and its required credit, "Seedling icons created by Umeicon - Flaticon", link https://www.flaticon.com/free-icons/seedling. `Design/AppIcon/make_icon.py` upscales it, sets it on a macOS-style rounded-square plate (824 of 1024 pt, dark green gradient, soft shadow) and writes all ten macOS icon slots to `Sources/Till/Assets.xcassets/AppIcon.appiconset` plus a 1024 px master. `project.yml` gains `ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon`. The credit is in the new `README.md` (verbatim anchor), the About panel (`Credits.appIconCredit`, test first) and `THIRD_PARTY_NOTICES.md`. Previewed here as an image only; **not built**. UNVERIFIED: that the asset catalog compiles and the icon appears in the About panel and Finder; how macOS 26 presents a classic rounded-square icon (it may apply its own container); the Flaticon license terms beyond attribution (not reviewed).

**Operator report on the app icon (REPORTED):** the icon shows in Finder but not in the About panel. Hypothesis (not proven): the panel asks the system for the running app's icon, which for a debug build launched from a build folder can still be the placeholder. Change (unbuilt): the panel is given the icon explicitly (`.applicationIcon: NSImage(named: "AppIcon")`). Tests first: `AppIconTests` checks the icon is loadable by name from the app bundle (the test host is Till.app) and that the panel options carry it. If `theAppIconAssetIsInTheAppBundle` fails, the asset catalog is not producing a loadable icon and the problem is the catalog, not the panel. UNVERIFIED until the operator reopens the panel.

**Operator report after passing the icon explicitly (REPORTED, "success", nothing pasted):** taken to mean the `test-028` run succeeded and the About panel now shows the app icon. No test count, exit status or image was pasted, so this is a report, not a measurement. Whether `AppIconTests` passed individually is not evidenced. Still open: the icon's look under macOS 26 in the Dock (a classic rounded-square icon may get an extra container), Flaticon license terms beyond attribution, MIT notice texts, Version 1.0 vs 0.1.0, no pull request.



## Update 19 — README screenshot (operator request)
The operator supplied a screenshot of the running app (REPORTED, image): the compact tiles with the glass edge, the OpenAI, Z.ai, Claude and opencode marks, tightened time units and the default icon in the composer. Added as `docs/images/popover.png` (703 x 686, 183 KB) and shown at the top of `README.md`. It is a single screenshot of one appearance (dark, over a dark wallpaper); light mode and the other states are still unseen.

## Update 20 — Light appearance and the state tiles, seen live (operator screenshot, REPORTED, image, no message)
One screenshot of the running app in **light appearance** over a light wallpaper, with the menu bar visible. Seen: (1) the menu-bar glyph tinted **red with the count `1`** next to it, which is the red/overdue bar state rendering (earlier UNVERIFIED R3 for the amber/red tint and adjacent count, red case only; the amber and dimmed bar states are still unseen); (2) an **overdue tile**: solid red, white OpenAI mark, `+0m` hero, the `Done` strip in the darker red; (3) an **approaching tile**: outline and digits in a brown that is the light-appearance amber (`Theme.amber` darkened to 4.5:1), the opencode mark in its own light grey; (4) two counting tiles with dark text over the light glass; (5) the composer pill with the default seedling-like icon button and a dark placeholder; the gear is faint but visible. Light appearance is therefore **seen and legible**, no longer entirely unseen; it was never mocked and no contrast was measured on the real window. Still UNVERIFIED: the paused tile, the picker in light mode, Reduce Transparency, Increase Contrast, VoiceOver, the notification firing. Observations, not defects: the approaching brown reads as muted next to the red tile; the gear is the lowest-contrast control.

**README:** the light-appearance screenshot is added beside the dark one (`docs/images/popover-light.png`, shown at 340 px each, with a one-line caption).

## Update 21 — README rewritten from scratch (operator request)
Rewritten with the readme-crafter method: source-first, Product temperament; centered icon, three static badges (platform, language, status), the two screenshots, highlights, build from source, usage table, status and limits, develop, credits (Umeicon attribution verbatim), license status. No test count, version number, CI or license badge (none can be backed). Checks run: the provided scanner (read-only, from a copy with its real file names) found all 8 local links and images present and no README-to-repo mismatches; it also confirms there is no LICENSE file, which the README states. Manual accuracy pass corrected two claims (network use includes previews; no minimum Xcode stated beyond what has been used). Not run here: `xcodegen generate`, the `xcodebuild` build, and `open` (no toolchain); they are copied from the project's own settings and the commands the operator has run. Needs the owner: a license.

## Update 22 — Handoff candidates C1, C2, C3 implemented (cloud session, UNBUILT, NOT RUN)
Operator approved C1, C2 and C3 from `docs/handoff/2026-11-03-architecture-suggestions-HANDOFF.md`, treated the #1859 guard as lifted (PR #1 merged), and skipped C4 to C6. All three are behaviour-preserving refactors; tests were written first.
- **C3** (`f48742a`): `IconChoice.hinted(by:)` and `resolved(with:)` in `IconModels.swift`; the picker and `CreationFlow.resolveIcon` use them; new `IconChoiceTests` (6) pin hint-vs-asset precedence.
- **C2** (`b0cc252`): `ChipPresentation.Tone` with `heroTone`, `iconTone`, `iconOpacity`, `controlTone`, `controlHasFill`; `Theme.color(_:accentHex:)`; `heroColor` and two inline ternaries removed from `ChipCardView`; 4 new tests.
- **C1**: `DisplayTickDriving` and `TaskDisplayTickDriver` (`Store/DisplayTickDriver.swift`), `TimerStore` slimmed (23 funcs to 20, net), `AppModel` wires and starts the driver after `store.start()`; `DisplayTickDriverTests` with `ManualTickDriver`; four old loop tests migrated; `Harness` lost its `sleep` parameter. Design doc updated with the real shape, including a fourth driver member the proposal omitted.
- Handoff claim checked and found already true: the guards are already one `scheduleIfPossible`; only the "not paused and not yet due" predicate was repeated, now `isActiveFuture`.
- GLOSSARY chip entry corrected (it still said "one label"). Not changed: the glossary lists "timer" under Avoid, while notifications and VoiceOver say "Timer".
**Not compiled or run.** New files: `IconChoiceTests.swift`, `DisplayTickDriver.swift`, `DisplayTickDriverTests.swift`; run `xcodegen generate` first. Highest compile risk: `@MainActor` closures in `TaskDisplayTickDriver` under Swift 6 strict concurrency, and the test double conforming to a `@MainActor` protocol. Manual checks that matter (behaviour must be unchanged): tiles tick each second with the popover open; closing it with an approaching timer stays at 1 s and with none drops to 30 s; wake from sleep refreshes the clock; colours match the earlier screenshots; monotone icons tint and multicolor ones do not.

