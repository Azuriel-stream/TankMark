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
Swarm.selfAmQueen    = false -- what WE currently advertise
Swarm.currentQueen   = nil   -- last elected queen (transition/repaint detection)

-- [v0.29] slice 4: profile-sync state. planVersion is a single global, runtime-only
-- monotonic counter bumped on every SaveProfileCache WHILE we are the queen; it
-- rides the Q heartbeat so drones detect a stale plan. heardVersion is the version
-- last advertised by our current queen. appliedKey is the (queen,version,zone)
-- triple a drone has already applied; a mismatch arms needPull, which fires one
-- coalesced PR on the next tick (storm control -- see SWARM_DESIGN.md sec.6.1).
Swarm.planVersion    = 0
Swarm.heardVersion   = 0
Swarm.appliedKey     = nil
Swarm.needPull       = false
Swarm.lastRole       = nil
Swarm.bootstrapping  = false
Swarm.bootstrapUntil = 0
Swarm.wasCandidate   = false

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

    local selfIsCandidate = Swarm.SelfIsCandidate()

    -- Bootstrap ENTRY: just became a candidate -> open the listen-window.
    if selfIsCandidate and not Swarm.wasCandidate then
        Swarm.bootstrapping  = true
        Swarm.bootstrapUntil = now + Swarm.PRESENCE_WINDOW
        Swarm.selfAmQueen    = false
    end
    Swarm.wasCandidate = selfIsCandidate

    local roster = Swarm.BuildRoster()
    local present, claimants = Swarm.ComputePresence(
        selfName, selfIsCandidate, Swarm.selfAmQueen,
        Swarm.lastHeard, Swarm.amQueenHeard, roster, now, Swarm.PRESENCE_WINDOW)

    -- Bootstrap EXIT: defer to any heard incumbent (during bootstrap we do not
    -- claim, so any claimant is someone else), or when the listen-window elapses.
    if Swarm.bootstrapping and (L._tgetn(claimants) >= 1 or now >= Swarm.bootstrapUntil) then
        Swarm.bootstrapping = false
    end

    local queen = Swarm.ElectQueen(present, claimants, roster)

    -- Assert queen only once past bootstrap, still a candidate, and elected.
    Swarm.selfAmQueen = (not Swarm.bootstrapping) and selfIsCandidate and (queen == selfName)

    local role = Swarm.DeriveRole(selfName, queen, Swarm.bootstrapping)
    if role ~= Swarm.lastRole or queen ~= Swarm.currentQueen then
        if TankMark.DebugEnabled then
            TankMark:DebugLog("SWARM", "election -> " .. role, {
                queen     = queen or "none",
                present   = L._tgetn(present),
                claimants = L._tgetn(claimants),
                boot      = Swarm.bootstrapping and "Y" or "N",
                amQueen   = Swarm.selfAmQueen and "Y" or "N",
            })
        end
        Swarm.lastRole     = role
        Swarm.currentQueen = queen
        -- [v0.29] slice 2 tracer: the HUD status line follows the election live.
        -- Repaint only an already-built HUD so we never force early creation.
        if TankMark.hudFrame and TankMark.UpdateHUD then TankMark:UpdateHUD() end
    end

    -- [v0.29] Debounced chat notice -- evaluated EVERY recompute (not only on a
    -- transition) so the commit can fire on a later tick once the state settles.
    Swarm.UpdateNotice(now, role, queen)
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
    -- [v0.29] slice 4: advertise planVersion only while actually queen, so a stale
    -- counter from a former reign cannot mislead drones after a handoff.
    local advertised = Swarm.selfAmQueen and Swarm.planVersion or 0
    TankMark:QueueMessage(TankMark.SyncPrefix,
        TankMark.SyncCodec.EncodeHeartbeat(Swarm.selfAmQueen, advertised), channel)
end

-- Receive path, dispatched from HandleSync on kind=="Q". sender is the
-- server-authoritative unit name; rec is the decoded heartbeat. Stamp presence +
-- claim, then recompute immediately.
function Swarm.OnHeartbeat(sender, rec)
    if not sender or not rec then return end
    local now = L._GetTime()
    Swarm.lastHeard[sender]    = now
    Swarm.amQueenHeard[sender] = rec.amQueen and true or false
    Swarm.Recompute(now)
end

-- Roster-change recompute: catches a demote/leave instantly via the eligibility
-- filter, not the 15s presence timeout.
function Swarm.OnRosterChange()
    Swarm.Recompute(L._GetTime())
end

-- ==========================================================
-- PROFILE SYNC  [v0.29] slice 4 (SWARM_DESIGN.md sec.6.1)
-- ==========================================================

-- Broadcast TankMarkProfileDB[zone] as one atomic "P" snapshot. Builds the
-- HUD-minimal entry list (mark+tank+role; healers omitted) straight from the DB.
-- Caller-gated -- the push (OnProfileSaved) and the PR-response both verify the
-- sender is the queen first. No group -> nothing to send.
function Swarm.PushProfile(zone)
    if not zone then return end
    if L._GetNumRaidMembers() == 0 and L._GetNumPartyMembers() == 0 then return end
    local channel = (L._GetNumRaidMembers() > 0) and "RAID" or "PARTY"
    local entries = (TankMarkProfileDB and TankMarkProfileDB[zone]) or {}
    local payload = TankMark.SyncCodec.EncodeProfile(zone, Swarm.planVersion, entries)
    if payload then
        TankMark:QueueMessage(TankMark.SyncPrefix, payload, channel)
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

-- The 5s tick: beat, then recompute (the recompute also sweeps stale candidates
-- via the presence filter -- the sole detector of a silent drop-out).
function Swarm.Tick(now)
    Swarm.SendBeat()
    Swarm.Recompute(now)
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
