-- TankMark: v0.26
-- File: Core/TankMark_Scanner.lua
-- SuperWoW nameplate scanner with Snapshot Batching and Table Reuse

if not TankMark then return end

local L = TankMark.Locals

local SCAN_INTERVAL = 0.5

if not TankMark.MarkMemory then TankMark.MarkMemory = {} end

-- [v0.26] Batch Buffers
local batchCandidates = {}

TankMark.visibleTargets = {}
TankMark.RangeSpellID = nil
TankMark.RangeSpellIndex = nil
TankMark.IsSuperWoW = false

function TankMark:InitDriver()
    if L._type(SUPERWOW_VERSION) ~= "nil" then
        TankMark.IsSuperWoW = true
        TankMark:Print("SuperWoW Detected: |cff00ff00v0.26 Hybrid Driver Loaded.|r")
        TankMark:StartSuperScanner()
    else
        TankMark:Print("Standard Client: Hybrid features disabled.")
    end
end

function TankMark:StartSuperScanner()
    local f = L._CreateFrame("Frame", "TMScannerFrame")
    local elapsed = 0
    
    f:SetScript("OnUpdate", function()
        elapsed = elapsed + arg1
        if elapsed < SCAN_INTERVAL then return end
        elapsed = 0
        
        if not TankMark.IsRecorderActive then
            if not TankMark:CanAutomate() then return end
            if L._GetNumRaidMembers() == 0 and L._GetNumPartyMembers() == 0 then return end
        end
        
        -- 1. RESET PHASE
        -- Clear visible targets map
        for k in L._pairs(TankMark.visibleTargets) do 
            TankMark.visibleTargets[k] = nil 
        end
        
        local batchIndex = 0
        
        -- 2. SNAPSHOT PHASE
        -- Capture current nameplates
        local frames = {WorldFrame:GetChildren()}
        
        for _, plate in L._ipairs(frames) do
            if plate:IsVisible() and TankMark:IsNameplate(plate) then
                local guid = plate:GetName(1)
                if guid then
                    TankMark.visibleTargets[guid] = true
                    
                    local activeIcon = TankMark.activeGUIDs[guid]
                    
                    if activeIcon then
                        -- [SYNC] KNOWN BLOCKER
                        -- Reinforce memory of marks we can see
                        TankMark.MarkMemory[activeIcon] = guid
                    else
                        -- [BUFFER] CANDIDATE
                        if TankMark.IsRecorderActive or TankMark:IsGUIDInCombat(guid) then
                            local name = L._UnitName(guid)
                            local hp = L._UnitHealth(guid) or 999999
                            local prio = 5
                            
                            if name and TankMark.activeDB and TankMark.activeDB[name] then
                                prio = TankMark.activeDB[name].prio or 5
                            end
                            
                            batchIndex = batchIndex + 1
                            
                            -- [OPTIMIZATION] Table Reuse
                            if not batchCandidates[batchIndex] then
                                batchCandidates[batchIndex] = {}
                            end
                            
                            local candidate = batchCandidates[batchIndex]
                            candidate.guid = guid
                            candidate.prio = L._tonumber(prio) or 5
                            candidate.hp = hp
                        end
                    end
                end
            end
        end
        
        -- 3. DECISION PHASE
        if batchIndex > 0 then
            -- [OPTIMIZATION] Trim the Tail
            local totalSize = L._tgetn(batchCandidates)
            if totalSize > batchIndex then
                for i = batchIndex + 1, totalSize do
                    batchCandidates[i] = nil
                end
            end
            
            -- Sort candidates (Priority ASC, then HP ASC)
            L._tsort(batchCandidates, function(a, b)
                if not a or not b then return false end
                if a.prio ~= b.prio then return a.prio < b.prio end
                return a.hp < b.hp
            end)
            
            -- Execute Assignments
            for i = 1, batchIndex do
                local candidate = batchCandidates[i]
                if candidate and candidate.guid then
                    TankMark:ProcessUnit(candidate.guid, "SCANNER")
                end
            end
        end
        
        -- 4. CLEANUP PHASE
        if TankMark.IsSuperWoW and TankMark.ReviewSkullState and not TankMark.IsRecorderActive then
            TankMark:ReviewSkullState("SCANNER_TICK")
        end
    end)
end

-- ==========================================================
-- UTILITIES
-- ==========================================================
function TankMark:IsGUIDInCombat(guid)
    if not guid then return false end
    local targetUnit = guid.."target"
    if not L._UnitExists(targetUnit) then return false end
    if L._UnitIsPlayer(targetUnit) then
        local targetName = L._UnitName(targetUnit)
        if targetName and TankMark:IsPlayerInRaid(targetName) then return true end
    end
    if L._UnitPlayerControlled(targetUnit) then
        local ownerUnit = targetUnit.."owner"
        if L._UnitExists(ownerUnit) and L._UnitIsPlayer(ownerUnit) then
            local ownerName = L._UnitName(ownerUnit)
            if ownerName and TankMark:IsPlayerInRaid(ownerName) then return true end
        end
    end
    return false
end

function TankMark:IsNameplate(frame)
    if not frame or not frame.GetChildren or not frame:IsVisible() then return false end
    local children = {frame:GetChildren()}
    for _, child in L._ipairs(children) do
        if child.GetValue and child.GetMinMaxValues and child.SetMinMaxValues then return true end
    end
    return false
end

function TankMark:ScanForRangeSpell()
    -- 1. SuperWoW Path
    if TankMark.IsSuperWoW then
        TankMark.RangeSpellID = 16707
        TankMark.RangeSpellIndex = nil
        return
    end

    -- 2. Standard Client Path (Scan for Name -> Store Index)
    local longRangeSpells = {
        ["Fireball"] = 35, ["Frostbolt"] = 30, ["Shadow Bolt"] = 30,
        ["Wrath"] = 30, ["Lightning Bolt"] = 30, ["Starfire"] = 30,
        ["Shoot"] = 30, ["Shoot Bow"] = 30, ["Shoot Gun"] = 30, ["Shoot Crossbow"] = 30,
        ["Hunter's Mark"] = 100, ["Mind Blast"] = 30, ["Smite"] = 30
    }
    
    local bestName = nil
    local bestRange = 0
    local bestIndex = nil
    local i = 1
    
    while true do
        if i > 1000 then break end -- Safety Cap
        local spellName, rank = L._GetSpellName(i, "spell")
        if not spellName then break end
        
        if longRangeSpells[spellName] then
            local range = longRangeSpells[spellName]
            if range > bestRange then
                bestRange = range
                bestName = spellName
                bestIndex = i
            end
        end
        i = i + 1
    end
    
    if bestIndex then
        TankMark.RangeSpellIndex = bestIndex
        TankMark.RangeSpellID = nil
        TankMark:Print("Range Extension: Legacy Mode (" .. bestName .. " ~" .. bestRange .. "y).")
    else
        TankMark.RangeSpellIndex = nil
        TankMark.RangeSpellID = nil
    end
end

function TankMark:Driver_IsDistanceValid(unitOrGuid)
    if TankMark.IsSuperWoW and TankMark.RangeSpellID and L._IsSpellInRange then
        if L._IsSpellInRange(TankMark.RangeSpellID, unitOrGuid) == 1 then return true end
    end
    if L._type(unitOrGuid) == "string" and L._strfind(unitOrGuid, "^0x") then
        local exists, mouseoverGuid = L._UnitExists("mouseover")
        if exists and mouseoverGuid == unitOrGuid then return true end
        return false
    end
    if TankMark.RangeSpellIndex and L._IsSpellInRange then
        if L._IsSpellInRange(TankMark.RangeSpellIndex, "spell", unitOrGuid) == 1 then return true end
    end
    if L._type(unitOrGuid) == "string" and not L._strfind(unitOrGuid, "^0x") then
        return L._CheckInteractDistance(unitOrGuid, 4)
    end
    return false
end