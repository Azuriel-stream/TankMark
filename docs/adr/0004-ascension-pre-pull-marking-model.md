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
- **Sweep 1** — Shift+mouseover the pack. Each hover snapshots the live reads (name, creatureType,
  tier) off the `mouseover` token *at hover time* — they cannot be re-read by GUID later — and
  collects the mob. On Shift-release, `DecidePull` runs, the `{guid→icon}` plan is stored **armed**,
  and `ReportPullPlan` announces it.
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
- **The adapter shrinks** to roughly *apply-a-mark (live token)* + *read-a-mark*; the planned
  `OnUnitDeath` CLEU job is **not needed** for v1.
- **The Ascension apply edge is the one place a platform fn is not GUID-in** — it takes the live
  `mouseover` token, the sole documented exception to the GUID-in rule in
  [ADR 0003](0003-one-repo-per-platform-adapter.md).
- **`pullPlan` graduates from ephemeral to durable session state** — it joins `ResetSession`'s clear
  list and the pull-end clear, where on Vanilla it was drained synchronously inside one batch run.
- **Reversibility hedge:** if a dungeon run shows in-combat re-marking or succession is missed, **CLEU
  death-cleanup is the re-entry point** — add it then, informed by real play rather than speculation.
</content>
