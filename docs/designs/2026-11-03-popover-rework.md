# Popover visual rework (addendum A2)

**Card:** 1859 · **Status:** operator-approved 2026-11-03 (mock v3) · **Authority:** additive to `2026-11-02-menu-bar-countdown-design.md` r3.1 and the A1 addendum. Where this file and A1.8 / design §4 disagree, this file wins for presentation only. No behavior, data or state-machine change.

**Source of truth for look:** `assets/2026-11-03-popover-mock-v3.html` (rendered: `assets/2026-11-03-popover-mock-v3.png`). Fonts and pixel glyphs in the mock are stand-ins; the app uses system fonts and the existing icon pipeline.

**Inspiration:** a single calm tile: centered icon, plain monospaced digits, one pause glyph, a quiet gear top right (operator-supplied screenshot of FocusPet).

## Principles
1. One object, repeated: every chip is the same tile.
2. Fill carries state; accent colour carries identity. Counting tiles are neutral; the chip's accent appears on its icon only. Amber and red mean state and nothing else.
3. State is never colour alone: a caption under the digits says it in words.
4. Static: no animation, no spinner, no transition (design §4 stands).

## Chip tile (156 pt wide at the 340 pt popover, ~152 pt tall)
Order, centered: icon 40 pt, label (12 pt medium, one line, slot reserved even when empty), hero digits (26 pt bold, monospaced, `minimumScaleFactor` 0.7), caption slot (12 pt semibold, 14 pt reserved), control strip (full-width hit target, 28 pt tall).

| State | Surface | Caption | Control |
|---|---|---|---|
| Counting (clean) | neutral translucent fill, hairline | none | pause |
| Approaching | neutral fill + 2 pt amber outline; digits and caption amber | `due soon` | pause |
| Overdue | solid red `#CF2F36`; white icon, digits, caption | `overdue` | `Done` (replaces pause; strip filled black 28%) |
| Paused | no fill, 1.5 pt dashed outline; dimmed icon and digits | `paused` | resume |

Hero text is the normative `HeroTime` string. Overdue renders `+41m overdue` as hero `+41m` plus caption `overdue` (a rendering split, not a format change). VoiceOver label (`Spoken`) is unchanged.

## Colour
- Accent palette (new chips only; stored chips keep their stored hex): `#6FCFFF #8FE0A0 #D2A4FF #FF93C9 #5EE0CF #A8B1FF`. Hues must stay out of the state hues (0–60° and 340–360°). Each reads at >= 3:1 on the dark tile (`#445D8E` reference).
- Legacy accents (`#F5A623 #4FC3F7 #81C784 #BA68C8 #FF8A65 #FFD54F`) are adjusted for legibility at draw time by lightness only, hue preserved.
- Amber `#FFC15E` (dark), derived darker in light appearance to >= 4.5:1 for the caption. White on the red fill measures 5.11:1.
- Text on tiles in dark appearance: primary 100%, secondary 82%, tertiary 66% white. Measured on the mock: secondary label 4.8:1, paused digits 7.7:1, paused label 5.6:1, amber caption 8.3:1; placeholder 3.5:1 (known weakest).
- Light appearance is **derived, not mocked**: system semantic label colours, tile = black ~6%, hairline black ~12%. Operator reviews it on the Mac.

## Popover
- Width 340 (unchanged). Padding 10, tile gap 8, concentric radii: tile 20, control 12, field pill 20. The window's own corner radius is system-controlled; tile radius is a single constant to tune after seeing it on the Mac.
- Surface: system window material with a blue-ish tint overlay. Reduce Transparency: opaque tint. Increase Contrast: stronger hairline and tile fill.
- Chips scroll in a region up to 470 pt (was 420) so three rows show.
- **Composer** (replaces the two fields, the icon row and the footer): one pill with a leading 26 pt icon tile button, the deadline field (`in 20 min, Fri 5pm`), and a right-aligned label field with a visible `Label` placeholder; the gear sits beside it. Below it, one status line.
- **Status line precedence:** error, then `Fetching icon…`, then editing note (`Editing. Leave the deadline blank to keep it.` with Cancel), then parse echo. The time prompt (`At what time?`, time picker, Set, Cancel) keeps its current behavior and is drawn as a row in the same style. **Edit mode, the time prompt and error styling are not in the mock;** they reuse the field row and status-line styles and need operator review.
- **Parse echo** (new, pure): `Friday 5:00 PM, in 3 d 7 h`; date-only input reads `Nov 15, then you pick a time`; unparseable or past input shows nothing (the error still appears on submit).
- **Gear menu** (replaces the footer): Notifications toggle, Open at login toggle, Quit Till. A denied permission and a login item awaiting approval appear as extra menu rows with an action. The gear shows an amber dot while either needs attention (notifications denied only counts while the Notifications toggle is on, or a login error exists, or approval is pending).
- **Picker** (inline under the composer): search field, 6-column result grid, a disclosure line for the highlighted result, and a built-in row (all eight built-ins, 26 pt cells; the mock shows six with a caption, dropped to fit). States, all static text: `Searching…`; `No icons match “q”. Try a simpler word, such as coffee or bell.`; the error hint (red-tinted block). Never blank after a search.
- **Empty state:** `Nothing counting down`, `Type when it’s due. Till tells you when time’s up.`, three example chips (`in 20 min`, `Fri 5pm`, `Nov 15`) that fill the field.

## Deviations from settled decisions (operator-approved)
1. Hero digits: true monospace instead of rounded (design §4 said rounded).
2. Translucent popover surface; chips stay solid (no `glassEffect` on chips, unchanged).
3. New cool accent palette (A1.8 item 6); existing chips keep theirs.
4. Footer toggles and Quit move into the gear menu.

## Not in this pass
Custom pixel icon sets, animation of any kind, light-mode mock.

## Menu-bar glyph (operator decision, 2026-11-03, after the mock)
The bar glyph changes from the SF `timer` symbol to Font Awesome 5 Solid `seedling` (Iconify `fa-solid:seedling`, CC BY 4.0). Still one static glyph with the same four tint variants and overdue count (design §6). It is bundled as an embedded SVG (`BarGlyph`), rasterized once at launch and tinted for amber/red, so there is no network call; if rasterizing ever fails the bar falls back to the SF `timer`. Attribution is required (see `THIRD_PARTY_NOTICES.md`); an in-app or download-page credit is still to be added before shipping.

