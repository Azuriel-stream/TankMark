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

if not TankMark then return end

local L = TankMark.Locals

TankMark.SyncCodec = {}
local Codec = TankMark.SyncCodec

-- Wire grammar for a mob record: "M;<zone>;<mob>;<prio>;<mark>;<type>;<class>"
-- ';' is not a Lua pattern magic char, so it is a literal delimiter on both ends.
-- The body pattern matches everything after the "M;" type tag.
local MOB_TAG = "M"
local MOB_BODY_PATTERN = "^(.-);(.-);(%d+);(%d+);(.-);(.-)$"

-- Wire grammar for a control heartbeat: "Q;<amQueen>" where amQueen is "1"/"0".
local HEARTBEAT_TAG = "Q"

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
-- it from GetRaidRosterInfo (unspoofable). planVersion is omitted until slice 4.
function Codec.EncodeHeartbeat(amQueen)
    return HEARTBEAT_TAG .. ";" .. (amQueen and "1" or "0")
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
-- amQueen flag is missing/malformed. Reads only the FIRST field after the tag, so
-- a future "Q;1;<planVersion>" wire (slice 4) decodes here unchanged.
local function decodeHeartbeat(body)
    local _, _, flag = L._strfind(body, "^([^;]*)")
    if flag ~= "0" and flag ~= "1" then return nil end
    return {
        kind    = HEARTBEAT_TAG,
        amQueen = (flag == "1"),
    }
end

-- Decode a wire message into a typed record, or nil if malformed / unknown type.
-- Pure validation only -- it rejects bad input but never touches the DB. Branches
-- on the leading tag: "M" -> mob record, "Q" -> heartbeat. The tag and its ';'
-- separator are stripped before the per-type body parser runs.
function Codec.Decode(msg)
    if not msg then return nil end

    local dataType = L._sub(msg, 1, 1)
    local body = L._sub(msg, 3) -- strip the tag + its ';' separator

    if dataType == MOB_TAG then
        return decodeMob(body)
    elseif dataType == HEARTBEAT_TAG then
        return decodeHeartbeat(body)
    end
    return nil -- unknown type tag
end
