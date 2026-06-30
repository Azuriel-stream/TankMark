# Pack-aware marking lives in the pre-fight batch, not the automatic scanner

**Status:** accepted (marking-redesign Phase 4, grilled 2026-06-30)

## Context & decision

The marking-intelligence redesign needs *pack-aware* decisions — the same mob type CC'd in one pull and
killed-first in another, based on what it's standing next to (sheep the lone elite Warrior to clear the
trash; sheep the Oracle healer beside two Warriors and skull the Warriors). The obvious home for this is
the **automatic scanner**, since it already drives all in-combat marking. We deliberately chose the
opposite: the pack-relative brain (`DecidePull`) lives in the **pre-fight Shift+mouseover Batch path**,
and the automatic scanner stays greedy/per-mob. The scanner gains only a *narrow, gated, per-mob*
auto-CC of **absolutely**-worthy mobs (healers/elite casters) — edited in the pure decision layer
(`ResolveCC`), never the `OnUpdate` scan loop.

## Considered options

- **Make the automatic scanner pack-aware (rejected).** The scanner discovers a pack **incrementally** —
  nameplates appear over the first ~1–2 s of a pull. A pack-level plan committed on tick 1 (when only the
  Warrior is visible) is already wrong on tick 2 (when the Oracle aggros), and stickiness forbids
  re-shuffling committed marks. So genuine pack reasoning fights the scanner's nature, and the payoff is
  reachable from pre-marking anyway. It would also mean surgery on the fragile, load-bearing scan loop.
- **Pre-fight batch + scoped scanner auto-CC (accepted).** The Batch path sees the *whole* pack
  pre-combat (complete information, deliberate trigger), so `DecidePull` can be a pure, fixture-testable
  function. The scanner only does the *absolute* CC call (a healer is worth CCing regardless of pack),
  which is local and incremental-safe.

## Consequences

- The **relative** "sheep the durable melee" trick is **pre-fight only**; the automatic scanner never
  makes pack-relative calls. This is a deliberate capability limit, not a bug.
- The fragile scanner `OnUpdate` loop and `ProcessUnit`'s verification front-half are **never touched**;
  all new decision logic lives in the pure, off-client-tested layer.
- "A patrol joins mid-fight" is handled by the *existing* in-combat mechanics (skull walks down the kill
  order via the death path; CC marks stay sticky), not by re-planning.
- Both behaviors ship behind default-off toggles — zero behavior change until opt-in.
