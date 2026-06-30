# TankMark

A World of Warcraft (Vanilla 1.12 / Turtle WoW) addon that automatically assigns
raid target **marks** to enemy mobs during a pull. This glossary fixes the language
of the **marking-intelligence** layer — what a mob *is*, what it *does*, and the
strategy a human authors for it.

## Language

### Mob knowledge (what a mob *is* / *does*)

**Mark**:
A raid target icon (skull, cross, moon, …, 1–8) placed on a mob. The unit of output —
the engine's whole job is deciding which mark each mob gets. Icon `0` means "ignored".
_Avoid_: icon (use only for the raw 1–8 id), target.

**Skull**:
Mark 8 — the highest-priority kill mark, governed specially (the "skull governor").
Among mobs that contest skull, the one with the lowest **prio** number holds it.

**creatureType**:
What kind of creature a mob is (Humanoid, Beast, Undead, …), read live and free from
the client. Drives legal-CC routing.

**tier**:
A mob's classification — `normal` / `elite` / `rare` / `rareelite` / `worldboss`.
Read live and free from the client. An input to default-priority derivation.
_Avoid_: rank, classification, level.

**mob `role`**:
What a mob *does* in a fight — `HEALER` / `CASTER` / `MELEE`. The one fact the client
cannot tell us; a human authors it. Lives on the mob entry in `TankMarkDB.Zones`.
_Avoid_: bare "role" — always qualify (see Flagged ambiguities).

### Strategy (what a human authors)

**type**:
The per-mob plan for a mob — `KILL` / `CC` / `IGNORE`. Distinct from **mob role**:
type is the *intent* (kill it, crowd-control it, leave it), role is an *attribute*.
A `KILL` mob defaults to **skull**; a `CC` mob gets its crowd-control class icon.

**prio**:
A mob's **kill-order rank** — a small number where *lower = killed sooner*. Its one
mechanical effect is **deciding skull contests**: among skull-authored mobs, lowest
prio wins/holds skull. It does *not* (yet) reorder non-skull marks — that is Phase 4
routing. _Avoid_: weight, priority (unqualified), importance.

**profile `role`**:
A *player's* job in the **Team Profile** roster — `TANK` / `CC`. Lives on
`TankMarkProfileDB`, a different table from mob role. Says who holds which mark.
_Avoid_: bare "role".

## Flagged ambiguities

- **"role" is two distinct concepts.** **mob `role`** (HEALER/CASTER/MELEE, on the
  mob entry) describes a *mob*; **profile `role`** (TANK/CC, on the team profile)
  describes a *player*. Different tables, no real collision, but never write bare
  "role" in code or docs — always qualify "mob role" vs "profile role".

- **"priority" vs "prio".** **prio** is the authored kill-order number on a mob entry.
  Do not conflate with the *governor incumbency* comparison (which mob keeps skull) —
  that comparison *consumes* prio but is a separate mechanism.

## Example dialogue

> **Dev:** A Frostmane caster pack — I want the healer dead first. Do I set its prio?
>
> **Lead:** You set its **mob role** to `HEALER`. That *derives* a low **prio** by
> default — you don't type the number. Prio is the kill-order rank.
>
> **Dev:** And that makes it die first how?
>
> **Lead:** Both the healer and the melee default to **type** `KILL`, so both are
> authored to **skull**. Lowest prio wins the skull contest — the healer steals it
> off the melee. Skull tracks the healer.
>
> **Dev:** What about the casters I want sheeped?
>
> **Lead:** Those are **type** `CC`, not a role question. They get the mage's CC mark,
> and your **profile role** `CC` player is who's assigned to sheep them. Role and type
> are different axes — a mob can be a `CASTER` (role) that you `KILL` (type).
