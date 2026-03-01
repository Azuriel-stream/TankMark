-- TankMark: v0.23
-- File: TankMark_Config_Mobs_Menus.lua
-- Dropdown menu initialization functions

if not TankMark then return end

-- ==========================================================
-- LOCALIZATIONS
-- ==========================================================

-- Import shared localizations
local L = TankMark.Locals

-- ==========================================================
-- LOGIC CONSTANTS (duplicated from main file for menu logic)
-- ==========================================================
local CLASS_DEFAULTS = {
	["MAGE"]    = { icon = 5, prio = 3 },
	["WARLOCK"] = { icon = 3, prio = 3 },
	["DRUID"]   = { icon = 4, prio = 3 },
	["ROGUE"]   = { icon = 1, prio = 3 },
	["PRIEST"]  = { icon = 6, prio = 3 },
	["HUNTER"]  = { icon = 2, prio = 3 },
	["KILL"]    = { icon = 8, prio = 1 },
	["IGNORE"]  = { icon = 0, prio = 9 }
}

local CC_MAP = {
	["Humanoid"]   = { "MAGE", "ROGUE", "WARLOCK", "PRIEST" },
	["Beast"]      = { "MAGE", "DRUID", "HUNTER" },
	["Elemental"]  = { "WARLOCK" },
	["Demon"]      = { "WARLOCK" },
	["Undead"]     = { "PRIEST" },
	["Dragonkin"]  = { "DRUID" }
}

local ALL_CLASSES = { "MAGE", "WARLOCK", "DRUID", "ROGUE", "PRIEST", "HUNTER", "WARRIOR", "SHAMAN", "PALADIN" }

-- ==========================================================
-- MAIN MOB ICON MENU
-- ==========================================================
-- Initialize icon dropdown menu for main mob row
function TankMark:InitIconMenu()
	local iconNames = {
		[8] = "|cffffffffSkull|r",
		[7] = "|cffff0000Cross|r",
		[6] = "|cff00ccffSquare|r",
		[5] = "|cffaabbccMoon|r",
		[4] = "|cff00ff00Triangle|r",
		[3] = "|cffff00ffDiamond|r",
		[2] = "|cffffaa00Circle|r",
		[1] = "|cffffff00Star|r"
	}

	-- [v0.23] IGNORE option only for single-mark mobs
	if L._tgetn(TankMark.editingSequentialMarks) == 0 then
		iconNames[0] = "|cff888888Disabled (Ignore)|r"
	end

	for i = 8, 0, -1 do
		if iconNames[i] then -- Skip 0 if sequential marks exist
			local capturedIcon = i
			local info = {}
			info.text = iconNames[i]
			info.func = function()
				TankMark.selectedIcon = capturedIcon
				if TankMark.iconBtn and TankMark.iconBtn.tex then
					TankMark:SetIconTexture(TankMark.iconBtn.tex, TankMark.selectedIcon)
					TankMark:UpdateClassButton()
				end
				-- [v0.23] If IGNORE selected, set prio = 9
				if capturedIcon == 0 and TankMark.editPrio then
					TankMark.editPrio:SetText("9")
				end
				CloseDropDownMenus()
			end
			info.checked = (TankMark.selectedIcon == i)
			UIDropDownMenu_AddButton(info)
		end
	end
end

-- ==========================================================
-- MAIN MOB CLASS MENU
-- ==========================================================
-- Initialize CC class dropdown menu for main mob row
function TankMark:InitClassMenu()
	local info = {}

	-- [v0.23] IGNORE option REMOVED - use Icon dropdown to set IGNORE instead
	-- IGNORE only appears in Icon menu when no sequential marks exist
	info = {
		text = "|cffffffffNo CC (Kill Target)|r",
		func = function()
			TankMark.selectedClass = nil
			TankMark:UpdateClassButton()
			TankMark:ApplySmartDefaults("KILL")
		end
	}
	UIDropDownMenu_AddButton(info)

	if TankMark.detectedCreatureType and CC_MAP[TankMark.detectedCreatureType] then
		info = { text = "--- Recommended ---", isTitle = 1 }
		UIDropDownMenu_AddButton(info)

		for _, class in L._ipairs(CC_MAP[TankMark.detectedCreatureType]) do
			local capturedClass = class
			info = {
				text = "|cff00ff00" .. capturedClass .. "|r",
				func = function()
					TankMark.selectedClass = capturedClass
					TankMark:UpdateClassButton()
					TankMark:ApplySmartDefaults(capturedClass)
				end
			}
			UIDropDownMenu_AddButton(info)
		end
	end

	info = { text = "--- All Classes ---", isTitle = 1 }
	UIDropDownMenu_AddButton(info)

	for _, class in L._ipairs(ALL_CLASSES) do
		local capturedClass = class
		info = {
			text = capturedClass,
			func = function()
				TankMark.selectedClass = capturedClass
				TankMark:UpdateClassButton()
				TankMark:ApplySmartDefaults(capturedClass)
			end
		}
		UIDropDownMenu_AddButton(info)
	end
end

-- ==========================================================
-- SEQUENTIAL ROW CLASS MENU
-- ==========================================================
-- Initialize CC class menu for a sequential row
function TankMark:InitSequentialClassMenu(seqIndex)
	local capturedSeqIndex = seqIndex
	local info = {}

	-- No IGNORE option for sequential rows
	info = {
		text = "|cffffffffNo CC (Kill Target)|r",
		func = function()
			if TankMark.editingSequentialMarks[capturedSeqIndex] then
				TankMark.editingSequentialMarks[capturedSeqIndex].class = nil
				TankMark.editingSequentialMarks[capturedSeqIndex].type = "KILL"
				TankMark:RefreshSequentialRows()
			end
		end
	}
	UIDropDownMenu_AddButton(info)

	if TankMark.detectedCreatureType and CC_MAP[TankMark.detectedCreatureType] then
		info = { text = "--- Recommended ---", isTitle = 1 }
		UIDropDownMenu_AddButton(info)

		for _, class in L._ipairs(CC_MAP[TankMark.detectedCreatureType]) do
			local capturedClass = class
			info = {
				text = "|cff00ff00" .. capturedClass .. "|r",
				func = function()
					if TankMark.editingSequentialMarks[capturedSeqIndex] then
						TankMark.editingSequentialMarks[capturedSeqIndex].class = capturedClass
						TankMark.editingSequentialMarks[capturedSeqIndex].type = "CC"
						TankMark:RefreshSequentialRows()
					end
				end
			}
			UIDropDownMenu_AddButton(info)
		end
	end

	info = { text = "--- All Classes ---", isTitle = 1 }
	UIDropDownMenu_AddButton(info)

	for _, class in L._ipairs(ALL_CLASSES) do
		local capturedClass = class
		info = {
			text = capturedClass,
			func = function()
				if TankMark.editingSequentialMarks[capturedSeqIndex] then
					TankMark.editingSequentialMarks[capturedSeqIndex].class = capturedClass
					TankMark.editingSequentialMarks[capturedSeqIndex].type = "CC"
					TankMark:RefreshSequentialRows()
				end
			end
		}
		UIDropDownMenu_AddButton(info)
	end
end

-- ==========================================================
-- SEQUENTIAL ROW ICON MENU
-- ==========================================================
-- Initialize icon menu for a sequential row
function TankMark:InitSequentialIconMenu(seqIndex)
	local capturedSeqIndex = seqIndex
	local iconNames = {
		[8] = "|cffffffffSkull|r",
		[7] = "|cffff0000Cross|r",
		[6] = "|cff00ccffSquare|r",
		[5] = "|cffaabbccMoon|r",
		[4] = "|cff00ff00Triangle|r",
		[3] = "|cffff00ffDiamond|r",
		[2] = "|cffffaa00Circle|r",
		[1] = "|cffffff00Star|r"
	}

	-- No IGNORE option for sequential marks
	for i = 8, 1, -1 do
		local capturedIcon = i
		local info = {}
		info.text = iconNames[i]
		info.func = function()
			if TankMark.editingSequentialMarks[capturedSeqIndex] then
				TankMark.editingSequentialMarks[capturedSeqIndex].icon = capturedIcon
				TankMark:RefreshSequentialRows()
			end
			CloseDropDownMenus()
		end
		info.checked = (TankMark.editingSequentialMarks[capturedSeqIndex] and TankMark.editingSequentialMarks[capturedSeqIndex].icon == i)
		UIDropDownMenu_AddButton(info)
	end
end
