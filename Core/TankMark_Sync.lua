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

	-- [v0.29] Decode + validate through the pure codec FIRST (pure, no state
	-- change) so the share plane can bypass the rank gate. The DB write below is
	-- the single stateful apply edge (mirrors the Ledger / ApplyMarkIntent pattern).
	local rec = TankMark.SyncCodec.Decode(msg)
	if not rec then return end

	-- [v0.29] slice 6.3: SHARE PLANE -- consent-only, NO rank gate (SWARM_DESIGN
	-- sec.7.2). A share-request (SR) is the directed pull a link-click fired; only
	-- the named poster serves it, and a requester this client has BLOCKED is
	-- dropped here (sec.7.4). No local state is mutated -- the poster just
	-- re-broadcasts its OWN Mob DB -- so the rank gate is irrelevant.
	if rec.kind == "SR" then
		if not TankMark.Trust.IsBlocked(sender) then
			TankMark:OnShareRequest(sender, rec)
		end
		return
	end

	-- [v0.29] slice 6.4a: SHARE-FRAME receive (also share plane -- consent-only,
	-- no rank gate). SB opens a buffer iff we hold a matching pending-click for
	-- (sender, zone); a framed M (we are buffering from this sender) appends; SE
	-- validates the count then applies under the trust gate. A NAKED M (no active
	-- buffer) is the legacy push, still handled rank-gated below until 6.4b.
	if rec.kind == "SB" then
		TankMark:OnShareBegin(sender, rec)
		return
	end
	if rec.kind == "SE" then
		TankMark:OnShareEnd(sender, rec)
		return
	end
	if rec.kind == "M" and TankMark:IsBufferingShare(sender) then
		TankMark:OnShareRecord(sender, rec)
		return
	end

	-- [v0.29] CONTROL PLANE + legacy "M" data: keep the rank>=1 gate (election
	-- integrity for Q/P/PR/H; the legacy push for M until the 6.4 cutover).
	if not TankMark:IsTrustedSender(sender) then return end

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

	-- [v0.29] slice 5a.3: a directed handoff offer (queen -> named target). Passed the
	-- same rank>=1 IsTrustedSender gate; OnHandoffOffer additionally requires the sender
	-- be our OWN elected queen and the target be us (4 gates, sec.5.10), so a trusted
	-- non-queen cannot forge a crown-pass and a bystander ignores it. No DB write.
	if rec.kind == "H" then
		if TankMark.Swarm then TankMark.Swarm.OnHandoffOffer(sender, rec) end
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

-- ==========================================================
-- [v0.29] SLICE 6.3: MOB DB SHARING -- POSTER PIPELINE
-- ==========================================================
-- The advertise -> pull -> broadcast-once model (SWARM_DESIGN.md sec.7.2) that
-- replaces the unsolicited push at the 6.4 cutover. This checkpoint is the POSTER
-- half: post a clickable link (PostShareLink), and serve directed pull-requests
-- coalesced into ONE framed broadcast (OnShareRequest -> BroadcastShareFrame).
-- The clicker half -- the SetItemRef hook that fires the request, and the framed
-- receive + consent apply -- is slice 6.4. Until then the link is visible but
-- only actionable once 6.4 adds the click hook.

-- Coalesce/cooldown: collapse a click-storm into one broadcast per zone, then a
-- cooldown during which further requests are ignored (DoS bound: <=1 broadcast
-- per SHARE_COOLDOWN per zone, no matter how many clicked).
local COALESCE_WINDOW = 4   -- seconds to gather requests before broadcasting
local SHARE_COOLDOWN  = 10  -- seconds before a zone may be re-broadcast
local shareCoalesce   = {}  -- zone -> GetTime() deadline to fire the broadcast
local lastShareBcast  = {}  -- zone -> GetTime() of the last broadcast

-- Does this client hold a non-empty Mob DB for the zone?
local function HasZoneDB(zone)
	if not zone or not TankMarkDB.Zones[zone] then return false end
	for _ in L._pairs(TankMarkDB.Zones[zone]) do return true end
	return false
end

-- The group channel for sharing, or nil if solo.
local function GroupChannel()
	if L._GetNumRaidMembers() > 0 then return "RAID" end
	if L._GetNumPartyMembers() > 0 then return "PARTY" end
	return nil
end

-- Post a clickable Mob DB share link for <zone> to party/raid chat. One entry
-- point for all triggers (the Manage Zones "Share" button this checkpoint; the
-- /tmark + HUD triggers repoint here at the 6.4 cutover). The link is only an
-- advertisement -- clicking it (6.4) pulls the data over addon messages.
function TankMark:PostShareLink(zone)
	zone = zone or L._GetRealZoneText()
	if not zone or zone == "" then
		TankMark:Print("|cffff0000Share:|r no zone selected.")
		return
	end
	if not HasZoneDB(zone) then
		TankMark:Print("|cffff0000Share:|r no Mob DB to share for zone: " .. zone)
		return
	end
	local channel = GroupChannel()
	if not channel then
		TankMark:Print("|cffff0000Share:|r join a party or raid to share.")
		return
	end

	local me = L._UnitName("player")
	local linkData = TankMark.SyncCodec.EncodeShareLink(me, zone)
	if not linkData then return end
	-- colour + |H<data>|h[display]|h + |r : clickable on the 1.12 client, inert
	-- (empty tooltip) for non-TankMark users -- the click hook is added in 6.4.
	local link = "|cff33ff99|H" .. linkData .. "|h[TankMark: " .. zone .. " Mob DB]|h|r"
	L._SendChatMessage("Click to import my " .. zone .. " Mob DB: " .. link, channel)
	TankMark:Print("Posted a " .. zone .. " Mob DB share link to " .. channel .. ".")
end

-- Broadcast one framed share of <zone>'s Mob DB: SB(count) -> N x M -> SE. The
-- count is the number of VALID M payloads (EncodeMob can skip a prio-less entry),
-- so the receiver's all-or-nothing count check at SE matches exactly.
function TankMark:BroadcastShareFrame(zone)
	if not HasZoneDB(zone) then return end
	local channel = GroupChannel()
	if not channel then return end  -- left the group before the timer fired
	local me = L._UnitName("player")

	local payloads = {}
	for mob, data in L._pairs(TankMarkDB.Zones[zone]) do
		local p = TankMark.SyncCodec.EncodeMob(zone, mob, data)
		if p then L._tinsert(payloads, p) end
	end
	local count = L._tgetn(payloads)

	TankMark:QueueMessage(SYNC_PREFIX, TankMark.SyncCodec.EncodeShareBegin(me, zone, count), channel)
	for i = 1, count do
		TankMark:QueueMessage(SYNC_PREFIX, payloads[i], channel)
	end
	TankMark:QueueMessage(SYNC_PREFIX, TankMark.SyncCodec.EncodeShareEnd(me, zone), channel)

	if TankMark.DebugEnabled then
		TankMark:DebugLog("SYNC", "Broadcast share frame", { zone = zone, count = count })
	end
end

-- The coalesce timer: fire any zone whose window has elapsed, then stop itself
-- once nothing is pending. Cheap -- only runs while a broadcast is queued.
local shareFrame = L._CreateFrame("Frame", "TankMarkShareFrame")
shareFrame:Hide()
shareFrame:SetScript("OnUpdate", function()
	local now = L._GetTime()
	local due
	for zone, deadline in L._pairs(shareCoalesce) do
		if now >= deadline then
			due = due or {}
			L._tinsert(due, zone)
		end
	end
	if due then
		for i = 1, L._tgetn(due) do
			local zone = due[i]
			shareCoalesce[zone] = nil
			lastShareBcast[zone] = now
			TankMark:BroadcastShareFrame(zone)
		end
	end
	-- keep running while any zone is still pending; otherwise stop.
	for _ in L._pairs(shareCoalesce) do return end
	this:Hide()
end)

-- A directed share-request arrived (clicker -> us). Serve it only if we are the
-- named poster and actually have the zone; coalesce a click-storm into one
-- broadcast and honour the per-zone cooldown. (The block filter on the requester
-- is applied in HandleSync before this runs.)
function TankMark:OnShareRequest(sender, rec)
	if not rec or rec.poster ~= L._UnitName("player") then return end
	if not HasZoneDB(rec.zone) then return end

	local now = L._GetTime()
	-- recently broadcast this zone -> ignore (cooldown / DoS bound)
	if lastShareBcast[rec.zone] and (now - lastShareBcast[rec.zone]) < SHARE_COOLDOWN then return end
	-- already coalescing this zone -> folded into the pending broadcast
	if shareCoalesce[rec.zone] then return end

	shareCoalesce[rec.zone] = now + COALESCE_WINDOW
	shareFrame:Show()
end

-- ==========================================================
-- [v0.29] SLICE 6.4a: MOB DB SHARING -- RECEIVER PIPELINE
-- ==========================================================
-- The clicker/receiver half (SWARM_DESIGN.md sec.7.2): a link-click pulls, the
-- framed reply is buffered solicited-only and applied under the trust gate.
-- SECURITY: trust + the buffer are keyed on the UNSPOOFABLE CHAT_MSG_ADDON sender
-- (sec.7.5), never the link's or SB's claimed poster name. A frame is buffered
-- ONLY while we hold a matching pending-click for (sender, zone). The SetItemRef
-- click hook and the import-confirm dialog live in UI/TankMark_HUD.lua (Core has
-- no UI); this file is the logic + the single DB-apply edge (snapshot + replace).

local PENDING_CLICK_TTL = 15   -- seconds a click stays valid awaiting a frame
local pendingClicks = {}       -- (poster..":"..zone) -> GetTime() expiry
local incoming = {}            -- sender -> { zone, count, received, records, expiry }

-- Return the live buffer for <sender>, lazily expiring a stale one (an SB whose
-- SE never arrived) so it can't shadow the legacy naked-M path indefinitely.
local function liveBuffer(sender)
	local buf = incoming[sender]
	if not buf then return nil end
	if L._GetTime() > buf.expiry then
		incoming[sender] = nil
		return nil
	end
	return buf
end

-- A link was clicked (from the SetItemRef hook). Fire the directed pull and arm a
-- pending-click so the named poster's framed reply will be accepted.
function TankMark:OnShareLinkClick(poster, zone)
	if not poster or not zone or zone == "" then return end
	if TankMark.Trust.IsBlocked(poster) then
		TankMark:Print("|cffff0000Share:|r ignored a link from blocked player " .. poster .. ".")
		return
	end
	if poster == L._UnitName("player") then
		TankMark:Print("That is your own " .. zone .. " Mob DB share link.")
		return
	end
	local channel = GroupChannel()
	if not channel then
		TankMark:Print("|cffff0000Share:|r join " .. poster .. "'s party/raid to import.")
		return
	end
	pendingClicks[poster .. ":" .. zone] = L._GetTime() + PENDING_CLICK_TTL
	local req = TankMark.SyncCodec.EncodeShareRequest(poster, zone)
	if req then TankMark:QueueMessage(SYNC_PREFIX, req, channel) end
	TankMark:Print("Requested " .. poster .. "'s " .. zone .. " Mob DB...")
end

-- True while a share frame from <sender> is being buffered (used by HandleSync to
-- route a framed M to the buffer vs the legacy naked-M path).
function TankMark:IsBufferingShare(sender)
	return liveBuffer(sender) ~= nil
end

-- SB: open a buffer, but ONLY if this client holds a valid pending-click for
-- (sender, zone) -- solicited-only, so an unrequested or forged frame is dropped.
function TankMark:OnShareBegin(sender, rec)
	if TankMark.Trust.IsBlocked(sender) then return end
	local key = sender .. ":" .. rec.zone
	local exp = pendingClicks[key]
	if not exp or L._GetTime() > exp then
		pendingClicks[key] = nil   -- expired/absent -> not solicited, ignore frame
		return
	end
	pendingClicks[key] = nil       -- consume the click; the frame is now in flight
	incoming[sender] = {
		zone = rec.zone, count = rec.count, received = 0, records = {},
		expiry = L._GetTime() + PENDING_CLICK_TTL,
	}
end

-- M while buffering: append (keyed by mob, the final DB shape). Bound the buffer
-- so a malicious over-send can't grow memory past the count SB promised.
function TankMark:OnShareRecord(sender, rec)
	local buf = liveBuffer(sender)
	if not buf then return end
	if buf.received >= buf.count then  -- more records than promised -> abort frame
		incoming[sender] = nil
		return
	end
	if rec.zone ~= buf.zone then return end
	buf.received = buf.received + 1
	buf.records[rec.mob] = {
		prio = rec.prio, marks = rec.marks, type = rec.type, class = rec.class,
	}
end

-- SE: finalize. Consume the buffer; require an exact count match (all-or-nothing);
-- then the trust gate decides auto-import (Trusted) vs confirm UI (Neutral).
function TankMark:OnShareEnd(sender, rec)
	local buf = liveBuffer(sender)
	if not buf then return end
	incoming[sender] = nil
	if not rec.zone or rec.zone ~= buf.zone then return end
	if buf.received ~= buf.count then
		TankMark:Print("|cffff0000Import:|r " .. sender .. "'s " .. buf.zone ..
			" share was incomplete (" .. buf.received .. "/" .. buf.count .. "); kept your DB.")
		return
	end
	if TankMark.Trust.IsBlocked(sender) then return end
	if TankMark.Trust.IsTrusted(sender) then
		TankMark:ApplyShare(sender, buf)
	elseif TankMark.ShowShareConfirm then
		TankMark:ShowShareConfirm(sender, buf)  -- Neutral -> UI confirm (HUD.lua)
	end
end

-- The single DB-apply edge: snapshot, then FULL-ZONE replace (deletions
-- propagate). Called by the Trusted auto-path and by the confirm UI on Import.
function TankMark:ApplyShare(sender, buf)
	if not buf or not buf.zone then return end
	if TankMark.CreateSnapshot then TankMark:CreateSnapshot() end
	TankMarkDB.Zones[buf.zone] = buf.records
	TankMark:Print("Imported " .. sender .. "'s " .. buf.zone .. " Mob DB (" ..
		buf.count .. " mobs). A snapshot was saved.")
	if TankMark.UpdateMobList then TankMark:UpdateMobList() end
end
