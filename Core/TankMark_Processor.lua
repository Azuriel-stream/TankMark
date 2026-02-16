-- TankMark: v0.26
-- File: Core/TankMark_Processor.lua
-- Module Version: 1.3
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
    if TankMark.MarkMemory and TankMark.MarkMemory[iconID] then return true end
    if TankMark.IsSuperWoW and L._UnitExists("mark"..iconID) and not L._UnitIsDead("mark"..iconID) then return true end
    if TankMark.usedIcons and (TankMark.usedIcons[iconID] or TankMark.usedIcons[L._tostring(iconID)]) then return true end
    return false
end

-- [v0.26] Helper to find priority of current mark holder
function TankMark:GetMarkOwnerPriority(iconID)
    local holderGUID = nil
    
    -- 1. Check Memory (Primary Source)
    if TankMark.MarkMemory and TankMark.MarkMemory[iconID] then
        holderGUID = TankMark.MarkMemory[iconID]
    end
    
    -- 2. Check Active GUIDs
    if not holderGUID and TankMark.activeGUIDs then
        for guid, icon in L._pairs(TankMark.activeGUIDs) do
            if icon == iconID then holderGUID = guid; break end
        end
    end
    
    if holderGUID then
        local name = L._UnitName(holderGUID)
        if name and TankMark.activeDB and TankMark.activeDB[name] then
            return TankMark.activeDB[name].prio or 5
        end
        -- If we know the GUID but not the name/prio, assume Standard Trash (5)
        return 5
    end
    
    -- Mark is not held by anyone we know -> Priority 99 (Weakest)
    return 99
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
    
    -- CC Logic
    if mobData.type == "CC" and mobData.class then
        local ccMark = TankMark:FindCCPlayerForClass(mobData.class)
        if ccMark then iconToApply = ccMark end
    end
    
    if not iconToApply then
        local isBusy = TankMark:IsMarkBusy(markToUse)
        local canOverride = false
        
        -- [v0.26] AGGRESSIVE THEFT LOGIC
        if isBusy and markToUse == 8 then -- Restrict theft to Skull for safety
            local myPrio = mobData.prio or 5
            local ownerPrio = TankMark:GetMarkOwnerPriority(markToUse)
            
            -- If I am STRICTLY more important (Lower #), I take it.
            if myPrio < ownerPrio then
                canOverride = true
            end
        end

        if (not isBusy or canOverride) and not TankMark.disabledMarks[markToUse] then
            iconToApply = markToUse
        end
        
        -- Fallback to free icon only if we failed to secure the primary mark
        if not iconToApply then
            iconToApply = TankMark:GetFreeTankIcon()
        end
    end
    
    -- GOVERNOR CHECK
    if iconToApply == 8 and mode ~= "FORCE" then
        local blocked = false
        
        -- Double check availability, but respect our Override decision
        local isBusy = TankMark:IsMarkBusy(8)
        
        -- Calculate Override again to satisfy the Governor
        local myPrio = mobData.prio or 5
        local ownerPrio = TankMark:GetMarkOwnerPriority(8)
        local overrideValid = (myPrio < ownerPrio)
        
        if isBusy and not overrideValid then 
            blocked = true 
        end
        
        if blocked then return end
    end
    
    if iconToApply then
        -- [v0.26 FIX] STATE CLEANUP (Theft Handling)
        -- If we are stealing this mark (or even if we think it's free but memory has a ghost),
        -- we MUST evict the previous owner from activeGUIDs.
        -- This ensures the previous owner is re-processed as "unmarked" in the next cycle.
        if TankMark.MarkMemory and TankMark.MarkMemory[iconToApply] then
            local oldGUID = TankMark.MarkMemory[iconToApply]
            -- If oldGUID exists and is not ME (the new mob)
            if oldGUID and oldGUID ~= guid then
                if TankMark.activeGUIDs[oldGUID] == iconToApply then
                    TankMark.activeGUIDs[oldGUID] = nil
                end
            end
        end

        -- Update Memory
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
    
    -- Unknown mobs are Prio 5. They can never steal Skull (Owner is at least 5).
    -- They only take Skull if it's genuinely free.
    if iconToApply == 8 and mode ~= "FORCE" then
        if TankMark:IsMarkBusy(8) then return end
        
        if TankMark.GetBlockingMarkInfo then
            local blockIcon, _, blockPrio, _ = TankMark:GetBlockingMarkInfo()
            if blockIcon then
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