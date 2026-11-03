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
