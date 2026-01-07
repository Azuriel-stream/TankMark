-- TankMark: v0.17-dev (Release Candidate)
-- File: TankMark_Sync.lua
-- [PHASE 1 FIX] Added sync data validation to prevent DB corruption

if not TankMark then return end

local SYNC_PREFIX = "TM_SYNC"
local TWA_BW_PREFIX = "TWABW"

-- ==========================================================
-- LOCALIZATIONS
-- ==========================================================
local _strfind = string.find
local _gsub = string.gsub
local _sub = string.sub
local _gfind = string.gfind
local _insert = table.insert
local _remove = table.remove
local _getn = table.getn
local _pairs = pairs
local _ipairs = ipairs
local _sort = table.sort
local _tonumber = tonumber

-- ==========================================================
-- HELPER: Permissions
-- ==========================================================
function TankMark:IsTrustedSender(name)
	local numRaid = GetNumRaidMembers()
	if numRaid > 0 then
		for i = 1, 40 do
			local n, rank = GetRaidRosterInfo(i)
			if n == name then return (rank >= 1) end -- 1=Assist, 2=Leader
		end
	else
		if GetNumPartyMembers() > 0 then
			for i = 1, 4 do
				if UnitName("party"..i) == name and UnitIsPartyLeader("party"..i) then
					return true
				end
			end
		end
	end
	return false
end

-- ==========================================================
-- TWA INTEGRATION (Receiver -> Ordered List)
-- ==========================================================
TankMark.TWA_MarkMap = {
	["Skull"]=8, ["Cross"]=7, ["Square"]=6, ["Moon"]=5,
	["Triangle"]=4, ["Diamond"]=3, ["Circle"]=2, ["Star"]=1
}

function TankMark:HandleTWABW(msg, sender)
	-- Pattern: BWSynch=MarkName: Tank || Healers: Healer
	local _, _, content = _strfind(msg, "^BWSynch=(.*)")
	if not content or content == "start" or content == "end" then return end
	
	local _, _, markName, rest = _strfind(content, "^%s*(.-)%s*:%s*(.*)")
	if not markName or not TankMark.TWA_MarkMap[markName] then return end
	
	local iconID = TankMark.TWA_MarkMap[markName]
	
	local _, _, tankPart, healPart = _strfind(rest, "^(.-)%s*[|][|]%s*Healers:%s*(.*)$")
	if not tankPart then
		tankPart = rest
		healPart = ""
	end
	
	local tankStr = _gsub(tankPart, "-", "")
	tankStr = _gsub(tankStr, "[|]", "")
	tankStr = _gsub(tankStr, "^%s*(.-)%s*$", "%1")
	
	local healStr = ""
	if healPart then
		healStr = _gsub(healPart, "-", "")
		healStr = _gsub(healStr, "^%s*(.-)%s*$", "%1")
	end
	
	local primaryTank = nil
	for word in _gfind(tankStr, "%S+") do
		if word ~= "" then primaryTank = word; break end
	end
	
	-- [v0.15] Insert/Update into Ordered List
	local zone = GetRealZoneText()
	if not TankMarkProfileDB[zone] then TankMarkProfileDB[zone] = {} end
	local list = TankMarkProfileDB[zone]
	
	-- 1. Check if this mark already exists in the list
	local found = false
	for _, entry in _ipairs(list) do
		if entry.mark == iconID then
			entry.tank = primaryTank or ""
			entry.healers = healStr
			found = true
			break
		end
	end
	
	-- 2. If not found, add it
	if not found and primaryTank then
		_insert(list, {
			mark = iconID,
			tank = primaryTank,
			healers = healStr
		})
	end
	
	-- 3. Sort List: Skull(8) > Cross(7) > ... Star(1)
	_sort(list, function(a,b) return a.mark > b.mark end)
	
	-- 4. Update Session if active zone
	if zone == GetRealZoneText() then
		if primaryTank then
			TankMark.sessionAssignments[iconID] = primaryTank
			TankMark.usedIcons[iconID] = true
		end
		if TankMark.UpdateHUD then TankMark:UpdateHUD() end
	end
	
	-- Refresh UI
	if TankMark.optionsFrame and TankMark.optionsFrame:IsVisible() then
		if TankMark.UpdateProfileList then TankMark:LoadProfileToCache(); TankMark:UpdateProfileList() end
	end
end

-- ==========================================================
-- CORE SYNC HANDLER
-- ==========================================================
function TankMark:HandleSync(prefix, msg, sender)
	if sender == UnitName("player") then return end
	
	if prefix == TWA_BW_PREFIX then
		if TankMark:IsTrustedSender(sender) then
			TankMark:HandleTWABW(msg, sender)
		end
		return
	end
	
	if prefix ~= SYNC_PREFIX then return end
	if not TankMark:IsTrustedSender(sender) then return end
	
	local dataType = _sub(msg, 1, 1) -- 'M' or 'L'
	local content = _sub(msg, 3) -- Strip prefix + separator
	
	if dataType == "M" then
		local _, _, zone, mob, prio, mark, mType, mClass = _strfind(content, "^(.-);(.-);(%d+);(%d+);(.-);(.-)$")
		if zone and mob then
			-- [PHASE 1 FIX] Validate incoming sync data
			local numPrio = _tonumber(prio)
			local numMark = _tonumber(mark)
			
			if not numPrio or not numMark then return end -- Reject malformed data
			if numMark < 0 or numMark > 8 then return end -- Invalid mark range
			
			if not TankMarkDB.Zones[zone] then TankMarkDB.Zones[zone] = {} end
			TankMarkDB.Zones[zone][mob] = {
				["prio"] = numPrio,
				["mark"] = numMark,
				["type"] = mType,
				["class"] = (mClass ~= "NIL") and mClass or nil
			}
		end
	
	elseif dataType == "L" then
		local _, _, zone, guid, mark, name = _strfind(content, "^(.-);(.-);(%d+);(.-)$")
		if zone and guid then
			-- [PHASE 1 FIX] Validate incoming lock data
			local numMark = _tonumber(mark)
			if not numMark or numMark < 0 or numMark > 8 then return end
			
			if not TankMarkDB.StaticGUIDs[zone] then TankMarkDB.StaticGUIDs[zone] = {} end
			TankMarkDB.StaticGUIDs[zone][guid] = {
				["mark"] = numMark,
				["name"] = name
			}
		end
	end
end

-- ==========================================================
-- BROADCAST (Sender)
-- ==========================================================
TankMark.MsgQueue = {}
TankMark.LastSendTime = 0
local THROTTLE_INTERVAL = 0.3

local throttleFrame = CreateFrame("Frame", "TankMarkThrottleFrame")
throttleFrame:Hide()
throttleFrame:SetScript("OnUpdate", function()
	if _getn(TankMark.MsgQueue) == 0 then
		this:Hide(); return
	end
	local now = GetTime()
	if (now - TankMark.LastSendTime) >= THROTTLE_INTERVAL then
		local msgData = _remove(TankMark.MsgQueue, 1)
		SendAddonMessage(msgData.prefix, msgData.text, msgData.channel)
		TankMark.LastSendTime = now
	end
end)

function TankMark:QueueMessage(prefix, text, channel)
	_insert(TankMark.MsgQueue, {prefix=prefix, text=text, channel=channel})
	throttleFrame:Show()
end

function TankMark:BroadcastZone()
	if not TankMark:CanAutomate() then
		TankMark:Print("Error: You must be Raid Leader/Assist to sync.")
		return
	end
	
	local zone = GetRealZoneText()
	local count = 0
	local channel = "PARTY"
	if GetNumRaidMembers() > 0 then channel = "RAID" end
	
	-- A. Broadcast Mobs (Prefix: M)
	if TankMarkDB.Zones[zone] then
		for mob, data in _pairs(TankMarkDB.Zones[zone]) do
			local safeClass = data.class or "NIL"
			local safeType = data.type or "KILL"
			local payload = "M;" .. zone .. ";" .. mob .. ";" .. data.prio .. ";" .. data.mark .. ";" .. safeType .. ";" .. safeClass
			TankMark:QueueMessage(SYNC_PREFIX, payload, channel)
			count = count + 1
		end
	end
	
	-- B. Broadcast Locks (Prefix: L)
	if TankMarkDB.StaticGUIDs[zone] then
		for guid, data in _pairs(TankMarkDB.StaticGUIDs[zone]) do
			local mark = (type(data) == "table") and data.mark or data
			local name = (type(data) == "table") and data.name or "Unknown"
			local payload = "L;" .. zone .. ";" .. guid .. ";" .. mark .. ";" .. name
			TankMark:QueueMessage(SYNC_PREFIX, payload, channel)
			count = count + 1
		end
	end
	
	TankMark:Print("Sync: Queued " .. count .. " items (Mobs & Locks) for zone: " .. zone)
end
