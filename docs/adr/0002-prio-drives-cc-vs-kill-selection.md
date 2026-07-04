# prio drives CC-vs-kill selection; CC-worthiness is only the auto-candidacy floor

**Status:** accepted (marking-redesign Phase 4, grilled 2026-07-04)

## Context & decision

Phase 4 derived a **CC-worthiness** curve (mob role × tier) and used it two ways: to *rank* which
pack mobs get scarce CC slots (batch `DecidePull`) and to *threshold* per-mob auto-CC (scanner). In
effect the engine preferred to CC the **highest-worthiness** mob — a healer — which is backwards for
the far more common play pattern: **kill the healer first, and CC the mobs you'll get to last**
(dangerous adds; a melee that fears / stuns / shreds armor and must die *last* but not be loose). It
also fought the human's own **prio** (kill-order) knob, and even contradicted this repo's own
`CONTEXT.md` example dialogue, which already said the healer is *skulled* via low prio.

**Decision:** **`prio` is the single driver of CC-vs-kill *selection*.** Among CC candidates, the mobs
killed **last** (highest prio number) get the scarce CC slots; the mobs killed **first** (lowest prio)
are killed, skull to the lowest. **CC-worthiness is demoted to one job: the auto-CC *candidacy floor*** —
which mobs are eligible for *automatic* CC without a human `type=="CC"` flag (healers / elite casters
clear it; trash does not). `type=="CC"` **forces** candidacy for a below-floor mob (the fear-melee).
The engine always leaves **≥1 kill target** (reserve-a-kill-target).

## Considered options

- **Worthiness-ranked selection (rejected — as shipped in Phase 4B).** CC the most "valuable" mob.
  Simple and fully automatic, but backwards for the common "kill the healer" strategy, blind to
  pack-specific human knowledge (a fear-melee is low-worthiness yet must be CC'd), and un-overridable
  except by disabling CC wholesale.
- **Prio-driven selection (accepted).** The human's kill-order knob orders CC-vs-kill; CC the kill-last
  tail. Matches traditional play, honors explicit human intent, keeps worthiness as a small candidacy
  gate. Costs a **default inversion** (a healer is skulled, not sheeped, by default) and a rewrite of
  `DecidePull`'s CC ranking.

## Consequences

- **The default flips:** a healer + caster pack now **skulls the healer** (low prio, killed first) and
  **CCs the caster** (killed last), instead of sheeping the healer. The "sheep the costly healer"
  framing is retired from `CONTEXT.md`.
- CC-worthiness shrinks to the candidacy floor (kept, so a spare slot never sheeps unflagged trash).
- The human controls CC-vs-kill three complementary ways: **static per-mob `prio`** (kill order),
  **static `type=="CC"`** (force candidacy + class preference), and the **dynamic HUD enable/disable of
  CC players** (live capacity/class dial — reuses `disabledMarks`).
- **Reserve-a-kill-target**: a fully-CC'd pack is never auto-produced; neutralizing an entire pack is a
  manual action.
- The **scanner** (per-mob, cannot sort a pack) approximates the policy with the worthiness floor +
  reserve-skull; the **batch** does the full prio-ordered selection. Consistent with
  [ADR 0001](0001-pack-awareness-in-prefight-batch.md): pack-relative reasoning is batch-only.
- Not a per-mob "never-CC / force-kill" **veto**: a human can't yet force-kill an above-floor mob while
  CCing a lower one *except* by prio ordering or disabling the CC slot. Deferred until in-game shows it
  is needed.
