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
