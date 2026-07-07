-- Permission checks and driver utilities

if not TankMark then return end

-- Import shared localizations
local L = TankMark.Locals

-- ==========================================================
-- PERMISSIONS
-- ==========================================================

function TankMark:HasPermissions()
    local numRaid = L._GetNumRaidMembers()
    local numParty = L._GetNumPartyMembers()
    if numRaid == 0 and numParty == 0 then return true end
    if numRaid > 0 then return (L._IsRaidLeader() or L._IsRaidOfficer()) end
    if numParty > 0 then return L._IsPartyLeader() end
    return false
end

function TankMark:CanAutomate()
    if not TankMark.IsSuperWoW then return false end
    if not TankMark.IsActive then return false end
    if not TankMark:HasPermissions() then return false end
    local zone = TankMark:GetCachedZone()
    if not TankMarkProfileDB[zone] or L._tgetn(TankMarkProfileDB[zone]) == 0 then
        return false
    end
    return true
end

-- [v0.29] swarm slice 3: the MARKING gate, deliberately distinct from the
-- candidacy gate above. CanAutomate answers "am I ELIGIBLE to mark?" -- it drives
-- the swarm election / failover pool (Swarm.SelfIsCandidate reads it), so it must
-- stay unchanged or the candidate set collapses. ShouldDriveMarks answers "should
-- I mark RIGHT NOW?" = eligible AND the swarm says I am the queen. Fail-open: if
-- the election shell is not running (Swarm absent / InitSwarm never fired), degrade
-- to today's eligible-clients-mark behavior rather than going silent -- the swarm
-- is an enhancement over a working baseline, and the server rank-gate is the real
-- safety backstop. This is the ONE gate every slice-3 marking site reads. No
-- circular dependency: it reads the STORED field selfAmQueen (set by Recompute from
-- SelfIsCandidate->CanAutomate), never CanAutomate's queen-status. See
-- SWARM_DESIGN.md sec.5.9.
function TankMark:ShouldDriveMarks()
    if not TankMark:CanAutomate() then return false end
    local swarm = TankMark.Swarm
    if swarm and swarm.IsRunning() and not swarm.selfAmQueen then
        return false
    end
    return true
end

-- ==========================================================
-- UTILITIES
-- ==========================================================

function TankMark:GetMarkString(iconID)
    local info = TankMark.MarkInfo[iconID]
    if info then return info.color .. info.name .. "|r" end
    return "Mark " .. iconID
end

function TankMark:Driver_GetGUID(unit)
    local exists, guid = L._UnitExists(unit)
    if exists and guid then return guid end
    return nil
end

function TankMark:Driver_ApplyMark(unitOrGuid, icon)
    -- [DEBUG] Log BEFORE applying mark
    if TankMark.DebugEnabled then
        local mobName = L._UnitName(unitOrGuid) or "Unknown"
        local guidShort = unitOrGuid
        
        -- Truncate GUID if it's a hex string
        if L._type(unitOrGuid) == "string" and L._strfind(unitOrGuid, "^0x") then
            guidShort = L._sub(unitOrGuid, 1, 10) .. "..."
        end
        
        -- Get calling function from stack ([v0.28] Lua 5.0 has no string.match;
        -- use strfind captures -- matches the idiom used elsewhere in the addon)
        local caller = L._debugstack(2, 1, 0)
        local _, _, callerShort = L._strfind(caller or "", "in function `([^']+)'")
        callerShort = callerShort or "Unknown"
        
        TankMark:DebugLog("APPLY", "Applying mark", {
            icon = icon,
            guid = guidShort,
            mob = mobName,
            caller = callerShort
        })
    end
    
    -- Original function logic
    -- [v0.29] the gated APPLY edge: the authoritative single-marker enforcement point,
    -- gated by ShouldDriveMarks (was CanAutomate), so even a stray caller cannot make a
    -- non-queen place a mark. [v0.32] slice A: the raw write now goes through the
    -- Platform.SetMark primitive (the per-platform fork point); this wrapper keeps the
    -- gate + debug logging in shared Core, inherited by every platform build.
    if TankMark:ShouldDriveMarks() then
        TankMark.Platform.SetMark(unitOrGuid, icon)
    else
        -- [DEBUG] Log when mark application is blocked
        if TankMark.DebugEnabled then
            TankMark:DebugLog("APPLY", "Mark blocked - no permission", {
                icon = icon,
                canAutomate = false
            })
        end
    end
end
