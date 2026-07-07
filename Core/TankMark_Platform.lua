-- Platform adapter seam -- the per-client boundary. [v0.32] (ADR 0003)
--
-- Shared Core reads platform CAPABILITIES (and, later, platform-bound PRIMITIVES:
-- apply/read-a-mark, identity, transport) through this one table, so a behavioral
-- change in Core inherits to every client build and only genuinely platform-
-- specific code forks. Exactly ONE platform impl registers itself at load
-- (package-per-target); in its ABSENCE the defaults below are the full-capability
-- Vanilla/SuperWoW baseline, so the Vanilla build needs no registration and stays
-- behavior-identical.
--
-- Slice 1 defines only the capability registry. The primitives land with the
-- Ascension impl that first needs them (ADR 0004).

if not TankMark then return end

local L = TankMark.Locals

TankMark.Platform = TankMark.Platform or {}

-- Capability flags. Default = the Vanilla/SuperWoW baseline (full capability); a
-- reduced platform downgrades only the flags it lacks, via Register.
--   hasScanner -- a passive nameplate scanner discovers and marks in-combat mobs.
--     true  -> the batch defers in-combat mobs to the scanner (Vanilla).
--     false -> no scanner exists, so the batch is the only in-combat marker
--              (ADR 0004: Ascension). Read at the batch in-combat gate.
TankMark.Platform.Caps = TankMark.Platform.Caps or {}
if TankMark.Platform.Caps.hasScanner == nil then
    TankMark.Platform.Caps.hasScanner = true
end
-- [v0.32] slice C: the CanAutomate gate capability. Vanilla automation REQUIRES
-- SuperWoW (no scanner + no mark-by-GUID without it), so this defaults true and the
-- gate keeps blocking a SuperWoW-less Vanilla client. Ascension registers false: it
-- marks via the two-sweep live-token path, not SuperWoW, so it must pass the gate.
--   true  -> CanAutomate returns false unless IsSuperWoW (Vanilla).
--   false -> CanAutomate skips the SuperWoW requirement (Ascension).
if TankMark.Platform.Caps.requiresSuperWoW == nil then
    TankMark.Platform.Caps.requiresSuperWoW = true
end

-- Register(impl): a platform impl calls this once at load to declare itself and
-- downgrade the capabilities it lacks. impl = { name = "...", caps = { ... } }.
-- Merges onto the baseline -- unspecified caps keep their default. Safe no-op on
-- a nil impl.
function TankMark.Platform.Register(impl)
    if not impl then return end
    if impl.name then TankMark.Platform.name = impl.name end
    if impl.caps then
        for k, v in L._pairs(impl.caps) do
            TankMark.Platform.Caps[k] = v
        end
    end
end

-- SetMark(unitOrGuid, icon): the raw raid-target WRITE primitive -- [v0.32] (slice A).
-- The ONE per-platform fork point for placing (icon 1-8) or clearing (icon 0) a mark.
-- Mechanical only: NO permission gate, NO logging. The drone-suppression backstop
-- (ShouldDriveMarks) + apply logging stay in Core's Driver_ApplyMark wrapper; the
-- clear sites keep their own outer ShouldDriveMarks gate. The first arg is a raid-
-- target-addressable reference: a GUID on SuperWoW/Vanilla (which unifies GUIDs and
-- unit tokens for SetRaidTarget) or a standard unit/mark-slot token (mark1-8, target,
-- ...). It CANNOT be strictly GUID-in: a clear addresses a slot ("clear mark3"), for
-- which no GUID exists. The DEFAULT below IS the Vanilla baseline AND already handles
-- the Ascension apply edge: SetRaidTarget accepts a live unit/mark token, so the
-- two-sweep (slice C) calls SetMark('mouseover', icon) through this same default --
-- Ascension needs NO override. ADR 0004's "not-GUID-in exception" is just the CALLER
-- passing a token, realized by this polymorphism, not by a platform override. The READ
-- primitive stays deferred (still no consumer): sweep 2 reads occupancy via
-- GetRaidTargetIndex('mouseover'), a token read that works natively on both platforms.
TankMark.Platform.SetMark = TankMark.Platform.SetMark or function(unitOrGuid, icon)
    L._SetRaidTarget(unitOrGuid, icon)
end

-- GUID(unit): the identity READ primitive -- [v0.32] (slice C). Returns a unit token's
-- GUID, or nil. The ONE genuinely platform-specific read the two-sweep needs, because
-- the two ways to read a GUID differ by client: SuperWoW/Vanilla returns it as the 2nd
-- value of UnitExists (the DEFAULT below); Ascension has no such extension and uses
-- native UnitGUID (the overlay overrides this at load). Driver_GetGUID delegates here,
-- so the batch collector AND the flight recorder inherit the right read per platform.
-- The default yields nil on a SuperWoW-less client (UnitExists returns no 2nd value) --
-- which is precisely why such a client cannot mark.
TankMark.Platform.GUID = TankMark.Platform.GUID or function(unit)
    local exists, guid = L._UnitExists(unit)
    if exists and guid then return guid end
    return nil
end
