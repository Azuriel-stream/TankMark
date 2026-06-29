# Intelligent Marking Redesign — Overview

> Status: **design / not yet built.** This folder is a set of build specs for future
> development sessions. No addon code has been written for it yet.
> Read this file first, then [`DATA-MODEL.md`](DATA-MODEL.md), then the phase you are building.

## Why this exists

TankMark today is two unevenly-developed layers:

- **Mechanism (mature — do not touch):** the Ledger (mark ownership), the skull governor /
  incumbency rules, server-side theft detection, the swarm queen election, sync, death cleanup,
  pull-end clear. This is solid defensive engineering. It answers: *"given a marking decision, apply
  it and keep it alive across ticks, deaths, theft and multiple markers without collisions."*
- **Policy (thin — the target of this work):** the actual *strategy* ("what should this mob be
  marked as") collapses to per-mob hand-typed data — `prio`, `marks[1]`, `type=CC + class` — plus a
  per-zone Team Profile mapping each icon to a named player. The engine does not *reason*; it looks
  up authored data and resolves conflicts.

### The five gaps in the policy layer

1. **No semantic model of a mob.** Nothing in the marking decision knows a mob is a *healer*, a
   *caster*, a *beast*, an *elemental* — even though the client can tell us most of this for free.
2. **No pack / pull awareness.** Every mob is decided in isolation, greedily, sorted by `(prio, hp)`.
   A pull of `{Oracle-healer, Warrior, 2× Cretin}` is four independent lookups, never one plan.
3. **CC is statically pinned to one class per mob.** A mob tagged `class=MAGE` is never CC'd by a
   Warlock-only group, even when the mob is legally banishable.
4. **Only Skull is priority-defended.** Cross / Square / … are handed out as "next free icon"; the
   kill-order ladder below Skull is emergent, never re-asserted.
5. **No interrupt concept.** Casters can only be killed or CC'd. *(Deferred — see Phase 5 / out of scope.)*

This redesign addresses gaps **1–4**. Gap 5 (interrupts) and a few extensions are explicitly deferred.

## What's actually feasible (verified against the code)

The cheap insight: the most expensive-sounding pillar is **half-built already** — the client reads
creature data live and the codebase throws it away.

| Mob attribute | How we get it | Authoring? |
|---|---|---|
| `creatureType` (Humanoid/Beast/Elemental/Undead/Demon/Dragonkin…) → **legal CC** | `UnitCreatureType(guid)` — **already cached in Locals & called live** at `Core/TankMark_Processor.lua:67` and `:415` | **Free** |
| `tier` (normal/elite/rare/rareelite/worldboss) → danger / whether-to-mark | `UnitClassification(guid)` — **already called live** at `Core/TankMark_Processor.lua:72–74` and `Core/TankMark_Batch.lua:230` | **Free** |
| `role` (HEALER/CASTER/MELEE/…) → kill priority, CC-vs-interrupt | not directly readable; `UNIT_CASTEVENT` not registered today | **Human-tag now; cast-learn later (Phase 5)** |
| `prio` / `marks` / CC slot (strategy intent) | — | **Human-framed**, with smart derived defaults |

## Existing assets we build on (not green-field)

The redesign mostly **promotes intelligence the editor already has into the runtime decision layer**
and adds **one** new mob field. Inventory:

- **Live creature reads:** `UnitCreatureType(guid)` / `UnitClassification(guid)` already called every
  scan (`Processor.lua:67`, `:72–74`), used today only as throwaway filters (skip critters / `MarkNormals`).
- **A creatureType → CC-class table already exists:** `CC_MAP` in
  `UI/Config/Database/TankMark_Config_Mobs_Menus.lua:26–33` (currently a UI-local). This *is* the
  legal-CC table — Phase 2 promotes it to a shared Core constant.
- **Smart defaults already exist:** `ApplySmartDefaults` / `CLASS_DEFAULTS` in
  `UI/Config/Database/TankMark_Config_Mobs_Logic.lua:35–45` already derive icon + prio from a CC class.
  Phase 3 extends this with role × tier.
- **A proven forward-compatible field-migration pattern:** the *profile* already gained a `role` field
  via `InferRoleFromClass` + the lazy `MigrateProfileRoles` (`Core/TankMark_Assignment.lua:109–137`).
  The mob schema follows the same shape. *(Note: that `role` is the **player's** TANK/CC role — distinct
  from the **mob's** HEALER/CASTER role added here. See [`DATA-MODEL.md`](DATA-MODEL.md#naming-the-mob-role-field).)*
- **Role-filtered roster builder:** `GetTankRoster` (`Assignment.lua:142–158`) already returns the
  TANK-role profile entries; Phase 4 adds the CC-roster mirror.
- **CC class → mark resolver:** `FindCCPlayerForClass` (`Assignment.lua:161–195`) already maps a mob's
  required CC class to that class's profile mark.
- **A pure, board-injected decision layer + off-client harness:** `DecideMark` takes a `board` of
  closures; `tests/decide_mark_spec.lua` etc. drive it with `make_board{}` mocks under Lua 5.1.
  Phase 4's pull pass plugs into the same seam and is testable the same way.
- **A single-sourced incumbency operator:** `IncumbencyBlocks` (`Assignment.lua:229–231`) — reused for
  the kill-order ladder so the `>=` rule can't drift.

## Design philosophy

Three knowledge tiers, each with a clear owner (full schema in [`DATA-MODEL.md`](DATA-MODEL.md)):

- **Tier A — what a mob *is* (auto, free):** `creatureType`, `tier`. Read live; stamped onto the DB
  entry so it's available pre-pull too.
- **Tier B — what a mob *does* (human-tagged):** `role`. One dropdown, reusing the CC-class menu
  pattern. Optional future: learn via casts (Phase 5).
- **Tier C — strategy intent (human-framed, smart-defaulted):** `prio` / `marks` / CC stay
  human-controllable, but the recorder and editor offer derived defaults from A+B that a human accepts
  or overrides.

### The non-negotiable: consistency over cleverness

A CC player must keep the **same mark across pulls**. We achieve this with **stable slots, computed
routing**: the profile's CC entries are *control slots* `(mark, player, derived-capability)`; the
player↔mark binding is human-set and **never** churned by the engine. The **only** per-pull dynamism is
*which mob in this pull becomes the Square target* — and even that is deterministic (same
creatureType/role → same slot). The CC player's experience never changes: *"I'm on Square, I sheep the
Square."* This bounds dynamism to mob-routing, not player-reassignment, and scales by slot count from a
1-CC 5-man to a 6-CC raid with no separate mode.

### Don't touch the mechanism

Every phase emits decisions as `{icon, reason}` **intents** through the existing
`ApplyMarkIntent → Ledger → Driver_ApplyMark`. The Ledger, governor, swarm, sync and death paths are
untouched. The mechanism's test suites (`governor_spec`, `incumbency_spec`, `swarm_election_spec`, …)
must stay green.

## Phase roadmap (dependency order 1 → 2 → 3 → 4; 5 optional)

| Phase | Doc | Outcome |
|---|---|---|
| 1 | [`phase-1-metadata-surfacing.md`](phase-1-metadata-surfacing.md) | Recorder auto-stamps `creatureType` + `tier`; editor shows them. Near-zero risk; no decision change. |
| 2 | [`phase-2-legal-cc.md`](phase-2-legal-cc.md) | CC routing respects creatureType legality (promote `CC_MAP`). Fixes "Mage-tagged mob never CC'd by a Warlock group." |
| 3 | [`phase-3-role-and-priority.md`](phase-3-role-and-priority.md) | Human `role` field; default kill priority derived from role × tier (extends `ApplySmartDefaults`). |
| 4 | [`phase-4-pull-assignment.md`](phase-4-pull-assignment.md) | `DecidePull` coordinates the whole pull: stable-slot CC + full kill-order ladder + deliberate overflow. |
| 5 | [`phase-5-cast-learning.md`](phase-5-cast-learning.md) | *(Future)* infer `role` from observed casts via `UNIT_CASTEVENT`. |

Each phase is independently shippable and reload-verified. Build them in order; do not start Phase 4
until 1–3 have landed and verified in-game.

## Testing approach (applies to every phase)

- **Off-client harness (`tests/`, Lua 5.1):** the cheapest place to prove strategy. Drive the pure
  decision layer with `make_board{}` mocks and mob fixtures. Encode the **Frostmane Burrow packs**
  (see [`DATA-MODEL.md`](DATA-MODEL.md#frostmane-fixture-packs)) as cases — they exercise mixed
  composition, legal-CC routing and kill order. Run with `lua tests/run.lua` (or the repo's harness entry).
- **In-game: OPEN-WORLD ZONES ONLY.** There is **no dungeon/instance access** for testing. Validate on
  open-world mobs, which still span the creature types (humanoid/beast/elemental/undead/…). Never write
  a test step that requires entering an instance. Deploy with `.claude/sync-to-network.sh`.

## Glossary

- **Slot / control slot** — a profile CC entry `(mark, player, derived-capability)`. Player↔mark is
  fixed by a human; the engine only chooses which mob fills it this pull.
- **Tier (Tier A/B/C)** — the three knowledge tiers above. *Also* a Tier-A field name (`tier` =
  `UnitClassification`, e.g. elite/boss). Context disambiguates.
- **Legal CC** — a `(class, creatureType)` pair allowed by the capability table (`CC_MAP`), e.g.
  Polymorph is legal on Humanoid/Beast but not Elemental.
- **Kill-order ladder** — assigning Skull→Cross→Square→… as a *deliberate* descending kill order, not
  just defending Skull.
- **Intent** — the `{icon, reason, …}` value a decision returns; applied by `ApplyMarkIntent`. The
  decision layer never calls `SetRaidTarget` directly.
