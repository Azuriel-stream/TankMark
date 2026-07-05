# Phase 5 — Cast-learning the mob `role` (FUTURE / OPTIONAL)

> Prev: [`phase-4-pull-assignment.md`](phase-4-pull-assignment.md) · Next: — · Up:
> [`00-OVERVIEW.md`](00-OVERVIEW.md) · Schema: [`DATA-MODEL.md`](DATA-MODEL.md)

> **Status: SHELVED by decision (2026-07-05).** Phases 1–4 shipped and the redesign is considered
> complete; this phase was reviewed and judged **high-investment / low-return**, so it is deliberately
> not built — not a pending backlog item. Revisit only if manual `role`-tagging becomes a real in-game
> pain. The design below is preserved as-is for that possibility.
>
> **Originally deferred.** Build only after Phases 1–4 are solid and you want to reduce the one remaining
> piece of human authoring (mob `role`). Everything else works without this.

## Goal

Infer a mob's `role` (HEALER/CASTER/MELEE) automatically by **observing what it casts**, so a human no
longer has to tag most casters/healers by hand. The human tag always wins; learning only fills unknowns.

## Prereqs

Phase 3 (the `role` field exists and drives priority/routing). Phase 4 benefits most (better routing
from better roles), but learning is independent of it.

## Why it's feasible (and why it's deferred)

SuperWoW exposes **`UNIT_CASTEVENT`**, which fires when *any* unit (including arbitrary mobs) casts —
this is the same mechanism noted in the SuperWoW feature set. It is **not registered anywhere today**
(verified: `TankMark.lua` event registrations do not include it), so this is net-new wiring, hence
deferred rather than free. `SpellInfo(id)` (already in `Locals` as `_SpellInfo`) resolves a spell id to
a name for classification.

## Design

### 1. Register and route the event

Register `UNIT_CASTEVENT` in `TankMark.lua` (add to `Locals`/event registration) and handle it like the
other events. The handler receives the casting unit (GUID under SuperWoW) and the spell id.

### 2. Classify spell → role

Maintain a small spell-classifier (a table or pattern set), conservative by design:

```lua
-- illustrative, not exhaustive
HEALER_SPELLS = { Heal, "Greater Heal", "Renew", "Holy Light", "Healing Wave", "Mend", ... }
CASTER_SPELLS = { "Frostbolt", "Shadow Bolt", "Fireball", "Lightning Bolt", "Arcane Missiles", ... }
-- everything else / no observed cast → leave role unknown (MELEE default)
```

Resolve the cast's spell name via `SpellInfo(id)` and map to a role. Prefer HEALER over CASTER when a mob
does both (healing is the higher-value classification for kill priority).

### 3. Learn into the DB (lazy, override-safe)

When a mob casts and its DB entry's `role` is **unset**, set the learned role and persist it (same
write path as the editor; mirror the lazy-migration discipline). **Never overwrite a human-set `role`.**
Consider a confidence guard (e.g. only commit after one unambiguous healer cast) to avoid mislabeling a
melee mob that occasionally casts a utility spell.

### 4. Surface it

Log learned roles (a `DebugLog` category) and optionally show a "learned" marker in the editor so a human
can confirm or override. Learned roles feed Phase 3's priority derivation and Phase 4's routing on the
**next** pull — do not retro-rewrite the current pull's marks (respect Phase 4 stickiness).

## Files & functions to touch

- `TankMark.lua` — register `UNIT_CASTEVENT`; add it + any new spell APIs to `Locals`.
- New learner module (e.g. `Core/TankMark_RoleLearner.lua`, added to `TankMark.toc`) — the classifier +
  the lazy DB write.
- `Data/TankMark_Data.lua` — persistence (reuses the `role` field from Phase 3).
- Optional `UI/Config/Database/*` — a "learned role" indicator.

## Schema / data changes

None new — reuses `role` from Phase 3. (Optionally a `roleSource = "human" | "learned"` flag if you want
to distinguish confirmed vs inferred; keep it optional.)

## Invariants to preserve

- **Human `role` always wins** — learning fills nil only.
- **Override-safe + conservative** — don't flip a role on a single ambiguous cast.
- Respect Phase 4 stickiness — learned changes affect future pulls, not the current applied marks.
- Mechanism untouched; existing suites stay green.

## Test plan

- **Off-client (`tests/`):** feed synthetic cast events (spell id → name via a stubbed `SpellInfo`) to the
  classifier; assert HEALER/CASTER inference, HEALER-over-CASTER preference, and that a human-set role is
  never overwritten.
- **In-game (OPEN-WORLD ONLY):** find an open-world mob that heals (e.g. a humanoid healer add); confirm it
  acquires `role="HEALER"` after casting and is prioritized next pull. Deploy via `.claude/sync-to-network.sh`.

## Done when

- Untagged mobs that cast heals/spells acquire the right `role` automatically.
- Human-tagged roles are never overwritten; learning is conservative and surfaced.
- Priority/routing improve on subsequent pulls without manual tagging; suites stay green.
