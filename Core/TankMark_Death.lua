-- TankMark: v0.25
-- File: Core/TankMark_Death.lua
-- Module Version: 1.0
-- Last Updated: 2026-02-08
-- Death detection, mark cleanup, and skull priority management

if not TankMark then return end

-- Import shared localizations
local L = TankMark.Locals

-- ==========================================================
-- COMBAT LOG PARSER
-- ==========================================================

function TankMark:InitCombatLogParser()
    local pattern = L._gsub(UNITDIESOTHER, "%%s", "(.*)")
    TankMark.DeathPattern = "^" .. pattern .. "$"
end

function TankMark:HandleCombatLog(msg)
    if not TankMark:CanAutomate() or not TankMark.DeathPattern then return end
    
    local _, _, deadMobName = L._strfind(msg, TankMark.DeathPattern)
    if deadMobName then
        for iconID, name in L._pairs(TankMark.activeMobNames) do
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

-- ==========================================================
-- DEATH HANDLERS
-- ==========================================================

function TankMark:HandleDeath(unitID)
    if not TankMark:CanAutomate() then return end
    
    -- Handle MOB death
    if not L._UnitIsPlayer(unitID) then
        local icon = L._GetRaidTargetIndex(unitID)
        local hp = L._UnitHealth(unitID)
        
        if icon and hp and hp <= 0 then
            TankMark:EvictMarkOwner(icon)
            if TankMark.IsSuperWoW and icon == 8 then
                TankMark:ReviewSkullState()
            end
        end
        return
    end
    
    -- [v0.24] Handle PLAYER death
    -- Check if player is actually dead/ghost (not just 0 HP from HoT ticks)
    if not L._UnitIsDeadOrGhost(unitID) then return end
    
    local deadPlayerName = L._UnitName(unitID)
    if not deadPlayerName then return end
    
    -- [v0.24] Check if we already alerted about this death
    if TankMark.alertedDeaths[deadPlayerName] then return end
    
    -- Mark death as processed
    TankMark.alertedDeaths[deadPlayerName] = true
    
    local zone = TankMark:GetCachedZone()
    local list = TankMarkProfileDB[zone]
    if not list then return end
    
    -- Check if dead player is a TANK
    local deadTankIndex = nil
    for i, entry in L._ipairs(list) do
        if entry.tank and entry.tank == deadPlayerName then
            deadTankIndex = i
            break
        end
    end
    
    if deadTankIndex then
        local deadMarkStr = TankMark:GetMarkString(list[deadTankIndex].mark)
        
        -- [v0.24] Find next ALIVE tank in sequence
        local nextTank = nil
        for i = deadTankIndex + 1, L._tgetn(list) do
            if list[i].tank and list[i].tank ~= "" then
                if TankMark:IsPlayerAliveAndInRaid(list[i].tank) then
                    nextTank = list[i].tank
                    break
                end
            end
        end
        
        if nextTank then
            local msg = "ALERT: " .. deadPlayerName .. " (" .. deadMarkStr .. ") has died! Take over!"
            SendChatMessage(msg, "WHISPER", nil, nextTank)
            TankMark:Print("Alerted " .. nextTank .. " to cover for " .. deadPlayerName)
        else
            TankMark:Print("|cffff0000WARNING:|r " .. deadPlayerName .. " died, but no alive backup tank found!")
        end
        return
    end
    
    -- Check if dead player is a HEALER
    for _, entry in L._ipairs(list) do
        if entry.healers and entry.healers ~= "" then
            -- Parse healer list (space-delimited)
            for healerName in L._gfind(entry.healers, "[^ ]+") do
                if healerName == deadPlayerName then
                    if TankMark:IsPlayerInRaid(healerName) then
                        local tankName = entry.tank
                        
                        -- [v0.24] Only alert if tank is alive
                        if tankName and tankName ~= "" and TankMark:IsPlayerAliveAndInRaid(tankName) then
                            local msg = "ALERT: Your healer " .. healerName .. " has died!"
                            SendChatMessage(msg, "WHISPER", nil, tankName)
                            TankMark:Print("Alerted " .. tankName .. " about healer death: " .. healerName)
                        else
                            TankMark:Print("|cffffaa00INFO:|r Healer " .. healerName .. " died, but tank " .. (tankName or "Unknown") .. " is unavailable.")
                        end
                    end
                    return
                end
            end
        end
    end
end

-- [v0.24] Clear death alert when player is alive again
function TankMark:ClearDeathAlert(playerName)
    if TankMark.alertedDeaths and playerName then
        TankMark.alertedDeaths[playerName] = nil
    end
end

-- ==========================================================
-- MARK VERIFICATION & CLEANUP
-- ==========================================================

function TankMark:VerifyMarkExistence(iconID)
    if TankMark.IsSuperWoW then
        for guid, mark in L._pairs(TankMark.activeGUIDs) do
            if mark == iconID then
                if L._UnitExists(guid) and not L._UnitIsDead(guid) then return true end
            end
        end
    end
    
    local numRaid = L._GetNumRaidMembers()
    local numParty = L._GetNumPartyMembers()
    
    local function Check(unit)
        return L._UnitExists(unit) and L._GetRaidTargetIndex(unit) == iconID and not L._UnitIsDead(unit)
    end
    
    if Check("target") then return true end
    if Check("mouseover") then return true end
    
    if numRaid > 0 then
        for i = 1, 40 do
            if Check("raid" .. i .. "target") then return true end
        end
    elseif numParty > 0 then
        for i = 1, 4 do
            if Check("party" .. i .. "target") then return true end
        end
    end
    
    return false
end

function TankMark:EvictMarkOwner(iconID)
    local oldName = TankMark.activeMobNames[iconID]
    TankMark.activeMobNames[iconID] = nil
    TankMark.usedIcons[iconID] = nil
    TankMark.activeMobIsCaster[iconID] = nil
    
    for guid, mark in L._pairs(TankMark.activeGUIDs) do
        if mark == iconID then
            TankMark.activeGUIDs[guid] = nil
        end
    end
    
    if TankMark.UpdateHUD then TankMark:UpdateHUD() end
end

-- ==========================================================
-- SKULL PRIORITY MANAGEMENT
-- ==========================================================

function TankMark:ReviewSkullState()
    -- [v0.22] Skip skull management when Recorder is active
    if TankMark.IsRecorderActive then return end
    
    -- 1. Identify Current Skull
    local skullGUID = nil
    for guid, mark in L._pairs(TankMark.activeGUIDs) do
        if mark == 8 then
            skullGUID = guid
            break
        end
    end
    
    -- 2. Logic: Promote Cross to Skull (Instant Priority)
    for guid, mark in L._pairs(TankMark.activeGUIDs) do
        if mark == 7 and TankMark.visibleTargets[guid] and not L._UnitIsDead(guid) then
            if not skullGUID then
                -- [v0.22] Check combat before promoting
                if TankMark:IsGUIDInCombat(guid) then
                    TankMark:Driver_ApplyMark(guid, 8)
                    TankMark:EvictMarkOwner(7)
                    TankMark:RegisterMarkUsage(8, L._UnitName(guid), guid, false, false)
                    TankMark:Print("Auto-Promoted " .. L._UnitName(guid) .. " to SKULL.")
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
    
    for guid, _ in L._pairs(TankMark.visibleTargets) do
        -- [v0.22] COMBAT GATING: Only consider mobs in combat
        if TankMark:IsGUIDInCombat(guid) then
            local currentMark = L._GetRaidTargetIndex(guid)
            local name = L._UnitName(guid)
            
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
            local isEligible = not L._UnitIsDead(guid) and (
                (not currentMark and (not databaseMark or databaseMark == 8)) or
                currentMark == 8
            )
            
            if isEligible then
                -- [v0.22] Respect MarkNormals filter
                if not TankMark.MarkNormals then
                    local cls = L._UnitClassification(guid)
                    if cls == "normal" or cls == "trivial" or cls == "minus" then
                        name = nil
                    end
                end
                
                -- [v0.22] Lookup in activeDB
                if name and TankMark.activeDB[name] then
                    local data = TankMark.activeDB[name]
                    local mobPrio = data.prio or 99
                    local mobHP = L._UnitHealth(guid)
                    
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
            local currentSkullName = L._UnitName(skullGUID)
            local currentSkullPrio = 99
            
            -- [v0.22] Lookup current skull in activeDB
            if currentSkullName and TankMark.activeDB[currentSkullName] then
                currentSkullPrio = TankMark.activeDB[currentSkullName].prio or 99
            end
            
            if bestPrio < currentSkullPrio then
                shouldSwap = true
            elseif bestPrio == currentSkullPrio then
                local currentHP = L._UnitHealth(skullGUID) or 1
                local candidateHP = L._UnitHealth(bestGUID)
                
                -- [v0.22] Changed HP threshold from 10% to 30% (0.90 → 0.70)
                if currentHP > 0 and candidateHP < (currentHP * 0.70) then
                    shouldSwap = true
                end
            end
        end
        
        if shouldSwap then
            if skullGUID then TankMark:EvictMarkOwner(8) end
            
            local oldMark = L._GetRaidTargetIndex(bestGUID)
            if oldMark then TankMark:EvictMarkOwner(oldMark) end
            
            TankMark:Driver_ApplyMark(bestGUID, 8)
            TankMark:RegisterMarkUsage(8, L._UnitName(bestGUID), bestGUID, false, false)
        end
    end
end

-- ==========================================================
-- RESET & CLEANUP
-- ==========================================================

function TankMark:UnmarkUnit(unit)
    if not TankMark:CanAutomate() then return end
    
    local currentIcon = L._GetRaidTargetIndex(unit)
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
    TankMark.alertedDeaths = {} -- [v0.24] Death alert tracking
    
    if TankMark.visibleTargets then
        for k in L._pairs(TankMark.visibleTargets) do
            TankMark.visibleTargets[k] = nil
        end
    end
    
    if TankMark:HasPermissions() then
        if TankMark.IsSuperWoW then
            for i = 1, 8 do
                if L._UnitExists("mark" .. i) then
                    SetRaidTarget("mark" .. i, 0)
                end
            end
        end
        
        local function ClearUnit(unit)
            if L._UnitExists(unit) and L._GetRaidTargetIndex(unit) then
                SetRaidTarget(unit, 0)
            end
        end
        
        ClearUnit("target")
        ClearUnit("mouseover")
        
        if L._UnitInRaid("player") then
            for i = 1, 40 do
                ClearUnit("raid" .. i)
                ClearUnit("raid" .. i .. "target")
            end
        else
            for i = 1, 4 do
                ClearUnit("party" .. i)
                ClearUnit("party" .. i .. "target")
            end
        end
        
        TankMark:Print("Session reset and ALL marks cleared.")
    else
        TankMark:Print("Session reset (Local HUD only - No permission to clear in-game marks).")
    end
    
    if TankMark.UpdateHUD then TankMark:UpdateHUD() end
end
