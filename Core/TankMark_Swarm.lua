-- Swarm control plane: queen/drone consensus (SWARM_DESIGN.md sec.5).
--
-- [v0.29] Swarm slice 2 -- control-plane tracer (DISPLAY-ONLY). This slice
-- computes & displays who the queen is; it changes NO marking behavior (it does
-- not touch CanAutomate / Driver_ApplyMark / the scanner / ProcessUnit). See
-- SWARM_DESIGN.md sec.5.8 for the ratified mechanics.
--
-- File shape mirrors the SyncCodec/Sync split: THIS section is the PURE election
-- core -- deterministic, no WoW state, no frame, no top-level execution -- so the
-- off-client tests/ harness can dofile it (the runtime shell that builds the
-- heartbeat frame, manages lastHeard, and paints the HUD is added in the next
-- checkpoint, behind a deferred InitSwarm). The election reads the world only
-- through plain-table arguments (presentCandidates, claimants, roster), exactly
-- like DecideMark reads through its board -- so its logic is fully unit-testable.

if not TankMark then return end

local L = TankMark.Locals

TankMark.Swarm = {}
local Swarm = TankMark.Swarm

-- ==========================================================
-- TUNABLES (SWARM_DESIGN.md sec.5.2 / sec.5.5)
-- ==========================================================
-- Candidates beat every INTERVAL seconds; a candidate unheard for
-- INTERVAL*MISS seconds is treated as absent. The bootstrap listen-window is the
-- same INTERVAL*MISS, symmetric with the presence timeout.
Swarm.HEARTBEAT_INTERVAL = 5
Swarm.MISS_THRESHOLD     = 3
Swarm.PRESENCE_WINDOW    = Swarm.HEARTBEAT_INTERVAL * Swarm.MISS_THRESHOLD -- 15s

-- [v0.29] Grace for a TRANSIENT self-candidacy loss. CanAutomate()'s HasPermissions()
-- leg reads IsPartyLeader(), which the 1.12 client momentarily returns FALSE for around
-- the combat-end boundary even for the real party leader (confirmed in-game: a ~0.9s
-- perms blip). A candidacy loss shorter than this window is treated as a blip and does
-- NOT depose the queen / re-arm bootstrap (see Recompute). Must exceed the observed blip
-- yet stay well under PRESENCE_WINDOW so a GENUINE demote still fails over promptly.
Swarm.CANDIDATE_GRACE    = Swarm.HEARTBEAT_INTERVAL -- 5s

-- [v0.29] slice 5a.3 handoff TTLs (SWARM_DESIGN.md sec.5.10). Ordered
-- CLAIM(20) > PRESENCE(15) > OFFER(10): the target's claim must outlive the queen's
-- presence window so a queen-DC mid-handoff resolves as the target inheriting the
-- crown, not a fresh DeterministicMax fallback to some bystander.
Swarm.HANDOFF_CLAIM_TTL  = 20  -- target: pendingClaim lifetime
Swarm.HANDOFF_OFFER_TTL  = 10  -- queen:  pendingHandoffTarget lifetime

-- ==========================================================
-- PURE ELECTION CORE
-- ==========================================================

-- Deterministic winner among a set of candidate names: highest roster rank, then
-- lowest name (Lua '<' byte order, consistent across clients). roster is
-- { [name] = rank }; a name absent from the roster sorts below any ranked name.
-- Returns the winning name, or nil if the set is empty. Pure -- order of the
-- input array does not affect the result (it is a max), so a pairs-built array is
-- safe to pass.
function Swarm.DeterministicMax(candidates, roster)
    local best, bestRank = nil, nil
    for i = 1, L._tgetn(candidates) do
        local name = candidates[i]
        local rank = roster[name] or -1
        if best == nil
            or rank > bestRank
            or (rank == bestRank and name < best) then
            best, bestRank = name, rank
        end
    end
    return best
end

-- The elected queen, driven by the set of amQueen=true claimants among the
-- present candidates (SWARM_DESIGN.md sec.5.8). One rule unifies election,
-- stickiness, and split-brain resolution:
--   >=2 claimants -> split-brain: deterministicMax(claimants) -- tiebreak OVERRIDES
--                    stickiness, so exactly one of two self-declared queens wins.
--    1 claimant   -> stickiness: the lone incumbent is respected, even against a
--                    higher-rank NON-claimant that appeared later.
--    0 claimants  -> fresh election over all present candidates (bootstrap-resolve
--                    or failover).
-- Pure: claimants is a subset of presentCandidates; both are name arrays; roster
-- is { [name] = rank }. Returns the queen name or nil (no present candidate).
function Swarm.ElectQueen(presentCandidates, claimants, roster)
    local nClaim = L._tgetn(claimants)
    if nClaim >= 2 then
        return Swarm.DeterministicMax(claimants, roster)
    elseif nClaim == 1 then
        return claimants[1]
    end
    return Swarm.DeterministicMax(presentCandidates, roster)
end

-- Build the present-candidate set and the claimant subset from the heard tables
-- and roster (SWARM_DESIGN.md sec.5.8). Two filters decide presence:
--   * self is present iff selfIsCandidate (CanAutomate) -- self-presence comes
--     from the GATE, never from heartbeats (we do not hear our own beats); self
--     claims iff selfAmQueen.
--   * any other X is present iff it was heard within the window AND currently
--     holds roster rank >= 1 -- so a DEMOTE drops X immediately (eligibility
--     filter) while an unclean DC drops X at the window timeout (presence filter).
-- Returns two name arrays: present, claimants. Pure (now/window injected).
function Swarm.ComputePresence(selfName, selfIsCandidate, selfAmQueen,
                               lastHeard, amQueenHeard, roster, now, window)
    local present, claimants = {}, {}

    if selfIsCandidate then
        L._tinsert(present, selfName)
        if selfAmQueen then L._tinsert(claimants, selfName) end
    end

    for name, ts in L._pairs(lastHeard) do
        if name ~= selfName then
            local rank = roster[name]
            if rank and rank >= 1 and (now - ts) < window then
                L._tinsert(present, name)
                if amQueenHeard[name] then L._tinsert(claimants, name) end
            end
        end
    end

    return present, claimants
end

-- [v0.29] slice 5a.2: the ADVERTISED CLAIM -- the amQueen bit a client puts on the
-- wire and counts as its OWN claim in ComputePresence -- split from selfAmQueen (the
-- election output / marking gate, which is unchanged and still drives ShouldDriveMarks).
-- A handoff TARGET enters the claimant set via pendingClaim WITHOUT anyone writing
-- selfAmQueen; the outgoing QUEEN drops its own claim for the one cycle that breaks
-- stickiness via relinquish. So the crown moves only through the deterministic
-- election (the claimant-count rule), never by imperative assignment -- the
-- single-queen invariant slice 3 established holds at every instant (sec.5.10).
-- DORMANT until 5a.3: with both flags false this returns selfAmQueen unchanged, so
-- every existing election result is reproduced exactly. Pure; always a boolean.
function Swarm.AdvertisedClaim(selfAmQueen, pendingClaim, relinquish)
    return ((selfAmQueen or pendingClaim) and not relinquish) or false
end

-- Derive the display role label from the election outcome (SWARM_DESIGN.md
-- sec.5.8 / sec.10: role is DERIVED, not a stored FSM). During the bootstrap
-- listen-window the role is BOOTSTRAP regardless of any tentative winner. Pure.
function Swarm.DeriveRole(selfName, queenName, bootstrapping)
    if bootstrapping then return "BOOTSTRAP" end
    if queenName == nil then return "NONE" end
    if queenName == selfName then return "QUEEN" end
    return "DRONE"
end

-- ==========================================================
-- RUNTIME SHELL  [v0.29] slice 2 -- the stateful wiring around the pure core.
-- This section reads WoW state and builds a frame, so it runs in-game only (the
-- tests/ harness exercises the pure functions above). It NEVER marks: there is no
-- SetRaidTarget here and CanAutomate is only ever READ.
-- ==========================================================

-- Heard-state, runtime only (bounded by raid size, keyed by player name).
Swarm.lastHeard      = {}    -- [name] = GetTime() of last beat
Swarm.amQueenHeard   = {}    -- [name] = that beat's amQueen flag
Swarm.versionHeard   = {}    -- [v0.29] slice 4: [name] = that beat's planVersion
Swarm.selfAmQueen    = false -- what WE currently advertise
Swarm.currentQueen   = nil   -- last elected queen (transition/repaint detection)

-- [v0.29] slice 5a.2/5a.3: handoff claim-override state (SWARM_DESIGN.md sec.5.10).
-- pendingClaim is a handoff TARGET briefly advertising amQueen=1 to enter the
-- claimant set (until it wins, or pendingClaimUntil elapses); relinquish is the
-- outgoing QUEEN suppressing its own claim for the single Recompute pass that breaks
-- stickiness (a strict one-shot, cleared each pass). While both are false,
-- AdvertisedClaim == selfAmQueen, so an idle swarm's election is unchanged. [5a.3]
-- the queen also tracks who it offered to (pendingHandoffTarget) under
-- handoffOfferUntil, so a lost offer self-clears WITHOUT ever relinquishing.
Swarm.pendingClaim         = false
Swarm.pendingClaimUntil    = 0
Swarm.relinquish           = false
Swarm.pendingHandoffTarget = nil
Swarm.handoffOfferUntil    = 0

-- [v0.29] slice 4: profile-sync state. planVersion is a single global, runtime-only
-- monotonic counter bumped on every SaveProfileCache WHILE we are the queen; it
-- rides the Q heartbeat so drones detect a stale plan. heardVersion is the version
-- last advertised by our current queen. appliedKey is the (queen,version,zone)
-- triple a drone has already applied; a mismatch arms needPull, which fires one
-- coalesced PR on the next tick (storm control -- see SWARM_DESIGN.md sec.6.1).
Swarm.planVersion    = 0     -- our own counter (meaningful only while queen)
Swarm.appliedKey     = nil   -- {queen=, version=, zone=} a drone last applied
Swarm.needPull       = false -- a drone armed a refetch (fired on the next tick)
Swarm.pendingPush    = nil   -- queen-side coalesced PR-response set: {[zone]=true}
Swarm.lastRole       = nil
Swarm.lastHandoffAvail = false -- [v0.29] slice 5b.3: last queen-has-candidate state (HUD chevron repaint gate)
Swarm.bootstrapping  = false
Swarm.bootstrapUntil = 0
Swarm.wasCandidate   = false
Swarm.lastCandidateTime = 0  -- [v0.29] last GetTime() we were a REAL candidate (transient-loss debounce)

-- [v0.29] slice 2 tracer: chat-notice debounce. The HUD line follows the election
-- live, but a chat announcement waits for the (role,queen) pair to survive >= one
-- heartbeat cycle, so the ~1s NONE flicker on a leader handover never reaches chat.
Swarm.committedRole  = nil
Swarm.committedQueen = nil
Swarm.pendingRole    = nil
Swarm.pendingQueen   = nil
Swarm.pendingSince   = 0

function Swarm.SelfName()
    return L._UnitName("player")
end

-- The existing automation gate IS the candidacy gate (SWARM_DESIGN.md sec.5.8 /
-- Q1). Read-only -- slice 2 never mutates CanAutomate.
function Swarm.SelfIsCandidate()
    return TankMark:CanAutomate()
end

-- Build { [name] = rank } from the server-authoritative roster. Raid: real ranks
-- (0/1/2). Party: only the leader is a candidate, so model the leader as rank 2
-- and everyone else 0 (the rank>=1 filter keeps just the leader). Solo: self at
-- rank 2. Rank is read here, never trusted from a heartbeat payload.
function Swarm.BuildRoster()
    local roster = {}
    if L._GetNumRaidMembers() > 0 then
        for i = 1, 40 do
            local n, rank = L._GetRaidRosterInfo(i)
            if n then roster[n] = rank or 0 end
        end
    elseif L._GetNumPartyMembers() > 0 then
        local me = Swarm.SelfName()
        if me then roster[me] = L._IsPartyLeader() and 2 or 0 end
        for i = 1, 4 do
            local n = L._UnitName("party"..i)
            if n then roster[n] = L._UnitIsPartyLeader("party"..i) and 2 or 0 end
        end
    else
        local me = Swarm.SelfName()
        if me then roster[me] = 2 end -- solo: sole candidate
    end
    return roster
end

-- The orchestrator: rebuild the world, run bootstrap entry/exit, run the pure
-- election, update our own claim, and log transitions. Idempotent -- safe to call
-- on any trigger (tick, receive, roster change).
function Swarm.Recompute(now)
    local selfName = Swarm.SelfName()
    if not selfName then return end

    -- [v0.29] Candidacy with a TRANSIENT-LOSS DEBOUNCE. SelfIsCandidate() is
    -- CanAutomate(); its HasPermissions() leg reads IsPartyLeader(), which the 1.12
    -- client momentarily returns FALSE for around combat-end even for the real leader
    -- (confirmed in-game: a ~0.9s perms blip mid-fight). Acting on that raw drop deposed
    -- the queen to NONE and, on recovery, re-armed the 15s bootstrap EVERY kill --
    -- violating "pure incumbency stickiness, never auto-depose". So a loss only counts
    -- as real once it persists past CANDIDATE_GRACE; a briefer blip holds the crown
    -- (selfIsCandidate stays true -> no NONE flicker, no bootstrap re-entry). A genuine
    -- demote/zone-out still drops after the grace. The scanner's own raw CanAutomate()
    -- still pauses for the sub-second blip (~1 skipped tick) -- invisible; only the
    -- swarm's 15s teardown is fixed here.
    local rawCandidate = Swarm.SelfIsCandidate()
    local selfIsCandidate = rawCandidate
    if rawCandidate then
        Swarm.lastCandidateTime = now
    elseif Swarm.wasCandidate and Swarm.lastCandidateTime > 0
            and (now - Swarm.lastCandidateTime) < Swarm.CANDIDATE_GRACE then
        selfIsCandidate = true  -- transient blip: keep the crown, do not bootstrap
        if TankMark.DebugEnabled then
            TankMark:DebugLog("SWARM", "candidacy blip held", { age = now - Swarm.lastCandidateTime })
        end
    end

    -- Bootstrap ENTRY: just became a candidate -> open the listen-window.
    if selfIsCandidate and not Swarm.wasCandidate then
        Swarm.bootstrapping  = true
        Swarm.bootstrapUntil = now + Swarm.PRESENCE_WINDOW
        Swarm.selfAmQueen    = false
    end
    Swarm.wasCandidate = selfIsCandidate

    local roster = Swarm.BuildRoster()

    -- [v0.29] slice 5a.3: handoff lifecycle (SWARM_DESIGN.md sec.5.10). Expire stale
    -- offers/claims first; then -- if WE are the queen and now HEAR our handoff target
    -- claiming -- relinquish: drop our own claim for THIS election so the lone remaining
    -- claimant (the target) wins via stickiness, even at a lower rank. Anchor rule: we
    -- never relinquish until we have heard the target claim, so a lost/ignored offer
    -- just leaves us marking. forceBeat fires one off-cycle heartbeat at the end of the
    -- pass so the swap completes in ~1s instead of waiting for the 5s tick.
    local forceBeat = false
    Swarm.ExpireHandoffState(now)
    if Swarm.selfAmQueen and Swarm.pendingHandoffTarget
        and Swarm.amQueenHeard[Swarm.pendingHandoffTarget] then
        Swarm.relinquish = true
        if TankMark.DebugEnabled then
            TankMark:DebugLog("SWARM", "handoff relinquish", { target = Swarm.pendingHandoffTarget })
        end
        Swarm.pendingHandoffTarget = nil
        Swarm.handoffOfferUntil = 0
        forceBeat = true
    end

    -- [v0.29] slice 5a.2: feed the ADVERTISED CLAIM (not raw selfAmQueen) into the
    -- election, so pendingClaim/relinquish move the crown through the claimant set.
    -- == selfAmQueen whenever no handoff is in flight, so behavior-identical.
    local claim = Swarm.AdvertisedClaim(Swarm.selfAmQueen, Swarm.pendingClaim, Swarm.relinquish)
    local present, claimants = Swarm.ComputePresence(
        selfName, selfIsCandidate, claim,
        Swarm.lastHeard, Swarm.amQueenHeard, roster, now, Swarm.PRESENCE_WINDOW)

    -- Bootstrap EXIT: defer to any heard incumbent (during bootstrap we do not
    -- claim, so any claimant is someone else), or when the listen-window elapses.
    if Swarm.bootstrapping and (L._tgetn(claimants) >= 1 or now >= Swarm.bootstrapUntil) then
        Swarm.bootstrapping = false
    end

    local queen = Swarm.ElectQueen(present, claimants, roster)

    -- Assert queen only once past bootstrap, still a candidate, and elected.
    local wasQueen = Swarm.selfAmQueen
    Swarm.selfAmQueen = (not Swarm.bootstrapping) and selfIsCandidate and (queen == selfName)

    -- [v0.29] slice 5a.3: relinquish is a strict ONE-SHOT -- consumed by the
    -- ComputePresence above for exactly the one election that breaks stickiness, then
    -- cleared here so it can never stick (e.g. if the target vanished before the swap
    -- completed and we got re-elected, a stuck relinquish would advertise amQueen=0
    -- while marking -- a self-inflicted split brain). The next beat advertises truth.
    Swarm.relinquish = false

    -- [v0.29] slice 4: push-on-promotion. On the rising edge to queen, propagate the
    -- current plan immediately (bump + push, like a Save) so drones converge on a
    -- handoff even when the new queen's plan changed without a version bump -- e.g. a
    -- pre-promotion drone-side edit, where neither a non-queen Save nor a version
    -- change ever fired. OnProfile applies any push from the current queen regardless
    -- of version, so this closes that gap with no pull latency. [slice 5a.3] the rising
    -- edge also clears a fulfilled pendingClaim -- we won the crown, the claim is spent.
    if Swarm.selfAmQueen and not wasQueen then
        Swarm.pendingClaim = false
        Swarm.pendingClaimUntil = 0
        Swarm.OnPromoted()
        -- [v0.29] slice 5b.2: a Flight Recorder left running on a fresh Queen is a
        -- dead-queen trap -- ProcessUnit records-and-returns under the recorder, so
        -- the new Queen never marks. Prompt to stop. Rising edge only; UI-guarded.
        if TankMark.IsRecorderActive and TankMark.PromptRecorderOnPromotion then
            TankMark:PromptRecorderOnPromotion(Swarm.SelfIsSoleCandidate())
        end
    end

    local role = Swarm.DeriveRole(selfName, queen, Swarm.bootstrapping)
    -- [v0.29] slice 5b.3: the HUD handoff chevron/button depends on the candidate
    -- SET, which changes WITHOUT a role/queen transition (a rejoined+promoted player
    -- starts heartbeating while we stay queen). Recompute already has `present`, so
    -- derive the queen's handoff-availability and repaint when IT flips too -- else
    -- the chevron never lights up and the queen can only hand off via slash.
    local others = 0
    for i = 1, L._tgetn(present) do
        if present[i] ~= selfName then others = others + 1 end
    end
    local handoffAvail = (role == "QUEEN") and (others > 0)
    if role ~= Swarm.lastRole or queen ~= Swarm.currentQueen
            or handoffAvail ~= Swarm.lastHandoffAvail then
        if TankMark.DebugEnabled then
            TankMark:DebugLog("SWARM", "election -> " .. role, {
                queen     = queen or "none",
                present   = L._tgetn(present),
                claimants = L._tgetn(claimants),
                boot      = Swarm.bootstrapping and "Y" or "N",
                amQueen   = Swarm.selfAmQueen and "Y" or "N",
            })
        end
        Swarm.lastRole         = role
        Swarm.currentQueen     = queen
        Swarm.lastHandoffAvail = handoffAvail
        -- [v0.29] slice 2 tracer: the HUD status line follows the election live.
        -- Repaint only an already-built HUD so we never force early creation.
        if TankMark.hudFrame and TankMark.UpdateHUD then TankMark:UpdateHUD() end
        -- [v0.29] slice 5b.1: a role flip read-only-gates (or releases) the Team
        -- Profiles tab when it's open. Guarded so it never forces UI creation.
        if TankMark.RefreshProfileGateIfVisible then TankMark:RefreshProfileGateIfVisible() end
    end

    -- [v0.29] Debounced chat notice -- evaluated EVERY recompute (not only on a
    -- transition) so the commit can fire on a later tick once the state settles.
    Swarm.UpdateNotice(now, role, queen)

    -- [v0.29] slice 4: arm a profile refetch if our queen's advertised plan no
    -- longer matches what we last applied. Arming here (on every recompute) and
    -- firing on the tick collapses a burst of heartbeats into one PR.
    Swarm.EvaluatePull(queen, role)

    -- [v0.29] slice 5a.3: an accept (target) or relinquish (queen) forces an off-cycle
    -- beat so the crown swap propagates in ~1s rather than at the next 5s tick. Sent
    -- last, after selfAmQueen reflects this pass, so the amQueen bit on the wire is current.
    if forceBeat then Swarm.SendBeat() end
end

-- Debounced chat announcer (slice 2 tracer). A (role,queen) pair must persist for
-- >= one heartbeat cycle before it is announced, so a transient flicker (e.g. a 1s
-- NONE during a leader handover) is swallowed. BOOTSTRAP commits silently -- it
-- always resolves to QUEEN/DRONE/NONE within the window. DISPLAY-ONLY: this prints
-- chat, it never marks.
function Swarm.UpdateNotice(now, role, queen)
    if role ~= Swarm.pendingRole or queen ~= Swarm.pendingQueen then
        Swarm.pendingRole, Swarm.pendingQueen = role, queen
        Swarm.pendingSince = now
        return
    end
    if (now - Swarm.pendingSince) < Swarm.HEARTBEAT_INTERVAL then return end
    if role == Swarm.committedRole and queen == Swarm.committedQueen then return end

    Swarm.committedRole, Swarm.committedQueen = role, queen
    if role == "BOOTSTRAP" then return end -- transient: settle silently

    -- Solo has no swarm to narrate -- commit silently so a later group transition
    -- still announces correctly, but keep chat quiet (the HUD line still shows).
    if L._GetNumRaidMembers() == 0 and L._GetNumPartyMembers() == 0 then return end

    if role == "QUEEN" then
        TankMark:Print("You are the marking |cffffd100Queen|r.")
    elseif role == "DRONE" then
        TankMark:Print("|cffffd100" .. (queen or "?")
            .. "|r is the marking Queen. You are a drone (read-only).")
    else -- NONE
        TankMark:Print("No marking Queen -- marking is paused.")
    end
end

-- Emit one heartbeat if we are a candidate and there is a group to hear it. Rides
-- the shared TM_SYNC prefix + 0.3s throttle; the 3-miss threshold absorbs any
-- delay behind a mob-sync burst.
function Swarm.SendBeat()
    if not Swarm.SelfIsCandidate() then return end
    if L._GetNumRaidMembers() == 0 and L._GetNumPartyMembers() == 0 then return end
    local channel = (L._GetNumRaidMembers() > 0) and "RAID" or "PARTY"
    -- [v0.29] slice 5a.2: the heartbeat's amQueen bit is the ADVERTISED CLAIM (a
    -- handoff target's pendingClaim, or self minus a relinquish), not the raw
    -- election output -- this is how a crown-pass nudges the claimant set without
    -- anyone writing selfAmQueen. == selfAmQueen when no handoff is in flight. [slice 4] planVersion
    -- stays gated on the REAL election output (selfAmQueen): only an actual queen has
    -- an authoritative plan, so a merely-claiming target advertises version 0.
    local claim = Swarm.AdvertisedClaim(Swarm.selfAmQueen, Swarm.pendingClaim, Swarm.relinquish)
    local advertisedVersion = Swarm.selfAmQueen and Swarm.planVersion or 0
    TankMark:QueueMessage(TankMark.SyncPrefix,
        TankMark.SyncCodec.EncodeHeartbeat(claim, advertisedVersion), channel)
end

-- Receive path, dispatched from HandleSync on kind=="Q". sender is the
-- server-authoritative unit name; rec is the decoded heartbeat. Stamp presence +
-- claim, then recompute immediately.
function Swarm.OnHeartbeat(sender, rec)
    if not sender or not rec then return end
    local now = L._GetTime()
    Swarm.lastHeard[sender]    = now
    Swarm.amQueenHeard[sender] = rec.amQueen and true or false
    Swarm.versionHeard[sender] = rec.planVersion or 0 -- [v0.29] slice 4
    Swarm.Recompute(now)
end

-- Roster-change recompute: catches a demote/leave instantly via the eligibility
-- filter, not the 15s presence timeout.
function Swarm.OnRosterChange()
    Swarm.Recompute(L._GetTime())
end

-- ==========================================================
-- HANDOFF  [v0.29] slice 5a.3 (SWARM_DESIGN.md sec.5.10)
-- The crown moves ONLY through the election: an offer nudges the claimant set
-- (target's pendingClaim, then queen's relinquish), never an imperative selfAmQueen
-- write -- so the single-queen invariant slice 3 established holds at every instant.
-- ==========================================================

-- Expire stale handoff bookkeeping (called at the top of every Recompute). Two
-- independent TTLs, ordered CLAIM(20) > PRESENCE(15) > OFFER(10) so a queen-DC
-- mid-handoff resolves as the target INHERITING (its claim outlives the queen's
-- presence window), not a fresh DeterministicMax to some bystander.
function Swarm.ExpireHandoffState(now)
    -- target side: a claim that never won within its window stops advertising.
    if Swarm.pendingClaim and now >= Swarm.pendingClaimUntil then
        Swarm.pendingClaim = false
        Swarm.pendingClaimUntil = 0
        if TankMark.DebugEnabled then
            TankMark:DebugLog("SWARM", "handoff claim expired", {})
        end
    end
    -- queen side: offered but never heard the target claim -> drop it, keep marking.
    if Swarm.pendingHandoffTarget and now >= Swarm.handoffOfferUntil then
        local t = Swarm.pendingHandoffTarget
        Swarm.pendingHandoffTarget = nil
        Swarm.handoffOfferUntil = 0
        TankMark:Print("Handoff to |cffffd100" .. t .. "|r not confirmed -- you remain Queen.")
    end
end

-- Receive a directed handoff offer (HandleSync, kind=="H"). Four gates, then
-- AUTO-ACCEPT (models passing raid lead -- no recipient dialog). Gate 1
-- (IsTrustedSender, rank>=1) already passed in HandleSync; here:
--   2. sender == our current elected queen -- a trusted non-queen cannot forge a
--      crown-pass (mirrors OnProfile's queen-only apply);
--   3. the offer names US;
--   4. we are eligible to mark right now AND not mid-bootstrap -- accepting while
--      ineligible would mint a queen that cannot mark; accepting inside the listen
--      window would advertise amQueen=1 during bootstrap (a forbidden claim).
-- Accept = enter the claimant set via pendingClaim + force a beat so the queen hears
-- us within ~1s. We do NOT write selfAmQueen -- the election promotes us once the
-- queen relinquishes, so there is never a moment with two marking queens.
function Swarm.OnHandoffOffer(sender, rec)
    if not sender or not rec or not rec.target then return end
    if sender ~= Swarm.currentQueen then return end
    if rec.target ~= Swarm.SelfName() then return end
    if not Swarm.SelfIsCandidate() or Swarm.bootstrapping then return end

    local now = L._GetTime()
    Swarm.pendingClaim = true
    Swarm.pendingClaimUntil = now + Swarm.HANDOFF_CLAIM_TTL
    if TankMark.DebugEnabled then
        TankMark:DebugLog("SWARM", "handoff accepted", { from = sender })
    end
    TankMark:Print("|cffffd100" .. sender .. "|r is passing you the marking Queen role...")
    Swarm.SendBeat() -- forced beat: advertise amQueen=1 (the confirm)
end

-- Initiate a handoff (queen-side, from /tmark handoff <name>). Validates queen-only,
-- a non-self target, and that the target is a LIVE candidate (present + rank>=1 in our
-- own presence view), then broadcasts the "H" offer and arms the offer TTL. The crown
-- does NOT move here -- it moves when the target claims and we relinquish (Recompute).
function Swarm.InitiateHandoff(targetName)
    if not Swarm.selfAmQueen then
        TankMark:Print("|cffff0000Handoff:|r only the marking Queen can pass the crown.")
        return
    end
    if not targetName or targetName == "" then
        TankMark:Print("Usage: /tmark handoff <player>")
        return
    end
    local selfName = Swarm.SelfName()
    if targetName == selfName then
        TankMark:Print("|cffff0000Handoff:|r you are already the Queen.")
        return
    end

    local now = L._GetTime()
    local roster = Swarm.BuildRoster()
    local present = Swarm.ComputePresence(selfName, Swarm.SelfIsCandidate(),
        Swarm.selfAmQueen, Swarm.lastHeard, Swarm.amQueenHeard, roster, now,
        Swarm.PRESENCE_WINDOW)
    local eligible = false
    for i = 1, L._tgetn(present) do
        if present[i] == targetName then eligible = true end
    end
    if not eligible then
        TankMark:Print("|cffff0000Handoff:|r '" .. targetName
            .. "' is not an eligible candidate (a present Assist/Leader running TankMark).")
        return
    end

    Swarm.pendingHandoffTarget = targetName
    Swarm.handoffOfferUntil = now + Swarm.HANDOFF_OFFER_TTL
    local channel = (L._GetNumRaidMembers() > 0) and "RAID" or "PARTY"
    local payload = TankMark.SyncCodec.EncodeHandoff(targetName)
    if payload then TankMark:QueueMessage(TankMark.SyncPrefix, payload, channel) end
    if TankMark.DebugEnabled then
        TankMark:DebugLog("SWARM", "handoff offered", { target = targetName })
    end
    TankMark:Print("Handoff offered to |cffffd100" .. targetName .. "|r -- waiting for confirmation...")
end

-- ==========================================================
-- PROFILE SYNC  [v0.29] slice 4 (SWARM_DESIGN.md sec.6.1)
-- ==========================================================

-- Broadcast TankMarkProfileDB[zone] as one atomic "P" snapshot (mark+tank+role),
-- then [v0.29 slice 7.2] append one "HR" healer record per entry that HAS healers
-- (SWARM_DESIGN.md sec.6.1a). The HRs carry the SAME planVersion as the P and are
-- queued AFTER it, so the FIFO throttle lands P first and a drone's version-gate
-- matches (the receive/apply is slice 7.3 -- until then drones drop the unknown
-- type, so the HR emission is DORMANT). Caller-gated -- the push (OnProfileSaved)
-- and the PR-response both verify the sender is the queen first. No group -> send nothing.
function Swarm.PushProfile(zone)
    if not zone then return end
    if L._GetNumRaidMembers() == 0 and L._GetNumPartyMembers() == 0 then return end
    local channel = (L._GetNumRaidMembers() > 0) and "RAID" or "PARTY"
    local entries = (TankMarkProfileDB and TankMarkProfileDB[zone]) or {}
    local payload = TankMark.SyncCodec.EncodeProfile(zone, Swarm.planVersion, entries)
    if payload then
        TankMark:QueueMessage(TankMark.SyncPrefix, payload, channel)
    end

    -- [v0.29] slice 7.2: append the healer records -- one HR per entry that has
    -- healers (EncodeHealerRecord returns nil for an empty list, so a healer-less
    -- entry is naturally skipped). A healer REMOVAL needs no message: it rides the
    -- P rebuild, which resets the drone's healers="" before these apply. Same
    -- planVersion as the P above so the drone's version-gate (slice 7.3) matches.
    local hrCount = 0
    for i = 1, L._tgetn(entries) do
        local e = entries[i]
        if e and e.mark and e.healers and e.healers ~= "" then
            local hr = TankMark.SyncCodec.EncodeHealerRecord(zone, Swarm.planVersion, e.mark, e.healers)
            if hr then
                TankMark:QueueMessage(TankMark.SyncPrefix, hr, channel)
                hrCount = hrCount + 1
            end
        end
    end
    if TankMark.DebugEnabled and hrCount > 0 then
        TankMark:DebugLog("SWARM", "pushed healer records", { zone = zone, n = hrCount, ver = Swarm.planVersion })
    end
end

-- Called from SaveProfileCache after the DB write (the sole commit point of the
-- cache->commit edit flow, so mid-edit state never leaks -- Save IS the debounce).
-- Only the queen propagates: bump the global planVersion so the new plan supersedes
-- the old on the heartbeat, then push immediately (the fast path). A non-queen Save
-- is silent -- its slot is overwritten by the next queen push.
function Swarm.OnProfileSaved(zone)
    if not Swarm.selfAmQueen then return end
    Swarm.planVersion = Swarm.planVersion + 1
    Swarm.PushProfile(zone)
end

-- Called from Recompute on the rising edge to queen (a fresh election win or a
-- handoff). Treat promotion like a Save: bump the version so the heartbeat
-- advertises a fresh plan (a drone that misses the push still pulls on the version
-- mismatch) and push the current zone now so drones converge immediately. Pushing
-- the current zone is correct -- that is the plan the new queen is about to enact.
function Swarm.OnPromoted()
    Swarm.planVersion = Swarm.planVersion + 1
    local zone = L._GetRealZoneText()
    if zone and zone ~= "" then Swarm.PushProfile(zone) end
end

-- [v0.29] slice 5b.3: the present candidates OTHER than self -- the eligible
-- handoff targets (present Assist/Leader running TankMark). Single source for the
-- handoff menu + the QUEEN line's chevron/click gate (5b.3) and the recorder
-- prompt's sole-candidate notice (5b.2). Mirrors InitiateHandoff's presence read.
function Swarm.HandoffCandidates()
    local selfName = Swarm.SelfName()
    local now      = L._GetTime()
    local roster   = Swarm.BuildRoster()
    local present  = Swarm.ComputePresence(selfName, Swarm.SelfIsCandidate(),
        Swarm.selfAmQueen, Swarm.lastHeard, Swarm.amQueenHeard, roster, now,
        Swarm.PRESENCE_WINDOW)
    local out = {}
    for i = 1, L._tgetn(present) do
        if present[i] ~= selfName then L._tinsert(out, present[i]) end
    end
    return out
end

-- [v0.29] slice 5b.2: true when nobody else could take over marking.
function Swarm.SelfIsSoleCandidate()
    return L._tgetn(Swarm.HandoffCandidates()) == 0
end

-- True when a drone's applied (queen,version,zone) key matches the live triple.
local function keyMatches(key, queen, version, zone)
    return key ~= nil and key.queen == queen and key.version == version and key.zone == zone
end

-- Arm a refetch when our queen's advertised plan no longer matches what we have
-- applied. Only a DRONE pulls (a queen renders its own DB; NONE/BOOTSTRAP have no
-- queen). The triple covers every staleness case: edit (version up), late join /
-- failover (queen differs), drop (version up), zone change (zone differs), queen
-- reload (counter resets -> inequality). An unknown zone (cold login, "") defers.
function Swarm.EvaluatePull(queen, role)
    if role ~= "DRONE" or not queen then
        Swarm.needPull = false
        return
    end
    local zone = L._GetRealZoneText()
    if not zone or zone == "" then return end
    local heard = Swarm.versionHeard[queen] or 0
    if not keyMatches(Swarm.appliedKey, queen, heard, zone) then
        Swarm.needPull = true
    end
end

-- Receive a profile snapshot (HandleSync, kind=="P"). Auto-apply ONLY what our own
-- elected queen sent -- stronger than the rank>=1 gate HandleSync already passed,
-- and split-brain-safe (each drone follows its own queen; the election converges).
-- Empty snapshot -> KEEP the current plan (a failover to an unprepared queen must
-- not blank drones while the old queen's marks are still on the mobs) but still
-- record the version so we stop pulling. Non-empty -> overwrite the local slot.
function Swarm.OnProfile(sender, rec)
    if not sender or not rec or not rec.zone then return end
    if sender ~= Swarm.currentQueen then return end
    if not TankMarkProfileDB then TankMarkProfileDB = {} end

    if L._tgetn(rec.entries) > 0 then
        local slot = {}
        for i = 1, L._tgetn(rec.entries) do
            local e = rec.entries[i]
            L._tinsert(slot, { mark = e.mark, tank = e.tank, role = e.role, healers = "" })
        end
        TankMarkProfileDB[rec.zone] = slot
        -- Render only the zone we are standing in (the HUD shows the current zone);
        -- other zones are stored but not painted.
        if rec.zone == L._GetRealZoneText() and TankMark.ApplyProfileToSession then
            TankMark:ApplyProfileToSession(rec.zone)
        end
        -- [v0.29] slice 5b.1: the HUD repaints above, but the open Profiles tab
        -- renders from profileCache (not the live DB) -- refresh it too when a drone
        -- is viewing this zone. Not limited to the current zone: the tab can view any
        -- zone via the dropdown. Guarded so it never forces UI creation.
        if TankMark.RefreshProfileTabForZone then
            TankMark:RefreshProfileTabForZone(rec.zone)
        end
    end

    -- The P itself proves the queen is at this version (at least as authoritative as
    -- a heartbeat), so align versionHeard now -- otherwise a push that lands before
    -- the next beat leaves applied > heard and arms a spurious pull for up to 5s.
    Swarm.versionHeard[sender] = rec.planVersion
    Swarm.appliedKey = { queen = sender, version = rec.planVersion, zone = rec.zone }
    Swarm.needPull   = false

    if TankMark.DebugEnabled then
        TankMark:DebugLog("SWARM", "profile applied", {
            queen = sender, zone = rec.zone,
            ver = rec.planVersion, n = L._tgetn(rec.entries),
        })
    end
end

-- Receive a pull-request (HandleSync, kind=="PR"). Only the queen answers, and it
-- coalesces: mark the zone pending, then the next tick broadcasts it ONCE no matter
-- how many drones asked this cycle (storm control after a queen reload/late join).
function Swarm.OnPullRequest(sender, rec)
    if not rec or not rec.zone then return end
    if not Swarm.selfAmQueen then return end
    Swarm.pendingPush = Swarm.pendingPush or {}
    Swarm.pendingPush[rec.zone] = true
end

-- Send one PR for a zone (drone -> queen). Rides the shared prefix + throttle.
function Swarm.SendPull(zone)
    if not zone then return end
    if L._GetNumRaidMembers() == 0 and L._GetNumPartyMembers() == 0 then return end
    local channel = (L._GetNumRaidMembers() > 0) and "RAID" or "PARTY"
    local payload = TankMark.SyncCodec.EncodePull(zone)
    if payload then TankMark:QueueMessage(TankMark.SyncPrefix, payload, channel) end
end

-- Tick-time sync flush. Queen: answer the coalesced pull-requests (one broadcast
-- per zone). Drone: fire one armed pull. needPull is NOT cleared here -- the P
-- response clears it (OnProfile); if it never arrives, the next tick re-arms and
-- retries, so a lost message self-heals at the 5s cadence.
function Swarm.FlushSync()
    if Swarm.selfAmQueen and Swarm.pendingPush then
        for zone in L._pairs(Swarm.pendingPush) do
            Swarm.PushProfile(zone)
        end
        Swarm.pendingPush = nil
    end
    if Swarm.needPull and not Swarm.selfAmQueen and Swarm.currentQueen then
        local zone = L._GetRealZoneText()
        if zone and zone ~= "" then Swarm.SendPull(zone) end
    end
end

-- The 5s tick: beat, recompute, then flush profile sync (pulls/PR-responses).
function Swarm.Tick(now)
    Swarm.SendBeat()
    Swarm.Recompute(now)
    Swarm.FlushSync()
end

-- Deferred init (called from the entry point, SuperWoW-gated). Builds the beat
-- frame and runs one immediate compute so the role is known at once. Idempotent.
function Swarm.InitSwarm()
    if Swarm.frame then return end
    local f = L._CreateFrame("Frame", "TMSwarmFrame")
    local elapsed = 0
    f:SetScript("OnUpdate", function()
        elapsed = elapsed + arg1
        if elapsed < Swarm.HEARTBEAT_INTERVAL then return end
        elapsed = 0
        Swarm.Tick(L._GetTime())
    end)
    Swarm.frame = f
    Swarm.Recompute(L._GetTime())
end

-- [v0.29] slice 3: liveness predicate for the marking gate. ShouldDriveMarks
-- (Permissions.lua) reads this to decide whether selfAmQueen is authoritative.
-- True once InitSwarm has built the beat frame (so the election is producing a
-- queen). Pure read. When false, ShouldDriveMarks fails open (see sec.5.9).
function Swarm.IsRunning()
    return Swarm.frame ~= nil
end
