-- Phase 2 legal-CC routing: the pure CC authority.
--
-- Covers the three pure functions added to Core/TankMark_Assignment.lua --
-- IsLegalCC (creature-legality over the reconciled CCMap), CCRaceEligible (the
-- narrow Troll-Hex race gate), and SelectCCSlot (the two-pass role-gated
-- resolver). All pure: no board, no WoW client. The live enumerator GetCCSlots
-- and the ResolveCC wiring are exercised via the board in governor_spec.lua and
-- in-game (open-world).

-- Build a CC slot record with sane defaults (alive, free, enabled).
-- slot{mark=5, class="MAGE", race="Gnome", alive=false, used=true, disabled=true}
local function slot(o)
    o = o or {}
    return {
        mark     = o.mark,
        class    = o.class,
        race     = o.race or "Orc",
        alive    = (o.alive ~= false),
        used     = o.used or false,
        disabled = o.disabled or false,
    }
end

describe("IsLegalCC (reconciled CCMap)", function()
    it("humanoid: Mage/Rogue/Warlock/Shaman legal; Priest removed", function()
        eq(TankMark:IsLegalCC("MAGE",    "Humanoid"), true,  "mage")
        eq(TankMark:IsLegalCC("ROGUE",   "Humanoid"), true,  "rogue")
        eq(TankMark:IsLegalCC("WARLOCK", "Humanoid"), true,  "warlock")
        eq(TankMark:IsLegalCC("SHAMAN",  "Humanoid"), true,  "shaman")
        eq(TankMark:IsLegalCC("PRIEST",  "Humanoid"), false, "priest removed")
    end)
    it("beast: Mage/Druid/Hunter/Shaman legal; Warlock not", function()
        eq(TankMark:IsLegalCC("MAGE",    "Beast"), true,  "mage")
        eq(TankMark:IsLegalCC("DRUID",   "Beast"), true,  "druid")
        eq(TankMark:IsLegalCC("HUNTER",  "Beast"), true,  "hunter")
        eq(TankMark:IsLegalCC("SHAMAN",  "Beast"), true,  "shaman")
        eq(TankMark:IsLegalCC("WARLOCK", "Beast"), false, "warlock not")
    end)
    it("elemental/demon: Warlock only", function()
        eq(TankMark:IsLegalCC("WARLOCK", "Elemental"), true,  "ele warlock")
        eq(TankMark:IsLegalCC("MAGE",    "Elemental"), false, "ele mage no")
        eq(TankMark:IsLegalCC("WARLOCK", "Demon"),     true,  "demon warlock")
        eq(TankMark:IsLegalCC("MAGE",    "Demon"),     false, "demon mage no")
    end)
    it("undead: Priest only (Shackle)", function()
        eq(TankMark:IsLegalCC("PRIEST", "Undead"), true,  "undead priest")
        eq(TankMark:IsLegalCC("MAGE",   "Undead"), false, "undead mage no")
    end)
    it("dragonkin: Druid only (Hibernate)", function()
        eq(TankMark:IsLegalCC("DRUID", "Dragonkin"), true,  "dragon druid")
        eq(TankMark:IsLegalCC("MAGE",  "Dragonkin"), false, "dragon mage no")
    end)
    it("unknown bucket / nil creatureType -> false", function()
        eq(TankMark:IsLegalCC("MAGE", "Mechanical"), false, "no bucket")
        eq(TankMark:IsLegalCC("MAGE", nil),          false, "nil ct")
    end)
end)

describe("CCRaceEligible (narrow race gate)", function()
    it("non-Shaman classes eligible regardless of race", function()
        eq(TankMark:CCRaceEligible("MAGE",  "Gnome"),  true, "gnome mage")
        eq(TankMark:CCRaceEligible("DRUID", "Tauren"), true, "tauren druid")
        eq(TankMark:CCRaceEligible("ROGUE", "Orc"),    true, "orc rogue")
    end)
    it("Shaman eligible ONLY as Troll (Hex)", function()
        eq(TankMark:CCRaceEligible("SHAMAN", "Troll"),  true,  "troll shaman")
        eq(TankMark:CCRaceEligible("SHAMAN", "Tauren"), false, "tauren shaman")
        eq(TankMark:CCRaceEligible("SHAMAN", "Orc"),    false, "orc shaman")
    end)
end)

describe("SelectCCSlot two-pass resolver", function()
    it("authored + legal + present -> authored class mark (pass 1)", function()
        local slots = { slot{mark=5, class="MAGE"}, slot{mark=3, class="WARLOCK"} }
        eq(TankMark:SelectCCSlot("MAGE", "Humanoid", slots), 5, "mage authored")
    end)
    it("authored class ILLEGAL for creatureType -> legal fallback (mistag fix)", function()
        -- MAGE-tagged Elemental, Mage + Warlock present: route to Warlock, NOT Mage.
        local slots = { slot{mark=5, class="MAGE"}, slot{mark=3, class="WARLOCK"} }
        eq(TankMark:SelectCCSlot("MAGE", "Elemental", slots), 3, "warlock fallback")
    end)
    it("no legal slot present -> nil (falls through to normal path)", function()
        local slots = { slot{mark=5, class="MAGE"} }  -- Mage illegal for Elemental, no Warlock
        eq(TankMark:SelectCCSlot("MAGE", "Elemental", slots), nil, "no legal -> nil")
    end)
    it("authored absent -> first legal slot in profile order (pass 2)", function()
        local slots = { slot{mark=3, class="WARLOCK"}, slot{mark=5, class="MAGE"} }
        eq(TankMark:SelectCCSlot(nil, "Humanoid", slots), 3, "first legal = warlock")
        local rev = { slot{mark=5, class="MAGE"}, slot{mark=3, class="WARLOCK"} }
        eq(TankMark:SelectCCSlot(nil, "Humanoid", rev), 5, "first legal = mage")
    end)
    it("DISABLED mark is skipped in both passes (decision 11)", function()
        -- authored Mage disabled -> pass 1 skips it, pass 2 falls to Warlock.
        local slots = { slot{mark=5, class="MAGE", disabled=true}, slot{mark=3, class="WARLOCK"} }
        eq(TankMark:SelectCCSlot("MAGE", "Humanoid", slots), 3, "disabled mage skipped")
        -- only a disabled legal slot -> nil.
        local only = { slot{mark=5, class="MAGE", disabled=true} }
        eq(TankMark:SelectCCSlot("MAGE", "Humanoid", only), nil, "all disabled -> nil")
    end)
    it("USED and DEAD slots are excluded", function()
        local used = { slot{mark=5, class="MAGE", used=true}, slot{mark=3, class="WARLOCK"} }
        eq(TankMark:SelectCCSlot("MAGE", "Humanoid", used), 3, "used mage -> warlock")
        local dead = { slot{mark=5, class="MAGE", alive=false}, slot{mark=3, class="WARLOCK"} }
        eq(TankMark:SelectCCSlot("MAGE", "Humanoid", dead), 3, "dead mage -> warlock")
    end)
    it("no authored class + known creatureType -> first legal (decision 10)", function()
        local slots = { slot{mark=3, class="WARLOCK"} }
        eq(TankMark:SelectCCSlot(nil, "Elemental", slots), 3, "no class, ele -> warlock")
    end)
    it("unknown creatureType degrades to authored-class-only (decision 7)", function()
        local slots = { slot{mark=5, class="MAGE"}, slot{mark=3, class="WARLOCK"} }
        eq(TankMark:SelectCCSlot("MAGE", nil, slots), 5, "degrade: authored mage")
        -- degrade with authored class absent among slots -> nil.
        local noMage = { slot{mark=3, class="WARLOCK"} }
        eq(TankMark:SelectCCSlot("MAGE", nil, noMage), nil, "degrade: authored absent")
        -- no class AND no creatureType -> nil.
        eq(TankMark:SelectCCSlot(nil, nil, slots), nil, "no class, no ct -> nil")
    end)
    it("non-Troll Shaman CC slot is excluded by the race gate", function()
        local tauren = { slot{mark=5, class="SHAMAN", race="Tauren"} }
        eq(TankMark:SelectCCSlot("SHAMAN", "Humanoid", tauren), nil, "tauren shaman excluded")
        local troll = { slot{mark=5, class="SHAMAN", race="Troll"} }
        eq(TankMark:SelectCCSlot("SHAMAN", "Humanoid", troll), 5, "troll shaman ok")
    end)
end)

describe("IsCCSlotMark (Phase-4 rev: a CC-role mark never blocks skull)", function()
    -- A Team Profile is a list of { mark, role, tank }; only role=="CC" marks are
    -- CC slots. The governor's UpdateBest excludes these from skull-blocker
    -- selection -- aura or not -- so an auto-CC'd / authored CC mob can't suppress
    -- the pack's skull. Pure over the passed profile list.
    local profile = {
        { mark = 8, role = "TANK", tank = "MainTank" },
        { mark = 6, role = "CC",   tank = "Mage" },
        { mark = 4, role = "TANK", tank = "OffTank" },
    }
    it("true for a CC-role mark", function()
        eq(TankMark:IsCCSlotMark(6, profile), true, "square is the mage CC slot")
    end)
    it("false for a TANK-role (kill) mark", function()
        eq(TankMark:IsCCSlotMark(8, profile), false, "skull is a tank mark")
        eq(TankMark:IsCCSlotMark(4, profile), false, "triangle is a tank mark")
    end)
    it("false for a mark absent from the profile", function()
        eq(TankMark:IsCCSlotMark(2, profile), false, "no such slot")
    end)
    it("compares numerically (string mark in profile)", function()
        local strMark = { { mark = "6", role = "CC", tank = "Mage" } }
        eq(TankMark:IsCCSlotMark(6, strMark), true, "string mark tonumber'd")
    end)
    it("fail-safe: nil icon / nil list / unmigrated nil-role -> false", function()
        eq(TankMark:IsCCSlotMark(nil, profile), false, "nil icon")
        eq(TankMark:IsCCSlotMark(6, nil), false, "nil list")
        local unmigrated = { { mark = 6, tank = "Mage" } }  -- role nil
        eq(TankMark:IsCCSlotMark(6, unmigrated), false, "nil role fail-safe")
    end)
end)
