-- Phase 3 role x tier -> default kill priority: the pure derivation.
--
-- Covers TankMark:RoleTierPrio(role, tier) added to Core/TankMark_Assignment.lua
-- -- the total, pure lookup behind the editor's authoring-time prio pre-fill.
-- "Total" means it returns a number for ANY input: nil/unknown role degrades to
-- the MELEE row, nil/unknown tier degrades to the `normal` column. The UI wrapper
-- ApplyRoleDefaults (and a future Phase-4 runtime read) is the only caller; the
-- table itself is asserted here. No board, no WoW client.
--
-- The curve (DATA-MODEL.md S5 -- defaults, not law):
--   role \ tier   normal  elite  rare/rareelite  worldboss/boss
--   HEALER          2       1          1               1
--   CASTER          3       2          2               1
--   MELEE / nil     5       4          3               1

describe("RoleTierPrio (role x tier -> default prio)", function()
    it("HEALER curve across tiers (healers die first)", function()
        eq(TankMark:RoleTierPrio("HEALER", "normal"),    2, "healer normal")
        eq(TankMark:RoleTierPrio("HEALER", "elite"),     1, "healer elite")
        eq(TankMark:RoleTierPrio("HEALER", "rare"),      1, "healer rare")
        eq(TankMark:RoleTierPrio("HEALER", "rareelite"), 1, "healer rareelite")
        eq(TankMark:RoleTierPrio("HEALER", "worldboss"), 1, "healer worldboss")
    end)

    it("CASTER curve across tiers", function()
        eq(TankMark:RoleTierPrio("CASTER", "normal"),    3, "caster normal")
        eq(TankMark:RoleTierPrio("CASTER", "elite"),     2, "caster elite")
        eq(TankMark:RoleTierPrio("CASTER", "rare"),      2, "caster rare")
        eq(TankMark:RoleTierPrio("CASTER", "rareelite"), 2, "caster rareelite")
        eq(TankMark:RoleTierPrio("CASTER", "worldboss"), 1, "caster worldboss")
    end)

    it("MELEE curve across tiers (background trash)", function()
        eq(TankMark:RoleTierPrio("MELEE", "normal"),    5, "melee normal")
        eq(TankMark:RoleTierPrio("MELEE", "elite"),     4, "melee elite")
        eq(TankMark:RoleTierPrio("MELEE", "rare"),      3, "melee rare")
        eq(TankMark:RoleTierPrio("MELEE", "rareelite"), 3, "melee rareelite")
        eq(TankMark:RoleTierPrio("MELEE", "worldboss"), 1, "melee worldboss")
    end)

    it("nil role degrades to the MELEE row", function()
        eq(TankMark:RoleTierPrio(nil, "normal"), 5, "nil-role normal")
        eq(TankMark:RoleTierPrio(nil, "elite"),  4, "nil-role elite")
        eq(TankMark:RoleTierPrio(nil, "rare"),   3, "nil-role rare")
    end)

    it("unknown role degrades to the MELEE row", function()
        eq(TankMark:RoleTierPrio("BANANA", "normal"), 5, "unknown-role normal")
        eq(TankMark:RoleTierPrio("BANANA", "elite"),  4, "unknown-role elite")
    end)

    it("nil tier degrades to the `normal` column", function()
        eq(TankMark:RoleTierPrio("HEALER", nil), 2, "healer nil-tier")
        eq(TankMark:RoleTierPrio("CASTER", nil), 3, "caster nil-tier")
        eq(TankMark:RoleTierPrio("MELEE",  nil), 5, "melee nil-tier")
    end)

    it("unknown tier degrades to the `normal` column", function()
        eq(TankMark:RoleTierPrio("HEALER", "mechanical"), 2, "healer junk-tier")
        eq(TankMark:RoleTierPrio("MELEE",  ""),           5, "melee empty-tier")
    end)

    it("both nil -> MELEE row, normal column", function()
        eq(TankMark:RoleTierPrio(nil, nil), 5, "nil/nil")
    end)
end)
