-- Pull-level coordinated assignment (pack-aware marking) -- marking-redesign Phase 4 (A)

if not TankMark then return end

local L = TankMark.Locals

-- ==========================================================
-- [v0.30] DecidePull -- the pre-fight pack brain (Phase 4, part A)
-- ==========================================================
-- PURE + board-injected exactly like DecideMark: it reasons over the WHOLE
-- moused-over pack at once and returns intents -- it applies NOTHING. The Batch
-- shell feeds the intents into the existing delayed-apply queue
-- (ApplyMarkIntent -> Ledger.Assign -> Driver_ApplyMark, the sole SetRaidTarget
-- edge). Two passes over the candidate set:
--   CC pass   -- rank CC-able mobs by CCWorthiness, greedily fill the stable CC
--                slots via SelectCCSlot; authored type=="CC" forced to the top.
--   Kill pass -- the rest by prio onto the tank ladder (GetTankRoster, profile
--                order): skull to the top, ladder down, overflow handed off.
-- Eligibility = the three composing gates: IsLegalCC + CCRaceEligible live inside
-- SelectCCSlot (per slot); CCTierEligible is a MOB gate applied here, before slot
-- selection. Because it decides ALL marks before any apply, it keeps a LOCAL
-- in-pass `usedMarks` overlay (seeded from the board's busy/disabled state) in
-- place of the live Ledger that the per-mob loop relies on between applies.
-- See docs/marking-redesign/phase-4-pull-assignment.md for the ratified tree.

-- [v0.30] Phase 4 (A) opt-in: pack-aware pre-marking only runs when the player
-- turns it on (default off). Per-character (TankMarkCharConfig), like HUD prefs.
function TankMark:SmartMarkEnabled()
    return (TankMarkCharConfig and TankMarkCharConfig.smartMark) and true or false
end

-- Stable tiebreak so identical packs route identically (determinism is an
-- invariant): mouseover sequence, then guid (always unique). No time/random.
local function stableLess(a, b)
    local sa, sb = a.sequence or 0, b.sequence or 0
    if sa ~= sb then return sa < sb end
    return (a.guid or "") < (b.guid or "")
end

-- Snapshot the CC slots into a LOCAL copy so the in-pass "used" overlay never
-- mutates the board's data (which would break the same-pack-twice determinism).
local function copySlots(slots)
    local out = {}
    for _, s in L._ipairs(slots) do
        L._tinsert(out, {
            mark = s.mark, class = s.class, race = s.race,
            alive = s.alive, used = s.used, disabled = s.disabled,
        })
    end
    return out
end

-- candidates: array of { guid, name, mobData (or nil), sequence (optional) }
-- returns { intents = { {guid,name,icon,reason}, ... }, overflow = {..}, unccd = {..} }
--   intents  -- the marks to apply (CC + kill).
--   overflow -- kill mobs past the ladder; handed off to the in-combat scanner.
--   unccd    -- absolutely-worthy mobs (CCWorthiness >= 70) we could not CC.
function TankMark:DecidePull(candidates, board)
    local intents, overflow, unccd = {}, {}, {}
    local usedMarks = {}   -- icon -> true (board busy/disabled seed + in-pass)

    -- Seed reserved icons: anything already busy or HUD-disabled is unavailable.
    for icon = 1, 8 do
        if board.isMarkBusy(icon) or board.isDisabled(icon) then
            usedMarks[icon] = true
        end
    end

    -- 1. FILTER. Drop IGNORE; partition sequential mobs OUT and reserve their
    -- icons -- the Batch cursor force-applies those, so the brain must avoid them.
    local pack = {}
    for _, c in L._ipairs(candidates) do
        local md = c.mobData
        if md and md.marks and L._tgetn(md.marks) > 1 then
            for _, ic in L._ipairs(md.marks) do
                if ic and ic ~= 0 then usedMarks[ic] = true end
            end
        elseif md and (md.type == "IGNORE" or (md.marks and md.marks[1] == 0)) then
            -- IGNORE: excluded from both passes.
        else
            L._tinsert(pack, {
                guid = c.guid, name = c.name, sequence = c.sequence,
                role = md and md.role, prio = (md and md.prio) or 5,
                ctype = board.creatureType(c.guid) or (md and md.creatureType),
                tier  = board.tier(c.guid) or (md and md.tier),
                authoredCC = (md and md.type == "CC") or false,
                authoredClass = md and md.class,
            })
        end
    end

    -- 2. KILL PASS. [v0.30 CC-model rev / ADR 0002] prio IS the kill order: walk the
    -- tank ladder DOWN it (prio asc, seq asc) -- skull to the kill-FIRST, laddering.
    -- These are the priority kills; the CC pass (step 3) then claims eligible
    -- LEFTOVERS. Doing kills FIRST makes reserve-a-kill-target AUTOMATIC -- the
    -- ladder always claims the lowest-prio mob before CC can reach it, so a lone /
    -- low-prio mob is killed by construction and there is NO demotion step.
    L._tsort(pack, function(a, b)
        if a.prio ~= b.prio then return a.prio < b.prio end
        return stableLess(a, b)
    end)
    local roster = board.getTankRoster()
    local rosterN = L._tgetn(roster)
    local ri = 1
    for _, c in L._ipairs(pack) do
        local mark = nil
        while ri <= rosterN do
            local entry = roster[ri]
            ri = ri + 1
            if entry.alive and entry.mark and not usedMarks[entry.mark] then
                mark = entry.mark
                break
            end
        end
        if mark then
            c.icon = mark
            c.killAssigned = true
            usedMarks[mark] = true
            L._tinsert(intents, { guid = c.guid, name = c.name, icon = mark, reason = "pull-kill" })
        end
        -- no tank mark left -> c is a CC candidate or overflow (steps 3/4).
    end

    -- 3. CC PASS. Among mobs the ladder did NOT claim, CC the eligible ones.
    -- Candidacy = tier-eligible AND (authored type=="CC" OR clears MeetsAutoCCFloor)
    -- -- worthiness gates candidacy ONLY, it no longer ranks. Selection = kill-LAST
    -- first (prio desc, then sequence desc). Greedy SelectCCSlot over the in-pass
    -- slot overlay (legal + race + used).
    local slots = copySlots(board.getCCSlots())
    local ccCands = {}
    for _, c in L._ipairs(pack) do
        if not c.killAssigned
           and TankMark:CCTierEligible(c.tier)
           and (c.authoredCC or TankMark:MeetsAutoCCFloor(c.role, c.tier)) then
            c.wasCCCand = true
            L._tinsert(ccCands, c)
        end
    end
    L._tsort(ccCands, function(a, b)
        if a.prio ~= b.prio then return a.prio > b.prio end   -- kill-last (high prio) first
        local sa, sb = a.sequence or 0, b.sequence or 0
        if sa ~= sb then return sa > sb end                   -- later-moused (kill-last) first
        return (a.guid or "") < (b.guid or "")                -- final determinism
    end)
    for _, c in L._ipairs(ccCands) do
        local mark = TankMark:SelectCCSlot(c.authoredClass, c.ctype, slots)
        if mark then
            c.icon = mark
            c.ccAssigned = true
            usedMarks[mark] = true
            for _, s in L._ipairs(slots) do
                if s.mark == mark then s.used = true end  -- consume the slot in-pass
            end
            L._tinsert(intents, { guid = c.guid, name = c.name, icon = mark, reason = "pull-cc" })
        end
    end

    -- 4. Surface leftovers (never silently drop). A CC candidate we could NOT slot
    -- -> unccd (worthy but un-CCable); a plain mob past the kill ladder -> overflow
    -- (the in-combat scanner picks it up as marks free).
    for _, c in L._ipairs(pack) do
        if not c.killAssigned and not c.ccAssigned then
            if c.wasCCCand then
                L._tinsert(unccd, { guid = c.guid, name = c.name })
            else
                L._tinsert(overflow, { guid = c.guid, name = c.name })
            end
        end
    end

    return { intents = intents, overflow = overflow, unccd = unccd }
end

-- ==========================================================
-- [v0.30] Surfacing -- never silently truncate (ratified #16)
-- ==========================================================
local ICON_NAME = {
    [1] = "Star", [2] = "Circle", [3] = "Diamond", [4] = "Triangle",
    [5] = "Moon", [6] = "Square",  [7] = "Cross",   [8] = "Skull",
}

-- Join a list of strings without table.concat (kept local + Locals-only).
local function joinList(list, sep)
    local s = ""
    for i, v in L._ipairs(list) do
        if i > 1 then s = s .. sep end
        s = s .. v
    end
    return s
end

-- Chat summary of a DecidePull plan: CC picks + kill ladder + overflow handoff,
-- plus any worthy mob we could not legally CC. Mirrors the existing batch summary
-- style; also writes a guarded PULL debug entry.
function TankMark:ReportPullPlan(plan)
    local cc, kill = {}, {}
    for _, it in L._ipairs(plan.intents) do
        local label = (it.name or "?") .. " (" .. (ICON_NAME[it.icon] or it.icon) .. ")"
        if it.reason == "pull-cc" then L._tinsert(cc, label) else L._tinsert(kill, label) end
    end
    local msg = "|cff00ff00Pull plan:|r "
    if L._tgetn(cc)   > 0 then msg = msg .. "CC " .. joinList(cc, ", ") .. ". " end
    if L._tgetn(kill) > 0 then msg = msg .. "Kill " .. joinList(kill, ", ") .. ". " end
    local nover = L._tgetn(plan.overflow)
    if nover > 0 then msg = msg .. "|cff888888" .. nover .. " left for AoE/scanner.|r" end
    TankMark:Print(msg)

    if L._tgetn(plan.unccd) > 0 then
        local names = {}
        for _, u in L._ipairs(plan.unccd) do L._tinsert(names, u.name or "?") end
        TankMark:Print("|cffffaa00No legal CC for:|r " .. joinList(names, ", "))
    end

    if TankMark.DebugEnabled then
        TankMark:DebugLog("PULL", "DecidePull plan", {
            cc = L._tgetn(cc), kill = L._tgetn(kill),
            overflow = nover, unccd = L._tgetn(plan.unccd),
        })
    end
end
