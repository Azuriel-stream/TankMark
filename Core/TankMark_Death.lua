-- Death detection, mark cleanup, and skull priority management

if not TankMark then return end

local L = TankMark.Locals

-- [v0.28] Last alive-skull GUID we emitted a steady-state confirm log for, so
-- ReviewSkullState breadcrumbs once per DISTINCT holder instead of every tick
-- (roadmap candidate 0: mark8-alive poll de-noise). Runtime-only; resets on /reload.
local lastAliveSkullLogged = nil

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
		local iconID = TankMark.Ledger.IconForName(deadMobName)
		if iconID and not TankMark:VerifyMarkExistence(iconID) then
			-- Resolve the dead mob's GUID so EvictMarkOwner can distinguish it
			-- from a freshly-assigned replacement. OwnerOf folds in the
			-- MarkMemory / activeGUIDs lookup.
			local deadGUID = TankMark.Ledger.OwnerOf(iconID)
			TankMark:EvictMarkOwner(iconID, deadGUID)
			if iconID == 8 then
				TankMark:ReviewSkullState("COMBAT_LOG")
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
			-- [FIX] Resolve dead mob GUID before eviction so EvictMarkOwner
			-- can distinguish it from a freshly-assigned replacement.
			-- UnitGUID is still valid at 0 HP before the mob despawns.
			-- Falls back to MarkMemory[icon] if UnitGUID returns nil.
			local _, deadGUID = L._UnitExists(unitID)
			if not deadGUID then
				deadGUID = TankMark.Ledger.OwnerOf(icon)
			end

			TankMark:EvictMarkOwner(icon, deadGUID)
			if icon == 8 then
				TankMark:ReviewSkullState("UNIT_DEATH")
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

	-- Lazily migrate role field on all entries before using it
	TankMark:MigrateProfileRoles(zone)

	-- Check if dead player is a TANK (role == "TANK")
	local deadTankIndex = nil
	for i, entry in L._ipairs(list) do
		if entry.tank and entry.tank == deadPlayerName and (not entry.role or entry.role == "TANK") then
			deadTankIndex = i
			break
		end
	end

	if deadTankIndex then
		local deadMarkStr = TankMark:GetMarkString(list[deadTankIndex].mark)

		-- Build the TANK-only roster (CC entries are excluded)
		local roster = TankMark:GetTankRoster(zone)

		-- Find the dead tank's position within the roster
		local deadRosterPos = nil
		for pos, entry in L._ipairs(roster) do
			if entry.player == deadPlayerName then
				deadRosterPos = pos
				break
			end
		end

		local nextTank = nil
		if deadRosterPos then
			-- 1. Search DOWN from the dead position (lower-priority tanks first)
			for pos = deadRosterPos + 1, L._tgetn(roster) do
				if roster[pos].alive then
					nextTank = roster[pos].player
					break
				end
			end

			-- 2. Search UP, but skip position 1 (SKULL holder)
			if not nextTank then
				for pos = deadRosterPos - 1, 2, -1 do
					if roster[pos].alive then
						nextTank = roster[pos].player
						break
					end
				end
			end

			-- 3. Last resort: SKULL tank (position 1) if alive and not the dead player
			if not nextTank and deadRosterPos ~= 1 and L._tgetn(roster) >= 1 then
				if roster[1].alive then
					nextTank = roster[1].player
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
	-- [v0.27] SuperWoW mark units are authoritative and visibility-independent.
	if L._UnitExists("mark"..iconID) then
		if not L._UnitIsDead("mark"..iconID) then
			return true
		end
	end
	return false
end

function TankMark:EvictMarkOwner(iconID, deadGUID)
	-- The Ledger's GUID-aware release preserves icon state when a reassignment
	-- was already committed this tick (deadGUID no longer owns the icon).
	TankMark.Ledger.Release(iconID, deadGUID)
	if TankMark.UpdateHUD then TankMark:UpdateHUD() end
end

-- ==========================================================
-- SKULL PRIORITY MANAGEMENT
-- ==========================================================

function TankMark:ReviewSkullState(callerID)
	local _caller = callerID or "UNKNOWN"

	-- [v0.28] Steady-state skull-confirm short-circuit (roadmap candidate 0:
	-- mark8-alive poll de-noise). When a skull is alive AND we already own that
	-- exact GUID, this call is a pure no-op confirm -- every downstream branch
	-- returns without touching a mark. The scanner CLEANUP phase calls this every
	-- tick the whole time a skull is up, so without this the entry log + the
	-- "BLOCKED - mark8 alive" log spammed ~2 lines/tick (125 in a 79s trace),
	-- evicting the real decision entries from the 500-slot ring. Return before the
	-- entry log and emit one breadcrumb per DISTINCT holder only. Adoption (owner
	-- nil) and theft/mismatch (owner ~= live GUID) fall through to the full logic
	-- below, so the wedge tell ("registered pre-existing skull holder") is intact;
	-- an adopted holder becomes owner==live next tick and then goes quiet here.
	-- The mark8 reads run every tick anyway (the real alive check below), so this
	-- adds no hot-path cost when debug is off -- it short-circuits earlier.
	if L._UnitExists("mark8") and L._UnitIsDead("mark8") ~= 1 then
		local _, liveSkullGUID = L._UnitExists("mark8")
		if liveSkullGUID and TankMark.Ledger.MemoryOwner(8) == liveSkullGUID then
			if TankMark.DebugEnabled and liveSkullGUID ~= lastAliveSkullLogged then
				TankMark:DebugLog("SKULL_REVIEW", "ReviewSkullState confirm - mark8 alive (owned)", {
					caller     = _caller,
					guid       = liveSkullGUID,
					mark8_name = L._UnitName("mark8") or "?",
				})
				lastAliveSkullLogged = liveSkullGUID
			end
			return
		end
	end

	-- DEBUG: Entry Snapshot
	-- Captures full skull-related state at invocation time. Primary instrument for
	-- diagnosing multiple-call issues. [v0.28] Computed INSIDE the debug guard: the
	-- scanner CLEANUP phase calls this every tick (grouped, in OR out of combat), and
	-- these ~6 WoW API reads feed only the log -- they must not run on the hot path
	-- when debug is off. The real logic below recomputes mark8/MemoryOwner fresh.
	if TankMark.DebugEnabled then
		local mark8Exists = L._UnitExists("mark8") or false
		local mark8IsDead = mark8Exists and (L._UnitIsDead("mark8") == 1) or false
		local mark8Name   = mark8Exists and (L._UnitName("mark8") or "?") or "nil"
		local memGUID     = TankMark.Ledger.MemoryOwner(8)
		local memMobName  = memGUID and (L._UnitName(memGUID) or "?") or "nil"
		local activeName8 = TankMark.Ledger.NameFor(8) or "nil"

		TankMark:DebugLog("SKULL_REVIEW", "ReviewSkullState entry", {
			caller       = _caller,
			mark8_exists = mark8Exists,
			mark8_dead   = mark8IsDead,
			mark8_name   = mark8Name,
			memory8_guid = memGUID or "nil",
			memory8_name = memMobName,
			active_name8 = activeName8,
		})
	end

	-- 1. Basic Checks
	if not TankMark:HasPermissions() then
		if TankMark.DebugEnabled then
			TankMark:DebugLog("SKULL_REVIEW", "ReviewSkullState BLOCKED - no permissions", {
				caller = _caller,
			})
		end
		return
	end

	-- [FIX] If SKULL is already on a valid, living target, nothing to review.
	-- UnitExists("mark8") is server-side and persists regardless of nameplate
	-- visibility (confirmed via in-game testing).
	if L._UnitExists("mark8") and L._UnitIsDead("mark8") ~= 1 then
		-- FIX: Populate MarkMemory if the skull holder is unknown
		if not TankMark.Ledger.MemoryOwner(8) then
			local _, existingGUID = L._UnitExists("mark8")
			if existingGUID then
				local existingName = L._UnitName("mark8") or "?"
				TankMark:RegisterMarkUsage(8, existingName, existingGUID, false)
				if TankMark.DebugEnabled then
					TankMark:DebugLog("SKULL_REVIEW", "ReviewSkullState registered pre-existing skull holder", {
						caller = _caller,
						guid   = existingGUID,
						name   = existingName,
					})
				end
			end
		end
		if TankMark.DebugEnabled then
			TankMark:DebugLog("SKULL_REVIEW", "ReviewSkullState BLOCKED - mark8 alive", {
				caller     = _caller,
				mark8_name = L._UnitName("mark8") or "?",
			})
		end
		return
	end

	-- [FIX] Duplicate-Event Guard.
	-- After a skull mob dies, two events fire within ~4ms of each other:
	-- COMBAT_LOG and UNIT_DEATH. The first ReviewSkullState call commits a
	-- new assignment by writing candidateGUID into MarkMemory[8] before
	-- calling Driver_ApplyMark. If MarkMemory[8] is non-nil here, and mark8
	-- is dead (server has not yet confirmed the new assignment), we are the
	-- duplicate caller. Block immediately to prevent a second SetRaidTarget.
	-- EvictMarkOwner's GUID-aware logic ensures MarkMemory[8] is only nil
	-- when no new assignment has been committed in this tick.
	if TankMark.Ledger.MemoryOwner(8) then
		if TankMark.DebugEnabled then
			TankMark:DebugLog("SKULL_REVIEW", "ReviewSkullState BLOCKED - pending assignment", {
				caller     = _caller,
				lockedGUID = TankMark.Ledger.MemoryOwner(8),
			})
		end
		return
	end

	-- [v0.26] Sequential Marking Guard
	-- Prevents auto-skull if the mob is part of a sequential kill list (e.g. Majordomo)
	local skullName = TankMark.Ledger.NameFor(8)
	if skullName and TankMark.activeDB and TankMark.activeDB[skullName] then
		local data = TankMark.activeDB[skullName]
		if data.marks and L._tgetn(data.marks) > 1 then
			if TankMark.DebugEnabled then
				TankMark:DebugLog("SKULL_REVIEW", "ReviewSkullState BLOCKED - sequential guard", {
					caller    = _caller,
					skullName = skullName,
				})
			end
			return
		end
	end

	-- 2. Governor Check (The Blocker)
	local blockIcon, _, blockPrio, _ = nil, nil, 99, nil
	if TankMark.GetBlockingMarkInfo then
		blockIcon, _, blockPrio, _ = TankMark:GetBlockingMarkInfo()
	end

	if TankMark.DebugEnabled then
		TankMark:DebugLog("SKULL_REVIEW", "ReviewSkullState governor check", {
			caller    = _caller,
			blockIcon = blockIcon or "nil",
			blockPrio = blockPrio or "nil",
		})
	end

	-- 3. Find Best Candidate for Skull
	if TankMark.FindEmergencyCandidate then
		local candidateGUID, candidatePrio = TankMark:FindEmergencyCandidate()

		if not candidateGUID then
			if TankMark.DebugEnabled then
				TankMark:DebugLog("SKULL_REVIEW", "ReviewSkullState NO CANDIDATE found", {
					caller = _caller,
				})
			end
			return
		end

		-- [v0.28] STRICT INCUMBENCY RULE via the shared IncumbencyBlocks predicate
		-- (single-sourced with GovernorBlocks so the >= operator can't drift).
		-- Only (re)assign skull when the candidate is strictly better (lower prio
		-- number) than the incumbent blocker; an equal-prio incumbent blocks.
		local shouldAssign = not TankMark:IncumbencyBlocks(candidatePrio or 5, blockIcon, blockPrio)

		if TankMark.DebugEnabled then
			TankMark:DebugLog("SKULL_REVIEW", "ReviewSkullState decision", {
				caller        = _caller,
				candidateGUID = candidateGUID or "nil",
				candidateName = candidateGUID and (L._UnitName(candidateGUID) or "?") or "nil",
				candidatePrio = candidatePrio or "nil",
				blockIcon     = blockIcon or "nil",
				blockPrio     = blockPrio or "nil",
				shouldAssign  = shouldAssign,
			})
		end

		if shouldAssign then
			-- Record ownership BEFORE calling Driver_ApplyMark. This serves
			-- two purposes: (1) keeps internal state visible to IsMarkBusy and
			-- GetMarkOwnerPriority, and (2) arms the duplicate-event guard above
			-- so any second ReviewSkullState call in the same tick is blocked
			-- before it reaches Driver_ApplyMark.
			local candidateName = L._UnitName(candidateGUID)
			TankMark:RegisterMarkUsage(8, candidateName, candidateGUID, false)
			TankMark:Driver_ApplyMark(candidateGUID, 8)
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

-- [v0.28] Pull-end physical mark clear. Fired from PLAYER_REGEN_ENABLED only when
-- the addon-holder is ALIVE -- a tank's only alive combat-exit is the pull genuinely
-- resolving (everything dead or evaded). Eliminates Turtle's retained-mark ghosts at
-- the source: Turtle WoW keeps raid-target icons on mobs through death AND respawn,
-- so a respawn wearing a retained skull can be adopted by ReviewSkullState and wedge
-- skull for the rest of the run. Physically stripping every hostile-worn mark at true
-- pull-end means there is no retained icon to carry onto a respawn. This is NOT
-- /tmark reset: it preserves the raid leader's plan (sessionAssignments, profile DB,
-- disabledMarks, sequentialMarkCursor, recorder) -- none of which are Ledger indices.
function TankMark:ClearMarksForPullEnd()
	if not TankMark:HasPermissions() then return end

	local n = 0
	for i = 1, 8 do
		local token = "mark" .. i
		-- Hostile-only: never strip a manually placed player mark (MT marks for healers, etc.).
		if L._UnitExists(token) and not L._UnitIsPlayer(token) then
			L._SetRaidTarget(token, 0)
			n = n + 1
		end
	end

	-- Wipe the four ownership indices. The plan survives (sessionAssignments / profile
	-- DB / disabledMarks / sequentialMarkCursor are not Ledger indices). Clearing
	-- usedIcons here matches the [v0.26] "usedIcons reflects live mob marks only" rule.
	TankMark.Ledger.Clear()

	if TankMark.DebugEnabled then
		TankMark:DebugLog("PULL_END", "cleared", { marks = n })
	end

	if TankMark.UpdateHUD then
		TankMark:UpdateHUD()
	end
end

function TankMark:ResetSession()
	TankMark.Ledger.Clear()
	TankMark.sessionAssignments = {}
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
		for i = 1, 8 do
			if L._UnitExists("mark" .. i) then
				L._SetRaidTarget("mark" .. i, 0)
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
