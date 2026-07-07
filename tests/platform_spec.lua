-- Platform seam (TankMark.Platform, Core/TankMark_Platform.lua).
--
-- The per-client boundary (ADR 0003). Shared Core reads platform CAPABILITIES
-- through this one table so a behavioral change in Core inherits to every build.
-- Exactly one platform impl registers at load (package-per-target); in its
-- ABSENCE the defaults are the full-capability Vanilla/SuperWoW baseline, so the
-- Vanilla build needs no registration and stays behavior-identical. Slice 1
-- covers only the capability registry; the primitives land with the impl that
-- first needs them.

describe("Platform seam (capabilities + registration)", function()
    -- Captured at load (describe body runs before any it mutates the table), so
    -- this genuinely asserts the MODULE's default -- not a value fresh() planted.
    local loadedHasScanner = TankMark.Platform.Caps and TankMark.Platform.Caps.hasScanner
    local loadedRequiresSuperWoW = TankMark.Platform.Caps and TankMark.Platform.Caps.requiresSuperWoW

    local function fresh()
        -- Reset to the as-loaded Vanilla baseline (mimics a fresh module load).
        TankMark.Platform.Caps = { hasScanner = true, requiresSuperWoW = true }
        TankMark.Platform.name = nil
    end

    it("defaults to the full-capability Vanilla baseline (hasScanner true)", function()
        eq(loadedHasScanner, true, "hasScanner defaults true at load")
    end)

    -- [v0.32] slice C: the gate capability. CanAutomate requires SuperWoW UNLESS the
    -- platform declares it does not -- so the default must be true (Vanilla needs it).
    it("requiresSuperWoW defaults true at load (Vanilla needs SuperWoW)", function()
        eq(loadedRequiresSuperWoW, true, "requiresSuperWoW defaults true at load")
    end)

    it("Register downgrades requiresSuperWoW to false (the Ascension gate opt-out)", function()
        fresh()
        TankMark.Platform.Register({ name = "Ascension", caps = { requiresSuperWoW = false } })
        eq(TankMark.Platform.Caps.requiresSuperWoW, false, "requiresSuperWoW downgraded")
    end)

    it("Register downgrades a capability a platform lacks", function()
        fresh()
        TankMark.Platform.Register({ name = "Ascension", caps = { hasScanner = false } })
        eq(TankMark.Platform.Caps.hasScanner, false, "hasScanner downgraded")
        eq(TankMark.Platform.name, "Ascension", "platform name recorded")
    end)

    it("Register leaves unspecified capabilities at the baseline", function()
        fresh()
        TankMark.Platform.Register({ name = "X", caps = {} })
        eq(TankMark.Platform.Caps.hasScanner, true, "unspecified cap keeps baseline")
    end)

    it("Register merges caps -- it does not replace unrelated flags", function()
        fresh()
        TankMark.Platform.Caps.someOther = true
        TankMark.Platform.Register({ caps = { hasScanner = false } })
        eq(TankMark.Platform.Caps.hasScanner, false, "target flag set")
        eq(TankMark.Platform.Caps.someOther, true, "unrelated flag survives")
    end)

    it("Register is a safe no-op on a nil impl", function()
        fresh()
        TankMark.Platform.Register(nil)
        eq(TankMark.Platform.Caps.hasScanner, true, "baseline untouched")
    end)

    fresh()  -- leave a clean baseline for later specs
end)

-- The write primitive (slice A). Platform.SetMark is the raw, mechanical raid-
-- target write -- the ONE per-platform fork point for placing/clearing a mark.
-- No gate, no logging (those stay in Core's Driver_ApplyMark wrapper / the clear
-- sites' outer ShouldDriveMarks gates). The Vanilla default just delegates to
-- L._SetRaidTarget, so we assert delegation + arg-forwarding via a capturing stub
-- (the harness deliberately leaves _SetRaidTarget unstubbed -- it is the WoW edge).
describe("Platform seam (write primitive -- Platform.SetMark)", function()
    local captured
    local function stubWrite()
        captured = nil
        TankMark.Locals._SetRaidTarget = function(unit, icon)
            captured = { unit = unit, icon = icon }
        end
    end

    it("SetMark exists as a callable default (the Vanilla baseline)", function()
        eq(TankMark.Locals._type(TankMark.Platform.SetMark), "function", "SetMark default present")
    end)

    it("the default delegates an apply to L._SetRaidTarget, forwarding both args", function()
        stubWrite()
        TankMark.Platform.SetMark("0xF130001234", 7)
        eq(captured and captured.unit, "0xF130001234", "unit forwarded")
        eq(captured and captured.icon, 7, "icon forwarded")
    end)

    it("the default forwards a clear (icon 0) unchanged -- clears are writes too", function()
        stubWrite()
        TankMark.Platform.SetMark("mark3", 0)
        eq(captured and captured.unit, "mark3", "clear token forwarded")
        eq(captured and captured.icon, 0, "clear icon 0 forwarded")
    end)
end)

-- The identity primitive (slice C). Platform.GUID(unit) reads a unit's GUID -- the
-- one genuinely platform-specific read the two-sweep needs. The Vanilla default uses
-- SuperWoW's 2-return UnitExists (exists, guid); Ascension overrides it with native
-- UnitGUID (that override lives in the overlay, exercised in-game). Here we assert the
-- DEFAULT's contract via a stubbed _UnitExists (the harness leaves it unstubbed -- a
-- WoW edge), including that it yields nil on a non-SuperWoW client (no 2nd return) --
-- which is exactly why a SuperWoW-less Vanilla client cannot mark.
describe("Platform seam (identity primitive -- Platform.GUID)", function()
    local function stubExists(existsRet, guidRet)
        TankMark.Locals._UnitExists = function(_) return existsRet, guidRet end
    end

    it("GUID exists as a callable default (the Vanilla baseline)", function()
        eq(TankMark.Locals._type(TankMark.Platform.GUID), "function", "GUID default present")
    end)

    it("the default returns the guid from SuperWoW's 2-return UnitExists", function()
        stubExists(true, "0xF130001234")
        eq(TankMark.Platform.GUID("mouseover"), "0xF130001234", "guid returned")
    end)

    it("the default returns nil when the unit does not exist", function()
        stubExists(nil, nil)
        eq(TankMark.Platform.GUID("mouseover"), nil, "nil when absent")
    end)

    it("the default returns nil when the unit exists but yields no guid (non-SuperWoW)", function()
        stubExists(1, nil)   -- native UnitExists: truthy, no 2nd return
        eq(TankMark.Platform.GUID("mouseover"), nil, "nil without a SuperWoW guid")
    end)
end)
