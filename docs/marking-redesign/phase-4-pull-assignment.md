# Phase 4 — Pull-level coordinated assignment (pack-aware marking)

> Prev: [`phase-3-role-and-priority.md`](phase-3-role-and-priority.md) · Next:
> [`phase-5-cast-learning.md`](phase-5-cast-learning.md) · Up:
> [`00-OVERVIEW.md`](00-OVERVIEW.md) · Schema: [`DATA-MODEL.md`](DATA-MODEL.md) ·
> Glossary: [`../../CONTEXT.md`](../../CONTEXT.md)

## Goal

Make a mark **depend on the pack it's in**. The *same* mob type should be CC'd in one pull and
killed-first in another, decided from what it's standing next to:

- `4× Cretin + Warrior` → **sheep the Warrior** (the durable one), cleave the trash.
- `2× Warrior + Oracle(healer)` → **sheep the Oracle** (heals are costliest), skull the Warriors.

Same Warrior, opposite call. The engine spends scarce CC on the costliest-to-leave-active mobs (a
**CC-worthiness** ranking: HEALER > dangerous CASTER > durable elite MELEE > trash, gated by **legal
CC** and **CC-immune tier**), then lays a kill-order ladder for the rest and leaves overflow to the
in-combat mechanics. This is the payoff of Phases 1–3; build it last, on their data.

## Prereqs

Phases 1, 2 and 3 landed and verified in-game. Do not start before then.

## Two deliverables (sequence A → B), one shared brain

The grill split the work in two, around a single shared helper so the CC judgment never forks:

- **A — pre-fight pack marking (build first).** A pure, pack-aware `DecidePull` in the **Batch path**
  (Shift+mouseover). It sees the *whole pack* before combat, so it does the **relative** reasoning ("of
  these mobs, sheep the best target(s), ladder the kills, drop the trash").
- **B — in-combat auto-CC (build second).** The scanner's `ResolveCC` extended to auto-CC the
  **absolutely**-worthy mobs (healer / elite caster) when a legal slot is free — for the run-into-packs
  playstyle. Touches only the **pure decision layer**, never the scanner `OnUpdate` loop.

Both call **`CCWorthiness(role, tier)`** — A *sorts* the pack by it, B *thresholds* it per-mob.

## Scope / non-goals

- **In:** `DecidePull` (CC-worthiness ranking + stable-slot CC + kill-order ladder + deliberate overflow)
  in the Batch path; the scanner `ResolveCC` auto-CC extension; two default-off toggles.
- **Out:** changing the Ledger/governor/swarm/sync/death mechanism; making the *automatic scanner*
  pack-aware (deliberately — see ratified #2); interrupts (Phase 5). Both passes **emit intents only**
  and apply through the existing edge (`ApplyMarkIntent → Ledger.Assign → Driver_ApplyMark`).

**Observable contract.** Pre-marking a pack (A) sheeps the worthy targets and skulls/ladders the kills.
In combat (B, when toggled on) a healer/elite-caster gets auto-sheeped as its nameplate appears. The
**relative** "sheep the durable melee" trick (pack `4× Cretin + Warrior`) is **pre-fight only** — the
scanner sees mobs one nameplate at a time and cannot make a pack-relative call, so it only ever auto-CCs
*absolutely*-worthy mobs (healers/casters).

## Ratified decisions (grill 2026-06-30)

1. **A in the Batch path, B in the scanner's decision layer; sequenced A → B; one shared
   `CCWorthiness`.** A replaces the per-mob decide step in `ExecuteBatchMarking`; B extends `ResolveCC`.
   The worthiness curve is single-sourced so the two never drift (like `IncumbencyBlocks`).
2. **Pack-awareness lives in the pre-fight batch, NOT the automatic scanner.** The scanner discovers a
   pack **incrementally** (nameplates appear over ~1–2 s of a pull), which defeats pack-level reasoning
   and fights stickiness; the batch sees the whole pack pre-combat. So the scanner stays greedy/per-mob.
   B is the *only* scanner-facing change and it is a scoped, gated **per-mob absolute** auto-CC — it
   edits the pure `ResolveCC`/`DecideKnownMark`, never the `OnUpdate` scan loop or `ProcessUnit`'s
   verification front-half. (This is the load-bearing architectural call — risk/completeness trade-off.)
3. **Scenario 2 (a patrol joins mid-fight) = existing in-combat mechanics, no rebuild.** With a sane
   profile the skull *walks down the kill order* via the death path
   (`ReviewSkullState`→`FindEmergencyCandidate`, `Assignment.lua:489`) as holders die, while committed CC
   marks stay sticky via the scanner's `Reaffirm`. Verify in-game; write no new code for it.
4. **`CCWorthiness(role, tier) → score`, pure, in `Core/TankMark_Assignment.lua`.** Reads role+tier
   **directly, never `prio`** (prio is the human's overridable *kill-order* knob — a different axis;
   deriving worthiness from it would make the scanner try to *sheep* a melee the human set to prio 1).
   **Total** (nil role → MELEE row, nil tier → `normal` col, reusing `ROLE_TIER_BUCKET`). One curve:
   B thresholds it (`SCANNER_CC_FLOOR`, ~70 → healers any tier + elite+ casters auto-CC; melee never);
   A sorts by it. Numbers are defaults, not law (tune like `RoleTierPrio`):

   | `role` \ `tier` | normal | elite | rare | boss |
   |---|---|---|---|---|
   | HEALER | 90 | 100 | 100 | 100 |
   | CASTER | 40 | 70 | 70 | 80 |
   | MELEE  | 10 | 30 | 35 | 40 |

5. **Three composing CC eligibility gates** (the Phase-2 pattern, +1). `IsLegalCC(class, creatureType)`
   (capability) + `CCRaceEligible(class, race)` (Troll-Hex, per-slot) + **new `CCTierEligible(tier)`** —
   true only for `normal`/`elite`; `rare`/`rareelite`/`worldboss`/`boss` are **CC-immune**.
   `CCTierEligible` is a **mob** gate, applied *before* `SelectCCSlot` (which stays about picking a
   *slot*). It also excludes bosses from CC for free (e.g. `Kan'za + 2× Snowcaller` → only the
   Snowcallers are CC candidates). Consequence: the `rare`/`boss` columns of the worthiness curve are
   unreachable for CC (gated out first) — kept for totality.
6. **Precedence ladder (top wins):**
   1. **IGNORE is absolute** — `type=="IGNORE"` or `marks=={0}` → excluded from CC *and* kill passes.
   2. **Authored `type=="CC"` = gated worthiness-override** — forces the mob into the CC-candidate set
      at top rank, and its authored `class` is the preferred slot (`SelectCCSlot` pass 1). Still gated by
      legality + tier + free slot; falls through to the kill pass if it can't actually be CC'd.
   3. **Authored `prio` overrides** the role×tier-derived kill order (the Phase-3 model).
   4. **`DecidePull` owns mark placement** — CC marks from the chosen slot, kill marks from the tank
      ladder. An authored single-icon `marks` is **not** honored as a fixed position (it fought the
      ladder); `marks` matters only for the `{0}`=IGNORE signal. Sequential `marks` (>1) is a separate
      mechanism — see #11.
7. **Context-dependent IGNORE is out of scope.** `type=="IGNORE"` is per-mob-name and *global*; the
   channelling-Ritualist case (killed in most packs, left alone only when channelling a boss) cannot be
   expressed by per-mob data. The human handles that pack manually. No pack-specific override system.
8. **CC pass = greedy by worthiness, reusing `SelectCCSlot`.** Walk CC-able candidates in worthiness
   order; for each, `SelectCCSlot` over the slots, marking the chosen slot used in the **in-pass**
   accounting so the next candidate can't double-book it. Accept rare *suboptimal matching* (a specialist
   slot ordered before a generalist can starve a mob only the generalist covers) — determinism and
   simplicity beat bipartite-optimality. `log()` when a worthy target goes unCC'd; never silent.
9. **Kill pass = tank roster, profile order, prio-sorted, laddered.** Marks come from `GetTankRoster`
   (alive `TANK` slots) in **profile order**; kill mobs sorted `(prio asc, stable tiebreak)`; top mob →
   first tank mark (skull), laddering down. **Ladder depth = tank-slot count** (1 tank → single-skull
   focus; 3 tanks → Skull/Cross/Square). Stable tiebreak = mouseover sequence live, mob name in fixtures.
10. **Overflow = in-combat handoff, not loss.** Kill mobs beyond the ladder stay unmarked; as marked
    holders die, the scanner's death path pulls them into freed marks (this is how pack B's "skull one
    Warrior, kill, skull the next" *emerges* — `DecidePull` skulls Warrior1, the death path hands skull
    to Warrior2). Surface as *"marked top N; M left for AoE/scanner pickup"* — never silent truncation.
11. **Sequential marking preserved (the explicit safety rule).** `ExecuteBatchMarking` **partitions**
    candidates: sequential (`marks>1`) mobs keep the **verbatim** `ProcessBatchMark` cursor branch
    (`Batch.lua:247-276`, incl. the force-apply at `:267-272` and exhausted→`DecideUnknownMark`);
    `DecidePull` handles only pack mobs. To match "sequential force-applies/wins" deterministically,
    `DecidePull` **seeds its `usedMarks` with every icon any sequential candidate's `marks` reserves**,
    so the brain never lays a mark on an icon a sequence will consume. The scanner's sequential bail
    (`DecideKnownMark`, `Processor.lua:289`) is *upstream* of the Part-B `ResolveCC` change → untouched.
12. **Purity + apply split.** `DecidePull(candidates, board)` is **pure** → an ordered list of intents
    `{guid, name, icon, reason}`, deciding the whole pack before anything applies. Local in-pass
    `usedMarks`/`usedSlots` (seeded from the board's busy/disabled state) stand in for the live Ledger
    that today advances between per-mob applies. The existing batch **delayed-apply queue**
    (`StartBatchProcessor`, 50 ms spacing) + its re-validation (still-exists / not-dead / not-already-
    marked / not-in-combat / `MarkNormals` / queen-gate) are reused; only the *decision source* changes.
13. **Placement + ports.** `CCWorthiness`/`CCTierEligible` → `Assignment.lua` (with `RoleTierPrio` /
    `SelectCCSlot` / `IncumbencyBlocks`). `DecidePull` → **new `Core/TankMark_Pull.lua`**, loaded after
    `TankMark_Processor.lua` in `.toc`. Two new `LiveBoard` ports: `getTankRoster()` and `tier(guid)`
    (live `UnitClassification`, stored fallback — mirroring `creatureType(guid)`). The mock `make_board`
    upgrades `creatureType`/`tier` to **per-guid** lookups (today one value for all) to fixture a pack.
14. **Two independent default-off toggles** in `TankMarkCharConfig`: **"Smart pre-mark"** (A) and
    **"Auto-CC in combat"** (B). Exposed via a config checkbox each + a slash toggle
    (`/tmark smartmark on/off`, `/tmark autocc on/off`). Default-off means installing the update changes
    nothing until opt-in. **No sync** — marking is the queen's job, so the active marker's toggles govern.
15. **Single mob `role` taxonomy** (HEALER/CASTER/MELEE) is sufficient; the human tags the
    *marking-dominant* role (Oracle → HEALER, Snowcaller → CASTER), secondary tags ignored.
16. **Surfacing:** one chat summary line (CC picks + skull + overflow-as-handoff) + a guarded `PULL`
    `DebugLog` category (full ranked plan + per-mob gate reasons). No new HUD — pre-marking populates the
    existing mark→assignee HUD through the normal `RegisterMarkUsage`/`UpdateHUD` path.

## Part-B refinements (grilled 2026-07-04)

Building Part B surfaced eight calls that refine — and in one case *change* — the decisions above:

- **B1. The toggle enters through a new board port `autoCCEnabled()`** (not a direct global read),
  keeping `ResolveCC` in the zero-global decide layer and making both toggle states harness-testable.
  `LiveBoard.autoCCEnabled → TankMark:AutoCCEnabled()`; the mock injects a boolean (default `false`).
- **B2. `AutoCCEnabled()` lives in `Processor.lua`** beside `ResolveCC`/`LiveBoard` (not `Pull.lua`, which
  B never touches); reads `TankMarkCharConfig.autoCC`. Mirrors `SmartMarkEnabled` in shape only.
- **B3. `SCANNER_CC_FLOOR` (~70) is single-sourced in a floor-only pure helper
  `ScannerAutoCCWorthy(role, tier)` in `Assignment.lua`**, beside `CC_WORTH` — `ResolveCC` stays a thin
  router. Directly unit-tested (healer→true, caster-elite→true, caster-normal/melee→false).
- **B4. CHANGES #5 — the tier gate is UNIVERSAL, not auto-CC-only.** `CCTierEligible` now gates the
  `type=="CC"` path too, finally honoring #5's "applied before `SelectCCSlot`." Consequence: a
  `type=="CC"` authored on a rare/boss tier stops routing to a CC slot **even with the toggle off** — a
  small, correct behavior change independent of the toggle. See the Invariants caveat.
- **B5. Auto-CC pre-empts an authored `type=="KILL"`** for a worthy mob with a free legal slot (the
  per-mob shadow of A's CC-pass-first). `ResolveCC` returns before the kill/skull selection, so a CC
  result structurally wins. No per-mob "kill-me-never-sheep-me" opt-out in B (the floor + toggle are the
  only knobs); revisit only if in-game demands it.
- **B6. The auto-CC branch passes `authoredClass=nil`** to `SelectCCSlot` (auto-CC has no authored CC
  preference → first-legal-in-profile-order). `mobData.class` is used only on the `type=="CC"` branch.
- **B7. Light-touch surfacing through the existing pure sink:** `DecideKnownMark` tags `reason="cc"` when
  the icon came from the CC seam (also relabels today's authored CC, currently mislabeled `"known"`), and
  `logDecision` gains a `type` field → the log distinguishes kill vs CC and authored vs auto CC. No
  `DebugLog` inside the pure `ResolveCC`.
- **B8. Toggle ships slash-only** (`/tmark autocc on/off`), matching Phase 4A's `smartmark` as *actually
  shipped* — #14's "config checkbox each" was never built for A. A single follow-up adds **both**
  checkboxes together (tracked). No sync (marking is the queen's job; the active marker's toggle governs).

**Sequential-safety re-confirmed (code-traced, not inferred):** `ResolveCC` has exactly one caller
(`DecideKnownMark:316`), which sits *below* the sequential bail (`:294`); and the batch path routes
sequential mobs through a mutually-exclusive `if` branch (`Batch.lua:263`) that never reaches
`DecideMark`. B changes only `ResolveCC`'s body, moving nothing — so #11 holds on the batch path too. A
one-line comment at the bail marks it load-bearing for sequential-safety.

## Phase-4 CC-model revision (grilled 2026-07-04)

In-game testing of Part B exposed two bugs **and** forced a rethink of the CC *selection* model. The
outcome **supersedes the worthiness-ranked selection** in ratified #8/#9 above and in Part A's design
(those passages are kept for the decision trail, not deleted). Authority now lives in
[ADR 0002](../adr/0002-prio-drives-cc-vs-kill-selection.md) and the sharpened `CONTEXT.md` terms
(`prio`, `type`, `CC-worthiness`, `reserve-a-kill-target`).

### The settled model

- **`prio` is the master ordering knob** — it decides skull contests **and** orders CC-vs-kill among
  candidates: CC the mobs killed *last* (highest prio number); kill the mobs killed *first* (lowest →
  skull).
- **CC-worthiness shrinks to the auto-candidacy *floor*** — which mobs are CC-eligible without a human
  `type=="CC"` flag. It no longer ranks or selects.
- **`type=="CC"` = candidacy forcer** (overrides the floor) + class preference — a guide, not a dictator.
- **reserve-a-kill-target** — the engine never spends CC *it chose on its own* on the last killable mob.
  A lone worthy/plain mob is killed; a fully-CC-able pack still leaves one kill. Full-pack CC is
  manual-only.
- **HUD enable/disable of CC players** (`disabledMarks`, already built) = the live per-pull CC
  capacity/class dial. No new UI.

### Build deltas (supersede the worthiness-ranked passages)

- **(b) governor** — new pure `IsCCSlotMark(icon, profileList)`; `GetBlockingMarkInfo`'s `UpdateBest`
  early-outs on it (beside `IsMarkCCd`) so a mob holding a **CC-role mark never blocks skull**, aura or
  not. Fixes the "auto-CC'd mob suppresses skull for the whole pack" bug on **both** governor paths
  (`GovernorBlocks` + `ReviewSkullState`). Predicate unit-tested (`legal_cc_spec`); wiring live-verified.
- **(a) reserve** — scanner `ResolveCC` skips unless `board.isMarkBusy(8)` (a skull is committed) on
  **both** branches (**BD3-A**, reversed from BD3-B after in-game): no CC — auto *or* authored
  `type=="CC"` — until a kill target exists, so the first mob engaged is the kill and a lone `type=="CC"`
  mob falls through to its own kill mark. Auto-CC additionally needs the toggle; authored `type=="CC"`
  does not. Batch `DecidePull` reserves a kill target **automatically** via kill-first ordering (below).
- **(c) selection** — `DecidePull` is now **KILL-FIRST**: the tank ladder claims the lowest-prio mobs
  (skull to the kill-first; `prio asc`, `seq asc`), then CC claims the eligible **leftovers** taking the
  **kill-last** (`prio desc`, `seq desc`). Candidacy = `CCTierEligible AND (type=="CC" OR
  MeetsAutoCCFloor)` — worthiness gates candidacy only; `authoredCC` drops out of the *ranking*.
  **No demotion** — reserve-a-kill-target is automatic (the ladder always kills the lowest-prio mob
  before CC can reach it). `ScannerAutoCCWorthy` → renamed **`MeetsAutoCCFloor`** (both paths share the
  one floor). NB: **mouseover order is the sub-`prio` kill-order tiebreak** — first-moused = kill-first =
  **skull**; a CC target must be authored **high-prio / kill-last** (not low prio).

### Consequence — the flip

A healer + caster pack now **skulls the healer** (low prio, killed first) and **CCs the caster** (killed
last) — the traditional "kill the healer, CC the adds." This **inverts** Part B's shipped worthiness
default; the `pull_assignment_spec` Pack A/B expectations are recomputed by prio. Kept (from Part B):
`MeetsAutoCCFloor` (as the floor), universal `CCTierEligible`, the `autocc` toggle/port, `reason="cc"`.

## Design

### Part A — `DecidePull` in the Batch path

`Core/TankMark_Pull.lua`, pure + board-injected like `DecideMark`:

```
DecidePull(candidates, board) -> { {guid, name, icon, reason}, ... }   -- intents only
```

1. **Filter.** Drop IGNORE (`type=="IGNORE"` / `marks=={0}`). Partition out sequential (`marks>1`) mobs —
   they are *not* handled here (#11); seed `usedMarks` with their reserved icons.
2. **Classify.** For each remaining candidate read `role`/`prio`/`type`/`class` from its `mobData`, and
   `creatureType`/`tier` live via the board (stored fallback). Compute `CCWorthiness(role, tier)`.
3. **CC pass.** Build the CC-candidate set = worthiness-ranked mobs that pass all three eligibility gates
   (with `type=="CC"` forced in at top rank). Greedily assign each to a slot via `SelectCCSlot`, marking
   the slot + icon used in-pass. `log` any worthy-but-unassigned target.
4. **Kill pass.** The rest are the kill list, sorted `(prio, tiebreak)`. Hand out `getTankRoster()` marks
   in profile order (skipping in-pass-used icons) — skull to the top, laddering to tank-slot depth.
5. **Overflow.** Remaining kill mobs → no intent; collect for the handoff summary (#10, #16).
6. **Return** the intent list. `ExecuteBatchMarking` feeds it (plus the untouched sequential branch) into
   the existing delayed-apply queue.

### Part B — scanner auto-CC in `ResolveCC`

**Grilled + refined 2026-07-04** (see the Part-B addendum under Ratified decisions). Today `ResolveCC`
(`Processor.lua:276`) returns a CC mark **only** for `type=="CC"`. The refined shape gates the *new*
auto-CC behavior behind the **`board.autoCCEnabled()`** port and applies the tier gate **universally**:

```
function TankMark:ResolveCC(mobData, guid, board)
    local isAuthoredCC = (mobData.type == "CC")
    if not isAuthoredCC and not board.autoCCEnabled() then return nil end   -- auto-CC gated by toggle
    local tier = board.tier(guid) or mobData.tier
    if not TankMark:CCTierEligible(tier) then return nil end                -- UNIVERSAL tier gate (#5, B4)
    if not isAuthoredCC and not TankMark:ScannerAutoCCWorthy(mobData.role, tier) then
        return nil                                                          -- auto-CC worthiness floor
    end
    local ct = board.creatureType(guid) or mobData.creatureType
    local authoredClass = isAuthoredCC and mobData.class or nil             -- auto-CC has NO authored pref
    return TankMark:SelectCCSlot(authoredClass, ct, board.getCCSlots())
end
```

Toggle off → today's behavior **except** the now-universal tier gate (a `type=="CC"` on a CC-immune tier
stops routing — see the Invariants caveat). The sequential bail (`DecideKnownMark:294`) is upstream and
the governor/theft below are untouched. The `tier(guid)` / `getCCSlots` ports already exist (Phase 4A).
`ScannerAutoCCWorthy(role, tier)` is a new **floor-only** pure helper in `Assignment.lua`
(`CCWorthiness(role,tier) >= SCANNER_CC_FLOOR`, ~70), co-located with the curve; the tier-immunity half of
"boss healer → nil" is the universal `CCTierEligible` gate, not the helper.

## Files & functions to touch

- `Core/TankMark_Assignment.lua` — **new pure `CCWorthiness(role, tier)`** (curve, total) + **new pure
  `CCTierEligible(tier)`**. Reuse `GetTankRoster`, `GetCCSlots`, `SelectCCSlot`, `IsLegalCC`,
  `CCRaceEligible`, `IncumbencyBlocks`.
- **New `Core/TankMark_Pull.lua`** — `TankMark:DecidePull(candidates, board)`. Add to `TankMark.toc`
  after `TankMark_Processor.lua`.
- `Core/TankMark_Processor.lua` — add `getTankRoster` + `tier` ports to `LiveBoard` (`:17`); extend
  `ResolveCC` (`:271`) for Part B behind the toggle.
- `Core/TankMark_Batch.lua` — `ExecuteBatchMarking` (`:73`): partition sequential vs pack, call
  `DecidePull` for the pack (gated by the "Smart pre-mark" toggle; toggle off = today's per-mob path),
  feed intents to the existing queue. **Sequential branch in `ProcessBatchMark` (`:247-276`) untouched.**
- `TankMark.lua` / config — two `TankMarkCharConfig` toggles + slash commands + config checkboxes.
- `tests/support/board.lua` — per-guid `creatureType`/`tier`; `getTankRoster` port.
- `tests/pull_assignment_spec.lua` — **new** (see Test plan). Register in `tests/run.lua`.

**Part-B deltas (the A rows above are shipped):**
- `Core/TankMark_Assignment.lua` — **new floor-only pure `ScannerAutoCCWorthy(role, tier)`** + file-local
  `SCANNER_CC_FLOOR = 70`, beside `CC_WORTH`.
- `Core/TankMark_Processor.lua` — **new `AutoCCEnabled()`** (reads `TankMarkCharConfig.autoCC`); **new
  `autoCCEnabled` port** on `LiveBoard`; rewrite `ResolveCC` (universal `CCTierEligible` gate + toggle-gated
  worthiness-floor branch, `authoredClass=nil` for auto-CC); tag `reason="cc"` in `DecideKnownMark` when
  the icon came from the CC seam; add `type=mobData.type` to `logDecision`'s payload. One-line comment at
  the sequential bail (`:294`) marking it load-bearing for sequential-safety.
- `TankMark.lua` — `/tmark autocc on/off` handler (mirror `smartmark` at `:461`) + help line; writes
  `TankMarkCharConfig.autoCC`. **Config checkbox deferred to a follow-up** (adds both toggles together).
- `tests/support/board.lua` — **new `autoCCEnabled` port** (`flag(o.autoCC, false)`).
- `tests/cc_worthiness_spec.lua` (`ScannerAutoCCWorthy`) + `tests/governor_spec.lua` (the 12 `ResolveCC`
  Part-B cases, beside the existing CC tests) — **extend**. No new spec file.

## Schema / data changes

None new — consumes Phase 1–3 fields. The board gains `getTankRoster` + `tier` ports (pure, for testing).

## Invariants to preserve

- **Stickiness:** never reassign/move a mark already in the Ledger (the scanner `Reaffirm`s held marks).
- **Stable player↔mark binding:** the engine picks the *mob* for a slot, never the *player* for a mark.
- **Determinism:** identical pack → identical intents (stable sort keys; no time/random).
- **Sequential marking** behaves identical-or-safer (#11).
- **Mechanism untouched:** intents only; `governor_spec`, `incumbency_spec`, `swarm_election_spec`,
  `sync_codec_spec`, `trust_spec`, `legal_cc_spec`, `role_prio_spec` all stay green.
- **No silent truncation:** overflow + unCC'd-worthy are logged/surfaced.
- **Default-off:** no behavior change until a toggle is flipped — **except** the now-universal
  `CCTierEligible` gate (Part-B refinement B4): a `type=="CC"` authored on a CC-immune tier
  (`rare`/`rareelite`/`worldboss`/`boss`) stops routing to a CC slot even with Auto-CC off. Deliberate,
  correct, and aligned with #5; the only toggle-independent change in Phase 4B.

## Test plan

**Off-client (`tests/`, Lua 5.1):**

- **Pure units (`Assignment.lua`):** `CCWorthiness` curve + totality (nil role→MELEE, nil tier→normal);
  `CCTierEligible` (normal/elite → true; rare/rareelite/worldboss/boss → false).
- **`tests/pull_assignment_spec.lua`** — `DecidePull` over a board with per-guid `creatureType`/`tier`,
  a tank roster + CC slots, using the **Frostmane fixture packs**
  ([`DATA-MODEL.md`](DATA-MODEL.md#frostmane-fixture-packs)):
  - Pack A `4× Cretin + Warrior` (1 Mage, 1 tank) → Warrior sheeped, a Cretin skulled, rest overflow-logged.
  - Pack B `2× Warrior + Oracle` (1 Mage, 1 tank) → Oracle sheeped, Warrior1 skulled, Warrior2 overflow.
  - Legal-CC `Snowcaller(Humanoid) + Ice Elemental(Elemental)` (Mage + Warlock) → Snowcaller→Mage,
    Elemental→Warlock; Mage **never** routed to the Elemental.
  - Boss exclusion `Kan'za(boss) + 2× Snowcaller` → Kan'za never CC'd; a Snowcaller CC'd.
  - Precedence → IGNORE excluded; `type=="CC"` forced into CC (still gated); authored `prio` reorders kills.
  - Sequential safety → a pack with a `marks>1` mob: `DecidePull` skips it **and** reserves its icons.
  - Determinism → same pack twice → identical intents. Overflow → handoff list logged.
- **Part B pure units (`cc_worthiness_spec.lua`):** `ScannerAutoCCWorthy(role, tier)` floor-only —
  HEALER normal/elite → true; CASTER elite → true (70≥70); CASTER normal → false (40<70); MELEE any →
  false; totality (nil role→MELEE→false, nil tier→normal col: HEALER→true). Tier-immunity stays covered
  by `CCTierEligible` (normal/elite→true, rare/rareelite/worldboss/boss→false).
- **Part B integration (`governor_spec.lua` — where the `ResolveCC` tests live; direct `ResolveCC` + through `DecideKnownMark`), 12 cases:**
  add `autoCCEnabled` to the mock board (default `false`). (1) toggle **off**, KILL HEALER, free legal
  slot → nil; (2) toggle **on**, KILL HEALER Humanoid/elite, free Mage slot → the Mage's CC mark; (3)
  toggle on, KILL MELEE → nil (below floor); (4) toggle on, KILL HEALER **boss** tier → nil (universal
  tier gate); (5) toggle on, worthy HEALER, **no legal slot** → nil; (6) toggle on, worthy HEALER, slot
  **already used** → nil (per-mob double-book safety via live Ledger); (7) `type=="CC"`, toggle **off** →
  still the CC mark (authored CC toggle-independent); (8) `type=="CC"` on **boss**, toggle off → nil (the
  B4 behavior-change pin); (9) toggle on, auto-CC HEALER, profile order Warlock-then-Mage, `mobData.class="MAGE"`
  → Warlock's mark (authoredClass=nil ⇒ first-legal-in-profile-order, B6). Through `DecideKnownMark`:
  (10) toggle on, KILL HEALER → `intent.icon`=CC mark **and** `reason=="cc"` (B7 + pre-empts skull);
  (11) `type=="CC"` → `reason=="cc"` (relabel guard); (12) **sequential** mob (`marks`>1), toggle on →
  `reason=="sequential-marks"`, no CC (sequential-safety regression).
- **Regression:** all mechanism suites stay green.

**In-game (OPEN-WORLD ONLY, deploy via `.claude/sync-to-network.sh`):** pre-mark mixed open-world packs
(A) — confirm the worthy target is sheeped + skull/ladder descends by prio + overflow surfaces; toggle
Auto-CC and pull (B) — confirm a healer/caster auto-sheeps; confirm sequential mobs still cycle; confirm
the patrol-join skull-handoff (scenario 2).

## Done when

- Pre-marking a pack CC's the worthy target(s) on **legal** slots, lays a descending kill ladder, and
  surfaces overflow as handoff — the *same* mob CC'd or killed depending on pack composition.
- With Auto-CC on, the scanner auto-sheeps absolutely-worthy mobs (healer/elite caster) in combat; off,
  behavior is unchanged.
- Sequential marking is unaffected; identical packs route identically; held marks are never reshuffled;
  every mechanism suite stays green.
- Both behaviors are behind default-off toggles.
