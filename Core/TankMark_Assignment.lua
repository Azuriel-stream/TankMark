-- TankMark: v0.26
-- File: Core/TankMark_Assignment.lua
-- Module Version: 1.2
-- Last Updated: 2026-02-24
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
    
    -- [DEBUG] Log search start
    if TankMark.DebugEnabled then
        TankMark:DebugLog("FREE", "GetFreeTankIcon search started", {
            zone = zone,
            profileCount = L._tgetn(list)
        })
    end

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
            -- [DEBUG] Log successful allocation
            if markID == 4 then
                if TankMark.DebugEnabled then
                    TankMark:DebugLog("FREE", "TRIANGLE would be returned", {
                        mark = markID,
                        tank = tankName or "none"
                    })
                end
            end

            if tankName and tankName ~= "" then
                local u = TankMark:FindUnitByName(tankName)
                if u then
                    if not L._UnitIsDeadOrGhost(u) and not TankMark:IsPlayerCCClass(tankName) then
                        -- [DEBUG] Final return
                        if TankMark.DebugEnabled then
                            TankMark:DebugLog("FREE", "Returning mark", {mark = markID})
                        end
                        return markID
                    end
                end
            else
                if TankMark.DebugEnabled then
                    TankMark:DebugLog("FREE", "Returning mark (no tank assigned)", {mark = markID})
                end
                return markID
            end
        end
    end
    if TankMark.DebugEnabled then
        TankMark:DebugLog("FREE", "GetFreeTankIcon returned nil", {})
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

-- [v0.26 FIXED] Safe GUID Handling + Liveness Guard
-- A mark holder only qualifies as a blocker if its mark unit token currently
-- exists server-side AND is not dead. This prevents dead-but-not-yet-evicted
-- MarkMemory entries from blocking SKULL reassignment after their mob dies.
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
        elseif prio == bestBlocker.prio and hp == bestBlocker.hp and icon < (bestBlocker.icon or 9) then
            bestBlocker = { icon = icon, guid = guid, prio = prio, hp = hp }
        end
    end

    -- [v0.26] Liveness check helper.
    -- Uses SuperWoW mark unit tokens (server-side, visibility-independent).
    -- Returns true only when the mark is on a living unit.
    local function IsMarkHolderAlive(iconID)
        if not L._UnitExists("mark" .. iconID) then return false end
        if L._UnitIsDead("mark" .. iconID) == 1 then return false end
        return true
    end

    local zone = TankMark:GetCachedZone()
    local list = TankMarkProfileDB[zone]

    -- PASS 1: Static Profile Checks
    if list then
        for i, entry in L._ipairs(list) do
            local markID = L._tonumber(entry.mark)
            local tankName = entry.tank
            
            -- CHECK A: STATIC PROFILE (usedIcons + MarkMemory/activeGUIDs)
            if markID and markID ~= 8 then
                -- [v0.26 FIX] Skip if mark holder is dead or gone.
                if IsMarkHolderAlive(markID) then
                    local isInUse = TankMark.usedIcons[markID] or TankMark.usedIcons[L._tostring(markID)]

                    if isInUse then
                        -- usedIcons stores boolean, not GUID.
                        -- Find the holder GUID via MarkMemory first (most reliable source),
                        -- then fall back to activeGUIDs scan.
                        local foundGUID = nil
                        if TankMark.MarkMemory and TankMark.MarkMemory[markID] then
                            foundGUID = TankMark.MarkMemory[markID]
                        end

                        if not foundGUID and TankMark.activeGUIDs then
                            for guid, icon in L._pairs(TankMark.activeGUIDs) do
                                if icon == markID then foundGUID = guid; break end
                            end
                        end

                        if foundGUID then
                            local mobName = TankMark.activeMobNames[markID]
                            if not mobName then mobName = L._UnitName(foundGUID) end

                            local mobPrio = 5 -- Safety default
                            if mobName and TankMark.activeDB and TankMark.activeDB[mobName] then
                                mobPrio = TankMark.activeDB[mobName].prio or 5
                            end
                            UpdateBest(markID, foundGUID, mobPrio, nil)
                        end
                    end
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
                            -- [v0.26 FIX] Skip if mark holder is dead or gone.
                            if IsMarkHolderAlive(icon) then
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
    end

    -- PASS 2: Active GUIDs Database
    if TankMark.activeGUIDs and TankMark.activeDB then
        for guid, icon in L._pairs(TankMark.activeGUIDs) do
            if icon ~= 8 then
                -- [v0.26 FIX] Skip if mark holder is dead or gone.
                if IsMarkHolderAlive(icon) then
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
    end

    -- NOTE: Pass 3 (MarkMemory fallback) has been removed.
    -- With the liveness guard in place, any MarkMemory entry whose mark holder
    -- is dead is correctly excluded by Passes 1 and 2. A dead-but-not-yet-evicted
    -- MarkMemory entry can no longer block SKULL reassignment.

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
                    -- Database Lookup
                    local name = L._UnitName(guid)
                    local prio = 5 -- Default for Unknown Mobs
                    local data = nil
                    
                    if name and TankMark.activeDB and TankMark.activeDB[name] then
                        data = TankMark.activeDB[name]
                        prio = data.prio or 5
                    end
                    
                    -- [v0.26 FIX] Changed from: data.marks[1] == 0
                    -- Now rejects any mob whose primary DB mark is explicitly NOT skull.
                    -- data nil → unknown mob → falls to else → allowed as fallback candidate.
                    -- marks[1] nil → malformed entry → falls to else → allowed conservatively.
                    -- marks[1] == 8 → SKULL configured → falls to else → allowed.
                    -- marks[1] ~= 8 → CROSS/TRIANGLE/etc → enters if → SKIPPED.
                    if data and data.marks and data.marks[1] and data.marks[1] ~= 8 then
                        if TankMark.DebugEnabled then
                            TankMark:DebugLog("CANDIDATE", "Skipping mob excluded from skull marking", {
                                guid = guid,
                                name = name,
                                prio = prio,
                            })
                        end
                    else
                        prio = L._tonumber(prio) or 5
                        local hp = L._UnitHealth(guid) or 999999

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