-- TankMark: v0.25
-- File: Core/TankMark_Processor.lua
-- Module Version: 1.0
-- Last Updated: 2026-02-08
-- Core marking decision logic

if not TankMark then return end

-- Import shared localizations
local L = TankMark.Locals

-- ==========================================================
-- PROCESS LOGIC
-- ==========================================================

function TankMark:ProcessUnit(guid, mode)
    if not guid then return end
    
    -- 1. Sanity Checks
    if L._UnitIsDead(guid) then return end
    if L._UnitIsPlayer(guid) or L._UnitIsFriend("player", guid) then return end
    
    local cType = L._UnitCreatureType(guid)
    if cType == "Critter" or cType == "Non-combat Pet" then return end
    
    -- Normal/Trivial Mob Filter
    if not TankMark.MarkNormals then
        local cls = L._UnitClassification(guid)
        if not cls and guid == TankMark:Driver_GetGUID("mouseover") then
            cls = L._UnitClassification("mouseover")
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
    local currentIcon = L._GetRaidTargetIndex(guid)
    if currentIcon then
        if not TankMark.usedIcons[currentIcon] or not TankMark.activeGUIDs[guid] then
            TankMark:RegisterMarkUsage(currentIcon, L._UnitName(guid), guid, (L._UnitPowerType(guid) == 0), false)
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
            TankMark:RegisterMarkUsage(lockedIcon, L._UnitName(guid), guid, (L._UnitPowerType(guid) == 0), false)
            return
        end
    end
    
    -- 6. Logic: Mob Name Lookup
    local mobName = L._UnitName(guid)
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
    if mobData.marks and L._tgetn(mobData.marks) > 1 then
        return -- Sequential mobs only marked via batch marking
    end
    
    -- [v0.23] Extract single mark from array
    local markToUse = mobData.marks and mobData.marks[1] or 8
    if markToUse == 0 then return end
    
    -- [v0.22] COMBAT GATING: Only mark mobs when combat is happening
    if mode == "SCANNER" then
        local playerInCombat = L._UnitAffectingCombat("player")
        local mobInCombat = TankMark:IsGUIDInCombat(guid)
        
        if not mobInCombat and not playerInCombat then
            return
        end
    end
    
    local iconToApply = nil
    
    -- [v0.24] CC ASSIGNMENT LOGIC
    if mobData.type == "CC" and mobData.class then
        -- Step 1: Try to find CC player matching required class
        local ccMark = TankMark:FindCCPlayerForClass(mobData.class)
        if ccMark then
            iconToApply = ccMark
        end
        
        -- Step 2: Fallback to tank assignment if no CC player available
        if not iconToApply then
            -- Try DB mark first (if not disabled)
            if not TankMark.usedIcons[markToUse] and not TankMark.disabledMarks[markToUse] then
                iconToApply = markToUse
            end
            
            -- Then try tank marks
            if not iconToApply then
                iconToApply = TankMark:GetFreeTankIcon()
            end
        end
    
    -- [v0.24] KILL ASSIGNMENT LOGIC (or CC with no class specified)
    else
        -- Priority 1: Use mob's database mark if free
        if not TankMark.usedIcons[markToUse] and not TankMark.disabledMarks[markToUse] then
            iconToApply = markToUse
        end
        
        -- Priority 2: Get next available tank mark
        if not iconToApply then
            iconToApply = TankMark:GetFreeTankIcon()
        end
    end
    
    if iconToApply then
        TankMark:Driver_ApplyMark(guid, iconToApply)
        TankMark:RegisterMarkUsage(iconToApply, mobData.name, guid, (L._UnitPowerType(guid) == 0), false)
    end
end

function TankMark:ProcessUnknownMob(guid, mode)
    -- [v0.22 FIX] Combat gating (only for SCANNER mode)
    -- FORCE mode (batch marking) bypasses this check
    if mode == "SCANNER" then
        local playerInCombat = L._UnitAffectingCombat("player")
        local mobInCombat = TankMark:IsGUIDInCombat(guid)
        
        if not mobInCombat and not playerInCombat then
            return -- Don't mark peaceful mobs via scanner
        end
    end
    
    local iconToApply = TankMark:GetFreeTankIcon()
    if iconToApply then
        TankMark:Driver_ApplyMark(guid, iconToApply)
        TankMark:RegisterMarkUsage(iconToApply, L._UnitName(guid), guid, (L._UnitPowerType(guid) == 0), false)
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
    if L._UnitIsPlayer(guid) then return end
    if L._UnitIsFriend("player", guid) then return end
    
    local cType = L._UnitCreatureType(guid)
    if cType == "Critter" or cType == "Non-combat Pet" then return end
    
    local name = L._UnitName(guid)
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
