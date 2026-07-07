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
