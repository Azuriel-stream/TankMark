# Shared Data Model

> Read [`00-OVERVIEW.md`](00-OVERVIEW.md) first. Every phase doc references this file for schema,
> the CC capability table, the control-slot model and the priority derivation. Change a shared
> definition **here**, then update the phases that depend on it.

## 1. Current schema (baseline — what exists today)

### Mob entry — `TankMarkDB.Zones[zone][mobName]`

```lua
-- Core/TankMark_Defaults.lua:6 documents the format; entries look like:
["Flamewaker Healer"] = { prio = 1, marks = {4}, type = "KILL", class = nil }
["Lucifron"]          = { prio = 5, marks = {8}, type = "KILL", class = nil }
["Garr"]              = { prio = 9, marks = {0}, type = "KILL", class = nil }  -- IGNORE
```

| Field | Type | Meaning |
|---|---|---|
| `prio` | int 1–9 | kill priority, **lower = higher**. 9 + `marks={0}` = never mark. |
| `marks` | int[] | icon IDs to apply. `>1` element = sequential (Batch owns the cursor). `{0}` = ignore. |
| `type` | `"KILL"` \| `"CC"` | strategy type. |
| `class` | string \| nil | for `type="CC"`: the class expected to CC it (e.g. `"MAGE"`). |

Keyed by **display name** (`UnitName`), case-sensitive, per zone. Merge: user `TankMarkDB.Zones`
over shipped `TankMarkDefaults` (user wins; defaults fill gaps) → `TankMark.activeDB`.

### Profile entry — `TankMarkProfileDB[zone][i]`

```lua
{ mark = 8, tank = "TankName", healers = "H1 H2", role = "TANK" }   -- role: "TANK" | "CC"
```

`role` here is the **player's** role, already auto-inferred from class by `InferRoleFromClass`
(`Core/TankMark_Assignment.lua:112–125`) and lazily backfilled by `MigrateProfileRoles` (`:129–137`).

## 2. Schema evolution (what this redesign adds)

Three new **mob-entry** fields. All nullable; absence means "unknown" and changes nothing until the
phase that consumes them ships.

| New field | Tier | Source | Added in | Values |
|---|---|---|---|---|
| `creatureType` | A | `UnitCreatureType(guid)` (live, free) | Phase 1 | `"Humanoid"`, `"Beast"`, `"Elemental"`, `"Undead"`, `"Demon"`, `"Dragonkin"`, `"Giant"`, `"Mechanical"`, … (Blizzard strings, **not** localized away — match exactly) |
| `tier` | A | `UnitClassification(guid)` (live, free) | Phase 1 | `"normal"`, `"elite"`, `"rare"`, `"rareelite"`, `"worldboss"` |
| `role` | B | human dropdown (Phase 3); cast-learned (Phase 5) | Phase 3 | `"HEALER"`, `"CASTER"`, `"MELEE"` (extensible: `"RUNNER"` later) |

### Forward-compatible migration (follow the proven precedent)

Do **not** rewrite the whole DB. Mirror `MigrateProfileRoles`: add fields lazily where missing, leave
old entries valid. Concretely:
- Validation/merge in `Data/TankMark_Data.lua` must tolerate entries lacking the new fields (treat as nil).
- Phase 1's recorder stamps A-fields on first sighting; an optional lazy stamp can backfill A-fields for
  an already-known mob the scanner sees that is missing them.
- Readers must default: `mob.role` nil → treat as `MELEE` for priority purposes; `mob.creatureType` nil
  → fall back to a live `UnitCreatureType(guid)` read at decision time.

### Naming the mob `role` field

The profile entry already has `role` (`"TANK"`/`"CC"`). The new field is on a **different table**
(`TankMarkDB.Zones[...]` vs `TankMarkProfileDB[...]`), so there is **no real collision**. Keep the name
`role` on the mob entry (matches the Frostmane vocabulary) but **always qualify in code comments**:
"mob `role` (HEALER/CASTER/MELEE)" vs "profile `role` (TANK/CC)". If a future reader finds this
ambiguous, the rename target is `mobRole` — but the two-table separation makes that optional.

## 3. CC capability table (the legal-CC authority)

This already exists as a UI-local — **promote it**, don't reinvent it.

```lua
-- CURRENT: UI/Config/Database/TankMark_Config_Mobs_Menus.lua:26–33 (local CC_MAP)
local CC_MAP = {
    ["Humanoid"]  = { "MAGE", "ROGUE", "WARLOCK", "PRIEST" },
    ["Beast"]     = { "MAGE", "DRUID", "HUNTER" },
    ["Elemental"] = { "WARLOCK" },
    ["Demon"]     = { "WARLOCK" },
    ["Undead"]    = { "PRIEST" },
    ["Dragonkin"] = { "DRUID" },
}
```

**Phase 2** moves this to a shared Core constant (e.g. `TankMark.CCMap` near
`Core/TankMark_Assignment.lua`) so both the editor menus *and* the runtime decision layer read one
source. Define the predicate:

```lua
-- legal iff the class appears under the mob's creatureType
function TankMark:IsLegalCC(class, creatureType)
    local list = TankMark.CCMap[creatureType]
    if not list then return false end
    for _, c in L._ipairs(list) do if c == class then return true end end
    return false
end
```

**Known correctness gaps to review when promoting** (cite, don't silently "fix"):
- **Shaman/Hex is missing** — `IsPlayerCCClass` (`Assignment.lua:95–104`) accepts Troll Shaman (Hex,
  which works on Humanoid/Beast), but `CC_MAP` lists no Shaman. Phase 2 should reconcile the two lists.
- **Priest under Humanoid is loose** — Priest has no reliable single-target humanoid CC in 1.12
  (Shackle is Undead-only; Psychic Scream is AoE fear). Decide deliberately whether to keep it.
- The two ability semantics behind one class entry (Mage = Polymorph; Rogue = Sap, out-of-combat only;
  Warlock on Humanoid = Fear/Seduce) are fine to leave implicit for now — the table is class-granular.

## 4. Control-slot model (consistency mechanism)

A **control slot** is a profile CC entry viewed as `(mark, player, derived-capability)`:

```
slot = {
    mark     = 6,                 -- STABLE, human-set (player owns Square forever)
    player   = "MageA",           -- STABLE, human-set
    class    = "MAGE",            -- derived from player's class (UnitClass)
    legalSet = CCMap-inverse("MAGE") = { Humanoid, Beast }   -- derived from the capability table
}
```

- Player↔mark binding is **human-set and never churned by the engine** (see the consistency rule in
  [`00-OVERVIEW.md`](00-OVERVIEW.md#the-non-negotiable-consistency-over-cleverness)).
- Build the CC slot list with a **mirror of `GetTankRoster`** (`Assignment.lua:142–158`) — add
  `GetCCRoster(zone)` in Phase 4 returning `role=="CC"` entries with their derived `class`/`legalSet`.
- Per-pull, the engine chooses *which mob* fills each slot (Phase 4), deterministically.

## 5. Kill-order priority derivation (role × tier → default `prio`)

Extends the existing `ApplySmartDefaults` / `CLASS_DEFAULTS` mechanism
(`UI/Config/Database/TankMark_Config_Mobs_Logic.lua:35–45`, which already maps a CC class → `{icon, prio}`).
Phase 3 adds a role×tier → default-prio table. **The human `prio` field always overrides** the derived value.

Suggested starting curve (tune in Phase 3 against real pulls — these are defaults, not law):

| `role` \ `tier` | normal | elite | rare/rareelite | worldboss/boss |
|---|---|---|---|---|
| HEALER | 2 | 1 | 1 | 1 |
| CASTER | 3 | 2 | 2 | 1 |
| MELEE  | 5 | 4 | 3 | 1 |
| *(nil → MELEE)* | 5 | 4 | 3 | 1 |

Rationale: healers and dangerous casters die first; bosses are always top; plain trash is background.
This only sets a **default** the human accepts or edits; it never silently overrides authored `prio`.

## 6. The intent contract (unchanged — the mechanism boundary)

Every decision — per-mob (`DecideMark`) and pull-level (`DecidePull`, Phase 4) — returns
`{ icon = <1-8 or nil>, reason = "<string>", ... }` and applies **nothing**. Application is the sole job
of `ApplyMarkIntent` → `RegisterMarkUsage` (`Ledger.Assign`) → `Driver_ApplyMark` (`SetRaidTarget`).
The decision layer is pure and board-injected, so all of it is unit-testable off-client.

## Frostmane fixture packs

Use these as off-client harness fixtures (from the user's example dungeon; for **fixtures only** — do
not test in-instance). Each mob: `name → {creatureType, tier, role}`.

```
Frostmane Oracle     -> { Humanoid,  elite,  HEALER }
Frostmane Snowcaller -> { Humanoid,  elite,  CASTER }
Frostmane Pathfinder -> { Humanoid,  elite,  CASTER }
Frostmane Warrior    -> { Humanoid,  elite,  MELEE  }
Frostmane Cretin     -> { Humanoid,  normal, MELEE  }
Frostmane Ritualist  -> { Humanoid,  normal, MELEE  }
Frostmane Slave      -> { Humanoid,  normal, MELEE  }
Frostmane Leopard    -> { Beast,     elite,  MELEE  }
Ice Elemental        -> { Elemental, elite,  MELEE  }
Kan'za the Seer      -> { Humanoid,  worldboss, CASTER }
Hailar the Frigid    -> { Elemental, worldboss, CASTER }   -- in-game name is "Hailar" (recorder-captured), not "Hallar"
```

Representative pack assertions (roster = 1 Mage + 1 Warlock, marks plentiful):

- `{Oracle(HEALER,Humanoid), Warrior(MELEE,Humanoid)}` → Oracle is the priority target: Skull or the
  Mage's Polymorph slot (legal on Humanoid); Warrior gets a tank mark.
- `{Snowcaller(CASTER,Humanoid), Ice Elemental(MELEE,Elemental)}` → Snowcaller → Mage Polymorph slot;
  Ice Elemental → Warlock Banish slot (Polymorph is **not** legal on Elemental → must not route to Mage).
- Same pack fed twice → identical slot routing (determinism); a mark already held is never reshuffled
  (stickiness).
