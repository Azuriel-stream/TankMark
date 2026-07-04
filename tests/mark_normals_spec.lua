-- MarkNormals persistence accessor (TankMark:MarkNormalsEnabled, Core/Processor).
--
-- Unlike Auto-CC / Smart Pre-Marking (which default OFF), this toggle defaults ON:
-- an unset config keeps the long-standing "mark normal mobs" behavior, so only an
-- explicit off (checkbox or /tmark normals) persists. The accessor reads the live
-- TankMarkCharConfig global; these cases lock the default-true (`~= false`) inversion.

describe("MarkNormalsEnabled (default-true persistence accessor)", function()
    local function set(v) TankMarkCharConfig = v end

    it("defaults true when the whole config table is absent", function()
        set(nil)
        eq(TankMark:MarkNormalsEnabled(), true, "nil config -> true")
    end)
    it("defaults true when the field is unset", function()
        set({})
        eq(TankMark:MarkNormalsEnabled(), true, "unset field -> true")
    end)
    it("returns false only for an explicit false (the persisted off)", function()
        set({ markNormals = false })
        eq(TankMark:MarkNormalsEnabled(), false, "false -> false")
    end)
    it("returns true for an explicit true", function()
        set({ markNormals = true })
        eq(TankMark:MarkNormalsEnabled(), true, "true -> true")
    end)

    set(nil)  -- leave the global clean for later specs
end)
