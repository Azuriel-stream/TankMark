-- The ZoneView seam: builds the "active zone view" (activeDB) -- the current
-- zone's mob knowledge as the decision layer reads it, TankMarkDB.Zones overlaid
-- user-wins on TankMarkDefaults, validated as it is built.
--
-- Why validate at all, when every writer already sanitizes (the editor coerces
-- prio, the SyncCodec rejects non-numeric prio/marks, the recorder hard-codes a
-- clean shape, the shipped Defaults are clean)? This is a fail-closed chokepoint:
-- defense-in-depth so a future writer -- or a hand-edited SavedVariables file --
-- can never feed the decision layer a malformed entry, plus the one guarantee no
-- writer makes today (type / mob-role enum membership). It is behavior-identical:
-- for every reachable input the entries are already clean, so nothing is dropped
-- or normalized in practice.
--
-- Contract:
--   Required fields invalid  -> DROP the entry (return nil). The mob then falls to
--                               the unknown-mob path -- we never fabricate a prio.
--   Optional fields invalid  -> NORMALIZE (type->KILL, bad role->nil, bad class->nil).
--   NON-MUTATING: a clean entry returns the SAME reference (activeDB keeps sharing
--   references with TankMarkDB.Zones, as it always has); an entry that needs a
--   field normalized returns a shallow COPY, leaving the authored DB untouched.
--
-- Pure: no WoW API, no globals -- the shell (Data.lua LoadZoneData) reads the
-- world and assigns activeDB; this module only transforms tables it is handed.

if not TankMark then return end

local L = TankMark.Locals

TankMark.ZoneView = {}
local ZoneView = TankMark.ZoneView

-- The canonical enums (CONTEXT.md). type is a required-ish field (defaulted, never
-- dropped); mob role is optional (bad -> nil). These are the ONLY place either enum
-- is asserted anywhere -- no writer validates them today.
local VALID_TYPE = { KILL = true, CC = true, IGNORE = true }
local VALID_ROLE = { HEALER = true, CASTER = true, MELEE = true }

-- [v0.31] Validate one mob entry. Returns the entry (same ref) if clean, a
-- normalized shallow copy if an optional field was out of range, or nil if a
-- required field (prio, marks) is unusable.
function ZoneView.ValidateEntry(name, entry)
    -- Lazily clone only when a field must change, so a clean entry returns the
    -- SAME reference (activeDB keeps sharing refs with TankMarkDB.Zones), and the
    -- authored DB is never mutated.
    local out = entry
    local function normalize()
        if out == entry then
            out = {}
            for k, v in L._pairs(entry) do out[k] = v end
        end
    end

    -- prio (required): coerce a string form ("5" -> 5); drop the entry if unusable.
    local numPrio = L._tonumber(entry.prio)
    if not numPrio then return nil end
    if numPrio ~= entry.prio then
        normalize()
        out.prio = numPrio
    end

    -- marks (required): non-empty; every element a number in [0,8]. Drop the entry
    -- on any unusable mark (a fabricated marks array is more dangerous than none).
    local srcMarks = entry.marks
    if L._type(srcMarks) ~= "table" or L._tgetn(srcMarks) == 0 then return nil end
    local cleanMarks, marksChanged = {}, false
    for i = 1, L._tgetn(srcMarks) do
        local m = L._tonumber(srcMarks[i])
        if not m or m < 0 or m > 8 then return nil end
        cleanMarks[i] = m
        if m ~= srcMarks[i] then marksChanged = true end
    end
    if marksChanged then
        normalize()
        out.marks = cleanMarks
    end

    -- type (optional): default anything outside {KILL,CC,IGNORE} to KILL -- garbage
    -- must never auto-CC. nil is treated as absent -> KILL (matches the codec).
    if not VALID_TYPE[entry.type] then
        normalize()
        out.type = "KILL"
    end

    -- mob role (optional): a PRESENT value outside {HEALER,CASTER,MELEE} is dropped
    -- to nil (which already degrades to the MELEE row). Absent stays absent -- so a
    -- default entry with no role keeps its same-reference passthrough.
    if entry.role ~= nil and not VALID_ROLE[entry.role] then
        normalize()
        out.role = nil
    end

    -- class (optional): the preferred-CC class hint must be a string. A non-string
    -- value is dropped to nil (it would never match a class anyway).
    if entry.class ~= nil and L._type(entry.class) ~= "string" then
        normalize()
        out.class = nil
    end

    return out
end

-- [v0.31] Build the active zone view for one zone: user entries win, shipped
-- defaults fill gaps, every entry validated through ValidateEntry (a dropped
-- entry is simply absent -> its mob falls to the unknown-mob path). Pure: hand it
-- the two source zone tables (either may be nil), get back the merged view. If a
-- user entry is dropped by validation, a valid default for the same name still
-- fills the gap -- the baseline is better than nothing.
function ZoneView.Merge(userZone, defaultsZone)
    local view = {}

    if userZone then
        for name, entry in L._pairs(userZone) do
            local clean = ZoneView.ValidateEntry(name, entry)
            if clean then view[name] = clean end
        end
    end

    if defaultsZone then
        for name, entry in L._pairs(defaultsZone) do
            if not view[name] then
                local clean = ZoneView.ValidateEntry(name, entry)
                if clean then view[name] = clean end
            end
        end
    end

    return view
end
