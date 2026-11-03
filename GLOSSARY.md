# Till

The domain language of Till, a macOS menu-bar countdown monitor: chips, the
deadlines they count toward, the states between them, and the bar icon that
surfaces them. One vocabulary, used in code, design docs, and UI copy alike.

## Language

### Chips and deadlines

**Chip**:
A single countdown tile in the popover: one deadline, one icon, one label. The unit the whole app reasons about.
_Avoid_: timer, tile, entry, reminder

**Deadline**:
The absolute moment a chip counts toward. Every deadline is an absolute date from creation on; quick and dated inputs are indistinguishable thereafter.
_Avoid_: target time, due date, end time

**Remaining time**:
Deadline minus the current moment, recomputed on every read. Never stored, never ticked forward.
_Avoid_: count, elapsed time

**Quick deadline**:
A relative input ("in 20 min", "1 day 2 hours") resolved to an absolute date at creation.
_Avoid_: relative timer, quick timer

**Dated deadline**:
A calendar-anchored input ("Fri 5pm", "Nov 15"). A plain date without a time proposes 09:00 and asks for the time before creating.
_Avoid_: scheduled timer, calendar entry

**Parse echo**:
The human-readable readback shown under the deadline field while typing; silent for anything that does not parse.
_Avoid_: preview, autocomplete, live parse

**Tile**:
The visual card a chip renders as in the popover. Every chip is the same tile: fill carries state, the accent colour on the icon carries identity. A UI word, not a domain word.
_Avoid_: chip (for the visual), card, panel

### Chip states

Precedence is fixed: Paused, else Overdue, else Approaching, else Clean.

**Clean**:
A chip whose remaining time is still outside its approach window.
_Avoid_: idle, normal, active

**Approaching**:
A chip whose remaining time is inside its approach window; the "final stretch."
_Avoid_: warning, pending, critical

**Approach window**:
The per-chip final stretch before the deadline during which a chip counts as approaching.
_Avoid_: warning threshold, grace period

**Overdue**:
A chip whose deadline has passed. Stays visible as `+overdue` until explicitly done; there is no auto-archive.
_Avoid_: expired, failed, finished

**Paused**:
A frozen chip. Cannot cross to overdue and is excluded from bar-icon badging until resumed.
_Avoid_: stopped, suspended, sleeping

**Done**:
The explicit user action that resolves an overdue chip, and the only way one leaves the list.
_Avoid_: archive, delete, dismiss, clear

### Ambient signal

**Zero crossing**:
The moment a chip's remaining time passes zero. Fires exactly one local notification per chip; deadlines crossed while asleep notify on wake.
_Avoid_: trigger, expiry event

**Bar icon**:
The single menu-bar icon — the app's only ambient signal — driven by the worst active chip: normal, amber, red with an overdue count, or dimmed when nothing is active or everything is paused.
_Avoid_: status item, menu bar badge, tray icon