-- TankMark: v0.23
-- File: TankMark_Config_Mobs_Logic.lua
-- Business logic for Mob Database configuration

if not TankMark then return end

-- ==========================================================
-- LOCALIZATIONS
-- ==========================================================
local _pairs = pairs
local _ipairs = ipairs
local _insert = table.insert
local _gsub = string.gsub
local _tonumber = tonumber

-- ==========================================================
-- LOGIC HELPERS
-- ==========================================================

-- Update the CC button text and color based on selected class
function TankMark:UpdateClassButton()
	if not TankMark.classBtn then return end

	if TankMark.selectedClass then
		TankMark.classBtn:SetText(TankMark.selectedClass)
		TankMark.classBtn:SetTextColor(0, 1, 0)
	else
		TankMark.classBtn:SetText("No CC")
		TankMark.classBtn:SetTextColor(1, 0.82, 0)
	end

	if TankMark.selectedIcon == 0 then
		TankMark.classBtn:SetText("IGNORED")
		TankMark.classBtn:SetTextColor(0.5, 0.5, 0.5)
	end
end

-- Apply smart defaults based on selected class or KILL/IGNORE
function TankMark:ApplySmartDefaults(className)
	local CLASS_DEFAULTS = {
		["MAGE"] = { icon = 5, prio = 3 },
		["WARLOCK"] = { icon = 3, prio = 3 },
		["DRUID"] = { icon = 4, prio = 3 },
		["ROGUE"] = { icon = 1, prio = 3 },
		["PRIEST"] = { icon = 6, prio = 3 },
		["HUNTER"] = { icon = 2, prio = 3 },
		["KILL"] = { icon = 8, prio = 1 },
		["IGNORE"] = { icon = 0, prio = 9 }
	}

	local defaults = className and CLASS_DEFAULTS[className] or CLASS_DEFAULTS["KILL"]
	TankMark.selectedIcon = defaults.icon

	if TankMark.iconBtn and TankMark.iconBtn.tex then
		TankMark:SetIconTexture(TankMark.iconBtn.tex, TankMark.selectedIcon)
	end

	if TankMark.editPrio then
		TankMark.editPrio:SetText(tostring(defaults.prio))
	end
end

-- Toggle GUID lock state for current target
function TankMark:ToggleLockState()
	if not UnitExists("target") and not TankMark.editingLockGUID then
		TankMark:Print("|cffff0000Error:|r You must target a mob to lock it.")
		return
	end

	TankMark.isLockActive = not TankMark.isLockActive

	if TankMark.lockBtn then
		if TankMark.isLockActive then
			TankMark.lockBtn:SetText("|cff00ff00LOCKED|r")
			TankMark.lockBtn:LockHighlight()
		else
			TankMark.lockBtn:SetText("Lock Mark")
			TankMark.lockBtn:UnlockHighlight()
		end
	end
end

-- Reset the mob editor to default state
function TankMark:ResetEditor()
	if TankMark.editMob then
        TankMark.editMob:SetText("Mob Name")
        TankMark.editMob:SetTextColor(0.5, 0.5, 0.5) -- Gray placeholder
    end
	if TankMark.editPrio then TankMark.editPrio:SetText("1") end

	TankMark.editingLockGUID = nil
	TankMark.detectedCreatureType = nil
	TankMark.isLockActive = false
	TankMark.selectedClass = nil
	TankMark:UpdateClassButton()
	TankMark.selectedIcon = 8

	if TankMark.iconBtn and TankMark.iconBtn.tex then
		TankMark:SetIconTexture(TankMark.iconBtn.tex, 8)
	end

	if TankMark.lockBtn then
		TankMark.lockBtn:SetText("Lock Mark")
		TankMark.lockBtn:UnlockHighlight()
		TankMark.lockBtn:Disable()
		TankMark.lockBtn:Show() -- [v0.23] Reset to visible for Add mode
	end

	if TankMark.saveBtn then
		TankMark.saveBtn:SetText("Save")
		TankMark.saveBtn:Disable()
	end

	if TankMark.cancelBtn then TankMark.cancelBtn:Hide() end

	-- [v0.23] Clear sequential marks
	TankMark.editingSequentialMarks = {}
	if TankMark.sequentialScrollFrame then
		TankMark.sequentialScrollFrame:Hide()
	end

	-- [v0.23] Show empty state text (if exists)
	if TankMark.sequentialEmptyText then
		TankMark.sequentialEmptyText:Show()
	end

	-- [v0.23] Collapse accordion(s)
	TankMark.isAddMobExpanded = false
	if TankMark.addMobInterface then
		TankMark.addMobInterface:Hide()
	end
	if TankMark.rightColumnContent then
		TankMark.rightColumnContent:Hide()
	end

	if TankMark.addMobHeader and TankMark.addMobHeader.arrow then
		TankMark.addMobHeader.arrow:SetTexture("Interface\\Buttons\\UI-PlusButton-Up")
	end

	if TankMark.addMoreMarksHeader and TankMark.addMoreMarksHeader.arrow then
		TankMark.addMoreMarksHeader.arrow:SetTexture("Interface\\Buttons\\UI-PlusButton-Up")
	end

	-- [v0.23] Re-enable "+ Add More Marks" header (if exists)
	if TankMark.addMoreMarksHeader then
		TankMark.addMoreMarksHeader.text:SetTextColor(0, 0.8, 1)
		TankMark.addMoreMarksHeader:Enable()
	end
end

-- Enable or disable the zone dropdown
function TankMark:SetDropdownState(enabled)
	if not TankMark.zoneDropDown then return end

	local name = TankMark.zoneDropDown:GetName()
	local btn = _G[name.."Button"]
	local txt = _G[name.."Text"]

	if enabled then
		if btn then btn:Enable(); btn:Show() end
		TankMark.zoneDropDown:EnableMouse(true)
		if txt then txt:SetVertexColor(1, 1, 1) end
	else
		if btn then btn:Disable() end
		TankMark.zoneDropDown:EnableMouse(false)
		if txt then txt:SetVertexColor(0.5, 0.5, 0.5) end
	end
end

-- Toggle between zone list mode and normal mob list mode
function TankMark:ToggleZoneBrowser()
	TankMark.isZoneListMode = not TankMark.isZoneListMode
	TankMark.lockViewZone = nil
	TankMark:ResetEditor()

	if TankMark.searchBox then TankMark.searchBox:SetText("") end

	if TankMark.isZoneListMode then
		TankMark:SetDropdownState(false)
		UIDropDownMenu_SetText("Manage Saved Zones", TankMark.zoneDropDown)
	else
		TankMark:SetDropdownState(true)
		UIDropDownMenu_SetText(GetRealZoneText(), TankMark.zoneDropDown)
	end

	if TankMark.zoneModeCheck then
		TankMark.zoneModeCheck:SetChecked(TankMark.isZoneListMode)
	end

	TankMark:UpdateMobList()
end

-- View GUID locks for a specific zone
function TankMark:ViewLocksForZone(zoneName)
	TankMark.lockViewZone = zoneName
	TankMark:ResetEditor()
	TankMark:UpdateMobList()
end

-- ==========================================================
-- [v0.23] GUID LOCK DETECTION
-- ==========================================================

-- Check if a mob name has a GUID lock
function TankMark:HasGUIDLockForMobName(mobName)
	if not mobName or mobName == "" then return false end
	return TankMark.guidLockIndex and TankMark.guidLockIndex[mobName] or false
end

-- ==========================================================
-- SAVE FORM DATA
-- ==========================================================

-- Save mob data from the edit form to the database
function TankMark:SaveFormData()
	local mobName = TankMark.editMob and TankMark.editMob:GetText()
    
    -- Ignore placeholder text
    if not mobName or mobName == "" or mobName == "Mob Name" then
        TankMark:Print("|cffff0000Error:|r Please enter a valid mob name.")
        return
    end

	-- [v0.23] Handle GUID lock updates (existing logic)
	if TankMark.editingLockGUID then
		local zone = TankMark.lockViewZone or (TankMark.zoneDropDown and UIDropDownMenu_GetText(TankMark.zoneDropDown))

		if not zone or zone == "Manage Saved Zones" then
			TankMark:Print("|cffff0000Error:|r Invalid zone for GUID lock.")
			return
		end

		local mob = TankMark.editMob:GetText()
		local icon = TankMark.selectedIcon

		if not TankMarkDB.StaticGUIDs[zone] then TankMarkDB.StaticGUIDs[zone] = {} end
		TankMarkDB.StaticGUIDs[zone][TankMark.editingLockGUID] = { mark = icon, name = mob }

		TankMark:Print("|cff00ff00Updated:|r Lock for " .. mob)
		TankMark:ResetEditor()
		TankMark:UpdateMobList()
		return
	end

	-- Handle new GUID lock
	if TankMark.isLockActive then
		local zone = TankMark.zoneDropDown and UIDropDownMenu_GetText(TankMark.zoneDropDown) or ""

		if zone == "Manage Saved Zones" or zone == "" then
			TankMark:Print("|cffff0000Error:|r Select a valid zone.")
			return
		end

		local mob = _gsub(TankMark.editMob:GetText(), ";", "")
		local icon = TankMark.selectedIcon
		local exists, guid = UnitExists("target")

		if exists and guid and not UnitIsPlayer("target") and UnitName("target") == mob then
			if not TankMarkDB.StaticGUIDs[zone] then TankMarkDB.StaticGUIDs[zone] = {} end
			TankMarkDB.StaticGUIDs[zone][guid] = { mark = icon, name = mob }

			TankMark:Print("|cff00ff00LOCKED GUID|r for: " .. mob)

			-- Rebuild GUID lock index
			if TankMark.RebuildGUIDLockIndex then
				TankMark:RebuildGUIDLockIndex()
			end
		else
			TankMark:Print("|cffff0000Error:|r Target lost or name mismatch. Lock failed.")
			return
		end
	end

	-- [v0.23] Normal mob entry save
	local zone = TankMark.zoneDropDown and UIDropDownMenu_GetText(TankMark.zoneDropDown) or ""

	if zone == "Manage Saved Zones" or zone == "" then
		TankMark:Print("|cffff0000Error:|r Select a valid zone.")
		return
	end

	local rawMob = TankMark.editMob:GetText()
	local mob = _gsub(rawMob, ";", "")
	local prio = _tonumber(TankMark.editPrio:GetText()) or 1

	if mob == "" or mob == "Mob Name" then return end

	-- [v0.23] Build mob entry with sequential marks
	local mobEntry = {
		prio = prio,
		marks = {},
		type = TankMark.selectedClass and "CC" or "KILL",
		class = TankMark.selectedClass
	}

	-- Add main row mark
	_insert(mobEntry.marks, TankMark.selectedIcon)

	-- Add sequential marks
	for i, seqData in _ipairs(TankMark.editingSequentialMarks) do
		_insert(mobEntry.marks, seqData.icon)
	end

	-- Validation: No IGNORE (mark = 0) in sequences
	if table.getn(mobEntry.marks) > 1 then
		for _, mark in _ipairs(mobEntry.marks) do
			if mark == 0 then
				TankMark:Print("|cffff0000Error:|r Sequential marks cannot contain IGNORE.")
				return
			end
		end
	end

	-- Save to database
	if not TankMarkDB.Zones[zone] then TankMarkDB.Zones[zone] = {} end
	TankMarkDB.Zones[zone][mob] = mobEntry

	local markCountStr = (table.getn(mobEntry.marks) > 1) and (", " .. table.getn(mobEntry.marks) .. " marks") or ""
	TankMark:Print("|cff00ff00Saved:|r " .. mob .. " |cff888888(P" .. prio .. markCountStr .. ")|r")

	-- Refresh activeDB
	if TankMark.RefreshActiveDB then
		TankMark:RefreshActiveDB()
	end

	TankMark:ResetEditor()
	TankMark.isZoneListMode = false
	TankMark:UpdateMobList()
end

-- ==========================================================
-- POPUP ACTIONS
-- ==========================================================

-- Request confirmation to delete a mob from the database
function TankMark:RequestDeleteMob(zone, mob)
	TankMark.pendingWipeAction = function()
		if TankMarkDB.Zones[zone] then
			TankMarkDB.Zones[zone][mob] = nil
			TankMark:UpdateMobList()
			TankMark:Print("|cffff0000Removed:|r " .. mob)
		end
	end

	StaticPopup_Show("TANKMARK_WIPE_CONFIRM", "Delete mob from database?\n\n|cffff0000" .. mob .. "|r")
end

-- Request confirmation to delete a GUID lock
function TankMark:RequestDeleteLock(guid, name)
	local z = TankMark.lockViewZone

	TankMark.pendingWipeAction = function()
		if z and TankMarkDB.StaticGUIDs[z] then
			TankMarkDB.StaticGUIDs[z][guid] = nil
			TankMark:UpdateMobList()
			TankMark:Print("|cffff0000Removed:|r Lock for " .. (name or "GUID"))

			-- Rebuild GUID lock index
			if TankMark.RebuildGUIDLockIndex then
				TankMark:RebuildGUIDLockIndex()
			end
		end
	end

	StaticPopup_Show("TANKMARK_WIPE_CONFIRM", "Remove GUID lock?\n\n|cffff0000" .. (name or "Unknown") .. "|r")
end

-- Request confirmation to delete an entire zone
function TankMark:RequestDeleteZone(zoneName)
	TankMark.pendingWipeAction = function()
		TankMarkDB.Zones[zoneName] = nil
		TankMarkDB.StaticGUIDs[zoneName] = nil
		TankMark:Print("|cffff0000Deleted:|r Zone '" .. zoneName .. "'")

		-- Refresh activeDB if we deleted the current zone
		local currentZone = TankMark:GetCachedZone()
		if zoneName == currentZone and TankMark.LoadZoneData then
			TankMark:LoadZoneData(currentZone)
		end

		TankMark:UpdateMobList()
	end

	StaticPopup_Show("TANKMARK_WIPE_CONFIRM", "Delete ENTIRE zone and all its data?\n\n|cffff0000" .. zoneName .. "|r")
end

-- ==========================================================
-- ADD CURRENT ZONE DIALOG
-- ==========================================================

-- Show dialog to add current zone to database
function TankMark:ShowAddCurrentZoneDialog()
	local currentZone = GetRealZoneText()

	-- Check if zone already exists
	if TankMarkDB.Zones[currentZone] then
		TankMark:Print("|cffffaa00Notice:|r Zone '" .. currentZone .. "' already exists in database.")
		return
	end

	StaticPopupDialogs["TANKMARK_ADD_ZONE"] = {
		text = "Add current zone to database?\n\n|cff00ff00" .. currentZone .. "|r",
		button1 = "Add",
		button2 = "Cancel",
		OnAccept = function()
			TankMarkDB.Zones[currentZone] = {}
			TankMark:Print("|cff00ff00Added:|r Zone '" .. currentZone .. "' to database.")
			UIDropDownMenu_SetText(currentZone, TankMark.zoneDropDown)

			if TankMark.isZoneListMode then
				TankMark:ToggleZoneBrowser()
			end

			TankMark:UpdateMobList()
		end,
		timeout = 0,
		whileDead = 1,
		hideOnEscape = 1,
		exclusive = 1,
	}

	StaticPopup_Show("TANKMARK_ADD_ZONE")
end
