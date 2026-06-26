# TankMark Swarm Design (target v0.29+)

**Status:** Slices 0–3 **built** and in-game-verified (remove-TWA, PR #64; pure `SyncCodec`
+ harness, PR #66; control-plane tracer, PR #69; single-marker enforcement, PR #72 — §5.8/§5.9).
Slice 4 (profile-sync) **design ratified** — see §6.1. New swarm code is tagged `[v0.29]`;
`.toc` is `0.27`. The sections below describe the full target; per-slice build status lives in §12.

**Scope note:** This started as roadmap item **#4 (Sync codec tidy-up)** and expanded —
deliberately — into the full **swarm** feature, because the codec's correct shape is
*downstream* of the swarm protocol it must carry. Build the swarm backbone; the codec
falls out of it (the "(3) then (2)" decision). #4 is therefore folded into this doc as the
**Codec** section.

---

## 1. Purpose and value

TankMark coordinates raid/party marking. Today every RL/Assist running TankMark with
automation on is an independent marker — they scan the same mobs and fight over marks
(the theft the Ledger's ownership-verification only *detects after the fact*). The swarm
model replaces that with **one marker (the queen) + many read-only watchers (drones).**

- **Queen** — the single authorized auto-marker for the group at a given moment.
- **Drone** — a TankMark user who does *not* mark; it has **read-only visibility** into the
  plan (who tanks/CCs which mark) and renders it locally.

**Value delivered:**
1. *No mark-fighting* — exactly one client drives `SetRaidTarget`.
2. *Shared situational awareness* — drones see the assignment plan, not just the bare icons.

**What the swarm is NOT (deliberately out of scope):**
- It does **not** stream live marks — drones read physical marks for free (see §6).
- It does **not** sync live runtime ownership (`MarkMemory` etc.) — each client derives locally.
- Mob-DB sharing (`/tmark sync`, the old #4) is a **separate** officer tool, not the swarm
  backbone — but it shares the same transport/codec and the same security guards.

---

## 2. Why this supersedes the original "#4 codec tidy"

The original #4 defect: the TM mob-record wire format is authored in two places with no
shared contract (encoder `Sync.lua:212`, decoder `Sync.lua:141`). Real, but cosmetic on
its own. The grill surfaced that:

- The **drone-visibility** half of the product vision is **unbuilt** — today a non-queen is
  *blind and inert*, not a read-only drone.
- A live-coordination channel will ride the **same** addon-message transport, so the codec
  should be designed as the substrate for *all* swarm messages, not just the `M` record.
- The receive path **silently mutates persistent local state from untrusted input** — a
  security defect (§7) that codec-tidying alone wouldn't fix.

So #4 is reframed: *make the receive path safe and design the codec to the swarm's known
message set*, rather than "tidy the M round-trip."

---

## 3. Glossary

| Term | Meaning |
|---|---|
| **Queen** | The single client currently authorized to auto-mark. |
| **Drone** | A TankMark client that renders the plan read-only; never marks. |
| **Candidate** | An *eligible* client (`CanAutomate` true: SuperWoW + active + permissions + zone profile). Only candidates heartbeat. |
| **Heartbeat** | Periodic presence beat emitted by candidates only (§5). |
| **`amQueen`** | A candidate's self-belief that it is the queen (heartbeat field). |
| **`planVersion`** | Version/hash of the queen's *profile* (heartbeat field) — drones detect staleness against it. |
| **Incumbency stickiness** | A sitting queen is never *automatically* deposed; only ineligibility, departure, or a *manual* handoff moves the crown. |
| **Profile** | `TankMarkProfileDB[zone]`: mark → tank → healers/role. Drives the drone HUD. |
| **Mob DB** | `TankMarkDB.Zones[zone]`: mob → mark/prio/type/class. Drives the *queen's* marking decisions only. |

---

## 4. Architecture: three planes

- **Control plane** (§5) — who is the queen. Election, heartbeat, stickiness, handoff, failover.
- **Data plane** (§6) — what the queen distributes so drones can derive-local.
- **Security** (§7) — consent, trust, blocking; the threat model and its server-gated backstop.

These map onto a **typed-message codec** (§8) and reuse the existing
`Ledger`/`ApplyMarkIntent` "pure core + single apply edge" pattern.

---

## 5. Control plane

### 5.1 Election — deterministic, over a presence heartbeat
The queen is **computed, not negotiated.** Every client independently picks the queen from
the *present, eligible* candidate set by a fixed rule, so all clients agree with **zero
election messages and no race.**

- **Election rule:** highest authority first (leader-preferred), then a deterministic
  tiebreak (lowest player name). Identical inputs (roster + heard heartbeats) → identical
  winner on every client.
- **Why deterministic, not query/timeout:** the original sketch was query-and-timeout
  ("ping leader; if silence, ask who's queen; if silence, self-elect"). Rejected because:
  (a) it has a **self-election race** — simultaneous joiners all see silence and all
  self-elect → multi-queen; (b) addon messages are **unreliable** (throttled, droppable),
  so "silence ⇒ no queen" is an unsafe inference. Heartbeats *repeat*, so a single drop is
  covered by the next beat — robust where a one-shot reply is not.

### 5.2 Heartbeat
- **Senders:** *candidates only* (eligible clients). Drones stay silent and just listen.
  Usually 2–4 candidates in a raid → a trickle.
- **Cadence:** **5s interval, 3-miss threshold** (~15s worst-case detection of an *unclean*
  exit). Clean transitions don't wait for this — see fast-path below.
- **Payload:** `amQueen` + `planVersion`. **Rank is NOT in the payload** — receivers read it
  from the server-authoritative roster (`GetRaidRosterInfo`), which is unspoofable.
  Eligibility is *implicit* (only eligible clients beat). `planVersion` makes the data plane
  self-healing (§6).
- **`amQueen`** is load-bearing: it lets newcomers see the incumbent to respect (stickiness),
  and resolves split-brain — two `amQueen` beats → deterministic tiebreak → one yields.

### 5.3 Incumbency stickiness (pure)
A sitting queen is **never automatically deposed**, even by a higher-authority candidate
appearing later (e.g. the leader becomes eligible after an assist already holds the crown).
The crown moves only via: becoming ineligible, leaving, the heartbeat timeout, or a
**manual handoff**. *(Considered "boundary leader-preference" — auto-defer to the leader
out of combat — and rejected in favour of pure stickiness for simplicity.)*

### 5.4 Correctness backstop + latency fast-path (two layers)
- **Backstop = timeout.** Track last-heard-per-candidate; present while heard within
  `interval × miss`. Present-set change → everyone recomputes (with stickiness). Correct
  even through crashes/DCs.
- **Fast-path = explicit edge messages.** On a *clean* transition the queen sends **resign**;
  an eligible joiner that finds no incumbent sends **claim**. Common transitions are
  near-instant; the timeout only governs the rare *unclean* exit.

### 5.5 Bootstrap (kills the join race)
On join, a candidate **listens ≥1 full heartbeat cycle before it may self-promote.** If it
hears any `amQueen` beat in that window → become a drone (respect the incumbent). Only if
the window passes with no incumbent does it run the compute and possibly claim. Nobody acts
on silence; they act on the collected steady-state.

### 5.6 Manual handoff — queen-only, voluntary
Modelled on **passing raid leadership**: only the **current queen** can hand the crown to a
specific target. *(Considered "any eligible officer can promote/seize"; rejected — it
reopens the multi-queen race and bypasses stickiness. The queen is the single locus.)*

- **Target** is chosen from the **live candidate set** (the heartbeat presence) — you
  cannot pick someone who can't wear the crown.
- **Two-phase ACK:** queen sends *you're-queen* → target asserts `amQueen` + confirms
  eligible → queen drops `amQueen` on seeing it. If the target never confirms, the queen
  **retains** — no marking gap, no dead-end crown.
- **UI:** dropdown populated from live candidates → confirmation dialog.
- **No-addon leader is served by proxy:** the leader directs verbally; the *cooperative
  queen* enacts the handoff. The protocol never needs the leader to hold a button.

### 5.7 Failover
- **Queen vanishes (DC/crash/quit):** heartbeat timeout → deterministic re-election. (This
  is the analog of WoW's "leader offline too long → auto-reassign".)
- **Queen present but AFK (still heartbeating, can't be asked to hand off):** the escape is
  WoW-level — **demote their raid rank** → `CanAutomate` goes false → they stop being a
  candidate → everyone re-elects. No new protocol. The swarm keeps marking via the AFK
  queen's still-running scanner in the meantime.

### 5.8 Ratified mechanics — slice 2 (control-plane tracer)

*Resolved 2026-06-25 in a slice-2 design stress-test. The buildable specifics behind
§5.1–§5.7; the §10 "state machine" and codec-dispatch items are nailed here.*

**Module & shape.** A new `Core/TankMark_Swarm.lua`, loaded **after `Sync.lua`** (it uses
the transport). A **pure election function** + a thin stateful shell, mirroring
`SyncCodec`/`DecideMark` — the election carries **no globals** and is unit-tested off-client
in `tests/`.

**Election as one rule.** §5.1 (election), §5.2 (split-brain), and §5.3 (stickiness) collapse
into a single pure function over the *claimants* — present candidates whose latest beat
asserted `amQueen=true` (self included if asserting):
- **≥2 claimants** → `deterministicMax(claimants)` — split-brain: the tiebreak **overrides**
  stickiness.
- **1 claimant** → that claimant — **stickiness** (the single incumbent is respected, even
  against a higher-rank *non*-claimant).
- **0 claimants** → `deterministicMax(presentCandidates)` — fresh election (bootstrap-resolve
  / failover).

`deterministicMax` = highest roster rank, then lowest name. Stickiness needs **no
stored-incumbent input** — it *is* the 1-claimant branch (the shell keeps `currentQueen` only
for repaint-detection + slice-4 rendering, never as an election input). This converges out of
split-brain deterministically: both queens read the same roster + names → same
`deterministicMax` → **exactly one yields** (never zero → no-queen, never two → persistent
split). Drops only *delay* convergence (beats repeat; the yield is event-driven on receive);
stale in-flight `amQueen` beats are idempotent (the winner keeps winning). The honest cost is
a **blackout flicker** — a third observer that loses the real queen for the full timeout
*must* fail over, then snaps back; inherent, and the 3-miss threshold is the knob that makes
it rare.

**Candidate set — two filters, recomputed each pass:**
- `self` iff `CanAutomate()` — self-presence reads the **gate**, not heartbeats (we never
  hear our own beats).
- each `X≠self` iff `now − lastHeard[X] < interval×miss` **and** `rosterRank(X) ≥ 1`.

Presence (`lastHeard`) and *current* eligibility (roster rank) are **both** filters, and catch
different failures: eligibility drops a **demote/leave instantly** (on `RAID_ROSTER_UPDATE`,
without waiting the timeout); presence drops an **unclean DC** at the timeout.

**Recompute triggers (pure + idempotent → trigger liberally):** the 5s heartbeat tick (also
the *sole* detector of a silent drop-out — the failover backstop), plus heartbeat-receive
(`CHAT_MSG_ADDON`) and `RAID_ROSTER_UPDATE` / `PARTY_MEMBERS_CHANGED`.

**Bootstrap (§5.5 concretized).** The listen-window = the **full timeout (interval×miss ≈
15s)**, symmetric with presence and free because slice 2 marks nothing. During it the
candidate **beats `amQueen=false`** (a visible candidate, not a claimant), defers to **drone**
immediately on any heard `amQueen=true`, else elects when the window closes. Its real job is
*collecting the full present-set so the deterministic election has complete input* — that, not
"wait then self-elect," is what kills the join race. Enter on `CanAutomate()` false→true.

**Heartbeat wire.** Reuses the `TM_SYNC` prefix via `SyncCodec` typed `kind`-dispatch. The `Q`
record carries **`amQueen` only** — rank is read from the roster (unspoofable), never sent;
**`planVersion` is omitted until slice 4** and `Q`-decode tolerates trailing fields so slice 4
adds it without a wire break. Send = one 5s `OnUpdate`, `CanAutomate()`-gated (candidates
only), via the existing `QueueMessage` throttle (the 3-miss threshold absorbs any delay behind
a mob-sync burst).

**Display (the deliverable).** (1) HUD **status line** = the elected **queen's name** + your
role, rendered in *both* the profiled and `NO PROFILE LOADED` states — the name is the
consensus-agreement signal you eyeball across the raid; (2) a `DebugEnabled`-guarded **`SWARM`
debug category** logging recompute inputs/output/transitions — the primary live acceptance
instrument; (3) a **chat notice debounced ≥1 cycle** to survive the blackout-flicker.

**Scope boundary (the keystone invariant).** Slice 2 touches **none** of `CanAutomate`,
`Driver_ApplyMark`, the scanner, or `ProcessUnit` — marking stays byte-for-byte today's
behavior. And today already *adopts and respects* an existing valid mark (`ProcessUnit` reads
`GetRaidTargetIndex`, verifies the server-side `mark` token, then returns **without**
overwriting), so a slice-2 **DRONE does not stomp the queen's marks**. The residual conflicts
slice 3 removes are narrow: the same-tick race on an *unmarked* mob, and divergent decisions
across clients (notably `getFreeTankIcon()` reading each client's *local* Ledger). The tracer
+ `SWARM` log let you **measure** how often those actually fire before committing to the
slice-3 flip.

**Degenerate cases.** Party (not raid): `HasPermissions` = `IsPartyLeader`, so the leader is
the **only** candidate — forced queen, no tiebreak, no party-rank source needed. Solo: sole
self-candidate. No special-casing; the 15s solo bootstrap delay is cosmetic and left as-is.

### 5.9 Ratified mechanics — slice 3 (single-marker enforcement)

*Resolved 2026-06-25 in a slice-3 design stress-test. The buildable specifics of the
automation-gate flip — the one slice that changes marking behavior, acting on slice 2's
now-verified queen.*

**The core move: split candidacy from active-marking.** Slice 2 conflated the two —
`Swarm.SelfIsCandidate()` literally returns `CanAutomate()`. Folding a queen-check *into*
`CanAutomate()` would therefore poison the election: a non-queen's `CanAutomate()` would go
false → it drops out of `SelfIsCandidate` → out of the present-set → **out of the failover
pool**, so when the queen dies there is no one left to elect. The two concepts must separate:

- **`CanAutomate()` — UNCHANGED.** Remains the *candidacy / eligibility* gate (SuperWoW +
  active + permissions + zone profile). `SelfIsCandidate` keeps reading it, so the **candidate
  set and failover pool are byte-for-byte preserved.** This is the safety crux.
- **`ShouldDriveMarks()` — NEW**, in `Permissions.lua` beside `CanAutomate`:
  `CanAutomate() and (not Swarm.IsRunning() or Swarm.selfAmQueen)`. **Fail-open**: if the
  election subsystem isn't running, degrade to today's "eligible clients mark" rather than go
  silent — the swarm is an enhancement over a working baseline, and the §7 server rank-gate is
  the real safety backstop (worst case without coordination is transient mark-fighting, not
  danger). A total marking blackout from a swarm bug is the worse regression.
- **`Swarm.IsRunning()` — NEW** accessor (`Swarm.frame ~= nil`) so `Permissions` reads swarm
  liveness without poking internals.

**No circular dependency:** `ShouldDriveMarks` reads the *stored field* `selfAmQueen`;
`selfAmQueen` is computed in `Recompute` from `SelfIsCandidate → CanAutomate` (the *unchanged*
gate). Nothing reads `ShouldDriveMarks` back. The fail-open also never fires in a healthy
client: `InitSwarm` runs whenever `IsSuperWoW`, and `CanAutomate()` *requires* SuperWoW — so
whenever marking is possible the frame exists and `selfAmQueen` governs.

**The gate migration — slice 3's actual diff.** The real audit target is *every* world-mark
`SetRaidTarget` write, not just the `CanAutomate` call sites:

- **`CanAutomate → ShouldDriveMarks` (7 sites):** scanner top gate (kept *inside* the
  recorder bypass — recording still works), the three Death paths (`HandleCombatLog`,
  `HandleDeath`, `UnmarkUnit`), both Batch guards (manual Shift+mouseover is gated to the
  queen, with a swarm-aware abort message), and `Driver_ApplyMark`'s internal backstop (the
  authoritative sole-edge enforcement point — even a stray caller can't make a drone mark).
- **`HasPermissions → ShouldDriveMarks` (the §11 holes the audit surfaced):**
  `ClearMarksForPullEnd` — **the critical one: it is *automatic* (PLAYER_REGEN, alive), so
  un-gated every drone races to strip the queen's marks the instant combat ends** — and the
  **physical-strip loop only** inside `ResetSession` (the local-state reset above it stays
  ungated, so `/tmark reset` on a drone clears local state without stripping the group's world
  marks). **[build, PR #72]** the audit during the build surfaced a *third* site this list
  originally missed: **`ReviewSkullState`** records skull ownership (`RegisterMarkUsage`)
  *before* `Driver_ApplyMark`, so it reaches `SetRaidTarget` indirectly and didn't show in the
  direct-write grep. All its callers are already `ShouldDriveMarks`-gated, but its own gate was
  tightened too (defense-in-depth, so a non-queen can never record a phantom drone-Ledger
  skull). Net migration: **7 `CanAutomate` + 3 `HasPermissions` = 10 gates.**

**Deliberately untouched:** `CanAutomate` body · `SelfIsCandidate` (candidacy) · `BroadcastZone`
(data-plane sync eligibility, not a marking edge) · `ResetSession`'s local-state reset · the
HUD `SetRaidTargetIconTexture` calls (texture draw, not world marks) · the **NUCLEAR startup
wipe** (`TankMark.lua`) — it runs at load *before* the election (so `selfAmQueen` is always
false then; gating it would simply break ghost-mark cleanup), a reloading drone briefly wiping
marks is self-healing (the queen re-marks next tick); it predates the swarm and is an
out-of-scope wart for its own later treatment.

**Why this finally enforces §11.** Slice 2's scope-boundary note observed a DRONE already
*adopts and respects* a valid mark (it doesn't stomp). Slice 3 closes the remaining writes: a
drone now does **zero** scan work (gate at the scanner top, not just the apply — matching "a
drone is a passive renderer, no scanner"), cannot manually mark, and cannot auto-strip at
pull-end or via `/tmark reset`. "Drones have no path to `SetRaidTarget`" becomes literally true
(modulo the consciously-parked NUCLEAR wipe).

**Accepted behavioral consequences.**
- A **~15s cold-start gap** (whole group logs in at once → all bootstrap → no auto-marking
  until the election settles). Invisible in practice: the scanner only runs in a group and has
  no hostiles to mark during pull-prep. Crucially **failover does *not* re-bootstrap** —
  losing the queen drops `claimants` to 0 → a *fresh election* over the already-present
  candidates → near-instant new queen, no 15s gap.
- A drone's **8-row HUD mark grid is blank until slice 4** (it stops scanning; derive-local
  render arrives in slice 4). The slice-2 status line ("DRONE — Queen: X") and the queen's
  actual on-mob icons remain visible — a coherent interim state, consciously scoped.
- A **recorder-active drone records mob data but places no marks** (the backstop at
  `Driver_ApplyMark`); recording, a data-collection task, stays fully available to anyone.
- A **dead-but-unreleased queen keeps marking** (no alive-check is added — a corpse can still
  target). A queen **released to the graveyard** is a *known parked gap* (present + heartbeating
  but can't usefully target) — same shape as the AFK-but-present queen, escape is the WoW-level
  rank-demote → auto-reelect; not solved here.

**Verification (this is *the* behavior-flip slice — in-game, 2-box minimum).** Queen marks /
drone silent · manual Shift+mouseover on drone suppressed · recorder on drone records-not-marks
· **pull-end: only the queen clears** · **failover: demote/remove the queen → drone promotes &
starts marking with no 15s gap** · `/tmark reset` on a drone keeps the queen's world marks
intact · dead-unreleased queen keeps marking. The `SWARM` debug category remains the live
instrument. New code tags `[v0.29]`; `.toc` stays `0.27` (release bump owed). **Naming:** the
new gate is `ShouldDriveMarks()`.

---

## 6. Data plane — derive-local

Drones reconstruct the live HUD **locally** from a synced static plan ⊕ free game state.
*(Considered streaming live assignments from the queen; rejected — the transport is
throttled to 1 msg/0.3s, so per-tick streaming is infeasible anyway, and most of the data
is already free.)*

A drone's HUD decomposes into three tiers by how each part is obtained:

| HUD element | Source | Cost |
|---|---|---|
| Who tanks/CCs each mark | the **profile** (mark→tank/role) | **sync once** |
| Which mob holds a mark *now* | physical raid icon, visible in-world (`UnitName("markN")`) | **free** |
| Queen's runtime deviations | queen session state | **live delta (deferred)** |

Tier 2 is dropped from the drone's concern entirely — the game renders the icons; a drone
re-printing "skull = ⟨mob⟩" just restates what's on screen, and a pure drone has no internal
use for a mark→mob map (it doesn't mark/decide/run a Ledger). Consequence: **a drone is a
passive HUD renderer** — likely runs *no scanner* and has *no path to `SetRaidTarget`*; it
re-renders on (profile received / delta received / zone change).

### 6.1 Profile sync — the actual drone-visibility enabler  *(slice 4 — RATIFIED 2026-06-26)*
The profile is **TankMark-native** (built by the queen in the Profiles tab) and, today,
**never synced** to other clients — that's the missing piece. The queen pushes it so drones
can render, filling the 8-row HUD mark grid that slice 3 intentionally left blank for
non-queens. *(The TWA inbound profile-feed is **removed** — slice 0, §9 — so the profile has
exactly one writer: the queen.)*

**Storage — single-slot overwrite, queen is sole writer.** A drone applies a received
snapshot by overwriting `TankMarkProfileDB[<zone>]` directly — the same per-character slot the
player edits — with **no separate drone cache and no backup.** Consequence: the existing HUD
render, `sessionAssignments`, and the promotion-marking path all read this slot unchanged, so a
promoted ex-drone marks off *exactly* the plan it was displaying (**display == enactment**).
*Rejected — a runtime-only display cache:* it diverges from the marking plan at the moment of
promotion (the HUD the raid trusted ≠ the marks that land) and evaporates on a temp-queen
`/reload`. *Why no backup / no consent:* team profiles are **operational, rebuilt per run**
(roster churns; the RL sets assignments right before the first pull; ≤8 entries), so the
overwritten draft is disposable — unlike the curated Mob DB. This **carves the profile out of
§7's consent rule:** the queen is an *elected, server-rank-gated authority* you've already
delegated marking to, whereas the Mob DB has no single authority and keeps offer→accept +
snapshot. The overwrite is scoped to the *pushed* zone — other zones' profiles are untouched.

**Refresh — pull-driven; `planVersion` is a counter, not a hash.** A single **global,
runtime-only** monotonic `planVersion` is bumped on every `SaveProfileCache` while `amQueen`
and advertised on the `Q` heartbeat (the first new heartbeat field; slice-2 decode already
tolerates it). Each drone records the **`(queenName, planVersion, zone)`** key it last applied.
The queen **pushes** the current-zone snapshot on Save (the fast path — `SaveProfileCache` is
the sole commit point of the cache→commit edit flow, so mid-edit state never leaks; *Save is
the debounce*). A drone **pulls** — sends `PR;<zone>`, the queen *broadcasts* the snapshot —
whenever its computed `(currentQueen, heardVersion, currentZone)` ≠ its applied key. That one
predicate covers every case: mid-run edit, late join, failover (queen changes), dropped push
(version advanced), zone change (zone differs), and queen `/reload` (counter resets —
*inequality*, not `>`, so a reset still forces a refetch). *Runtime-only suffices* — the
trigger is inequality, so persistence buys nothing. *Storm control:* a mismatch sets a
`needPull` flag that fires one request on the next 5 s tick, and the queen's broadcast response
clears every drone's flag, so a queen-reload that mismatches the whole raid resolves in one
request + one response. *Global, not per-zone:* one integer rides the heartbeat; editing a
different zone causes a redundant (harmless) refetch of the current zone.

**Wire — HUD-minimal, one atomic message.** The push carries `mark + tank + role` **only**,
encoded as a single `P;<zone>;<planVersion>;<m>,<tank>,<role>;…` message (role as a 1-char
`T`/`C`). At ≤8 entries this is ~160 chars — always within the ~255 cap — so it is **one atomic
message**: the drone replaces the whole zone in one apply, which makes **deletions free** (an
absent mark is gone) and needs **no framing / completeness logic.** *Healers are deliberately
omitted* — they are never rendered in the HUD (only `Announce Assignments` reads them), and
including them overflows one message (~300+ chars), forcing multi-part framing. **Deferred
follow-up:** when the reliable large-message / chunked transport is built (its **own** slice,
at/before Mob-DB-sharing slice 7, designed against Mob DB's real consent + scale requirements —
*not* bundled into slice 4), revisit profile sync to carry healers at full fidelity, so a
promoted ex-drone queen's repeated re-announces include healer assignments. (Single-message
profile is the degenerate 1-part case, not a throwaway the chunker replaces — no double-build.)

**Trust + empty semantics.** A `P` is applied **only from the drone's own
`Swarm.currentQueen`** (stronger than the rank ≥ 1 `IsTrustedSender` baseline): `P`
auto-applies, so without this any assist could overwrite every drone's HUD and future-marking
plan. Robust under split-brain — each drone follows *its* elected queen and the election
converges. A `PR` is **coalesced** (one broadcast per zone per tick, however many drones ask)
and the queen answers it **even when it has no plan.** **Empty snapshot → keep current**
(non-empty replaces; empty is ignored): replacing a plan with nothing is wrong in the case that
matters — a failover to an unprepared queen would blank every drone mid-run while the previous
queen's marks are still physically on the mobs. **Known limitation:** an intentional *full-zone*
clear (Reset / Delete-whole-zone) therefore does not propagate — rare, since a real re-plan is a
non-empty Save, which does. *Deferred option if ever needed:* distinguish a solicited
(`PR`-response) empty → keep from an unsolicited (pushed) empty → clear, plus a Reset/Delete push
hook; not worth the extra concept for slice 4.

**Render + apply seam.** **No new HUD render path** — the overwrite makes the existing
`UpdateHUD` / `RenderHUDRow` show the plan natively (tanks from `sessionAssignments`; the empty
`Ledger.NameFor` fallback never fires on a drone; normal TANK / CROWD CONTROL sectioning). The
drone applies via a shared **`ApplyProfileToSession(zone)`** seam factored out of
`SaveProfileCache` (rebuild `sessionAssignments` + `UpdateHUD`, *without* the Print /
dropdown-read / `UpdateProfileList`, and *without* marking — which stays behind
`ShouldDriveMarks`, failed by a drone). The live "which mob holds each mark right now" overlay
is **dropped entirely** — drones see physical marks on the game screen; the HUD's only job is
*who tanks / CCs what.*

**Edges.** Drone-side profile editing stays **enabled** — a drone's local Save writes its own
slot but, being `not amQueen`, neither bumps `planVersion` nor pushes, and the next queen push
overwrites it; UI-gating the Profiles tab on swarm role is deferred. The **recorder runs on
drones** unchanged (the slice-3 bypass; it records the Mob DB and never marks) — a "you're queen
now but still recording" prompt belongs to the **slice-5 promotion event**, not here. Queen and
solo render paths are **byte-identical** to today.

**Net new protocol surface:** two message types — `P` (profile snapshot, queen→drones) and `PR`
(pull-request, drone→queen) — plus one `Q` heartbeat field (`planVersion`).

### 6.2 Mob DB sharing — opt-in, at handoff only
The Mob DB drives the *queen's* marking only; drones never need it for the HUD. So it is
**not** auto-pushed. It is an **optional attachment to a handoff**:

- **Default OFF**, scoped to the **current zone** (the motivating case is "hand off *because*
  the new queen has the better DB" — don't clobber it).
- Recipient gets **accept/reject** with an overwrite warning that **names the zone**
  ("Your Mob DB for ⟨Zone⟩ will be replaced").
- **Snapshot before overwrite** (reuse `TankMarkDB_Snapshot`) — an accidental Accept is
  recoverable.
- **Role and DB are decoupled** — rejecting the DB does *not* reject the role; the role
  transfers like leadership, the DB is the only consent point.

### 6.3 No deltas anywhere
Full snapshots throughout. Profile is too small to bother; Mob DB pushes too rarely to bother.

---

## 7. Security model

The untrusted-cross-client surface (`/security-review`-worthy). **Run a security pass when built.**

### 7.1 Threat model and the bounding backstop
- Sender identity is **server-set** (the `CHAT_MSG_ADDON` sender arg) — unspoofable.
- The realistic attacker is a **ranked insider** (assist+ in your own group); in pugs that's
  a low bar. A *modified* client can craft arbitrary well-formed `M;<zone>;<mob>;…` messages
  for any zone/mob, ignore the throttle, and **poison/bloat** the DB (no delete path exists,
  so it's corruption + junk-injection, not literal erase).
- **Bounding backstop:** the one privileged operation — `SetRaidTarget` — is **server
  rank-gated.** A rank-less griefer can pollute comms and try to mutate *local* state, but
  can **never actually place a mark.** So defenses only need to protect *persistent local
  state* (the data plane), not marking itself.
- **Key principle:** you cannot stop a malicious client from *sending*; you can only control
  what your client *does with it*. **Guards live on the receiver.**

### 7.2 offer → accept (consent), not push → auto-apply
All incoming **mob-DB writes** (broadcast *and* handoff) are **offers**, applied only on the
user's click. *(Originally leaned "broadcast stays authoritative, silent overwrite is fine";
reversed once the benevolent-sender assumption was dropped.)*

- Prompt: "PlayerX offers their ⟨Zone⟩ Mob DB — Accept / Reject / Always-trust PlayerX".
- **One pending offer per sender** (rate-limit) so it can't become popup-DoS.
- Snapshot before any accepted apply (§6.2).

### 7.3 Per-player trust axis (one structure, not two lists)
Block and "always-trust" are the two ends of **one** per-player setting:

- **Blocked** → dropped at the filter, never processed.
- **Neutral** (default) → offer→accept prompt.
- **Trusted** → auto-accept, no prompt.

Precedence **Blocked > Trusted > Neutral**. Stored **account-wide**, keyed by **player name**.

### 7.4 Scoped block (data-plane only)
A block suppresses the sender's **mutating/data-plane** messages and offers — but **keeps
observing their election heartbeat.** *(Considered total block; rejected as default because
election is a **consensus protocol** — locally censoring a candidate's heartbeat can
fracture the shared candidate set and, for an *eligible* blocker, cause a split-brain second
queen. The marks are server-truth and visible regardless, and a rank-less actor can't mark
anyway, so there's no safety need to censor the control plane.)*

---

## 8. Codec (the folded-in #4)

The protocol's known message set, to be single-sourced in a **typed-message codec**:

| Type | Plane | Direction | Notes |
|---|---|---|---|
| `M` mob record | data | TM↔TM | exists today; the coupled-at-a-distance round-trip to single-source |
| `P` profile snapshot | data | queen→drones | slice 4 (§6.1) — HUD-minimal (`mark+tank+role`), one atomic message; healers deferred |
| `Q` heartbeat | control | candidate→all | `amQueen` + `planVersion` (slice 4); slice-2 wire is `amQueen`-only — see §5.8 |
| resign / claim | control | candidate→all | clean-transition fast-path |
| handoff offer / ACK | control | queen↔target | two-phase, optional DB attachment |
| `PR` pull-request | data | drone→queen | slice 4 (§6.1) — `(queen,planVersion,zone)`-mismatch refetch; queen broadcasts the response |

**Architecture (mirror `Ledger`/`ApplyMarkIntent`):**
- The **codec is pure** — decode → validate → **reject malformed** → return a structured
  record. No WoW/Ledger/session state. Lives in a **new `Core/` file that is
  definition-only** (so the off-client `tests/` harness can `dofile` it, unlike `Sync.lua`
  which runs `CreateFrame` at top level).
- A **single DB-apply edge** enforces *policy* — consent (§7.2) + snapshot — i.e. **rejects
  *unwanted*** input. Same shape as the mark pipeline: pure decision/codec, one guarded edge.
- The codec is the ideal next target for the **`tests/` harness** (pure string↔record).
- **TWA integration is removed** (slice 0) — there is no second dialect; the codec is
  *purely* TM. The old `HandleTWABW`, `TWA_MarkMap`, `TWA_BW_PREFIX`, and the `TWABW`
  dispatch branch are deleted.

**Existing bare-global cleanups to fold in while here:** `Sync.lua:169` uses bare
`CreateFrame`, `:179` bare `SendAddonMessage` — both are in `Locals` (`L._CreateFrame`,
`L._SendAddonMessage`); route them through `L._` per the CLAUDE.md rule.

---

## 9. Open decisions

**Resolved during design:**
- ~~TWA vs TM profile-sync precedence~~ → **TWA support is being DROPPED entirely** (slice 0).
  One profile writer (queen-native) ⇒ no precedence rule, no source-tagging, no TWA-lock
  toggle needed. Bonus: removes an untrusted inbound parser (smaller §7 surface) and
  collapses the codec to pure-TM (§8). Rationale: niche feature (added for one RL); the
  swarm's profile-sync is a strict upgrade over the TWA import (one-person entry,
  auto-distributed to all drones — TWA only ever reached other TWA users). Reversible from
  git history if ever needed (cf. the Static-GUID removal). Build-time check: confirm shared
  helpers (e.g. `InferRoleFromClass`) aren't TWA-only before pulling them.

- ~~Build slicing~~ → **slice sequence locked — see §12.**

**All design forks are now resolved.** Remaining work is execution (§12) plus the mechanical
detail items in §10 (state machine, `planVersion` mechanics, per-type wire encoding), which
get nailed *within* their owning slice rather than up front.

---

## 10. Still to design (mechanical — recommendations exist, need ratifying)

- ~~**Drone-mode state machine**~~ → **RATIFIED in slice 2 (§5.8):** role is *derived*, not a
  stored FSM (queen / drone / bootstrapping fall out of the `amQueen`-claim set + candidacy +
  the listen-window); scanner suppression is **slice 3**, not here; the read-only HUD indicator
  and the debounced (≥1 cycle) transition notice are specified.
- ~~**`planVersion` mechanics**~~ → **RATIFIED in slice 4 (§6.1):** a single **global,
  runtime-only counter** (not a hash) bumped on every `amQueen` `SaveProfileCache` and carried
  on the `Q` heartbeat; the drone keys on `(queenName, planVersion, zone)` and pulls via `PR` on
  mismatch (queen broadcasts). Single-slot overwrite of `TankMarkProfileDB[zone]`; empty keeps;
  healers deferred to the chunked-transport slice.
- ~~**Codec encoding detail**~~ → **partially ratified (§5.8):** the `Q` heartbeat rides the
  `TM_SYNC` prefix via `SyncCodec` typed `kind`-dispatch (`amQueen` only). Per-type detail for
  the later message types still evolves with their owning slices.

---

## 11. Invariants to preserve

- Exactly **one queen** auto-marking at a time (no *silent* multi-queen). Manual/contended
  cases resolve via deterministic tiebreak.
- **Candidacy and active-marking are distinct gates** (slice 3, §5.9): `CanAutomate()` =
  eligibility (drives the election / failover pool, unchanged), `ShouldDriveMarks()` = the
  queen-only marking gate. Folding the queen-check into `CanAutomate` would collapse the
  candidate set and break failover.
- The codec stays **pure**; all *state mutation* goes through guarded apply edges.
- `SetRaidTarget` remains the **sole** marking edge (`Driver_ApplyMark`), server-rank-gated.
- Drones have **no** path to `SetRaidTarget` — enforced (slice 3) across *all* world-mark
  writes: the scanner, manual batch, the death paths, **and** the automatic pull-end clear /
  `ResetSession` strip (the last two were only rank-gated before). The load-time NUCLEAR wipe
  is the one consciously-parked exception (runs pre-election; self-healing).
- Receiver never mutates persistent local state (`TankMarkDB`/`TankMarkProfileDB`) from
  unsolicited network input without consent + snapshot.

---

## 12. Build slices (locked order)

Cadence: tiny reload-verified commits — deploy to network, test in-game, then commit.
Guiding principle: **de-risk the novel consensus logic early, and never bundle a risky
behavior-flip with anything else.** The detail items in §10 are designed *within* the slice
that owns them.

| # | Slice | Delivers | Risk / verify |
|---|---|---|---|
| **0** | **Remove TWA** | One profile writer; smaller codec + security surface | Pure deletion. Verify: loads clean, no TWA writes, existing profiles intact. Check `InferRoleFromClass` isn't TWA-only first. |
| **1** | **Codec skeleton + harness** | Pure, definition-only `Core/TankMark_SyncCodec.lua` carrying the existing `M` round-trip; `tests/` specs | **Behavior-identical** refactor (the original #4). Zero protocol risk. Verify: marks/sync unchanged in-game; specs green off-client. |
| **2** | **Control-plane tracer (display-only)** | Heartbeat (`Q`) + deterministic election + stickiness + failover, **computing & displaying** queen/drone only | **No marking behavior change.** The keystone — validates the hard consensus logic live (races, failover, AFK-demote) at zero marking risk. |
| **3** | **Single-marker enforcement** (ratified §5.9) | New `ShouldDriveMarks()` gate (`CanAutomate ∧ (¬swarm ∨ selfAmQueen)`, fail-open); `CanAutomate` unchanged (candidacy/failover preserved). Migrates 7 marking sites + the audit-found pull-end-clear / `ResetSession`-strip from `HasPermissions`. | The **one** slice flipping marking behavior — isolated. Acts on slice 2's verified queen. Closes the §11 `SetRaidTarget` holes; in-game 2-box verify (queen marks / drone silent / failover / pull-end). |
| **4** | **Profile-sync** | Push-on-Save + `planVersion` pull; drones render the queen's plan | Drone-mode render path; the actual *visibility* payoff. |
| **5** | **Manual handoff** | Queen-only, two-phase ACK, dropdown UI; failover polish | §5.6/§5.7. |
| **6** | **Security hardening** | offer→accept consent + trust axis + scoped block | **Its own slice = its own `/security-review`.** |
| **7** | **Mob-DB-at-handoff** | Opt-in DB attachment, accept/reject + snapshot | §6.2. |

**Ordering rationale:** the codec (slice 1) is low-risk and foundational, so it comes first
as the substrate; the *display-only* tracer (slice 2) puts the novel election/heartbeat in a
real raid before any behavior depends on it; the automation-gate flip (slice 3) is isolated;
data plane (4) and handoff (5) layer on; security (6) is reviewable in isolation; the bulky
opt-in DB attach (7) lands last.

**Build status (2026-06-25):** slices **0** (remove TWA, PR #64), **1** (codec + harness,
PR #66), and **2** (control-plane tracer, PR #69) are shipped and in-game-verified. Slice 2
landed in three harness-checkpointed commits — pure election core (`Core/TankMark_Swarm.lua`:
`ElectQueen`/`ComputePresence`/`DeriveRole`, §5.8) + `Q` heartbeat in the codec, then the
runtime shell (beat frame / roster build / bootstrap / `Recompute`), then the HUD status line
+ debounced chat notice. The deterministic election held live: exact 15s bootstrap windows,
correct party-leader DRONE deference, no double-queen. **Display-only confirmed** — no marking
path was touched. **Slice 3 (single-marker enforcement) is shipped and in-game-verified
(PR #72, §5.9)** — the candidacy/active-marking split (`ShouldDriveMarks()`, fail-open), the
**10-gate** migration (7 `CanAutomate` + 3 `HasPermissions`: automatic pull-end clear,
`ResetSession` strip, and the build-found `ReviewSkullState` record-before-apply path), with
the NUCLEAR wipe consciously left alone. 2-box live: queen marks / drone silent / DRONE
deference (queen=Frostkeg) / failover reclaim with no gap; harness 75/0. **Slice 4 (profile-sync)
design is ratified (§6.1, 2026-06-26):** single-slot overwrite of `TankMarkProfileDB[zone]`
(queen sole writer, no backup, profile carved out of §7 consent), pull-driven global runtime
`planVersion`, HUD-minimal atomic `P` push + coalesced `PR` pull, empty-keeps; net new surface =
`P`/`PR` message types + a `planVersion` heartbeat field. **Next action: build slice 4** in
reload-safe checkpoints.
