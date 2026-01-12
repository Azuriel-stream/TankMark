-- TankMark: v0.19
-- File: TankMark.lua
-- [v0.19] Added snapshot triggers and zone data loading

if not TankMark then
	TankMark = CreateFrame("Frame", "TankMarkFrame")
end

-- ==========================================================
-- LOCALIZATIONS
-- ==========================================================
local _strfind = string.find
local _lower = string.lower
local _pairs = pairs
local _ipairs = ipairs
local _getn = table.getn

-- ==========================================================
-- ZONE CACHING
-- ==========================================================
TankMark.currentZone = nil

function TankMark:GetCachedZone()
	if not TankMark.currentZone then
		TankMark.currentZone = GetRealZoneText()
	end
	return TankMark.currentZone
end

-- ==========================================================
-- EVENT HANDLER
-- ==========================================================
function TankMark:HandleMouseover()
	if not TankMark:CanAutomate() and not TankMark.IsRecorderActive then return end
	
	if IsControlKeyDown() then
		if GetRaidTargetIndex("mouseover") then TankMark:UnmarkUnit("mouseover") end
		return
	end
	
	if IsShiftKeyDown() then
		local guid = TankMark:Driver_GetGUID("mouseover")
		if guid then TankMark:ProcessUnit(guid, "FORCE") end
		return
	end
	
	local guid = TankMark:Driver_GetGUID("mouseover")
	if guid then TankMark:ProcessUnit(guid, "PASSIVE") end
end

TankMark:SetScript("OnEvent", function()
	if (event == "ADDON_LOADED" and arg1 == "TankMark") then
		if TankMark.InitializeDB then TankMark:InitializeDB() end
	
	elseif (event == "PLAYER_LOGIN") then
		math.randomseed(time())
		
		-- Initialize zone cache
		TankMark.currentZone = GetRealZoneText()
		
		-- [v0.19] Load zone data (merge defaults + user DB)
		if TankMark.LoadZoneData then
			TankMark:LoadZoneData(TankMark.currentZone)
		end
		
		if TankMark.UpdateRoster then TankMark:UpdateRoster() end
		
		-- Calls to Logic Engine
		TankMark:InitCombatLogParser()
		
		-- Calls to Scanner Module
		TankMark:InitDriver()
		TankMark:ScanForRangeSpell()
		
		TankMark:Print("TankMark v0.19 loaded.")
	
	elseif (event == "ZONE_CHANGED_NEW_AREA") then
		local oldZone = TankMark.currentZone
		TankMark.currentZone = GetRealZoneText()
		
		-- [v0.19] Load zone data for new zone
		if TankMark.LoadZoneData then
			TankMark:LoadZoneData(TankMark.currentZone)
		end
		
		-- Disable Flight Recorder on zone change (safety)
		if TankMark.IsRecorderActive then
			TankMark.IsRecorderActive = false
			TankMark:Print("|cffffaa00Flight Recorder:|r Auto-disabled (zone changed from '" .. (oldZone or "Unknown") .. "' to '" .. TankMark.currentZone .. "')")
			TankMark:Print("Use '/tmark recorder start' to re-enable for new zone.")
		end
		
	elseif (event == "UPDATE_MOUSEOVER_UNIT") then
		TankMark:HandleMouseover()
	
	elseif (event == "UNIT_HEALTH") then
		TankMark:HandleDeath(arg1)
	
	elseif (event == "RAID_ROSTER_UPDATE" or event == "PARTY_MEMBERS_CHANGED") then
		-- Update HUD colors when roster changes
		if TankMark.UpdateHUD then
			TankMark:UpdateHUD()
		end
		
		-- Update Profile tab colors if visible
		if TankMark.UpdateProfileList and TankMark.optionsFrame and TankMark.optionsFrame:IsVisible() then
			TankMark:UpdateProfileList()
		end

	elseif (event == "CHAT_MSG_COMBAT_HOSTILE_DEATH") then
		TankMark:HandleCombatLog(arg1)
	
	elseif (event == "CHAT_MSG_ADDON") then
		if TankMark.HandleSync then TankMark:HandleSync(arg1, arg2, arg4) end
	end
end)

TankMark:RegisterEvent("ADDON_LOADED")
TankMark:RegisterEvent("PLAYER_LOGIN")
TankMark:RegisterEvent("ZONE_CHANGED_NEW_AREA")
TankMark:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
TankMark:RegisterEvent("UNIT_HEALTH")
TankMark:RegisterEvent("CHAT_MSG_COMBAT_HOSTILE_DEATH")
TankMark:RegisterEvent("CHAT_MSG_ADDON")
TankMark:RegisterEvent("RAID_ROSTER_UPDATE")
TankMark:RegisterEvent("PARTY_MEMBERS_CHANGED")

-- ==========================================================
-- COMMANDS
-- ==========================================================
function TankMark:SlashHandler(msg)
	local _, _, cmd, args = _strfind(msg, "^(%S*)%s*(.*)$")
	cmd = _lower(cmd or "")
	
	local iconNames = {
		["skull"] = 8, ["cross"] = 7, ["square"] = 6, ["moon"] = 5,
		["triangle"] = 4, ["diamond"] = 3, ["circle"] = 2, ["star"] = 1
	}
	
	if cmd == "reset" or cmd == "r" then TankMark:ResetSession()
	
	elseif cmd == "announce" or cmd == "a" then
		if TankMark.AnnounceAssignments then TankMark:AnnounceAssignments() end
	
	elseif cmd == "on" or cmd == "enable" then
		TankMark.IsActive = true
		TankMark:Print("Auto-Marking |cff00ff00ENABLED|r.")
	
	elseif cmd == "off" or cmd == "disable" then
		TankMark.IsActive = false
		TankMark:Print("Auto-Marking |cffff0000DISABLED|r.")
	
	elseif cmd == "normals" then
		TankMark.MarkNormals = not TankMark.MarkNormals
		TankMark:Print("Marking Normal Mobs: " .. (TankMark.MarkNormals and "|cff00ff00ON|r" or "|cffff0000OFF|r"))
		if TankMark.optionsFrame and TankMark.optionsFrame:IsVisible() then
			if TankMark.normalsCheck then TankMark.normalsCheck:SetChecked(TankMark.MarkNormals) end
		end
	
	elseif cmd == "recorder" then
		if args == "start" then
			local zone = TankMark:GetCachedZone()
			
			-- Create zone if it doesn't exist
			if not TankMarkDB.Zones[zone] then
				TankMarkDB.Zones[zone] = {}
				TankMark:Print("|cff00ff00Created:|r New zone '" .. zone .. "'")
			end
			
			TankMark.IsRecorderActive = true
			TankMark:Print("Flight Recorder: |cff00ff00ENABLED|r for '" .. zone .. "'. Mouseover mobs to record.")
		elseif args == "stop" then
			TankMark.IsRecorderActive = false
			TankMark:Print("Flight Recorder: |cffff0000DISABLED|r.")
		else
			TankMark:Print("Usage: /tmark recorder start | stop")
		end
	
	elseif cmd == "zone" or cmd == "debug" then
		local currentZone = TankMark:GetCachedZone()
		TankMark:Print("Current Zone: " .. currentZone)
		TankMark:Print("Driver Mode: " .. (TankMark.IsSuperWoW and "|cff00ff00SuperWoW|r" or "|cffffaa00Standard|r"))
		if TankMark.IsSuperWoW then
			local count = 0
			for k,v in _pairs(TankMark.visibleTargets) do count = count + 1 end
			TankMark:Print("Scanner: " .. count .. " visible targets tracked.")
		end
	
	elseif cmd == "assign" then
		local _, _, markStr, targetPlayer = _strfind(args, "^(%S+)%s+(%S+)$")
		if markStr and targetPlayer then
			markStr = _lower(markStr)
			local iconID = tonumber(markStr) or iconNames[markStr]
			if iconID and iconID >= 1 and iconID <= 8 then
				TankMark.sessionAssignments[iconID] = targetPlayer
				TankMark.usedIcons[iconID] = true
				TankMark:Print("Manually assigned " .. TankMark:GetMarkString(iconID) .. " to " .. targetPlayer)
				if TankMark.UpdateHUD then TankMark:UpdateHUD() end
			else
				TankMark:Print("|cffff0000Error:|r Invalid mark.")
			end
		else
			TankMark:Print("Usage: /tmark assign [mark] [player]")
		end
	
	elseif cmd == "config" or cmd == "c" then
		if TankMark.ShowOptions then TankMark:ShowOptions() end
	
	elseif cmd == "sync" or cmd == "share" then
		if TankMark.BroadcastZone then TankMark:BroadcastZone() end
	
	elseif cmd == "debugprofiles" then
		TankMark:Print("=== Profile Database Debug ===")
		if not TankMarkProfileDB then
			TankMark:Print("TankMarkProfileDB is NIL!")
		else
			local count = 0
			for zoneName, profile in pairs(TankMarkProfileDB) do
				count = count + 1
				local entries = table.getn(profile)
				TankMark:Print(count .. ". '" .. zoneName .. "' - " .. entries .. " marks")
			end
			if count == 0 then
				TankMark:Print("Database is EMPTY")
			end
		end
	else
		TankMark:Print("Commands: /tmark reset, /tmark on, /tmark off, /tmark assign, /tmark recorder")
	end
end

-- ==========================================================
-- ROSTER VALIDATION
-- ==========================================================

function TankMark:IsPlayerInRaid(playerName)
	if not playerName or playerName == "" then return true end
	
	-- Check player
	if UnitName("player") == playerName then return true end
	
	-- Check raid
	local numRaid = GetNumRaidMembers()
	if numRaid > 0 then
		for i = 1, 40 do
			if UnitName("raid"..i) == playerName then
				return true
			end
		end
		return false
	end
	
	-- Check party
	local numParty = GetNumPartyMembers()
	if numParty > 0 then
		for i = 1, 4 do
			if UnitName("party"..i) == playerName then
				return true
			end
		end
		return false
	end
	
	-- Solo - always valid (can't check)
	return true
end

function TankMark:AnnounceAssignments()
	local zone = TankMark:GetCachedZone()
	local profile = TankMarkProfileDB[zone]
	
	if not profile or _getn(profile) == 0 then
		TankMark:Print("No profile assignments found for " .. zone .. ".")
		return
	end
	
	local channel = "SAY"
	if GetNumRaidMembers() > 0 then channel = "RAID"
	elseif GetNumPartyMembers() > 0 then channel = "PARTY" end
	
	SendChatMessage("== " .. zone .. " Assignments ==", channel)
	SendChatMessage("Mark || Tank || Healers", channel)
	
	for _, data in _ipairs(profile) do
		if data.mark and data.tank ~= "" then
			local info = TankMark.MarkInfo[data.mark]
			local markDisplay = ""
			if info then markDisplay = info.color .. info.name .. "|r"
			else markDisplay = "Mark " .. data.mark end
			
			local msg = markDisplay .. " || " .. data.tank
			
			if data.healers and data.healers ~= "" then
				msg = msg .. " || " .. data.healers
			else
				msg = msg .. " || -"
			end
			
			SendChatMessage(msg, channel)
		end
	end
end

SLASH_TANKMARK1 = "/tmark"
SLASH_TANKMARK2 = "/tankmark"
SlashCmdList["TANKMARK"] = function(msg) TankMark:SlashHandler(msg) end
