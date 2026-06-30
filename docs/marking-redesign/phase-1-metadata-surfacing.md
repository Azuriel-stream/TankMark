# Phase 1 — Surface the metadata (Tier A auto-capture)

> Prev: — · Next: [`phase-2-legal-cc.md`](phase-2-legal-cc.md) · Up:
> [`00-OVERVIEW.md`](00-OVERVIEW.md) · Schema: [`DATA-MODEL.md`](DATA-MODEL.md)

## Goal

Auto-capture each mob's `creatureType` and `tier` into its DB entry, and show them (read-only) in the
Mob Database editor. **No marking decision changes** — this phase only enriches data.

### Purpose framing (decided during build planning)

The stored A-fields are a **convenience cache, not a runtime input.** The decision layer (Phases 2–4)
always holds a live GUID and can read `UnitCreatureType`/`UnitClassification` for free at decide time
(`Processor.lua:67`, `:72–74`); per [`DATA-MODEL.md §2`](DATA-MODEL.md#2-schema-evolution-what-this-redesign-adds)
a nil stored field falls back to that live read. So the stored copy only matters when the mob is **not in
front of you** — the editor display (this phase) and pre-pull planning (future). A missing field is always
recoverable, which is why backfill is unnecessary (see below).

**No backward-compat burden:** the addon is in active development with a single user, so old DB entries
that predate these fields do not need migrating — they heal organically as mobs are re-recorded, or via a
one-time offline DB stamp. Do not build migration machinery for them.

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

**Lazy backfill — CUT.** An earlier draft proposed stamping A-fields onto already-known mobs from the
`ProcessUnit` scanner path. **Dropped during build planning:** it was the *only* part of this phase that
touched the hot scanner path, and its sole purpose was healing pre-existing entries — which the
convenience-cache framing plus the no-backward-compat decision (above) make unnecessary. Phase 1 therefore
touches **nothing** on the scanner/decision path. Old entries heal organically when re-recorded.

**Save-path preservation — REQUIRED (was missing from this doc).** The editor save is field-explicit:
`SaveFormData` (`UI/Config/Database/TankMark_Config_Mobs_Logic.lua:291–296`) builds the entry from a fixed
`{prio, marks, type, class}` literal and `PerformSave` does a **full replace**
(`TankMarkDB.Zones[zone][mob] = mobEntry`, `:248`). Without intervention, editing *any* mob in the config UI
would **silently drop** the stored `creatureType`/`tier`/`role`. So `SaveFormData` must read the existing
entry and carry those fields forward (read-modify-write). All three are read-only in the Phase 1 editor
(`role` only becomes user-editable in Phase 3), so unconditional carry-forward is correct.

**Manual add via the Target button.** The recorder is not the only way an entry is born — a user can add
a mob by hand in the editor. The **Target** button (`TankMark_Config_Mobs_UI.lua`) already reads
`UnitCreatureType("target")` into `TankMark.detectedCreatureType` (it drives the CC-class menu's legal-CC
filter). Extend it to also snapshot `UnitClassification("target")` and tag the detection with the targeted
name (`detectedForName`); then `SaveFormData` stamps `creatureType`/`tier` from those when the saved name
matches. The name-match guard prevents a stale detection from leaking onto a different mob, and a fresh
detection also backfills an old metadata-less entry the user re-targets. A hand-typed mob with no target
stays nil (heals on next sighting — convenience cache). `role` is never set here (human/Phase-3 only).

**Editor display (read-only).** The editor already detects creature type on the "Target" button
(`UI/Config/Database/TankMark_Config_Mobs_UI.lua:384` sets `TankMark.detectedCreatureType`). Add a
read-only FontString row showing the entry's stored `creatureType` + `tier` when a mob is loaded for
edit (populate in `TankMark_Config_Mobs_List.lua`'s edit-population path). Use the FontString pattern
already used by sequential rows; no validation, display only.

## Files & functions to touch

- `Core/TankMark_Processor.lua` — `RecordUnit` (`:411–441`): add `tier` read + stamp `creatureType` + `tier`
  on the new-mob write. **No `ProcessUnit` change** (backfill cut — see Design).
- `UI/Config/Database/TankMark_Config_Mobs_Logic.lua` — `SaveFormData`: carry forward
  `creatureType`/`tier`/`role` from the existing entry so an edit-save does not drop them (the required
  fix above). `ResetEditorState`: clear the display FontString.
- `UI/Config/Database/TankMark_Config_Mobs_List.lua` — `BuildListData`: pass the three fields onto the row
  view object; the row's edit-click handler populates the read-only display from them.
- `UI/Config/Database/TankMark_Config_Mobs_UI.lua` — add the read-only FontString row to the editor.
- `Data/TankMark_Data.lua` — **no change needed.** Verified already field-agnostic: `ValidateDB` checks only
  `prio`/`marks`, `CreateSnapshot` deep-copies all keys, `LoadZoneData`/`RefreshActiveDB` copy the entry by
  reference. (`MergeDefaults` is field-explicit but only reconstructs *shipped-default* mobs, which carry no
  A-fields — so it can't lose anything here.)
- `TankMark.lua` — **no change needed.** `UnitClassification` + `UnitCreatureType` are already in `Locals`
  (`:28–29`). `UnitCreatureFamily` is not captured this phase.

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
