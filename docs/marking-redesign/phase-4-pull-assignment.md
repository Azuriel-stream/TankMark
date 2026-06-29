# Phase 4 — Pull-level coordinated assignment

> Prev: [`phase-3-role-and-priority.md`](phase-3-role-and-priority.md) · Next:
> [`phase-5-cast-learning.md`](phase-5-cast-learning.md) · Up:
> [`00-OVERVIEW.md`](00-OVERVIEW.md) · Schema: [`DATA-MODEL.md`](DATA-MODEL.md)

## Goal

Stop deciding each mob in isolation. Reason about the **whole visible pull** at once: route CC to the
best **legal** targets via **stable slots**, lay down a **deliberate kill-order ladder**
(Skull→Cross→Square→…), and leave overflow trash unmarked **on purpose** — all while keeping marks
**sticky and consistent** across ticks and pulls. This is where the redesign pays off; build it last,
on the data from Phases 1–3.

## Prereqs

Phases 1, 2 and 3 landed and verified in-game. Do not start before then.

## Scope / non-goals

- **In:** a `DecidePull` pass over the scanner's candidate set; stable-slot CC routing; the full
  kill-order ladder; deliberate overflow; deterministic + sticky behavior.
- **Out:** changing the Ledger/governor/swarm/sync mechanism; interrupts (Phase 5+). The pass **emits
  intents only** and applies through the existing edge.

## Design

### Where it plugs in

The scanner's DECISION phase (`Core/TankMark_Scanner.lua`) already builds the in-combat candidate set
and sorts it by `(prio, hp)`, then calls `ProcessUnit(guid,"SCANNER")` per mob. Replace that per-mob
loop with a single `DecidePull(candidates, board)` that returns a **list of intents**, which the shell
applies via the existing `ApplyMarkIntent` for each. `ProcessUnit`'s sanity/ownership-verification front
half still runs per candidate (or is factored so the pull pass consumes already-verified candidates) —
do not lose the `[v0.26]` ownership cross-check.

Keep `DecidePull` **pure and board-injected**, exactly like `DecideMark`, so it is fully unit-testable
off-client. Reuse the existing board ports and add what the pass needs (CC roster, blocking info — both
already exist as `findCCPlayer`/`getBlockingMarkInfo`).

### The pass (deterministic, sticky)

Input: the candidate set (each: guid, name, entry with `creatureType`/`tier`/`role`/`prio`/`type`/`class`),
plus the profile's tank roster (`GetTankRoster`, `Assignment.lua:142–158`) and a new **CC roster**
(`GetCCRoster`, mirroring it — see [`DATA-MODEL.md §4`](DATA-MODEL.md#4-control-slot-model-consistency-mechanism)).

1. **Skip held marks (stickiness).** Any candidate already owning a Ledger mark keeps it — the scanner
   already `Reaffirm`s these. The pass only assigns to **unmarked** candidates and never reshuffles an
   existing mark. This is what guarantees cross-tick/cross-pull consistency.
2. **Classify.** For each unmarked candidate compute: legal-CC set (`IsLegalCC`, Phase 2), kill priority
   (authored `prio`, already role×tier-derived in Phase 3), and whether it's CC-worthy (CASTER/HEALER, or
   `type=="CC"`).
3. **CC pass (stable slots).** For each CC control slot `(mark, player, legalSet)` in roster order, pick
   the best unassigned candidate whose creatureType ∈ `legalSet` and that is CC-worthy — deterministically
   (stable key: e.g. highest priority, then lowest guid/name) so the **same pack → same slot routing**.
   Emit `{icon = slot.mark}` for that mob. A slot with no legal candidate is simply left empty this pull.
   Player↔mark never changes.
4. **Kill-order ladder.** Order the remaining (non-CC'd) kill candidates by priority and assign the
   tank/kill marks as a **deliberate descending order** — Skull first, then the next free profile marks.
   Reuse `IncumbencyBlocks` (`Assignment.lua:229–231`) so the ladder's `>=` discipline matches the
   governor and can't drift. The skull governor still applies through the normal apply path.
5. **Overflow (deliberate).** If kill candidates outnumber remaining marks, mark the highest-priority
   ones and **leave the lowest-value trash unmarked on purpose**. Surface what was dropped (HUD line or a
   `DebugLog` category) — never silently truncate. This is the honest answer to scarce marks in big pulls.
6. **Emit intents.** Return the assignment list; the shell applies each via
   `ApplyMarkIntent → Ledger.Assign → Driver_ApplyMark`. Nothing in the pass calls `SetRaidTarget`.

### Scaling 5-man ↔ 40-man

No modes. Slot count drives CC breadth (1–2 in a 5-man, several in a raid); the ladder + overflow handle
mark scarcity. The same `DecidePull` runs for both.

## Files & functions to touch

- New `TankMark:DecidePull(candidates, board)` — in `Core/TankMark_Processor.lua` (next to `DecideMark`)
  or a small new `Core/TankMark_Pull.lua` added to `TankMark.toc` after the Processor.
- `Core/TankMark_Scanner.lua` — DECISION phase calls `DecidePull` and applies the returned intents
  instead of looping `ProcessUnit` for the marking decision (keep the per-candidate sanity/ownership half).
- `Core/TankMark_Assignment.lua` — add `GetCCRoster(zone)` (mirror `GetTankRoster`); a kill-order helper
  if useful; reuse `IncumbencyBlocks`, `GetBlockingMarkInfo`.
- `tests/` — new `pull_assignment_spec.lua`.
- Optionally `UI/TankMark_HUD.lua` — surface deliberate overflow.

## Schema / data changes

None new — consumes Phase 1–3 fields. The **board** gains a CC-roster port (and any needed accessor),
kept pure for testing.

## Invariants to preserve

- **Stickiness:** never reassign or move a mark already in the Ledger.
- **Stable player↔mark binding:** the engine chooses the *mob* for a slot, never the *player* for a mark.
- **Determinism:** identical pack → identical routing (stable sort keys; no `Math.random`/time).
- **Mechanism untouched:** intents only; `governor_spec`, `incumbency_spec`, `swarm_election_spec`,
  `sync_codec_spec`, `trust_spec` all stay green.
- **No silent truncation:** overflow drops are logged/surfaced.

## Test plan

- **Off-client (`tests/pull_assignment_spec.lua`):** drive `DecidePull` with a board exposing a tank
  roster + CC roster (Mage + Warlock slots) and the **Frostmane fixture packs**
  ([`DATA-MODEL.md`](DATA-MODEL.md#frostmane-fixture-packs)). Assert:
  - `{Oracle(HEALER,Humanoid), Warrior(MELEE,Humanoid)}` → Oracle CC'd by the Mage slot (or Skull if no
    CC), Warrior a tank mark.
  - `{Snowcaller(CASTER,Humanoid), Ice Elemental(Elemental)}` → Snowcaller→Mage slot,
    Ice Elemental→Warlock slot; **never** Polymorph the Elemental.
  - A large pack (`4× Cretin, Warrior`) with few free marks → highest-priority marked, lowest dropped,
    drop surfaced.
  - **Determinism:** same pack twice → identical intents.
  - **Stickiness:** feed a candidate that already holds a Ledger mark → it is not reassigned.
- **In-game (OPEN-WORLD ONLY):** pull mixed open-world packs across consecutive fights; verify the CC
  player keeps the same mark every pull, kill-order marks descend by priority, and big pulls drop the
  right trash. Deploy via `.claude/sync-to-network.sh`.

## Done when

- A whole pull gets CC on legal targets, a descending kill-order ladder, and deliberate (surfaced) overflow.
- The same CC player holds the same mark across pulls; identical packs route identically.
- Marks already applied are never reshuffled; the mechanism test suites remain green.
