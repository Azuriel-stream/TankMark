-- Two-sweep drain kernel (Core/TankMark_Batch.lua) -- Ascension slice C.
--
-- On Ascension the batch arms a durable {guid->icon} plan on sweep 1, then sweep 2
-- drains it per-hover onto the live mouseover token. TakePlanIcon is the PURE seam
-- of that drain: it owns the plan mutation (look up + remove + disarm-on-empty), so
-- the drain/full-drain behavior is locked down off-client. The WoW-edge apply
-- (Driver_ApplyMark on the token) stays in the thin event handler, exercised in-game.

describe("Two-sweep drain kernel (TakePlanIcon)", function()
    it("returns the planned icon and removes that entry", function()
        TankMark.pullPlan = { g1 = 8, g2 = 5 }
        eq(TankMark:TakePlanIcon("g1"), 8, "planned icon returned")
        eq(TankMark.pullPlan.g1, nil, "drained entry removed")
        eq(TankMark.pullPlan.g2, 5, "other entry survives")
    end)

    it("returns nil for a guid not in the plan (an unplanned hover is a no-op)", function()
        TankMark.pullPlan = { g1 = 8 }
        eq(TankMark:TakePlanIcon("gX"), nil, "nil for unplanned guid")
        eq(TankMark.pullPlan.g1, 8, "plan untouched")
    end)

    it("disarms the plan (pullPlan -> nil) when the last entry is drained", function()
        TankMark.pullPlan = { g1 = 8 }
        eq(TankMark:TakePlanIcon("g1"), 8, "last icon returned")
        eq(TankMark.pullPlan, nil, "plan disarmed on full drain")
    end)

    it("returns nil when no plan is armed", function()
        TankMark.pullPlan = nil
        eq(TankMark:TakePlanIcon("g1"), nil, "nil with no plan armed")
    end)

    it("returns nil on a nil guid (defensive)", function()
        TankMark.pullPlan = { g1 = 8 }
        eq(TankMark:TakePlanIcon(nil), nil, "nil guid -> nil")
        eq(TankMark.pullPlan.g1, 8, "plan untouched")
    end)
end)
