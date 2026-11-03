# Till — architecture suggestions handoff (2026-11-03, session of the domain-modeling + design passes)

**How to use:** open a session on repo `4w4vzkk24c-cyber/till`, branch
`claude/peaceful-hawking-avdm1c` (HEAD `b00d673` at write time), and read this
file plus `GLOSSARY.md`. Then read
`docs/designs/2026-11-03-tick-store-seam.md` before touching
`Sources/Till/Store/TimerStore.swift` — candidate C1 below has a full design
doc; the others are one-paragraph proposals.

**Scope of this file:** work *suggested or marked worth exploring* in the
2026-11-03 review session (codebase-domain-modeling pass, codebase-design pass,
architecture-improvement pass with an independent fresh-context walker). It is
not the app's build history — that lives in
`docs/handoff/2026-11-03-session-handoff.md` and `docs/evidence/`. Evidence
labels follow the repo convention: **MEASURED** = ran against the tree this
session; **REPORTED** = stated without output; **PROPOSED** = suggestion only,
no decision made.

---

## Start here

Till's architecture held up under review: the pure-core/imperative-shell split
is real, every protocol seam has two adapters (MEASURED: `MockScheduler` /
`SystemNotificationScheduler`, `MockLoginItem` / `SMAppServiceLoginItem`,
`MockIcons` / real provider — zero hypothetical seams), and the domain
vocabulary is now written down in `GLOSSARY.md`. Six deepening candidates came
out of the passes; one has a committed design doc, two are worth exploring, and
three are speculative hygiene rated honestly as such. Nothing here is a
decision — each candidate needs its own go-ahead before building.

## Objective and acceptance

- **Outcome:** a Till codebase where each module has one vocabulary, colour and
  action decisions live in unit-tested layers, and cadence tests cost no
  persistence harness.
- **Done when (per candidate):** see each card's acceptance note.
- **Non-goals:** no cadence change (`TickCadence` stays the single authority,
  MEASURED `active: 1` / `idle: 30` — a walker report of "1 s/5 s" was wrong and
  was corrected); no behaviour change at all in C1–C6; no re-litigating
  ADR 0001.

## Constraints and authority

- **Sequencing guard:** card #1859 (`status: in-progress` in kanban-zed) is the
  peer lane's active build. **Do not build any candidate until #1859 lands.**
  The hot-spot files (`ChipCardView`, `ChipPresentation`, `ChipsPopover`,
  `IconPicker`, `TimerStore`) are all in that lane's blast radius.
- **Authorized already:** docs commits on this branch (glossary, seam design,
  ADR 0001) were made and pushed by the reviewing session with Zane's
  go-ahead; they are additive only.
- **Requires fresh approval:** implementing any candidate — the design doc
  covers C1 only; C2–C6 need at least a "go" plus, if via the switchyard, the
  usual route (`switchyard-route`; C1 is likely a sprint-tier card).
- **Repo/branch facts (MEASURED at write time):** branch
  `claude/peaceful-hawking-avdm1c` at `b00d673`, clean tree, pushed and
  converged with origin. A second active branch
  (`claude/zealous-einstein-uwu5oe`) is the peer's; main is `64be8b7`+.
  Rebase before extending anything.

## Decisions to preserve

| Decision | Reason or evidence | Reopen only if |
| --- | --- | --- |
| Chip is the domain object; tile is its visual rendering | Popover-rework line "every chip is the same tile"; `GLOSSARY.md` records both | A third word appears in docs or code |
| Every deadline becomes absolute at creation | ADR 0001 (accepted): two rejected options recorded; wake catch-up behaviour is deliberate | Chip storage model changes fundamentally |
| Cadence is 1 s visible-or-approaching / 30 s otherwise | `TickCadence.swift` MEASURED | Design §7.4/TRC-01 is amended |
| No animation anywhere; static glyph/tint swaps only | Domain invariants (`~/.openclaw/domains/till.json`) + design docs | — |

## Current state

### Already done (committed, pushed `5702ce2..b00d673`)

- `GLOSSARY.md` — 17 canonical terms (chip/tile split settled; README still
  says "timer tiles" — see C7).
- `docs/designs/2026-11-03-tick-store-seam.md` — PROPOSED design for C1 with
  measured baseline (TimerStore = 23 funcs), shape, two adapters, mutation-style
  acceptance, and the #1859 guard.
- `docs/adr/0001-absolute-deadlines-at-creation.md` — accepted.

### Candidates awaiting a go-ahead

#### C1 — Extract the display-tick driver from TimerStore (Strong)

`TimerStore` is two modules sharing one interface (23 funcs: 5 chip-mutation, 6
tick-lifecycle, plus authorization). Design doc exists:
`DisplayTickDriving` protocol (start/stop), adapters `TaskDisplayTickDriver`
(existing loop verbatim) and `ManualTickDriver` (tests);
`TimerStore` keeps ~17 chip-shaped funcs; `AppModel` composes. The seam is real
— two consumers exist today. **Acceptance (from the doc):** a cadence test
constructing neither `ModelContainer` nor `NotificationScheduling`; ≥5 func
drop against 23; existing tests pass or migrate mechanically. Combine with the
walker's scheduling-guard finding: the wake/tick/notification paths duplicate
`pausedAt`/clock/authorization checks — fold them into one private
`scheduleIfPossible` in the same change.

#### C2 — Pull tile colour decisions into ChipPresentation (Worth exploring)

MEASURED: `ChipCardView.heroColor` (≈ line 79) is a second, untested
state→colour enum parallel to `ChipPresentation.surface`. "What colour is this
tile?" currently bounces through `ChipViewData` → `ChipPresentation` →
`Theme`/`Contrast` → `heroColor` (`ChipCardView`). Move surface→colour-token
decisions into `ChipPresentation` (reading `Theme`, not hard-coding hexes);
delete `heroColor`; `ChipCardView` becomes a pure map. Acceptance:
`ChipPresentationTests` covers the full colour surface; no colour enum survives
in a view file.

#### C3 — Name the icon monotone hint→truth step (Worth exploring)

MEASURED: `IconPicker` (≈ line 146) sets `monotone` eagerly from the palette
hint; the fetched asset's truth lands later, silently, in
`CreationFlow.resolveIcon` (≈ line 139) — the model comment says the asset
wins. Make it a named, tested step in the Icons layer: `IconChoice` carries the
hint; one function produces the final flag at asset resolution. Acceptance: a
unit test pins hint-vs-asset precedence in one place.

#### C4 — One definition of the Pause/Resume action per tile (Speculative)

MEASURED: three switch sites — context menu (`state == .paused`,
`ChipCardView` ≈ 46–56), control strip (`p.control == .resume`), and
`pauseOrResume` (`pausedAt == nil`, `ChipsPopover` ≈ line 116). They cannot
disagree while the state precedence is fixed, but a tile-state change touches
all three. Fix: context menu reads `ChipPresentation.control`;
`pauseOrResume` trusts the presentation. Act only if the rework mutates tile
states again (it has, twice this week).

#### C5 — Bar escalation as a function of explicit inputs (Speculative)

MEASURED: `DeadlineState.barEscalation` is pure, but `now` reaches it only via
the live tick loop, so "bar goes amber at N minutes" is assertable only
end-to-end. C1's `ManualTickDriver` mostly solves this (advance `now`
explicitly, assert bar state). Only add a store query taking `now` if a real
test still needs it after C1.

#### C6 — Give the error funnel an explicit contract (Speculative)

REPORTED by the walker, spot-checked at file level: `CreationFlow.perform`
(≈ 125) / `errorHint` paths (≈ 157–160) / `message(for:)` (≈ 167–179). The
post-failure contract is implicit — `notFound` resets the flow, other errors
don't, nothing in the interface says why. Fix when the creation flow next
gains an error path (the icon fetch is the likely one):
`message(for:)` → `(text, resetsFlow: Bool)`, one tested mapping.

#### C7 — README wording: "timer tiles" → chips (one-word fix, not made)

The peer's 2026-11-03 README rewrite still opens with "popover of timer
tiles"; `GLOSSARY.md` rules chip = domain object, tile = visual rendering
("every chip is the same tile" — their own rework doc). Left unedited because
they were actively rewriting the file. One word, next time anyone touches the
README.

## Artifacts

| Artifact | Path | Status |
| --- | --- | --- |
| Domain glossary | `GLOSSARY.md` (repo root) | committed, pushed |
| C1 design doc | `docs/designs/2026-11-03-tick-store-seam.md` | committed, pushed, PROPOSED |
| ADR 0001 | `docs/adr/0001-absolute-deadlines-at-creation.md` | committed, pushed, accepted |
| Architecture review report (HTML, dark-mode, 6 cards) | `/Users/zanerobinson/.openclaw/tmp/architecture-review-20261103-172052.html` | delivered to Zane; tmp — regenerate if needed |
| Peer's session handoff (build history) | `docs/handoff/2026-11-03-session-handoff.md` | theirs, keep separate |
| Domain invariants | `~/.openclaw/domains/till.json` (outside repo) | repo path field updated post-move |

## Verification performed

- Module inventory and line-cite spot checks: MEASURED against the tree
  (2026-11-03): TimerStore func count 23; `heroColor` at ChipCardView ≈79;
  tick-loop guards TimerStore ≈120–130; IconPicker eager monotone ≈146;
  `TickCadence.active=1, idle=30`.
- Walker claims used only after spot-check; one factual error caught and
  corrected (cadence). Walker verdict: done, 6 items.
- No candidate has been built; no tests were run for this handoff (none
  needed — no code changed).

## Immediate next step

When #1859 lands: claim a card for C1, carry
`docs/designs/2026-11-03-tick-store-seam.md` as the design input, and build the
driver extraction with its mutation-style acceptance. C2 is the second pick if
the popover colour language mutates first. Everything else waits for its
trigger.