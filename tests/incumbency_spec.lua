-- IncumbencyBlocks (Core/TankMark_Assignment.lua) is the shared skull-incumbency
-- predicate, used by BOTH the decide-path governor (GovernorBlocks) and the
-- death-path ReviewSkullState. It is pure -- (myPrio, blockIcon, blockPrio) in,
-- bool out -- so it needs no board. These specs pin the >= operator so it cannot
-- silently drift between its two callers.
describe("IncumbencyBlocks", function()
    local function blocks(myPrio, blockIcon, blockPrio)
        return TankMark:IncumbencyBlocks(myPrio, blockIcon, blockPrio)
    end

    it("blocks when an incumbent exists and the candidate is not strictly better", function()
        eq(blocks(5, 8, 3), true, "5 >= 3 with blocker")
    end)

    it("blocks on EQUAL priority (>=, not >)", function()
        eq(blocks(3, 4, 3), true, "3 >= 3")
    end)

    it("does NOT block when the candidate strictly outranks the incumbent", function()
        eq(blocks(2, 4, 3), false, "2 < 3")
    end)

    it("does NOT block when there is no incumbent (nil blockIcon)", function()
        eq(blocks(5, nil, 3), false, "no blocker")
    end)

    it("treats a nil blockPrio as weakest (99)", function()
        eq(blocks(5, 4, nil), false, "5 < 99")
        eq(blocks(99, 4, nil), true, "99 >= 99")
    end)
end)
