-- ZoneView seam (TankMark.ZoneView, Core/TankMark_ZoneView.lua).
--
-- The "active zone view" (activeDB) is the current zone's mob knowledge as the
-- decision layer reads it: TankMarkDB.Zones overlaid user-wins on TankMarkDefaults,
-- validated as it is built. ZoneView.ValidateEntry is the per-entry gate;
-- ZoneView.Merge builds the whole view. Both are pure -- no WoW API, no globals.
--
-- Contract (from the candidate-C grill):
--   Required fields invalid  -> DROP the entry (mob falls to the unknown-mob path).
--   Optional fields invalid  -> NORMALIZE (type->KILL, role->nil, class->nil), keep.
--   Validation is NON-MUTATING: same ref if clean, shallow copy if it normalizes.

describe("ZoneView.ValidateEntry (per-entry gate)", function()
    it("passes a clean entry through unchanged, same reference", function()
        local entry = { prio = 5, marks = { 8 }, type = "KILL", class = nil }
        local got = TankMark.ZoneView.ValidateEntry("Lucifron", entry)
        eq(got, entry, "clean entry returns the same reference")
    end)

    it("coerces a string prio to a number without mutating the source", function()
        local entry = { prio = "5", marks = { 8 }, type = "KILL" }
        local got = TankMark.ZoneView.ValidateEntry("Gehennas", entry)
        eq(got.prio, 5, "returned prio is the number 5")
        eq(entry.prio, "5", "source entry left untouched (non-mutating)")
    end)

    it("drops an entry whose prio is unusable (nil or non-numeric)", function()
        eq(TankMark.ZoneView.ValidateEntry("M", { prio = nil, marks = { 8 } }), nil,
            "nil prio -> dropped")
        eq(TankMark.ZoneView.ValidateEntry("M", { prio = "abc", marks = { 8 } }), nil,
            "non-numeric prio -> dropped")
    end)

    it("drops an entry with unusable marks (nil, empty, out-of-range, non-numeric)", function()
        eq(TankMark.ZoneView.ValidateEntry("M", { prio = 5, marks = nil }), nil,
            "nil marks -> dropped")
        eq(TankMark.ZoneView.ValidateEntry("M", { prio = 5, marks = {} }), nil,
            "empty marks -> dropped")
        eq(TankMark.ZoneView.ValidateEntry("M", { prio = 5, marks = { 9 } }), nil,
            "out-of-range mark -> dropped")
        eq(TankMark.ZoneView.ValidateEntry("M", { prio = 5, marks = { "x" } }), nil,
            "non-numeric mark -> dropped")
    end)

    it("coerces string marks to numbers without mutating the source", function()
        local entry = { prio = 5, marks = { "8", 2 } }
        local got = TankMark.ZoneView.ValidateEntry("M", entry)
        eq(got.marks[1], 8, "first mark coerced to number 8")
        eq(got.marks[2], 2, "second mark preserved as 2")
        eq(entry.marks[1], "8", "source marks left untouched (non-mutating)")
    end)

    it("defaults an invalid type to KILL, keeps a valid one, non-mutating", function()
        local bad = { prio = 5, marks = { 8 }, type = "BOGUS" }
        local got = TankMark.ZoneView.ValidateEntry("M", bad)
        eq(got.type, "KILL", "invalid type -> KILL")
        eq(bad.type, "BOGUS", "source type left untouched (non-mutating)")

        local cc = { prio = 5, marks = { 8 }, type = "CC" }
        eq(TankMark.ZoneView.ValidateEntry("M", cc), cc, "valid type -> same reference")
    end)

    it("nils an invalid mob role, keeps a valid one, preserves absent, non-mutating", function()
        local bad = { prio = 5, marks = { 8 }, type = "KILL", role = "BOGUS" }
        local got = TankMark.ZoneView.ValidateEntry("M", bad)
        eq(got.role, nil, "invalid role -> nil")
        eq(bad.role, "BOGUS", "source role left untouched (non-mutating)")

        local healer = { prio = 5, marks = { 8 }, type = "KILL", role = "HEALER" }
        eq(TankMark.ZoneView.ValidateEntry("M", healer), healer, "valid role -> same reference")
    end)

    it("nils a non-string class, keeps a valid one, non-mutating", function()
        local bad = { prio = 5, marks = { 8 }, type = "KILL", class = 123 }
        local got = TankMark.ZoneView.ValidateEntry("M", bad)
        eq(got.class, nil, "non-string class -> nil")
        eq(bad.class, 123, "source class left untouched (non-mutating)")

        local mage = { prio = 3, marks = { 5 }, type = "CC", class = "MAGE" }
        eq(TankMark.ZoneView.ValidateEntry("M", mage), mage, "valid class -> same reference")
    end)
end)

describe("ZoneView.Merge (build the active zone view)", function()
    it("lets a user entry win over the shipped default", function()
        local user     = { Gehennas = { prio = 1, marks = { 8 }, type = "KILL" } }
        local defaults = { Gehennas = { prio = 9, marks = { 0 }, type = "KILL" } }
        local view = TankMark.ZoneView.Merge(user, defaults)
        eq(view.Gehennas.prio, 1, "user prio wins over default")
    end)

    it("fills a gap from defaults where the user has no entry", function()
        local user     = { Alpha = { prio = 2, marks = { 8 } } }
        local defaults = { Beta  = { prio = 5, marks = { 8 } } }
        local view = TankMark.ZoneView.Merge(user, defaults)
        eq(view.Alpha.prio, 2, "user entry present")
        eq(view.Beta.prio, 5, "default fills the gap")
    end)

    it("validates entries during the merge -- a malformed entry is dropped", function()
        local user = { Bad = { prio = "x", marks = { 8 } } }
        local view = TankMark.ZoneView.Merge(user, {})
        eq(view.Bad, nil, "malformed entry dropped from the view")
        eq(next(view), nil, "view is empty")
    end)

    it("returns an empty view when both zones are absent", function()
        eq(next(TankMark.ZoneView.Merge(nil, nil)), nil, "nil zones -> empty view")
    end)
end)
