-- Reservation seam (TankMark.Reservation.Reserve, Core/TankMark_Reservation.lua).
--
-- Reservation is the manual claim of a mark slot for a player (/tmark assign, the
-- HUD): it flags the icon occupied (usedIcons) AND binds the responsible player
-- (sessionAssignments) in one atomic write -- the pair the CLAUDE.md "one
-- documented exception" used to hand-enforce at scattered call sites. Ownership
-- (the Ledger) and assignment-projection (the profile) are separate concerns;
-- these cases lock only the reservation write.

describe("Reservation.Reserve (manual mark-slot claim)", function()
    local function fresh()
        TankMark.usedIcons = {}
        TankMark.sessionAssignments = {}
    end

    it("occupies the icon and binds the player in one call", function()
        fresh()
        TankMark.Reservation.Reserve(3, "Bob")
        eq(TankMark.usedIcons[3], true, "usedIcons occupied")
        eq(TankMark.sessionAssignments[3], "Bob", "player bound")
    end)

    it("is a safe no-op when the icon is nil (no error, no write)", function()
        fresh()
        TankMark.Reservation.Reserve(nil, "Bob")
        eq(next(TankMark.usedIcons), nil, "usedIcons untouched")
        eq(next(TankMark.sessionAssignments), nil, "sessionAssignments untouched")
    end)

    it("does not occupy the slot when the player is nil", function()
        fresh()
        TankMark.Reservation.Reserve(3, nil)
        eq(TankMark.usedIcons[3], nil, "slot not occupied without a player")
        eq(TankMark.sessionAssignments[3], nil, "no player bound")
    end)

    fresh()  -- leave the globals clean for later specs
end)
