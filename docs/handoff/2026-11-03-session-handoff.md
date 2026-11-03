# Till — session handoff (2026-11-03)

**How to use:** open a new Claude Code session on repo `4w4vzkk24c-cyber/till`, branch `claude/zealous-einstein-uwu5oe`, and paste either this whole file or just: *"Read docs/handoff/2026-11-03-session-handoff.md, then docs/designs/2026-11-02-menu-bar-countdown-addendum.md and docs/evidence/2026-11-03-static-review.md, and continue from section 7 (the Iconify search problem). Do not change code until you have the diagnostics in 7.3."*

Everything below is stated as it was known at the end of the previous session. Evidence labels: **MEASURED** = the operator ran it on their Mac and pasted output; **REPORTED** = the operator said so without output; **UNVERIFIED** = written by the previous session, never executed.

---

## 1. Who/what

- **Product:** *Till* — a macOS 26 menu-bar countdown monitor. One menu-bar icon; a `MenuBarExtra` window popover shows named timer "chips" (2 per row: icon, rounded monospaced-digit remaining time, optional label, pause control). Overdue chips stay `+overdue` until the user taps Done. Zero-crossing → one local notification per chip. SwiftUI + SwiftData, Swift 6, zero third-party runtime dependencies, no accounts/sync.
- **Operator:** Zane Robinson (Crossed Keys Co.). **Card:** 1859. Lane: `cofounder-macos-development`.
- **Operator's Mac path:** `~/Repositories/till` (`/Users/zanerobinson/Repositories/till`). Cloud clone: `/home/user/till`.
- **Remote:** `https://github.com/4w4vzkk24c-cyber/till`. Pushing works now (the Claude GitHub App was installed after an initial 403). `git push -u origin claude/zealous-einstein-uwu5oe`. **No PR has been opened and none was requested.** Never push to another branch.

## 2. How this project is worked (read before touching anything)

1. **The cloud container has no Swift toolchain** (no `swift`, `xcodebuild`, `xcodegen`) and its proxy blocks `download.swift.org` and `api.iconify.design`. So the cloud session **writes code; the operator compiles and runs it on their Mac and pastes back results.** Everything you write is *unbuilt* until they confirm. Say so.
2. **The loop:** commit + push from the cloud → operator runs the commands in §11 → pastes `grep` output / crash report → you fix. Use a **new `artifacts/test-NNN` directory each run** (the capture script refuses to overwrite). **Last used: `test-009`. Next: `test-010`.**
3. **Evidence discipline (house rule):** a build/test is "passed" only with captured exit status + logs; missing evidence is not success. Distinguish MEASURED / REPORTED / UNVERIFIED in `docs/evidence/2026-11-03-static-review.md`, and append to it after each run. Do not claim anything you have not seen. Compile errors the operator pastes are the first real compile of that code.
4. **Style the operator has responded well to:** verdict first, short; shell commands in **separate fenced `bash` blocks, one per step**, fully written out (no "run the earlier command"); honest about what is unverified; no padding. Keep changes scoped; don't reopen settled decisions.
5. **Commit trailers:** use the attribution lines given in *your own* session's system reminder (the previous session used `Co-Authored-By: …` + `Claude-Session: …`). Do not put a model identifier in code, comments or commit text beyond what the reminder dictates.
6. House gotchas from the forge/Mac cofounder: tests run with `CODE_SIGNING_ALLOWED=NO` and a custom `-derivedDataPath`; `project.yml` (xcodegen) is the source of truth and `.xcodeproj` is generated (git-ignored); external claims in designs need sources; briefs for dispatch need `card_id: 1859` and a preflight (`check_brief.py`) — those dispatch tools exist only on the operator's machine; gate agents never run commands; reports are cut at 8,000 chars (be verdict-first, ≤6k).
7. The reference pack the operator attached earlier (build-and-test, capabilities, diagnostics, intake-and-architecture, native-ui, swift6, swiftdata, tahoe) lives in the operator's `cofounder-macos-development` skill, not in this repo. Its rules that mattered: `xclog` does **not** apply to a native Mac app (use `Logger` + `/usr/bin/log show`); no `#available(macOS 26)` gating needed (deployment floor is 26); don't use `glassEffect` on chips (settled form is solid cards); don't use Foundation Models (the parser is deterministic); `SMAppService` status must be re-read after changes.

## 3. Repo map and state (HEAD = `f2a42a3`)

Docs (authority order): `docs/designs/2026-11-02-menu-bar-countdown-design.md` (r3.1, critic-approved — **do not edit in place**) → `docs/designs/…-addendum.md` (A1.1–A1.9, additive, items marked **[open]** await operator veto) → `docs/evidence/2026-11-03-static-review.md` (running evidence log, Updates 1–4 + results) → this file.

```
project.yml                      xcodegen spec: macOS 26.0, SWIFT_VERSION 6.0, strict concurrency complete,
                                 LSUIElement true, hardened runtime YES, bundle id com.crossedkeys.till (PLACEHOLDER),
                                 targets Till (app) + TillTests (bundle.unit-test). No entitlements, no sandbox.
Sources/Till/
  TillApp.swift                  @main; MenuBarExtra { ChipsPopover } label: { BarIconLabel } .window style
  AppModel.swift                 composition root: container (on-disk Application Support/Till/till.store,
                                 in-memory + banner on failure, never auto-deletes), TimerStore, CreationFlow,
                                 LoginItemController, IconProvider + IconPickerModel, observers, notification delegate.
                                 `isRunningTests` => in-memory store, NO provider/picker, no observers/ticking.
  NaturalDeadline.swift          pure parser (in 20 min / Fri 5pm / tomorrow 9am / Nov 15 → time prompt) + applyingTime
  DeadlineState.swift            ChipSnapshot, DeadlineState (state, barEscalation, driver, displayOrder), HeroTime
  TickCadence.swift              1 s if popover open or any chip approaching, else 30 s (seed verbatim)
  Spoken.swift                   VoiceOver label text
  LoginItem.swift                SMAppService.mainApp wrapper + controller
  SystemEvents.swift             wake / active / resign observers; UNUserNotificationCenterDelegate
  Store/ChipEntity.swift         @Model + TillSchemaV1 + TillPersistence.makeContainer
  Store/TimerStore.swift         @MainActor @Observable single mutable owner (create/done/pause/resume/edit, toggle,
                                 authorization watcher, single-flight reconciliation, tick loop). RETAINS its container.
  Store/NotificationScheduling.swift  protocol seam + SystemNotificationScheduler (real UN center)
  Icons/IconModels.swift         IconID validation, IconChoice, IconError(+hint), IconFetching/IconNetworking, URLSessionIconNetworking
  Icons/IconProvider.swift       actor: search, fetch, PNG cache (+ .json monotone sidecar), eviction
  Icons/SVGColorInspector.swift  monotone vs palette detection
  Icons/SVGRasterizer.swift      NSImage decode → CGContext redraw at exact pixel size → PNG via ImageIO
  Views/ChipsPopover.swift       header (deadline field, label field, icon row + inline picker, time prompt, errors),
                                 chips grid, footer (notifications, open at login, Quit)
  Views/IconPicker.swift         IconPickerModel, IconPickerView, IconPreviewCell
  Views/CreationFlow.swift       add/edit state machine; icon fetch between time prompt and persist; cancellable
  Views/ChipCardView.swift, BarIcon.swift, ChipViewData.swift (HexColor, FallbackIcons, IconCache, ChipIconView)
Tests/TillTests/                 swift-testing; Harness + MockScheduler + MockNetwork/MockIcons support files
```

Git history is one commit per step; `git log --oneline` reads as the story.

## 4. Settled decisions (binding — do not reopen)

Single menu-bar icon, no Dock presence; `MenuBarExtra` windowed style. Dropdown: static chips 2-per-row — unique icon, hero remaining-time digits (rounded, `monospacedDigit`), optional label, pause control. **No animation, no expression states, no transitions** — static glyph/tint swaps only. Overdue chip stays `+overdue` until the user taps Done; no auto-archive. Zero crossing → one local notification per chip; app-level toggle, default ON; catch-up notify on wake. Bar icon escalates: normal / amber / red + overdue count, dimmed when paused-or-empty; worst active chip drives it. One NL parser field: `in 20 min`, `Fri 5pm`, `Nov 15`; deadlines become absolute at creation; unparseable stays inline with a hint. Icons: any Iconify icon, fetched at chip creation, cached, template-rendered, per-chip accent tint (operator-approved exception: **multicolor icons render untinted**, disclosed in the picker); **no network calls after creation**; custom art later is a pure asset swap. SwiftData single `ChipEntity` (`eventIdentifier` reserved); no CloudKit/sync/export in v1. Distribution: Developer ID + notarytool direct, no App Store, no updater in v1; launch-at-login default OFF via `SMAppService`. Name **Till** (two l's), macOS 26, Swift 6, SwiftUI, xcodegen. Tick cadence is the seed's, verbatim (a parent directive reverted a "better" one). Changing a chip's icon = delete-and-recreate.

## 5. What is built, and how well each piece is evidenced

| Piece | Evidence |
|---|---|
| Parser, state machine, hero-time format | **MEASURED**: passed on the Mac (`test-002`: exit 0, 41 tests) |
| TimerStore + SwiftData + reconciliation (mock scheduler) | **MEASURED**: all passed (`test-004`) |
| Tick loop, views, creation flow, login item, observers | **MEASURED**: `test-005`: 108 tests in 11 suites passed |
| App launches, menu-bar icon present, `LSUIElement` true, no Dock icon, hardened runtime build setting, Swift 6/strict concurrency settings | **MEASURED/REPORTED**: `LSUIElement`=true and build settings pasted; icon visible after the launch-crash fix |
| Manual checklist (bar tint/count R3, `Nov 15` prompt, notification, Done/Pause/Resume/Edit, idle cadence) | **REPORTED** only ("everythings good") — no screenshots/measurements |
| IconProvider, cache, eviction, offline-invariant test, creation-flow icon tests, picker model tests | **MEASURED**: `test-008` 148/149; the one failure was the real-SVG rasterizer size (see §6). Then fixed in `f2a42a3`; the operator reported **"it succeeded"** for the rerun (**REPORTED**; the count — expected 150 — and log were not pasted) |
| **Live Iconify search/fetch in the running app** | **NEVER WORKED/NEVER VERIFIED — this is the open problem (§7).** All icon tests use injected mocks (`MockNetwork`, `MockIcons`); the real `URLSessionIconNetworking` has never been exercised |
| VoiceOver, Increase Contrast/Reduce Transparency, login-item approval flow, signed/notarized build, wake-after-sleep notification dedupe in practice | Not exercised |

## 6. Defects found so far and the lessons (don't repeat)

1. **Launch crash (SwiftData trap in `reload()`):** `AppModel` kept the `ModelContainer` in a local; `TimerStore` kept only `mainContext`, which does not retain the container. 108 green tests missed it because the test `Harness` holds its own container reference. Fixed (store retains container; regression test `storeKeepsItsContainerAlive`). **Lesson: composition-root lifetime is only caught by a real launch. Green logic tests ≠ working app.**
2. **Swift raw strings:** a `"#` inside a `#"…"#` literal ends it; SVG samples need `##"…"##`. Test-only; fixed in `7caeb24`.
3. **`cgImage(forProposedRect:)` does not guarantee pixel size** (real-SVG test `rendersAWhiteSquareWithTransparentSurroundings` failed on `pixelsWide == 256`; decode/centre/corner checks passed → design assumption R1 held). Fixed by always redrawing into an exact-size `CGContext` (`f2a42a3`).
4. Pattern: when a symptom arrives, **get the crash report / `log show` / exact on-screen state first**; the previous session twice guessed (XCTest-detection theory for the launch crash) and was wrong until the report arrived.

## 7. THE OPEN PROBLEM — Iconify search "doesn't turn up anything"

### 7.1 What the operator said
After the rasterizer fix, the test suite succeeded, but "iconify search doesn't turn up anything." **Nothing more is known.** It is *not* known whether (a) the icon row/picker exists at all, (b) the picker opens, (c) pressing Return shows "Searching…", (d) it ends with "No icons found.", (e) a red hint appears, or (f) results appear with blank/warning previews. **Ask for the exact on-screen state before changing code.** The previous session has not diagnosed this and has not seen the app.

### 7.2 How the code is wired (so you can reason without re-reading everything)

- **Row/picker visibility** (`Views/ChipsPopover.swift`): in add mode (not editing) an icon row shows `Text(picker == nil ? "Built-in icon" : "Icon")`; the button toggles `creation.pickerOpen` only `if picker != nil` and is `.disabled(picker == nil || creation.phase != .idle)`. `IconPickerView` renders only if `creation.pickerOpen && picker != nil`.
- **`picker` is nil when** `AppModel.isRunningTests` is true (`AppModel.swift`: env `XCTestConfigurationFilePath`/`XCTestSessionIdentifier` set, **or `NSClassFromString("XCTestCase") != nil`**). In that case there is no `IconProvider`, no observers, no ticking. The earlier log of a manually-launched `Till` showed `com.apple.dt.xctest` lines, so it is **possible the debug app has XCTest loaded and this guard misfires on a normal launch** — but the launch crash happened inside the `!testing` startup task, which suggests it was false at that time. Unresolved.
- **Search path:** `IconPickerView` search `TextField` → `.onSubmit { model.startSearch() }` (Return only — there is no Search button) → `IconPickerModel.search()` → `IconProvider.search(query:prefix:limit:)` → request `GET https://api.iconify.design/search?query=<q>&limit=64` (+`&prefix=` if given) via `URLSessionIconNetworking` (`URLSession(configuration: .ephemeral)`, 10 s timeout, `User-Agent: Till/0.1 (macOS)`) → HTTP 200 required → decode `{"icons": ["mdi:coffee", …], "collections": {prefix: {name, license:{title,spdx}, palette}}}` (only `icons` required) → ids not matching `IconID` (`prefix:name`, lowercase ASCII/digits/single hyphens) are silently dropped → results.
- **UI states** (`IconPickerModel.Status`): `.searching` → "Searching…"; `.empty` → "No icons found."; `.failed(hint)` → red hint; `.idle` with `results` → grid of `IconPreviewCell` (each fetches the icon's SVG to warm cache and render a preview; failure shows a warning triangle); `.idle` with no results shows **nothing** (blank).
- **Error masking:** `IconProvider.get` converts **every** non-cancellation error into `IconError.network` ("Couldn't reach the icon service…"). The real underlying `URLError`/TLS/sandbox error is **discarded and there is no `Logger` anywhere in the app**, so a network failure cannot currently be diagnosed from the app.
- **App entitlements:** none. `project.yml` sets no `ENABLE_APP_SANDBOX` and no entitlements file; hardened runtime is on. (Hardened runtime alone does not block outgoing network; a sandbox without `com.apple.security.network.client` would. **Verify the built app's actual entitlements — don't assume.**)

### 7.3 Diagnostics to run first (ask the operator; each discriminates a hypothesis)

Ranked hypotheses (all UNVERIFIED):

- **H1 — `picker == nil`** (test-host guard misfires, or stale/other build): the icon row says **"Built-in icon"** and clicking does nothing. *Discriminator:* the label text.
- **H2 — request fails and the real error is hidden:** red text "Couldn't reach the icon service…" appears after Return. *Discriminators:* the `curl` below; add a `Logger` of the underlying error; check entitlements; try the app launched from Terminal.
- **H3 — request succeeds but parsing yields nothing / different shape than assumed:** "No icons found." or blank. *Discriminator:* `curl` the exact URL and compare the JSON with `SearchResponse` in `Icons/IconProvider.swift`.
- **H4 — Return doesn't reach the search field's `onSubmit`** inside the MenuBarExtra window (focus): *nothing at all happens, no "Searching…" flash.*
- **H5 — search works but previews/fetch fail in the real app** (e.g. real `fetch` or rasterize on a real Iconify SVG): results grid shows warning triangles. Possible if the real service's SVG differs from the test samples (e.g. gradients, `currentColor`, `<use>`).
- **H6 — stale build:** no icon row at all.

On the operator's Mac (give these as separate fenced blocks):

```bash
curl -sS -m 15 -w '\nHTTP %{http_code}\n' 'https://api.iconify.design/search?query=coffee&limit=5'
```

```bash
curl -sS -m 15 -o /dev/null -w 'svg HTTP %{http_code} bytes %{size_download}\n' 'https://api.iconify.design/mdi/coffee.svg?color=%23ffffff&height=256'
```

```bash
codesign -d --entitlements - "$PWD/artifacts/DerivedData/Build/Products/Debug/Till.app" 2>&1 | head -20
```

```bash
pkill -x Till; open -n "$PWD/artifacts/DerivedData/Build/Products/Debug/Till.app"; sleep 3; pgrep -lx Till || echo "NOT RUNNING"
```

```bash
/usr/bin/log show --last 3m --style compact --predicate 'process == "Till"' | grep -viE 'linkd|autoShortcut|appintents' | tail -60
```

Also ask: what does the icon row's label say ("Built-in icon" vs "Icon")? After opening the picker and pressing Return in the search field, which of the six UI states in §7.1 appears?

### 7.4 Likely fixes by hypothesis (do not apply blind)

- **Always:** stop discarding errors. Add `os.Logger` (subsystem `com.crossedkeys.till`, category `icons`) in `IconProvider.get` / `IconPickerModel.search` logging the underlying error **without** query text or labels; surface a more specific hint (e.g. offline vs HTTP status vs decode). Keep `IconError` typed.
- H1: replace the brittle `NSClassFromString("XCTestCase")` test with an explicit signal (e.g. only the two env vars, or an `-UITests`/launch-argument the test host sets), and/or build `picker` regardless of test status but with a `NoNetwork` fetcher under tests.
- H2: if sandboxed without network client → add the entitlement (and re-check the design's §10 "no sandbox in v1" decision before doing so); if TLS/ATS or proxy → read the logged error.
- H3: adjust `SearchResponse` to the real shape and add the real JSON as a test fixture.
- H4: add an explicit Search button (still static, no animation) in addition to `onSubmit`.
- H5: reproduce with the real SVG saved as a fixture; extend `SVGColorInspector`/rasterizer accordingly.
- After any fix: add/adjust tests, update the evidence file, and ask for **test-010** plus the live checks below.

### 7.5 Live acceptance checks for the icon feature (still all to do, on the Mac)
(1) search `coffee` → results with previews; hover/accessibility hint shows collection · license · tint note; (2) monotone icon → chip tinted with its accent; multicolor (`logos:`) icon → own colours, untinted; (3) Wi-Fi off → inline hint, built-in icons still create chips, already-cached icon still works; (4) after a chip with a fetched icon exists, no further requests to `api.iconify.design` (the offline invariant, e.g. `nettop`/Little Snitch); (5) delete chip, wait >5 min, mutate any chip → its PNG + `.json` vanish from `~/Library/Application Support/Till/icons`; (6) dismiss the popover mid-fetch → no chip, field usable next time.

## 8. Decisions awaiting operator veto (all marked [open] in the addendum)

A1.5 initial focus on the add field; A1.6 parser readings (`in 20m` accepted; `Nov 3` typed on Nov 3 stays this year; overdue ≥ 24 h shows hours; tie-break = smallest deadline); A1.7 delivered-wins when a notification is in both pending and delivered, editing a paused chip keeps it paused, notification text = chip label or "Timer" / "Time's up"; A1.8 label entered in a second optional field, Edit loads only the label (blank deadline = keep), popover-open inferred from `onAppear/onDisappear` + app active/resign, Quit in footer, accent palette; A1.9 icon fetched after the time prompt and before persist, picker previews cost one request per visible result, cache sidecar `.json`, eviction with 5-min grace.

## 9. Known risks / unverified assumptions

R3 (does the menu bar render the amber/red `NSImage` tint and the adjacent count text? operator says fine, no evidence), popover-open signal heuristics, bundle identifier `com.crossedkeys.till` is a placeholder, the System Settings deep link `x-apple.systempreferences:com.apple.Notifications-Settings.extension` is unverified, `SMAppService` flows untested, notification delegate behaviour untested beyond compile, the 1 s tick tests poll with `Task.yield` (potentially flaky), no repeated-run flake assessment.

## 10. Remaining work (suggested order)

1. **Resolve §7** (diagnose first; fix; verify live; record evidence).
2. Repeat-run the suite a few times to check tick-loop test flakiness; capture the full `Test run with N tests` line and exit status in the evidence file (the 150 figure is an expectation, not a measurement).
3. Accessibility pass: VoiceOver (labels/actions), Increase Contrast, Reduce Transparency, light/dark contrast of red/amber/gray on the card.
4. Release work: real bundle id / team, signing, notarization (`notarytool`), staple, Gatekeeper check on the downloaded artifact, `.dmg`; revisit entitlements/sandbox decision (§10 of the design) if network needs it.
5. Optional hardening: on-disk SwiftData predicate/fixture tests and a committed v1 store fixture (addendum A1.3), snapshot tests.

## 11. Commands template (Mac, from `~/Repositories/till`; bump the test number)

```bash
git fetch origin claude/zealous-einstein-uwu5oe && git checkout claude/zealous-einstein-uwu5oe && git pull --ff-only origin claude/zealous-einstein-uwu5oe
```

```bash
xcodegen generate
```

```bash
bash "$HOME/.agents/skills/cofounder-macos-development/scripts/capture-build.sh" "$PWD/artifacts/test-010" -- -project Till.xcodeproj -scheme Till -destination 'platform=macOS' -derivedDataPath "$PWD/artifacts/DerivedData" -resultBundlePath "$PWD/artifacts/test-010.xcresult" CODE_SIGNING_ALLOWED=NO test
```

```bash
grep -nE 'error:|recorded an issue|✘|Test run with|TEST SUCCEEDED|TEST FAILED' artifacts/test-010/build.log | grep -v autoShortcut
```

Failing-test detail: `xcrun xcresulttool get test-results test-details --test-id '<Suite>/<test>()' --path artifacts/test-010.xcresult`. Crash reports: `~/Library/Logs/DiagnosticReports/Till-*.ips` (the previous session used a small Python script to print the exception and faulting-thread frames from the newest one).

Harmless log noise in every run: `com.apple.linkd.autoShortcut` connection errors and AppIntents "metadata extraction skipped" — from the app being the test host, not Till code.

## 12. Swift 6 / tooling gotchas already hit or designed around

`@MainActor` closure properties must not capture mutable local `var`s (use the `Box<T>` test helper); a function named like its local result (`let content = content(for:)`, `guard let moment = moment(...)`) is a self-reference error — rename; `ModelContext` does not retain its `ModelContainer`; SwiftData `rollback()` does restore a pending insert/delete (measured); `UNAuthorizationStatus.ephemeral` is not available on macOS (the scheduler uses `default:`); test fixtures avoid real-time sleeps except the tick tests; icon ids are validated before use in URLs or file names; the PNG cache is `~/Library/Application Support/Till/icons/{prefix}--{name}.png` plus `.json` sidecar, read by `IconCache` for chip display.
