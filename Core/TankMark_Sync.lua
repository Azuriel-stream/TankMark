-- Raid data synchronization

if not TankMark then return end

local SYNC_PREFIX = "TM_SYNC"
-- [v0.29] Exposed so the swarm shell (Core/TankMark_Swarm.lua) sends heartbeats
-- on the same prefix it receives them on. One transport, one trust gate.
TankMark.SyncPrefix = SYNC_PREFIX

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

	-- [v0.29] Decode + validate through the pure codec. The DB write below is the
	-- single stateful apply edge (mirrors the Ledger / ApplyMarkIntent pattern).
	local rec = TankMark.SyncCodec.Decode(msg)
	if not rec then return end

	-- [v0.29] slice 2: a control-plane heartbeat routes to the swarm shell. It
	-- passed the same IsTrustedSender (rank>=1) gate as the M data record above --
	-- which is exactly the candidate set -- and the swarm reads rank from the
	-- roster regardless, so a spoofed payload cannot promote anyone.
	if rec.kind == "Q" then
		if TankMark.Swarm then TankMark.Swarm.OnHeartbeat(sender, rec) end
		return
	end

	-- [v0.29] slice 4: profile-sync data plane. Both passed the same rank>=1
	-- IsTrustedSender gate above. OnProfile additionally requires the sender be the
	-- drone's OWN elected queen before it overwrites the local plan (auto-apply), so
	-- a rank>=1 non-queen can pollute comms but never rewrite a drone's HUD. A PR is
	-- a public refetch the queen answers (coalesced); harmless from any trusted peer.
	if rec.kind == "P" then
		if TankMark.Swarm then TankMark.Swarm.OnProfile(sender, rec) end
		return
	end
	if rec.kind == "PR" then
		if TankMark.Swarm then TankMark.Swarm.OnPullRequest(sender, rec) end
		return
	end

	if rec.kind ~= "M" then return end

	if not TankMarkDB.Zones[rec.zone] then TankMarkDB.Zones[rec.zone] = {} end
	-- [v0.23] marks stored as an array (the wire carries only the first mark).
	TankMarkDB.Zones[rec.zone][rec.mob] = {
		["prio"] = rec.prio,
		["marks"] = { rec.mark },
		["type"] = rec.type,
		["class"] = rec.class,
	}
end

-- ==========================================================
-- BROADCAST (Sender)
-- ==========================================================
TankMark.MsgQueue = {}
TankMark.LastSendTime = 0
local THROTTLE_INTERVAL = 0.3

local throttleFrame = L._CreateFrame("Frame", "TankMarkThrottleFrame")
throttleFrame:Hide()
throttleFrame:SetScript("OnUpdate", function()
	if L._tgetn(TankMark.MsgQueue) == 0 then
		this:Hide(); return
	end

	local now = L._GetTime()
	if (now - TankMark.LastSendTime) >= THROTTLE_INTERVAL then
		local msgData = L._tremove(TankMark.MsgQueue, 1)
		L._SendAddonMessage(msgData.prefix, msgData.text, msgData.channel)
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

	-- A. Broadcast Mobs (Prefix: M). The wire format is single-sourced in the
	-- codec; EncodeMob syncs only the first mark (sequential marks stay local).
	if TankMarkDB.Zones[zone] then
		for mob, data in L._pairs(TankMarkDB.Zones[zone]) do
			local payload = TankMark.SyncCodec.EncodeMob(zone, mob, data)
			if payload then
				TankMark:QueueMessage(SYNC_PREFIX, payload, channel)
				count = count + 1
			end
		end
	end

	TankMark:Print("Sync: Queued " .. count .. " items (Mobs) for zone: " .. zone)
end
