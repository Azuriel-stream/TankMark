-- Raid data synchronization

if not TankMark then return end

local SYNC_PREFIX = "TM_SYNC"

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
-- CORE SYNC HANDLER
-- ==========================================================
function TankMark:HandleSync(prefix, msg, sender)
	if sender == L._UnitName("player") then return end

	if prefix ~= SYNC_PREFIX then return end
	if not TankMark:IsTrustedSender(sender) then return end

	local dataType = L._sub(msg, 1, 1) -- 'M' (mob data)
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

	TankMark:Print("Sync: Queued " .. count .. " items (Mobs) for zone: " .. zone)
end
