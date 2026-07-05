-- DecideSkullSuccessor (Core/TankMark_Processor.lua) is the pure death-path skull
-- decision -- the harness-testable mirror of DecideMark for skull succession.
-- Snapshot in (cheap skull-slot facts) + board (lazy live-scan ports) -> a tagged
-- intent { action = none|adopt|assign, ... }. The two scans (getBlockingMarkInfo,
-- findEmergencyCandidate) stay opaque ports; these specs pin the guard sequence and
-- the >= incumbency comparison (via the REAL loaded IncumbencyBlocks) on the death
-- path -- the one governor path otherwise only verifiable in-game.
local function decide(snap, board)
    return TankMark:DecideSkullSuccessor(snap, board or make_board{})
end

-- The succession-ready snapshot: skull dead/absent, nothing pending, not sequential.
-- Specs override only the field under test (mirrors make_board's override style).
local function snap(o)
    o = o or {}
    return {
        skullAlive    = o.skullAlive or false,
        skullLiveGUID = o.skullLiveGUID,
        memoryOwner   = o.memoryOwner,
        isSequential  = o.isSequential or false,
    }
end

describe("DecideSkullSuccessor: succession (mark8 dead/absent)", function()
    it("assigns the candidate when there is no incumbent blocker", function()
        local i = decide(snap{}, make_board{ candidate={guid="cand-1", prio=5} })
        eq_skull(i, "assign")
        eq(i.guid, "cand-1", "guid")
    end)

    it("yields none/no-candidate when the scan finds nobody", function()
        eq_skull(decide(snap{}, make_board{}), "none", "no-candidate")
    end)

    it("yields to a STRONGER incumbent (lower prio number)", function()
        local i = decide(snap{}, make_board{ candidate={guid="c", prio=5}, blocker={icon=4, prio=3} })
        eq_skull(i, "none", "incumbency")
    end)

    it("yields to an EQUAL-prio incumbent (>=, not >)", function()
        local i = decide(snap{}, make_board{ candidate={guid="c", prio=5}, blocker={icon=4, prio=5} })
        eq_skull(i, "none", "incumbency")
    end)

    it("assigns over a WEAKER incumbent (higher prio number)", function()
        local i = decide(snap{}, make_board{ candidate={guid="c", prio=5}, blocker={icon=4, prio=7} })
        eq_skull(i, "assign")
        eq(i.guid, "c", "guid")
    end)

    it("assigns when the candidate strictly outranks the incumbent", function()
        local i = decide(snap{}, make_board{ candidate={guid="c", prio=2}, blocker={icon=4, prio=5} })
        eq_skull(i, "assign")
    end)
end)

describe("DecideSkullSuccessor: guards short-circuit before the scan", function()
    it("dup-event: a pending MarkMemory owner blocks (even with a candidate ready)", function()
        local i = decide(snap{ memoryOwner="pending-guid" }, make_board{ candidate={guid="c", prio=1} })
        eq_skull(i, "none", "pending-assignment")
    end)

    it("sequential: a multi-mark skull mob is left to the batch cursor", function()
        local i = decide(snap{ isSequential=true }, make_board{ candidate={guid="c", prio=1} })
        eq_skull(i, "none", "sequential")
    end)
end)

describe("DecideSkullSuccessor: mark8-alive arm", function()
    it("adopts a live physical skull the Ledger has lost track of (owner nil)", function()
        local i = decide(snap{ skullAlive=true, skullLiveGUID="live-8" }, make_board{})
        eq_skull(i, "adopt")
        eq(i.guid, "live-8", "guid")   -- shell resolves the name from this guid at apply
    end)

    it("confirms (no-op) when we already own the live skull", function()
        local i = decide(snap{ skullAlive=true, skullLiveGUID="live-8", memoryOwner="live-8" }, make_board{})
        eq_skull(i, "none", "mark8-alive-owned")
    end)

    it("leaves a live skull alone on a STALE owner mismatch (no adopt, no steal)", function()
        local i = decide(snap{ skullAlive=true, skullLiveGUID="live-8", memoryOwner="stale-guid" },
                         make_board{ candidate={guid="c", prio=1} })
        eq_skull(i, "none", "mark8-alive")
    end)
end)
