-- SuperWoW nameplate scanner with Snapshot Batching and Table Reuse

if not TankMark then return end

local L = TankMark.Locals

local SCAN_INTERVAL = 0.5

-- [v0.26] Batch Buffers
local batchCandidates = {}

TankMark.visibleTargets = {}
TankMark.IsSuperWoW = false

function TankMark:InitDriver()
    if L._type(SUPERWOW_VERSION) ~= "nil" then
        TankMark.IsSuperWoW = true
        TankMark:Print("SuperWoW Detected: |cff00ff00Scanner active.|r")
        TankMark:StartSuperScanner()
    else
        TankMark:Print("|cffff0000TankMark requires SuperWoW. Automation disabled.|r")
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
                    
                    local activeIcon = TankMark.Ledger.IconOf(guid)
                    
                    if activeIcon then
                        -- [SYNC] KNOWN BLOCKER
                        -- Reinforce memory of marks we can see
                        TankMark.Ledger.Reaffirm(activeIcon, guid)
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
        -- [v0.28] Skip skull review when there is provably nothing to review: no skull
        -- token to adopt/reassess AND no unmarked in-combat candidate this tick
        -- (batchIndex counts exactly the unmarked in-combat candidates this tick, the
        -- same set FindEmergencyCandidate would search). Death-driven reassignment is
        -- unaffected -- it runs via the COMBAT_LOG/UNIT_DEATH callers, not this tick.
        if TankMark.ReviewSkullState and not TankMark.IsRecorderActive
            and (batchIndex > 0 or L._UnitExists("mark8")) then
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

-- [v0.27] Range gating removed with the non-SuperWoW path. The scanner relies on
-- nameplate visibility plus combat state; SuperWoW mark units are visibility-independent.
