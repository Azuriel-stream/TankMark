-- Core marking decision logic

if not TankMark then return end

local L = TankMark.Locals

-- ==========================================================
-- LIVE BOARD (decide/apply split Tier 2, roadmap #2)
-- ==========================================================
-- [v0.28] The single dependency the pure decision layer (DecideMark and below)
-- reads the outside world through: one table of closures over the live TankMark
-- methods. Closures resolve at CALL time, so Ledger ownership reads stay LIVE
-- across a scanner tick (candidate #1's Assign is visible to candidate #2's
-- getFreeTankIcon) -- a frozen snapshot could not do that. Tests inject a mock
-- board instead, so the decision functions never touch a WoW/Ledger/session
-- global directly. Built once: the closures never change tick to tick.
TankMark.LiveBoard = {
    playerInCombat      = function()      return L._UnitAffectingCombat("player") end,
    guidInCombat        = function(guid)  return TankMark:IsGUIDInCombat(guid) end,
    isMarkBusy          = function(icon)  return TankMark:IsMarkBusy(icon) end,
    markOwnerPriority   = function(icon)  return TankMark:GetMarkOwnerPriority(icon) end,
    getFreeTankIcon     = function()      return TankMark:GetFreeTankIcon() end,
    getBlockingMarkInfo = function()      return TankMark:GetBlockingMarkInfo() end,
    -- [v0.30] legal-CC ports (Phase 2): the live creatureType read and the
    -- role=="CC" profile-slot snapshot. The CC routing decision itself is the
    -- pure SelectCCSlot, so these two only do the live reads.
    creatureType        = function(guid)  return L._UnitCreatureType(guid) end,
    getCCSlots          = function()      return TankMark:GetCCSlots() end,
    -- [v0.30] Phase 4 ports: live tier (UnitClassification) for CC-worthiness /
    -- tier-immunity, and the tank roster for the kill ladder. DecidePull reads
    -- these; the per-mob DecideMark path does not.
    tier                = function(guid)  return L._UnitClassification(guid) end,
    getTankRoster       = function()      return TankMark:GetTankRoster(TankMark:GetCachedZone()) end,
    isDisabled          = function(icon)  return TankMark.disabledMarks[icon] end,
    -- [v0.28] Side-effect SINK (not a read): the single DECIDE log. Production
    -- emits the guarded DebugLog (resolving the unknown-path name via UnitName);
    -- tests pass a no-op. Keeps the one-log-site Tier 1 created while letting
    -- DecideMark stay zero-global -- the last global it touched lived here.
    logDecision         = function(mobData, guid, intent)
        if not TankMark.DebugEnabled then return end
        TankMark:DebugLog("DECIDE", (mobData and "known: " or "unknown: ") .. (intent.reason or "?"), {
            icon     = intent.icon,
            mob      = mobData and mobData.name or L._UnitName(guid),
            prio     = mobData and mobData.prio,
            wasBusy  = intent.wasBusy,
            override = intent.override
        })
    end,
}

-- ==========================================================
-- PROCESS LOGIC
-- ==========================================================

function TankMark:ProcessUnit(guid, mode)
    if not guid then return end

    -- [DEBUG] Entry point
    local mobName = L._UnitName(guid)
    if TankMark.DebugEnabled then
        TankMark:DebugLog("PROCESS", "ProcessUnit entry", {
            guid = guid,
            mob  = mobName or "nil",
            mode = mode
        })
    end

    -- 1. Sanity Checks
    if L._UnitIsDead(guid) then
        if TankMark.DebugEnabled then
            TankMark:DebugLog("PROCESS", "Skipped: dead", { mob = mobName })
        end
        return
    end
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
    local zone        = TankMark:GetCachedZone()
    local hasActiveDB = (TankMark.activeDB and L._next(TankMark.activeDB) ~= nil)
    local dbExists    = hasActiveDB
    if not dbExists and mode ~= "FORCE" then return end

    -- 3. Check Current Mark
    local currentIcon = L._GetRaidTargetIndex(guid)

    -- [DEBUG] Log what GetRaidTargetIndex returned
    if currentIcon then
        if TankMark.DebugEnabled then
            TankMark:DebugLog("PROCESS", "GetRaidTargetIndex returned", {
                guid = guid,
                mob  = mobName,
                icon = currentIcon
            })
        end
    end

    -- [v0.26 FIX] Verify ownership server-side before trusting GetRaidTargetIndex.
    -- After a mark theft, GetRaidTargetIndex can return a stale icon for the
    -- previous owner, causing ghost re-registration and locking the unit out of
    -- receiving a new mark permanently.
    if currentIcon then
        local exists, actualHolderGUID = L._UnitExists("mark"..currentIcon)
        if not exists or actualHolderGUID ~= guid then
            if TankMark.DebugEnabled then
                TankMark:DebugLog("PROCESS", "Ownership mismatch - nulling currentIcon", {
                    icon         = currentIcon,
                    expectedGUID = guid,
                    actualGUID   = actualHolderGUID and L._sub(actualHolderGUID, 1, 10).."..." or "nil"
                })
            end
            currentIcon = nil
        end
    end

    if currentIcon then
        if not TankMark.Ledger.IsUsed(currentIcon) or not TankMark.Ledger.IconOf(guid) then
            if TankMark.DebugEnabled then
                TankMark:DebugLog("PROCESS", "Re-registering existing mark", {
                    icon       = currentIcon,
                    guid       = guid,
                    mob        = mobName,
                    usedIcons  = L._tostring(TankMark.Ledger.IsUsed(currentIcon)),
                    activeGUIDs = L._tostring(TankMark.Ledger.IconOf(guid))
                })
            end
            TankMark:RegisterMarkUsage(currentIcon, L._UnitName(guid), guid, false)
        end
        return
    end

    -- [FIX] At this point currentIcon is nil - the mob has no mark in-game.
    -- If activeGUIDs still has an entry for this GUID, it is a stale record from
    -- a previous encounter (or an externally removed mark). Invalidate it and
    -- fall through so DecideMark can re-mark the mob correctly.
    -- Only the icon-level state (usedIcons, MarkMemory, etc.) is cleared if
    -- MarkMemory confirms this mob still owns that slot, preventing us from
    -- accidentally evicting a different mob that has since taken the same icon.
    if TankMark.Ledger.IconOf(guid) then
        if TankMark.DebugEnabled then
            TankMark:DebugLog("PROCESS", "Stale activeGUIDs - invalidating", {
                guid         = guid,
                mob          = mobName or "nil",
                expectedIcon = TankMark.Ledger.IconOf(guid)
            })
        end
        TankMark.Ledger.Evict(guid)
        -- Fall through to re-mark below
    end

    -- 5. Logic: Mob Name Lookup
    local mobName = L._UnitName(guid)
    if not mobName then return end
    local mobData = nil
    if TankMark.activeDB and TankMark.activeDB[mobName] then
        mobData = TankMark.activeDB[mobName]
    end
    if mobData then
        mobData.name = mobName
    elseif mode ~= "FORCE" and mode ~= "SCANNER" then
        -- Unknown mobs are only marked under FORCE/SCANNER.
        return
    end

    -- [v0.28] Decide once via the unified seam, then apply at the centralized edge.
    local intent = TankMark:DecideMark(mobData, guid, mode, TankMark.LiveBoard)
    if intent.icon then
        TankMark:ApplyMarkIntent(guid, mobName, intent, false)
    end
end

-- [v0.26] Helper to check if a mark is truly busy
function TankMark:IsMarkBusy(iconID)
    local reason = nil
    local result = false
    if TankMark.Ledger.OwnerOf(iconID) then
        reason = "MarkMemory"
        result = true
    elseif L._UnitExists("mark"..iconID) and not L._UnitIsDead("mark"..iconID) then
        reason = "MarkUnit"
        result = true
    elseif TankMark.Ledger.IsUsed(iconID) then
        reason = "usedIcons"
        result = true
    end

    -- [DEBUG] Log every IsMarkBusy check (generic)
    if TankMark.DebugEnabled then
        local holderGUID = TankMark.Ledger.OwnerOf(iconID)
        TankMark:DebugLog("BUSY", "IsMarkBusy(" .. L._tostring(iconID) .. ") check", {
            result  = L._tostring(result),
            reason  = reason or "none",
            Memory  = holderGUID and L._sub(holderGUID, 1, 10) .. "..." or "nil",
            used    = L._tostring(TankMark.Ledger.IsUsed(iconID))
        })
    end
    
    return result
end

-- [v0.26] Helper to find priority of current mark holder
function TankMark:GetMarkOwnerPriority(iconID)
    local holderGUID = TankMark.Ledger.OwnerOf(iconID)

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

-- [v0.28] Shared skull governor gate (decide/apply split, roadmap #2). Collapses
-- the duplicated incumbency checks from the known + unknown decision paths into
-- one helper. Returns a block-reason string, or nil if the icon is allowed.
-- Only gates Skull (icon 8) and only when mode ~= "FORCE".
--   allowSteal=true  (known): may steal an occupied skull if myPrio < ownerPrio.
--   allowSteal=false (unknown, prio 5): never steals -- any busy skull blocks.
-- The allowSteal split is the DELIBERATE prio-5 asymmetry, not a TODO: known
-- honors its DB designation (asserts the plan over a phantom/foreign holder),
-- while unknown has nothing to assert and stays hands-off an occupied skull.
-- [v0.28] policy RESOLVED -- roadmap #3's last loose end: unknown NEVER steals
-- (decided 2026-06-23; no behavior change -- this was already the shipped state).
-- Both operators stay distinct: `myPrio < ownerPrio` (steal an occupied skull)
-- and `myPrio >= blockPrio` (incumbency block when skull is free).
function TankMark:GovernorBlocks(icon, myPrio, mode, allowSteal, board)
    if icon ~= 8 or mode == "FORCE" then return nil end
    if board.isMarkBusy(8) then
        -- Skull TAKEN.
        if not allowSteal then return "governor-skull-taken" end
        local ownerPrio = board.markOwnerPriority(8)
        if not (myPrio < ownerPrio) then return "governor-skull-taken" end
        return nil
    end
    -- Skull FREE: yield to a lower incumbent mark (incumbency).
    local blockIcon, _, blockPrio, _ = board.getBlockingMarkInfo()
    -- [v0.28] Incumbency rule via the shared IncumbencyBlocks predicate
    -- (single-sourced with ReviewSkullState so >= can't drift). IncumbencyBlocks
    -- stays a direct pure-value call -- not a board port (it reads no state).
    if TankMark:IncumbencyBlocks(myPrio, blockIcon, blockPrio) then
        return "governor-incumbency"
    end
    return nil
end

-- [v0.30] CC resolver seam (legal-CC routing, marking-redesign Phase 2). Returns
-- the CC mark for this mob, or nil if it is not a CC target or no legal CC slot
-- qualifies. Owns the type=="CC" guard. creatureType is read LIVE first (free,
-- authoritative) with the stored mobData.creatureType as fallback for the
-- off-client harness; no write-back (respects the Phase-1 lazy-backfill cut).
-- The routing decision is the pure SelectCCSlot over the live getCCSlots()
-- snapshot -- this seam only resolves creatureType and orchestrates. A nil class
-- is allowed now (routes on creatureType alone); a fully-unknown creatureType
-- degrades to authored-class-only inside SelectCCSlot.
function TankMark:ResolveCC(mobData, guid, board)
    if mobData.type ~= "CC" then return nil end
    local ct = board.creatureType(guid) or mobData.creatureType
    return TankMark:SelectCCSlot(mobData.class, ct, board.getCCSlots())
end

-- [v0.28] Known-mob decision (decide/apply split, roadmap #2). Returns an
-- inspectable intent { icon, reason, wasBusy?, override? } and applies NOTHING.
-- Order: sequential/zero bails -> SCANNER combat gate -> CC seam -> primary-mark
-- selection (with selection-time skull theft, myPrio < ownerPrio) -> free-icon
-- fallback -> skull governor gate. Skips are values, not bare returns.
--
-- Governor landmine: BOTH operators are preserved and MUST stay distinct --
-- `myPrio < ownerPrio` (steal an occupied skull) and `myPrio >= blockPrio`
-- (incumbency block when skull is free). The governor gate is the shared
-- GovernorBlocks helper (allowSteal=true here). Sequential (marks>1) stays out
-- of scope -- Batch owns that cursor.
function TankMark:DecideKnownMark(mobData, guid, mode, board)
    if mobData.marks and L._tgetn(mobData.marks) > 1 then
        return { icon = nil, reason = "sequential-marks" }
    end
    local markToUse = mobData.marks and mobData.marks[1] or 8
    if markToUse == 0 then
        return { icon = nil, reason = "mark-zero" }
    end

    if mode == "SCANNER" then
        local playerInCombat = board.playerInCombat()
        local mobInCombat    = board.guidInCombat(guid)
        if not mobInCombat and not playerInCombat then
            return { icon = nil, reason = "not-in-combat" }
        end
    end

    local iconToApply = nil
    local isBusy      = false
    local canOverride = false

    -- [v0.28] CC Logic via ResolveCC seam. [v0.30] passes guid for the live
    -- creatureType read (legal-CC routing, Phase 2).
    iconToApply = TankMark:ResolveCC(mobData, guid, board)

    if not iconToApply then
        isBusy = board.isMarkBusy(markToUse)

        -- [v0.26] AGGRESSIVE THEFT LOGIC (selection-time steal of an occupied
        -- primary skull; inline because it is icon selection, not a block).
        if isBusy and markToUse == 8 then
            local myPrio    = mobData.prio or 5
            local ownerPrio = board.markOwnerPriority(markToUse)
            if myPrio < ownerPrio then
                canOverride = true
            end
        end

        if (not isBusy or canOverride) and (mode == "FORCE" or not board.isDisabled(markToUse)) then
            iconToApply = markToUse
        end

        -- Fallback to free icon only if we failed to secure the primary mark
        if not iconToApply then
            iconToApply = board.getFreeTankIcon()
        end
    end

    if not iconToApply then
        return { icon = nil, reason = "no-icon", wasBusy = isBusy }
    end

    -- [v0.28] GOVERNOR CHECK via shared helper. Known mobs may steal an occupied
    -- skull (allowSteal=true) when they outrank the holder.
    local block = TankMark:GovernorBlocks(iconToApply, mobData.prio or 5, mode, true, board)
    if block then
        return { icon = nil, reason = block, wasBusy = isBusy }
    end

    return { icon = iconToApply, reason = "known", wasBusy = isBusy, override = canOverride }
end

-- [v0.28] Single decision entry point (decide/apply split, roadmap #2). Routes
-- by mobData (nil -> unknown path), logs the resulting intent ONCE, and returns
-- an inspectable intent { icon, reason, ... }. Applies NOTHING -- callers apply
-- via ApplyMarkIntent. ProcessUnit (scanner) and the Batch shims all funnel
-- through here, so the decision and its DECIDE log live in exactly one place.
function TankMark:DecideMark(mobData, guid, mode, board)
    local intent
    if mobData == nil then
        intent = TankMark:DecideUnknownMark(guid, mode, board)
    else
        intent = TankMark:DecideKnownMark(mobData, guid, mode, board)
    end
    board.logDecision(mobData, guid, intent)
    return intent
end

-- [v0.28] Unknown-mob decision (decide/apply split, roadmap #2). Returns an
-- inspectable intent { icon, reason } and applies NOTHING; the shell applies.
-- Unknown mobs are Prio 5: they take the highest free tank icon, and only take
-- Skull when it is genuinely free -- they NEVER steal it (allowSteal=false, the
-- prio-5 case of the governor; [v0.28] policy RESOLVED, not deferred -- see
-- GovernorBlocks). Skips are values, not bare returns.
function TankMark:DecideUnknownMark(guid, mode, board)
    if mode == "SCANNER" then
        local playerInCombat = board.playerInCombat()
        local mobInCombat    = board.guidInCombat(guid)
        if not mobInCombat and not playerInCombat then
            return { icon = nil, reason = "not-in-combat" }
        end
    end

    local iconToApply = board.getFreeTankIcon()
    if not iconToApply then
        return { icon = nil, reason = "no-free-icon" }
    end

    -- [v0.28] Prio 5, allowSteal=false: never steal an occupied skull; yield to
    -- a lower incumbent. Same shared governor as the known path.
    local block = TankMark:GovernorBlocks(iconToApply, 5, mode, false, board)
    if block then
        return { icon = nil, reason = block }
    end

    return { icon = iconToApply, reason = "unknown-free" }
end

-- [v0.28] Centralized apply edge for the decide/apply split (roadmap #2).
-- The single place a mark intent becomes action: record ownership in the Ledger
-- (via RegisterMarkUsage) BEFORE applying, so state is consistent when
-- RAID_TARGET_UPDATE fires, then call the sole SetRaidTarget driver. `intent` is
-- the decision table { icon = N, reason?, override?, wasBusy? }; a nil/iconless
-- intent is a no-op skip. `skipProfileLookup` is apply-policy, not a decision
-- field (false for the scanner/decide path; the Batch sequential path passes
-- true). Driver_ApplyMark stays the lone SetRaidTarget site.
function TankMark:ApplyMarkIntent(guid, name, intent, skipProfileLookup)
    if not intent or not intent.icon then return end
    TankMark:RegisterMarkUsage(intent.icon, name, guid, skipProfileLookup)
    TankMark:Driver_ApplyMark(guid, intent.icon)
end

function TankMark:RegisterMarkUsage(icon, name, guid, skipProfileLookup)
    TankMark.Ledger.Assign(icon, guid, name)
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
    -- [v0.30] Tier-A metadata: stamp creatureType + tier (cType already read above).
    -- Convenience cache only -- the decision layer re-reads these live; never a runtime input.
    local tier = L._UnitClassification(guid)
    TankMarkDB.Zones[zone][name] = {
        prio  = 5,
        marks = {8},
        type  = "KILL",
        class = nil,
        creatureType = cType,
        tier = tier
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
