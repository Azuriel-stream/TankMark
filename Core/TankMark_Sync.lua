-- TankMark: v0.26
-- File: Core/TankMark_Sync.lua
-- Raid data synchronization and TWA integration

if not TankMark then return end

local SYNC_PREFIX = "TM_SYNC"
local TWA_BW_PREFIX = "TWABW"

-- ==========================================================
-- LOCALIZATIONS
-- ==========================================================

-- Import shared localizations
local L = TankMark.Locals

-- ==========================================================
-- HELPER: Permissions
-- ==========================================================
function TankMark:IsTrustedSender(name)
	local numRaid = L._GetNumRaidMembers()
	if numRaid > 0 then
		for i = 1, 40 do
			local n, rank = L._GetRaidRosterInfo(i)
			if n == name then return (rank >= 1) end -- 1=Assist, 2=Leader
		end
	else
		if L._GetNumPartyMembers() > 0 then
			for i = 1, 4 do
				if L._UnitName("party"..i) == name and L._UnitIsPartyLeader("party"..i) then
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
	local _, _, content = L._strfind(msg, "^BWSynch=(.*)")
	if not content or content == "start" or content == "end" then return end

	local _, _, markName, rest = L._strfind(content, "^%s*(.-)%s*:%s*(.*)")
	if not markName or not TankMark.TWA_MarkMap[markName] then return end

	local iconID = TankMark.TWA_MarkMap[markName]
	local _, _, tankPart, healPart = L._strfind(rest, "^(.-)%s*[|][|]%s*Healers:%s*(.*)$")
	
	if not tankPart then
		tankPart = rest
		healPart = ""
	end

	local tankStr = L._gsub(tankPart, "-", "")
	tankStr = L._gsub(tankStr, "[|]", "")
	tankStr = L._gsub(tankStr, "^%s*(.-)%s*$", "%1")

	local healStr = ""
	if healPart then
		healStr = L._gsub(healPart, "-", "")
		healStr = L._gsub(healStr, "^%s*(.-)%s*$", "%1")
	end

	local primaryTank = nil
	for word in L._gfind(tankStr, "%S+") do
		if word ~= "" then primaryTank = word; break end
	end

	-- [v0.15] Insert/Update into Ordered List
	local zone = L._GetRealZoneText()
	if not TankMarkProfileDB[zone] then TankMarkProfileDB[zone] = {} end
	local list = TankMarkProfileDB[zone]

	-- 1. Check if this mark already exists in the list
	local found = false
	for _, entry in L._ipairs(list) do
		if entry.mark == iconID then
			entry.tank = primaryTank or ""
			entry.healers = healStr
			entry.role = TankMark:InferRoleFromClass(primaryTank or "")
			found = true
			break
		end
	end

	-- 2. If not found, add it
	if not found and primaryTank then
		L._tinsert(list, {
			mark = iconID,
			tank = primaryTank,
			healers = healStr,
			role = TankMark:InferRoleFromClass(primaryTank),
		})
	end

	-- 3. Sort List: Skull(8) > Cross(7) > ... Star(1)
	L._tsort(list, function(a,b) return a.mark > b.mark end)

	-- 4. Update Session if active zone
	if zone == L._GetRealZoneText() then
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
	if sender == L._UnitName("player") then return end

	if prefix == TWA_BW_PREFIX then
		if TankMark:IsTrustedSender(sender) then
			TankMark:HandleTWABW(msg, sender)
		end
		return
	end

	if prefix ~= SYNC_PREFIX then return end
	if not TankMark:IsTrustedSender(sender) then return end

	local dataType = L._sub(msg, 1, 1) -- 'M' or 'L'
	local content = L._sub(msg, 3) -- Strip prefix + separator

	if dataType == "M" then
		local _, _, zone, mob, prio, mark, mType, mClass = L._strfind(content, "^(.-);(.-);(%d+);(%d+);(.-);(.-)$")
		if zone and mob then
			-- [PHASE 1 FIX] Validate incoming sync data
			local numPrio = L._tonumber(prio)
			local numMark = L._tonumber(mark)
			if not numPrio or not numMark then return end -- Reject malformed data
			if numMark < 0 or numMark > 8 then return end -- Invalid mark range

			if not TankMarkDB.Zones[zone] then TankMarkDB.Zones[zone] = {} end

			-- [v0.23] FIX: Use marks array instead of scalar mark
			TankMarkDB.Zones[zone][mob] = {
				["prio"] = numPrio,
				["marks"] = {numMark}, -- ✅ FIXED: Wrap in array
				["type"] = mType,
				["class"] = (mClass ~= "NIL") and mClass or nil
			}
		end

	elseif dataType == "L" then
		local _, _, zone, guid, mark, name = L._strfind(content, "^(.-);(.-);(%d+);(.-)$")
		if zone and guid then
			-- [PHASE 1 FIX] Validate incoming lock data
			local numMark = L._tonumber(mark)
			if not numMark or numMark < 0 or numMark > 8 then return end

			if not TankMarkDB.StaticGUIDs[zone] then TankMarkDB.StaticGUIDs[zone] = {} end
			TankMarkDB.StaticGUIDs[zone][guid] = {
				["mark"] = numMark, -- GUID locks still use scalar (not array)
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
	if L._tgetn(TankMark.MsgQueue) == 0 then
		this:Hide(); return
	end

	local now = L._GetTime()
	if (now - TankMark.LastSendTime) >= THROTTLE_INTERVAL then
		local msgData = L._tremove(TankMark.MsgQueue, 1)
		SendAddonMessage(msgData.prefix, msgData.text, msgData.channel)
		TankMark.LastSendTime = now
	end
end)

function TankMark:QueueMessage(prefix, text, channel)
	L._tinsert(TankMark.MsgQueue, {prefix=prefix, text=text, channel=channel})
	throttleFrame:Show()
end

function TankMark:BroadcastZone()
	if not TankMark:CanAutomate() then
		-- [PHASE 2] Standardized error format
		TankMark:Print("|cffff0000Error:|r You must be Raid Leader/Assist to sync.")
		return
	end

	local zone = L._GetRealZoneText()
	local count = 0
	local channel = "PARTY"
	if L._GetNumRaidMembers() > 0 then channel = "RAID" end

	-- A. Broadcast Mobs (Prefix: M)
	if TankMarkDB.Zones[zone] then
		for mob, data in L._pairs(TankMarkDB.Zones[zone]) do
			local safeClass = data.class or "NIL"
			local safeType = data.type or "KILL"

			-- [v0.23] FIX: Extract first mark from marks array
			local firstMark = (data.marks and data.marks[1]) or 8

			-- [v0.23] NOTE: Sync protocol only transmits FIRST mark
			-- Sequential marks are NOT synced (local-only feature)
			local payload = "M;" .. zone .. ";" .. mob .. ";" .. data.prio .. ";" .. firstMark .. ";" .. safeType .. ";" .. safeClass
			TankMark:QueueMessage(SYNC_PREFIX, payload, channel)
			count = count + 1
		end
	end

	-- B. Broadcast Locks (Prefix: L)
	if TankMarkDB.StaticGUIDs[zone] then
		for guid, data in L._pairs(TankMarkDB.StaticGUIDs[zone]) do
			local mark = (L._type(data) == "table") and data.mark or data
			local name = (L._type(data) == "table") and data.name or "Unknown"
			local payload = "L;" .. zone .. ";" .. guid .. ";" .. mark .. ";" .. name
			TankMark:QueueMessage(SYNC_PREFIX, payload, channel)
			count = count + 1
		end
	end

	TankMark:Print("Sync: Queued " .. count .. " items (Mobs & Locks) for zone: " .. zone)
end
