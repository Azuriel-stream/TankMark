-- TankMark: v0.17-dev (Release Candidate)
-- File: TankMark_Engine.lua

if not TankMark then return end

-- Localizations
local _strfind = string.find
local _gsub = string.gsub
local _pairs = pairs
local _ipairs = ipairs
local _getn = table.getn

-- State Variables
TankMark.usedIcons = {}
TankMark.activeMobNames = {}
TankMark.activeGUIDs = {}
TankMark.activeMobIsCaster = {}
TankMark.disabledMarks = {} 
TankMark.IsActive = true 
TankMark.MarkNormals = false 
TankMark.DeathPattern = nil 
TankMark.IsRecorderActive = false 

TankMark.MarkInfo = {
    [8] = { name = "SKULL",    color = "|cffffffff" },
    [7] = { name = "CROSS",    color = "|cffff0000" },
    [6] = { name = "SQUARE",   color = "|cff00ccff" },
    [5] = { name = "MOON",     color = "|cffaabbcc" },
    [4] = { name = "TRIANGLE", color = "|cff00ff00" },
    [3] = { name = "DIAMOND",  color = "|cffff00ff" },
    [2] = { name = "CIRCLE",   color = "|cffffaa00" },
    [1] = { name = "STAR",     color = "|cffffff00" }
}

-- ==========================================================
-- PERMISSIONS & UTILS
-- ==========================================================

function TankMark:HasPermissions()
    local numRaid = GetNumRaidMembers()
    local numParty = GetNumPartyMembers()
    if numRaid == 0 and numParty == 0 then return true end -- Solo

    if numRaid > 0 then return (IsRaidLeader() or IsRaidOfficer())
    elseif numParty > 0 then return IsPartyLeader() end
    return false
end

function TankMark:CanAutomate()
    if not TankMark.IsActive then return false end
    if not TankMark:HasPermissions() then return false end
    
    local zone = GetRealZoneText()
    if not TankMarkProfileDB[zone] or _getn(TankMarkProfileDB[zone]) == 0 then
        return false 
    end
    return true
end

function TankMark:GetMarkString(iconID)
    local info = TankMark.MarkInfo[iconID]
    if info then return info.color .. info.name .. "|r" end
    return "Mark " .. iconID
end

function TankMark:Driver_GetGUID(unit)
    local exists, guid = UnitExists(unit)
    if exists and guid then return guid end
    return nil
end

function TankMark:Driver_ApplyMark(unitOrGuid, icon)
    if TankMark:CanAutomate() then
        SetRaidTarget(unitOrGuid, icon)
    end
end

-- ==========================================================
-- PROCESS LOGIC
-- ==========================================================

function TankMark:ProcessUnit(guid, mode)
    if not guid then return end

    -- 1. Sanity Checks
    if UnitIsDead(guid) then return end
    if UnitIsPlayer(guid) or UnitIsFriend("player", guid) then return end
    local cType = UnitCreatureType(guid)
    if cType == "Critter" or cType == "Non-combat Pet" then return end

    -- Normal/Trivial Mob Filter
    if not TankMark.MarkNormals then
        local cls = UnitClassification(guid)
        if not cls and guid == TankMark:Driver_GetGUID("mouseover") then
            cls = UnitClassification("mouseover")
        end
        if cls == "normal" or cls == "trivial" or cls == "minus" then return end
    end

    if TankMark.IsRecorderActive then
        TankMark:RecordUnit(guid)
    end

    -- 2. Check Database Existence
    local zone = GetRealZoneText()
    local dbExists = (TankMarkDB.Zones[zone] or TankMarkDB.StaticGUIDs[zone])
    
    -- [FIX] Allow FORCE mode to proceed even if DB is empty for this zone
    if not TankMark.IsRecorderActive and not dbExists and mode ~= "FORCE" then return end

    -- 3. Check Current Mark
    local currentIcon = GetRaidTargetIndex(guid)
    if currentIcon then
        if not TankMark.usedIcons[currentIcon] or not TankMark.activeGUIDs[guid] then
            TankMark:RegisterMarkUsage(currentIcon, UnitName(guid), guid, (UnitPowerType(guid) == 0))
        end
        return 
    end

    if TankMark.activeGUIDs[guid] then return end

    -- 4. Range Check
    if mode == "PASSIVE" then
        if not TankMark:Driver_IsDistanceValid(guid) then return end
    end

    -- 5. Logic: Static GUID Lock
    if TankMarkDB.StaticGUIDs[zone] and TankMarkDB.StaticGUIDs[zone][guid] then
        local lockData = TankMarkDB.StaticGUIDs[zone][guid]
        local lockedIcon = nil
        if type(lockData) == "table" then lockedIcon = lockData.mark
        elseif type(lockData) == "number" then lockedIcon = lockData end
        
        if lockedIcon and lockedIcon > 0 then
            TankMark:Driver_ApplyMark(guid, lockedIcon)
            TankMark:RegisterMarkUsage(lockedIcon, UnitName(guid), guid, (UnitPowerType(guid) == 0))
            return
        end
    end

    -- 6. Logic: Mob Name Lookup
    local mobName = UnitName(guid)
    if not mobName then return end
    
    local mobData = nil
    if TankMarkDB.Zones[zone] and TankMarkDB.Zones[zone][mobName] then
        mobData = TankMarkDB.Zones[zone][mobName]
    end

    if mobData then
        mobData.name = mobName
        TankMark:ProcessKnownMob(mobData, guid)
    else
        if mode == "FORCE" then TankMark:ProcessUnknownMob(guid) end
    end
end

function TankMark:ProcessKnownMob(mobData, guid)
    if mobData.mark == 0 then return end -- IGNORE logic

    local iconToApply = nil
    local isCCBlocked = (mobData.type == "CC" and TankMark.disabledMarks[mobData.mark])
    
    if mobData.type == "KILL" or isCCBlocked then
        -- Priority 1: Use specific mark if free AND in profile
        if not TankMark.usedIcons[mobData.mark] then
             local zone = GetRealZoneText()
             local list = TankMarkProfileDB[zone]
             if list then
                 for _, entry in _ipairs(list) do
                     -- [FIX] Allow fallback to mark if Tank name is empty (Wildcard)
                     if entry.mark == mobData.mark then
                         if entry.tank == "" or TankMark:FindUnitByName(entry.tank) then
                             iconToApply = mobData.mark
                             break
                         end
                     end
                 end
             end
        end
        -- Priority 2: Get next available from Ordered List
        if not iconToApply then iconToApply = TankMark:GetFreeTankIcon() end
    
    elseif mobData.type == "CC" then
        if not TankMark.usedIcons[mobData.mark] and not TankMark.disabledMarks[mobData.mark] then
            local assignee = TankMark:GetAssigneeForMark(mobData.mark)
            if assignee then
                 iconToApply = mobData.mark
                 TankMark:AssignCC(iconToApply, assignee, mobData.type)
            end
        end
    end

    if iconToApply then
        TankMark:Driver_ApplyMark(guid, iconToApply)
        TankMark:RegisterMarkUsage(iconToApply, mobData.name, guid, (UnitPowerType(guid) == 0))
    end
end

function TankMark:ProcessUnknownMob(guid)
    local iconToApply = TankMark:GetFreeTankIcon()
    if iconToApply then
        TankMark:Driver_ApplyMark(guid, iconToApply)
        TankMark:RegisterMarkUsage(iconToApply, UnitName(guid), guid, (UnitPowerType(guid) == 0))
    end
end

function TankMark:RegisterMarkUsage(icon, name, guid, isCaster)
    TankMark.usedIcons[icon] = true
    TankMark.activeMobNames[icon] = name
    TankMark.activeMobIsCaster[icon] = isCaster
    if guid then TankMark.activeGUIDs[guid] = icon end
    
    if not TankMark.sessionAssignments[icon] then
        local assignee = TankMark:GetAssigneeForMark(icon)
        if assignee then TankMark.sessionAssignments[icon] = assignee end
    end
    if TankMark.UpdateHUD then TankMark:UpdateHUD() end
end

function TankMark:RecordUnit(guid)
    local name = UnitName(guid)
    if not name then return end
    local zone = GetRealZoneText()
    if not TankMarkDB.Zones[zone] then TankMarkDB.Zones[zone] = {} end
    if not TankMarkDB.Zones[zone][name] then
        TankMarkDB.Zones[zone][name] = { 
            ["prio"] = 1, ["mark"] = 8, ["type"] = "KILL", ["class"] = nil 
        }
        TankMark:Print("Recorder: Captured [" .. name .. "]")
        if TankMark.UpdateMobList then TankMark:UpdateMobList() end
    end
end

-- ==========================================================
-- ASSIGNMENT HELPERS
-- ==========================================================

function TankMark:GetFreeTankIcon()
    local zone = GetRealZoneText()
    local list = TankMarkProfileDB[zone]
    if not list then return nil end
    
    for _, entry in _ipairs(list) do
        local markID = entry.mark
        local tankName = entry.tank
        if markID and not TankMark.usedIcons[markID] and not TankMark.disabledMarks[markID] then
            if tankName and tankName ~= "" then
                -- Standard Logic: Mark belongs to a specific Tank
                local u = TankMark:FindUnitByName(tankName)
                if u and not UnitIsDeadOrGhost(u) then return markID end
            else
                -- [FIX] Wildcard Logic: Mark is in profile but unassigned. Use it.
                return markID
            end
        end
    end
    return nil
end

function TankMark:FindUnitByName(name)
    if UnitName("player") == name then return "player" end
    for i=1,4 do if UnitName("party"..i) == name then return "party"..i end end
    for i=1,40 do if UnitName("raid"..i) == name then return "raid"..i end end
    return nil
end

function TankMark:GetAssigneeForMark(markID)
    local zone = GetRealZoneText()
    local list = TankMarkProfileDB[zone]
    if not list then return nil end
    for _, entry in _ipairs(list) do
        if entry.mark == markID then return entry.tank end
    end
    return nil
end

function TankMark:AssignCC(iconID, playerName, taskType)
    TankMark.sessionAssignments[iconID] = playerName
    TankMark.usedIcons[iconID] = true
    if TankMark.UpdateHUD then TankMark:UpdateHUD() end
end

-- ==========================================================
-- DEATH & RESET HANDLERS
-- ==========================================================

function TankMark:InitCombatLogParser()
    local pattern = _gsub(UNITDIESOTHER, "%%s", "(.*)")
    TankMark.DeathPattern = "^" .. pattern .. "$"
end

function TankMark:HandleCombatLog(msg)
    if not TankMark:CanAutomate() or not TankMark.DeathPattern then return end
    local _, _, deadMobName = _strfind(msg, TankMark.DeathPattern)
    
    if deadMobName then
        for iconID, name in _pairs(TankMark.activeMobNames) do
            if name == deadMobName then
                if not TankMark:VerifyMarkExistence(iconID) then
                    TankMark:EvictMarkOwner(iconID)
                    if TankMark.IsSuperWoW and iconID == 8 then TankMark:ReviewSkullState() end
                    return 
                end
            end
        end
    end
end

function TankMark:HandleDeath(unitID)
    if not TankMark:CanAutomate() then return end

    if not UnitIsPlayer(unitID) then
        local icon = GetRaidTargetIndex(unitID)
        local hp = UnitHealth(unitID)
        if icon and hp and hp <= 0 then
            TankMark:EvictMarkOwner(icon)
            if TankMark.IsSuperWoW and icon == 8 then TankMark:ReviewSkullState() end
        end
        return
    end

    local hp = UnitHealth(unitID)
    if hp and hp > 0 then return end 
    local deadPlayerName = UnitName(unitID)
    if not deadPlayerName then return end

    local zone = GetRealZoneText()
    local list = TankMarkProfileDB[zone]
    if not list then return end
    
    local deadIndex = nil
    for i, entry in _ipairs(list) do
        if entry.tank == deadPlayerName then deadIndex = i; break end
    end
    
    if deadIndex then
        local deadMarkStr = TankMark:GetMarkString(list[deadIndex].mark)
        local nextEntry = list[deadIndex + 1]
        if nextEntry and nextEntry.tank and nextEntry.tank ~= "" then
             local msg = "ALERT: " .. deadPlayerName .. " ("..deadMarkStr..") has died! Take over!"
             SendChatMessage(msg, "WHISPER", nil, nextEntry.tank)
             TankMark:Print("Alerted " .. nextEntry.tank .. " to cover for " .. deadPlayerName)
        end
    end
end

function TankMark:VerifyMarkExistence(iconID)
    if TankMark.IsSuperWoW then
        for guid, mark in _pairs(TankMark.activeGUIDs) do
            if mark == iconID then
                if UnitExists(guid) and not UnitIsDead(guid) then return true end
            end
        end
    end
    local numRaid = GetNumRaidMembers()
    local numParty = GetNumPartyMembers()
    local function Check(unit)
        return UnitExists(unit) and GetRaidTargetIndex(unit) == iconID and not UnitIsDead(unit)
    end
    if Check("target") then return true end
    if Check("mouseover") then return true end
    if numRaid > 0 then
        for i = 1, 40 do if Check("raid"..i.."target") then return true end end
    elseif numParty > 0 then
        for i = 1, 4 do if Check("party"..i.."target") then return true end end
    end
    return false
end

function TankMark:EvictMarkOwner(iconID)
    local oldName = TankMark.activeMobNames[iconID]
    TankMark.activeMobNames[iconID] = nil
    TankMark.usedIcons[iconID] = nil
    TankMark.activeMobIsCaster[iconID] = nil
    for guid, mark in _pairs(TankMark.activeGUIDs) do
        if mark == iconID then TankMark.activeGUIDs[guid] = nil end
    end
    if TankMark.UpdateHUD then TankMark:UpdateHUD() end
end

-- [REVISED] Cascading Priority Logic (Prio 1 > Prio 2 > ...)
function TankMark:ReviewSkullState()
    -- 1. Identify Current Skull
    local skullGUID = nil
    for guid, mark in _pairs(TankMark.activeGUIDs) do
        if mark == 8 then skullGUID = guid; break end
    end
    
    -- 2. Logic: Promote Cross to Skull (Instant Priority)
    for guid, mark in _pairs(TankMark.activeGUIDs) do
        if mark == 7 and TankMark.visibleTargets[guid] and not UnitIsDead(guid) then
             -- [FIXED] Only promote Cross if Skull is ACTUALLY MISSING.
             if not skullGUID then
                 TankMark:Driver_ApplyMark(guid, 8)
                 TankMark:EvictMarkOwner(7)
                 TankMark:RegisterMarkUsage(8, UnitName(guid), guid, false)
                 TankMark:Print("Auto-Promoted " .. UnitName(guid) .. " to SKULL.")
                 return
             end
        end
    end

    -- 3. Find Best Candidate (Cascading Priority)
    local bestGUID = nil
    local lowestHP = 999999
    local bestPrio = 99 -- Start with worst possible priority
    
    local zone = GetRealZoneText()
    if not TankMarkDB.Zones[zone] then return end
    
    for guid, _ in _pairs(TankMark.visibleTargets) do
        local currentMark = GetRaidTargetIndex(guid)
        
        -- Candidate Check: Alive, and (Unmarked OR Low Mark OR is Current Skull)
        if not UnitIsDead(guid) and (not currentMark or currentMark <= 6 or guid == skullGUID) then
            local name = UnitName(guid)
            if name and TankMarkDB.Zones[zone][name] then
                local data = TankMarkDB.Zones[zone][name]
                local mobPrio = data.prio or 99
                local mobHP = UnitHealth(guid)
                
                -- LOGIC UPDATE: Switch to better Priority Tier immediately
                if mobPrio < bestPrio then
                    bestPrio = mobPrio
                    lowestHP = mobHP
                    bestGUID = guid
                    
                -- If Same Priority Tier, check HP
                elseif mobPrio == bestPrio then
                    if mobHP and mobHP < lowestHP and mobHP > 0 then
                        lowestHP = mobHP
                        bestGUID = guid
                    end
                end
            end
        end
    end
    
    -- 4. Decision: Swap or Keep?
    if bestGUID then
        local shouldSwap = false
        
        if not skullGUID then
            shouldSwap = true
        elseif bestGUID ~= skullGUID then
            -- Compare Candidate against Current Skull
            local currentSkullName = UnitName(skullGUID)
            local currentSkullPrio = 99
            if currentSkullName and TankMarkDB.Zones[zone][currentSkullName] then
                currentSkullPrio = TankMarkDB.Zones[zone][currentSkullName].prio or 99
            end
            
            if bestPrio < currentSkullPrio then
                -- Always swap if we found a higher priority target
                shouldSwap = true
            elseif bestPrio == currentSkullPrio then
                -- If same priority, use Hysteresis (10% HP threshold)
                local currentHP = UnitHealth(skullGUID) or 1
                local candidateHP = UnitHealth(bestGUID)
                if currentHP > 0 and candidateHP < (currentHP * 0.90) then
                    shouldSwap = true
                end
            end
        end
        
        if shouldSwap then
            if skullGUID then TankMark:EvictMarkOwner(8) end
            local oldMark = GetRaidTargetIndex(bestGUID)
            if oldMark then TankMark:EvictMarkOwner(oldMark) end
            
            TankMark:Driver_ApplyMark(bestGUID, 8)
            TankMark:RegisterMarkUsage(8, UnitName(bestGUID), bestGUID, false)
        end
    end
end

function TankMark:UnmarkUnit(unit)
    if not TankMark:CanAutomate() then return end
    local currentIcon = GetRaidTargetIndex(unit)
    local guid = TankMark:Driver_GetGUID(unit)
    TankMark:Driver_ApplyMark(unit, 0)
    if currentIcon then
        TankMark:EvictMarkOwner(currentIcon)
    end
end

function TankMark:ResetSession() 
    TankMark.usedIcons = {}
    TankMark.sessionAssignments = {}
    TankMark.activeMobNames = {}
    TankMark.activeGUIDs = {}
    if TankMark.visibleTargets then
         for k in _pairs(TankMark.visibleTargets) do TankMark.visibleTargets[k] = nil end
    end
    
    if TankMark:HasPermissions() then
        if TankMark.IsSuperWoW then
            for i = 1, 8 do
                if UnitExists("mark"..i) then SetRaidTarget("mark"..i, 0) end
            end
        end

        local function ClearUnit(unit)
            if UnitExists(unit) and GetRaidTargetIndex(unit) then 
                SetRaidTarget(unit, 0)
            end
        end
        ClearUnit("target"); ClearUnit("mouseover")
        if UnitInRaid("player") then
            for i = 1, 40 do ClearUnit("raid"..i); ClearUnit("raid"..i.."target") end
        else
            for i = 1, 4 do ClearUnit("party"..i); ClearUnit("party"..i.."target") end
        end
        TankMark:Print("Session reset and ALL marks cleared.")
    else
        TankMark:Print("Session reset (Local HUD only - No permission to clear in-game marks).")
    end

    if TankMark.UpdateHUD then TankMark:UpdateHUD() end
end