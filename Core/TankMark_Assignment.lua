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
        elseif TankMark.Ledger.OwnerOf(markID) then
            isBusy = true
        elseif TankMark.Ledger.IsUsed(markID) then
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

-- ==========================================================
-- [v0.30] LEGAL-CC AUTHORITY (marking-redesign Phase 2)
-- ==========================================================
-- The single Core source of CC capability, shared by the editor menus and the
-- runtime decision layer. Two COMPOSING predicates gate CC routing:
--   * creature-legality: IsLegalCC(class, creatureType) -- class is in CCMap.
--   * player-capability: CCRaceEligible(class, race)     -- the narrow race gate.
-- CCMap stays RACE-FREE (it is class x creatureType only); the one sub-class CC
-- constraint in Turtle 1.12 (Troll-only Hex) lives in CCRaceEligible. Do NOT use
-- IsPlayerCCClass as the capability check -- it excludes Druid/Rogue (kept legal
-- here on purpose) and serves a different job (conservative role auto-inference).

-- creatureType -> the classes whose CC is legal on it (race-free).
TankMark.CCMap = {
    ["Humanoid"]  = { "MAGE", "ROGUE", "WARLOCK", "SHAMAN" },  -- Sap/Polymorph/Fear/Hex
    ["Beast"]     = { "MAGE", "DRUID", "HUNTER", "SHAMAN" },   -- Polymorph/Hibernate/Trap/Hex
    ["Elemental"] = { "WARLOCK" },                              -- Banish
    ["Demon"]     = { "WARLOCK" },                              -- Banish
    ["Undead"]    = { "PRIEST" },                               -- Shackle
    ["Dragonkin"] = { "DRUID" },                                -- Hibernate
}

-- Creature-legality: is `class` a legal CC for `creatureType`? Pure.
function TankMark:IsLegalCC(class, creatureType)
    local list = TankMark.CCMap[creatureType]
    if not list then return false end
    for _, c in L._ipairs(list) do
        if c == class then return true end
    end
    return false
end

-- Player-capability: the narrow race gate. Only non-Troll Shamans fail (no Hex);
-- every other CCMap class has no per-player CC constraint. Pure.
function TankMark:CCRaceEligible(class, race)
    return class ~= "SHAMAN" or race == "Troll"
end

-- [v0.30] The pure two-pass CC resolver. Picks a CC mark from a snapshot of the
-- role=="CC" profile slots (built live by GetCCSlots), or nil if none qualifies.
--   slot = { mark, class (UPPER token), race, alive, used, disabled }
-- Pass 1 prefers the authored class IFF it is legal; pass 2 takes the first legal
-- slot in profile order. With an unknown creatureType it degrades to authored-
-- class-only. A slot is eligible only if alive, not used, not disabled, and
-- race-eligible -- so a disabled mark (HUD toggle) is never routed to.
function TankMark:SelectCCSlot(authoredClass, creatureType, slots)
    local function eligible(s)
        return s.alive and not s.used and not s.disabled
           and TankMark:CCRaceEligible(s.class, s.race)
    end
    if creatureType and TankMark.CCMap[creatureType] then
        -- Pass 1: authored preference, only if the authored class is legal here.
        if authoredClass and TankMark:IsLegalCC(authoredClass, creatureType) then
            for _, s in L._ipairs(slots) do
                if s.class == authoredClass and eligible(s) then return s.mark end
            end
        end
        -- Pass 2: first legal slot in profile order.
        for _, s in L._ipairs(slots) do
            if eligible(s) and TankMark:IsLegalCC(s.class, creatureType) then return s.mark end
        end
        return nil
    end
    -- Degrade (creatureType unknown): authored-class-only, still gated.
    if authoredClass then
        for _, s in L._ipairs(slots) do
            if s.class == authoredClass and eligible(s) then return s.mark end
        end
    end
    return nil
end

-- [v0.30] Phase 3 role x tier -> default kill-priority derivation. The pure
-- lookup behind the editor's authoring-time prio pre-fill (ApplyRoleDefaults);
-- the human prio field always overrides (this only pre-fills it). TOTAL: any
-- input returns a number -- nil/unknown role degrades to the MELEE row,
-- nil/unknown tier to the `normal` column. NB: mob `role` (HEALER/CASTER/MELEE)
-- is a DIFFERENT axis from the profile `role` (TANK/CC). Curve from
-- DATA-MODEL.md S5 (defaults, not law -- tuned against real pulls).
local ROLE_PRIO = {
    HEALER = { normal = 2, elite = 1, rare = 1, boss = 1 },
    CASTER = { normal = 3, elite = 2, rare = 2, boss = 1 },
    MELEE  = { normal = 5, elite = 4, rare = 3, boss = 1 },
}
-- Collapse the live client tier classifications into the four curve columns.
local ROLE_TIER_BUCKET = {
    normal    = "normal",
    elite     = "elite",
    rare      = "rare",
    rareelite = "rare",
    worldboss = "boss",
    boss      = "boss",
}
function TankMark:RoleTierPrio(role, tier)
    local row    = ROLE_PRIO[role] or ROLE_PRIO.MELEE
    local bucket = ROLE_TIER_BUCKET[tier] or "normal"
    return row[bucket]
end

-- [v0.30] Phase 4 CC-worthiness: how much a mob warrants a scarce CC slot,
-- derived from mob role x tier -- and NOT from prio (prio is the human's
-- overridable kill-order knob, a DIFFERENT axis; deriving worthiness from it
-- would make the scanner try to sheep a melee the human set to prio 1). One curve
-- serves both callers: the pre-fight DecidePull SORTS a pack by it; the in-combat
-- scanner THRESHOLDS it (SCANNER_CC_FLOOR, Phase 4 part B) to auto-CC only the
-- absolutely-worthy. TOTAL: nil/unknown role -> MELEE row, nil/unknown tier ->
-- normal column (reuses ROLE_TIER_BUCKET above). NB: mob role (HEALER/CASTER/
-- MELEE) is a different axis from profile role (TANK/CC). Curve from CONTEXT.md /
-- the phase-4 doc -- defaults, not law (tune against real pulls).
local CC_WORTH = {
    HEALER = { normal = 90, elite = 100, rare = 100, boss = 100 },
    CASTER = { normal = 40, elite = 70,  rare = 70,  boss = 80  },
    MELEE  = { normal = 10, elite = 30,  rare = 35,  boss = 40  },
}
function TankMark:CCWorthiness(role, tier)
    local row    = CC_WORTH[role] or CC_WORTH.MELEE
    local bucket = ROLE_TIER_BUCKET[tier] or "normal"
    return row[bucket]
end

-- [v0.30] Phase 4 tier-immunity gate: rare/boss-class mobs are generally immune
-- to player CC (Polymorph/Banish/Sap/Shackle/...). Only normal & elite mobs are
-- CC-eligible. A MOB gate, composed ALONGSIDE creature-legality (IsLegalCC) and
-- the race gate (CCRaceEligible) but applied BEFORE SelectCCSlot (which only
-- picks a slot). Independent of creatureType: an elite Humanoid is CC-able, a
-- boss Humanoid is not. Reuses ROLE_TIER_BUCKET (worldboss/boss -> "boss";
-- rare/rareelite -> "rare"). nil tier defaults to normal -> eligible (the live
-- UnitClassification read fills it in-game).
function TankMark:CCTierEligible(tier)
    local bucket = ROLE_TIER_BUCKET[tier] or "normal"
    return bucket == "normal" or bucket == "elite"
end

-- Check if player is a CC-capable class
function TankMark:IsPlayerCCClass(playerName)
    if not playerName or playerName == "" then return false end
    
    local unit = TankMark:FindUnitByName(playerName)
    if not unit then return false end
    
    local class = L._UnitClass(unit)
    
    -- CC-capable classes (long-duration CC abilities)
    if class == "Mage" or class == "Warlock" or class == "Hunter" or
       class == "Priest" then
        return true
    end
    
    -- Shaman: Only Troll race can CC (Hex ability)
    if class == "Shaman" then
        local race = L._UnitRace(unit)
        return race == "Troll"
    end
    
    return false
end

-- Infer role ("TANK" or "CC") from a player's class/race.
-- Pure CC classes → "CC"; everyone else → "TANK".
-- Returns "TANK" if the player is not in the current raid/party.
function TankMark:InferRoleFromClass(playerName)
    if not playerName or playerName == "" then return "TANK" end
    local unit = TankMark:FindUnitByName(playerName)
    if not unit then return "TANK" end
    local class = L._UnitClass(unit)
    if class == "Mage" or class == "Warlock" or class == "Hunter" or class == "Priest" then
        return "CC"
    end
    if class == "Shaman" then
        local race = L._UnitRace(unit)
        if race == "Troll" then return "CC" end
    end
    return "TANK"
end

-- Lazily migrate profile entries that are missing the role field.
-- Called before any code that reads or depends on entry.role.
function TankMark:MigrateProfileRoles(zone)
    local list = TankMarkProfileDB[zone]
    if not list then return end
    for _, entry in L._ipairs(list) do
        if not entry.role then
            entry.role = TankMark:InferRoleFromClass(entry.tank)
        end
    end
end

-- Returns an ordered array of TANK-role entries for the given zone.
-- Each element: { profileIndex, mark, player, alive }
-- Only entries with role == "TANK" and a non-empty player name are included.
function TankMark:GetTankRoster(zone)
    local list = TankMarkProfileDB[zone]
    if not list then return {} end
    local roster = {}
    for i, entry in L._ipairs(list) do
        if (not entry.role or entry.role == "TANK") and entry.tank and entry.tank ~= "" then
            local alive = TankMark:IsPlayerAliveAndInRaid(entry.tank)
            L._tinsert(roster, {
                profileIndex = i,
                mark = entry.mark,
                player = entry.tank,
                alive = alive,
            })
        end
    end
    return roster
end

-- [v0.30] Live enumerator for the legal-CC resolver (marking-redesign Phase 2).
-- Snapshots the role=="CC" profile slots as PURE DATA so the decision lives in
-- the pure SelectCCSlot (and the off-client harness can drive it). Each record:
--   { mark, class (UPPER token), race, alive, used, disabled }
-- Replaces FindCCPlayerForClass -- its single-class match + availability checks
-- are now SelectCCSlot's job. `used`/`disabled` carry the same availability gate
-- (Ledger.IsUsed + disabledMarks) so a HUD-disabled mark is never routed to.
function TankMark:GetCCSlots()
    local zone = TankMark:GetCachedZone()
    TankMark:MigrateProfileRoles(zone)   -- ensure entry.role populated (idempotent)
    local list = TankMarkProfileDB[zone]
    if not list then return {} end

    local slots = {}
    for _, entry in L._ipairs(list) do
        if entry.role == "CC" and entry.tank and entry.tank ~= "" then
            local unit = TankMark:FindUnitByName(entry.tank)
            if unit then
                local _, classEng = L._UnitClass(unit)
                L._tinsert(slots, {
                    mark     = entry.mark,
                    class    = classEng,
                    race     = L._UnitRace(unit),
                    alive    = not L._UnitIsDeadOrGhost(unit),
                    used     = TankMark.Ledger.IsUsed(entry.mark) and true or false,
                    disabled = TankMark.disabledMarks[entry.mark] and true or false,
                })
            end
        end
    end
    return slots
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

-- [v0.28] Single source of the skull incumbency comparison. Shared by the
-- decide-path governor (GovernorBlocks, Processor) and the death-path skull
-- review (ReviewSkullState, Death) so the >= operator can never drift between
-- the two. Pure: callers fetch GetBlockingMarkInfo themselves and pass the
-- blocker icon/prio in. A skull candidate is blocked when an incumbent blocker
-- exists and the candidate is NOT strictly better (lower prio number).
function TankMark:IncumbencyBlocks(myPrio, blockIcon, blockPrio)
    return blockIcon and myPrio >= (blockPrio or 99) and true or false
end

-- [v0.28] Parked-CC test (roadmap #3, sheep-edge). True when the mob currently
-- holding `icon` is wearing one of the incapacitate/sleep/banish/shackle debuffs
-- in TankMark.CCAuraSet -- i.e. it is deliberately benched, not being killed, so
-- it must NOT count as a skull-blocker (see the UpdateBest early-out in
-- GetBlockingMarkInfo). Uses the SuperWoW mark unit token (server-resolved, so it
-- works even when the parked mob is not our target/nameplate) and reads the aura
-- id from the 4th return of UnitDebuff (texture, applications, dispelType, AURAID
-- -- confirmed in-game via `/tmark debug ccscan`). Fail-safe: a dead/gone holder or
-- an unrecognized/stale debuff returns false, yielding current blocking behavior.
function TankMark:IsMarkCCd(icon)
    if not icon then return false end
    local unit = "mark" .. icon
    if not L._UnitExists(unit) then return false end
    for i = 1, 16 do
        local _, _, _, auraID = L._UnitDebuff(unit, i)
        if auraID and TankMark.CCAuraSet[auraID] then
            return true
        end
    end
    return false
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
        -- [v0.28] Sheep-edge (roadmap #3): a parked/CC'd mark holder is removed
        -- from the kill order, so it must not block SKULL reassignment. Single
        -- chokepoint for all three discovery passes below. Both governor paths
        -- (decide-path GovernorBlocks + death-path ReviewSkullState) read this
        -- function, so excluding here fixes both with no duplication.
        if TankMark:IsMarkCCd(icon) then
            if TankMark.DebugEnabled then
                TankMark:DebugLog("SKULL_REVIEW", "blocker excluded: parked CC", {
                    icon = icon,
                    guid = guid,
                })
            end
            return
        end
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
                    local isInUse = TankMark.Ledger.IsUsed(markID)

                    if isInUse then
                        -- OwnerOf folds in the MarkMemory-then-activeGUIDs lookup.
                        local foundGUID = TankMark.Ledger.OwnerOf(markID)

                        if foundGUID then
                            local mobName = TankMark.Ledger.NameFor(markID)
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
               not TankMark.Ledger.IconOf(guid) then -- Must not already have a mark
                
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
