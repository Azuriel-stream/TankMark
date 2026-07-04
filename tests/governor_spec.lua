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
    -- [v0.30] legal-CC routing via the pure SelectCCSlot. ccMob carries creatureType
    -- so the stored-fallback path resolves it. [v0.30 rev / BD3-A] authored type=="CC"
    -- is now reserve-gated too, so these boards commit a skull (busy={[8]=true}) to
    -- let the CC seam fire.
    local function ccMob() return { type="CC", class="MAGE", creatureType="Humanoid", marks={6}, prio=5, name="M" } end
    local function mageSlot(mark) return { mark=mark, class="MAGE", race="Orc", alive=true, used=false, disabled=false } end
    local function warlockSlot(mark) return { mark=mark, class="WARLOCK", race="Orc", alive=true, used=false, disabled=false } end

    it("resolves to the CC mark when a legal CC slot is available", function()
        -- [v0.30] B7: a CC-seam resolution reports reason "cc" (was "known").
        eq_intent(decide(ccMob(), "SCANNER", make_board{ busy={[8]=true}, ccSlots={ mageSlot(6) } }), 6, "cc")
    end)
    it("falls back to the configured mark when no CC slot is available", function()
        eq_intent(decide(ccMob(), "SCANNER", make_board{ busy={[8]=true}, ccSlots={} }), 6, "known")
    end)
    it("yields no-icon if the configured mark is busy and nothing else is free", function()
        eq_intent(decide(ccMob(), "SCANNER", make_board{ busy={[6]=true, [8]=true}, ccSlots={} }), nil, "no-icon")
    end)
    it("routes a mistagged MAGE/Elemental to the Warlock slot (legal-CC end to end)", function()
        local mob = { type="CC", class="MAGE", creatureType="Elemental", marks={6}, prio=5, name="M" }
        eq_intent(decide(mob, "SCANNER", make_board{ busy={[8]=true}, ccSlots={ mageSlot(5), warlockSlot(3) } }), 3, "cc")
    end)
    it("prefers the live creatureType over the stored one", function()
        -- Stored says Humanoid (Mage legal) but the live read says Elemental
        -- (only Warlock legal) -> must route to Warlock, proving live-first.
        local mob = { type="CC", class="MAGE", creatureType="Humanoid", marks={6}, prio=5, name="M" }
        eq_intent(decide(mob, "SCANNER", make_board{ busy={[8]=true}, creatureType="Elemental", ccSlots={ mageSlot(5), warlockSlot(3) } }), 3, "cc")
    end)
end)

describe("ResolveCC / Phase 4 auto-CC (toggle, tier gate, floor, reserve-skull)", function()
    -- Direct ResolveCC calls (the seam in isolation): a nil here means "no CC" --
    -- through the full DecideKnownMark a nil would fall through to the mob's kill
    -- mark. [v0.30 rev / BD3-A] BOTH auto-CC AND authored type=="CC" require
    -- reserve-a-kill-target (a committed skull, board.isMarkBusy(8)) -- so auto-CC
    -- cases use autoBoard{} (toggle on + skull busy) and authored-CC cases use
    -- ccBoard{} (skull busy, toggle irrelevant). No CC until a kill target exists.
    local function resolve(mob, board) return TankMark:ResolveCC(mob, "guid-1", board or make_board{}) end
    local function mageSlot(mark)    return { mark=mark, class="MAGE",    race="Orc", alive=true, used=false, disabled=false } end
    local function warlockSlot(mark) return { mark=mark, class="WARLOCK", race="Orc", alive=true, used=false, disabled=false } end
    local function healer(t) return { type="KILL", role="HEALER", creatureType="Humanoid", tier=t or "elite", name="M" } end
    -- auto-CC board: toggle on + a skull already committed (reserve satisfied).
    local function autoBoard(o) o = o or {}; o.autoCC = true; o.busy = o.busy or { [8]=true }; return make_board(o) end
    -- authored-CC board: skull committed (reserve satisfied); toggle irrelevant.
    local function ccBoard(o) o = o or {}; o.busy = o.busy or { [8]=true }; return make_board(o) end

    it("(1) toggle OFF: a worthy KILL healer with a free legal slot is NOT auto-CC'd", function()
        eq(resolve(healer(), make_board{ autoCC=false, busy={[8]=true}, ccSlots={ mageSlot(6) } }), nil, "off -> nil")
    end)
    it("(2) toggle ON + skull committed: a KILL healer takes the free Mage slot", function()
        eq(resolve(healer(), autoBoard{ ccSlots={ mageSlot(6) } }), 6, "on -> mage mark")
    end)
    it("(3) toggle ON: a MELEE is below the floor -> nil", function()
        local m = { type="KILL", role="MELEE", creatureType="Humanoid", tier="elite", name="M" }
        eq(resolve(m, autoBoard{ ccSlots={ mageSlot(6) } }), nil, "melee -> nil")
    end)
    it("(4) toggle ON: a BOSS-tier healer is CC-immune (universal tier gate) -> nil", function()
        eq(resolve(healer("boss"), autoBoard{ ccSlots={ mageSlot(6) } }), nil, "boss -> nil")
    end)
    it("(5) toggle ON: worthy healer but NO legal slot (Mage vs Elemental) -> nil", function()
        local m = { type="KILL", role="HEALER", creatureType="Elemental", tier="elite", name="M" }
        eq(resolve(m, autoBoard{ ccSlots={ mageSlot(6) } }), nil, "no legal slot -> nil")
    end)
    it("(6) toggle ON: worthy healer but the slot is already used -> nil (per-mob double-book safety)", function()
        local usedMage = { mark=6, class="MAGE", race="Orc", alive=true, used=true, disabled=false }
        eq(resolve(healer(), autoBoard{ ccSlots={ usedMage } }), nil, "used slot -> nil")
    end)
    it("(7) authored type==CC (skull committed, toggle OFF) takes the slot", function()
        local m = { type="CC", class="MAGE", creatureType="Humanoid", tier="elite", name="M" }
        eq(resolve(m, ccBoard{ ccSlots={ mageSlot(6) } }), 6, "authored CC -> mark (toggle-independent)")
    end)
    it("(8) B4: authored type==CC on a BOSS tier yields nil (universal tier gate)", function()
        local m = { type="CC", class="MAGE", creatureType="Humanoid", tier="boss", name="M" }
        eq(resolve(m, ccBoard{ ccSlots={ mageSlot(6) } }), nil, "authored CC boss -> nil")
    end)
    it("(9) B6: auto-CC passes authoredClass=nil -> first-legal-in-profile-order (ignores mobData.class)", function()
        -- Warlock listed before Mage; both legal for Humanoid. mobData.class="MAGE"
        -- would prefer the Mage slot IF honored -- asserting Warlock proves it isn't.
        local m = { type="KILL", role="HEALER", class="MAGE", creatureType="Humanoid", tier="elite", name="M" }
        eq(resolve(m, autoBoard{ ccSlots={ warlockSlot(3), mageSlot(6) } }), 3, "first-legal, not class")
    end)
    it("(10) through DecideMark: auto-CC returns the CC mark (skull committed); reason=cc", function()
        local m = { type="KILL", role="HEALER", creatureType="Humanoid", tier="elite", marks={8}, prio=5, name="M" }
        eq_intent(decide(m, "SCANNER", autoBoard{ ccSlots={ mageSlot(6) } }), 6, "cc")
    end)
    it("(11) through DecideMark: authored CC (skull committed) reports reason=cc", function()
        local m = { type="CC", class="MAGE", creatureType="Humanoid", tier="elite", marks={6}, prio=5, name="M" }
        eq_intent(decide(m, "SCANNER", ccBoard{ ccSlots={ mageSlot(6) } }), 6, "cc")
    end)
    it("(12) sequential (marks>1) bails BEFORE the CC seam even with auto-CC on", function()
        local m = { type="KILL", role="HEALER", creatureType="Humanoid", tier="elite", marks={8,6}, prio=5, name="M" }
        eq_intent(decide(m, "SCANNER", autoBoard{ ccSlots={ mageSlot(6) } }), nil, "sequential-marks")
    end)
    -- [v0.30 rev / BD3-A] reserve-a-kill-target on the scanner, BOTH branches:
    it("(13) reserve: auto-CC does NOT fire when NO skull is committed (a lone mob is killed, not CC'd)", function()
        eq(resolve(healer(), make_board{ autoCC=true, ccSlots={ mageSlot(6) } }), nil, "no skull -> reserve blocks")
    end)
    it("(14) authored type==CC ALSO needs a committed skull (BD3-A: reserve is universal)", function()
        -- a lone type==CC mob (no skull committed) is NOT sheeped -> it falls through
        -- to its own kill mark, so the first mob engaged is always a kill.
        local m = { type="CC", class="MAGE", creatureType="Humanoid", tier="elite", name="M" }
        eq(resolve(m, make_board{ ccSlots={ mageSlot(6) } }), nil, "authored, no skull -> reserve blocks")
    end)
end)
