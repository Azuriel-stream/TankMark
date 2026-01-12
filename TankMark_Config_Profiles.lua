-- TankMark: v0.19-dev

-- File: TankMark_Config_Profiles.lua

-- Team Profiles configuration with templates and copy features

if not TankMark then return end

-- ==========================================================
-- LOCALIZATIONS
-- ==========================================================

local _pairs = pairs
local _ipairs = ipairs
local _insert = table.insert
local _remove = table.remove
local _getn = table.getn

-- ==========================================================
-- STATE
-- ==========================================================

TankMark.profileRows = {}
TankMark.profileScroll = nil
TankMark.profileZoneDropdown = nil
TankMark.profileCache = {}

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
		{mark = 1, tank = "", healers = ""}
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

-- ==========================================================
-- DATA LOGIC
-- ==========================================================

function TankMark:LoadProfileToCache()
	if not TankMarkProfileDB then TankMarkProfileDB = {} end
	local zone = UIDropDownMenu_GetText(TankMark.profileZoneDropdown) or GetRealZoneText()
	TankMark.profileCache = {}
	if TankMarkProfileDB[zone] then
		for _, entry in _ipairs(TankMarkProfileDB[zone]) do
			_insert(TankMark.profileCache, {
				mark = entry.mark or 8,
				tank = entry.tank or "",
				healers = entry.healers or ""
			})
		end
	end
end

function TankMark:SaveProfileCache()
	local zone = UIDropDownMenu_GetText(TankMark.profileZoneDropdown) or GetRealZoneText()
	TankMarkProfileDB[zone] = {}
	for i, entry in _ipairs(TankMark.profileCache) do
		_insert(TankMarkProfileDB[zone], {
			mark = entry.mark,
			tank = entry.tank,
			healers = entry.healers
		})
	end
	
	-- Update session if current zone
	if zone == GetRealZoneText() then
		TankMark.sessionAssignments = {}
		TankMark.usedIcons = {}
		for _, entry in _ipairs(TankMarkProfileDB[zone]) do
			if entry.tank and entry.tank ~= "" then
				TankMark.sessionAssignments[entry.mark] = entry.tank
				TankMark.usedIcons[entry.mark] = true
			end
		end
		if TankMark.UpdateHUD then
			TankMark:UpdateHUD()
		end
	end
	
	TankMark:Print("|cff00ff00Saved:|r Profile for '" .. zone .. "'")
	TankMark:UpdateProfileList()
end

function TankMark:RequestResetProfile()
	local zone = UIDropDownMenu_GetText(TankMark.profileZoneDropdown) or GetRealZoneText()
	if zone and TankMarkProfileDB[zone] then
		TankMark.pendingWipeAction = function()
			TankMarkProfileDB[zone] = {}
			TankMark:LoadProfileToCache()
			TankMark:UpdateProfileList()
			if zone == GetRealZoneText() then
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

function TankMark:ProfileAddRow()
	_insert(TankMark.profileCache, {mark = 8, tank = "", healers = ""})
	TankMark:UpdateProfileList()
end

function TankMark:ProfileDeleteRow(index)
	if not index or not TankMark.profileCache[index] then return end
	_remove(TankMark.profileCache, index)
	TankMark:UpdateProfileList()
end

function TankMark:ProfileMoveRow(index, direction)
	if not index then return end
	local target = index + direction
	if target < 1 or target > _getn(TankMark.profileCache) then return end
	local temp = TankMark.profileCache[index]
	TankMark.profileCache[index] = TankMark.profileCache[target]
	TankMark.profileCache[target] = temp
	TankMark:UpdateProfileList()
end

-- ==========================================================
-- TEMPLATE SYSTEM
-- ==========================================================

function TankMark:ShowTemplateMenu()
	local templateDrop = CreateFrame("Frame", "TMTemplateDropDown", UIParent, "UIDropDownMenuTemplate")
	UIDropDownMenu_Initialize(templateDrop, function()
		for templateName, _ in _pairs(TankMarkProfileTemplates) do
			local capturedTemplate = templateName  -- Closure capture
			local info = {}
			info.text = templateName
			info.func = function()
				TankMark:LoadTemplate(capturedTemplate)  -- Use captured variable
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
	
	-- Clear and rebuild cache
	TankMark.profileCache = {}
	for _, entry in _ipairs(template) do
		_insert(TankMark.profileCache, {
			mark = entry.mark,
			tank = entry.tank or "",
			healers = entry.healers or ""
		})
	end
	
	-- Reset scroll position
	if TankMark.profileScroll then
		FauxScrollFrame_SetOffset(TankMark.profileScroll, 0)
	end
	
	TankMark:UpdateProfileList()
	TankMark:Print("|cff00ff00Loaded:|r Template '" .. templateName .. "' (" .. _getn(TankMark.profileCache) .. " marks)")
end

-- ==========================================================
-- COPY FROM ZONE FEATURE
-- ==========================================================

function TankMark:ShowCopyProfileDialog()
	local currentZone = UIDropDownMenu_GetText(TankMark.profileZoneDropdown) or GetRealZoneText()
	
	-- Build list of zones that have profiles
	local sourceZones = {}
	for zoneName, profile in _pairs(TankMarkProfileDB) do
		-- Skip current zone and empty profiles
		if zoneName ~= currentZone and type(profile) == "table" and _getn(profile) > 0 then
			_insert(sourceZones, zoneName)
		end
	end
	
	if _getn(sourceZones) == 0 then
		TankMark:Print("|cffffaa00Notice:|r No other profiles found to copy from.")
		return
	end
	
	-- Sort zones alphabetically
	table.sort(sourceZones)
	
	-- Create dropdown menu
	local copyDrop = CreateFrame("Frame", "TMCopyProfileDropDown", UIParent, "UIDropDownMenuTemplate")
	UIDropDownMenu_Initialize(copyDrop, function()
		for _, zoneName in _ipairs(sourceZones) do
			local capturedZone = zoneName  -- Closure capture
			local info = {}
			info.text = zoneName .. " |cff888888(" .. _getn(TankMarkProfileDB[zoneName]) .. " marks)|r"
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
	-- Debug: Print what we're looking for
	if not TankMarkProfileDB[sourceZone] then
		TankMark:Print("|cffff0000Error:|r Source profile '" .. sourceZone .. "' not found in database.")
		TankMark:Print("|cffffaa00Debug:|r Available zones:")
		for zName, _ in _pairs(TankMarkProfileDB) do
			TankMark:Print("  - '" .. zName .. "'")
		end
		return
	end
	
	-- Check if source has data
	if _getn(TankMarkProfileDB[sourceZone]) == 0 then
		TankMark:Print("|cffffaa00Notice:|r Source zone '" .. sourceZone .. "' has no profile data.")
		return
	end
	
	-- Deep copy profile
	TankMark.profileCache = {}
	for _, entry in _ipairs(TankMarkProfileDB[sourceZone]) do
		_insert(TankMark.profileCache, {
			mark = entry.mark,
			tank = entry.tank or "",
			healers = entry.healers or ""
		})
	end
	
	-- Reset scroll position
	if TankMark.profileScroll then
		FauxScrollFrame_SetOffset(TankMark.profileScroll, 0)
	end
	
	TankMark:UpdateProfileList()
	TankMark:Print("|cff00ff00Copied:|r " .. _getn(TankMark.profileCache) .. " marks from '" .. sourceZone .. "'")
end


-- ==========================================================
-- UI LOGIC
-- ==========================================================

function TankMark:InitProfileIconMenu(parentFrame, dataIndex)
	if not dataIndex or not TankMark.profileCache[dataIndex] then return end
	local info
	local iconNames = {
		[8] = "Skull",
		[7] = "Cross",
		[6] = "Square",
		[5] = "Moon",
		[4] = "Triangle",
		[3] = "Diamond",
		[2] = "Circle",
		[1] = "Star"
	}
	for i = 8, 1, -1 do
		local capturedIcon = i
		info = {}
		info.text = iconNames[capturedIcon]
		info.func = function()
			if TankMark.profileCache[dataIndex] then
				TankMark.profileCache[dataIndex].mark = capturedIcon
				TankMark:UpdateProfileList()
			end
		end
		if TankMark.profileCache[dataIndex].mark == capturedIcon then
			info.checked = 1
		end
		UIDropDownMenu_AddButton(info)
	end
end

function TankMark:UpdateProfileList()
	if not TankMark.profileScroll then return end
	
	local list = TankMark.profileCache
	local numItems = _getn(list)
	local MAX_ROWS = 6
	FauxScrollFrame_Update(TankMark.profileScroll, numItems, MAX_ROWS, 44)
	local offset = FauxScrollFrame_GetOffset(TankMark.profileScroll)
	
	for i = 1, MAX_ROWS do
		local index = offset + i
		local row = TankMark.profileRows[i]
		if index <= numItems then
			local data = list[index]
			row.index = index
			TankMark:SetIconTexture(row.iconTex, data.mark)
			row.tankEdit:SetText(data.tank or "")
			row.healEdit:SetText(data.healers or "")
			
			-- Disable Up button for first row, Down for last row
			if index == 1 then
				row.upBtn:Disable()
			else
				row.upBtn:Enable()
			end
			if index == numItems then
				row.downBtn:Disable()
			else
				row.downBtn:Enable()
			end
			row:Show()
		else
			row.index = nil
			row:Hide()
		end
	end
	
	-- Hide extra rows
	for i = MAX_ROWS + 1, 8 do
		if TankMark.profileRows[i] then
			TankMark.profileRows[i]:Hide()
		end
	end
end

-- ==========================================================
-- TAB CONSTRUCTION
-- ==========================================================

function TankMark:CreateProfileTab(parent)
	local t2 = CreateFrame("Frame", nil, parent)
	t2:SetPoint("TOPLEFT", 15, -40)
	t2:SetPoint("BOTTOMRIGHT", -15, 50)
	t2:Hide()
	
	-- Zone Dropdown
	local pDrop = CreateFrame("Frame", "TMProfileZoneDropDown", t2, "UIDropDownMenuTemplate")
	pDrop:SetPoint("TOPLEFT", 0, -10)
	UIDropDownMenu_SetWidth(150, pDrop)
	UIDropDownMenu_Initialize(pDrop, function()
		local curr = GetRealZoneText()
		local info = {}
		info.text = curr
		info.func = function()
			UIDropDownMenu_SetSelectedID(pDrop, this:GetID())
			if TankMark.LoadProfileToCache then
				TankMark:LoadProfileToCache()
			end
			if TankMark.UpdateProfileList then
				TankMark:UpdateProfileList()
			end
		end
		UIDropDownMenu_AddButton(info)
		for zName, _ in _pairs(TankMarkProfileDB) do
			if zName ~= curr then
				info = {}
				info.text = zName
				info.func = function()
					UIDropDownMenu_SetSelectedID(pDrop, this:GetID())
					if TankMark.LoadProfileToCache then
						TankMark:LoadProfileToCache()
					end
					if TankMark.UpdateProfileList then
						TankMark:UpdateProfileList()
					end
				end
				UIDropDownMenu_AddButton(info)
			end
		end
	end)
	UIDropDownMenu_SetText(GetRealZoneText(), pDrop)
	TankMark.profileZoneDropdown = pDrop
	
	-- Column Headers
	local ph1 = t2:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
	ph1:SetText("Icon")
	ph1:SetPoint("TOPLEFT", 20, -45)
	local ph2 = t2:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
	ph2:SetText("Assigned Tank")
	ph2:SetPoint("TOPLEFT", 60, -45)
	local ph3 = t2:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
	ph3:SetText("Assigned Healers")
	ph3:SetPoint("TOPLEFT", 220, -45)
	local ph4 = t2:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
	ph4:SetText("Priority")
	ph4:SetPoint("TOPRIGHT", -30, -45)
	
	-- Scroll Frame
	local psf = CreateFrame("ScrollFrame", "TankMarkProfileScroll", t2, "FauxScrollFrameTemplate")
	psf:SetPoint("TOPLEFT", 10, -60)
	psf:SetWidth(380)
	psf:SetHeight(270)
	local plistBg = CreateFrame("Frame", nil, t2)
	plistBg:SetPoint("TOPLEFT", psf, -5, 5)
	plistBg:SetPoint("BOTTOMRIGHT", psf, 25, -5)
	plistBg:SetBackdrop({
		bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true,
		tileSize = 16,
		edgeSize = 16,
		insets = {left = 4, right = 4, top = 4, bottom = 4}
	})
	plistBg:SetBackdropColor(0, 0, 0, 0.5)
	psf:SetScript("OnVerticalScroll", function()
		FauxScrollFrame_OnVerticalScroll(44, function() TankMark:UpdateProfileList() end)
	end)
	TankMark.profileScroll = psf
	
	-- Profile Rows
	for i = 1, 8 do
		local row = CreateFrame("Frame", nil, t2)
		row:SetWidth(380)
		row:SetHeight(44)
		row:SetPoint("TOPLEFT", 10, -60 - ((i-1)*44))
		
		-- Icon Button
		local ibtn = CreateFrame("Button", "TMProfileRowIcon"..i, row)
		ibtn:SetWidth(24)
		ibtn:SetHeight(24)
		ibtn:SetPoint("LEFT", 5, 0)
		local itex = ibtn:CreateTexture(nil, "ARTWORK")
		itex:SetAllPoints()
		ibtn:SetNormalTexture(itex)
		row.iconTex = itex
		local idrop = CreateFrame("Frame", "TMProfileRowIconMenu"..i, ibtn, "UIDropDownMenuTemplate")
		ibtn:SetScript("OnClick", function()
			UIDropDownMenu_Initialize(idrop, function()
				TankMark:InitProfileIconMenu(idrop, row.index)
			end, "MENU")
			ToggleDropDownMenu(1, nil, idrop, "cursor", 0, 0)
		end)
		
		-- Tank Edit Box
		local teb = TankMark:CreateEditBox(row, "", 120)
		teb:SetPoint("LEFT", ibtn, "RIGHT", 10, 0)
		row.tankEdit = teb
		teb:SetScript("OnTextChanged", function()
			if row.index and TankMark.profileCache[row.index] then
				TankMark.profileCache[row.index].tank = this:GetText()
			end
		end)
		
		-- Target Button
		local tbtn = CreateFrame("Button", "TMProfileRowTarget"..i, row, "UIPanelButtonTemplate")
		tbtn:SetWidth(30)
		tbtn:SetHeight(20)
		tbtn:SetPoint("LEFT", teb, "RIGHT", 2, 0)
		tbtn:SetText("T")
		tbtn:SetScript("OnClick", function()
			if UnitExists("target") then
				teb:SetText(UnitName("target"))
			end
		end)
		
		-- Healer Edit Box
		local heb = TankMark:CreateEditBox(row, "", 120)
		heb:SetPoint("LEFT", tbtn, "RIGHT", 10, 0)
		row.healEdit = heb
		heb:SetScript("OnTextChanged", function()
			if row.index and TankMark.profileCache[row.index] then
				TankMark.profileCache[row.index].healers = this:GetText()
			end
		end)
		
		-- Up Button
		local up = CreateFrame("Button", "TMProfileRowUp"..i, row, "UIPanelButtonTemplate")
		up:SetWidth(20)
		up:SetHeight(20)
		up:SetPoint("TOPRIGHT", row, "TOPRIGHT", -30, -2)
		up:SetText("↑")
		up:SetScript("OnClick", function()
			TankMark:ProfileMoveRow(row.index, -1)
		end)
		row.upBtn = up
		
		-- Down Button
		local dn = CreateFrame("Button", "TMProfileRowDown"..i, row, "UIPanelButtonTemplate")
		dn:SetWidth(20)
		dn:SetHeight(20)
		dn:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -30, 2)
		dn:SetText("↓")
		dn:SetScript("OnClick", function()
			TankMark:ProfileMoveRow(row.index, 1)
		end)
		row.downBtn = dn
		
		-- Delete Button
		local del = CreateFrame("Button", "TMProfileRowDel"..i, row, "UIPanelButtonTemplate")
		del:SetWidth(20)
		del:SetHeight(32)
		del:SetPoint("RIGHT", row, "RIGHT", -5, 0)
		del:SetText("X")
		del:SetScript("OnClick", function()
			TankMark:ProfileDeleteRow(row.index)
		end)
		
		TankMark.profileRows[i] = row
		row:Hide()
	end
	
	-- Bottom Buttons
	local addBtn = CreateFrame("Button", "TMProfileAddBtn", t2, "UIPanelButtonTemplate")
	addBtn:SetWidth(90)
	addBtn:SetHeight(24)
	addBtn:SetPoint("BOTTOMLEFT", 10, 15)
	addBtn:SetText("Add Mark")
	addBtn:SetScript("OnClick", function()
		TankMark:ProfileAddRow()
	end)
	
	local templateBtn = CreateFrame("Button", "TMProfileTemplateBtn", t2, "UIPanelButtonTemplate")
	templateBtn:SetWidth(100)
	templateBtn:SetHeight(24)
	templateBtn:SetPoint("LEFT", addBtn, "RIGHT", 5, 0)
	templateBtn:SetText("Load Template")
	templateBtn:SetScript("OnClick", function()
		TankMark:ShowTemplateMenu()
	end)
	
	local copyBtn = CreateFrame("Button", "TMProfileCopyBtn", t2, "UIPanelButtonTemplate")
	copyBtn:SetWidth(90)
	copyBtn:SetHeight(24)
	copyBtn:SetPoint("LEFT", templateBtn, "RIGHT", 5, 0)
	copyBtn:SetText("Copy From...")
	copyBtn:SetScript("OnClick", function()
		TankMark:ShowCopyProfileDialog()
	end)
	
	local resetPBtn = CreateFrame("Button", "TMProfileResetBtn", t2, "UIPanelButtonTemplate")
	resetPBtn:SetWidth(80)
	resetPBtn:SetHeight(24)
	resetPBtn:SetPoint("BOTTOMRIGHT", -110, 15)
	resetPBtn:SetText("Reset")
	resetPBtn:SetScript("OnClick", function()
		TankMark:RequestResetProfile()
	end)
	
	local savePBtn = CreateFrame("Button", "TMProfileSaveBtn", t2, "UIPanelButtonTemplate")
	savePBtn:SetWidth(100)
	savePBtn:SetHeight(24)
	savePBtn:SetPoint("BOTTOMRIGHT", -10, 15)
	savePBtn:SetText("Save Profile")
	savePBtn:SetScript("OnClick", function()
		TankMark:SaveProfileCache()
	end)
	
	return t2
end
