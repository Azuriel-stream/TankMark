# Phase 3 — Mob `role` field + role-derived priority

> Prev: [`phase-2-legal-cc.md`](phase-2-legal-cc.md) · Next:
> [`phase-4-pull-assignment.md`](phase-4-pull-assignment.md) · Up:
> [`00-OVERVIEW.md`](00-OVERVIEW.md) · Schema: [`DATA-MODEL.md`](DATA-MODEL.md)

## Goal

Give a mob a **role** (`HEALER`/`CASTER`/`MELEE`) — the one piece the client can't tell us — and use
`role × tier` to derive a sensible **default kill priority**, which a human can always override. This is
what makes "healers die first" automatic instead of hand-typed per zone.

## Prereqs

- Phase 1 (`tier` field available for the derivation).
- Independent of Phase 2, but normally built after it.

## Scope / non-goals

- **In:** the human `role` dropdown; persistence; role×tier → default `prio` derivation as a new pure
  sibling of the smart-defaults mechanism.
- **Out:** cast-learning the role (Phase 5); pack coordination (Phase 4). Role does not yet change
  *which mark* — only the default *priority*. It becomes a routing input in Phase 4.

**Observable contract (the honest scope — ratified 2026-06-30).** `prio` only changes runtime behavior
in **skull (mark 8) contests**: among mobs authored to skull (the KILL default), the lowest-prio one
wins/holds it (`DecideKnownMark` aggressive-theft `Core/TankMark_Processor.lua:318-324` + the governor).
So Phase 3's *visible* win is **skull migration**: tag a pack's healer `HEALER` → it derives a low prio →
the skull migrates onto it. For a mob authored to a *non-skull* mark, or a `CC` mob (sheeped, governor-
excluded), the role-derived prio is **recorded but invisible** until Phase 4 wires role into per-mark
routing. Do not claim a visible effect beyond skull-default KILL mobs in Phase 3.

## Ratified decisions (grill 2026-06-30)

1. **Trigger = action-only, last-action-wins.** Role derivation fires *only* when the human picks a role
   from the new dropdown (mirrors how class-derivation fires only on class-menu select). It pre-fills the
   visible `editPrio`; the field is the single source of truth at save (`SaveFormData:293`). No dirty
   flag — "human override always wins" falls out for free, exactly as today.
2. **Pure function in Core.** `TankMark:RoleTierPrio(role, tier)` → number lives in
   `Core/TankMark_Assignment.lua` (home of `CCMap`/`SelectCCSlot`/`IncumbencyBlocks`), **total** (any
   input returns a number), harness-tested directly like `SelectCCSlot`. The UI `ApplyRoleDefaults(role)`
   is a thin wrapper (read tier → call `RoleTierPrio` → `editPrio:SetText`). No table logic in the UI.
   The existing class `ApplySmartDefaults` is **not** refactored (out of scope).
3. **nil-tier → `normal` column; nil-role → `MELEE` row.** `RoleTierPrio` normalizes both internally so
   it degrades gracefully and stays testable. The `nil-role` row is unreachable from the editor (you
   never *pick* nil) — it exists for totality + future Phase-4 runtime use.
4. **Authoring-time only.** Persists a concrete `prio` number; the runtime never recomputes. Mechanism
   suites stay untouched (the Phase-3 safety property).
5. **`role` becomes editable exactly like `class`** — three coordinated touch-points (reset / populate-
   on-edit / write-on-save). See §1 and the Files list. The Phase-1 preserve block **splits**:
   `creatureType`/`tier` stay carried-forward from `existing`; `role` now comes from `selectedRole`.
6. **Single role control.** The dropdown is the sole role display+editor; `role` is **removed** from the
   read-only meta line (`List.lua`) to avoid a stale double-display.
7. **Recorder leaves `role` nil** (no creatureType guess). **Shipped-defaults tagging deferred** to a
   trivial follow-up after in-game proof.

## Design

### 1. Add the `role` field + editor dropdown

Add `role` to the mob entry (see [`DATA-MODEL.md §2`](DATA-MODEL.md#2-schema-evolution-what-this-redesign-adds);
mind the naming note vs the profile's `role`). Add a "Role" dropdown to the Mob editor by **cloning the
CC-class menu pattern** — `role` becomes editable **exactly as `class` is**:

- Button + dropdown like the CC Class control (`classBtn` at `TankMark_Config_Mobs_UI.lua:459`), placed
  on the **same row as the Class button** (`y=-43`, to its right, ~`x=160`, within the editor's ~249px
  inner width). Verify exact pixels at `/reload` (watch the prio spinners + editor edge); respect the
  CLAUDE.md anchor landmarks.
- `InitRoleMenu()` mirroring `InitClassMenu` (`TankMark_Config_Mobs_Menus.lua:85–133`) with options
  `No Role` (nil), `Healer`, `Caster`, `Melee`. Selecting a (non-nil) role calls `ApplyRoleDefaults`.
- **The three `class`-parallel touch-points** (miss one → silent role loss / stale leak on edit):
  - reset on new-mob: `ResetEditorState` → `TankMark.selectedRole = nil` (beside `selectedClass = nil`).
  - populate on edit-open: `List.lua` → `TankMark.selectedRole = data.role` (beside `selectedClass`).
  - write on save: `SaveFormData` → `mobEntry.role = TankMark.selectedRole`. **Split the Phase-1
    preserve block** (`:309-313`): keep `creatureType`/`tier` carried from `existing`, but `role` now
    comes from `selectedRole` (not `existing.role`).
- **Remove `role` from the read-only meta line** (`List.lua:137`) — the dropdown is the sole role
  display+control; keep the meta line `creatureType / tier` only.

### 2. Derive default priority from role × tier

Add a **new pure sibling** — `TankMark:RoleTierPrio(role, tier)` in `Core/TankMark_Assignment.lua`
(alongside `SelectCCSlot`), holding the role×tier table from
[`DATA-MODEL.md §5`](DATA-MODEL.md#5-kill-order-priority-derivation-role--tier--default-prio). It is
**total**: normalizes nil role → `MELEE` row, nil tier → `normal` column, returns a number for any input.
The UI `ApplyRoleDefaults(role)` (`TankMark_Config_Mobs_Logic.lua`) is the thin wrapper: read the current
tier (`detectedTier`/`existing.tier`), call `RoleTierPrio`, `editPrio:SetText`. **Do not** extend or
refactor the class `ApplySmartDefaults` — it stays inline/untested (out of scope).

**Override rule (critical):** the human `prio` field always wins — and falls out for free from the trigger
model. Derivation fires *only* when the human picks a role (action-triggered, like class-derivation),
pre-fills the visible `editPrio`, and `SaveFormData:293` persists whatever text is in the field. Last menu
action wins; once the human types a number, nothing recomputes. Persist `prio` as a concrete number — the
derivation is an authoring convenience, **not** a runtime recomputation, so the decision code keeps reading
a plain `prio` and the mechanism suites stay green.

### 3. Recorder default

**Ratified:** the recorder leaves `role = nil` — **no creatureType guess** (the floated CASTER-hint is
*cut*; role is a human-only decision in Phase 3, no silent truth to later un-learn). A nil-role mob never
derives (trigger is action-only), so recordings keep their recorder-assigned `prio`; a human upgrades
healers/casters intentionally.

## Files & functions to touch

- `Core/TankMark_Assignment.lua` — **new pure `TankMark:RoleTierPrio(role, tier)`** (the role×tier table,
  total, normalizes nils). The harness-testable seam.
- `UI/Config/Database/TankMark_Config_Mobs_UI.lua` — Role button (same row as `classBtn`).
- `UI/Config/Database/TankMark_Config_Mobs_Menus.lua` — `InitRoleMenu` (calls `ApplyRoleDefaults`).
- `UI/Config/Database/TankMark_Config_Mobs_Logic.lua` — thin `ApplyRoleDefaults(role)` wrapper;
  `ResetEditorState` resets `selectedRole`; `SaveFormData` writes `mobEntry.role = selectedRole` and
  **splits** the preserve block (keep `creatureType`/`tier`, drop `role` carry-forward).
- `UI/Config/Database/TankMark_Config_Mobs_List.lua` — populate `selectedRole` on edit; **remove `role`
  from the read-only meta line**.
- `Data/TankMark_Data.lua` — schema tolerance (additive; nil-tolerant — likely no change, mirror Phase 1).
- `tests/role_prio_spec.lua` — **new**, asserts `RoleTierPrio` directly (see Test plan).
- _Deferred:_ `Data/TankMark_Defaults.lua` role-tagging of shipped healers/casters — trivial follow-up
  after in-game proof, **not** in the Phase-3 build.

## Schema / data changes

Adds nullable `role` (string `HEALER`/`CASTER`/`MELEE`) to the mob entry. Additive; old entries valid.

## Invariants to preserve

- **Human `prio` override always wins.** Derivation only pre-fills.
- No runtime decision change *yet* beyond priority values flowing from authored `prio` (which the scanner
  already sorts on). Mechanism suites stay green.
- Keep mob `role` (HEALER/CASTER/MELEE) clearly distinct from profile `role` (TANK/CC) in code comments.

## Test plan

- **Off-client (`tests/role_prio_spec.lua`):** assert `TankMark:RoleTierPrio` directly (it's pure/total) —
  `(HEALER, elite) → 1`, `(MELEE, normal) → 5`, `(CASTER, elite) → 2`; `nil role → MELEE` row;
  `nil tier → normal` column. Build test-first (red→green), like `legal_cc_spec`. The mechanism suites
  (`governor_spec`/`decide_mark_spec`/`incumbency_spec`) must stay green — Phase 3 adds no runtime path.
- **In-game (OPEN-WORLD ONLY) — the skull-migration check:** in a skull-default KILL pack, tag the healer
  `HEALER`, confirm the Role dropdown pre-fills a low `prio`, save, and confirm **the skull migrates onto
  the healer** on the pull (it steals from the melee). Also round-trip: edit an unrelated field on a roled
  mob and confirm `role` survives the save.

## Done when

- `role` is editable, persisted, populated on edit, and the read-only meta line no longer double-shows it.
- Picking a role pre-fills `prio` from `role × tier`; a human-typed override is respected and never
  clobbered (it's the same field, last-action-wins).
- `RoleTierPrio` is harness-tested green; the mechanism suites stay green.
- **The skull migrates to a role-prioritized mob** among skull-default mobs (the observable contract) —
  broader per-mark routing remains explicitly Phase 4.
