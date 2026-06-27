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
--
-- [v0.29] Swarm slice 5a.1: "H" (handoff offer, queen->target) -- the protocol's
-- first explicit control-edge message (SWARM_DESIGN.md sec.5.10). A directed
-- crown-pass, broadcast on the shared transport; every client decodes it but only
-- the named target acts (the name-filter lives in Sync.lua, slice 5a.3). The wire
-- is one field, the target name. This checkpoint is the pure codec only -- no
-- election or runtime behavior rides on it yet.
--
-- [v0.29] Swarm slice 6.1: Mob DB sharing (SWARM_DESIGN.md sec.7). Three additions,
-- pure codec only (no runtime behavior yet -- the link hook, pull-request, send and
-- framed apply are slices 6.3/6.4): (1) the "M" mark field is widened to a '.'-joined
-- LIST so sequential marks transfer losslessly -- a single mark is the legacy-
-- identical one-element case; (2) "SB"/"SE" frame the broadcast-once share of one
-- zone (begin carries the record count, validated at end -> all-or-nothing apply);
-- (3) the clickable chat-link data grammar "tankmark:<poster>:<zone>" (a |H..|h
-- hyperlink body, not an addon message) is encoded/decoded here so it stays
-- single-sourced and harness-testable.

if not TankMark then return end

local L = TankMark.Locals

TankMark.SyncCodec = {}
local Codec = TankMark.SyncCodec

-- Wire grammar for a mob record: "M;<zone>;<mob>;<prio>;<marks>;<type>;<class>"
-- ';' is not a Lua pattern magic char, so it is a literal delimiter on both ends.
-- The body pattern matches everything after the "M;" type tag. [v0.29] slice 6:
-- the <marks> field is a '.'-joined list ("8.1.2") so sequential marks transfer
-- losslessly; a single-mark mob is the one-element case "8" (legacy-identical), so
-- the mark field pattern is now [%d%.]+ rather than %d+.
local MOB_TAG = "M"
local MOB_BODY_PATTERN = "^(.-);(.-);(%d+);([%d%.]+);(.-);(.-)$"

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

-- [v0.29] slice 5a.1 wire grammar:
--   handoff  "H;<targetName>"  -- a directed crown-pass offer, queen->target.
--            Broadcast; the target name carries no ';' so it is the whole body.
local HANDOFF_TAG = "H"

-- [v0.29] slice 6 wire grammar (SWARM_DESIGN.md sec.7.2) -- the broadcast-once
-- share of one zone's Mob DB, framed so the receiver applies it all-or-nothing:
--   share-begin "SB;<poster>;<zone>;<count>"  -- opens the frame; <count> is the
--               number of "M" records to follow (validated at SE).
--   share-end   "SE;<poster>;<zone>"          -- closes the frame.
-- Both key the frame on poster+zone; a receiver buffers a frame only while it
-- holds a matching pending-click (the click/apply machinery is slice 6.3/6.4).
local SHAREBEGIN_TAG = "SB"
local SHAREEND_TAG   = "SE"

-- [v0.29] slice 6.3 wire grammar:
--   share-request "SR;<poster>;<zone>"  -- the directed pull a link-click fires
--                 (clicker -> poster). Broadcast (1.12 has no addon-WHISPER); only
--                 the named <poster> serves it. The requester is the unspoofable
--                 CHAT_MSG_ADDON sender, gated poster-side in Sync.lua.
local SHAREREQ_TAG = "SR"

-- [v0.29] slice 6: the clickable chat-LINK data grammar -- NOT an addon message,
-- but a |H...|h hyperlink body: "tankmark:<poster>:<zone>". ':' is the hyperlink
-- delimiter (no player/zone name contains one). Single-sourced here so every wire
-- grammar stays harness-testable; the colour/display wrapping + the SetItemRef
-- hook are the UI's job (slice 6.3/6.4).
local LINK_TAG = "tankmark"

-- Encode a mob DB entry to its wire string, or nil if the entry is unusable.
-- type defaults to "KILL", a missing class is sent as the sentinel "NIL", and
-- zone/mob/prio are required -- a prio-less entry returns nil rather than
-- producing a malformed string. [v0.29] slice 6: the mark field now carries the
-- FULL marks array as a '.'-joined list, so sequential marks transfer losslessly.
-- A single-mark mob encodes to exactly the legacy "8" (byte-identical wire); the
-- whole list is <= 8 single digits, far under the 254B cap. (decodeMob parses both
-- forms; HandleSync still reads marks[1] until the framed apply lands in 6.4.)
function Codec.EncodeMob(zone, mob, data)
    if not zone or not mob or not data then return nil end
    local prio = data.prio
    if not prio then return nil end

    local marks = data.marks
    local markStr
    if marks and L._tgetn(marks) > 0 then
        markStr = "" .. marks[1]
        for i = 2, L._tgetn(marks) do
            markStr = markStr .. "." .. marks[i]
        end
    else
        markStr = "8"
    end

    local mType = data.type or "KILL"
    local mClass = data.class or "NIL"

    return MOB_TAG .. ";" .. zone .. ";" .. mob .. ";" .. prio .. ";" .. markStr .. ";" .. mType .. ";" .. mClass
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

-- [v0.29] slice 5a.1: encode a handoff offer -- the queen's directed crown-pass to
-- <target>. Broadcast like any other message; only the named target acts on it (the
-- name-filter is Sync.lua's job, slice 5a.3). A nil target returns nil, mirroring the
-- other encoders; an empty name is left to the decoder to reject (as PR does).
function Codec.EncodeHandoff(target)
    if not target then return nil end
    return HANDOFF_TAG .. ";" .. target
end

-- [v0.29] slice 6: share-frame markers. EncodeShareBegin opens a zone share with
-- the record count; EncodeShareEnd closes it. The "M" records carried between them
-- reuse Codec.EncodeMob (one mob per message, already under the 254B cap).
function Codec.EncodeShareBegin(poster, zone, count)
    if not poster or not zone then return nil end
    return SHAREBEGIN_TAG .. ";" .. poster .. ";" .. zone .. ";" .. (count or 0)
end

function Codec.EncodeShareEnd(poster, zone)
    if not poster or not zone then return nil end
    return SHAREEND_TAG .. ";" .. poster .. ";" .. zone
end

-- [v0.29] slice 6.3: encode a directed share-request (clicker -> poster).
function Codec.EncodeShareRequest(poster, zone)
    if not poster or not zone then return nil end
    return SHAREREQ_TAG .. ";" .. poster .. ";" .. zone
end

-- [v0.29] slice 6: encode the clickable share link's data field
-- ("tankmark:<poster>:<zone>"). The caller wraps it as |c..|H<this>|h[text]|h|r.
function Codec.EncodeShareLink(poster, zone)
    if not poster or not zone then return nil end
    return LINK_TAG .. ":" .. poster .. ":" .. zone
end

-- [v0.29] slice 6: decode a clicked link's data (the SetItemRef `link` arg) back
-- to { poster, zone }, or nil if it isn't ours / is malformed. The zone is
-- everything after the 2nd ':' (greedy), so a stray ':' can't truncate it.
function Codec.DecodeShareLink(linkData)
    if not linkData then return nil end
    local _, _, poster, zone = L._strfind(linkData, "^tankmark:([^:]*):(.*)$")
    if not poster or poster == "" then return nil end
    if not zone or zone == "" then return nil end
    return { poster = poster, zone = zone }
end

-- Decode the "M;..." body into a typed mob record, or nil if malformed.
local function decodeMob(body)
    local _, _, zone, mob, prio, markStr, mType, mClass = L._strfind(body, MOB_BODY_PATTERN)
    if not zone or not mob then return nil end

    local numPrio = L._tonumber(prio)
    if not numPrio then return nil end -- non-numeric prio

    -- [v0.29] slice 6: markStr is a '.'-joined list (a legacy single mark "8" is
    -- the one-element case). Parse every element; any non-numeric or out-of-icon-
    -- range value rejects the WHOLE record (the field validation HandleSync used to
    -- do inline). mark stays = marks[1] for callers that read a single icon.
    local marks = {}
    for m in L._gfind(markStr, "[^%.]+") do
        local numMark = L._tonumber(m)
        if not numMark then return nil end                 -- non-numeric mark
        if numMark < 0 or numMark > 8 then return nil end  -- icon out of range
        L._tinsert(marks, numMark)
    end
    if L._tgetn(marks) == 0 then return nil end            -- empty mark field

    return {
        kind  = MOB_TAG,
        zone  = zone,
        mob   = mob,
        prio  = numPrio,
        marks = marks,
        mark  = marks[1],
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

-- [v0.29] slice 5a.1: decode an "H;..." body into a typed handoff offer, or nil if
-- the target name is empty. Single field, trailing-tolerant (mirrors decodePull).
local function decodeHandoff(body)
    local _, _, target = L._strfind(body, "^([^;]*)")
    if not target or target == "" then return nil end
    return { kind = HANDOFF_TAG, target = target }
end

-- [v0.29] slice 6: decode an "SB;..." body into a typed share-begin, or nil if
-- malformed. body = "<poster>;<zone>;<count>" (count is the M-record total).
local function decodeShareBegin(body)
    local _, _, poster, zone, count = L._strfind(body, "^([^;]*);([^;]*);(%d+)$")
    if not poster or poster == "" then return nil end
    if not zone or zone == "" then return nil end
    local numCount = L._tonumber(count)
    if not numCount then return nil end
    return { kind = SHAREBEGIN_TAG, poster = poster, zone = zone, count = numCount }
end

-- [v0.29] slice 6: decode an "SE;..." body into a typed share-end, or nil if
-- malformed. body = "<poster>;<zone>".
local function decodeShareEnd(body)
    local _, _, poster, zone = L._strfind(body, "^([^;]*);([^;]*)$")
    if not poster or poster == "" then return nil end
    if not zone or zone == "" then return nil end
    return { kind = SHAREEND_TAG, poster = poster, zone = zone }
end

-- [v0.29] slice 6.3: decode an "SR;..." body into a typed share-request.
local function decodeShareRequest(body)
    local _, _, poster, zone = L._strfind(body, "^([^;]*);([^;]*)$")
    if not poster or poster == "" then return nil end
    if not zone or zone == "" then return nil end
    return { kind = SHAREREQ_TAG, poster = poster, zone = zone }
end

-- Decode a wire message into a typed record, or nil if malformed / unknown type.
-- Pure validation only -- it rejects bad input but never touches the DB. The tag is
-- everything before the first ';' (so a multi-char tag like "PR" parses correctly),
-- and the body is everything after it. Branches: "M" -> mob, "Q" -> heartbeat,
-- "P" -> profile snapshot, "PR" -> pull-request, "H" -> handoff offer,
-- "SB"/"SE" -> share-frame begin/end (slice 6).
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
    elseif tag == HANDOFF_TAG then
        return decodeHandoff(body)
    elseif tag == SHAREBEGIN_TAG then
        return decodeShareBegin(body)
    elseif tag == SHAREEND_TAG then
        return decodeShareEnd(body)
    elseif tag == SHAREREQ_TAG then
        return decodeShareRequest(body)
    end
    return nil -- unknown type tag
end
