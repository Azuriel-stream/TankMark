-- The skull governor (GovernorBlocks), CC resolution (ResolveCC), and the
-- deliberate allowSteal asymmetry (roadmap #3 / PR #57). These exercise the
-- board's skull ports (isMarkBusy(8), markOwnerPriority(8), getBlockingMarkInfo)
-- and the real, loaded IncumbencyBlocks.
local function decide(mob, mode, board)
    return TankMark:DecideMark(mob, "guid-1", mode or "SCANNER", board or make_board{})
end
local SKULL = { marks = {8}, prio = 5, name = "M" }   -- prio-5 skull mob

describe("Governor: known path (allowSteal=true)", function()
    it("takes a free skull when there is no incumbent", function()
        eq_intent(decide(SKULL, "SCANNER", make_board{}), 8, "known")
    end)
    it("yields to a stronger incumbent (lower prio number)", function()
        eq_intent(decide(SKULL, "SCANNER", make_board{ blocker={icon=4, prio=2} }), nil, "governor-incumbency")
    end)
    it("yields to an EQUAL-prio incumbent (>=, not >)", function()
        eq_intent(decide(SKULL, "SCANNER", make_board{ blocker={icon=4, prio=5} }), nil, "governor-incumbency")
    end)
    it("does NOT yield to a weaker incumbent (higher prio number)", function()
        eq_intent(decide(SKULL, "SCANNER", make_board{ blocker={icon=4, prio=7} }), 8, "known")
    end)
    it("steals an occupied skull it outranks (override=true)", function()
        local i = decide({marks={8}, prio=1, name="M"}, "SCANNER", make_board{ busy={[8]=true}, ownerPrio={[8]=5} })
        eq_intent(i, 8, "known")
        eq(i.override, true, "override")
    end)
    it("does not steal an occupied skull it does not outrank (-> no-icon, no free)", function()
        local i = decide(SKULL, "SCANNER", make_board{ busy={[8]=true}, ownerPrio={[8]=3} })
        eq_intent(i, nil, "no-icon")
    end)
    it("does not steal on equal priority either (-> no-icon, no free)", function()
        local i = decide(SKULL, "SCANNER", make_board{ busy={[8]=true}, ownerPrio={[8]=5} })
        eq_intent(i, nil, "no-icon")
    end)
end)

describe("Governor: unknown path (allowSteal=false)", function()
    it("takes a free skull", function()
        eq_intent(decide(nil, "SCANNER", make_board{ free=8 }), 8, "unknown-free")
    end)
    it("NEVER steals an occupied skull", function()
        eq_intent(decide(nil, "SCANNER", make_board{ free=8, busy={[8]=true} }), nil, "governor-skull-taken")
    end)
    it("yields to an incumbent when the skull is free", function()
        eq_intent(decide(nil, "SCANNER", make_board{ free=8, blocker={icon=4, prio=2} }), nil, "governor-incumbency")
    end)
end)

describe("allowSteal asymmetry (PR #57 -- deliberate, not a TODO)", function()
    -- Same situation, opposite policy: an occupied skull held by an UNTRACKED
    -- holder (markOwnerPriority defaults to 99). Known asserts its DB plan and
    -- takes it; unknown has nothing to assert and stays hands-off.
    it("KNOWN prio-5 steals an untracked/phantom skull", function()
        local i = decide(SKULL, "SCANNER", make_board{ busy={[8]=true} })  -- ownerPrio defaults 99
        eq_intent(i, 8, "known")
        eq(i.override, true, "override")
    end)
    it("UNKNOWN prio-5 leaves the same untracked skull alone", function()
        eq_intent(decide(nil, "SCANNER", make_board{ free=8, busy={[8]=true} }), nil, "governor-skull-taken")
    end)
end)

describe("ResolveCC / CC marking", function()
    -- [v0.30] legal-CC routing: the board now exposes getCCSlots() + creatureType()
    -- and the decision is the pure SelectCCSlot. ccMob carries creatureType so the
    -- stored-fallback path resolves it (board.creatureType defaults nil).
    local function ccMob() return { type="CC", class="MAGE", creatureType="Humanoid", marks={6}, prio=5, name="M" } end
    local function mageSlot(mark) return { mark=mark, class="MAGE", race="Orc", alive=true, used=false, disabled=false } end
    local function warlockSlot(mark) return { mark=mark, class="WARLOCK", race="Orc", alive=true, used=false, disabled=false } end

    it("resolves to the CC mark when a legal CC slot is available", function()
        eq_intent(decide(ccMob(), "SCANNER", make_board{ ccSlots={ mageSlot(6) } }), 6, "known")
    end)
    it("falls back to the configured mark when no CC slot is available", function()
        eq_intent(decide(ccMob(), "SCANNER", make_board{ ccSlots={} }), 6, "known")
    end)
    it("yields no-icon if the configured mark is busy and nothing else is free", function()
        eq_intent(decide(ccMob(), "SCANNER", make_board{ ccSlots={}, busy={[6]=true} }), nil, "no-icon")
    end)
    it("routes a mistagged MAGE/Elemental to the Warlock slot (legal-CC end to end)", function()
        local mob = { type="CC", class="MAGE", creatureType="Elemental", marks={6}, prio=5, name="M" }
        eq_intent(decide(mob, "SCANNER", make_board{ ccSlots={ mageSlot(5), warlockSlot(3) } }), 3, "known")
    end)
    it("prefers the live creatureType over the stored one", function()
        -- Stored says Humanoid (Mage legal) but the live read says Elemental
        -- (only Warlock legal) -> must route to Warlock, proving live-first.
        local mob = { type="CC", class="MAGE", creatureType="Humanoid", marks={6}, prio=5, name="M" }
        eq_intent(decide(mob, "SCANNER", make_board{ creatureType="Elemental", ccSlots={ mageSlot(5), warlockSlot(3) } }), 3, "known")
    end)
end)
