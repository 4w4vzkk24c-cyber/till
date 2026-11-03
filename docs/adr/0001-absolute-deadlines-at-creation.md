---
status: accepted
---

# 0001: Every deadline becomes an absolute date at creation

Quick relative inputs ("in 20 min") and dated inputs ("Fri 5pm") both resolve to
one absolute `Date` at creation, stored on the chip; nothing about the input's
original form survives creation (`ParsedDeadline.kind` is a parse-time concept
only). The state machine, bar icon, and notifications never learn where a
deadline came from, and remaining time is always `deadline − now` — recomputed,
never accumulated from tick deltas — so sleep/wake self-corrects for free.

## Considered options

- **Store the intent (e.g. "in 20 min" as a duration offset):** two deadline
  vocabularies would flow through every module — ChipsPopover rendering,
  `DeadlineState`, notifications, the popover rework's tile fill — and each
  would need to re-resolve the anchor moment. Rejected; the resolution moment
  belongs to creation, where the clock and calendar already exist.
- **Accumulate remaining time from 1 s/30 s ticks:** drifts across suspensions
  and app sleep contradicts the wake-reconciliation invariant. Rejected in favor
  of the pure read.

## Consequences

- Editing a deadline re-parses through `NaturalDeadline` and produces a new
  absolute date; there is no "keep the relative countdown, shift the base"
  operation.
- A quick deadline's anchor is creation time, permanently: "in 20 min" saved
  before a 3-hour sleep crosses while away, fires catch-up on wake (zero
  crossing, one notification per chip) — it does not wait for wake plus 20
  minutes.