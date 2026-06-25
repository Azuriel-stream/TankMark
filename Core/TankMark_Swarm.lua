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
