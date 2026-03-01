-- TankMark: v0.27
-- File: TankMark_Config_Profiles.lua
-- State registry and data constants for Team Profiles tab

if not TankMark then return end

-- ==========================================================
-- STATE VARIABLES
-- ==========================================================

TankMark.profileRows = {}
TankMark.profileScroll = nil
TankMark.profileZoneDropdown = nil
TankMark.profileCache = {}
TankMark.profileAddBtn = nil

-- ==========================================================
-- PROFILE TEMPLATES
-- ==========================================================

TankMarkProfileTemplates = {
	["Standard 8-Tank"] = {
		{mark = 8, tank = "", healers = ""},
		{mark = 7, tank = "", healers = ""},
		{mark = 6, tank = "", healers = ""},
		{mark = 5, tank = "", healers = ""},
		{mark = 4, tank = "", healers = ""},
		{mark = 3, tank = "", healers = ""},
		{mark = 2, tank = "", healers = ""},
		{mark = 1, tank = ""}
	},
	["Priority 5-Tank"] = {
		{mark = 8, tank = "", healers = ""},
		{mark = 7, tank = "", healers = ""},
		{mark = 6, tank = "", healers = ""},
		{mark = 4, tank = "", healers = ""},
		{mark = 3, tank = "", healers = ""}
	},
	["Minimal 3-Tank"] = {
		{mark = 8, tank = "", healers = ""},
		{mark = 7, tank = "", healers = ""},
		{mark = 6, tank = "", healers = ""}
	},
	["CC Heavy (4 Tank + 4 CC)"] = {
		{mark = 8, tank = "", healers = ""},
		{mark = 7, tank = "", healers = ""},
		{mark = 6, tank = "", healers = ""},
		{mark = 4, tank = "", healers = ""},
		{mark = 5, tank = "", healers = ""},
		{mark = 3, tank = "", healers = ""},
		{mark = 2, tank = "", healers = ""},
		{mark = 1, tank = "", healers = ""}
	}
}