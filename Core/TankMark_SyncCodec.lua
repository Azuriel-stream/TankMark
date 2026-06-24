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

if not TankMark then return end

local L = TankMark.Locals

TankMark.SyncCodec = {}
local Codec = TankMark.SyncCodec

-- Wire grammar for a mob record: "M;<zone>;<mob>;<prio>;<mark>;<type>;<class>"
-- ';' is not a Lua pattern magic char, so it is a literal delimiter on both ends.
-- The body pattern matches everything after the "M;" type tag.
local MOB_TAG = "M"
local MOB_BODY_PATTERN = "^(.-);(.-);(%d+);(%d+);(.-);(.-)$"

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

-- Decode a wire message into a typed record, or nil if malformed / unknown type.
-- Pure validation only -- it rejects bad input but never touches the DB. On
-- success returns { kind = "M", zone, mob, prio = <number>, mark = <number>,
-- type, class = <string|nil> } (class "NIL" sentinel decodes back to nil).
function Codec.Decode(msg)
    if not msg then return nil end

    local dataType = L._sub(msg, 1, 1)
    if dataType ~= MOB_TAG then return nil end -- only the mob record exists today

    local body = L._sub(msg, 3) -- strip the tag + its ';' separator
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
