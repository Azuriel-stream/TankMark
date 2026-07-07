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
-- [v0.32] slice C: TWO-SWEEP DRAIN KERNEL (Ascension)
-- ==========================================================
-- On Ascension the batch arms a durable {guid->icon} plan on sweep 1 (ExecuteBatch-
-- Marking, force-DecidePull); sweep 2 drains it per-hover onto the LIVE mouseover
-- token, because a GUID is not a re-readable handle there (ADR 0004). TakePlanIcon is
-- the PURE seam of that drain -- it owns the plan mutation only: return the planned
-- icon for `guid` (removing that entry), or nil if guid is not in the plan / no plan
-- is armed. On FULL drain the plan DISARMS (pullPlan -> nil) so the next Shift+hold
-- begins a fresh collect sweep. The WoW-edge apply (Driver_ApplyMark on the token)
-- stays in the thin drain-hover handler; this function never touches the world.
function TankMark:TakePlanIcon(guid)
    local plan = TankMark.pullPlan
    if not plan or not guid then return nil end
    local icon = plan[guid]
    if not icon then return nil end
    plan[guid] = nil
    -- Disarm on full drain: if no entries remain, retire the plan.
    local remaining = false
    for _ in L._pairs(plan) do remaining = true; break end
    if not remaining then TankMark.pullPlan = nil end
    return icon
end

-- ==========================================================
-- BATCH COLLECTION
-- ==========================================================

-- Add candidate to batch collection (called during Shift-hold)
function TankMark:AddBatchCandidate(guid)
    if not guid then return end
    
    -- Ignore duplicates
    if TankMark.batchCandidates[guid] then return end

    -- [v0.32] slice C: on a scanner-less platform (Ascension) a GUID is not a
    -- re-readable handle, so read the mob's live attributes off the LIVE mouseover
    -- token -- AddBatchCandidate is only ever called at hover time, with mouseover
    -- live. On Vanilla the GUID IS addressable (SuperWoW), so readUnit stays the GUID
    -- and every read below is byte-identical. The GUID is kept as the identity/dedup
    -- key and the plan key regardless.
    local readUnit = TankMark.Platform.Caps.hasScanner and guid or "mouseover"

    -- Basic validation (skip already-marked, dead, friendly)
    if L._UnitIsDead(readUnit) then return end
    if L._UnitIsPlayer(readUnit) or L._UnitIsFriend("player", readUnit) then return end

    -- [v0.32] Skip combat mobs only when a scanner will handle them (Vanilla).
    -- Without a scanner (Ascension, Platform.Caps.hasScanner=false) the batch is
    -- the only in-combat marker, so it must NOT skip them. See ADR 0004.
    if TankMark.Platform.Caps.hasScanner and TankMark:IsGUIDInCombat(guid) then
        return
    end

    local mobName = L._UnitName(readUnit)
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
    
    -- [v0.29] slice 3: manual batch is gated to the swarm queen, not just eligibility
    -- (honors "drones have no SetRaidTarget path"). A drone (eligible but not queen) is
    -- told who the active marker is, rather than a misleading permission error.
    if not TankMark:ShouldDriveMarks() then
        if TankMark:CanAutomate() then
            local q = TankMark.Swarm and TankMark.Swarm.currentQueen
            TankMark:Print("|cffff0000Batch marking suppressed:|r " .. (q and (q .. " is the active marker.") or "another client is the active marker."))
        else
            TankMark:Print("|cffff0000Batch marking aborted: Permission/Profile check failed.|r")
        end
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

    -- [v0.30] Phase 4 (A): smart pre-mark. When enabled, decide the WHOLE pack at
    -- once (DecidePull) and stash a guid->icon plan; ProcessBatchMark applies it
    -- per mob through the existing delayed queue + re-validation. Sequential mobs
    -- are NOT in the plan (DecidePull partitions them out and reserves their
    -- icons), so they still run the cursor branch below. Toggle off -> no plan ->
    -- classic per-mob marking, unchanged.
    TankMark.pullPlan = nil
    -- [v0.32] slice C: on a scanner-less platform (Ascension) the plan path is the ONLY
    -- viable batch path -- the classic per-mob delayed-by-GUID queue below cannot apply
    -- to an ephemeral token -- so force DecidePull there regardless of the SmartMark
    -- toggle (which is a Vanilla-only choice). On Vanilla the toggle governs as before.
    if TankMark:SmartMarkEnabled() or not TankMark.Platform.Caps.hasScanner then
        local plan = TankMark:DecidePull(sortedCandidates, TankMark.LiveBoard)
        TankMark.pullPlan = {}
        for _, intent in L._ipairs(plan.intents) do
            TankMark.pullPlan[intent.guid] = intent.icon
        end
        TankMark:ReportPullPlan(plan)
    end

    -- [v0.32] slice C: on Ascension the plan is ARMED for a second Shift+mouseover sweep
    -- that drains it onto live tokens (see the mouseover dispatch + TakePlanIcon) -- do
    -- NOT drive the delayed by-GUID queue. Arm only if DecidePull produced >=1 intent; an
    -- empty plan would trap the next hold in drain mode, so disarm instead. Vanilla
    -- (hasScanner) falls through to the synchronous queue below, exactly as before.
    if not TankMark.Platform.Caps.hasScanner then
        local armed = false
        if TankMark.pullPlan then
            for _ in L._pairs(TankMark.pullPlan) do armed = true; break end
        end
        if not armed then TankMark.pullPlan = nil end
        TankMark.batchCandidates = {}
        if armed then
            TankMark:Print("|cff00ff00Pull plan armed.|r Shift+mouseover the pack again to place the marks.")
        else
            TankMark:Print("|cffffaa00No marks to place for this pack.|r")
        end
        return
    end

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
    
    -- [v0.32] Skip combat mobs only when a scanner will handle them (Vanilla).
    -- Without a scanner (Ascension) the batch is the only in-combat marker. ADR 0004.
    if TankMark.Platform.Caps.hasScanner and TankMark:IsGUIDInCombat(guid) then
        TankMark.batchSkipCounters.inCombat = TankMark.batchSkipCounters.inCombat + 1
        TankMark.batchSkipCounters.total = TankMark.batchSkipCounters.total + 1
        return
    end
    
    -- [v0.21] Respect MarkNormals filter for batch marking
    if not TankMark:MarkNormalsEnabled() then
        local cls = L._UnitClassification(guid)
        if cls == "normal" or cls == "trivial" or cls == "minus" then
            TankMark.batchSkipCounters.normalMob = TankMark.batchSkipCounters.normalMob + 1
            TankMark.batchSkipCounters.total = TankMark.batchSkipCounters.total + 1
            return -- Skip normal mobs if filter is active
        end
    end
    
    -- [v0.29] slice 3: re-check the queen gate mid-batch (queen status can change
    -- during the batch window, e.g. a handover or rank change).
    if not TankMark:ShouldDriveMarks() then
        TankMark:Print("|cffff0000Batch marking aborted: no longer the active marker.|r")
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

        if cursorIndex > L._tgetn(mobData.marks) then
            -- [v0.28] Sequence exhausted: this body is beyond the defined
            -- sequence. Treat it as a free-icon pickup, governed like an unknown
            -- (prio 5, never steals). Never wrap back and re-grab marks[1] -- the
            -- former "Reset (for 5th+ mobs)" wrap re-stole an already-used icon
            -- (e.g. SKULL jumped off the first mob). Reuses the unknown
            -- decide/apply seam; cursor stays clamped past the end (no advance).
            local intent = TankMark:DecideUnknownMark(guid, "FORCE", TankMark.LiveBoard)
            if intent.icon then
                TankMark:ApplyMarkIntent(guid, mobName, intent, false)
            end
        else
            local iconToApply = mobData.marks[cursorIndex]

            -- [v0.27] Record ownership BEFORE applying the mark (matches ApplyMarkIntent's record-before-apply order).
            -- Protects the mark from ReviewSkullState interference during the batch window.
            TankMark:RegisterMarkUsage(iconToApply, mobName, guid, true) -- skipProfileLookup = true
            TankMark:Driver_ApplyMark(guid, iconToApply)

            -- Advance cursor (clamp, never wrap -- the exhausted branch above
            -- handles every body past the sequence length).
            TankMark.sequentialMarkCursor[mobName] = cursorIndex + 1
        end
    elseif TankMark.pullPlan then
        -- [v0.30] Phase 4 (A): smart pre-mark active. Apply the precomputed pull
        -- intent for this mob; a plan with no entry means it was deliberate
        -- overflow / un-CCable -> leave it unmarked (handed off to the scanner).
        local plannedIcon = TankMark.pullPlan[guid]
        if plannedIcon then
            local name = mobData and mobData.name or L._UnitName(guid)
            TankMark:ApplyMarkIntent(guid, name, { icon = plannedIcon }, false)
        end
    else
        -- [v0.28] Single-mark / unknown: decide via the unified seam, then apply
        -- at the centralized edge (migrated off the deleted Process* shims).
        local intent = TankMark:DecideMark(mobData, guid, "FORCE", TankMark.LiveBoard)
        if intent.icon then
            local name = mobData and mobData.name or L._UnitName(guid)
            TankMark:ApplyMarkIntent(guid, name, intent, false)
        end
    end
end
