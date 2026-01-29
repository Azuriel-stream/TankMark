-- TankMark: v0.23
-- File: TankMark_Engine.lua
-- Core marking logic and assignment algorithms

if not TankMark then return end

-- ==========================================================
-- LOCALIZATIONS
-- ==========================================================

local _UnitIsDead = UnitIsDead
local _UnitIsPlayer = UnitIsPlayer
local _UnitIsFriend = UnitIsFriend
local _UnitName = UnitName
local _UnitExists = UnitExists
local _UnitPowerType = UnitPowerType
local _GetRaidTargetIndex = GetRaidTargetIndex
local _strfind = string.find
local _gsub = string.gsub
local _gfind = string.gfind
local _pairs = pairs
local _ipairs = ipairs
local _tinsert = table.insert
local _tsort = table.sort
local _tgetn = table.getn

-- ==========================================================
-- STATE VARIABLES
-- ==========================================================

TankMark.usedIcons = {}
TankMark.activeMobNames = {}
TankMark.activeGUIDs = {}
TankMark.activeMobIsCaster = {}
TankMark.disabledMarks = {}
TankMark.sessionAssignments = {}
TankMark.IsActive = true
TankMark.MarkNormals = false
TankMark.DeathPattern = nil
TankMark.IsRecorderActive = false

-- [v0.21] Flight Recorder GUID tracking (prevent re-recording spam)
TankMark.recordedGUIDs = {}

-- [v0.23] Sequential marking cursor
TankMark.sequentialMarkCursor = {}

TankMark.MarkInfo = {
    [8] = { name = "SKULL", color = "|cffffffff" },
    [7] = { name = "CROSS", color = "|cffff0000" },
    [6] = { name = "SQUARE", color = "|cff00ccff" },
    [5] = { name = "MOON", color = "|cffaabbcc" },
    [4] = { name = "TRIANGLE", color = "|cff00ff00" },
    [3] = { name = "DIAMOND", color = "|cffff00ff" },
    [2] = { name = "CIRCLE", color = "|cffffaa00" },
    [1] = { name = "STAR", color = "|cffffff00" }
}

-- ==========================================================
-- PERMISSIONS & UTILS
-- ==========================================================

function TankMark:HasPermissions()
    local numRaid = GetNumRaidMembers()
    local numParty = GetNumPartyMembers()
    
    if numRaid == 0 and numParty == 0 then return true end
    if numRaid > 0 then return (IsRaidLeader() or IsRaidOfficer()) end
    if numParty > 0 then return IsPartyLeader() end
    
    return false
end

function TankMark:CanAutomate()
    if not TankMark.IsActive then return false end
    if not TankMark:HasPermissions() then return false end
    
    local zone = TankMark:GetCachedZone()
    if not TankMarkProfileDB[zone] or _tgetn(TankMarkProfileDB[zone]) == 0 then
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
    local exists, guid = _UnitExists(unit)
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
    if _UnitIsDead(guid) then return end
    if _UnitIsPlayer(guid) or _UnitIsFriend("player", guid) then return end
    
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
    
    -- Flight Recorder (record only, don't mark)
    if TankMark.IsRecorderActive then
        TankMark:RecordUnit(guid)
        return
    end
    
    -- 2. Check Database Existence
    local zone = TankMark:GetCachedZone()
    local hasActiveDB = (TankMark.activeDB and next(TankMark.activeDB) ~= nil)
    local hasGUIDLocks = (TankMarkDB.StaticGUIDs[zone] and next(TankMarkDB.StaticGUIDs[zone]) ~= nil)
    local dbExists = hasActiveDB or hasGUIDLocks
    
    if not dbExists and mode ~= "FORCE" then return end
    
    -- 3. Check Current Mark
    local currentIcon = _GetRaidTargetIndex(guid)
    if currentIcon then
        if not TankMark.usedIcons[currentIcon] or not TankMark.activeGUIDs[guid] then
            TankMark:RegisterMarkUsage(currentIcon, _UnitName(guid), guid, (_UnitPowerType(guid) == 0), false)
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
        
        if type(lockData) == "table" then
            lockedIcon = lockData.mark
        elseif type(lockData) == "number" then
            lockedIcon = lockData
        end
        
        if lockedIcon and lockedIcon > 0 then
            TankMark:Driver_ApplyMark(guid, lockedIcon)
            TankMark:RegisterMarkUsage(lockedIcon, _UnitName(guid), guid, (_UnitPowerType(guid) == 0), false)
            return
        end
    end
    
    -- 6. Logic: Mob Name Lookup
    local mobName = _UnitName(guid)
    if not mobName then return end
    
    -- [v0.21] LOOKUP IN MERGED ZONE CACHE (activeDB)
    local mobData = nil
    if TankMark.activeDB and TankMark.activeDB[mobName] then
        mobData = TankMark.activeDB[mobName]
    end
    
    if mobData then
        mobData.name = mobName
        TankMark:ProcessKnownMob(mobData, guid, mode)
    else
        -- [v0.22 FIX] Allow SCANNER mode to mark unknown mobs
        if mode == "FORCE" or mode == "SCANNER" then
            TankMark:ProcessUnknownMob(guid, mode)
        end
    end
end

function TankMark:ProcessKnownMob(mobData, guid, mode)
    -- [v0.23] Skip auto-marking for sequential mobs
    if mobData.marks and _tgetn(mobData.marks) > 1 then
        return  -- Sequential mobs only marked via batch marking
    end
    
    -- [v0.23] Extract single mark from array
    local markToUse = mobData.marks and mobData.marks[1] or 8
    
    if markToUse == 0 then return end
    
    -- [v0.22] COMBAT GATING: Only mark mobs when combat is happening
    if mode == "SCANNER" then
        -- Check if mob is targeting raid OR player is in combat
        local playerInCombat = UnitAffectingCombat("player")
        local mobInCombat = TankMark:IsGUIDInCombat(guid)
        
        if not mobInCombat and not playerInCombat then
            return -- Don't mark peaceful mobs
        end
    end
    
    local iconToApply = nil
    local isCCBlocked = (mobData.type == "CC" and TankMark.disabledMarks[markToUse])
    
    if mobData.type == "KILL" or isCCBlocked then
        -- [v0.22 FIX] Priority 1: Use mob's database mark if free (regardless of Team Profile)
        if not TankMark.usedIcons[markToUse] then
            iconToApply = markToUse
        end
        
        -- [v0.22 FIX] Priority 2: Only if mark is taken, get next available from Team Profile
        if not iconToApply then
            iconToApply = TankMark:GetFreeTankIcon()
        end
        
    elseif mobData.type == "CC" then
        if not TankMark.usedIcons[markToUse] and not TankMark.disabledMarks[markToUse] then
            local assignee = TankMark:GetAssigneeForMark(markToUse)
            if assignee then
                iconToApply = markToUse
                TankMark:AssignCC(iconToApply, assignee, mobData.type)
            end
        end
    end
    
    if iconToApply then
        TankMark:Driver_ApplyMark(guid, iconToApply)
        TankMark:RegisterMarkUsage(iconToApply, mobData.name, guid, (_UnitPowerType(guid) == 0), false)
    end
end

function TankMark:ProcessUnknownMob(guid, mode)
    -- [v0.22 FIX] Combat gating (only for SCANNER mode)
    -- FORCE mode (batch marking) bypasses this check
    if mode == "SCANNER" then
        local playerInCombat = UnitAffectingCombat("player")
        local mobInCombat = TankMark:IsGUIDInCombat(guid)
        
        if not mobInCombat and not playerInCombat then
            return -- Don't mark peaceful mobs via scanner
        end
    end
    
    local iconToApply = TankMark:GetFreeTankIcon()
    if iconToApply then
        TankMark:Driver_ApplyMark(guid, iconToApply)
        TankMark:RegisterMarkUsage(iconToApply, _UnitName(guid), guid, (_UnitPowerType(guid) == 0), false)
    end
end

function TankMark:RegisterMarkUsage(icon, name, guid, isCaster, skipProfileLookup)
    TankMark.usedIcons[icon] = true
    TankMark.activeMobNames[icon] = name
    TankMark.activeMobIsCaster[icon] = isCaster
    if guid then TankMark.activeGUIDs[guid] = icon end
    
    if not skipProfileLookup and not TankMark.sessionAssignments[icon] then
        local assignee = TankMark:GetAssigneeForMark(icon)
        if assignee then
            TankMark.sessionAssignments[icon] = assignee
        end
    end
    
    if TankMark.UpdateHUD then TankMark:UpdateHUD() end
end

function TankMark:RecordUnit(guid)
    -- [v0.21] Skip if already recorded this session (prevent spam)
    if TankMark.recordedGUIDs[guid] then return end
    
    -- Sanity check: Don't record players (even enemy faction)
    if _UnitIsPlayer(guid) then return end
    if _UnitIsFriend("player", guid) then return end
    
    local cType = UnitCreatureType(guid)
    if cType == "Critter" or cType == "Non-combat Pet" then return end
    
    local name = _UnitName(guid)
    if not name then return end
    
    local zone = TankMark:GetCachedZone()
    
    -- Safety: Ensure zone exists
    if not TankMarkDB.Zones[zone] then
        TankMarkDB.Zones[zone] = {}
    end
    
    -- Check if mob already exists
    if TankMarkDB.Zones[zone][name] then return end
    
    -- [v0.23] Record new mob with array schema
    TankMarkDB.Zones[zone][name] = {
        prio = 5,
        marks = {8},
        type = "KILL",
        class = nil
    }
    
    TankMark:Print("|cff00ff00Recorded:|r " .. name .. " |cff888888(P5, Mark: Skull)|r")
    
    -- [v0.21] Track GUID to prevent re-recording during this session
    TankMark.recordedGUIDs[guid] = true
    
    -- [v0.21] Don't add to activeDB in Recorder mode (prevents immediate marking)
    -- Recorded mobs will be loaded into activeDB on zone reload or when Recorder is disabled
    if not TankMark.IsRecorderActive then
        if not TankMark.activeDB then
            TankMark.activeDB = {}
        end
        TankMark.activeDB[name] = TankMarkDB.Zones[zone][name]
    end
    
    -- Refresh mob list if config window is open
    if TankMark.UpdateMobList then
        TankMark:UpdateMobList()
    end
end

-- ==========================================================
-- ASSIGNMENT HELPERS
-- ==========================================================

function TankMark:GetFreeTankIcon()
    local zone = TankMark:GetCachedZone()
    local list = TankMarkProfileDB[zone]
    if not list then return nil end
    
    for _, entry in _ipairs(list) do
        local markID = entry.mark
        local tankName = entry.tank
        
        if markID and not TankMark.usedIcons[markID] and not TankMark.disabledMarks[markID] then
            if tankName and tankName ~= "" then
                local u = TankMark:FindUnitByName(tankName)
                if u and not UnitIsDeadOrGhost(u) then return markID end
            else
                return markID
            end
        end
    end
    
    return nil
end

function TankMark:FindUnitByName(name)
    if _UnitName("player") == name then return "player" end
    for i=1,4 do if _UnitName("party"..i) == name then return "party"..i end end
    for i=1,40 do if _UnitName("raid"..i) == name then return "raid"..i end end
    return nil
end

function TankMark:GetAssigneeForMark(markID)
    local zone = TankMark:GetCachedZone()
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
                    if TankMark.IsSuperWoW and iconID == 8 then
                        TankMark:ReviewSkullState()
                    end
                    return
                end
            end
        end
    end
end

function TankMark:HandleDeath(unitID)
    if not TankMark:CanAutomate() then return end
    
    -- Handle MOB death
    if not _UnitIsPlayer(unitID) then
        local icon = _GetRaidTargetIndex(unitID)
        local hp = UnitHealth(unitID)
        if icon and hp and hp <= 0 then
            TankMark:EvictMarkOwner(icon)
            if TankMark.IsSuperWoW and icon == 8 then
                TankMark:ReviewSkullState()
            end
        end
        return
    end
    
    -- Handle PLAYER death
    local hp = UnitHealth(unitID)
    if hp and hp > 0 then return end
    
    local deadPlayerName = _UnitName(unitID)
    if not deadPlayerName then return end
    
    local zone = TankMark:GetCachedZone()
    local list = TankMarkProfileDB[zone]
    if not list then return end
    
    -- Check if dead player is a TANK
    local deadTankIndex = nil
    for i, entry in _ipairs(list) do
        if entry.tank and entry.tank == deadPlayerName then
            deadTankIndex = i
            break
        end
    end
    
    if deadTankIndex then
        -- Alert next tank in line
        local deadMarkStr = TankMark:GetMarkString(list[deadTankIndex].mark)
        local nextEntry = list[deadTankIndex + 1]
        
        if nextEntry and nextEntry.tank and nextEntry.tank ~= "" then
            local msg = "ALERT: " .. deadPlayerName .. " ("..deadMarkStr..") has died! Take over!"
            SendChatMessage(msg, "WHISPER", nil, nextEntry.tank)
            TankMark:Print("Alerted " .. nextEntry.tank .. " to cover for " .. deadPlayerName)
        end
        return
    end
    
    -- Check if dead player is a HEALER
    for _, entry in _ipairs(list) do
        if entry.healers and entry.healers ~= "" then
            -- Parse healer list (space-delimited)
            for healerName in _gfind(entry.healers, "[^ ]+") do
                if healerName == deadPlayerName then
                    -- Check if healer is in raid/party (roster validation)
                    if TankMark:IsPlayerInRaid(healerName) then
                        -- Alert the tank
                        local tankName = entry.tank
                        if tankName and tankName ~= "" then
                            local msg = "ALERT: Your healer " .. healerName .. " has died!"
                            SendChatMessage(msg, "WHISPER", nil, tankName)
                            TankMark:Print("Alerted " .. tankName .. " about healer death: " .. healerName)
                        end
                    end
                    return
                end
            end
        end
    end
end

function TankMark:VerifyMarkExistence(iconID)
    if TankMark.IsSuperWoW then
        for guid, mark in _pairs(TankMark.activeGUIDs) do
            if mark == iconID then
                if _UnitExists(guid) and not _UnitIsDead(guid) then return true end
            end
        end
    end
    
    local numRaid = GetNumRaidMembers()
    local numParty = GetNumPartyMembers()
    
    local function Check(unit)
        return _UnitExists(unit) and _GetRaidTargetIndex(unit) == iconID and not _UnitIsDead(unit)
    end
    
    if Check("target") then return true end
    if Check("mouseover") then return true end
    
    if numRaid > 0 then
        for i = 1, 40 do
            if Check("raid"..i.."target") then return true end
        end
    elseif numParty > 0 then
        for i = 1, 4 do
            if Check("party"..i.."target") then return true end
        end
    end
    
    return false
end

function TankMark:EvictMarkOwner(iconID)
    local oldName = TankMark.activeMobNames[iconID]
    TankMark.activeMobNames[iconID] = nil
    TankMark.usedIcons[iconID] = nil
    TankMark.activeMobIsCaster[iconID] = nil
    
    for guid, mark in _pairs(TankMark.activeGUIDs) do
        if mark == iconID then
            TankMark.activeGUIDs[guid] = nil
        end
    end
    
    if TankMark.UpdateHUD then TankMark:UpdateHUD() end
end

function TankMark:ReviewSkullState()
    -- [v0.22] Skip skull management when Recorder is active
    if TankMark.IsRecorderActive then return end
    
    -- 1. Identify Current Skull
    local skullGUID = nil
    for guid, mark in _pairs(TankMark.activeGUIDs) do
        if mark == 8 then
            skullGUID = guid
            break
        end
    end
    
    -- 2. Logic: Promote Cross to Skull (Instant Priority)
    for guid, mark in _pairs(TankMark.activeGUIDs) do
        if mark == 7 and TankMark.visibleTargets[guid] and not _UnitIsDead(guid) then
            if not skullGUID then
                -- [v0.22] Check combat before promoting
                if TankMark:IsGUIDInCombat(guid) then
                    TankMark:Driver_ApplyMark(guid, 8)
                    TankMark:EvictMarkOwner(7)
                    TankMark:RegisterMarkUsage(8, _UnitName(guid), guid, false, false)
                    TankMark:Print("Auto-Promoted " .. _UnitName(guid) .. " to SKULL.")
                end
                return
            end
        end
    end
    
    -- 3. Find Best Candidate (Cascading Priority)
    local bestGUID = nil
    local lowestHP = 999999
    local bestPrio = 99
    
    -- [v0.22] Use activeDB instead of TankMarkDB.Zones[zone]
    if not TankMark.activeDB then return end
    
    for guid, _ in _pairs(TankMark.visibleTargets) do
        -- [v0.22] COMBAT GATING: Only consider mobs in combat
        if TankMark:IsGUIDInCombat(guid) then
            local currentMark = _GetRaidTargetIndex(guid)
            local name = _UnitName(guid)
            
            -- [v0.23] Check database mark to determine eligibility
            local mobData = name and TankMark.activeDB[name]
            local databaseMark = nil
            
            if mobData and mobData.marks then
                -- [v0.23] For sequential mobs, only first mark matters for Skull eligibility
                databaseMark = mobData.marks[1]
            end
            
            -- Candidate eligibility:
            -- 1. Unmarked mob with NO database entry OR database mark is SKULL
            -- 2. Mob currently has SKULL (for dynamic swapping)
            -- EXPLICITLY EXCLUDE: Mobs whose database mark is anything other than SKULL
            local isEligible = not _UnitIsDead(guid) and (
                (not currentMark and (not databaseMark or databaseMark == 8)) or
                currentMark == 8
            )
            
            if isEligible then
                -- [v0.22] Respect MarkNormals filter
                if not TankMark.MarkNormals then
                    local cls = UnitClassification(guid)
                    if cls == "normal" or cls == "trivial" or cls == "minus" then
                        name = nil
                    end
                end
                
                -- [v0.22] Lookup in activeDB
                if name and TankMark.activeDB[name] then
                    local data = TankMark.activeDB[name]
                    local mobPrio = data.prio or 99
                    local mobHP = UnitHealth(guid)
                    
                    if mobPrio < bestPrio then
                        bestPrio = mobPrio
                        lowestHP = mobHP
                        bestGUID = guid
                    elseif mobPrio == bestPrio then
                        if mobHP and mobHP < lowestHP and mobHP > 0 then
                            lowestHP = mobHP
                            bestGUID = guid
                        end
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
            local currentSkullName = _UnitName(skullGUID)
            local currentSkullPrio = 99
            
            -- [v0.22] Lookup current skull in activeDB
            if currentSkullName and TankMark.activeDB[currentSkullName] then
                currentSkullPrio = TankMark.activeDB[currentSkullName].prio or 99
            end
            
            if bestPrio < currentSkullPrio then
                shouldSwap = true
            elseif bestPrio == currentSkullPrio then
                local currentHP = UnitHealth(skullGUID) or 1
                local candidateHP = UnitHealth(bestGUID)
                
                -- [v0.22] Changed HP threshold from 10% to 30% (0.90 → 0.70)
                if currentHP > 0 and candidateHP < (currentHP * 0.70) then
                    shouldSwap = true
                end
            end
        end
        
        if shouldSwap then
            if skullGUID then TankMark:EvictMarkOwner(8) end
            
            local oldMark = _GetRaidTargetIndex(bestGUID)
            if oldMark then TankMark:EvictMarkOwner(oldMark) end
            
            TankMark:Driver_ApplyMark(bestGUID, 8)
            TankMark:RegisterMarkUsage(8, _UnitName(bestGUID), bestGUID, false, false)
        end
    end
end

function TankMark:UnmarkUnit(unit)
    if not TankMark:CanAutomate() then return end
    
    local currentIcon = _GetRaidTargetIndex(unit)
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
    TankMark.recordedGUIDs = {} -- [v0.21] Clear recorder GUID tracking
    TankMark.sequentialMarkCursor = {} -- [v0.23] Clear sequential cursor
    
    if TankMark.visibleTargets then
        for k in _pairs(TankMark.visibleTargets) do
            TankMark.visibleTargets[k] = nil
        end
    end
    
    if TankMark:HasPermissions() then
        if TankMark.IsSuperWoW then
            for i = 1, 8 do
                if _UnitExists("mark"..i) then
                    SetRaidTarget("mark"..i, 0)
                end
            end
        end
        
        local function ClearUnit(unit)
            if _UnitExists(unit) and _GetRaidTargetIndex(unit) then
                SetRaidTarget(unit, 0)
            end
        end
        
        ClearUnit("target")
        ClearUnit("mouseover")
        
        if UnitInRaid("player") then
            for i = 1, 40 do
                ClearUnit("raid"..i)
                ClearUnit("raid"..i.."target")
            end
        else
            for i = 1, 4 do
                ClearUnit("party"..i)
                ClearUnit("party"..i.."target")
            end
        end
        
        TankMark:Print("Session reset and ALL marks cleared.")
    else
        TankMark:Print("Session reset (Local HUD only - No permission to clear in-game marks).")
    end
    
    if TankMark.UpdateHUD then TankMark:UpdateHUD() end
end

-- ==========================================================
-- [v0.21] BATCH PROCESSING SYSTEM
-- ==========================================================

local BATCH_MARK_DELAY = 0.05 -- 50ms delay between marks

-- Batch processing queue
TankMark.batchMarkQueue = {}
TankMark.batchQueueTimer = 0
TankMark.batchCandidates = {} -- Temporary collection during Shift-hold
TankMark.batchSequence = 0 -- [v0.21] Track mouseover order

-- Add candidate to batch collection (called during Shift-hold)
function TankMark:AddBatchCandidate(guid)
    if not guid then return end
    
    -- Ignore duplicates
    if TankMark.batchCandidates[guid] then return end
    
    -- Basic validation (skip already-marked, dead, friendly)
    if _UnitIsDead(guid) then return end
    if _UnitIsPlayer(guid) or _UnitIsFriend("player", guid) then return end
    
    -- [v0.22 FIX] Combat filtering depends on SuperWoW availability
    -- WITH SuperWoW: Skip combat mobs (scanner will handle them automatically)
    -- WITHOUT SuperWoW: Allow combat mobs (batch marking is the only marking method)
    if TankMark.IsSuperWoW and TankMark:IsGUIDInCombat(guid) then
        return
    end
    
    local mobName = _UnitName(guid)
    if not mobName then return end
    
    -- Lookup priority from activeDB
    local priority = 5 -- Default for unknown mobs
    local mobData = nil
    
    if TankMark.activeDB and TankMark.activeDB[mobName] then
        mobData = TankMark.activeDB[mobName]
        priority = mobData.prio or 5
    end
    
    -- [v0.21] Increment sequence to preserve mouseover order
    TankMark.batchSequence = TankMark.batchSequence + 1
    
    -- Store structured data
    TankMark.batchCandidates[guid] = {
        name = mobName,
        prio = priority,
        guid = guid,
        mobData = mobData,
        sequence = TankMark.batchSequence -- [v0.21] Mouseover order
    }
end

-- Execute batch marking (called on Shift release)
function TankMark:ExecuteBatchMarking()
    -- Check if any candidates collected
    local candidateCount = 0
    for _ in _pairs(TankMark.batchCandidates) do
        candidateCount = candidateCount + 1
    end
    
    if candidateCount == 0 then
        return -- Silent if no candidates
    end
    
    -- Permission/Profile check
    if not TankMark:CanAutomate() then
        TankMark:Print("|cffff0000Batch marking aborted: Permission/Profile check failed.|r")
        TankMark.batchCandidates = {}
        return
    end
    
    -- [v0.23] Reset sequential cursor
    TankMark.sequentialMarkCursor = {}
    
    -- Convert hashmap to array
    local sortedCandidates = {}
    for guid, data in _pairs(TankMark.batchCandidates) do
        _tinsert(sortedCandidates, data)
    end
    
    -- [v0.21] Sort by priority (ascending), then by sequence (mouseover order)
    _tsort(sortedCandidates, function(a, b)
        if a.prio == b.prio then
            return (a.sequence or 0) < (b.sequence or 0) -- Handle nil gracefully
        end
        return a.prio < b.prio
    end)
    
    -- Limit to top 8
    local maxMarks = math.min(8, _tgetn(sortedCandidates))
    
    -- Build queue for delayed execution
    TankMark.batchMarkQueue = {}
    for i = 1, maxMarks do
        _tinsert(TankMark.batchMarkQueue, {
            data = sortedCandidates[i],
            delay = (i - 1) * BATCH_MARK_DELAY
        })
    end
    
    -- Start queue processor
    TankMark:StartBatchProcessor()
    
    -- Clear candidate table
    TankMark.batchCandidates = {}
    
    -- User feedback
    TankMark:Print("|cff00ff00Batch marking:|r Processing " .. maxMarks .. " mobs...")
end

-- Queue processor using OnUpdate
function TankMark:StartBatchProcessor()
    if not TankMark.batchProcessorFrame then
        TankMark.batchProcessorFrame = CreateFrame("Frame")
    end
    
    TankMark.batchQueueTimer = 0
    TankMark.batchCurrentIndex = 1
    
    TankMark.batchProcessorFrame:SetScript("OnUpdate", function()
        TankMark.batchQueueTimer = TankMark.batchQueueTimer + arg1
        
        -- Check if queue is empty
        if TankMark.batchCurrentIndex > _tgetn(TankMark.batchMarkQueue) then
            TankMark.batchProcessorFrame:SetScript("OnUpdate", nil)
            TankMark.batchCurrentIndex = 1
            return
        end
        
        -- Process next mark if delay expired
        local queueEntry = TankMark.batchMarkQueue[TankMark.batchCurrentIndex]
        if TankMark.batchQueueTimer >= queueEntry.delay then
            TankMark:ProcessBatchMark(queueEntry.data)
            TankMark.batchCurrentIndex = TankMark.batchCurrentIndex + 1
        end
    end)
end

-- Process individual batch mark
function TankMark:ProcessBatchMark(candidateData)
    local guid = candidateData.guid
    local mobData = candidateData.mobData
    local mobName = candidateData.name
    
    -- Validate GUID still exists and is unmarked
    if not _UnitExists(guid) then
        return
    end
    
    if _UnitIsDead(guid) then
        return
    end
    
    if _GetRaidTargetIndex(guid) then
        return
    end
    
    -- [v0.22 FIX] Combat filtering depends on SuperWoW availability
    -- WITH SuperWoW: Skip combat mobs (let scanner handle them)
    -- WITHOUT SuperWoW: Process combat mobs (batch marking is the only option)
    if TankMark.IsSuperWoW and TankMark:IsGUIDInCombat(guid) then
        return
    end
    
    -- [v0.21] Respect MarkNormals filter for batch marking
    if not TankMark.MarkNormals then
        local cls = UnitClassification(guid)
        if cls == "normal" or cls == "trivial" or cls == "minus" then
            return -- Skip normal mobs if filter is active
        end
    end
    
    -- Permission check (may have changed during batch)
    if not TankMark:CanAutomate() then
        TankMark:Print("|cffff0000Batch marking aborted: Permission lost.|r")
        TankMark.batchProcessorFrame:SetScript("OnUpdate", nil)
        return
    end
    
    -- [v0.23] SEQUENTIAL MARKING LOGIC
    if mobData and mobData.marks and _tgetn(mobData.marks) > 1 then
        -- Initialize cursor for this mob name
        if not TankMark.sequentialMarkCursor[mobName] then
            TankMark.sequentialMarkCursor[mobName] = 1
        end
        
        local cursorIndex = TankMark.sequentialMarkCursor[mobName]
        local iconToApply = mobData.marks[cursorIndex]
        
        -- Apply mark (ignore conflicts per user requirement)
        TankMark:Driver_ApplyMark(guid, iconToApply)
        TankMark:RegisterMarkUsage(iconToApply, mobName, guid, false, true)  -- skipProfileLookup = true
        
        -- Advance cursor (with wraparound safety)
        TankMark.sequentialMarkCursor[mobName] = cursorIndex + 1
        if TankMark.sequentialMarkCursor[mobName] > _tgetn(mobData.marks) then
            TankMark.sequentialMarkCursor[mobName] = 1  -- Reset (for 5th+ mobs)
        end
    else
        -- Single mark or unknown mob (existing logic)
        if mobData then
            TankMark:ProcessKnownMob(mobData, guid, "FORCE")
        else
            TankMark:ProcessUnknownMob(guid, "FORCE")
        end
    end
end
