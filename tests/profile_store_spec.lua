-- ProfileStore seam (TankMark.ProfileStore, Core/TankMark_ProfileStore.lua).
--
-- The sole writer of the Team Profile store (TankMarkProfileDB) and sole constructor
-- of profile entries. These cases lock the entry shape + defaults (esp. role
-- preserved-as-passed, NOT hard-defaulted to TANK), the whole-zone replace, the
-- skull-first upsert, zone delete, and the bootstrap.

local L = TankMark.Locals

describe("ProfileStore (Team Profile store writer)", function()
    local function fresh() TankMarkProfileDB = {} end

    describe("NewEntry (entry constructor)", function()
        it("builds the full {mark,tank,healers,role} shape", function()
            local e = TankMark.ProfileStore.NewEntry(8, "Bob", "Aine", "TANK")
            eq(e.mark, 8, "mark")
            eq(e.tank, "Bob", "tank")
            eq(e.healers, "Aine", "healers")
            eq(e.role, "TANK", "role")
        end)

        it("defaults healers and tank to empty string", function()
            local e = TankMark.ProfileStore.NewEntry(8)
            eq(e.tank, "", "tank default")
            eq(e.healers, "", "healers default")
        end)

        it("preserves role as-passed, nil when absent (no hard TANK default)", function()
            eq(TankMark.ProfileStore.NewEntry(8, "Bob").role, nil, "nil role preserved")
            eq(TankMark.ProfileStore.NewEntry(8, "Jaina", "", "CC").role, "CC", "CC role preserved")
        end)

        it("coerces a string mark to a number", function()
            eq(TankMark.ProfileStore.NewEntry("8", "Bob").mark, 8, "mark coerced")
        end)
    end)

    describe("SetZone (whole-zone replace)", function()
        it("replaces the zone list and normalizes each entry", function()
            fresh()
            TankMarkProfileDB["Z"] = { { mark = 8, tank = "Old" } }
            TankMark.ProfileStore.SetZone("Z", {
                { mark = "6", tank = "Bob" },              -- string mark, no healers/role
                { mark = 8, tank = "Ann", role = "CC" },
            })
            local list = TankMarkProfileDB["Z"]
            eq(L._tgetn(list), 2, "count")
            eq(list[1].mark, 6, "entry1 mark coerced")
            eq(list[1].healers, "", "entry1 healers defaulted")
            eq(list[1].role, nil, "entry1 role nil")
            eq(list[2].role, "CC", "entry2 role preserved")
        end)

        it("clears the zone to an empty list when entries is nil or {}", function()
            fresh()
            TankMarkProfileDB["Z"] = { { mark = 8, tank = "Bob" } }
            TankMark.ProfileStore.SetZone("Z", {})
            eq(L._tgetn(TankMarkProfileDB["Z"]), 0, "emptied")
            TankMark.ProfileStore.SetZone("Z", nil)
            eq(L._tgetn(TankMarkProfileDB["Z"]), 0, "nil also empties")
        end)

        it("stores fresh tables (input mutation does not leak in)", function()
            fresh()
            local src = { { mark = 8, tank = "Bob" } }
            TankMark.ProfileStore.SetZone("Z", src)
            src[1].tank = "Mutated"
            eq(TankMarkProfileDB["Z"][1].tank, "Bob", "stored copy is independent")
        end)
    end)

    describe("Upsert (assign a player to a mark)", function()
        it("updates the tank when the mark already exists", function()
            fresh()
            TankMarkProfileDB["Z"] = { { mark = 8, tank = "Old", healers = "", role = "TANK" } }
            TankMark.ProfileStore.Upsert("Z", 8, "New")
            eq(L._tgetn(TankMarkProfileDB["Z"]), 1, "no new row")
            eq(TankMarkProfileDB["Z"][1].tank, "New", "tank updated")
        end)

        it("inserts a fresh entry and re-sorts skull-first when the mark is new", function()
            fresh()
            TankMarkProfileDB["Z"] = { { mark = 6, tank = "Bob", healers = "", role = "TANK" } }
            TankMark.ProfileStore.Upsert("Z", 8, "Ann")
            local list = TankMarkProfileDB["Z"]
            eq(L._tgetn(list), 2, "row inserted")
            eq(list[1].mark, 8, "skull sorted first")
            eq(list[2].mark, 6, "lower mark second")
            eq(list[1].role, nil, "inserted role nil (class-infer path preserved)")
        end)

        it("creates the zone list on first upsert", function()
            fresh()
            TankMark.ProfileStore.Upsert("NewZone", 8, "Ann")
            eq(TankMarkProfileDB["NewZone"][1].tank, "Ann", "zone created")
        end)
    end)

    describe("DeleteZone", function()
        it("removes the zone key entirely (distinct from an empty list)", function()
            fresh()
            TankMarkProfileDB["Z"] = { { mark = 8, tank = "Bob" } }
            TankMark.ProfileStore.DeleteZone("Z")
            eq(TankMarkProfileDB["Z"], nil, "zone removed")
        end)
    end)

    describe("Wipe", function()
        it("resets the entire store to empty (every zone gone)", function()
            TankMarkProfileDB = { Z = { { mark = 8 } }, Y = { { mark = 6 } } }
            TankMark.ProfileStore.Wipe()
            eq(next(TankMarkProfileDB), nil, "store emptied")
        end)
    end)

    describe("EnsureDB", function()
        it("creates the top-level table when absent and is idempotent", function()
            TankMarkProfileDB = nil
            TankMark.ProfileStore.EnsureDB()
            eq(L._type(TankMarkProfileDB), "table", "created")
            TankMarkProfileDB["Z"] = { { mark = 8 } }
            TankMark.ProfileStore.EnsureDB()
            eq(L._tgetn(TankMarkProfileDB["Z"]), 1, "idempotent -- existing data kept")
        end)
    end)

    fresh()  -- leave the global clean for later specs
end)
