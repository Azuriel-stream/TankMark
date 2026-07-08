# On Ascension, TankMark is a pre-pull pack planner, not a live marking engine

**Status:** accepted (WotLK/Ascension port, grilled 2026-07-07)

## Context & decision

Empirical probing (a throwaway `TMTest` addon, `/tmtest` + `/tmsweep`, corroborated by a client
research doc) established that **Ascension is a stock 3.3.5 client for unit addressing**: SuperWoW's
GUID-as-token, nameplate-GUID discovery, mark-by-GUID, and `mark`-token verify are **all absent**.
Native `UnitGUID` and structured CLEU deaths are present (and the CLEU `destGUID` / `UnitGUID`
namespace is shared); **token-based `SetRaidTarget` works, in and out of combat, with no taint
block**. The hard fact: on Ascension **a GUID is an identifier, not a handle** — you can only mark a
mob while it is under a live unit token (`mouseover` / `target`).

Two consequences follow. The **passive scanner has no discovery source** and cannot exist (its whole
job was turning nameplate GUIDs into addressable units). And without the scanner, *in-combat* marking
degrades to manual Shift+mouseover labor that competes with tanking — dense packs, focus theft,
moving mobs — a bad trade for casual 5-mans. SuperWoW is what made in-combat marking hands-free; it is
gone.

**Decision:** on Ascension, TankMark is a **pre-pull pack planner**. It keeps the entire pure decision
brain — `DecidePull`, mob role × tier → **prio**, CC-tagging, `ReportPullPlan` — and **drops the
reactive engine**: the scanner, the **Ledger** (ownership tracking), CLEU death-cleanup, **skull
succession**, the **skull governor**, in-combat marking, and auto-CC *player* assignment.

Application is a **human-driven two-sweep**, forced by ephemeral tokens:
- **Sweep 1** — Shift+mouseover the pack. Each hover reads the mob's **name** off the `mouseover`
  token *at hover time* (the token, not the GUID — which is not a re-readable handle) and collects the
  mob; role / tier / creatureType / prio come from the authored DB entry keyed on that name. On
  Shift-release, `DecidePull` runs, the `{guid→icon}` plan is stored **armed**, and `ReportPullPlan`
  announces it. (A *live* tier/creatureType snapshot is **deferred** — see Amendments: its only
  consumer is auto-CC, which does not fire under the ladder-≥-pack / verbal-CC model, so the DB entry
  is sufficient; the recorder is the path to make an unknown mob CC-able.)
- **Sweep 2** — Shift+mouseover again. On each hover, if `UnitGUID('mouseover')` is in the plan, the
  mark is applied to the live token then and there, draining that entry.

The armed plan is **durable session state**. It disarms on full drain, on `ResetSession` (the existing
bound `TANKMARK_RESET` / `/tmark reset` — the player's manual control), and on the existing pull-end
path (`PLAYER_REGEN_ENABLED` + player-alive), which bounds a half-drained plan to a single pull.
Combat *start* is deliberately **not** a disarm trigger, so a sweep-2 that bleeds into the opening of a
pull still completes.

**Mark-pool expansion is configuration, not code.** The kill ladder is the Team Profile tank roster
(`GetTankRoster`, one rung per profile entry), so a dungeon profile simply stacks N marks on one tank.
Tank-binding is unchanged (kept for future raids). When the ladder has ≥ pack-size rungs it claims
every mob before the CC pass runs, so auto-CC naturally does not fire — **CC becomes a verbal call
driven by the announcement**, which also sidesteps Ascension's classless CC problem.

## Considered options

- **Autonomous scanner / token-sweep discovery (rejected).** No discovery source. A party/raid-target
  union is a weak, assist-model signal (everyone on the kill target; healer on friendlies; idle =
  nothing), and a wandering add is not addressable until a human targets it.
- **In-combat human-driven marking (rejected).** Shift+mouseover mid-fight steals the tank's focus and
  is unreliable in dense packs. The scanner is what made in-combat marking invisible; without it this
  is a chore, not automation.
- **Keep the Ledger + CLEU death-cleanup as a hedge (rejected for v1).** They exist to *reuse a freed
  icon* and drive *succession*. A pure pre-pull pass never reuses an icon, so nothing needs freeing.
  Dropped until real play proves a need.
- **Lazy target-drain — single sweep, marks self-apply on natural targeting (rejected).** Revives an
  in-combat apply hook we are dropping, and marks land a beat late. Reconsider only if two-sweep proves
  annoying in a dungeon.
- **Greedy single-sweep — apply at hover in hover order (rejected).** Bypasses the prio auto-sort at
  apply time (skull follows *your hover order*, not the healer), undercutting the DB's whole point.
- **Two-sweep planned apply (accepted).** Full intelligence, fully pre-combat, zero reactive code; the
  double-hover is cheap *out of combat*, where the focus/threat objection that killed in-combat marking
  simply does not exist.

## Consequences

- **Ascension runs a strict subset of the marking model** — the *Strategy* and *Pull-time marking*
  glossary, minus the runtime reactive machinery. Succession and the governor are death-time /
  incremental concepts with no meaning in a single pre-pull pass, so they retire cleanly.
- **The Ascension pre-pull mode *is* Smart Pre-Marking** (pre-fight, pack-aware) — no new glossary
  term. The two-sweep / armed-plan mechanics are implementation and are captured here, not in
  `CONTEXT.md`.
- **The adapter adds exactly one primitive: _identity_** (`Platform.GUID(unit)` — GUID-of-a-unit,
  needed because SuperWoW's GUID-returning `UnitExists` is absent). *Apply* needs **no override** (the
  default `SetMark` is a thin `SetRaidTarget` passthrough that accepts a live token); *read-a-mark* is
  **deferred** (sweep 2 reads occupancy via `GetRaidTargetIndex('mouseover')`, a token read that works
  natively); and the planned `OnUnitDeath` CLEU job is **not needed** for v1.
- **The Ascension apply edge is the one place a platform fn is not GUID-in** — it *receives* the live
  `mouseover` token (the two-sweep calls `Driver_ApplyMark('mouseover', icon)`), the sole documented
  exception to the GUID-in rule in [ADR 0003](0003-one-repo-per-platform-adapter.md). This is realized
  by the polymorphic default `SetMark` accepting a token — **not** by a platform override.
- **On Ascension the two-sweep is the _sole_ batch path.** The classic per-mob batch applies by GUID
  on a ~50 ms-delayed queue — structurally incompatible with ephemeral tokens — so the collect sweep
  always builds the plan regardless of the `SmartMark` toggle (Vanilla-only; inert on Ascension). The
  `CanAutomate` SuperWoW gate is reconciled by a dedicated `requiresSuperWoW` capability (default
  `true`; Ascension `false`), so the single gated apply edge (`Driver_ApplyMark`) is kept on both
  platforms — the drain applies through it with **no Ledger write** (a pure pre-pull reuses no icon).
- **`pullPlan` graduates from ephemeral to durable session state** — it joins `ResetSession`'s clear
  list and the pull-end clear, where on Vanilla it was drained synchronously inside one batch run.
- **Reversibility hedge:** if a dungeon run shows in-combat re-marking or succession is missed, **CLEU
  death-cleanup is the re-entry point** — add it then, informed by real play rather than speculation.

## Amendments

- **2026-07-07 (slice C design grill).** Four implementation specifics were sharpened during the
  slice-C design walk and are corrected in the text above; the core decision (pre-pull planner,
  human-driven two-sweep, armed durable plan) is unchanged:
  - **Sweep 1 snapshots the _name_ only** (not name + creatureType + tier). The DB entry supplies role
    / tier / creatureType / prio, and a live tier/creatureType snapshot is deferred because auto-CC —
    its only consumer — does not fire under the ladder-≥-pack / verbal-CC model.
  - **The adapter's one new primitive is _identity_** (`Platform.GUID`), not "apply + read": apply
    needs no override (the polymorphic default `SetMark` accepts a token) and read-a-mark is deferred
    (no consumer — a token `GetRaidTargetIndex` works natively).
  - **The two-sweep control flow lives in shared Core, gated on `hasScanner`**, not in the Ascension
    overlay — per ADR 0003, only genuinely platform-specific code (the identity primitive) forks; the
    two-sweep uses only shared/localized APIs and is capability-gated *behavior*.
  - **The `CanAutomate` SuperWoW gate is reconciled via a dedicated `requiresSuperWoW` capability**
    (default `true`; Ascension `false`), preserving the single gated apply edge and keeping Vanilla
    byte-identical.

- **2026-07-07 (slice C in-game test).** **Clearing marks is token-bound too — the mirror of the
  marking constraint.** 3.3.5 has no mark-slot token and no "clear all raid targets" API, so no bulk
  clear is possible for the swept (nameplate) pack. Consequently `/tmark reset` on a scanner-less
  platform is a **session/plan reset only** — the physical mark strip (SuperWoW `mark1..8` +
  `ClearUnit`) is gated to platforms with mark tokens, because a partial "clear only what you happen
  to be targeting" is more misleading than none. The world clear is the existing **Ctrl+mouseover**
  unmark, which fires per hover — hold Ctrl and sweep the pack to clear it (the clear-sweep
  counterpart to the Shift mark-sweep). `ResetSession`'s message is made truthful on Ascension.
  (Whether Ascension auto-clears a mark on the mob's death is **untested** and is not relied on or
  claimed anywhere — note Turtle/Vanilla is documented to *retain* marks through death and respawn.)
  (Verified in-game: two-sweep marking works; Ctrl+mouseover is the redo clear; Vanilla unchanged.)

- **2026-07-08 (re-sweep follow-ups).** Three follow-ups on the shipped two-sweep, all
  Ascension-gated (Vanilla byte-identical), grilled against this ADR. The core decision is
  unchanged; a new client fact was discovered.
  - **Raid marks are unique (singleton per icon).** Re-applying an icon a mob *already wears*
    **toggles it off**; applying a live icon to a *different* mob **moves** it (the prior
    holder loses it). Consequence: a **re-sweep must be mark-preserving.** The collect sweep
    now reads each hovered mob's live `GetRaidTargetIndex`; an already-marked mob is
    **skipped and its icon reserved** (fed to `DecidePull` via a new optional `reservedIcons`
    seed), so the plan fills only the free slots around it. Without this the re-sweep
    re-planned from scratch — the seed is blind to physical marks because the two-sweep is
    no-Ledger — and re-applied identical icons, toggling the whole pack off. This mirrors the
    guard Vanilla already had at *apply* time (`ProcessBatchMark` skips already-marked); the
    two-sweep drops `ProcessBatchMark`, so the guard moves to *collect* time. To re-mark
    differently, **Ctrl+mouseover clear first**, then sweep — the clear-sweep is the redo
    affordance.
  - **`ClearMarksForPullEnd` is gated off on scanner-less platforms**, completing the parity
    with `ResetSession` (whose physical strip was already gated in the slice-C in-game
    amendment above). On Ascension this path only ever *disarmed the plan* (that lives at the
    `PLAYER_REGEN_ENABLED` call site); its `mark1-8` strip found no tokens and its
    `Ledger.Clear()` wiped empty tables — an accidental no-op, now an intentional documented
    one. The death-auto-clear question stays **untested and unclaimed** (per the prior
    amendment); this gate makes the code not depend on it.
  - **The two inert config toggles are shown truthfully.** Smart Pre-Marking is forced on (the
    two-sweep is the only batch path) and Auto-CC needs the absent scanner, so both are shown
    **disabled at their effective value** with explaining legends rather than live controls
    that silently do nothing — the same "make the message truthful on Ascension" call as
    `/tmark reset`. Mark Normals stays a live toggle.
  (Verified in-game on Ascension: re-sweeping a marked pack now retains its marks (no
  toggle-off), and a fresh pack marks cleanly after a prior pull with no wedge. Vanilla
  unchanged.)
