-- TankMark: v0.26
-- File: Core/TankMark_Processor.lua
-- Module Version: 1.1
-- Last Updated: 2026-02-16
-- Core marking decision logic

if not TankMark then return end

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
    
    -- Flight Recorder
    if TankMark.IsRecorderActive then
        TankMark:RecordUnit(guid)
        return
    end
    
    -- 2. Check Database Existence
    local zone = TankMark:GetCachedZone()
    local hasActiveDB = (TankMark.activeDB and L._next(TankMark.activeDB) ~= nil)
    local hasGUIDLocks = (TankMarkDB.StaticGUIDs[zone] and L._next(TankMarkDB.StaticGUIDs[zone]) ~= nil)
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
        
        if L._type(lockData) == "table" then
            lockedIcon = lockData.mark
        elseif L._type(lockData) == "number" then
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
    
    local mobData = nil
    if TankMark.activeDB and TankMark.activeDB[mobName] then
        mobData = TankMark.activeDB[mobName]
    end
    
    if mobData then
        mobData.name = mobName
        TankMark:ProcessKnownMob(mobData, guid, mode)
    else
        if mode == "FORCE" or mode == "SCANNER" then
            TankMark:ProcessUnknownMob(guid, mode)
        end
    end
end

-- [v0.26] Helper to check if a mark is truly busy
function TankMark:IsMarkBusy(iconID)
    -- 1. Check Memory (Persistence)
    -- This catches "Ghost" blockers that are off-screen but known by the Scanner.
    if TankMark.MarkMemory and TankMark.MarkMemory[iconID] then
        return true 
    end

    -- 2. SuperWoW Global Check (Ignore Dead)
    -- This handles static GUIDs on corpses (TurtleWoW).
    -- If the unit holding the mark is dead, the mark is NOT busy.
    if TankMark.IsSuperWoW and L._UnitExists("mark"..iconID) then
        if not L._UnitIsDead("mark"..iconID) then
            return true
        end
    end
    
    -- 3. Standard Local Check
    -- Fallback for standard vanilla clients or immediate usage.
    if TankMark.usedIcons and (TankMark.usedIcons[iconID] or TankMark.usedIcons[L._tostring(iconID)]) then
        return true
    end
    
    return false
end

function TankMark:ProcessKnownMob(mobData, guid, mode)
    if mobData.marks and L._tgetn(mobData.marks) > 1 then return end
    
    local markToUse = mobData.marks and mobData.marks[1] or 8
    if markToUse == 0 then return end
    
    if mode == "SCANNER" then
        local playerInCombat = L._UnitAffectingCombat("player")
        local mobInCombat = TankMark:IsGUIDInCombat(guid)
        if not mobInCombat and not playerInCombat then return end
    end
    
    local iconToApply = nil
    
    if mobData.type == "CC" and mobData.class then
        local ccMark = TankMark:FindCCPlayerForClass(mobData.class)
        if ccMark then iconToApply = ccMark end
    end
    
    if not iconToApply then
        if not TankMark:IsMarkBusy(markToUse) and not TankMark.disabledMarks[markToUse] then
            iconToApply = markToUse
        end
        if not iconToApply then
            iconToApply = TankMark:GetFreeTankIcon()
        end
    end
    
    -- GOVERNOR CHECK
    -- Prevents mark stealing based on Priority Incumbency
    if iconToApply == 8 and mode ~= "FORCE" then
        local blocked = false
        
        -- Double check availability just in case
        if TankMark:IsMarkBusy(8) then 
            blocked = true 
        else
            if TankMark.GetBlockingMarkInfo then
                local blockIcon, _, blockPrio, _ = TankMark:GetBlockingMarkInfo()
                if blockIcon then
                    local mobPrio = mobData.prio or 99
                    
                    -- Strict Incumbency Rule:
                    -- If the new mob's priority is equal (5) or worse (99) than the blocker (5),
                    -- do NOT assign. Blockers win ties.
                    if mobPrio >= blockPrio then
                        blocked = true
                    end
                end
            end
        end
        
        if blocked then return end
    end
    
    if iconToApply then
        -- Sync Memory immediately to prevent race conditions in the same frame
        if TankMark.MarkMemory then
            TankMark.MarkMemory[iconToApply] = guid 
        end
        
        TankMark:Driver_ApplyMark(guid, iconToApply)
        TankMark:RegisterMarkUsage(iconToApply, mobData.name, guid, (L._UnitPowerType(guid) == 0), false)
    end
end

function TankMark:ProcessUnknownMob(guid, mode)
    if mode == "SCANNER" then
        local playerInCombat = L._UnitAffectingCombat("player")
        local mobInCombat = TankMark:IsGUIDInCombat(guid)
        if not mobInCombat and not playerInCombat then return end
    end
    
    local iconToApply = TankMark:GetFreeTankIcon()
    
    if iconToApply == 8 and mode ~= "FORCE" then
        if TankMark:IsMarkBusy(8) then return end
        
        if TankMark.GetBlockingMarkInfo then
            local blockIcon, _, blockPrio, _ = TankMark:GetBlockingMarkInfo()
            if blockIcon then
                -- Unknown mobs are assumed Prio 5.
                -- If Blocker is Prio 5, 5 >= 5 is TRUE -> Blocked.
                local myPrio = 5 
                if myPrio >= blockPrio then return end
            end
        end
    end

    if iconToApply then
        if TankMark.MarkMemory then
            TankMark.MarkMemory[iconToApply] = guid 
        end
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
    if TankMark.recordedGUIDs[guid] then return end
    
    if L._UnitIsPlayer(guid) then return end
    if L._UnitIsFriend("player", guid) then return end
    
    local cType = L._UnitCreatureType(guid)
    if cType == "Critter" or cType == "Non-combat Pet" then return end
    
    local name = L._UnitName(guid)
    if not name then return end
    
    local zone = TankMark:GetCachedZone()
    
    if not TankMarkDB.Zones[zone] then
        TankMarkDB.Zones[zone] = {}
    end
    
    if TankMarkDB.Zones[zone][name] then return end
    
    TankMarkDB.Zones[zone][name] = {
        prio = 5,
        marks = {8},
        type = "KILL",
        class = nil
    }
    
    TankMark:Print("|cff00ff00Recorded:|r " .. name .. " |cff888888(P5, Mark: Skull)|r")
    
    TankMark.recordedGUIDs[guid] = true
    
    if not TankMark.IsRecorderActive then
        if not TankMark.activeDB then
            TankMark.activeDB = {}
        end
        TankMark.activeDB[name] = TankMarkDB.Zones[zone][name]
    end
    
    if TankMark.UpdateMobList then
        TankMark:UpdateMobList()
    end
end