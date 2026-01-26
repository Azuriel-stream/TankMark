-- TankMark: v0.23
-- File: TankMark_Config_Mobs_UI.lua
-- UI construction for Mobs tab

if not TankMark then return end

-- ==========================================================
-- LOCALIZATIONS
-- ==========================================================
local _pairs = pairs
local _getn = table.getn

-- ==========================================================
-- UI CONSTRUCTION HELPERS
-- ==========================================================

-- Create zone dropdown
local function CreateZoneControls(parent)
	-- Zone Dropdown
	local drop = CreateFrame("Frame", "TMZoneDropDown", parent, "UIDropDownMenuTemplate")
	drop:SetPoint("TOPLEFT", 0, -10)
	UIDropDownMenu_SetWidth(150, drop)

	UIDropDownMenu_Initialize(drop, function()
		local curr = GetRealZoneText()
		local info = {}

		-- Current zone first
		info.text = curr
		info.func = function()
			local previousZone = UIDropDownMenu_GetText(TankMark.zoneDropDown)
			UIDropDownMenu_SetSelectedID(drop, this:GetID())

			if previousZone ~= curr then
				TankMark:ResetEditor()
			end
			TankMark:UpdateMobList()
		end
		UIDropDownMenu_AddButton(info)

		-- All other saved zones
		for zName, _ in _pairs(TankMarkDB.Zones) do
			if zName ~= curr then
				info = {}
				info.text = zName
				info.func = function()
					local previousZone = UIDropDownMenu_GetText(TankMark.zoneDropDown)
					UIDropDownMenu_SetSelectedID(drop, this:GetID())

					if previousZone ~= zName then
						TankMark:ResetEditor()
					end
					TankMark:UpdateMobList()
				end
				UIDropDownMenu_AddButton(info)
			end
		end
	end)

	UIDropDownMenu_SetText(GetRealZoneText(), drop)
	TankMark.zoneDropDown = drop

	-- Manage Zones Checkbox
	local mzCheck = CreateFrame("CheckButton", "TMManageZonesCheck", parent, "UICheckButtonTemplate")
	mzCheck:SetWidth(24)
	mzCheck:SetHeight(24)
	mzCheck:SetPoint("LEFT", drop, "RIGHT", 10, 2)
	getglobal(mzCheck:GetName().."Text"):SetText("Manage Zones")
	mzCheck:SetScript("OnClick", function()
		TankMark:ToggleZoneBrowser()
		PlaySound("igMainMenuOptionCheckBoxOn")
	end)
	TankMark.zoneModeCheck = mzCheck

	-- Add Zone Button
	local addZoneBtn = CreateFrame("Button", "TMAddZoneBtn", parent, "UIPanelButtonTemplate")
	addZoneBtn:SetWidth(80)
	addZoneBtn:SetHeight(24)
	addZoneBtn:SetPoint("TOPLEFT", drop, "TOPRIGHT", 130, -2)
	addZoneBtn:SetText("Add Zone")
	addZoneBtn:SetScript("OnClick", function()
		TankMark:ShowAddCurrentZoneDialog()
	end)

	return drop
end

-- Create mob list scroll frame
local function CreateMobList(parent)
	local sf = CreateFrame("ScrollFrame", "TankMarkScrollFrame", parent, "FauxScrollFrameTemplate")
	sf:SetPoint("TOPLEFT", 10, -50)
	sf:SetWidth(380)
	sf:SetHeight(132) -- 6 rows * 22px

	local listBg = CreateFrame("Frame", nil, parent)
	listBg:SetPoint("TOPLEFT", sf, -5, 5)
	listBg:SetPoint("BOTTOMRIGHT", sf, 25, -5)
	listBg:SetBackdrop({
		bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true, tileSize = 16, edgeSize = 16,
		insets = { left = 4, right = 4, top = 4, bottom = 4 }
	})
	listBg:SetBackdropColor(0, 0, 0, 0.5)

	sf:SetScript("OnVerticalScroll", function()
		FauxScrollFrame_OnVerticalScroll(22, function() TankMark:UpdateMobList() end)
	end)

	TankMark.scrollFrame = sf

	-- Create 6 mob rows
	for i = 1, 6 do
		local row = CreateFrame("Button", "TMMobRow"..i, parent)
		row:SetWidth(380)
		row:SetHeight(22)
		row:SetPoint("TOPLEFT", 10, -50 - (i-1)*22)

		row.icon = row:CreateTexture(nil, "ARTWORK")
		row.icon:SetWidth(18)
		row.icon:SetHeight(18)
		row.icon:SetPoint("LEFT", 0, 0)

		row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		row.text:SetPoint("LEFT", row.icon, "RIGHT", 5, 0)

		row.del = CreateFrame("Button", "TMMobRowDel"..i, row, "UIPanelButtonTemplate")
		row.del:SetWidth(20)
		row.del:SetHeight(18)
		row.del:SetPoint("RIGHT", -5, 0)
		row.del:SetText("X")

		row.edit = CreateFrame("Button", "TMMobRowEdit"..i, row, "UIPanelButtonTemplate")
		row.edit:SetWidth(20)
		row.edit:SetHeight(18)
		row.edit:SetPoint("RIGHT", row.del, "LEFT", -2, 0)
		row.edit:SetText("E")

		row:Hide()
		TankMark.mobRows[i] = row
	end

	return sf
end

-- Create search box
local function CreateSearchBox(parent, listBg)
	local searchLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	searchLabel:SetPoint("TOPLEFT", listBg, "BOTTOMLEFT", 5, -8)
	searchLabel:SetText("Search:")

	local sBox = TankMark:CreateEditBox(parent, "", 150)
	sBox:SetPoint("LEFT", searchLabel, "RIGHT", 8, 0)
	sBox:SetScript("OnTextChanged", function()
		TankMark:UpdateMobList()
	end)
	TankMark.searchBox = sBox

	local sClear = CreateFrame("Button", "TMBSearchClear", sBox, "UIPanelCloseButton")
	sClear:SetWidth(20)
	sClear:SetHeight(20)
	sClear:SetPoint("LEFT", sBox, "RIGHT", 2, 0)
	sClear:SetScript("OnClick", function()
		sBox:SetText("")
		sBox:ClearFocus()
		TankMark:UpdateMobList()
	end)

	return sBox
end

-- Create accordion header
local function CreateAccordionHeader(parent, yOffset)
	local divider = parent:CreateTexture(nil, "ARTWORK")
	divider:SetHeight(1)
	divider:SetWidth(380)
	divider:SetPoint("TOPLEFT", 10, yOffset)
	divider:SetTexture(1, 1, 1, 0.2)

	local header = CreateFrame("Button", "TMAddMobHeader", parent)
	header:SetWidth(200)
	header:SetHeight(20)
	header:SetPoint("TOPLEFT", 10, yOffset - 10)

	header.arrow = header:CreateTexture(nil, "ARTWORK")
	header.arrow:SetWidth(16)
	header.arrow:SetHeight(16)
	header.arrow:SetPoint("LEFT", 0, 0)
	header.arrow:SetTexture("Interface\\Buttons\\UI-PlusButton-Up")

	header.text = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	header.text:SetPoint("LEFT", header.arrow, "RIGHT", 5, 0)
	header.text:SetText("|cff00ccffAdd a mob manually|r")

	header:SetScript("OnEnter", function()
		this.text:SetTextColor(0, 1, 1)
	end)

	header:SetScript("OnLeave", function()
		this.text:SetTextColor(0, 0.8, 1)
	end)

	header:SetScript("OnClick", function()
		if TankMark.isAddMobExpanded then
			TankMark.addMobInterface:Hide()
			header.arrow:SetTexture("Interface\\Buttons\\UI-PlusButton-Up")
			TankMark.isAddMobExpanded = false
		else
			TankMark.addMobInterface:Show()
			header.arrow:SetTexture("Interface\\Buttons\\UI-MinusButton-Up")
			TankMark.isAddMobExpanded = true
		end
	end)

	TankMark.addMobHeader = header
	return header
end

-- Create mob editor interface
local function CreateMobEditor(parent, header)
	local editor = CreateFrame("Frame", nil, parent)
	editor:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 20, -5)
	editor:SetWidth(380)
	editor:SetHeight(120)
	editor:Hide()

	TankMark.addMobInterface = editor

	-- Mob Name Input
	local nameBox = TankMark:CreateEditBox(editor, "Mob Name", 180)
	nameBox:SetPoint("TOPLEFT", 0, -5)
	TankMark.editMob = nameBox

	nameBox:SetScript("OnTextChanged", function()
		local text = this:GetText()
		if text and text ~= "" and text ~= "Mob Name" then
			if TankMark.saveBtn then
				TankMark.saveBtn:Enable()
			end

			if TankMark:HasGUIDLockForMobName(text) and TankMark.addMoreMarksText then
				TankMark.addMoreMarksText:SetTextColor(0.5, 0.5, 0.5)
				if TankMark.addMoreMarksBtn then
					TankMark.addMoreMarksBtn:Disable()
				end
			elseif TankMark.addMoreMarksText and TankMark.addMoreMarksText:IsVisible() then
				TankMark.addMoreMarksText:SetTextColor(0, 0.8, 1)
				if TankMark.addMoreMarksBtn then
					TankMark.addMoreMarksBtn:Enable()
				end
			end
		else
			if TankMark.saveBtn then
				TankMark.saveBtn:Disable()
			end
		end
	end)

	-- Target Button
	local targetBtn = CreateFrame("Button", "TMTargetBtn", editor, "UIPanelButtonTemplate")
	targetBtn:SetWidth(60)
	targetBtn:SetHeight(20)
	targetBtn:SetPoint("LEFT", nameBox, "RIGHT", 5, 0)
	targetBtn:SetText("Target")
	targetBtn:SetScript("OnClick", function()
		if UnitExists("target") then
			nameBox:SetText(UnitName("target"))
			TankMark.detectedCreatureType = UnitCreatureType("target")

			local currentIcon = GetRaidTargetIndex("target")
			if currentIcon then
				TankMark.selectedIcon = currentIcon
				if TankMark.iconBtn and TankMark.iconBtn.tex then
					TankMark:SetIconTexture(TankMark.iconBtn.tex, currentIcon)
				end
			end

			if TankMark.lockBtn then TankMark.lockBtn:Enable() end
			if TankMark.saveBtn then TankMark.saveBtn:Enable() end
		end
	end)

	return editor
end

-- Create icon/priority/CC controls
local function CreateEditorControls(editor)
	local row2Top = -40

	-- Icon Selector
	local iconSel = CreateFrame("Button", nil, editor)
	iconSel:SetWidth(24)
	iconSel:SetHeight(24)
	iconSel:SetPoint("TOPLEFT", 0, row2Top)

	local iconTex = iconSel:CreateTexture(nil, "ARTWORK")
	iconTex:SetAllPoints()
	iconSel.tex = iconTex
	iconTex:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
	TankMark:SetIconTexture(iconTex, TankMark.selectedIcon)

	local iconDrop = CreateFrame("Frame", "TMIconDropDown", iconSel, "UIDropDownMenuTemplate")
	UIDropDownMenu_Initialize(iconDrop, function() TankMark:InitIconMenu() end, "MENU")
	iconSel:SetScript("OnClick", function()
		ToggleDropDownMenu(1, nil, iconDrop, "cursor", 0, 0)
	end)
	TankMark.iconBtn = iconSel

	-- Priority Input + Spinner
	local prioBox = TankMark:CreateEditBox(editor, "Prio", 30)
	prioBox:SetPoint("LEFT", iconSel, "RIGHT", 10, 0)
	prioBox:SetText("1")
	prioBox:SetNumeric(true)
	TankMark.editPrio = prioBox

	local prioUp = CreateFrame("Button", nil, editor)
	prioUp:SetWidth(16)
	prioUp:SetHeight(12)
	prioUp:SetPoint("LEFT", prioBox, "RIGHT", 2, 6)
	prioUp:SetNormalTexture("Interface\\Buttons\\UI-ScrollBar-ScrollUpButton-Up")
	prioUp:SetScript("OnClick", function()
		local current = tonumber(prioBox:GetText()) or 1
		prioBox:SetText(math.min(current + 1, 9))
	end)

	local prioDown = CreateFrame("Button", nil, editor)
	prioDown:SetWidth(16)
	prioDown:SetHeight(12)
	prioDown:SetPoint("LEFT", prioBox, "RIGHT", 2, -6)
	prioDown:SetNormalTexture("Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Up")
	prioDown:SetScript("OnClick", function()
		local current = tonumber(prioBox:GetText()) or 1
		prioBox:SetText(math.max(current - 1, 1))
	end)

	-- CC Button
	local cBtn = CreateFrame("Button", "TMClassBtn", editor, "UIPanelButtonTemplate")
	cBtn:SetWidth(90)
	cBtn:SetHeight(20)
	cBtn:SetPoint("LEFT", prioDown, "RIGHT", 10, 0)
	cBtn:SetText("No CC (Kill)")

	local cDrop = CreateFrame("Frame", "TMClassDropDown", cBtn, "UIDropDownMenuTemplate")
	UIDropDownMenu_Initialize(cDrop, function() TankMark:InitClassMenu() end, "MENU")
	cBtn:SetScript("OnClick", function()
		ToggleDropDownMenu(1, nil, cDrop, "cursor", 0, 0)
	end)
	TankMark.classBtn = cBtn

	-- Lock Button
	local lBtn = CreateFrame("Button", "TMLockBtn", editor, "UIPanelButtonTemplate")
	lBtn:SetWidth(75)
	lBtn:SetHeight(20)
	lBtn:SetPoint("LEFT", cBtn, "RIGHT", 5, 0)
	lBtn:SetText("Lock Mark")
	lBtn:SetScript("OnClick", function() TankMark:ToggleLockState() end)
	lBtn:Disable()

	lBtn:SetScript("OnEnter", function()
		if not this:IsEnabled() and _getn(TankMark.editingSequentialMarks) > 0 then
			GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
			GameTooltip:SetText("GUID locking is unavailable for mobs with sequential marks. Remove all sequential marks to enable locking.", 1, 1, 1, 1, true)
			GameTooltip:Show()
		end
	end)

	lBtn:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)

	TankMark.lockBtn = lBtn

	-- Save Button
	local saveBtn = CreateFrame("Button", "TMSaveBtn", editor, "UIPanelButtonTemplate")
	saveBtn:SetWidth(50)
	saveBtn:SetHeight(20)
	saveBtn:SetPoint("LEFT", lBtn, "RIGHT", 5, 0)
	saveBtn:SetText("Save")
	saveBtn:SetScript("OnClick", function() TankMark:SaveFormData() end)
	saveBtn:Disable()
	TankMark.saveBtn = saveBtn

	-- Cancel Button
	local cancelBtn = CreateFrame("Button", "TMCancelBtn", editor, "UIPanelButtonTemplate")
	cancelBtn:SetWidth(20)
	cancelBtn:SetHeight(20)
	cancelBtn:SetPoint("LEFT", saveBtn, "RIGHT", 2, 0)
	cancelBtn:SetText("X")
	cancelBtn:SetScript("OnClick", function() TankMark:ResetEditor() end)
	cancelBtn:Hide()
	TankMark.cancelBtn = cancelBtn
end

-- Create sequential marks UI
local function CreateSequentialMarksUI(editor, nameBox)
	-- Divider Label
	local seqLabel = editor:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	seqLabel:SetPoint("TOPLEFT", 0, -60)
	seqLabel:SetText("|cff888888Marking Sequence|r")

	-- Add More Marks Text
	local addMoreText = editor:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	addMoreText:SetPoint("TOPLEFT", seqLabel, "BOTTOMLEFT", 0, -5)
	addMoreText:SetText("|cff00ccff+ Add More Marks|r")
	addMoreText:Show()
	TankMark.addMoreMarksText = addMoreText

	-- Clickable button
	local addMoreBtn = CreateFrame("Button", nil, editor)
	addMoreBtn:SetAllPoints(addMoreText)
	addMoreBtn:SetScript("OnClick", function()
		TankMark:OnAddMoreMarksClicked()
	end)

	addMoreBtn:SetScript("OnEnter", function()
		if TankMark:HasGUIDLockForMobName(nameBox:GetText()) then
			GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
			GameTooltip:SetText("Sequential marking is unavailable because this mob has a GUID lock. Remove the GUID lock to enable sequential marks.", 1, 1, 1, 1, true)
			GameTooltip:Show()
		else
			addMoreText:SetTextColor(0, 1, 1)
		end
	end)

	addMoreBtn:SetScript("OnLeave", function()
		GameTooltip:Hide()
		if not TankMark:HasGUIDLockForMobName(nameBox:GetText()) then
			addMoreText:SetTextColor(0, 0.8, 1)
		end
	end)

	TankMark.addMoreMarksBtn = addMoreBtn
	addMoreText.clickFrame = addMoreBtn

	-- Sequential Scroll Frame
	local seqScroll = CreateFrame("ScrollFrame", "TMSeqScrollFrame", editor, "FauxScrollFrameTemplate")
	seqScroll:SetWidth(360)
	seqScroll:SetHeight(72) -- 3 rows * 24px
	seqScroll:SetPoint("TOPLEFT", addMoreText, "BOTTOMLEFT", 0, -5)
	seqScroll:Hide()
	TankMark.sequentialScrollFrame = seqScroll

	local seqContent = CreateFrame("Frame", nil, seqScroll)
	seqContent:SetWidth(360)
	seqContent:SetHeight(168) -- 7 rows * 24px
	seqScroll:SetScrollChild(seqContent)

	seqScroll:SetScript("OnVerticalScroll", function()
		FauxScrollFrame_OnVerticalScroll(24, function() TankMark:RefreshSequentialRows() end)
	end)

	-- Create 7 sequential row frames
	for i = 1, 7 do
		local seqRow = CreateFrame("Frame", "TMSeqRow"..i, seqContent)
		seqRow:SetWidth(340)
		seqRow:SetHeight(24)
		seqRow:SetPoint("TOPLEFT", 0, -(i-1)*24)

		seqRow.number = seqRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		seqRow.number:SetPoint("LEFT", 5, 0)
		seqRow.number:SetText("|cff888888#"..(i+1).."|r")

		seqRow.iconBtn = CreateFrame("Button", nil, seqRow)
		seqRow.iconBtn:SetWidth(24)
		seqRow.iconBtn:SetHeight(20)
		seqRow.iconBtn:SetPoint("LEFT", seqRow.number, "RIGHT", 10, 0)

		seqRow.iconBtn.tex = seqRow.iconBtn:CreateTexture(nil, "ARTWORK")
		seqRow.iconBtn.tex:SetAllPoints()
		seqRow.iconBtn.tex:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
		TankMark:SetIconTexture(seqRow.iconBtn.tex, 8)

		local seqIconDrop = CreateFrame("Frame", "TMSeqIconDrop"..i, seqRow.iconBtn, "UIDropDownMenuTemplate")
		UIDropDownMenu_Initialize(seqIconDrop, function() TankMark:InitSequentialIconMenu(i) end, "MENU")
		seqRow.iconBtn:SetScript("OnClick", function()
			local rowIndex = this:GetParent().dataIndex
			if not rowIndex then return end
			UIDropDownMenu_Initialize(seqIconDrop, function() TankMark:InitSequentialIconMenu(rowIndex) end, "MENU")
			ToggleDropDownMenu(1, nil, seqIconDrop, "cursor", 0, 0)
		end)

		seqRow.ccBtn = CreateFrame("Button", nil, seqRow, "UIPanelButtonTemplate")
		seqRow.ccBtn:SetWidth(90)
		seqRow.ccBtn:SetHeight(20)
		seqRow.ccBtn:SetPoint("LEFT", seqRow.iconBtn, "RIGHT", 10, 0)
		seqRow.ccBtn:SetText("No CC (Kill)")

		local seqClassDrop = CreateFrame("Frame", "TMSeqClassDrop"..i, seqRow.ccBtn, "UIDropDownMenuTemplate")
		UIDropDownMenu_Initialize(seqClassDrop, function() TankMark:InitSequentialClassMenu(i) end, "MENU")
		seqRow.ccBtn:SetScript("OnClick", function()
			local rowIndex = this:GetParent().dataIndex
			if not rowIndex then return end
			UIDropDownMenu_Initialize(seqClassDrop, function() TankMark:InitSequentialClassMenu(rowIndex) end, "MENU")
			ToggleDropDownMenu(1, nil, seqClassDrop, "cursor", 0, 0)
		end)

		seqRow.delBtn = CreateFrame("Button", nil, seqRow, "UIPanelButtonTemplate")
		seqRow.delBtn:SetWidth(20)
		seqRow.delBtn:SetHeight(20)
		seqRow.delBtn:SetPoint("RIGHT", -5, 0)
		seqRow.delBtn:SetText("X")
		seqRow.delBtn:SetScript("OnClick", function()
			TankMark:RemoveSequentialRow(this:GetParent().dataIndex)
		end)

		seqRow:Hide()
		TankMark.sequentialRows[i] = seqRow
	end
end

-- ==========================================================
-- MAIN TAB CREATION FUNCTION
-- ==========================================================

function TankMark:CreateMobTab(parent)
	local t1 = CreateFrame("Frame", nil, parent)
	t1:SetPoint("TOPLEFT", parent, "TOPLEFT", 15, -40)
	t1:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -15, 50)

	-- Create all UI sections
	local zoneDropdown = CreateZoneControls(t1)
	local mobList = CreateMobList(t1)
	local searchBox = CreateSearchBox(t1, t1:GetChildren())

	local header = CreateAccordionHeader(t1, -230)
	local editor = CreateMobEditor(t1, header)
	CreateEditorControls(editor)
	CreateSequentialMarksUI(editor, TankMark.editMob)

	return t1
end
