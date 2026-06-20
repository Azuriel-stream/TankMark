-- TankMark: v0.23
-- File: TankMark_Config_Mobs.lua
-- State registry for Mobs configuration tab

if not TankMark then return end

-- ==========================================================
-- STATE VARIABLES
-- ==========================================================
TankMark.mobRows = {}
TankMark.selectedIcon = 8
TankMark.selectedClass = nil
TankMark.isZoneListMode = false
TankMark.detectedCreatureType = nil
TankMark.editingSequentialMarks = {}
TankMark.sequentialRows = {}
TankMark.isAddMobExpanded = false       -- LEFT accordion state
TankMark.isSequentialExpanded = false   -- RIGHT accordion expand/collapse state
TankMark.isSequentialActive = false     -- RIGHT accordion enabled/disabled state

-- ==========================================================
-- UI WIDGET REFERENCES
-- ==========================================================
TankMark.scrollFrame = nil
TankMark.searchBox = nil
TankMark.zoneDropDown = nil
TankMark.zoneModeCheck = nil
TankMark.editMob = nil
TankMark.editPrio = nil
TankMark.saveBtn = nil
TankMark.cancelBtn = nil
TankMark.classBtn = nil
TankMark.iconBtn = nil
TankMark.addMobHeader = nil
TankMark.addMobInterface = nil
TankMark.sequentialScrollFrame = nil
TankMark.sequentialInterface = nil
TankMark.addMoreMarksText = nil
TankMark.addMoreMarksHeader = nil
TankMark.addMoreMarksHeader = nil
TankMark.sequentialEmptyText = nil
