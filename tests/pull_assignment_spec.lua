-- Phase 4: DecidePull -- the pre-fight pack brain.
--
-- [v0.30 CC-model rev / ADR 0002] KILL-FIRST + prio-ordered: prio is the kill
-- order; the tank ladder claims the lowest-prio mobs (skull to kill-first), then
-- CC claims the eligible LEFTOVERS taking the kill-LAST (highest prio) first.
-- Worthiness gates candidacy ONLY (the floor); type=="CC" forces candidacy for a
-- below-floor mob. Reserve-a-kill-target is automatic (the ladder always claims a
-- kill before CC). Determinism via prio then mouseover sequence.

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

describe("DecidePull -- the flip (prio drives CC-vs-kill)", function()
    it("a low-prio HEALER is skulled; the higher-prio CASTER is CC'd", function()
        local cands = {
            cand("g-heal", "Oracle",     { role="HEALER", prio=1, type="KILL", marks={8} }, 1),
            cand("g-cast", "Snowcaller", { role="CASTER", prio=3, type="KILL", marks={8} }, 2),
            cand("g-mel",  "Warrior",    { role="MELEE",  prio=4, type="KILL", marks={8} }, 3),
        }
        local board = make_board{
            creatureType = { ["g-heal"]="Humanoid", ["g-cast"]="Humanoid", ["g-mel"]="Humanoid" },
            tier         = { ["g-heal"]="elite",    ["g-cast"]="elite",    ["g-mel"]="elite" },
            ccSlots      = { slot{mark=6, class="MAGE"} },
            tankRoster   = { {mark=8, player="T", alive=true} },
        }
        local plan = TankMark:DecidePull(cands, board)
        eq(iconFor(plan, "g-heal"), 8,   "healer skulled (prio 1 = kill first)")
        eq(iconFor(plan, "g-cast"), 6,   "caster CC'd (kill-last eligible)")
        eq(iconFor(plan, "g-mel"),  nil, "melee overflow (below floor, not type=CC)")
    end)

    it("type=CC forces a below-floor melee (kill-last) into CC; a cretin is skulled", function()
        local cands = {
            cand("g-war",  "Durable Warrior", { role="MELEE", prio=6, type="CC", class="MAGE", marks={6} }, 1),
            cand("g-cre1", "Cretin",          { role="MELEE", prio=5, type="KILL", marks={8} }, 2),
            cand("g-cre2", "Cretin",          { role="MELEE", prio=5, type="KILL", marks={8} }, 3),
        }
        local board = make_board{
            creatureType = { ["g-war"]="Humanoid", ["g-cre1"]="Humanoid", ["g-cre2"]="Humanoid" },
            tier         = { ["g-war"]="elite",    ["g-cre1"]="normal",   ["g-cre2"]="normal" },
            ccSlots      = { slot{mark=6, class="MAGE"} },
            tankRoster   = { {mark=8, player="T", alive=true} },
        }
        local plan = TankMark:DecidePull(cands, board)
        eq(iconFor(plan, "g-war"),  6,   "warrior sheeped (type=CC, prio 6 = kill-last)")
        eq(iconFor(plan, "g-cre1"), 8,   "cretin1 skulled (lowest prio)")
        eq(iconFor(plan, "g-cre2"), nil, "cretin2 overflow")
    end)
end)

describe("DecidePull CC pass (legality, tier, floor)", function()
    it("legal-CC routing: Snowcaller->Mage, Ice Elemental->Warlock; Mage never on the elemental", function()
        local cands = {
            cand("g-kill", "Trash",         { role="MELEE",  prio=2, type="KILL", marks={8} }, 1),
            cand("g-snow", "Snowcaller",    { role="CASTER", prio=5, type="CC", class="MAGE",    marks={6} }, 2),
            cand("g-ice",  "Ice Elemental", { role="CASTER", prio=6, type="CC", class="WARLOCK", marks={3} }, 3),
        }
        local board = make_board{
            creatureType = { ["g-kill"]="Humanoid", ["g-snow"]="Humanoid", ["g-ice"]="Elemental" },
            tier         = { ["g-kill"]="elite",    ["g-snow"]="elite",    ["g-ice"]="elite" },
            ccSlots      = { slot{mark=6, class="MAGE"}, slot{mark=3, class="WARLOCK"} },
            tankRoster   = { {mark=8, player="T", alive=true} },
        }
        local plan = TankMark:DecidePull(cands, board)
        eq(iconFor(plan, "g-kill"), 8, "trash skulled (kill first)")
        eq(iconFor(plan, "g-snow"), 6, "snowcaller -> mage polymorph")
        eq(iconFor(plan, "g-ice"),  3, "ice elemental -> warlock banish (never mage)")
    end)

    it("boss is CC-immune even when authored type=CC + kill-last: overflow, not sheeped", function()
        local cands = {
            cand("g-kan",  "Kan'za",     { role="CASTER", prio=6, type="CC", class="MAGE", marks={6} }, 1),
            cand("g-snow", "Snowcaller", { role="CASTER", prio=5, type="CC", class="MAGE", marks={6} }, 2),
            cand("g-mel",  "Trash",      { role="MELEE",  prio=2, type="KILL", marks={8} }, 3),
        }
        local board = make_board{
            creatureType = { ["g-kan"]="Humanoid", ["g-snow"]="Humanoid", ["g-mel"]="Humanoid" },
            tier         = { ["g-kan"]="boss",     ["g-snow"]="elite",    ["g-mel"]="elite" },
            ccSlots      = { slot{mark=6, class="MAGE"} },
            tankRoster   = { {mark=8, player="T", alive=true} },
        }
        local plan = TankMark:DecidePull(cands, board)
        eq(iconFor(plan, "g-mel"),  8,   "trash skulled (kill first)")
        eq(iconFor(plan, "g-snow"), 6,   "elite snowcaller CC'd")
        eq(iconFor(plan, "g-kan"),  nil, "boss overflow: CC-immune despite type=CC + kill-last")
    end)

    it("floor-gated candidacy: a spare CC slot does NOT sheep a below-floor trash melee", function()
        local cands = {
            cand("g-k",  "Kill",  { role="MELEE", prio=2, type="KILL", marks={8} }, 1),
            cand("g-tr", "Trash", { role="MELEE", prio=6, type="KILL", marks={8} }, 2),
        }
        local board = make_board{
            creatureType = { ["g-k"]="Humanoid", ["g-tr"]="Humanoid" },
            tier         = { ["g-k"]="normal",   ["g-tr"]="normal" },
            ccSlots      = { slot{mark=6, class="MAGE"} },  -- a spare slot IS available
            tankRoster   = { {mark=8, player="T", alive=true} },
        }
        local plan = TankMark:DecidePull(cands, board)
        eq(iconFor(plan, "g-k"),  8,   "kill skulled")
        eq(iconFor(plan, "g-tr"), nil, "trash NOT sheeped (below floor, not type=CC) -> overflow")
        eq(TankMark.Locals._tgetn(plan.overflow), 1, "trash is overflow, not a CC pick")
    end)
end)

describe("DecidePull precedence + kill ladder", function()
    it("IGNORE gets no mark; a low-prio caster is skulled while a kill-last type=CC mob is sheeped", function()
        local cands = {
            cand("g-ign",  "Garr",         { type="IGNORE", marks={0}, prio=9 }, 1),
            cand("g-cast", "Wild Caster",  { role="CASTER", prio=2, type="KILL", marks={8} }, 2),
            cand("g-cc",   "Tagged Melee", { role="MELEE",  prio=6, type="CC", class="MAGE", marks={6} }, 3),
        }
        local board = make_board{
            creatureType = { ["g-ign"]="Humanoid", ["g-cast"]="Humanoid", ["g-cc"]="Humanoid" },
            tier         = { ["g-ign"]="elite",    ["g-cast"]="elite",    ["g-cc"]="elite" },
            ccSlots      = { slot{mark=6, class="MAGE"} },
            tankRoster   = { {mark=8, player="T", alive=true} },
        }
        local plan = TankMark:DecidePull(cands, board)
        eq(iconFor(plan, "g-ign"),  nil, "garr ignored entirely")
        eq(iconFor(plan, "g-cast"), 8,   "caster skulled (prio 2 = kill first)")
        eq(iconFor(plan, "g-cc"),   6,   "tagged melee sheeped (type=CC, prio 6 = kill-last)")
    end)

    it("kill ladder descends by prio across multiple tank marks", function()
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

describe("DecidePull reserve + safety + determinism", function()
    it("reserve is automatic: a lone worthy mob is killed (skull), never sheeped", function()
        local cands = { cand("g-lone", "Lone Healer", { role="HEALER", prio=1, type="KILL", marks={8} }, 1) }
        local board = make_board{
            creatureType = { ["g-lone"]="Humanoid" },
            tier         = { ["g-lone"]="elite" },
            ccSlots      = { slot{mark=6, class="MAGE"} },  -- a slot is free, but it's the last killable mob
            tankRoster   = { {mark=8, player="T", alive=true} },
        }
        local plan = TankMark:DecidePull(cands, board)
        eq(iconFor(plan, "g-lone"), 8, "lone worthy mob skulled (kill ladder claims it first)")
    end)

    it("reserve: a lone type=CC mob is also killed (the batch does the pack reasoning)", function()
        local cands = { cand("g-cc", "Lone CC Mob", { role="MELEE", prio=1, type="CC", class="MAGE", marks={6} }, 1) }
        local board = make_board{
            creatureType = { ["g-cc"]="Humanoid" },
            tier         = { ["g-cc"]="elite" },
            ccSlots      = { slot{mark=6, class="MAGE"} },
            tankRoster   = { {mark=8, player="T", alive=true} },
        }
        local plan = TankMark:DecidePull(cands, board)
        eq(iconFor(plan, "g-cc"), 8, "lone type=CC mob killed (reserve, kill-first)")
    end)

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

    it("a worthy-but-unCCable mob (kill-last, no legal slot) is surfaced (unccd), not dropped", function()
        local cands = {
            cand("g-kill", "Trash",         { role="MELEE",  prio=2, type="KILL", marks={8} }, 1),
            cand("g-h",    "Undead Healer", { role="HEALER", prio=6, type="KILL", marks={8} }, 2),
        }
        local board = make_board{
            creatureType = { ["g-kill"]="Humanoid", ["g-h"]="Undead" },
            tier         = { ["g-kill"]="elite",    ["g-h"]="elite" },
            ccSlots      = { slot{mark=6, class="MAGE"} },  -- Mage cannot CC Undead
            tankRoster   = { {mark=8, player="T", alive=true} },
        }
        local plan = TankMark:DecidePull(cands, board)
        eq(iconFor(plan, "g-kill"), 8,   "trash skulled")
        eq(iconFor(plan, "g-h"),    nil, "healer unmarked -- no legal CC slot")
        eq(TankMark.Locals._tgetn(plan.unccd), 1, "one worthy mob flagged")
        eq(plan.unccd[1].name, "Undead Healer", "the healer is surfaced")
    end)

    -- [v0.32] slice C re-sweep: reservedIcons seeds usedMarks so an icon a mob
    -- ALREADY physically wears (read live at collect time on Ascension, where the
    -- two-sweep is no-Ledger and the board's busy-seed is blind to it) is not
    -- handed to another mob -- else applying it would STEAL the mark (marks are
    -- unique). nil/absent -> byte-identical to the 2-arg call (Vanilla).
    it("reservedIcons keeps skull off a kill mob: it takes the next ladder rung", function()
        local cands = { cand("g-new", "New Add", { role="MELEE", prio=2, type="KILL", marks={8} }, 1) }
        local board = make_board{
            creatureType = { ["g-new"]="Humanoid" },
            tier         = { ["g-new"]="elite" },
            ccSlots      = {},
            -- ladder offers skull then cross; skull is reserved (an existing mob
            -- physically wears it) -> the new add must take cross, not steal skull.
            tankRoster   = { {mark=8, player="T", alive=true}, {mark=7, player="T2", alive=true} },
        }
        local plan = TankMark:DecidePull(cands, board, { [8] = true })
        eq(iconFor(plan, "g-new"), 7, "reserved skull skipped -> next rung (cross)")
    end)

    it("reservedIcons taking the only rung -> overflow, mark not stolen", function()
        local cands = { cand("g-new", "New Add", { role="MELEE", prio=2, type="KILL", marks={8} }, 1) }
        local board = make_board{
            creatureType = { ["g-new"]="Humanoid" },
            tier         = { ["g-new"]="elite" },
            ccSlots      = {},
            tankRoster   = { {mark=8, player="T", alive=true} },  -- only skull, and it's reserved
        }
        local plan = TankMark:DecidePull(cands, board, { [8] = true })
        eq(iconFor(plan, "g-new"), nil, "no free rung -> overflow (existing skull retained)")
        eq(TankMark.Locals._tgetn(plan.overflow), 1, "new add surfaced as overflow")
    end)

    it("nil reservedIcons is byte-identical to the 2-arg call", function()
        local cands = { cand("g-a", "A", { role="MELEE", prio=2, type="KILL", marks={8} }, 1) }
        local board = make_board{
            creatureType = { ["g-a"]="Humanoid" }, tier = { ["g-a"]="elite" },
            ccSlots = {}, tankRoster = { {mark=8, player="T", alive=true} },
        }
        eq(iconFor(TankMark:DecidePull(cands, board), "g-a"), 8, "2-arg: skull as before")
        eq(iconFor(TankMark:DecidePull(cands, board, nil), "g-a"), 8, "explicit nil: identical")
    end)

    it("same pack twice on the SAME board -> identical intents (no fixture mutation)", function()
        local function build()
            return {
                cand("g-1", "Healer",  { role="HEALER", prio=1, type="KILL", marks={8} }, 1),
                cand("g-2", "Caster",  { role="CASTER", prio=5, type="KILL", marks={8} }, 2),
                cand("g-3", "Caster2", { role="CASTER", prio=6, type="KILL", marks={8} }, 3),
            }
        end
        local board = make_board{
            creatureType = { ["g-1"]="Humanoid", ["g-2"]="Humanoid", ["g-3"]="Humanoid" },
            tier         = { ["g-1"]="elite",    ["g-2"]="elite",    ["g-3"]="elite" },
            ccSlots      = { slot{mark=6, class="MAGE"} },
            tankRoster   = { {mark=8, player="T", alive=true} },
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
