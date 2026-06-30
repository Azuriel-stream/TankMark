-- Phase 4 (A): DecidePull -- the pre-fight pack brain.
--
-- Drives the pure DecidePull with a board exposing per-guid creatureType/tier, a
-- tank roster and CC slots, over Frostmane-style packs (DATA-MODEL fixtures).
-- Asserts the ratified behavior: CC the worthiest legal targets, ladder the kills
-- by prio, hand off overflow, exclude IGNORE/boss, honor authored type=="CC",
-- preserve sequential mobs, and route deterministically.

-- A CC slot record with sane defaults (alive, free, enabled).
local function slot(o)
    o = o or {}
    return {
        mark = o.mark, class = o.class, race = o.race or "Orc",
        alive = (o.alive ~= false), used = o.used or false, disabled = o.disabled or false,
    }
end

-- A pull candidate: guid, display name, mob-DB entry, mouseover sequence.
local function cand(guid, name, md, seq)
    return { guid = guid, name = name, mobData = md, sequence = seq }
end

-- Find the icon assigned to a guid in a plan (nil if unmarked).
local function iconFor(plan, guid)
    for _, it in ipairs(plan.intents) do
        if it.guid == guid then return it.icon end
    end
    return nil
end

describe("DecidePull CC pass (pack composition)", function()
    it("pack A: lone elite Warrior sheeped, trash skulled, rest overflow", function()
        local mob = function(role, prio) return { role = role, prio = prio, type = "KILL", marks = {8} } end
        local cands = {
            cand("g-war",  "Frostmane Warrior", mob("MELEE", 4), 1),
            cand("g-cre1", "Frostmane Cretin",  mob("MELEE", 5), 2),
            cand("g-cre2", "Frostmane Cretin",  mob("MELEE", 5), 3),
        }
        local board = make_board{
            creatureType = { ["g-war"]="Humanoid", ["g-cre1"]="Humanoid", ["g-cre2"]="Humanoid" },
            tier         = { ["g-war"]="elite",    ["g-cre1"]="normal",   ["g-cre2"]="normal" },
            ccSlots      = { slot{mark=6, class="MAGE"} },
            tankRoster   = { {mark=8, player="T", alive=true} },
        }
        local plan = TankMark:DecidePull(cands, board)
        eq(iconFor(plan, "g-war"),  6,   "warrior sheeped (durable elite > trash)")
        eq(iconFor(plan, "g-cre1"), 8,   "cretin1 skulled")
        eq(iconFor(plan, "g-cre2"), nil, "cretin2 unmarked")
        eq(TankMark.Locals._tgetn(plan.overflow), 1, "one overflow")
        eq(plan.overflow[1].guid, "g-cre2", "cretin2 is the overflow (deterministic)")
    end)

    it("pack B: healer Oracle sheeped (not skulled), a Warrior skulled, the other overflow", function()
        local cands = {
            cand("g-w1",  "Frostmane Warrior", { role="MELEE",  prio=4, type="KILL", marks={8} }, 1),
            cand("g-w2",  "Frostmane Warrior", { role="MELEE",  prio=4, type="KILL", marks={8} }, 2),
            cand("g-ora", "Frostmane Oracle",  { role="HEALER", prio=1, type="KILL", marks={8} }, 3),
        }
        local board = make_board{
            creatureType = { ["g-w1"]="Humanoid", ["g-w2"]="Humanoid", ["g-ora"]="Humanoid" },
            tier         = { ["g-w1"]="elite",    ["g-w2"]="elite",    ["g-ora"]="elite" },
            ccSlots      = { slot{mark=6, class="MAGE"} },
            tankRoster   = { {mark=8, player="T", alive=true} },
        }
        local plan = TankMark:DecidePull(cands, board)
        eq(iconFor(plan, "g-ora"), 6,   "oracle sheeped despite being top prio")
        eq(iconFor(plan, "g-w1"),  8,   "warrior1 skulled")
        eq(iconFor(plan, "g-w2"),  nil, "warrior2 overflow")
    end)

    it("legal-CC routing: caster->Mage, elemental->Warlock; Mage never on the elemental", function()
        local cands = {
            cand("g-snow", "Frostmane Snowcaller", { role="CASTER", prio=2, type="KILL", marks={8} }, 1),
            cand("g-ice",  "Ice Elemental",        { role="MELEE",  prio=4, type="KILL", marks={8} }, 2),
        }
        local board = make_board{
            creatureType = { ["g-snow"]="Humanoid", ["g-ice"]="Elemental" },
            tier         = { ["g-snow"]="elite",    ["g-ice"]="elite" },
            ccSlots      = { slot{mark=6, class="MAGE"}, slot{mark=3, class="WARLOCK"} },
            tankRoster   = { {mark=8, player="T", alive=true} },
        }
        local plan = TankMark:DecidePull(cands, board)
        eq(iconFor(plan, "g-snow"), 6, "snowcaller -> mage polymorph")
        eq(iconFor(plan, "g-ice"),  3, "ice elemental -> warlock banish (never mage)")
    end)

    it("boss is CC-immune: Kan'za never sheeped, a Snowcaller is", function()
        local cands = {
            cand("g-kan", "Kan'za the Seer",      { role="CASTER", prio=1, type="KILL", marks={8} }, 1),
            cand("g-s1",  "Frostmane Snowcaller",  { role="CASTER", prio=2, type="KILL", marks={8} }, 2),
            cand("g-s2",  "Frostmane Snowcaller",  { role="CASTER", prio=2, type="KILL", marks={8} }, 3),
        }
        local board = make_board{
            creatureType = { ["g-kan"]="Humanoid", ["g-s1"]="Humanoid", ["g-s2"]="Humanoid" },
            tier         = { ["g-kan"]="boss",     ["g-s1"]="elite",    ["g-s2"]="elite" },
            ccSlots      = { slot{mark=6, class="MAGE"} },
            tankRoster   = { {mark=8, player="T", alive=true}, {mark=7, player="T2", alive=true} },
        }
        local plan = TankMark:DecidePull(cands, board)
        eq(iconFor(plan, "g-kan"), 8, "kanza skulled, never sheeped")
        eq(iconFor(plan, "g-s1"),  6, "snowcaller1 sheeped")
        eq(iconFor(plan, "g-s2"),  7, "snowcaller2 on the next kill mark")
    end)
end)

describe("DecidePull precedence", function()
    it("IGNORE is excluded; authored type==CC outranks a worthier derived caster", function()
        local cands = {
            cand("g-ign",  "Garr",         { type="IGNORE", marks={0}, prio=9 }, 1),
            cand("g-cc",   "Tagged Melee", { role="MELEE",  prio=5, type="CC", class="MAGE", marks={6} }, 2),
            cand("g-cast", "Wild Caster",  { role="CASTER", prio=2, type="KILL", marks={8} }, 3),
        }
        local board = make_board{
            creatureType = { ["g-ign"]="Humanoid", ["g-cc"]="Humanoid", ["g-cast"]="Humanoid" },
            tier         = { ["g-ign"]="elite",    ["g-cc"]="elite",    ["g-cast"]="elite" },
            ccSlots      = { slot{mark=6, class="MAGE"} },
            tankRoster   = { {mark=8, player="T", alive=true} },
        }
        local plan = TankMark:DecidePull(cands, board)
        eq(iconFor(plan, "g-ign"),  nil, "garr ignored entirely")
        eq(iconFor(plan, "g-cc"),   6,   "tagged CC wins the mage slot")
        eq(iconFor(plan, "g-cast"), 8,   "worthier caster falls through to skull")
    end)

    it("authored prio overrides derived order in the kill ladder", function()
        local cands = {
            cand("g-a", "Mob A", { role="MELEE", prio=5, type="KILL", marks={8} }, 1),
            cand("g-b", "Mob B", { role="MELEE", prio=2, type="KILL", marks={8} }, 2),
        }
        local board = make_board{
            creatureType = { ["g-a"]="Humanoid", ["g-b"]="Humanoid" },
            tier         = { ["g-a"]="normal",   ["g-b"]="normal" },
            ccSlots      = {},
            tankRoster   = { {mark=8, player="T", alive=true}, {mark=7, player="T2", alive=true} },
        }
        local plan = TankMark:DecidePull(cands, board)
        eq(iconFor(plan, "g-b"), 8, "lower prio -> skull")
        eq(iconFor(plan, "g-a"), 7, "higher prio -> next mark")
    end)
end)

describe("DecidePull safety + determinism", function()
    it("sequential mob is skipped and its icons reserved", function()
        local cands = {
            cand("g-seq", "Seq Mob",  { role="MELEE", prio=3, type="KILL", marks={4,6} }, 1),
            cand("g-k",   "Kill Mob", { role="MELEE", prio=5, type="KILL", marks={8} },   2),
        }
        local board = make_board{
            creatureType = { ["g-seq"]="Humanoid", ["g-k"]="Humanoid" },
            tier         = { ["g-seq"]="elite",    ["g-k"]="elite" },
            ccSlots      = {},
            -- roster offers 4 then 8; 4 is reserved by the sequence -> kill mob takes 8.
            tankRoster   = { {mark=4, player="T", alive=true}, {mark=8, player="T2", alive=true} },
        }
        local plan = TankMark:DecidePull(cands, board)
        eq(iconFor(plan, "g-seq"), nil, "sequential mob untouched by DecidePull")
        eq(iconFor(plan, "g-k"),   8,   "kill mob skips reserved 4, takes 8")
    end)

    it("a worthy-but-unCCable healer is surfaced (unccd), not silently dropped", function()
        local cands = {
            cand("g-h", "Undead Healer", { role="HEALER", prio=1, type="KILL", marks={8} }, 1),
            cand("g-m", "Undead Melee",  { role="MELEE",  prio=5, type="KILL", marks={8} }, 2),
        }
        local board = make_board{
            creatureType = { ["g-h"]="Undead", ["g-m"]="Undead" },
            tier         = { ["g-h"]="elite",  ["g-m"]="elite" },
            ccSlots      = { slot{mark=6, class="MAGE"} },  -- Mage cannot CC Undead
            tankRoster   = { {mark=8, player="T", alive=true}, {mark=7, player="T2", alive=true} },
        }
        local plan = TankMark:DecidePull(cands, board)
        eq(iconFor(plan, "g-h"), 8, "healer falls to skull -- no legal CC")
        eq(TankMark.Locals._tgetn(plan.unccd), 1, "one worthy mob flagged")
        eq(plan.unccd[1].name, "Undead Healer", "the healer is surfaced")
    end)

    it("same pack twice on the SAME board -> identical intents (no fixture mutation)", function()
        local function build()
            return {
                cand("g-1", "Warrior", { role="MELEE",  prio=4, type="KILL", marks={8} }, 1),
                cand("g-2", "Oracle",  { role="HEALER", prio=1, type="KILL", marks={8} }, 2),
                cand("g-3", "Cretin",  { role="MELEE",  prio=5, type="KILL", marks={8} }, 3),
            }
        end
        local board = make_board{
            creatureType = { ["g-1"]="Humanoid", ["g-2"]="Humanoid", ["g-3"]="Humanoid" },
            tier         = { ["g-1"]="elite",    ["g-2"]="elite",    ["g-3"]="normal" },
            ccSlots      = { slot{mark=6, class="MAGE"} },
            tankRoster   = { {mark=8, player="T", alive=true}, {mark=7, player="T2", alive=true} },
        }
        local function ser(p)
            local parts = {}
            for _, it in ipairs(p.intents) do table.insert(parts, it.guid .. "=" .. tostring(it.icon)) end
            table.sort(parts)
            return table.concat(parts, ",")
        end
        local p1 = TankMark:DecidePull(build(), board)
        local p2 = TankMark:DecidePull(build(), board)
        eq(ser(p1), ser(p2), "identical intents across runs on one board")
    end)
end)
