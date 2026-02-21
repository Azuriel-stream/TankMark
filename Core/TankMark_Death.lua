-- TankMark: v0.26
-- File: Core/TankMark_Death.lua
-- Module Version: 1.1
-- Last Updated: 2026-02-16
-- Death detection, mark cleanup, and skull priority management

if not TankMark then return end

local L = TankMark.Locals

-- ==========================================================
-- COMBAT LOG PARSER
-- ==========================================================

function TankMark:InitCombatLogParser()
    local pattern = L._gsub(L._UNITDIESOTHER, "%%s", "(.*)")
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
    
    -- Handle PLAYER death
    -- Check if player is actually dead/ghost (not just 0 HP from HoT ticks)
    if not L._UnitIsDeadOrGhost(unitID) then return end
    
    local deadPlayerName = L._UnitName(unitID)
    if not deadPlayerName then return end
    
    -- Check if we already alerted about this death
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
        
        -- Find next ALIVE tank in sequence
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
            L._SendChatMessage(msg, "WHISPER", nil, nextTank)
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
                        
                        -- Only alert if tank is alive
                        if tankName and tankName ~= "" and TankMark:IsPlayerAliveAndInRaid(tankName) then
                            local msg = "ALERT: Your healer " .. healerName .. " has died!"
                            L._SendChatMessage(msg, "WHISPER", nil, tankName)
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

-- Clear death alert when player is alive again
function TankMark:ClearDeathAlert(playerName)
    if TankMark.alertedDeaths and playerName then
        TankMark.alertedDeaths[playerName] = nil
    end
end

-- ==========================================================
-- MARK VERIFICATION & CLEANUP
-- ==========================================================

function TankMark:VerifyMarkExistence(iconID)
    -- [v0.26 FIX] Use SuperWoW mark units directly (server-side tracking)
    if TankMark.IsSuperWoW then
        if L._UnitExists("mark"..iconID) then
            local isDead = L._UnitIsDead("mark"..iconID)
            -- UnitIsDead returns nil (alive) or 1 (dead)
            if not isDead or isDead == nil then
                return true
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
    TankMark.activeMobNames[iconID] = nil
    TankMark.usedIcons[iconID] = nil
    TankMark.activeMobIsCaster[iconID] = nil
    
    -- [v0.26] Clear Persistent Memory
    if TankMark.MarkMemory then
        TankMark.MarkMemory[iconID] = nil
    end
    
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
    -- 1. Basic Checks
    if not TankMark:HasPermissions() then return end
    if TankMark.IsSuperWoW and not TankMark.IsSuperWoW then return end

    -- [v0.26] Sequential Marking Guard
    -- Prevents auto-skull if the mob is part of a sequential kill list (e.g. Majordomo)
    local skullName = TankMark.activeMobNames and TankMark.activeMobNames[8]
    if skullName and TankMark.activeDB and TankMark.activeDB[skullName] then
        local data = TankMark.activeDB[skullName]
        if data.marks and L._tgetn(data.marks) > 1 then return end
    end

    -- 2. Governor Check (The Blocker)
    local blockIcon, _, blockPrio, _ = nil, nil, 99, nil
    if TankMark.GetBlockingMarkInfo then
        blockIcon, _, blockPrio, _ = TankMark:GetBlockingMarkInfo()
    end

    -- 3. Find Best Candidate for Skull
    if TankMark.FindEmergencyCandidate then
        local candidateGUID, candidatePrio = TankMark:FindEmergencyCandidate()
        
        if candidateGUID then
            local shouldAssign = true
            
            -- [v0.26] STRICT INCUMBENCY RULE
            if blockIcon then
                -- Safe fallback if prio is nil
                candidatePrio = candidatePrio or 5
                blockPrio = blockPrio or 99
                
                -- IF BLOCKER EXISTS:
                -- Only assign if Candidate is STRICTLY better (Lower Prio #).
                -- If Prio is Equal (5 vs 5), DO NOT ASSIGN.
                if candidatePrio >= blockPrio then
                    shouldAssign = false
                end
            end
            
            if shouldAssign then
                TankMark:Driver_ApplyMark(candidateGUID, 8)
            end
        end
    end
end

-- ==========================================================
-- RESET & CLEANUP
-- ==========================================================

function TankMark:UnmarkUnit(unit)
    if not TankMark:CanAutomate() then return end
    
    local currentIcon = L._GetRaidTargetIndex(unit)
    
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
    TankMark.recordedGUIDs = {}
    TankMark.sequentialMarkCursor = {}
    TankMark.alertedDeaths = {}
    TankMark.IsRecorderActive = false
    
    if TankMark.visibleTargets then
        for k in L._pairs(TankMark.visibleTargets) do
            TankMark.visibleTargets[k] = nil
        end
    end
    
    if TankMark:HasPermissions() then
        if TankMark.MarkMemory then
            for k in L._pairs(TankMark.MarkMemory) do
                TankMark.MarkMemory[k] = nil
            end
        end

        if TankMark.IsSuperWoW then
            for i = 1, 8 do
                if L._UnitExists("mark" .. i) then
                    L._SetRaidTarget("mark" .. i, 0)
                end
            end
        end
        
        local function ClearUnit(unit)
            if L._UnitExists(unit) and L._GetRaidTargetIndex(unit) then
                L._SetRaidTarget(unit, 0)
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