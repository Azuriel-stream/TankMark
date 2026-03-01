-- TankMark: v0.27
-- File: TankMark_Config_Profiles_Logic.lua
-- Business logic for Team Profiles configuration

if not TankMark then return end

-- ==========================================================
-- LOCALIZATIONS
-- ==========================================================

local L = TankMark.Locals

-- ==========================================================
-- CACHE OPERATIONS
-- ==========================================================

function TankMark:LoadProfileToCache()
	if not TankMarkProfileDB then TankMarkProfileDB = {} end
	local zone = UIDropDownMenu_GetText(TankMark.profileZoneDropdown) or L._GetRealZoneText()
	TankMark:MigrateProfileRoles(zone)
	TankMark.profileCache = {}
	if TankMarkProfileDB[zone] then
		for _, entry in L._ipairs(TankMarkProfileDB[zone]) do
			L._tinsert(TankMark.profileCache, {
				mark    = entry.mark or 8,
				tank    = entry.tank or "",
				healers = entry.healers or "",
				role    = entry.role or "TANK",
			})
		end
	end
end

function TankMark:SaveProfileCache()
	local zone = UIDropDownMenu_GetText(TankMark.profileZoneDropdown) or L._GetRealZoneText()
	TankMarkProfileDB[zone] = {}
	for i, entry in L._ipairs(TankMark.profileCache) do
		L._tinsert(TankMarkProfileDB[zone], {
			mark    = entry.mark,
			tank    = entry.tank,
			healers = entry.healers,
			role    = entry.role or "TANK",
		})
	end

	-- Update session if saving for the current zone
	if zone == L._GetRealZoneText() then
		-- [v0.26] Do NOT pre-mark icons as used.
		-- Session assignments drive the HUD; usedIcons should reflect live mob marks only.
		TankMark.sessionAssignments = {}

		for _, entry in L._ipairs(TankMarkProfileDB[zone]) do
			if entry.tank and entry.tank ~= "" then
				TankMark.sessionAssignments[entry.mark] = entry.tank
			end
		end

		-- Leave TankMark.usedIcons untouched here.
		-- It will be populated when marks are actually applied to mobs.
		if TankMark.UpdateHUD then
			TankMark:UpdateHUD()
		end
	end

	TankMark:Print("|cff00ff00Saved:|r Profile for '" .. zone .. "'")
	TankMark:UpdateProfileList()
end

-- ==========================================================
-- ROW OPERATIONS
-- ==========================================================

function TankMark:ProfileAddRow()
	L._tinsert(TankMark.profileCache, {mark = 8, tank = "", healers = "", role = "TANK"})
	TankMark:UpdateProfileList()
end

function TankMark:ProfileDeleteRow(index)
	if not index or not TankMark.profileCache[index] then return end
	L._tremove(TankMark.profileCache, index)
	TankMark:UpdateProfileList()
end

function TankMark:ProfileMoveRow(index, direction)
	if not index then return end
	local target = index + direction
	if target < 1 or target > L._tgetn(TankMark.profileCache) then return end
	local temp                     = TankMark.profileCache[index]
	TankMark.profileCache[index]   = TankMark.profileCache[target]
	TankMark.profileCache[target]  = temp
	TankMark:UpdateProfileList()
end

-- ==========================================================
-- DESTRUCTIVE OPERATIONS (CONFIRMATION DIALOGS)
-- ==========================================================

function TankMark:RequestResetProfile()
	local zone = UIDropDownMenu_GetText(TankMark.profileZoneDropdown) or L._GetRealZoneText()
	if zone and TankMarkProfileDB[zone] then
		TankMark.pendingWipeAction = function()
			TankMarkProfileDB[zone] = {}
			TankMark:LoadProfileToCache()
			TankMark:UpdateProfileList()
			if zone == L._GetRealZoneText() then
				TankMark.sessionAssignments = {}
				TankMark.usedIcons = {}
				if TankMark.UpdateHUD then
					TankMark:UpdateHUD()
				end
			end
			TankMark:Print("|cffff0000Reset:|r Cleared profile for '" .. zone .. "'")
		end
		StaticPopup_Show("TANKMARK_WIPE_CONFIRM", "Clear profile for zone?\n\n|cffff0000" .. zone .. "|r")
	else
		TankMark:Print("|cffffaa00Notice:|r No profile data to reset.")
	end
end

function TankMark:RequestDeleteProfile()
	local zone = UIDropDownMenu_GetText(TankMark.profileZoneDropdown) or L._GetRealZoneText()
	if zone and TankMarkProfileDB[zone] then
		TankMark.pendingWipeAction = function()
			TankMarkProfileDB[zone] = nil
			UIDropDownMenu_SetText(L._GetRealZoneText(), TankMark.profileZoneDropdown)
			TankMark:LoadProfileToCache()
			TankMark:UpdateProfileList()
			TankMark:Print("|cffff0000Deleted:|r Profile for '" .. zone .. "'")
		end
		StaticPopup_Show("TANKMARK_WIPE_CONFIRM", "Delete entire profile for zone?\n\n|cffff0000" .. zone .. "|r")
	else
		TankMark:Print("|cffffaa00Notice:|r No profile data to delete.")
	end
end

-- ==========================================================
-- HEALER ASSIGNMENT HELPER
-- ==========================================================

function TankMark:AddHealerToRow(rowIndex)
	if not rowIndex or not TankMark.profileCache[rowIndex] then return end

	if not L._UnitExists("target") then
		TankMark:Print("|cffffaa00Notice:|r No target selected.")
		return
	end

	if not L._UnitIsPlayer("target") then
		TankMark:Print("|cffffaa00Notice:|r Target must be a player.")
		return
	end

	local healerName = L._UnitName("target")
	if not healerName then return end

	local currentHealers = TankMark.profileCache[rowIndex].healers or ""

	-- Check if healer already in list
	if currentHealers ~= "" then
		local healerList = {}
		for name in L._gfind(currentHealers, "[^ ]+") do
			L._tinsert(healerList, name)
			if name == healerName then
				TankMark:Print("|cffffaa00Notice:|r " .. healerName .. " is already in the healer list.")
				return
			end
		end
		-- Append new healer
		TankMark.profileCache[rowIndex].healers = currentHealers .. " " .. healerName
	else
		-- First healer
		TankMark.profileCache[rowIndex].healers = healerName
	end

	TankMark:UpdateProfileList()
	TankMark:Print("|cff00ff00Added:|r " .. healerName .. " as healer")
end

-- ==========================================================
-- TEMPLATE SYSTEM
-- ==========================================================

function TankMark:ShowTemplateMenu()
	local templateDrop = CreateFrame("Frame", "TMTemplateDropDown", UIParent, "UIDropDownMenuTemplate")
	UIDropDownMenu_Initialize(templateDrop, function()
		for templateName, _ in L._pairs(TankMarkProfileTemplates) do
			local capturedTemplate = templateName
			local info = {}
			info.text = templateName
			info.func = function()
				TankMark:LoadTemplate(capturedTemplate)
				CloseDropDownMenus()
			end
			UIDropDownMenu_AddButton(info)
		end
	end)
	ToggleDropDownMenu(1, nil, templateDrop, "cursor", 0, 0)
end

function TankMark:LoadTemplate(templateName)
	local template = TankMarkProfileTemplates[templateName]
	if not template then
		TankMark:Print("|cffff0000Error:|r Template '" .. templateName .. "' not found.")
		return
	end

	TankMark.profileCache = {}
	for _, entry in L._ipairs(template) do
		L._tinsert(TankMark.profileCache, {
			mark    = entry.mark,
			tank    = entry.tank or "",
			healers = entry.healers or "",
			role    = entry.role or "TANK",
		})
	end

	if TankMark.profileScroll then
		FauxScrollFrame_SetOffset(TankMark.profileScroll, 0)
	end

	TankMark:UpdateProfileList()
	TankMark:Print("|cff00ff00Loaded:|r Template '" .. templateName .. "' (" .. L._tgetn(TankMark.profileCache) .. " marks)")
end

-- ==========================================================
-- COPY FROM ZONE FEATURE
-- ==========================================================

function TankMark:ShowCopyProfileDialog()
	local currentZone = UIDropDownMenu_GetText(TankMark.profileZoneDropdown) or L._GetRealZoneText()

	-- Build list of zones that have profiles (excluding current zone and empty ones)
	local sourceZones = {}
	for zoneName, profile in L._pairs(TankMarkProfileDB) do
		if zoneName ~= currentZone and L._type(profile) == "table" and L._tgetn(profile) > 0 then
			L._tinsert(sourceZones, zoneName)
		end
	end

	if L._tgetn(sourceZones) == 0 then
		TankMark:Print("|cffffaa00Notice:|r No other profiles found to copy from.")
		return
	end

	L._tsort(sourceZones)

	local copyDrop = CreateFrame("Frame", "TMCopyProfileDropDown", UIParent, "UIDropDownMenuTemplate")
	UIDropDownMenu_Initialize(copyDrop, function()
		for _, zoneName in L._ipairs(sourceZones) do
			local capturedZone = zoneName
			local info = {}
			info.text = zoneName .. " |cff888888(" .. L._tgetn(TankMarkProfileDB[zoneName]) .. " marks)|r"
			info.func = function()
				TankMark:CopyProfileFrom(capturedZone, currentZone)
				CloseDropDownMenus()
			end
			UIDropDownMenu_AddButton(info)
		end
	end)
	ToggleDropDownMenu(1, nil, copyDrop, "cursor", 0, 0)
end

function TankMark:CopyProfileFrom(sourceZone, targetZone)
	if not TankMarkProfileDB[sourceZone] then
		TankMark:Print("|cffff0000Error:|r Source profile '" .. sourceZone .. "' not found in database.")
		TankMark:Print("|cffffaa00Debug:|r Available zones:")
		for zName, _ in L._pairs(TankMarkProfileDB) do
			TankMark:Print("  - '" .. zName .. "'")
		end
		return
	end

	if L._tgetn(TankMarkProfileDB[sourceZone]) == 0 then
		TankMark:Print("|cffffaa00Notice:|r Source zone '" .. sourceZone .. "' has no profile data.")
		return
	end

	TankMark.profileCache = {}
	for _, entry in L._ipairs(TankMarkProfileDB[sourceZone]) do
		L._tinsert(TankMark.profileCache, {
			mark    = entry.mark,
			tank    = entry.tank or "",
			healers = entry.healers or "",
			role    = entry.role or "TANK",
		})
	end

	if TankMark.profileScroll then
		FauxScrollFrame_SetOffset(TankMark.profileScroll, 0)
	end

	TankMark:UpdateProfileList()
	TankMark:Print("|cff00ff00Copied:|r " .. L._tgetn(TankMark.profileCache) .. " marks from '" .. sourceZone .. "'")
end