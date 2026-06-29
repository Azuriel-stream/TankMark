# Phase 2 — Legal-CC routing (capability-aware CC)

> Prev: [`phase-1-metadata-surfacing.md`](phase-1-metadata-surfacing.md) · Next:
> [`phase-3-role-and-priority.md`](phase-3-role-and-priority.md) · Up:
> [`00-OVERVIEW.md`](00-OVERVIEW.md) · Schema: [`DATA-MODEL.md`](DATA-MODEL.md)

## Goal

Make CC routing respect **what CC is legal for the mob's creatureType** and **what CC the group
actually has** — instead of blindly trusting one hard-coded class per mob. Fixes the canonical bug:
*a mob tagged `class=MAGE` is never CC'd by a Warlock-only group, even when it's legally banishable.*

## Prereqs

- Phase 1 conceptually (the `creatureType` field). At decision time you can also read
  `UnitCreatureType(guid)` live, so this phase can degrade gracefully when an entry's field is nil —
  but build on Phase 1 so authored/recorded entries carry it.

## Scope / non-goals

- **In:** promote `CC_MAP` to a shared Core authority; add `IsLegalCC`; make the CC resolution path
  prefer a legal CC slot present in the group. Still **per-mob** decisions.
- **Out:** pack-level coordination (Phase 4), the `role` field (Phase 3). Do not touch the mechanism.

## Design

### 1. Promote the capability table

`CC_MAP` is currently a UI-local (`UI/Config/Database/TankMark_Config_Mobs_Menus.lua:26–33`). Move the
canonical copy to a shared Core location (e.g. `TankMark.CCMap` defined near
`Core/TankMark_Assignment.lua`) and have the editor menus read the shared one (delete the duplicate).
Add the predicate from [`DATA-MODEL.md §3`](DATA-MODEL.md#3-cc-capability-table-the-legal-cc-authority):

```lua
function TankMark:IsLegalCC(class, creatureType) ... end   -- class ∈ CCMap[creatureType]
```

Reconcile the two known gaps called out in the data model: **add Shaman/Hex** (Troll-gated, matches
`IsPlayerCCClass` `Assignment.lua:95–104`) and **decide on Priest/Humanoid**. Make these changes
deliberately and note them in the entry's commit.

### 2. Make CC resolution legality-aware

Today `ResolveCC` (in `Core/TankMark_Processor.lua`) calls `board.findCCPlayer(mob.class)` →
`FindCCPlayerForClass` (`Assignment.lua:161–195`), which returns the mark of the **one** authored class
if that player is present/alive/free. Generalize to a legality match:

- Resolve the mob's `creatureType` (entry field, else live `UnitCreatureType(guid)`).
- Build the set of **legal** classes = `CCMap[creatureType]`.
- Among the profile's CC slots (players whose class ∈ legal set, present, alive, mark free/enabled),
  pick a slot deterministically. Prefer the authored `mob.class` **iff** it is legal and available;
  otherwise fall to any legal available CC slot.
- Return that slot's mark, exactly as `FindCCPlayerForClass` does today (player↔mark stays stable).

Keep the existing fall-through: if no legal CC slot is available, the mob proceeds down the normal
primary-mark / kill path (unchanged). CC marks continue to bypass the skull governor as they do now.

### 3. Keep the board seam pure

Add the legality logic behind the existing `board.findCCPlayer` port so `DecideMark` stays pure and the
off-client harness can drive it (the board already injects `findCCPlayer` — see
`tests/governor_spec.lua` / `make_board`).

## Files & functions to touch

- New shared `TankMark.CCMap` + `TankMark:IsLegalCC` (Core; e.g. top of `TankMark_Assignment.lua`).
- `UI/Config/Database/TankMark_Config_Mobs_Menus.lua` — read the shared table; remove the local `CC_MAP`.
- `Core/TankMark_Assignment.lua` — generalize `FindCCPlayerForClass` (`:161–195`) into a legality-aware
  resolver (or add a sibling it delegates to).
- `Core/TankMark_Processor.lua` — `ResolveCC` passes the mob's creatureType through.
- `tests/support` — extend `make_board` so `findCCPlayer` can model multiple CC slots + legality, if needed.

## Schema / data changes

None beyond Phase 1. (`mob.class` remains a *preference/hint*; legality now gates it.)

## Invariants to preserve

- **Stable player↔mark binding** — never reassign a player's mark; only choose which slot a mob routes to.
- **No illegal CC** — never route a mob to a class not in `CCMap[creatureType]`.
- CC still bypasses the skull governor; non-CC paths unchanged. Mechanism suites stay green.

## Test plan

- **Off-client (`tests/`):** new cases on the CC path —
  - MAGE-tagged **Humanoid** with a Mage slot present → Mage's mark (legal, authored).
  - MAGE-tagged **Elemental** with only a Warlock slot present → **Warlock's** mark (authored class
    illegal → legal fallback). Assert it does **not** route to the Mage.
  - CC-tagged mob with **no legal slot** present → falls through to the normal mark path.
  - `IsLegalCC` truth table over the promoted `CCMap` (incl. the Shaman/Priest reconciliation).
- **In-game (OPEN-WORLD ONLY):** with a profile that has a Mage and a Warlock CC slot, pull a humanoid
  caster (routes to Mage) and an elemental (routes to Warlock) in an open-world zone; confirm the marks
  land on the legal CC class each time.

## Done when

- CC mobs route to a **legal** CC class that is actually present in the group.
- A mistagged authored class falls through to a legal alternative instead of failing to CC.
- No illegal CC assignments occur; per-mob behavior otherwise unchanged; all suites green.
