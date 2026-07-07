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

    local function fresh()
        -- Reset to the as-loaded Vanilla baseline (mimics a fresh module load).
        TankMark.Platform.Caps = { hasScanner = true }
        TankMark.Platform.name = nil
    end

    it("defaults to the full-capability Vanilla baseline (hasScanner true)", function()
        eq(loadedHasScanner, true, "hasScanner defaults true at load")
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
