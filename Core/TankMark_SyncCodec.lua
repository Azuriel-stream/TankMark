-- Sync wire codec: the single source of truth for the TankMark addon-message
-- format. Pure and definition-only -- string <-> typed record, no WoW client
-- state, no Ledger, no session, no top-level execution -- so the off-client
-- tests/ harness can dofile it directly (unlike Sync.lua, which builds a frame
-- at load). All stateful work (trust checks, the DB write, the send queue) stays
-- in Sync.lua; this file only translates between the wire and a structured record.
--
-- [v0.29] Swarm slice 1: extracted from the two hand-rolled copies of the "M"
-- mob-record format that previously lived apart in Sync.lua (encoder in
-- BroadcastZone, decoder in HandleSync). One contract now, so the field order /
-- separator / validation cannot drift between the two ends.
--
-- [v0.29] Swarm slice 2: the codec is now the typed-dispatch table the swarm
-- design (SWARM_DESIGN.md sec.8) calls for -- Decode branches on the leading tag.
-- The "Q" control-plane heartbeat rides the SAME TM_SYNC prefix as the "M" data
-- record; its wire carries amQueen only (rank is read from the unspoofable
-- roster, never sent). Q-decode tolerates trailing fields so slice 4 can append
-- planVersion without a wire break.
--
-- [v0.29] Swarm slice 4: profile-sync (SWARM_DESIGN.md sec.6.1). Two new types --
-- "P" (profile snapshot, queen->drones) and "PR" (pull-request, drone->queen) --
-- plus the now-live "planVersion" field on the "Q" heartbeat. The "P" snapshot is
-- HUD-minimal (mark+tank+role only; healers are deferred to the chunked-transport
-- slice) and small enough to be ONE atomic message, so a drone replaces the whole
-- zone in one apply (deletions are free; no framing). Tags are now multi-char
-- ("PR"), so Decode splits the tag on the first ';' rather than taking one char.

if not TankMark then return end

local L = TankMark.Locals

TankMark.SyncCodec = {}
local Codec = TankMark.SyncCodec

-- Wire grammar for a mob record: "M;<zone>;<mob>;<prio>;<mark>;<type>;<class>"
-- ';' is not a Lua pattern magic char, so it is a literal delimiter on both ends.
-- The body pattern matches everything after the "M;" type tag.
local MOB_TAG = "M"
local MOB_BODY_PATTERN = "^(.-);(.-);(%d+);(%d+);(.-);(.-)$"

-- Wire grammar for a control heartbeat: "Q;<amQueen>;<planVersion>" where amQueen
-- is "1"/"0" and planVersion is the queen's profile counter (0 if none/non-queen).
local HEARTBEAT_TAG = "Q"

-- [v0.29] slice 4 wire grammar:
--   profile  "P;<zone>;<planVersion>;<mark>,<tank>,<role>;<mark>,<tank>,<role>;..."
--            role is a single char: "T" (TANK) / "C" (CC). Entries are optional
--            (an empty profile is "P;<zone>;<planVersion>"). Player names carry no
--            ',' or ';', so both stay literal delimiters.
--   pull     "PR;<zone>"  -- a bare refetch request for one zone.
local PROFILE_TAG = "P"
local PULL_TAG    = "PR"

-- Encode a mob DB entry to its wire string, or nil if the entry is unusable.
-- Mirrors the historical BroadcastZone defaults: only the FIRST mark is synced
-- (sequential marks are a local-only feature), type defaults to "KILL", and a
-- missing class is sent as the sentinel "NIL". zone/mob/prio are required --
-- a prio-less entry returns nil rather than producing a malformed string.
function Codec.EncodeMob(zone, mob, data)
    if not zone or not mob or not data then return nil end
    local prio = data.prio
    if not prio then return nil end

    local mark = (data.marks and data.marks[1]) or 8
    local mType = data.type or "KILL"
    local mClass = data.class or "NIL"

    return MOB_TAG .. ";" .. zone .. ";" .. mob .. ";" .. prio .. ";" .. mark .. ";" .. mType .. ";" .. mClass
end

-- [v0.29] Encode a control-plane heartbeat. amQueen is the sender's own current
-- belief that it is the queen. Rank is deliberately NOT carried -- receivers read
-- it from GetRaidRosterInfo (unspoofable). [slice 4] planVersion now rides the
-- heartbeat so drones can detect a stale profile; it is 0 for a non-queen.
function Codec.EncodeHeartbeat(amQueen, planVersion)
    return HEARTBEAT_TAG .. ";" .. (amQueen and "1" or "0") .. ";" .. (planVersion or 0)
end

-- [v0.29] slice 4: encode a profile snapshot. entries is an array of
-- { mark, tank, role } (role "TANK"/"CC"); healers are deliberately omitted (they
-- are never rendered and would overflow one message -- see SWARM_DESIGN.md sec.6.1).
-- An entry without a mark is skipped; an empty/absent entry list yields the
-- header-only "P;<zone>;<planVersion>" which decodes to an empty snapshot.
function Codec.EncodeProfile(zone, planVersion, entries)
    if not zone then return nil end
    local s = PROFILE_TAG .. ";" .. zone .. ";" .. (planVersion or 0)
    entries = entries or {}
    for i = 1, L._tgetn(entries) do
        local e = entries[i]
        if e and e.mark then
            local role = (e.role == "CC") and "C" or "T"
            s = s .. ";" .. e.mark .. "," .. (e.tank or "") .. "," .. role
        end
    end
    return s
end

-- [v0.29] slice 4: encode a pull-request -- a bare "refetch zone X" the drone
-- sends when its applied (queen,planVersion,zone) key no longer matches.
function Codec.EncodePull(zone)
    if not zone then return nil end
    return PULL_TAG .. ";" .. zone
end

-- Decode the "M;..." body into a typed mob record, or nil if malformed.
local function decodeMob(body)
    local _, _, zone, mob, prio, mark, mType, mClass = L._strfind(body, MOB_BODY_PATTERN)
    if not zone or not mob then return nil end

    local numPrio = L._tonumber(prio)
    local numMark = L._tonumber(mark)
    if not numPrio or not numMark then return nil end -- non-numeric prio/mark
    if numMark < 0 or numMark > 8 then return nil end -- mark out of icon range

    return {
        kind  = MOB_TAG,
        zone  = zone,
        mob   = mob,
        prio  = numPrio,
        mark  = numMark,
        type  = mType,
        class = (mClass ~= "NIL") and mClass or nil,
    }
end

-- [v0.29] Decode the "Q;..." body into a typed heartbeat record, or nil if the
-- amQueen flag is missing/malformed. [slice 4] also reads planVersion from the
-- second field; a legacy "Q;1" (no version) or any non-numeric version decodes to
-- planVersion 0, so a slice-2 peer is forward-compatible.
local function decodeHeartbeat(body)
    local _, _, flag, ver = L._strfind(body, "^([^;]*);?(%d*)")
    if flag ~= "0" and flag ~= "1" then return nil end
    return {
        kind        = HEARTBEAT_TAG,
        amQueen     = (flag == "1"),
        planVersion = L._tonumber(ver) or 0,
    }
end

-- [v0.29] slice 4: decode a "P;..." body into a typed profile snapshot, or nil if
-- malformed. body = "<zone>;<planVersion>;<entry>;<entry>;...". A single bad entry
-- rejects the WHOLE message (return nil) so a drone keeps its current plan and
-- refetches, rather than applying a corrupt partial. An empty entry list is valid
-- (the empty snapshot -- the receiver decides keep-vs-clear, see sec.6.1).
local function decodeProfile(body)
    local _, _, zone, ver, rest = L._strfind(body, "^([^;]*);(%d+);?(.*)$")
    if not zone or zone == "" then return nil end
    local numVer = L._tonumber(ver)
    if not numVer then return nil end

    local entries = {}
    if rest and rest ~= "" then
        for chunk in L._gfind(rest, "[^;]+") do
            local _, _, m, tank, role = L._strfind(chunk, "^(%d+),([^,]*),([TC])$")
            local numMark = L._tonumber(m)
            if not numMark or numMark < 0 or numMark > 8 then return nil end
            L._tinsert(entries, {
                mark = numMark,
                tank = tank or "",
                role = (role == "C") and "CC" or "TANK",
            })
        end
    end

    return {
        kind        = PROFILE_TAG,
        zone        = zone,
        planVersion = numVer,
        entries     = entries,
    }
end

-- [v0.29] slice 4: decode a "PR;..." body into a typed pull-request, or nil if the
-- zone is empty. Only the first field is read (trailing-tolerant).
local function decodePull(body)
    local _, _, zone = L._strfind(body, "^([^;]*)")
    if not zone or zone == "" then return nil end
    return { kind = PULL_TAG, zone = zone }
end

-- Decode a wire message into a typed record, or nil if malformed / unknown type.
-- Pure validation only -- it rejects bad input but never touches the DB. The tag is
-- everything before the first ';' (so a multi-char tag like "PR" parses correctly),
-- and the body is everything after it. Branches: "M" -> mob, "Q" -> heartbeat,
-- "P" -> profile snapshot, "PR" -> pull-request.
function Codec.Decode(msg)
    if not msg then return nil end

    local _, _, tag, body = L._strfind(msg, "^([^;]*);(.*)$")
    if not tag then return nil end -- no separator -> structurally malformed

    if tag == MOB_TAG then
        return decodeMob(body)
    elseif tag == HEARTBEAT_TAG then
        return decodeHeartbeat(body)
    elseif tag == PROFILE_TAG then
        return decodeProfile(body)
    elseif tag == PULL_TAG then
        return decodePull(body)
    end
    return nil -- unknown type tag
end
