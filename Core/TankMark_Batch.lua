-- TankMark: v0.26
-- File: Core/TankMark_Batch.lua
-- Module Version: 1.0
-- Last Updated: 2026-02-08
-- Batch marking system (Shift+Mouseover)

if not TankMark then return end

-- Import shared localizations
local L = TankMark.Locals

-- ==========================================================
-- BATCH PROCESSING CONSTANTS
-- ==========================================================

local BATCH_MARK_DELAY = 0.05 -- 50ms delay between marks

-- ==========================================================
-- BATCH STATE
-- ==========================================================

TankMark.batchMarkQueue = {}
TankMark.batchQueueTimer = 0
TankMark.batchCandidates = {} -- Temporary collection during Shift-hold
TankMark.batchSequence = 0 -- [v0.21] Track mouseover order
TankMark.batchSkipCounters = {}

-- ==========================================================
-- BATCH COLLECTION
-- ==========================================================

-- Add candidate to batch collection (called during Shift-hold)
function TankMark:AddBatchCandidate(guid)
    if not guid then return end
    
    -- Ignore duplicates
    if TankMark.batchCandidates[guid] then return end
    
    -- Basic validation (skip already-marked, dead, friendly)
    if L._UnitIsDead(guid) then return end
    if L._UnitIsPlayer(guid) or L._UnitIsFriend("player", guid) then return end
    
    -- [v0.22 FIX] Combat filtering depends on SuperWoW availability
    -- WITH SuperWoW: Skip combat mobs (scanner will handle them automatically)
    -- WITHOUT SuperWoW: Allow combat mobs (batch marking is the only marking method)
    if TankMark.IsSuperWoW and TankMark:IsGUIDInCombat(guid) then
        return
    end
    
    local mobName = L._UnitName(guid)
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

-- ==========================================================
-- BATCH EXECUTION
-- ==========================================================

-- Execute batch marking (called on Shift release)
function TankMark:ExecuteBatchMarking()
    -- Check if any candidates collected
    local candidateCount = 0
    for _ in L._pairs(TankMark.batchCandidates) do
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
    
    -- [v0.24] Initialize skip counters
    TankMark.batchSkipCounters = {
        alreadyMarked = 0,
        dead = 0,
        inCombat = 0,
        normalMob = 0,
        total = 0
    }
    
    -- Convert hashmap to array
    local sortedCandidates = {}
    for guid, data in L._pairs(TankMark.batchCandidates) do
        L._tinsert(sortedCandidates, data)
    end
    
    -- [v0.21] Sort by priority (ascending), then by sequence (mouseover order)
    L._tsort(sortedCandidates, function(a, b)
        if a.prio == b.prio then
            return (a.sequence or 0) < (b.sequence or 0) -- Handle nil gracefully
        end
        return a.prio < b.prio
    end)
    
    -- Limit to top 8
    local maxMarks = L._min(8, L._tgetn(sortedCandidates))
    
    -- Build queue for delayed execution
    TankMark.batchMarkQueue = {}
    for i = 1, maxMarks do
        L._tinsert(TankMark.batchMarkQueue, {
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

-- ==========================================================
-- BATCH PROCESSOR
-- ==========================================================

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
        if TankMark.batchCurrentIndex > L._tgetn(TankMark.batchMarkQueue) then
            TankMark.batchProcessorFrame:SetScript("OnUpdate", nil)
            TankMark.batchCurrentIndex = 1
            
            -- [v0.23] Print skip summary if any mobs were skipped
            if TankMark.batchSkipCounters and TankMark.batchSkipCounters.total > 0 then
                local skipMsg = "|cffffaa00Skipped " .. TankMark.batchSkipCounters.total .. " mob(s):|r"
                if TankMark.batchSkipCounters.alreadyMarked > 0 then
                    skipMsg = skipMsg .. " " .. TankMark.batchSkipCounters.alreadyMarked .. " already marked"
                end
                if TankMark.batchSkipCounters.dead > 0 then
                    skipMsg = skipMsg .. " " .. TankMark.batchSkipCounters.dead .. " dead/gone"
                end
                if TankMark.batchSkipCounters.inCombat > 0 then
                    skipMsg = skipMsg .. " " .. TankMark.batchSkipCounters.inCombat .. " in combat"
                end
                if TankMark.batchSkipCounters.normalMob > 0 then
                    skipMsg = skipMsg .. " " .. TankMark.batchSkipCounters.normalMob .. " normal mobs"
                end
                TankMark:Print(skipMsg)
            end
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
    if not L._UnitExists(guid) then
        TankMark.batchSkipCounters.dead = TankMark.batchSkipCounters.dead + 1
        TankMark.batchSkipCounters.total = TankMark.batchSkipCounters.total + 1
        return
    end
    
    if L._UnitIsDead(guid) then
        TankMark.batchSkipCounters.dead = TankMark.batchSkipCounters.dead + 1
        TankMark.batchSkipCounters.total = TankMark.batchSkipCounters.total + 1
        return
    end
    
    if L._GetRaidTargetIndex(guid) then
        TankMark.batchSkipCounters.alreadyMarked = TankMark.batchSkipCounters.alreadyMarked + 1
        TankMark.batchSkipCounters.total = TankMark.batchSkipCounters.total + 1
        return
    end
    
    -- [v0.22 FIX] Combat filtering depends on SuperWoW availability
    -- WITH SuperWoW: Skip combat mobs (let scanner handle them)
    -- WITHOUT SuperWoW: Process combat mobs (batch marking is the only option)
    if TankMark.IsSuperWoW and TankMark:IsGUIDInCombat(guid) then
        TankMark.batchSkipCounters.inCombat = TankMark.batchSkipCounters.inCombat + 1
        TankMark.batchSkipCounters.total = TankMark.batchSkipCounters.total + 1
        return
    end
    
    -- [v0.21] Respect MarkNormals filter for batch marking
    if not TankMark.MarkNormals then
        local cls = L._UnitClassification(guid)
        if cls == "normal" or cls == "trivial" or cls == "minus" then
            TankMark.batchSkipCounters.normalMob = TankMark.batchSkipCounters.normalMob + 1
            TankMark.batchSkipCounters.total = TankMark.batchSkipCounters.total + 1
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
    if mobData and mobData.marks and L._tgetn(mobData.marks) > 1 then
        -- Initialize cursor for this mob name
        if not TankMark.sequentialMarkCursor[mobName] then
            TankMark.sequentialMarkCursor[mobName] = 1
        end
        
        local cursorIndex = TankMark.sequentialMarkCursor[mobName]
        local iconToApply = mobData.marks[cursorIndex]
        
        -- [v0.27] Update MarkMemory BEFORE applying mark (matches ProcessKnownMob pattern)
        -- This protects the mark from ReviewSkullState interference during the batch window
        if TankMark.MarkMemory then
            TankMark.MarkMemory[iconToApply] = guid
        end
        
        -- Apply mark (ignore conflicts per user requirement)
        TankMark:Driver_ApplyMark(guid, iconToApply)
        TankMark:RegisterMarkUsage(iconToApply, mobName, guid, false, true) -- skipProfileLookup = true
        
        -- Advance cursor (with wraparound safety)
        TankMark.sequentialMarkCursor[mobName] = cursorIndex + 1
        if TankMark.sequentialMarkCursor[mobName] > L._tgetn(mobData.marks) then
            TankMark.sequentialMarkCursor[mobName] = 1 -- Reset (for 5th+ mobs)
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
