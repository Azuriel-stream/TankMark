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
TankMark.lockViewZone = nil
TankMark.editingLockGUID = nil
TankMark.detectedCreatureType = nil
TankMark.isLockActive = false
TankMark.editingSequentialMarks = {}
TankMark.sequentialRows = {}
TankMark.isAddMobExpanded = false

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
TankMark.lockBtn = nil
TankMark.classBtn = nil
TankMark.iconBtn = nil
TankMark.addMobHeader = nil
TankMark.addMobInterface = nil
TankMark.sequentialScrollFrame = nil
TankMark.addMoreMarksText = nil