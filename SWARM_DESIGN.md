# TankMark Swarm Design (target v0.29+)

**Status:** Slices 0–1 **built** and in-game-verified (remove-TWA, PR #64; pure `SyncCodec`
+ harness, PR #66). Slice 2 (control-plane tracer) **design ratified** — see §5.8. New swarm
code is tagged `[v0.29]`; `.toc` is `0.27`. The sections below describe the full target;
per-slice build status lives in §12.

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

### 6.1 Profile sync — the actual drone-visibility enabler
The profile is **TankMark-native** (built by the queen in the Profiles tab) and, today,
**never synced** to other clients — that's the missing piece. The queen pushes it so drones
can render. *(The TWA inbound profile-feed is **removed** — slice 0, §9 — so the profile has
exactly one writer: the queen.)*

- **Trigger:** on **Save Profile** (`SaveProfileCache` in
  `UI/Config/Profiles/TankMark_Config_Profiles_Logic.lua`). Profile editing uses a
  cache→commit pattern; `SaveProfileCache` is the *only* commit point, so mid-edit state
  never gets pushed. *No debounce needed — Save is the debounce.* Push gated on `amQueen`;
  bump `planVersion` here.
- **Form:** full **zone snapshot** (≤8 entries — too small for deltas).
- **Backstop:** a drone whose stored `planVersion` ≠ the queen's heartbeat `planVersion`
  **pulls** a fresh copy. Covers dropped pushes *and* a freshly-promoted queen (drones
  converge without waiting for the next Save).

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
| profile record | data | TM→drones | new — the drone-visibility artifact |
| `Q` heartbeat | control | candidate→all | `amQueen` (+ `planVersion` from slice 4; slice-2 wire is `amQueen`-only — see §5.8) |
| resign / claim | control | candidate→all | clean-transition fast-path |
| handoff offer / ACK | control | queen↔target | two-phase, optional DB attachment |
| pull-request | data | drone→queen | `planVersion`-mismatch refetch |

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
- **`planVersion` mechanics:** exactly what it hashes (the zone profile), and the
  pull-request round-trip. *(Still open — owned by slice 4; the slice-2 `Q` wire omits the
  field and decode tolerates its later addition.)*
- ~~**Codec encoding detail**~~ → **partially ratified (§5.8):** the `Q` heartbeat rides the
  `TM_SYNC` prefix via `SyncCodec` typed `kind`-dispatch (`amQueen` only). Per-type detail for
  the later message types still evolves with their owning slices.

---

## 11. Invariants to preserve

- Exactly **one queen** auto-marking at a time (no *silent* multi-queen). Manual/contended
  cases resolve via deterministic tiebreak.
- The codec stays **pure**; all *state mutation* goes through guarded apply edges.
- `SetRaidTarget` remains the **sole** marking edge (`Driver_ApplyMark`), server-rank-gated.
- Drones have **no** path to `SetRaidTarget`.
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
| **3** | **Single-marker enforcement** | Eligible non-queen yields to the queen (the automation-gate flip) | The **one** slice touching `CanAutomate`/`Driver_ApplyMark` behavior — isolated & small. Acts on slice 2's verified queen. Security-adjacent. |
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
path was touched. Slices **3–7 are unchanged. Next action: build slice 3** (single-marker
enforcement — the isolated `CanAutomate`/`Driver_ApplyMark` flip, acting on slice 2's verified
queen).
