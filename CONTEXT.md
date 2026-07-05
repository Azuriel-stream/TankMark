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

**skull succession**:
When the mob currently wearing **skull** dies, the engine promotes the next-best
remaining target to skull — the highest-priority (lowest **prio**) eligible mob still
in combat — unless a standing incumbent mark of equal-or-higher rank should keep
priority instead. The **death-time** counterpart to the **skull governor** (which
resolves skull *contests among living mobs* at mark-time); succession resolves *who
inherits skull on a death*. Both consume **prio** through the same incumbency
comparison, so the rule can't drift between them. A special case: if a physical skull
is found already on a living mob the engine has lost track of, succession *adopts* it
(records ownership) rather than re-placing it. _Avoid_: conflating with the governor —
governor is contest-time, succession is death-time.

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
The per-mob plan for a mob — `KILL` / `CC` / `IGNORE`. A **guide, not a dictator**.
`KILL` = normal (killed in **prio** order). `CC` = **forces the mob into the CC
candidate set** (overriding the auto-candidacy floor) and names a preferred CC class
— but it still yields to legality, capability, and **reserve-a-kill-target**, so a
`CC`-flagged mob can still be killed (it's the last killable mob, or a
higher-priority CC target took the slot). `IGNORE` = no mark. Distinct from **mob
role** (an *attribute*): type is *intent*.

**prio**:
A mob's **kill-order rank** — a small number where *lower = killed sooner*. The
**master ordering knob**, with two mechanical effects: (1) it **decides skull
contests** (among mobs contesting skull, lowest prio wins/holds it); and (2) it
**orders CC-vs-kill** among CC candidates — the mobs killed *last* (highest prio
number) get the scarce CC slots, the mobs killed *first* (lowest prio) are killed
(skull to the lowest). Defaults from **mob role** × **tier**, human-overridable.
_Avoid_: weight, priority (unqualified), importance.

**profile `role`**:
A *player's* job in the **Team Profile** roster — `TANK` / `CC`. Lives on
`TankMarkProfileDB`, a different table from mob role. Says who holds which mark.
_Avoid_: bare "role".

### Pull-time marking (Phase 4)

**pack**:
The set of enemy mobs in a single pull — the unit the pull-time decision reasons
over *as a whole*, rather than mob-by-mob. Pack composition decides each mob's
mark: the *same* mob type is CC'd in one pack and killed first in another (a lone
elite Warrior gets sheeped to clear the trash; a Warrior beside a healer Oracle
gets skull-killed while the Oracle is sheeped).

**CC-worthiness**:
The **auto-CC candidacy floor** — derived from **mob role** × **tier**. Its *only*
job is deciding which mobs are eligible for **automatic** CC without a human
`type=="CC"` flag (healers / elite casters clear the floor; trash does not). It does
**not** decide *which* candidate gets CC'd, nor whether a mob is CC'd vs killed —
**prio** orders that (CC the kill-last tail). Distinct from **prio** (kill order) and
**legal CC** (capability). _Avoid_: treating it as "sheep the most valuable mob" — a
healer is often a priority *kill*, not a CC target; **prio** decides, and it defaults
to killing the healer first.

**reserve-a-kill-target**:
The invariant that a pull always keeps at least one **kill target** — the engine
never spends **CC** on the last killable mob. So a lone mob is killed, not CC'd
(**even one authored `type=="CC"`** — it falls through to its own kill mark), and a
fully-CC-able pack still leaves one mob to kill. On the scanner this means the first
mob engaged is the kill and CC only starts once a skull is committed; the batch
enforces it via kill-first ordering. Neutralizing an *entire* pack is a deliberate
manual action, never an automatic outcome.

**CC-immune tier**:
Mobs of tier `rare` / `rareelite` / `worldboss` / `boss` are generally immune to
player CC (Polymorph, Banish, Sap, Shackle, …); only `normal` and `elite` mobs
are CC-eligible. This gate is **independent of legal CC**: an elite Humanoid is
CC-able, a *boss* Humanoid is not, even though the creatureType is the same.

**Smart Pre-Marking**:
The **pre-fight** marking mode. When on, a Shift+mouseover over a **pack** runs the
pack-aware `DecidePull` and marks the *whole pack at once* — kill ladder and CC
assignment computed together, before engagement. A per-character toggle, default
off. Contrast **Auto-CC** (acts in combat, per-mob). _Avoid_: conflating the two
modes — this one is pre-fight and pack-aware.

**Auto-CC**:
The **in-combat** marking mode. When on, the live scanner assigns a CC mark to a
mob that clears the **CC-worthiness** floor (healers / elite casters) as its
nameplate appears — per-mob and incremental, always honoring
**reserve-a-kill-target**. A per-character toggle, default off. Contrast **Smart
Pre-Marking** (pre-fight, whole-pack). _Avoid_: assuming it reasons over the pack —
it does not; that is Smart Pre-Marking's job.

### Mob-knowledge store (runtime)

**active zone view**:
The mob knowledge for the **current zone** as the decision layer reads it: the
per-zone entries from `TankMarkDB.Zones` overlaid **user-wins** on the shipped
`TankMarkDefaults`, validated as it is built, and cached in `activeDB`. Rebuilt on
zone change. Distinct from the persistent multi-zone store (`TankMarkDB.Zones`,
every zone as authored) and the shipped baseline (`TankMarkDefaults`): the active
zone view is the *transient, merged, validated* projection of both for the one
zone in play — what every marking decision reads. _Avoid_: conflating with the
persistent store.

### Mark-slot state (runtime)

Three distinct facts about a mark slot during a live session. They are routinely
conflated because a manual/CC assignment sets two of them at once — but each has
its own writer and lifetime, and they are **not** a biconditional pair (a profile
loads assignments with nothing owned; a wild mob is owned with nobody assigned).

**ownership**:
"A live mob currently wears this mark." Recorded in the **Ledger** (`MarkMemory`,
and the `usedIcons` occupancy flag) when a mark lands on a mob, cleared when it
dies or the mark is stolen. The engine's factual record of what is physically
marked in the world. _Avoid_: conflating with reservation (a slot can be reserved
with no mob wearing it) or assignment (a mark can be owned with nobody assigned).

**reservation**:
The act of **claiming a mark slot for a player** ahead of — or independent of —
any mob wearing it; done when a human manually assigns a mark (`/tmark assign` or
the HUD). It flags the slot occupied (`usedIcons`) so the auto-marker won't hand
that icon to another mob, and names the responsible player. Distinct from
**ownership** (no live mob need exist) and stronger than **assignment** (it also
occupies the slot). _Avoid_: reading `usedIcons` as "reserved" on its own
(ownership sets it too); and the transient "reserved icons" set inside `DecidePull`
(that is just "already unavailable this pull" — it reads occupancy, it does not
create a reservation).

**assignment** (session):
The live **player↔mark binding** — which player is responsible for each mark this
session (`sessionAssignments`). The **Team Profile** roster projected onto the
current pull; also filled as a side effect when an owned mark matches a profile
entry. Drives the HUD. Present with no mob marked (a loaded profile binds every
mark before the pull) and absent on an owned mark nobody is assigned to. _Avoid_:
conflating with **profile role** (the TANK/CC axis) or with reservation —
assignment alone does **not** occupy the slot (the `[v0.26]` rule).

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
