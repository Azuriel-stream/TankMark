-- TankMark: v0.26
-- File: Core/TankMark_Assignment.lua
-- Module Version: 1.1
-- Last Updated: 2026-02-16
-- Mark assignment algorithms and player detection

if not TankMark then return end

local L = TankMark.Locals

-- ==========================================================
-- ASSIGNMENT HELPERS
-- ==========================================================

function TankMark:GetFreeTankIcon()
    local zone = TankMark:GetCachedZone()
    local list = TankMarkProfileDB[zone]
    if not list then return nil end
    
    for _, entry in L._ipairs(list) do
        local markID = L._tonumber(entry.mark)
        local tankName = entry.tank
        
        -- Check if mark is busy via Processor logic or fallback
        local isBusy = false
        if TankMark.IsMarkBusy then
            isBusy = TankMark:IsMarkBusy(markID)
        elseif TankMark.MarkMemory and TankMark.MarkMemory[markID] then
            isBusy = true
        elseif TankMark.usedIcons and (TankMark.usedIcons[markID] or TankMark.usedIcons[L._tostring(markID)]) then
            isBusy = true
        end

        if markID and not isBusy and not TankMark.disabledMarks[markID] then
            if tankName and tankName ~= "" then
                local u = TankMark:FindUnitByName(tankName)
                if u then
                    if not L._UnitIsDeadOrGhost(u) and not TankMark:IsPlayerCCClass(tankName) then
                        return markID
                    end
                end
            else
                return markID
            end
        end
    end
    return nil
end

function TankMark:FindUnitByName(name)
    if L._UnitName("player") == name then return "player" end
    for i = 1, 4 do
        if L._UnitName("party" .. i) == name then return "party" .. i end
    end
    for i = 1, 40 do
        if L._UnitName("raid" .. i) == name then return "raid" .. i end
    end
    return nil
end

-- Check if player is a CC-capable class
function TankMark:IsPlayerCCClass(playerName)
    if not playerName or playerName == "" then return false end
    
    local unit = TankMark:FindUnitByName(playerName)
    if not unit then return false end
    
    local class = L._UnitClass(unit)
    
    -- CC-capable classes (long-duration CC abilities)
    if class == "Mage" or class == "Warlock" or class == "Hunter" or
       class == "Priest" or class == "Druid" then
        return true
    end
    
    -- Shaman: Only Troll race can CC (Hex ability)
    if class == "Shaman" then
        local race = L._UnitRace(unit)
        return race == "Troll"
    end
    
    return false
end

-- Find CC player in Team Profile matching required class
function TankMark:FindCCPlayerForClass(requiredClass)
    local zone = TankMark:GetCachedZone()
    local list = TankMarkProfileDB[zone]
    if not list then return nil end
    
    -- Normalize required class to uppercase for comparison
    if requiredClass then
        requiredClass = L._strupper(requiredClass)
    end
    
    for _, entry in L._ipairs(list) do
        local playerName = entry.tank
        local markID = entry.mark
        
        if playerName and playerName ~= "" then
            local unit = TankMark:FindUnitByName(playerName)
            if unit then
                local _, playerClassEng = L._UnitClass(unit)
                
                -- Use English class token (always uppercase)
                if playerClassEng == requiredClass then
                    -- Check if mark is available (not used and not disabled)
                    if not TankMark.usedIcons[markID] and not TankMark.disabledMarks[markID] then
                        -- Check if player is alive
                        if not L._UnitIsDeadOrGhost(unit) then
                            return markID
                        end
                    end
                end
            end
        end
    end
    
    return nil
end

-- Helper: Check if player is alive and in raid
function TankMark:IsPlayerAliveAndInRaid(playerName)
    if not playerName or playerName == "" then return false end
    
    -- Find unit token
    local unit = TankMark:FindUnitByName(playerName)
    if not unit then return false end -- Not in raid/party
    
    -- Check if alive (includes ghost check)
    if L._UnitIsDeadOrGhost(unit) then return false end
    
    return true
end

function TankMark:GetAssigneeForMark(markID)
    local zone = TankMark:GetCachedZone()
    local list = TankMarkProfileDB[zone]
    if not list then return nil end
    
    for _, entry in L._ipairs(list) do
        if entry.mark == markID then return entry.tank end
    end
    
    return nil
end

-- [v0.26 FIXED] Safe GUID Handling + Memory Fallback
function TankMark:GetBlockingMarkInfo()
    local bestBlocker = {
        icon = nil,
        guid = nil,
        prio = 99,
        hp = 999999
    }

    local function UpdateBest(icon, guid, prio, hp)
        prio = prio or 99
        hp = hp or 999999
        if prio < bestBlocker.prio then
            bestBlocker = {icon=icon, guid=guid, prio=prio, hp=hp}
        elseif prio == bestBlocker.prio and hp < bestBlocker.hp then
            bestBlocker = {icon=icon, guid=guid, prio=prio, hp=hp}
        end
    end

    local zone = TankMark:GetCachedZone()
    local list = TankMarkProfileDB[zone]

    -- PASS 1: Static Profile Checks
    if list then
        for i, entry in L._ipairs(list) do
            local markID = L._tonumber(entry.mark)
            local tankName = entry.tank
            
            -- CHECK A: STATIC PROFILE (usedIcons + activeGUIDs)
            if markID and markID ~= 8 then
                local foundGUID = TankMark.usedIcons[markID] or TankMark.usedIcons[L._tostring(markID)]
                
                -- Fallback scan
                if not foundGUID and TankMark.activeGUIDs then
                    for guid, icon in L._pairs(TankMark.activeGUIDs) do
                        if icon == markID then foundGUID = guid; break end
                    end
                end
                
                if foundGUID and TankMark.activeGUIDs and TankMark.activeGUIDs[foundGUID] then
                    local mobName = TankMark.activeMobNames[markID]
                    if not mobName then mobName = L._UnitName(foundGUID) end
                    
                    local mobPrio = 99
                    if mobName and TankMark.activeDB and TankMark.activeDB[mobName] then
                        mobPrio = TankMark.activeDB[mobName].prio or 99
                    else
                        mobPrio = 5 -- Safety Default
                    end
                    UpdateBest(markID, foundGUID, mobPrio, nil)
                end
            end

            -- CHECK B: DYNAMIC TANK TARGETS
            if tankName and tankName ~= "" then
                local tankUnitID = TankMark:GetUnitIDForName(tankName)
                if tankUnitID then
                    local targetUnit = tankUnitID .. "target"
                    local exists, guid = L._UnitExists(targetUnit)
                    
                    if exists and not L._UnitIsDead(targetUnit) then
                        if not guid then guid = L._UnitName(targetUnit) end
                        local icon = L._GetRaidTargetIndex(targetUnit)
                        
                        if icon and icon > 0 and icon ~= 8 then
                             local name = L._UnitName(targetUnit)
                             local prio = 99
                             if name and TankMark.activeDB and TankMark.activeDB[name] then
                                 prio = TankMark.activeDB[name].prio or 99
                             end
                             UpdateBest(icon, guid, prio, L._UnitHealth(targetUnit))
                        end
                    end
                end
            end
        end
    end

    -- PASS 2: Active GUIDs Database
    if TankMark.activeGUIDs and TankMark.activeDB then
        for guid, icon in L._pairs(TankMark.activeGUIDs) do
            if icon ~= 8 then
                local name = L._UnitName(guid)
                if name then
                    local data = TankMark.activeDB[name]
                    if data and data.type ~= "CC" then
                        local requiredMark = (data.marks and data.marks[1])
                        if requiredMark and requiredMark == icon then
                             local mobPrio = data.prio or 99
                             UpdateBest(icon, guid, mobPrio, nil)
                        end
                    end
                end
            end
        end
    end

    -- [v0.26 NEW] PASS 3: Mark Memory Fallback (The Fix)
    -- If activeGUIDs missed it, check the persistent memory.
    if TankMark.MarkMemory then
        for icon, guid in L._pairs(TankMark.MarkMemory) do
            if icon ~= 8 then
                -- Check if we already found this icon in previous passes to avoid double counting
                if bestBlocker.icon ~= icon then
                    -- We found a Ghost Blocker!
                    -- Since we don't have full mob data from Memory, we assume:
                    -- Priority: 5 (Standard Trash)
                    -- HP: 999999 (Full/Unknown)
                    -- This ensures 5 >= 5 blocks the Skull.
                    UpdateBest(icon, guid, 5, 999999)
                end
            end
        end
    end

    return bestBlocker.icon, bestBlocker.guid, bestBlocker.prio, bestBlocker.hp
end

-- [v0.26 FIX] Robust Candidate Finder
function TankMark:FindEmergencyCandidate()
    local bestGUID = nil
    local bestPrio = 99
    local bestHP = 999999

    -- Iterate over all visible targets from the scanner
    if TankMark.visibleTargets then
        for guid, _ in L._pairs(TankMark.visibleTargets) do
            -- Basic Validity Checks
            if guid and not L._UnitIsDead(guid) and 
               not L._UnitIsPlayer(guid) and 
               not L._UnitIsFriend("player", guid) and
               not TankMark.activeGUIDs[guid] then -- Must not already have a mark
                
                -- Is it in combat with us?
                if TankMark:IsGUIDInCombat(guid) then
                    local name = L._UnitName(guid)
                    local prio = 5 -- Default for Unknown Mobs
                    
                    -- Database Lookup
                    if name and TankMark.activeDB and TankMark.activeDB[name] then
                        prio = TankMark.activeDB[name].prio or 5
                    end
                    
                    -- Ensure prio is a number
                    prio = L._tonumber(prio) or 5
                    
                    local hp = L._UnitHealth(guid) or 999999

                    -- Selection Logic:
                    -- 1. Lower Prio # is better (1 is best)
                    -- 2. Lower HP is better (Kill weak first)
                    if prio < bestPrio then
                        bestGUID = guid
                        bestPrio = prio
                        bestHP = hp
                    elseif prio == bestPrio and hp < bestHP then
                        bestGUID = guid
                        bestPrio = prio
                        bestHP = hp
                    end
                end
            end
        end
    end

    -- Return nil if no valid candidate found
    if bestPrio == 99 then return nil, nil end
    
    return bestGUID, bestPrio
end

function TankMark:GetUnitIDForName(name)
    if name == L._UnitName("player") then return "player" end
    local numRaid = L._GetNumRaidMembers()
    if numRaid > 0 then
        for i=1, numRaid do
            if L._UnitName("raid"..i) == name then return "raid"..i end
        end
    else
        for i=1, 4 do
            if L._UnitName("party"..i) == name then return "party"..i end
        end
    end
    return nil
end

function TankMark:AssignCC(iconID, playerName, taskType)
    TankMark.sessionAssignments[iconID] = playerName
    TankMark.usedIcons[iconID] = true
    if TankMark.UpdateHUD then TankMark:UpdateHUD() end
end