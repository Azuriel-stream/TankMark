-- TankMark: v0.23
-- File: TankMark_Config_Mobs.lua
-- Mob Database configuration UI with sequential marking support

if not TankMark then return end

-- ==========================================================
-- LOCALIZATIONS
-- ==========================================================

local _pairs = pairs
local _ipairs = ipairs
local _insert = table.insert
local _remove = table.remove
local _sort = table.sort
local _getn = table.getn
local _lower = string.lower
local _strfind = string.find
local _gsub = string.gsub

-- ==========================================================
-- STATE
-- ==========================================================

TankMark.mobRows = {}
TankMark.selectedIcon = 8
TankMark.selectedClass = nil
TankMark.isZoneListMode = false
TankMark.lockViewZone = nil
TankMark.editingLockGUID = nil
TankMark.detectedCreatureType = nil
TankMark.isLockActive = false

-- [v0.23] Sequential marking state
TankMark.editingSequentialMarks = {}  -- Array of {icon, class, type}
TankMark.sequentialRows = {}  -- UI frame pool (max 7 additional marks)
TankMark.isAddMobExpanded = false  -- Accordion state

-- ==========================================================
-- UI REFERENCES
-- ==========================================================

TankMark.scrollFrame = nil
TankMark.searchBox = nil
TankMark.zoneDropDown = nil
TankMark.zoneModeCheck = nil
TankMark.editMob = nil
TankMark.editPrio = nil
TankMark.saveBtn = nil
TankMark.cancelBtn = nil
TankMark.lockBtn = nil
TankMark.classBtn = nil
TankMark.iconBtn = nil
TankMark.addMobHeader = nil
TankMark.addMobInterface = nil
TankMark.sequentialScrollFrame = nil
TankMark.addMoreMarksText = nil