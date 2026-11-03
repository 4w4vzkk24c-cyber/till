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
