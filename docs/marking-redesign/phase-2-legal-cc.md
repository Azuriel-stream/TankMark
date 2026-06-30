# Phase 2 — Legal-CC routing (capability-aware CC)

> Prev: [`phase-1-metadata-surfacing.md`](phase-1-metadata-surfacing.md) · Next:
> [`phase-3-role-and-priority.md`](phase-3-role-and-priority.md) · Up:
> [`00-OVERVIEW.md`](00-OVERVIEW.md) · Schema: [`DATA-MODEL.md`](DATA-MODEL.md)

## Status

**Design grill-hardened and ratified 2026-06-30** (grill-me session). The original design
below was sharpened on ten decision points; the resolved decision tree is recorded in
[§ Resolved decisions](#resolved-decisions-ratified-2026-06-30) and is the build spec. Not yet
built. Verify off-client in `tests/` + open-world only.

## Goal

Make CC routing respect **what CC is legal for the mob's creatureType** and **what CC the group
actually has** — instead of blindly trusting one hard-coded class per mob. Fixes the canonical bug:
*a mob tagged `class=MAGE` is never CC'd by a Warlock-only group, even when it's legally banishable.*

## Prereqs

- Phase 1 (the `creatureType` field on mob entries). At decision time we **re-read
  `UnitCreatureType(guid)` live** (Phase-1 philosophy: stored A-fields are a cache, the decision
  layer always re-reads live), with the stored field as fallback for the off-client harness.

## Scope / non-goals

- **In:** promote `CC_MAP` to a shared Core authority; add `IsLegalCC` + `CCRaceEligible`; make the
  CC resolution path a pure, legality-aware, role-gated two-pass selector. Still **per-mob** decisions.
- **Out:** pack-level coordination (Phase 4), the mob `role` field (Phase 3). **Do not touch the
  mechanism** — `GetFreeTankIcon`, the Ledger, the governor, the apply edge all stay as-is.

---

## Resolved decisions (ratified 2026-06-30)

The decision tree, in dependency order. Each line is a frozen choice; the rationale is the grill.

1. **The CC gate is two composing predicates** — *creature-legality* (`class ∈ CCMap[creatureType]`)
   × *player-capability* (a **narrow race gate**). `CCMap` stays **race-free**; it structurally can't
   express "Troll-only Hex", so that nuance lives in the capability axis.

2. **Routing is role-gated.** An eligible CC target requires `entry.role == "CC"` (the human's
   explicit CC-slot designation via the HUD/profile checkbox). Honors the *stable slots, computed
   routing* invariant; fixes the latent bug where a tank-role Mage could be conscripted for CC.
   **No legacy break:** `MigrateProfileRoles`/`InferRoleFromClass` already auto-tag
   Mage/Warlock/Hunter/Priest/Troll-Shaman as `role=="CC"`, and the target button auto-checks the box.

3. **`CCMap` keeps Druid & Rogue; auto-role inference stays conservative.** They are *legally* capable
   (Hibernate on Beast/Dragonkin; Sap on Humanoid) so a **human-checked** Druid/Rogue CC slot is
   honored — but `InferRoleFromClass` does **not** auto-tag them CC (a Druid is usually a healer/tank,
   a Rogue usually melee DPS). The checkbox bridges the two. *(Sap is out-of-combat-only, but the addon
   assigns the mark, not the cast — situational-cast timing is the player's problem.)*

4. **Shaman/Hex → `CCMap["Humanoid"]` + `CCMap["Beast"]`** (Turtle WoW Hex targets). The **Troll-only**
   constraint is enforced by the capability axis (`CCRaceEligible`), **not** `CCMap`.

5. **Remove `PRIEST` from `CCMap["Humanoid"]`; keep `PRIEST` in `CCMap["Undead"]`** (Shackle). A Priest
   has no reliable parkable single-target *humanoid* CC in 1.12 — keeping it would create a **phantom
   CC** (mark assigned, tank trusts it, Priest can't actually hold it). Safer to fall through to the
   normal mark/kill path.

   **Reconciled `CCMap` (the single Core authority):**
   ```lua
   TankMark.CCMap = {
       ["Humanoid"]  = { "MAGE", "ROGUE", "WARLOCK", "SHAMAN" },  -- −PRIEST, +SHAMAN
       ["Beast"]     = { "MAGE", "DRUID", "HUNTER", "SHAMAN" },   -- +SHAMAN
       ["Elemental"] = { "WARLOCK" },
       ["Demon"]     = { "WARLOCK" },
       ["Undead"]    = { "PRIEST" },
       ["Dragonkin"] = { "DRUID" },
   }
   ```

6. **Two-pass resolver, tie-break = profile (list) order.**
   - **Pass 1 (authored preference):** if `mob.class` is legal for the creatureType *and* a `role=="CC"`
     slot of that class is eligible → return its mark. *(The mistag fix: a MAGE-tagged Elemental skips
     pass 1 — Mage isn't legal for Elemental.)*
   - **Pass 2 (legal fallback):** otherwise return the first eligible `role=="CC"` slot whose class is
     legal, in **profile order** (the human reorders rows to express preference).
   - **Fall-through:** none → `nil` → mob proceeds down the normal mark/kill path (unchanged).

7. **creatureType resolution = live-first, stored-fallback, authored-class-degrade, no write-back.**
   1. Live `UnitCreatureType(guid)` (behind a board port) — authoritative, free, current.
   2. `mobData.creatureType` (Phase-1 cache) — fallback; the source the harness uses.
   3. Neither (rare): **degrade to authored-class-only** routing (find a `role=="CC"` slot whose class
      == `mob.class`, eligible) and debug-log it. **Never** write the live value back into `mobData`
      (respects the Phase-1 lazy-backfill cut).

8. **Capability axis = a narrow `CCRaceEligible`, NOT `IsPlayerCCClass`.** `IsPlayerCCClass` returns
   `false` for Druid/Rogue — using it as the capability check would cancel out the very classes Q3
   kept. The only sub-class CC constraint in Turtle 1.12 is Troll-Hex, so:
   ```lua
   function TankMark:CCRaceEligible(class, race)   -- pure
       return class ~= "SHAMAN" or race == "Troll"
   end
   ```
   `IsPlayerCCClass` / `InferRoleFromClass` are **left untouched** — they keep their separate job
   (conservative role auto-inference). The two predicates answer different questions; do not conflate.

9. **Split the seam — the routing is PURE (Option B).** Not "behind one port." Two thin data-returning
   ports do the live reads; the decision runs in a pure, harness-testable function:
   - `board.creatureType(guid)` → live `UnitCreatureType` (nil in tests → stored fallback).
   - `board.getCCSlots()` → enumerate `role=="CC"` profile entries as **plain records**.
   - pure `SelectCCSlot(authoredClass, creatureType, slots)` runs the two-pass legality/race/role/avail
     selection over that data and returns a mark or nil.
   - `board.findCCPlayer` is **removed** (only the board used it).

   This is what makes the test plan real — "MAGE-tagged Elemental → Warlock, not Mage" becomes a pure
   unit test, not a mock that re-implements routing. Liveness holds: `getCCSlots()` is called fresh
   inside each `DecideMark`, so slot freeness reflects the Ledger at that decision point.

10. **`type=="CC"` with no authored class routes on creatureType alone.** `nil` class + **known**
    creatureType → run **pass 2 only** (first legal slot). `nil` class + **nil** creatureType → `nil`.
    Strictly increases capability; CC no longer *needs* a per-mob class hint.

11. **Disabled marks are excluded from CC routing — unconditionally.** A mark turned off in the HUD
    (`disabledMarks[icon]`, keyed by icon; the stable binding makes it a per-slot disable) must not be
    used for CC *or* tank. **Already true today** (`FindCCPlayerForClass:183`, `GetFreeTankIcon:38`);
    Phase 2 preserves it as an **explicit, testable gate**: each slot record carries `used` + `disabled`
    and `SelectCCSlot` skips them in **both** passes. No FORCE override for a disabled CC slot (matches
    today — `FindCCPlayerForClass` takes no `mode`). Tank path is out of scope and already honors it.

---

## Build spec

### The pure selector (`Core/TankMark_Assignment.lua`)

```lua
TankMark.CCMap = { ... }                                  -- reconciled table (decision 5)

function TankMark:IsLegalCC(class, creatureType)          -- pure: class ∈ CCMap[creatureType]
    local list = TankMark.CCMap[creatureType]
    if not list then return false end
    for _, c in L._ipairs(list) do if c == class then return true end end
    return false
end

function TankMark:CCRaceEligible(class, race)             -- pure: narrow race gate (decision 8)
    return class ~= "SHAMAN" or race == "Troll"
end

-- pure two-pass selector over slot data (decisions 6, 7-degrade, 8, 10, 11)
-- slot = { mark, class, race, alive, used, disabled }  (class = UPPER English token)
function TankMark:SelectCCSlot(authoredClass, creatureType, slots)
    local function eligible(s)
        return s.alive and not s.used and not s.disabled
           and TankMark:CCRaceEligible(s.class, s.race)
    end
    if creatureType and TankMark.CCMap[creatureType] then
        -- pass 1: authored preference, iff legal
        if authoredClass and TankMark:IsLegalCC(authoredClass, creatureType) then
            for _, s in L._ipairs(slots) do
                if s.class == authoredClass and eligible(s) then return s.mark end
            end
        end
        -- pass 2: first legal slot in profile order
        for _, s in L._ipairs(slots) do
            if eligible(s) and TankMark:IsLegalCC(s.class, creatureType) then return s.mark end
        end
        return nil
    end
    -- degrade: creatureType unknown -> authored-class-only (decision 7.3)
    if authoredClass then
        for _, s in L._ipairs(slots) do
            if s.class == authoredClass and eligible(s) then return s.mark end
        end
    end
    return nil
end
```

### The live enumerator (`Core/TankMark_Assignment.lua`)

```lua
-- live: snapshot the role=="CC" profile slots as pure data for SelectCCSlot.
function TankMark:GetCCSlots()
    local zone = TankMark:GetCachedZone()
    TankMark:MigrateProfileRoles(zone)        -- ensure entry.role populated (idempotent)
    local list = TankMarkProfileDB[zone]
    if not list then return {} end
    local slots = {}
    for _, e in L._ipairs(list) do
        if e.role == "CC" and e.tank and e.tank ~= "" then
            local unit = TankMark:FindUnitByName(e.tank)
            if unit then
                local _, classEng = L._UnitClass(unit)
                L._tinsert(slots, {
                    mark     = e.mark,
                    class    = classEng,                              -- UPPER token
                    race     = L._UnitRace(unit),
                    alive    = not L._UnitIsDeadOrGhost(unit),
                    used     = TankMark.Ledger.IsUsed(e.mark),
                    disabled = TankMark.disabledMarks[e.mark] and true or false,
                })
            end
        end
    end
    return slots
end
```
> `FindCCPlayerForClass` is **removed** — its single-class match + availability logic is absorbed
> here + in `SelectCCSlot`. (`UnitRace` must be a `TankMark.Locals` entry — add `L._UnitRace` if not
> already present.)

### The board + decide layer (`Core/TankMark_Processor.lua`)

```lua
-- LiveBoard: drop findCCPlayer; add two read ports.
creatureType = function(guid) return L._UnitCreatureType(guid) end,
getCCSlots   = function()     return TankMark:GetCCSlots() end,

-- ResolveCC: new signature (+guid), live-first CT, drop the nil-class bail (decision 10).
function TankMark:ResolveCC(mobData, guid, board)
    if mobData.type ~= "CC" then return nil end
    local ct = board.creatureType(guid) or mobData.creatureType      -- live-first, stored-fallback
    return TankMark:SelectCCSlot(mobData.class, ct, board.getCCSlots())
end
```
> Call site in `DecideKnownMark` becomes `TankMark:ResolveCC(mobData, guid, board)` (`guid` is in
> scope). Everything downstream (CC bypasses the governor; `ApplyMarkIntent`) is unchanged.

### Editor menus (`UI/Config/Database/TankMark_Config_Mobs_Menus.lua`)

- Delete the local `CC_MAP` (`:26-33`); read `TankMark.CCMap` at `:100-104` and `:156-160`. The CC
  suggestions in the editor now match runtime legality (Shaman in, Priest-Humanoid out) — single source
  of truth. Leave `CLASS_DEFAULTS`/`ALL_CLASSES` local (UI-only).

## Invariants to preserve

- **Stable player↔mark binding** — never reassign a player's mark; only choose which slot a mob routes to.
- **No illegal CC** — never route a mob to a class ∉ `CCMap[creatureType]`.
- **Disabled/used marks excluded** from CC routing, unconditionally (decision 11); tank path unchanged.
- **CC bypasses the skull governor**; non-CC paths unchanged.
- **`DecideMark` stays pure** — no new globals; every live read is behind a board port.
- Mechanism suites stay green.

## Versioning fold-in

- Tag all Phase-2 code `[v0.30]` (the current `.toc` dev version, mirroring the swarm's
  write-under-N / release-at-N+1 cadence — see [[version-tag-policy]]).
- **Fold in the owed Phase-1 retag** `[v0.29] → [v0.30]` (the Phase-1 marking code was mistakenly
  stamped with the swarm dev-cycle tag, e.g. `Processor.lua:424`). Small, mechanical, marking-files only.
- **No `.toc` bump for Phase 2** — defer the release bump (→ `0.31`) to a marking-redesign milestone,
  as the swarm bumped once at completion.

## Test plan

- **Off-client (`tests/`)** — new `legal_cc_spec.lua` (all pure):
  - `IsLegalCC` truth table over the reconciled `CCMap` (incl. Shaman in Humanoid/Beast, Priest only in
    Undead, Druid/Rogue present).
  - `CCRaceEligible` truth table: non-Troll Shaman → false; Troll Shaman → true; every other class → true.
  - `SelectCCSlot` cases:
    - MAGE-tagged **Humanoid**, Mage slot present → Mage's mark (legal + authored).
    - MAGE-tagged **Elemental**, only Warlock slot present → **Warlock's** mark; assert **not** Mage.
    - CC-tagged mob, **no legal slot** present → nil (falls through).
    - **Disabled** Mage slot on a Humanoid → skips Mage → next legal slot (or nil). *(decision 11)*
    - **No authored class** + known creatureType → first legal slot. *(decision 10)*
    - **Unknown creatureType** (degrade) → authored-class-only; no class + no CT → nil. *(decision 7)*
    - Non-Troll Shaman CC slot on a Humanoid → excluded (race gate).
  - **Migrate** the 3 existing CC tests (`governor_spec.lua:67-73`, `make_board{cc=...}`) to the new
    `creatureType` + `getCCSlots` board shape; update `tests/support/board.lua` (`make_board`): drop
    `cc`/`findCCPlayer`, add `creatureType` (→ `o.creatureType`) and `getCCSlots` (→ `o.ccSlots or {}`).
- **In-game (OPEN-WORLD ONLY):** profile with a Mage and a Warlock CC slot — pull a humanoid caster
  (→ Mage) and an elemental (→ Warlock); then **disable the Mage's mark** in the HUD and pull a humanoid
  again (→ skips Mage). Confirm marks land on the legal CC class each time.

## Done when

- CC mobs route to a **legal** CC class actually present in the group.
- A mistagged authored class falls through to a legal alternative instead of failing to CC.
- A `type=="CC"` mob with no authored class but a known creatureType still CCs.
- Disabled marks are never used for CC (or tank).
- No illegal CC assignments; per-mob behavior otherwise unchanged; all suites green.
- Phase-1 `[v0.29]` marking tags retagged to `[v0.30]`.
