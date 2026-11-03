# Till

A macOS 26 menu-bar countdown monitor. One menu-bar icon opens a popover of timer tiles: type a
deadline in plain words (`in 20 min`, `1 day 2 hours`, `Fri 5pm`, `Nov 15`), pick an icon, and Till
counts down to it and sends one local notification when time is up. Overdue timers stay until you
mark them done. SwiftUI and SwiftData, Swift 6, no third-party code dependencies, no accounts, no
sync.

<p align="center">
  <img src="docs/images/popover.png" alt="Till's popover in dark appearance: a deadline field with an icon button and a gear menu above four countdown tiles showing 1d 1h, 1d 3h, 2d 12h and 24d 7h, each with a pause control" width="340">
  &nbsp;
  <img src="docs/images/popover-light.png" alt="Till's popover in light appearance with a red overdue tile showing +0m and a Done button, an amber-outlined tile counting down 13:51, and two counting tiles; the menu bar icon is red with the count 1" width="340">
</p>

<p align="center"><sub>Dark and light appearance. The light one shows the overdue tile, the due-soon outline, and the red menu-bar icon with its count.</sub></p>

## Build and test

The Xcode project is generated from `project.yml` (re-run after adding files):

```bash
xcodegen generate
```

```bash
xcodebuild -project Till.xcodeproj -scheme Till -destination 'platform=macOS' -derivedDataPath artifacts/DerivedData CODE_SIGNING_ALLOWED=NO test
```

The app icon is generated from the source artwork:

```bash
python3 Design/AppIcon/make_icon.py
```

## Docs

- `docs/designs/` the design, its addenda and the popover rework spec.
- `docs/evidence/2026-11-03-static-review.md` what has and has not been run or verified.
- `docs/handoff/2026-11-03-session-handoff.md` project context.
- `THIRD_PARTY_NOTICES.md` licenses and credits for bundled artwork.

## Credits

App icon: <a href="https://www.flaticon.com/free-icons/seedling" title="seedling icons">Seedling icons created by Umeicon - Flaticon</a>

Other bundled icons and their authors and licenses are listed in `THIRD_PARTY_NOTICES.md` and in the
app's About panel (gear menu, `About Till`).
