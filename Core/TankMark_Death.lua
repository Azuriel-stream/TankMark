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
	if not TankMark:ShouldDriveMarks() or not TankMark.DeathPattern then return end
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
	if not TankMark:ShouldDriveMarks() then return end

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

	-- [v0.31] Shell for the pure skull-succession seam (architecture candidate A).
	-- This was ~190 lines of tangled guards + decision; the decision now lives in
	-- the harness-tested DecideSkullSuccessor (Processor.lua). The shell only: gates
	-- permission, builds the cheap skull-slot snapshot, decides on the seam, logs,
	-- and dispatches the tagged intent to the apply edge. See CONTEXT.md
	-- "skull succession".

	-- Permission gate first (a shell side-condition, not a decision). All callers
	-- are ShouldDriveMarks-gated already; this is the defense-in-depth backstop that
	-- keeps a non-queen out of the Ledger-writing dispatch below.
	if not TankMark:ShouldDriveMarks() then
		if TankMark.DebugEnabled then
			TankMark:DebugLog("SKULL_REVIEW", "BLOCKED - not active marker", { caller = _caller })
		end
		return
	end

	-- Build the cheap skull-slot snapshot (the guard inputs) -- all live reads, done
	-- once and consistently. Safe here because ReviewSkullState makes <=1 assignment
	-- per call; cross-call freshness (the COMBAT_LOG/UNIT_DEATH dup race) comes from
	-- re-entry, not from live-reading mid-call. mark8 tokens are server-side
	-- (visibility-independent). memoryOwner is RAW MarkMemory (MemoryOwner, not
	-- OwnerOf) -- the activeGUIDs fallback would over-block the dup-event guard.
	local skullExists, skullLiveGUID = L._UnitExists("mark8")
	local skullAlive = (skullExists and L._UnitIsDead("mark8") ~= 1) and true or false
	if not skullAlive then skullLiveGUID = nil end

	local isSequential = false
	local skullName = TankMark.Ledger.NameFor(8)
	if skullName and TankMark.activeDB and TankMark.activeDB[skullName] then
		local marks = TankMark.activeDB[skullName].marks
		isSequential = (marks and L._tgetn(marks) > 1) and true or false
	end

	local snapshot = {
		skullAlive    = skullAlive,
		skullLiveGUID = skullLiveGUID,
		memoryOwner   = TankMark.Ledger.MemoryOwner(8),
		isSequential  = isSequential,
	}

	-- Decide on the pure seam (the death-path mirror of DecideMark).
	local intent = TankMark:DecideSkullSuccessor(snapshot, TankMark.LiveBoard)

	-- Debug breadcrumbs live in the shell (the pure fn stays zero-global). Guarded,
	-- and the confirm case is throttled to once per distinct holder so the every-tick
	-- mark8-alive poll cannot flood the 500-slot SKULL_REVIEW ring (PR #53 / #55).
	if TankMark.DebugEnabled then
		TankMark:LogSkullReview(_caller, snapshot, intent)
	end

	-- Dispatch the tagged intent.
	if intent.action == "adopt" then
		-- Ledger-only: the physical skull already exists on the mob, so we record
		-- ownership but must NOT re-emit SetRaidTarget (behavior-identical adopt).
		if intent.guid then
			TankMark:RegisterMarkUsage(8, L._UnitName(intent.guid) or "?", intent.guid, false)
		end
	elseif intent.action == "assign" then
		-- Real succession: reuse the one apply edge (RegisterMarkUsage + Driver).
		TankMark:ApplyMarkIntent(intent.guid, L._UnitName(intent.guid), { icon = 8, reason = intent.reason }, false)
	end
end

-- [v0.31] Shell-side SKULL_REVIEW breadcrumbs for the succession seam (kept out of
-- the pure DecideSkullSuccessor, which stays zero-global). Only ever called inside
-- the DebugEnabled guard. The steady-state confirm is throttled to once per DISTINCT
-- holder via the module-local lastAliveSkullLogged, so the scanner's every-tick
-- mark8-alive poll emits one line per holder, not one per tick (PR #53 / #55).
function TankMark:LogSkullReview(caller, snapshot, intent)
	if intent.reason == "mark8-alive-owned" then
		if snapshot.skullLiveGUID ~= lastAliveSkullLogged then
			TankMark:DebugLog("SKULL_REVIEW", "confirm - mark8 alive (owned)", {
				caller = caller,
				guid   = snapshot.skullLiveGUID or "nil",
				name   = L._UnitName("mark8") or "?",
			})
			lastAliveSkullLogged = snapshot.skullLiveGUID
		end
		return
	end
	TankMark:DebugLog("SKULL_REVIEW", "entry", {
		caller       = caller,
		mark8_alive  = snapshot.skullAlive,
		mark8_name   = snapshot.skullAlive and (L._UnitName("mark8") or "?") or "nil",
		memory8_guid = snapshot.memoryOwner or "nil",
		sequential   = snapshot.isSequential,
	})
	-- Adopt keeps its exact legacy wording -- it is the documented wedge tell for the
	-- skull-retention bug (a respawn wearing a retained skull being re-adopted).
	local outcomeMsg = (intent.action == "adopt")
		and "registered pre-existing skull holder" or intent.reason
	TankMark:DebugLog("SKULL_REVIEW", outcomeMsg, {
		caller        = caller,
		action        = intent.action,
		guid          = intent.guid or "nil",
		candidatePrio = intent.candidatePrio or "nil",
		blockIcon     = intent.blockIcon or "nil",
		blockPrio     = intent.blockPrio or "nil",
	})
end

-- ==========================================================
-- RESET & CLEANUP
-- ==========================================================

function TankMark:UnmarkUnit(unit)
	if not TankMark:ShouldDriveMarks() then return end
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
	-- [v0.29] slice 3: queen-only (was HasPermissions). This fires automatically on
	-- PLAYER_REGEN_ENABLED; un-gated, every eligible drone would race to strip the
	-- queen's marks the instant combat ends. Only the active marker clears.
	if not TankMark:ShouldDriveMarks() then return end

	local n = 0
	for i = 1, 8 do
		local token = "mark" .. i
		-- Hostile-only: never strip a manually placed player mark (MT marks for healers, etc.).
		if L._UnitExists(token) and not L._UnitIsPlayer(token) then
			-- [v0.32] slice A: clears are raid-target writes too -- route through the
			-- Platform.SetMark primitive (already under this fn's outer ShouldDriveMarks gate).
			TankMark.Platform.SetMark(token, 0)
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

	-- [v0.29] slice 3: the local-state reset above is unconditional (harmless local
	-- hygiene); only the PHYSICAL world-mark strip below is queen-gated (was
	-- HasPermissions). So `/tmark reset` on a drone clears its own state without
	-- stripping the group's (queen's) marks. A solo player is the queen post-bootstrap.
	if TankMark:ShouldDriveMarks() then
		-- [v0.32] slice A: clears route through the Platform.SetMark write primitive
		-- (under this outer ShouldDriveMarks gate).
		for i = 1, 8 do
			if L._UnitExists("mark" .. i) then
				TankMark.Platform.SetMark("mark" .. i, 0)
			end
		end

		local function ClearUnit(unit)
			if L._UnitExists(unit) and L._GetRaidTargetIndex(unit) then
				TankMark.Platform.SetMark(unit, 0)
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
