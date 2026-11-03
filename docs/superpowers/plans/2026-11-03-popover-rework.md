# Till Popover Rework Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restyle Till's popover to the approved v3 design (neutral tiles whose fill and caption carry state, one composer, gear menu, designed picker states), and first make Iconify failures diagnosable.

**Architecture:** Keep every state machine and store as is. Add small pure types (`ChipPresentation`, `ParseEcho`, `SettingsAttention`, `ComposerStatus`, `Contrast`, `IconFailure`) that the SwiftUI views read, so the testable decisions are unit-tested and the views stay thin. Views get a `Theme` value built from the environment's colour scheme and contrast.

**Tech Stack:** Swift 6 (strict concurrency complete), SwiftUI, SwiftData, swift-testing, `os.Logger`, xcodegen. macOS 26 floor, no third-party dependencies.

**Spec:** `docs/designs/2026-11-03-popover-rework.md` (look: `docs/designs/assets/2026-11-03-popover-mock-v3.html` and `.png`). Parent: `docs/designs/2026-11-02-menu-bar-countdown-design.md` r3.1 plus addendum A1. Context: `docs/handoff/2026-11-03-session-handoff.md`.

## Global Constraints

- **No Swift toolchain in the cloud.** Everything is written unbuilt; the operator builds and runs on the Mac. Never claim a build or test passed without pasted output. Say "unbuilt" in commit bodies and evidence.
- Swift 6, `SWIFT_STRICT_CONCURRENCY: complete`, deployment target macOS 26.0, no `#available` gating, zero third-party runtime dependencies.
- **No animation anywhere:** keep `.transaction { $0.animation = nil }` on the popover root; no spinner, no transition, no `withAnimation`.
- No `glassEffect` on chips (solid tiles). The translucent surface is the popover background only.
- No network call after chip creation; the icon service is only reached from the picker and creation flow (design §5, pinned by `IconProviderTests`).
- `Logger` subsystem `com.crossedkeys.till`. **Never log query text, labels, URLs or icon ids' queries**; log operation name, error domain and code, HTTP status only.
- `project.yml` is the source of truth; `.xcodeproj` is generated and git-ignored. New files under `Sources/Till` and `Tests/TillTests` are picked up by `xcodegen generate`.
- VoiceOver text comes from `Spoken` and is unchanged; each tile stays one accessibility element with Edit / Pause|Resume / Done actions.
- Hero text is the normative `HeroTime` string (design §4); presentation may split it but not reformat it.
- Existing chips keep their stored `accentHex`; do not migrate data.
- Commit trailers: use the attribution lines from your own session's system reminder. No model identifier in code, comments or commit text beyond what the reminder dictates.
- Push only to `claude/peaceful-hawking-avdm1c`. No PR unless asked.
- Evidence discipline: label results MEASURED (operator pasted output) / REPORTED / UNVERIFIED in `docs/evidence/2026-11-03-static-review.md`. Next artifacts directory is `artifacts/test-010` (last used `test-009`; the capture script refuses to overwrite).

## Review Focus

Failure modes the spec implies but a straight implementation would miss, most likely first. Each has a test in the owning task.

1. **Stored legacy accents** (amber, coral, yellow from the old palette) must stay legible on both tiles and must not read as state. Task 2 (`legacyAccentsStayLegible…`).
2. **Overdue of a day or more** (`+50h overdue`) must split into hero and caption without losing digits. Task 3.
3. **Echo for hostile input** (empty, gibberish, a past time, `in 0 min`) must return nil, never crash or show a stale line. Task 4.
4. **Gear badge nagging**: permission denied while the user has turned Notifications off must not badge. Task 5.
5. **Awkward search text** in the no-results message (curly quotes, 64 characters, leading/trailing spaces) must render intact and never blank the picker. Task 6.

Manual-only (views, no test seam): very long or emoji labels truncate to one line with an unchanged tile height; an unlabeled chip keeps the label slot; light appearance, Reduce Transparency, Increase Contrast, bright and dark wallpapers. These are on the Task 8 checklist.

---

### Task 1: Make Iconify failures diagnosable

Do first and push; the operator's live result decides Task 6 (see the hold note there).

**Files:**
- Create: `Sources/Till/Icons/IconFailure.swift` (holds `IconFailure` and `IconLog`)
- Modify: `Sources/Till/Icons/IconModels.swift` (`IconError`), `Sources/Till/Icons/IconProvider.swift` (`get`, status and decode logging), `Sources/Till/AppModel.swift` (launch signals)
- Test: `Tests/TillTests/IconDiagnosticsTests.swift` (new); update `Tests/TillTests/IconProviderTests.swift:99` and `:172`

**Interfaces:**
- Produces: `IconError` gains `.offline`, `.tls`, `.timedOut` (all `Equatable`, `Sendable`); `IconFailure.classify(_ error: Error) -> IconError`; `IconLog.describe(_ error: Error, operation: String) -> String`; `IconLog.record(_ error: Error, operation: String)`; `IconLog.recordStatus(_ status: Int, operation: String)`; `TestHostSignals` (struct with `configurationFile`, `sessionIdentifier`, `xctestClassLoaded: Bool`, `isTesting: Bool`, `static func current() -> TestHostSignals`).
- Consumes: nothing from other tasks.

- [ ] **Step 1: Write the failing tests** in `IconDiagnosticsTests.swift`

```swift
@Suite struct IconFailureTests {
    @Test func offlineCodesMapToOffline() {
        let codes: [URLError.Code] = [.notConnectedToInternet, .networkConnectionLost, .dataNotAllowed]
        for code in codes { #expect(IconFailure.classify(URLError(code)) == .offline) }
    }
    @Test func tlsCodesMapToTLS() {
        let codes: [URLError.Code] = [.secureConnectionFailed, .serverCertificateUntrusted,
            .serverCertificateHasBadDate, .serverCertificateHasUnknownRoot,
            .appTransportSecurityRequiresSecureConnection]
        for code in codes { #expect(IconFailure.classify(URLError(code)) == .tls) }
    }
    @Test func timeoutMapsToTimedOut() { #expect(IconFailure.classify(URLError(.timedOut)) == .timedOut) }
    @Test func otherErrorsStayNetwork() {
        #expect(IconFailure.classify(URLError(.cannotFindHost)) == .network)
        #expect(IconFailure.classify(TestFailure()) == .network)
    }
    @Test func iconErrorsPassThrough() { #expect(IconFailure.classify(IconError.badStatus(503)) == .badStatus(503)) }
    @Test func logLineNamesDomainAndCodeButNeverTheURL() {
        let error = URLError(.notConnectedToInternet,
            userInfo: [NSURLErrorFailingURLStringKey: "https://api.iconify.design/search?query=secret-query"])
        let line = IconLog.describe(error, operation: "search")
        #expect(line == "search failed: NSURLErrorDomain -1009")
        #expect(!line.contains("secret-query"))
    }
    @Test func diagnosableCasesHaveDistinctHints() {
        let hints = [IconError.offline, .tls, .timedOut, .network, .badStatus(500)].map(\.hint)
        #expect(Set(hints).count == 5)
    }
}

@Suite struct TestHostSignalsTests {
    @Test func anySignalMeansTesting() {
        #expect(TestHostSignals(configurationFile: false, sessionIdentifier: false, xctestClassLoaded: true).isTesting)
        #expect(TestHostSignals(configurationFile: true, sessionIdentifier: false, xctestClassLoaded: false).isTesting)
    }
    @Test func noSignalMeansNormalLaunch() {
        #expect(!TestHostSignals(configurationFile: false, sessionIdentifier: false, xctestClassLoaded: false).isTesting)
    }
}
```

In `IconProviderTests.swift` change the two `IconError.network` expectations that use `MockNetwork.offline` (`:99`, `:172`) to `IconError.offline`, and add a test that a `MockNetwork { _ in throw URLError(.secureConnectionFailed) }` makes `search` throw `IconError.tls`.

- [ ] **Step 2: Run to verify it fails** (operator, Mac): `xcodegen generate` then the capture command in the Task 8 command block with `artifacts/test-010`. Expected: compile errors for the missing symbols.

- [ ] **Step 3: Implement.**
  - `IconError`: add the three cases. Hints (no apology, say the fix): `.network` → `Can’t reach the icon service. Check your connection, or pick a built-in icon.`; `.badStatus(code)` → `The icon service returned an error (\(code)). Try again, or pick a built-in icon.`; `.offline` → `You’re offline. Pick a built-in icon, or try again once you’re connected.`; `.tls` → `Can’t make a secure connection to the icon service. Check your VPN or proxy, or pick a built-in icon.`; `.timedOut` → `The icon service didn’t answer in time. Try again, or pick a built-in icon.` Other cases keep their text.
  - `IconFailure.classify` maps by `URLError.code` using the sets in the tests; non-URLError and unlisted codes become `.network`; an `IconError` is returned unchanged.
  - `IconLog` wraps a `Logger(subsystem: "com.crossedkeys.till", category: "icons")`. `describe` builds `"\(operation) failed: \(ns.domain) \(ns.code)"` from `error as NSError`; `record` logs it at `.error` with `privacy: .public`; `recordStatus` logs `"\(operation) status \(status)"`.
  - `IconProvider.get(_ url: URL, operation: String)`: keep the two cancellation catches; the final catch calls `IconLog.record` then throws `IconFailure.classify(error)`. Call `IconLog.recordStatus` when a non-200 status is turned into `.badStatus`, and `IconLog.logger.error("\(operation) decode failed")` before throwing `.decodeFailed`. Pass `"search"` / `"fetch"` from the two callers.
  - `AppModel`: replace the body of `isRunningTests` with `TestHostSignals.current().isTesting` (same three signals, no behavior change). In `init`, log once at `.notice` in category `launch`: `testing=… configurationFile=… sessionIdentifier=… xctestClass=…` (booleans only, `privacy: .public`). Do not remove the `NSClassFromString("XCTestCase")` signal in this task; the log decides whether it misfires (handoff H1).

- [ ] **Step 4: Run tests** (operator). Expected: `** TEST SUCCEEDED **` and a `Test run with N tests … passed` line; record N in the evidence file (no earlier count is trustworthy beyond "succeeded").

- [ ] **Step 5: Commit and push**, then ask the operator for the live diagnostics: relaunch the app, search `coffee` once, then run the bounded capture in the handoff addendum (`--info --debug`, saved to `artifacts/diag-001/`, exit status recorded) and paste its tail, the label of the icon row, and which on-screen state appeared (handoff §7.1/§7.3).

```bash
git add Sources/Till/Icons Sources/Till/AppModel.swift Tests/TillTests
git commit -m "Icons: typed offline/TLS/timeout errors, os.Logger diagnostics, launch signal log (1859, unbuilt)"
git push -u origin claude/peaceful-hawking-avdm1c
```

---

### Task 2: Colour system and accent palette

**Files:**
- Create: `Sources/Till/Views/Contrast.swift`, `Sources/Till/Views/Theme.swift`
- Modify: `Sources/Till/Views/ChipViewData.swift` (`HexColor`), `Sources/Till/Views/CreationFlow.swift` (`accents`)
- Test: `Tests/TillTests/ColorSystemTests.swift` (new)

**Interfaces:**
- Produces: `Contrast.ratio(_ a: String, _ b: String) -> Double` (hex `#RRGGBB`, WCAG relative luminance); `HexColor.hue(of: String) -> Double?` (degrees 0..<360); `HexColor.adjusted(_ hex: String, forLight: Bool, minContrast: Double) -> String` (uppercase `#RRGGBB`; changes HSL lightness only, in 0.01 steps, until the contrast against the reference tile meets `minContrast`; unchanged if it already does; reference tiles `#ECEFF6` light, `#445D8E` dark); `Theme` struct:

```swift
struct Theme {
    init(_ scheme: ColorScheme, _ contrast: ColorSchemeContrast)
    var tile: Color; var hairline: Color
    var ink: Color; var ink2: Color; var ink3: Color      // 100 / 82 / 66 % white in dark; system label colours in light
    var amber: Color                                      // #FFC15E dark; adjusted(forLight, 4.5) in light
    func accent(_ hex: String) -> Color                   // adjusted(hex, forLight: scheme == .light, minContrast: 3.0)
    static let overdueFill: Color                         // #CF2F36
    enum Radius { static let tile: CGFloat = 20; static let control: CGFloat = 12; static let pill: CGFloat = 20 }
    enum Space { static let s: CGFloat = 8; static let m: CGFloat = 12; static let pad: CGFloat = 10 }
}
```
  and `CreationFlow.accents = ["#6FCFFF", "#8FE0A0", "#D2A4FF", "#FF93C9", "#5EE0CF", "#A8B1FF"]`.
- Consumes: nothing.

- [ ] **Step 1: Write the failing tests**

```swift
@Suite struct ColorSystemTests {
    static let legacy = ["#F5A623", "#4FC3F7", "#81C784", "#BA68C8", "#FF8A65", "#FFD54F"]

    @Test func contrastMatchesWCAGReferences() {
        #expect(abs(Contrast.ratio("#FFFFFF", "#000000") - 21) < 0.01)
        #expect(abs(Contrast.ratio("#FFFFFF", "#FFFFFF") - 1) < 0.0001)
    }
    @Test func overdueFillCarriesWhiteText() { #expect(Contrast.ratio("#FFFFFF", "#CF2F36") >= 4.5) }
    @Test func newAccentsAvoidTheStateHues() throws {
        for hex in CreationFlow.accents { let h = try #require(HexColor.hue(of: hex)); #expect(h > 60 && h < 340) }
    }
    @Test func newAccentsReadOnTheDarkTile() {
        for hex in CreationFlow.accents { #expect(Contrast.ratio(hex, "#445D8E") >= 3.0) }
    }
    @Test func legacyAccentsStayLegibleInBothAppearances() {
        for hex in Self.legacy + CreationFlow.accents {
            #expect(Contrast.ratio(HexColor.adjusted(hex, forLight: true, minContrast: 3.0), "#ECEFF6") >= 3.0)
            #expect(Contrast.ratio(HexColor.adjusted(hex, forLight: false, minContrast: 3.0), "#445D8E") >= 3.0)
        }
    }
    @Test func adjustmentKeepsHueAndLeavesLegibleColoursAlone() {
        for hex in Self.legacy {
            let adjusted = HexColor.adjusted(hex, forLight: true, minContrast: 3.0)
            #expect(abs(HexColor.hue(of: adjusted)! - HexColor.hue(of: hex)!) < 2)
        }
        #expect(HexColor.adjusted("#1C9383", forLight: true, minContrast: 3.0) == "#1C9383")
    }
    @Test func amberCaptionIsLegibleOnTheLightTile() {
        #expect(Contrast.ratio(HexColor.adjusted("#FFC15E", forLight: true, minContrast: 4.5), "#ECEFF6") >= 4.5)
    }
}
```

- [ ] **Step 2: Run to verify it fails** (operator; compile error on missing `Contrast`/`HexColor.adjusted`). May batch with Task 3's run.

- [ ] **Step 3: Implement** the signatures above. `Contrast.ratio` uses the sRGB linearisation and `(L1+0.05)/(L2+0.05)`. `adjusted` converts to HSL, steps lightness (up for dark, down for light) and stops at 0 or 1. `Theme.tile` is white 10% (dark) / black 6% (light), 18% / 12% under `.increased`; `hairline` white 16% / black 12%, doubled under `.increased`. Replace `CreationFlow.accents`; leave the rotation logic alone. Do not touch stored chips.

- [ ] **Step 4: Run tests** (operator). Expected: `ColorSystemTests` and the existing `accentsCycle` pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/Till/Views Tests/TillTests/ColorSystemTests.swift
git commit -m "Colour system: contrast helper, hue-safe accent palette, Theme tokens (1859, unbuilt)"
```

---

### Task 3: Chip tile and grid

**Files:**
- Create: `Sources/Till/Views/ChipPresentation.swift`
- Modify: `Sources/Till/Views/ChipCardView.swift` (rewrite body), `Sources/Till/Views/ChipsPopover.swift` (`chipsGrid`: spacing 8, empty state, `maxHeight` 470)
- Test: `Tests/TillTests/ChipPresentationTests.swift` (new)

**Interfaces:**
- Consumes: `ChipState`, `HeroTime`, `DeadlineState` (existing); `Theme`, `Theme.overdueFill`, `Theme.Radius`, `Theme.accent(_:)` (Task 2).
- Produces:

```swift
struct ChipPresentation: Equatable {
    enum Surface: Equatable { case neutral, dueSoon, overdue, paused }
    enum Control: Equatable { case pause, resume, done }
    let surface: Surface; let hero: String; let caption: String?; let control: Control
    init(state: ChipState, heroText: String)
}
```

- [ ] **Step 1: Write the failing tests**

```swift
@Suite struct ChipPresentationTests {
    @Test func captionsSayTheState() {
        #expect(ChipPresentation(state: .clean, heroText: "12:40").caption == nil)
        #expect(ChipPresentation(state: .approaching, heroText: "4:12").caption == "due soon")
        #expect(ChipPresentation(state: .overdue, heroText: "+41m overdue").caption == "overdue")
        #expect(ChipPresentation(state: .paused, heroText: "14h 32m").caption == "paused")
    }
    @Test func surfaceAndControlFollowState() {
        let cases: [(ChipState, ChipPresentation.Surface, ChipPresentation.Control)] = [
            (.clean, .neutral, .pause), (.approaching, .dueSoon, .pause),
            (.overdue, .overdue, .done), (.paused, .paused, .resume)]
        for (state, surface, control) in cases {
            let p = ChipPresentation(state: state, heroText: "1h 05m")
            #expect(p.surface == surface && p.control == control)
        }
    }
    @Test func overdueHeroDropsTheWordOverdue() {   // Review Focus 2
        #expect(ChipPresentation(state: .overdue, heroText: "+41m overdue").hero == "+41m")
        #expect(ChipPresentation(state: .overdue, heroText: "+50h overdue").hero == "+50h")
        #expect(ChipPresentation(state: .overdue, heroText: "+0m overdue").hero == "+0m")
    }
    @Test func otherHeroTextPassesThrough() {
        for text in ["3d 14h", "14h 32m", "4:12"] { #expect(ChipPresentation(state: .clean, heroText: text).hero == text) }
    }
    @Test func agreesWithHeroTimeForARealChip() {
        let now = TestClock.now
        let chip = ChipSnapshot(id: UUID(), deadline: now.addingTimeInterval(-(41 * 60 + 5)), approachWindow: 1800)
        let p = ChipPresentation(state: DeadlineState.state(of: chip, at: now), heroText: HeroTime.format(chip: chip, at: now))
        #expect(p.hero == "+41m" && p.caption == "overdue")
    }
}
```

- [ ] **Step 2: Run to verify it fails** (compile error: `ChipPresentation` undefined).

- [ ] **Step 3: Implement `ChipPresentation`** (overdue hero = text with a trailing ` overdue` removed). Rewrite `ChipCardView.body` to the spec's tile table: centered `VStack(spacing: 2)` with padding top 10 / sides 6 / bottom 6; icon 40 pt tinted `theme.accent(data.accentHex)` (white on the overdue fill, 50% opacity when paused; multicolor icons stay untinted as today); label 12 pt medium `ink2`, one line, 16 pt slot always present; hero 26 pt bold `.monospaced`, `minimumScaleFactor(0.7)`; caption 12 pt semibold in a 14 pt slot (empty string keeps the height); control strip full-width, 28 pt, `contentShape(Rectangle())`, corner `Theme.Radius.control`, showing `pause.fill` / `play.fill` / the text `Done` per `control`. Surfaces: neutral = `theme.tile` fill + 0.5 pt hairline; dueSoon = neutral fill darkened (black 28%) + 2 pt amber stroke, amber hero and caption; overdue = `Theme.overdueFill`, strip filled black 28% with white `Done`; paused = no fill, 1.5 pt dashed stroke. Keep `contextMenu`, the single accessibility element, the three accessibility actions and the overdue-cannot-pause guard exactly as they are. Grid: two flexible columns, spacing 8; empty state is Task 7's.

- [ ] **Step 4: Run tests** (operator). Expected: `ChipPresentationTests` pass; all earlier suites still pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/Till/Views Tests/TillTests/ChipPresentationTests.swift
git commit -m "Chips: state-by-fill tile with caption and full-width control (1859, unbuilt)"
```

---

### Task 4: Parse echo

**Files:**
- Create: `Sources/Till/ParseEcho.swift`
- Test: `Tests/TillTests/ParseEchoTests.swift` (new)

**Interfaces:**
- Consumes: `NaturalDeadline.parse(_:now:calendar:timeZone:)`, `ParsedDeadline` (existing).
- Produces: `ParseEcho.text(for input: String, now: Date, calendar: Calendar, timeZone: TimeZone) -> String?`.

- [ ] **Step 1: Write the failing tests** (`TestClock.now` is Tue 2026-11-03 10:00 America/Chicago, `en_US_POSIX`)

```swift
@Suite struct ParseEchoTests {
    private func echo(_ s: String) -> String? {
        ParseEcho.text(for: s, now: TestClock.now, calendar: TestClock.calendar, timeZone: TestClock.zone)
    }
    @Test func quickTimer() { #expect(echo("in 20 min") == "Today 10:20 AM, in 20 min") }
    @Test func weekdayAndClock() { #expect(echo("Fri 5pm") == "Friday 5:00 PM, in 3 d 7 h") }
    @Test func tomorrowUnderADay() { #expect(echo("tomorrow 9am") == "Tomorrow 9:00 AM, in 23 h") }
    @Test func hoursAndMinutes() { #expect(echo("in 90 min") == "Today 11:30 AM, in 1 h 30 min") }
    @Test func dateOnlyAsksForATimeNext() { #expect(echo("Nov 15") == "Nov 15, then you pick a time") }
    @Test func hostileInputShowsNothing() {          // Review Focus 3
        for s in ["", "   ", "gibberish", "today 9am", "in 0 min", "yesterday 5pm"] { #expect(echo(s) == nil) }
    }
}
```

- [ ] **Step 2: Run to verify it fails** (compile error).

- [ ] **Step 3: Implement `ParseEcho.text`.** Call `NaturalDeadline.parse`; any thrown error returns nil. Day label: `Today`, `Tomorrow`, the full weekday from `calendar.weekdaySymbols` when the deadline is within the next 6 days, else `"<shortMonthSymbols> <day>"`. Time via `DateFormatter` (`timeStyle = .short`, `locale = calendar.locale ?? .current`, calendar and time zone applied), with U+202F and U+00A0 replaced by a plain space. Relative part from the whole-second remaining: at least 24 h → `in {d} d {h} h` (drop ` {h} h` when 0); at least 1 h → `in {h} h {m} min` (drop ` {m} min` when 0); else `in {m} min`. Date-only (`timePromptRequired`) returns `"<day label>, then you pick a time"` with the date label rule (never `Today`).

- [ ] **Step 4: Run tests** (operator). If the time string differs only by the separator or AM/PM spelling on macOS 26, fix the normalisation in `ParseEcho`, not the test.

- [ ] **Step 5: Commit**

```bash
git add Sources/Till/ParseEcho.swift Tests/TillTests/ParseEchoTests.swift
git commit -m "ParseEcho: pure human readback of the deadline field (1859, unbuilt)"
```

---

### Task 5: Settings menu (gear)

**Files:**
- Create: `Sources/Till/Views/SettingsMenu.swift`
- Modify: `Sources/Till/Views/ChipsPopover.swift` (remove the `footer`, `notificationsBinding`, `loginBinding`; they move into `SettingsMenu`)
- Test: `Tests/TillTests/SettingsAttentionTests.swift` (new)

**Interfaces:**
- Consumes: `TimerStore.authorization: NotificationAuthorization?`, `TimerStore.notificationsEnabled`, `TimerStore.setNotificationsEnabled(_:) async`, `LoginItemController` (`isOn`, `needsApproval`, `errorText`, `setEnabled(_:)`, `openSystemSettings()`), `Theme` (Task 2).
- Produces: `SettingsAttention.needsBadge(authorization: NotificationAuthorization?, notificationsEnabled: Bool, loginNeedsApproval: Bool, loginError: String?) -> Bool`; `struct SettingsMenu: View { let store: TimerStore; let loginItems: LoginItemController }`.

- [ ] **Step 1: Write the failing tests**

```swift
@Suite struct SettingsAttentionTests {
    private func badge(_ auth: NotificationAuthorization?, enabled: Bool = true, approval: Bool = false, error: String? = nil) -> Bool {
        SettingsAttention.needsBadge(authorization: auth, notificationsEnabled: enabled, loginNeedsApproval: approval, loginError: error)
    }
    @Test func deniedWhileOnBadges() { #expect(badge(.denied)) }
    @Test func deniedWhileTheUserTurnedItOffDoesNotBadge() { #expect(!badge(.denied, enabled: false)) }   // Review Focus 4
    @Test func authorizedOrUnknownDoesNotBadge() { #expect(!badge(.authorized)); #expect(!badge(nil)); #expect(!badge(.notDetermined)) }
    @Test func loginApprovalBadges() { #expect(badge(.authorized, approval: true)) }
    @Test func loginErrorBadges() { #expect(badge(.authorized, error: "boom")) }
}
```

- [ ] **Step 2: Run to verify it fails** (compile error).

- [ ] **Step 3: Implement.** `SettingsAttention.needsBadge` is true if (`authorization == .denied` and `notificationsEnabled`) or `loginNeedsApproval` or `loginError != nil`. `SettingsMenu` is a `Menu` (`.menuStyle(.button)`, `.buttonStyle(.plain)`, label `Image(systemName: "gearshape")`, 32 pt hit area, `ink3`) containing: `Toggle("Notifications")` (disabled while denied), a `Button("Notifications are off for Till. Open System Settings")` row when denied (opens the existing `x-apple.systempreferences:com.apple.Notifications-Settings.extension` URL), `Toggle("Open at login")`, a `Button("Approve Till in Login Items")` row when `needsApproval`, the login error text as a disabled row when present, a `Divider`, and `Button("Quit Till")` with `keyboardShortcut("q")`. Bindings are the two that currently live in `ChipsPopover` (moved verbatim). Overlay a 9 pt `theme.amber` dot at the top trailing corner while `needsBadge` is true; accessibility label `Settings, needs attention` / `Settings`. **Keep Quit reachable at every commit:** in this task, delete the footer and put `SettingsMenu` at the trailing end of the existing header's deadline-field row; Task 7 then moves it beside the composer pill.

- [ ] **Step 4: Run tests** (operator). Manual: the gear opens a menu inside the `MenuBarExtra` window and the toggles work (UNVERIFIED: SwiftUI `Menu` inside a window-style `MenuBarExtra`; if it fails to open, fall back to a `.popover` on the gear and tell the operator).

- [ ] **Step 5: Commit**

```bash
git add Sources/Till/Views Tests/TillTests/SettingsAttentionTests.swift
git commit -m "Settings: gear menu replaces footer, attention badge (1859, unbuilt)"
```

---

### Task 6: Picker rework

**Hold:** do not start until the operator has answered Task 1's diagnostics. If the result is H4 (Return never reaches the search field) add a visible Search button to the field in this task; if H1/H2/H3 the fix belongs in Task 1's area first.

**Files:**
- Modify: `Sources/Till/Views/IconPicker.swift` (`IconPickerModel`, `IconPickerView`, `IconPreviewCell`)
- Test: `Tests/TillTests/IconFlowTests.swift` (extend `IconPickerModelTests`)

**Interfaces:**
- Consumes: `IconSearchResult`, `IconError.hint`, `FallbackIcons.all`, `CreationFlow.selectIcon(_:)`, `Theme` (Task 2).
- Produces on `IconPickerModel`: `private(set) var lastQuery: String` (trimmed text of the most recent search); `var highlighted: IconSearchResult?` (set to the first result after a successful search, cleared on failure or empty); `static func statusText(for status: Status, query: String) -> String?`.

- [ ] **Step 1: Write the failing tests** (added to `IconPickerModelTests`; reuse its `result(_:)` helper)

```swift
@Test func statusTextCoversEveryState() {
    #expect(IconPickerModel.statusText(for: .idle, query: "coffee") == nil)
    #expect(IconPickerModel.statusText(for: .searching, query: "coffee") == "Searching…")
    #expect(IconPickerModel.statusText(for: .empty, query: "qzxv")
            == "No icons match “qzxv”. Try a simpler word, such as coffee or bell.")
    #expect(IconPickerModel.statusText(for: .failed("Hint."), query: "x") == "Hint.")
}
@Test func awkwardQueriesStayIntactInTheNoResultsText() {      // Review Focus 5
    let q = "“it’s” \"quoted\" " + String(repeating: "a", count: 40)
    #expect(IconPickerModel.statusText(for: .empty, query: q)!.contains(q))
}
@Test func searchRecordsTheTrimmedQueryAndHighlightsTheFirstResult() async {
    let model = IconPickerModel(provider: MockIcons(search: .success([result("mdi:coffee"), result("mdi:tea")])))
    model.query = "  coffee "
    await model.search()
    #expect(model.lastQuery == "coffee")
    #expect(model.highlighted?.id == "mdi:coffee")
}
@Test func failureAndEmptyClearTheHighlight() async {
    let model = IconPickerModel(provider: MockIcons(search: .success([])))
    model.highlighted = result("mdi:coffee")
    model.query = "zzzz"
    await model.search()
    #expect(model.highlighted == nil)
}
```

- [ ] **Step 2: Run to verify it fails** (compile error on the new members).

- [ ] **Step 3: Implement the model members, then the view** per the mock: a 32 pt rounded search field (Return runs `startSearch()`); the status text from `statusText`, rendered as plain secondary text, or a red-tinted block for `.failed`; a 6-column result grid of 24 pt previews in 12 pt-radius cells, selected/highlighted cell outlined 2 pt in `ink`, `onHover` sets `highlighted`, tap calls `selectIcon` exactly as today; the disclosure line for `highlighted` using the existing `IconPickerModel.disclosure(for:)` (its strings are unchanged); then a hairline and the built-in row of all eight `FallbackIcons.all` at 26 pt, spacing 6, each with its existing accessibility label. Remove the footer line `Icons come from Iconify…`. `IconPreviewCell` keeps its fetch/warm-cache behavior and failure triangle, at 24 pt. Container: `theme.tile` fill, `Theme.Radius.tile`, 0.5 pt hairline, padding 8.

- [ ] **Step 4: Run tests** (operator). Expected: all `IconPickerModelTests` pass, including the existing ones (the `Status` enum is unchanged).

- [ ] **Step 5: Commit**

```bash
git add Sources/Till/Views/IconPicker.swift Tests/TillTests/IconFlowTests.swift
git commit -m "Picker: designed search states, highlight disclosure, built-in row (1859, unbuilt)"
```

---

### Task 7: Composer, status line and popover assembly

**Files:**
- Create: `Sources/Till/Views/ComposerView.swift`, `Sources/Till/Views/ComposerStatus.swift`
- Modify: `Sources/Till/Views/ChipsPopover.swift` (replace `header` and `iconRow`, empty state, surface, `maxHeight`)
- Test: `Tests/TillTests/ComposerStatusTests.swift` (new)

**Interfaces:**
- Consumes: `CreationFlow` (`input`, `label`, `phase`, `errorHint`, `editingID`, `isFetchingIcon`, `selectedIcon`, `pickerOpen`, `startSubmit()`, `cancel()`, `confirmTime()`, `promptHour`, `promptMinute`), `ParseEcho.text` (Task 4), `SettingsMenu` (Task 5), `IconPickerView` (Task 6), `ChipIconView`, `Theme` (Task 2).
- Produces: `ComposerStatus` enum (`.error(String)`, `.fetching`, `.editing`, `.echo(String)`) with `static func line(error: String?, fetching: Bool, editing: Bool, echo: String?) -> ComposerStatus?` choosing in that precedence, or nil.

- [ ] **Step 1: Write the failing tests**

```swift
@Suite struct ComposerStatusTests {
    @Test func errorBeatsEverything() {
        #expect(ComposerStatus.line(error: "Nope.", fetching: true, editing: true, echo: "Today 10:20 AM") == .error("Nope."))
    }
    @Test func fetchingBeatsEditingAndEcho() {
        #expect(ComposerStatus.line(error: nil, fetching: true, editing: true, echo: "x") == .fetching)
    }
    @Test func editingBeatsEcho() { #expect(ComposerStatus.line(error: nil, fetching: false, editing: true, echo: "x") == .editing) }
    @Test func echoShowsWhenNothingElseDoes() {
        #expect(ComposerStatus.line(error: nil, fetching: false, editing: false, echo: "Today 10:20 AM") == .echo("Today 10:20 AM"))
    }
    @Test func nothingMeansNoLine() { #expect(ComposerStatus.line(error: nil, fetching: false, editing: false, echo: nil) == nil) }
}
```

- [ ] **Step 2: Run to verify it fails** (compile error).

- [ ] **Step 3: Implement `ComposerStatus`, then the views.** `ComposerView`: a 40 pt pill (`theme.tile`, 0.5 pt hairline) holding a 26 pt round icon-tile button (shows `creation.selectedIcon` via `ChipIconView`, toggles `pickerOpen`, accessibility label `Choose icon`, help `Choose icon`; disabled while `phase != .idle` or `picker == nil`, as today), the deadline `TextField` (placeholder `in 20 min, Fri 5pm`, editing placeholder `New deadline (optional)`, `onSubmit { creation.startSubmit() }`, focus binding supplied by the popover so initial focus stays on it), and a right-aligned label `TextField` with placeholder `Label` (also submits); `SettingsMenu` beside the pill. Under it, the status line rendered from `ComposerStatus.line` (echo only when not editing and `phase == .idle`; error style = red-tinted rounded block; `Fetching icon…` as static text; editing note `Editing. Leave the deadline blank to keep it.` plus a `Cancel` button), then the existing time prompt row (`At what time?`, hour/minute `DatePicker`, `Set`, `Cancel`, default action) with the same row styling, then `IconPickerView` when `pickerOpen` and `picker != nil`. `ChipsPopover.body`: composer, then the grid or the empty state (`Nothing counting down`, `Type when it’s due. Till tells you when time’s up.`, three example buttons `in 20 min`, `Fri 5pm`, `Nov 15` that set `creation.input` and refocus the field), no divider or footer; padding `Theme.Space.pad`, width 340, grid scroll cap 470, `.transaction { $0.animation = nil }` kept, `onAppear`/`onDisappear` bodies unchanged. Tray surface: tint over the system window material; under `accessibilityReduceTransparency` an opaque tint of the same hue; the `loadError` line keeps its red caption above the composer.

- [ ] **Step 4: Run tests** (operator). Expected: `ComposerStatusTests` pass; all earlier suites still pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/Till/Views Tests/TillTests/ComposerStatusTests.swift
git commit -m "Popover: composer pill, status line, empty state, tray surface (1859, unbuilt)"
```

---

### Task 8: Evidence and operator verification

**Files:**
- Modify: `docs/evidence/2026-11-03-static-review.md` (append Update 5), `docs/handoff/2026-11-03-session-handoff.md` (note that Tasks 1–7 exist and what is still unverified)

- [ ] **Step 1: Append Update 5** to the evidence file: what changed per task, labelled **unbuilt** until pasted output exists; list every UNVERIFIED item (SwiftUI `Menu` in a `MenuBarExtra` window, time-format separator on macOS 26, window corner radius vs `Theme.Radius.tile`, light appearance, Reduce Transparency, Increase Contrast).

- [ ] **Step 2: Give the operator the run block** (one command per fenced block, fully written out) and ask for the pasted `grep` output:

```bash
git fetch origin claude/peaceful-hawking-avdm1c && git checkout claude/peaceful-hawking-avdm1c && git pull --ff-only origin claude/peaceful-hawking-avdm1c
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

```bash
pkill -x Till; open -n "$PWD/artifacts/DerivedData/Build/Products/Debug/Till.app"; sleep 3; pgrep -lx Till || echo "NOT RUNNING"
```

- [ ] **Step 3: Manual checklist for the operator** (report each as seen / not seen; screenshots welcome): (1) all four tile states side by side, amber outline and caption legible, Done on the red tile; (2) an unlabeled chip and a 60-character label keep the tile height; (3) composer: add a timer, label visible placeholder, Tab between fields, echo line updates, `Nov 15` time prompt, edit mode via right-click; (4) gear menu opens and toggles work, dot appears with notifications denied and the toggle on; (5) picker: search `coffee`, no-results text with `qzxv`, Wi-Fi off shows the offline hint and built-ins still work; (6) light appearance; (7) System Settings > Accessibility > Display: Reduce Transparency and Increase Contrast; (8) over a bright and a dark wallpaper; (9) VoiceOver reads each tile as before; (10) nothing animates.

- [ ] **Step 4: Commit and push**

```bash
git add docs
git commit -m "Docs: popover rework evidence update 5 and operator checklist (1859)"
git push -u origin claude/peaceful-hawking-avdm1c
```
