# Phase 1 — Surface the metadata (Tier A auto-capture)

> Prev: — · Next: [`phase-2-legal-cc.md`](phase-2-legal-cc.md) · Up:
> [`00-OVERVIEW.md`](00-OVERVIEW.md) · Schema: [`DATA-MODEL.md`](DATA-MODEL.md)

## Goal

Auto-capture each mob's `creatureType` and `tier` into its DB entry, and show them (read-only) in the
Mob Database editor. **No marking decision changes** — this phase only enriches data.

## Prereqs

None. This is the foundation; build it first.

## Scope / non-goals

- **In:** stamp `creatureType` + `tier` on recording; tolerate the new fields everywhere; display them.
- **Out:** using the fields to drive any decision (that starts in Phase 2/3). Do not change `DecideMark`.

## Design

The recorder already has `creatureType` in hand and writes a dumb stub. Extend it.

`RecordUnit` today (`Core/TankMark_Processor.lua:411–441`) already reads `cType` at line 415 (to skip
critters) and writes:

```lua
TankMarkDB.Zones[zone][name] = { prio = 5, marks = {8}, type = "KILL", class = nil }   -- :424–429
```

Change it to also read classification and stamp both Tier-A fields:

```lua
local cType = L._UnitCreatureType(guid)            -- already present at :415
-- ... existing critter guard / name / zone lookup ...
local tier  = L._UnitClassification(guid)          -- NEW
TankMarkDB.Zones[zone][name] = {
    prio  = 5,
    marks = {8},
    type  = "KILL",
    class = nil,
    creatureType = cType,                            -- NEW
    tier = tier,                                     -- NEW
}
```

**Optional lazy backfill** (recommended, mirrors `MigrateProfileRoles`): when the scanner sees an
already-known mob whose entry lacks `creatureType`/`tier`, stamp them from the live GUID. Cheapest place
is where `ProcessUnit` already resolves the entry, guarded so it runs once per entry. Keep it behind the
existing `if TankMark.DebugEnabled` discipline for any logging.

**Editor display (read-only).** The editor already detects creature type on the "Target" button
(`UI/Config/Database/TankMark_Config_Mobs_UI.lua:384` sets `TankMark.detectedCreatureType`). Add a
read-only FontString row showing the entry's stored `creatureType` + `tier` when a mob is loaded for
edit (populate in `TankMark_Config_Mobs_List.lua`'s edit-population path). Use the FontString pattern
already used by sequential rows; no validation, display only.

## Files & functions to touch

- `Core/TankMark_Processor.lua` — `RecordUnit` (`:411–441`): add `tier` read + stamp both fields.
  Optional: lazy backfill near the entry-resolution in `ProcessUnit`.
- `Data/TankMark_Data.lua` — ensure DB init/validation/snapshot logic tolerates the two new optional
  fields (no stripping on load/merge; `RefreshActiveDB` carries them through).
- `UI/Config/Database/TankMark_Config_Mobs_List.lua` — populate the read-only display fields on edit.
- `UI/Config/Database/TankMark_Config_Mobs_UI.lua` — add the read-only FontString row.
- `TankMark.lua` — confirm `UnitClassification` is in `Locals` (it is — used at `Processor.lua:72`).
  Add `UnitCreatureFamily` **only** if you decide to capture family now (not required this phase).

## Schema / data changes

Adds nullable `creatureType` (string) and `tier` (string) to the mob entry. See
[`DATA-MODEL.md §2`](DATA-MODEL.md#2-schema-evolution-what-this-redesign-adds). Old entries without them
remain valid. Bump no SavedVariables version; the merge is additive.

## Invariants to preserve

- **No decision change.** `DecideMark`/`DecideKnownMark`/`ResolveCC` must behave identically — verify by
  re-running `tests/decide_mark_spec.lua`, `governor_spec.lua`, `incumbency_spec.lua` green.
- Match Blizzard's exact `creatureType` strings (e.g. `"Humanoid"`, capital H) so `CC_MAP` lookups in
  Phase 2 hit.
- Keep the recorder's existing critter/non-combat-pet guard (`:416`).

## Test plan

- **Off-client (`tests/`):** add a `RecordUnit`-level test (or extend an existing spec) with a mock that
  returns a creatureType + classification for a GUID; assert the written entry contains
  `creatureType`/`tier`. If `RecordUnit` is not yet board-injectable, the minimal seam is to stub the
  `L._UnitCreatureType`/`L._UnitClassification` Locals in the harness support file.
- **In-game (OPEN-WORLD ONLY):** `/tmark recorder start`, roam an open-world zone with mixed mobs
  (humanoid bandits, beasts, elementals), let it record, then `/tmark config` → Mob Database and confirm
  entries show the right creatureType + tier. Deploy via `.claude/sync-to-network.sh`.

## Done when

- New recordings carry correct `creatureType` + `tier`.
- The Mob Database editor shows both, read-only, for any loaded mob that has them.
- Marking behavior is unchanged; all existing test suites stay green.
- Old DB entries (without the fields) still load, edit and save cleanly.
