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

- **In:** the human `role` dropdown; persistence; role×tier → default `prio` derivation extending the
  existing smart-defaults mechanism.
- **Out:** cast-learning the role (Phase 5); pack coordination (Phase 4). Role does not yet change
  *which mark* — only the default *priority*. It becomes a routing input in Phase 4.

## Design

### 1. Add the `role` field + editor dropdown

Add `role` to the mob entry (see [`DATA-MODEL.md §2`](DATA-MODEL.md#2-schema-evolution-what-this-redesign-adds);
mind the naming note vs the profile's `role`). Add a "Role" dropdown to the Mob editor by **cloning the
CC-class menu pattern**:

- Button + dropdown like the CC Class control (`TankMark_Config_Mobs_UI.lua:451–463`).
- `InitRoleMenu()` mirroring `InitClassMenu` (`TankMark_Config_Mobs_Menus.lua:85–133`) with options
  `No Role` (nil), `Healer`, `Caster`, `Melee`.
- Store in `TankMark.selectedRole`; write into `mobEntry.role` in `SaveFormData`
  (`TankMark_Config_Mobs_Logic.lua`, alongside `prio`/`marks`/`type`/`class`); populate on edit in
  `TankMark_Config_Mobs_List.lua`.

### 2. Derive default priority from role × tier

Extend the existing smart-defaults path. `ApplySmartDefaults(className)` already maps a CC class →
`{icon, prio}` via `CLASS_DEFAULTS` (`TankMark_Config_Mobs_Logic.lua:35–45`). Add a role×tier → prio
lookup (table in [`DATA-MODEL.md §5`](DATA-MODEL.md#5-kill-order-priority-derivation-role--tier--default-prio))
and apply it when role/tier are known and the human has not typed an explicit `prio`.

**Override rule (critical):** the human `prio` field always wins. The derived value only *pre-fills* the
field (like `ApplySmartDefaults` does today); once a human edits `prio`, the derivation never clobbers it.
Persist `prio` as a concrete number as today — the derivation is an authoring convenience, not a runtime
recomputation, so existing decision code keeps reading a plain `prio`.

### 3. Recorder default

The recorder may set `role = nil` (unknown) or guess `MELEE`. Recommended: leave `nil` and let the
derivation treat nil as `MELEE` (per the data-model default), so recordings stay conservative and a human
upgrades healers/casters intentionally. Optionally pre-fill `CASTER` when `tier` is set and the editor's
detected creatureType is a typically-casting type — but keep it a *suggestion*, never silent truth.

## Files & functions to touch

- `Data/TankMark_Defaults.lua` — optionally tag known healers/casters with `role` (e.g. `Flamewaker Healer`
  already `prio=1` → add `role="HEALER"`); validation tolerates absence.
- `UI/Config/Database/TankMark_Config_Mobs_UI.lua` — Role button.
- `UI/Config/Database/TankMark_Config_Mobs_Menus.lua` — `InitRoleMenu`.
- `UI/Config/Database/TankMark_Config_Mobs_Logic.lua` — `SaveFormData` writes `role`; extend
  `ApplySmartDefaults` (or a sibling) with role×tier → default prio.
- `UI/Config/Database/TankMark_Config_Mobs_List.lua` — populate `selectedRole` on edit.
- `Data/TankMark_Data.lua` — schema tolerance.

## Schema / data changes

Adds nullable `role` (string `HEALER`/`CASTER`/`MELEE`) to the mob entry. Additive; old entries valid.

## Invariants to preserve

- **Human `prio` override always wins.** Derivation only pre-fills.
- No runtime decision change *yet* beyond priority values flowing from authored `prio` (which the scanner
  already sorts on). Mechanism suites stay green.
- Keep mob `role` (HEALER/CASTER/MELEE) clearly distinct from profile `role` (TANK/CC) in code comments.

## Test plan

- **Off-client (`tests/`):** assert the derivation table — e.g. `(HEALER, elite) → 1`,
  `(MELEE, normal) → 5`, `(CASTER, elite) → 2`; assert a human-set `prio` is not overwritten by the
  derivation; assert nil role behaves as MELEE.
- **In-game (OPEN-WORLD ONLY):** tag an open-world caster pack's healer as `HEALER`, confirm it pre-fills a
  high priority, save, and confirm the scanner kill-order favors it (skull/earliest mark) on the pull.

## Done when

- `role` is editable, persisted, and shown on edit.
- Default `prio` reflects `role × tier`; a human override is respected and never clobbered.
- Healers/casters get prioritized by default without per-mob priority typing; suites stay green.
