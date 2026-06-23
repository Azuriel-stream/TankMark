-- Runtime session state management (mark tracking, assignments, and constants)

if not TankMark then return end

local L = TankMark.Locals

-- ==========================================================
-- STATE VARIABLES
-- ==========================================================

-- Mark ownership indices (MarkMemory, usedIcons, activeGUIDs, activeMobNames)
-- are owned by the Mark Ledger -- see Core/TankMark_Ledger.lua.
TankMark.disabledMarks = {}
TankMark._skullReviewInProgress = false

-- Session assignments
TankMark.sessionAssignments = {}

-- Addon state
TankMark.IsActive = true
TankMark.MarkNormals = true
TankMark.DeathPattern = nil
TankMark.IsRecorderActive = false

-- [v0.21] Flight Recorder GUID tracking
TankMark.recordedGUIDs = {}

-- [v0.23] Sequential marking cursor
TankMark.sequentialMarkCursor = {}

-- [v0.24] Death alert tracking
TankMark.alertedDeaths = {}

-- ==========================================================
-- CONSTANTS
-- ==========================================================

TankMark.MarkInfo = {
    [8] = { name = "SKULL", color = "|cffffffff" },
    [7] = { name = "CROSS", color = "|cffff0000" },
    [6] = { name = "SQUARE", color = "|cff00ccff" },
    [5] = { name = "MOON", color = "|cffaabbcc" },
    [4] = { name = "TRIANGLE", color = "|cff00ff00" },
    [3] = { name = "DIAMOND", color = "|cffff00ff" },
    [2] = { name = "CIRCLE", color = "|cffffaa00" },
    [1] = { name = "STAR", color = "|cffffff00" },
}

-- [v0.28] Parked-CC aura IDs (roadmap #3, sheep-edge). A mark holder wearing one
-- of these incapacitate/sleep/banish/shackle debuffs is deliberately benched and
-- NOT being killed, so it must not count as a skull-blocker -- see IsMarkCCd
-- (Assignment.lua) and the UpdateBest early-out in GetBlockingMarkInfo. Authored
-- grouped-by-spell for maintainability; flattened into TankMark.CCAuraSet below
-- (the O(1) lookup IsMarkCCd actually reads).
--
-- Scope is intentional: only break-on-damage incapacitate + banish/shackle/sleep.
-- Fear/root/stun/snare/gouge are EXCLUDED -- those mobs are still being fought.
--
-- IDs are standard Vanilla 1.12 spell IDs. 118 confirmed in-game on Turtle via
-- `/tmark debug ccscan`; 3355/19386/18647/6358 confirmed against Classic Wowhead.
-- Turtle honors base-game IDs, so these should match; if a Turtle-custom CC is
-- missed in play, capture its aura id with `/tmark debug ccscan` and add it here.
-- Fail-safe: an unrecognized debuff just falls through to current behavior.
-- Freezing Trap uses the EFFECT aura ids (3355/14308/14309), NOT the trap-cast
-- ids -- IsMarkCCd reads the debuff the mob wears, not the spell that applied it.
local CC_SOURCE = {
    Polymorph     = { 118, 12824, 12825, 12826, 28272, 28271 }, -- ranks 1-4 + Pig/Turtle
    Sap           = { 6770, 2070, 11297 },
    ShackleUndead = { 9484, 9485, 10955 },
    Banish        = { 710, 18647 },
    Hibernate     = { 2637, 18657, 18658 },
    FreezingTrap  = { 3355, 14308, 14309 },                     -- effect auras, not trap-cast
    WyvernSting   = { 19386, 24132, 24133 },
    Seduction     = { 6358 },
}

TankMark.CCAuraSet = {}
for _, ids in L._pairs(CC_SOURCE) do
    for _, id in L._ipairs(ids) do
        TankMark.CCAuraSet[id] = true
    end
end
