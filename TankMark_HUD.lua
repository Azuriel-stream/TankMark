-- TankMark: v0.19-dev (Release Candidate)
-- File: TankMark_HUD.lua
-- [PHASE 2] Use cached zone lookups

if not TankMark then return end

-- Localizations
local _pairs = pairs
local _ipairs = ipairs
local _insert = table.insert
local _sort = table.sort

-- UI State
TankMark.hudFrame = nil
TankMark.hudRows = {}
TankMark.menuFrame = nil
TankMark.clickedIconID = nil -- Tracks which row was right-clicked

-- ==========================================================
-- 1. MENUS (Global & Context)
-- ==========================================================
function TankMark:InitGlobalMenu()
	local info = {}
	
	-- Header
	info = { text = "TankMark Actions", isTitle = 1, notCheckable = 1 }
	UIDropDownMenu_AddButton(info)
	
	-- Master Toggle
	info = {
		text = "Enable Auto-Marking",
		checked = TankMark.IsActive,
		func = function()
			TankMark.IsActive = not TankMark.IsActive
			CloseDropDownMenus()
			TankMark:Print("Auto-Marking is now: " .. (TankMark.IsActive and "|cff00ff00ON|r" or "|cffff0000OFF|r"))
		end
	}
	UIDropDownMenu_AddButton(info)
	
	-- Actions
	info = { text = "Enable All Marks", notCheckable = 1, func = function() TankMark.disabledMarks = {}; TankMark:UpdateHUD() end }
	UIDropDownMenu_AddButton(info)
	
	info = { text = "Announce Assignments", notCheckable = 1, func = function() TankMark:AnnounceAssignments() end }
	UIDropDownMenu_AddButton(info)
	
	info = { text = "Sync Zone Data", notCheckable = 1, func = function() TankMark:BroadcastZone() end }
	UIDropDownMenu_AddButton(info)
	
	info = { text = "Open Configuration", notCheckable = 1, func = function() TankMark:ShowOptions() end }
	UIDropDownMenu_AddButton(info)
	
	-- Reset
	info = { text = "|cffff0000Reset Session|r", notCheckable = 1, func = function() TankMark:ResetSession() end }
	UIDropDownMenu_AddButton(info)
	
	info = { text = "Close", notCheckable = 1, func = function() CloseDropDownMenus() end }
	UIDropDownMenu_AddButton(info)
end

function TankMark:InitRowMenu()
	local iconID = TankMark.clickedIconID
	if not iconID then return end
	
	local markName = TankMark.MarkInfo[iconID].color .. TankMark.MarkInfo[iconID].name .. "|r"
	
	local info = { text = markName .. " Options", isTitle = 1, notCheckable = 1 }
	UIDropDownMenu_AddButton(info)
	
	-- 1. Assign Target
	local targetName = UnitName("target")
	local canAssign = (targetName and UnitIsPlayer("target"))
	local assignText = "Assign Target"
	if canAssign then assignText = assignText .. " |cff00ff00(" .. targetName .. ")|r" end
	
	info = {
		text = assignText,
		notCheckable = 1,
		disabled = not canAssign,
		func = function()
			TankMark:SetProfileAssignment(iconID, targetName)
			CloseDropDownMenus()
		end
	}
	UIDropDownMenu_AddButton(info)
	
	-- 2. Clear Assignment
	info = {
		text = "Clear Assignment (Free)",
		notCheckable = 1,
		func = function()
			TankMark:SetProfileAssignment(iconID, "")
			CloseDropDownMenus()
		end
	}
	UIDropDownMenu_AddButton(info)
	
	-- 3. Disable Toggle
	local isDisabled = TankMark.disabledMarks[iconID]
	info = {
		text = isDisabled and "Enable Mark" or "Disable Mark",
		notCheckable = 1,
		func = function()
			TankMark:ToggleMarkState(iconID)
			CloseDropDownMenus() -- Close to show update
		end
	}
	UIDropDownMenu_AddButton(info)
	
	info = { text = "Cancel", notCheckable = 1, func = function() CloseDropDownMenus() end }
	UIDropDownMenu_AddButton(info)
end

-- Helper to write directly to DB from HUD
function TankMark:SetProfileAssignment(iconID, playerName)
	local zone = TankMark:GetCachedZone()  -- [PHASE 2] Use cached zone
	if not TankMarkProfileDB[zone] then TankMarkProfileDB[zone] = {} end
	local list = TankMarkProfileDB[zone]
	
	-- 1. Find existing entry or create new
	local found = false
	for _, entry in _ipairs(list) do
		if entry.mark == iconID then
			entry.tank = playerName
			found = true
			break
		end
	end
	
	if not found then
		_insert(list, { mark = iconID, tank = playerName, healers = "" })
		-- Sort new list by ID desc (Skull first)
		_sort(list, function(a,b) return a.mark > b.mark end)
	end
	
	-- 2. Update Live Session
	if playerName and playerName ~= "" then
		TankMark.sessionAssignments[iconID] = playerName
		TankMark.usedIcons[iconID] = true
		TankMark:Print("Assigned " .. playerName .. " to " .. TankMark:GetMarkString(iconID))
	else
		-- If clearing, we remove the name but keep the 'used' status if it's currently on a mob
		TankMark.sessionAssignments[iconID] = nil
		TankMark:Print("Cleared assignment for " .. TankMark:GetMarkString(iconID))
	end
	
	-- 3. Refresh UI
	TankMark:UpdateHUD()
	
	-- Refresh Config Tab 2 if it's open
	if TankMark.UpdateProfileList then TankMark:LoadProfileToCache(); TankMark:UpdateProfileList() end
end

-- ==========================================================
-- 2. FRAME CREATION
-- ==========================================================
function TankMark:CreateHUD()
	-- Single Menu Frame used for both contexts (re-initialized on click)
	TankMark.menuFrame = CreateFrame("Frame", "TankMarkHUDMenu", UIParent, "UIDropDownMenuTemplate")
	
	local f = CreateFrame("Frame", "TankMarkHUD", UIParent)
	f:SetWidth(200); f:SetHeight(150)
	f:SetPoint("CENTER", UIParent, "CENTER", 200, 0)
	f:SetBackdrop({
		bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true, tileSize = 16, edgeSize = 16,
		insets = { left = 5, right = 5, top = 5, bottom = 5 }
	})
	f:SetBackdropColor(0, 0, 0, 0.4)
	f:SetBackdropBorderColor(0.8, 0.8, 0.8, 0.5)
	f:SetMovable(true); f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", function() this:StartMoving() end)
	f:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)
	
	-- Right-Click on Background -> Global Menu
	f:SetScript("OnMouseUp", function()
		if arg1 == "RightButton" then
			UIDropDownMenu_Initialize(TankMark.menuFrame, function() TankMark:InitGlobalMenu() end, "MENU")
			ToggleDropDownMenu(1, nil, TankMark.menuFrame, "cursor", 0, 0)
		end
	end)
	
	f.header = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	f.header:SetPoint("TOP", f, "TOP", 0, -5)
	f.header:SetText("TankMark HUD")
	
	for i = 8, 1, -1 do
		local row = CreateFrame("Button", nil, f)
		row:SetWidth(180); row:SetHeight(20)
		row:SetID(i)
		
		row.icon = row:CreateTexture(nil, "ARTWORK")
		row.icon:SetWidth(16); row.icon:SetHeight(16)
		row.icon:SetPoint("LEFT", row, "LEFT", 0, 0)
		row.icon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
		SetRaidTargetIconTexture(row.icon, i)
		
		row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		row.text:SetPoint("LEFT", row.icon, "RIGHT", 5, 0)
		row.text:SetText("")
		
		row:EnableMouse(true)
		row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		row:SetScript("OnClick", function()
			if arg1 == "LeftButton" then
				TankMark:ToggleMarkState(this:GetID())
			elseif arg1 == "RightButton" then
				-- Open Row Context Menu
				TankMark.clickedIconID = this:GetID()
				UIDropDownMenu_Initialize(TankMark.menuFrame, function() TankMark:InitRowMenu() end, "MENU")
				ToggleDropDownMenu(1, nil, TankMark.menuFrame, "cursor", 0, 0)
			end
		end)
		
		row:Hide()
		TankMark.hudRows[i] = row
	end
	
	TankMark.hudFrame = f
	TankMark:UpdateHUD()
end

-- ==========================================================
-- 3. TOGGLE & UPDATE LOGIC
-- ==========================================================
function TankMark:ToggleMarkState(iconID)
	TankMark.disabledMarks[iconID] = not TankMark.disabledMarks[iconID]
	TankMark:UpdateHUD()
end

function TankMark:UpdateHUD()
	if not TankMark.hudFrame then TankMark:CreateHUD() end
	
	local activeRows = 0
	local lastVisibleRow = nil
	local zone = TankMark:GetCachedZone()  -- [PHASE 2] Use cached zone
	
	local renderList = {}
	local added = {} -- Tracks if mark exists in Profile
	
	-- 1. Build List from Profile
	if TankMarkProfileDB and TankMarkProfileDB[zone] then
		for _, entry in _ipairs(TankMarkProfileDB[zone]) do
			if entry.mark then
				_insert(renderList, entry.mark)
				added[entry.mark] = true
			end
		end
	end
	
	-- 2. Empty Profile Warning
	if table.getn(renderList) == 0 then
		local warningRow = TankMark.hudRows[8]
		warningRow.icon:SetTexture(nil)
		warningRow.text:SetText("|cffff0000NO PROFILE LOADED|r")
		warningRow:ClearAllPoints()
		warningRow:SetPoint("TOPLEFT", TankMark.hudFrame, "TOPLEFT", 10, -25)
		warningRow:Show()
		
		for i = 7, 1, -1 do TankMark.hudRows[i]:Hide() end
		
		TankMark.hudFrame:Show()
		TankMark.hudFrame:SetHeight(50)
		return
	end
	
	-- 3. Add Leftovers (Standard desc order)
	for i = 8, 1, -1 do
		if not added[i] then
			_insert(renderList, i)
		end
	end
	
	-- 4. Render Loop
	for _, i in _ipairs(renderList) do
		local row = TankMark.hudRows[i]
		local assignedPlayer = TankMark.sessionAssignments[i]
		local activeMob = TankMark.activeMobNames[i]
		local textToShow = nil
		
		if assignedPlayer then
			textToShow = "|cff00ff00" .. assignedPlayer .. "|r"
		elseif activeMob then
			textToShow = "|cffffffff" .. activeMob .. "|r"
		end
		
		local isProfileMark = added[i]
		local hasAssignment = (textToShow ~= nil)
		local isDisabled = TankMark.disabledMarks[i]
		
		-- Apply Visual Disable (Dimming)
		if isDisabled then
			row.icon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
			SetRaidTargetIconTexture(row.icon, i)
			row.icon:SetVertexColor(0.3, 0.3, 0.3)
			
			if textToShow then
				local plainText = string.gsub(textToShow, "|c%x%x%x%x%x%x%x%x", "")
				plainText = string.gsub(plainText, "|r", "")
				textToShow = "|cff888888" .. plainText .. " (OFF)|r"
			else
				textToShow = "|cff888888(Disabled)|r"
			end
		else
			row.icon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
			SetRaidTargetIconTexture(row.icon, i)
			row.icon:SetVertexColor(1, 1, 1)
		end
		
		-- Display Decision
		if isProfileMark or hasAssignment or isDisabled then
			if not textToShow then
				textToShow = "|cff888888(Free)|r"
			end
			
			row.text:SetText(textToShow)
			row:ClearAllPoints()
			
			if not lastVisibleRow then
				row:SetPoint("TOPLEFT", TankMark.hudFrame, "TOPLEFT", 10, -25)
			else
				row:SetPoint("TOPLEFT", lastVisibleRow, "BOTTOMLEFT", 0, 0)
			end
			
			row:Show()
			lastVisibleRow = row
			activeRows = activeRows + 1
		else
			row:Hide()
		end
	end
	
	if activeRows > 0 then
		TankMark.hudFrame:Show()
		TankMark.hudFrame:SetHeight((activeRows * 20) + 30)
	else
		TankMark.hudFrame:Hide()
	end
end
