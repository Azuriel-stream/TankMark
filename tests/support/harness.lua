-- TankMark off-client test harness (Lua 5.1).
--
-- The decision layer (roadmap #2 Tier 2) reads the world through an injected
-- "board", so testing it needs no WoW client and no mock of the full Locals
-- table -- only a mock board (see support/board.lua) plus the one pure-language
-- shim DecideKnownMark still uses: L._tgetn (= table.getn).
--
-- This file stubs that minimum, loads the system under test, and exposes a tiny
-- describe/it/eq runner. Entry point: tests/run.lua (run from the repo root).

-- ---- SUT environment -------------------------------------------------------
-- The SUT is zero-global except for a handful of pure *language* utilities it
-- reaches through L._ (not WoW state): table.getn for the decision layer, and
-- string/tonumber for the SyncCodec. Stubbing these to their stock Lua versions
-- is faithful -- in-game they are just WoW's aliases of the same functions.
-- Nothing here mocks game/Ledger/session state -- that is the board's job,
-- injected per test.
TankMark = TankMark or {}
TankMark.Locals = TankMark.Locals or {}
TankMark.Locals._tgetn    = TankMark.Locals._tgetn    or table.getn
TankMark.Locals._sub      = TankMark.Locals._sub      or string.sub
TankMark.Locals._strfind  = TankMark.Locals._strfind  or string.find
TankMark.Locals._tonumber = TankMark.Locals._tonumber or tonumber
TankMark.Locals._tinsert  = TankMark.Locals._tinsert  or table.insert
TankMark.Locals._tsort    = TankMark.Locals._tsort    or table.sort
TankMark.Locals._pairs    = TankMark.Locals._pairs    or pairs
TankMark.Locals._ipairs   = TankMark.Locals._ipairs   or ipairs
-- Vanilla's string.gfind is Lua 5.1's string.gmatch; the SyncCodec uses _gfind to
-- iterate the slice-4 profile-snapshot entries.
TankMark.Locals._gfind    = TankMark.Locals._gfind    or string.gmatch

-- ---- load the system under test --------------------------------------------
-- Both files are definition-only (no top-level execution), so they load cleanly
-- under the stub above. Assignment.lua is loaded for the REAL pure IncumbencyBlocks
-- that GovernorBlocks calls -- so a drift in its >= operator is actually caught.
local SUT = {
    "Core/TankMark_Assignment.lua",
    "Core/TankMark_Processor.lua",
    "Core/TankMark_Pull.lua",
    "Core/TankMark_SyncCodec.lua",
    "Core/TankMark_Trust.lua",
    "Core/TankMark_Swarm.lua",
}
for _, path in ipairs(SUT) do
    local fh = io.open(path, "r")
    if not fh then
        error("cannot find '" .. path .. "'. Run from the repo root: lua5.1 tests/run.lua")
    end
    fh:close()
    dofile(path)
end

-- ---- tiny test runner ------------------------------------------------------
local results = { pass = 0, fail = 0, failures = {} }
_G.TM_TEST_RESULTS = results

local group = ""

function describe(name, fn)
    local prev = group
    group = (prev == "") and name or (prev .. " / " .. name)
    fn()
    group = prev
end

function it(name, fn)
    local label = (group == "") and name or (group .. " > " .. name)
    local ok, err = pcall(fn)
    if ok then
        results.pass = results.pass + 1
    else
        results.fail = results.fail + 1
        table.insert(results.failures, label .. "\n      " .. tostring(err))
    end
end

-- Assertion: raises on mismatch (caught by `it`). `label` aids the report.
function eq(got, want, label)
    if got ~= want then
        error(string.format("%s: got=%s want=%s", label or "eq", tostring(got), tostring(want)), 2)
    end
end

-- Convenience: assert a decided intent's icon and (optionally) reason at once.
function eq_intent(intent, icon, reason, label)
    label = label or "intent"
    eq(intent.icon, icon, label .. ".icon")
    if reason ~= nil then eq(intent.reason, reason, label .. ".reason") end
end

-- Convenience: assert a skull-succession intent's action and (optionally) reason.
-- The death-path DecideSkullSuccessor tags outcomes by `action` (none/adopt/assign),
-- not `icon` (which is always skull), so it needs its own assertion.
function eq_skull(intent, action, reason, label)
    label = label or "skull-intent"
    eq(intent.action, action, label .. ".action")
    if reason ~= nil then eq(intent.reason, reason, label .. ".reason") end
end
