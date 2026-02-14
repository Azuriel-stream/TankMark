-- TankMark: v0.25
-- File: Core/TankMark_Permissions.lua
-- Module Version: 1.0
-- Last Updated: 2026-02-08
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
    if not TankMark.IsActive then return false end
    if not TankMark:HasPermissions() then return false end
    local zone = TankMark:GetCachedZone()
    if not TankMarkProfileDB[zone] or L._tgetn(TankMarkProfileDB[zone]) == 0 then
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
    if TankMark:CanAutomate() then
        L._SetRaidTarget(unitOrGuid, icon)
    end
end
