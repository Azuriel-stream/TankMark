-- TankMark: v0.26
-- File: Core/TankMark_Session.lua
-- Module Version: 1.0
-- Last Updated: 2026-02-08
-- Runtime session state management (mark tracking, assignments, and constants)

if not TankMark then return end

-- ==========================================================
-- STATE VARIABLES
-- ==========================================================

-- Mark usage tracking
TankMark.usedIcons = {}
TankMark.activeMobNames = {}
TankMark.activeGUIDs = {}
TankMark.activeMobIsCaster = {}
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
