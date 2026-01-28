-- TankMark: v0.23
-- File: TankMark_Config_Mobs_UI.lua
-- UI construction for Mobs tab (Wireframe v2 Layout)

if not TankMark then return end

-- ==========================================================
-- LOCALIZATIONS
-- ==========================================================
local _pairs = pairs
local _getn = table.getn

-- ==========================================================
-- UI CONSTRUCTION HELPERS
-- ==========================================================

-- Create horizontal divider line
local function CreateHorizontalDivider(parent, width)
	local line = parent:CreateTexture(nil, "ARTWORK")
	line:SetTexture(1, 1, 1, 0.2)
	line:SetHeight(1)
	line:SetWidth(width)
	return line
end

-- Create vertical divider line
local function CreateVerticalDivider(parent, height)
	local line = parent:CreateTexture(nil, "ARTWORK")
	line:SetTexture(1, 1, 1, 0.2)
	line:SetWidth(1)
	line:SetHeight(height)
	return line
end

-- Create small button (for E, X, etc)
local function CreateSmallButton(parent, width, text)
	local btn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	btn:SetWidth(width)
	btn:SetHeight(18)
	btn:SetText(text)
	return btn
end

-- ==========================================================
-- TOP SECTION: ZONE CONTROLS (Right-aligned)
-- ==========================================================
local function CreateZoneControls(parent)
	-- Zone Dropdown (wireframe: canvas offset x=101, y=43, w=190, h=32)
	-- Note: UIDropDownMenu has ~15px left padding, so we compensate
	local drop = CreateFrame("Frame", "TMZoneDropDown", parent, "UIDropDownMenuTemplate")
	drop:SetPoint("TOPLEFT", parent, "TOPLEFT", 44, -43)
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
				TankMark:ResetEditorState()
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
						TankMark:ResetEditorState()
					end
					TankMark:UpdateMobList()
				end
				UIDropDownMenu_AddButton(info)
			end
		end
	end)
	
	UIDropDownMenu_SetText(GetRealZoneText(), drop)
	TankMark.zoneDropDown = drop
	
	-- Manage Zones Checkbox (wireframe: absolute x=300, y=47, w=120, h=24)
	local mzCheck = CreateFrame("CheckButton", "TMManageZonesCheck", parent, "UICheckButtonTemplate")
	mzCheck:SetWidth(24)
	mzCheck:SetHeight(24)
	mzCheck:SetPoint("TOPLEFT", parent, "TOPLEFT", 243, -45)
	
	local checkLabel = getglobal(mzCheck:GetName().."Text")
	checkLabel:SetText("Manage Zones")
	checkLabel:ClearAllPoints()
	checkLabel:SetPoint("LEFT", mzCheck, "RIGHT", 2, 0)
	
	mzCheck:SetScript("OnClick", function()
		TankMark:ToggleZoneBrowser()
		PlaySound("igMainMenuOptionCheckBoxOn")
	end)
	TankMark.zoneModeCheck = mzCheck
	
	-- Add Zone Button (wireframe: absolute x=430, y=47, w=80, h=24)
	local addZoneBtn = CreateFrame("Button", "TMAddZoneBtn", parent, "UIPanelButtonTemplate")
	addZoneBtn:SetWidth(80)
	addZoneBtn:SetHeight(24)
	addZoneBtn:SetPoint("TOPLEFT", parent, "TOPLEFT", 372, -45)
	addZoneBtn:SetText("Add Zone")
	addZoneBtn:SetScript("OnClick", function()
		TankMark:ShowAddCurrentZoneDialog()
	end)
	
	return drop
end

-- ==========================================================
-- CENTER SECTION: MOB LIST
-- ==========================================================
local function CreateMobList(parent)
	-- Mob List Background (wireframe: x=95, y=79, w=410, h=147)
	local listBg = CreateFrame("Frame", nil, parent)
	listBg:SetPoint("TOPLEFT", parent, "TOPLEFT", 31, -79)
	listBg:SetWidth(457)
	listBg:SetHeight(147)
	listBg:SetBackdrop({
		bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true, tileSize = 16, edgeSize = 16,
		insets = { left = 4, right = 4, top = 4, bottom = 4 }
	})
	listBg:SetBackdropColor(0, 0, 0, 0.5)
	
	-- Mob List Scroll Frame (wireframe: x=100, y=84, w=380, h=132)
	local sf = CreateFrame("ScrollFrame", "TankMarkScrollFrame", listBg, "FauxScrollFrameTemplate")
	sf:SetPoint("TOPLEFT", 5, -5)
	sf:SetWidth(426)
	sf:SetHeight(138)
	sf:SetScript("OnVerticalScroll", function()
		FauxScrollFrame_OnVerticalScroll(22, function() TankMark:UpdateMobList() end)
	end)
	TankMark.scrollFrame = sf
	
	-- Create 6 mob rows (wireframe: y=10/32/54/76/98/120, h=20 each)
	for i = 1, 6 do
		local row = CreateFrame("Button", "TMMobRow"..i, listBg)
		row:SetWidth(416)
		row:SetHeight(20)
		row:SetPoint("TOPLEFT", 10, -10 - (i-1)*22)
		
		row.icon = row:CreateTexture(nil, "ARTWORK")
		row.icon:SetWidth(16)
		row.icon:SetHeight(16)
		row.icon:SetPoint("LEFT", 2, 0)
		
		row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		row.text:SetPoint("LEFT", row.icon, "RIGHT", 4, 0)
		row.text:SetWidth(280)
		row.text:SetJustifyH("LEFT")
		
		row.edit = CreateSmallButton(row, 20, "E")
		row.edit:SetPoint("RIGHT", -24, 0)
		
		row.del = CreateSmallButton(row, 20, "X")
		row.del:SetPoint("RIGHT", -2, 0)
		
		row:Hide()
		TankMark.mobRows[i] = row
	end
	
	return sf, listBg
end

-- ==========================================================
-- SEARCH BOX (Below Mob List, Centered with Placeholder)
-- ==========================================================
local function CreateSearchBox(parent, listBg)
	-- Search Input with placeholder text (centered, no label)
	local sBox = TankMark:CreateEditBox(parent, "", 200)
	sBox:SetPoint("TOPLEFT", parent, "TOPLEFT", 170, -236)
	sBox:SetText("Search Mob Database")
	sBox:SetTextColor(0.5, 0.5, 0.5)
	
	sBox:SetScript("OnEditFocusGained", function()
		if this:GetText() == "Search Mob Database" then
			this:SetText("")
			this:SetTextColor(1, 1, 1)
		end
	end)
	
	sBox:SetScript("OnEditFocusLost", function()
		if this:GetText() == "" then
			this:SetText("Search Mob Database")
			this:SetTextColor(0.5, 0.5, 0.5)
		end
	end)
	
	sBox:SetScript("OnTextChanged", function()
		if this:GetText() ~= "Search Mob Database" then
			TankMark:UpdateMobList()
		end
	end)
	TankMark.searchBox = sBox
	
	-- Clear Button
	local sClear = CreateFrame("Button", "TMBSearchClear", parent, "UIPanelCloseButton")
	sClear:SetWidth(20)
	sClear:SetHeight(20)
	sClear:SetPoint("TOPLEFT", parent, "TOPLEFT", 375, -236)
	sClear:SetScript("OnClick", function()
		sBox:SetText("Search Mob Database")
		sBox:SetTextColor(0.5, 0.5, 0.5)
		sBox:ClearFocus()
		TankMark:UpdateMobList()
	end)
	
	return sBox
end

-- ==========================================================
-- HORIZONTAL DIVIDER (Between Search and Accordions)
-- ==========================================================
local function CreateMainDivider(parent)
	local divider = CreateHorizontalDivider(parent, 457)
	divider:SetPoint("TOPLEFT", parent, "TOPLEFT", 31, -266)
	return divider
end

-- ==========================================================
-- VERTICAL DIVIDER (Between Left and Right Columns)
-- ==========================================================
local function CreateColumnDivider(parent)
	local divider = CreateVerticalDivider(parent, 147)
	divider:SetPoint("TOPLEFT", parent, "TOPLEFT", 259, -276)
	return divider
end

-- ==========================================================
-- LEFT COLUMN: ADD MOB MANUALLY (Accordion)
-- ==========================================================
local function CreateMobEditorAccordion(parent)
	-- Accordion Header (wireframe: x=16, y=284, w=260, h=20.8)
	local header = CreateFrame("Button", "TMAddMobHeader", parent)
	header:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, -284)
	header:SetWidth(238)
	header:SetHeight(21)
	
	-- Arrow texture
	header.arrow = header:CreateTexture(nil, "ARTWORK")
	header.arrow:SetWidth(16)
	header.arrow:SetHeight(16)
	header.arrow:SetPoint("LEFT", 0, 0)
	header.arrow:SetTexture("Interface\\Buttons\\UI-PlusButton-Up")
	
	-- Header text
	header.text = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	header.text:SetPoint("LEFT", header.arrow, "RIGHT", 5, 0)
	header.text:SetText("Add a mob manually")
	header.text:SetTextColor(0, 0.8, 1)
	
	-- Entire header is clickable (toggle expand/collapse)
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
	
	-- Header text hover effects
	header:SetScript("OnEnter", function()
		header.text:SetTextColor(0, 1, 1)
	end)
	
	header:SetScript("OnLeave", function()
		header.text:SetTextColor(0, 0.8, 1)
	end)
	
	TankMark.addMobHeader = header
	
	-- Editor Interface Frame (wireframe: x=16, y=313, w=260, h=120)
	local editor = CreateFrame("Frame", nil, parent)
	editor:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, -313)
	editor:SetWidth(238)
	editor:SetHeight(114)
	editor:SetBackdrop({
		bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true, tileSize = 16, edgeSize = 16,
		insets = { left = 4, right = 4, top = 4, bottom = 4 }
	})
	editor:SetBackdropColor(0.1, 0.1, 0.1, 0.8)
	editor:Hide() -- Start collapsed
	
	TankMark.addMobInterface = editor
	
	return editor
end

-- ==========================================================
-- MOB EDITOR CONTROLS (Inside Accordion)
-- ==========================================================
local function CreateMobEditorControls(editor)
	-- Mob Name Input with placeholder text
	local nameBox = TankMark:CreateEditBox(editor, "", 154)
	nameBox:SetPoint("TOPLEFT", 10, -8)
	nameBox:SetText("Mob Name")
	nameBox:SetTextColor(0.5, 0.5, 0.5)
	
	nameBox:SetScript("OnEditFocusGained", function()
		if this:GetText() == "Mob Name" then
			this:SetText("")
			this:SetTextColor(1, 1, 1)
		end
	end)
	
	nameBox:SetScript("OnEditFocusLost", function()
		if this:GetText() == "" then
			this:SetText("Mob Name")
			this:SetTextColor(0.5, 0.5, 0.5)
		end
	end)
	
	TankMark.editMob = nameBox
	
	nameBox:SetScript("OnTextChanged", function()
		local text = this:GetText()
		if text and text ~= "" and text ~= "Mob Name" then
			if TankMark.saveBtn then
				TankMark.saveBtn:Enable()
			end
			
			-- Check GUID lock conflict
			if TankMark:HasGUIDLockForMobName(text) and TankMark.addMoreMarksText then
				TankMark.addMoreMarksText:SetTextColor(0.5, 0.5, 0.5)
				if TankMark.addMoreMarksArrow then
					TankMark.addMoreMarksArrow:Disable()
				end
			elseif TankMark.addMoreMarksText and TankMark.isSequentialActive then
				TankMark.addMoreMarksText:SetTextColor(0, 0.8, 1)
				if TankMark.addMoreMarksArrow then
					TankMark.addMoreMarksArrow:Enable()
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
	targetBtn:SetPoint("TOPLEFT", 169, -8)
	targetBtn:SetText("Target")
	targetBtn:SetScript("OnClick", function()
		if UnitExists("target") then
			nameBox:SetText(UnitName("target"))
			nameBox:SetTextColor(1, 1, 1)
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
			
			-- Activate sequential accordion (allows adding marks to new mob)
			TankMark:ActivateSequentialAccordion(false)
		end
	end)
	
	-- Icon Selector
	local iconSel = CreateFrame("Button", nil, editor)
	iconSel:SetWidth(24)
	iconSel:SetHeight(24)
	iconSel:SetPoint("TOPLEFT", 10, -41)
	
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
	
	-- Priority Input
	local prioBox = TankMark:CreateEditBox(editor, "   Prio", 30)
	prioBox:SetPoint("TOPLEFT", 39, -43)
	prioBox:SetText("1")
	prioBox:SetNumeric(true)
	TankMark.editPrio = prioBox
	
	-- Priority Spinner Up
	local prioUp = CreateFrame("Button", nil, editor)
	prioUp:SetWidth(16)
	prioUp:SetHeight(12)
	prioUp:SetPoint("LEFT", prioBox, "RIGHT", 2, 6)
	prioUp:SetNormalTexture("Interface\\Buttons\\UI-ScrollBar-ScrollUpButton-Up")
	prioUp:SetScript("OnClick", function()
		local current = tonumber(prioBox:GetText()) or 1
		prioBox:SetText(math.min(current + 1, 9))
	end)
	
	-- Priority Spinner Down
	local prioDown = CreateFrame("Button", nil, editor)
	prioDown:SetWidth(16)
	prioDown:SetHeight(12)
	prioDown:SetPoint("LEFT", prioBox, "RIGHT", 2, -6)
	prioDown:SetNormalTexture("Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Up")
	prioDown:SetScript("OnClick", function()
		local current = tonumber(prioBox:GetText()) or 1
		prioBox:SetText(math.max(current - 1, 1))
	end)
	
	-- CC Class Button
	local cBtn = CreateFrame("Button", "TMClassBtn", editor, "UIPanelButtonTemplate")
	cBtn:SetWidth(70)
	cBtn:SetHeight(20)
	cBtn:SetPoint("TOPLEFT", 87, -43)
	cBtn:SetText("No CC")
	
	local cDrop = CreateFrame("Frame", "TMClassDropDown", cBtn, "UIDropDownMenuTemplate")
	UIDropDownMenu_Initialize(cDrop, function() TankMark:InitClassMenu() end, "MENU")
	
	cBtn:SetScript("OnClick", function()
		ToggleDropDownMenu(1, nil, cDrop, "cursor", 0, 0)
	end)
	TankMark.classBtn = cBtn
	
	-- Lock Button
	local lBtn = CreateFrame("Button", "TMLockBtn", editor, "UIPanelButtonTemplate")
	lBtn:SetWidth(70)
	lBtn:SetHeight(20)
	lBtn:SetPoint("TOPLEFT", 160, -43)
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
	saveBtn:SetPoint("TOPLEFT", 60, -81)
	saveBtn:SetText("Save")
	saveBtn:SetScript("OnClick", function() TankMark:SaveFormData() end)
	saveBtn:Disable()
	TankMark.saveBtn = saveBtn
	
	-- Cancel Button
	local cancelBtn = CreateFrame("Button", "TMCancelBtn", editor, "UIPanelButtonTemplate")
	cancelBtn:SetWidth(50)
	cancelBtn:SetHeight(20)
	cancelBtn:SetPoint("TOPLEFT", 120, -81)
	cancelBtn:SetText("Cancel")
	cancelBtn:SetScript("OnClick", function() TankMark:ResetEditorState() end)
	TankMark.cancelBtn = cancelBtn
end

-- ==========================================================
-- RIGHT COLUMN: ADD MORE MARKS (Accordion)
-- ==========================================================
local function CreateSequentialAccordion(parent)
	-- Accordion Header Container (wireframe: x=305, y=284, w=261, h=20)
	local header = CreateFrame("Frame", "TMAddMoreMarksHeader", parent)
	header:SetPoint("TOPLEFT", parent, "TOPLEFT", 265, -284)
	header:SetWidth(238)
	header:SetHeight(20)
	
	-- Arrow texture
	header.arrow = header:CreateTexture(nil, "ARTWORK")
	header.arrow:SetWidth(16)
	header.arrow:SetHeight(16)
	header.arrow:SetPoint("LEFT", 0, 0)
	header.arrow:SetTexture("Interface\\Buttons\\UI-PlusButton-Up")
	
	-- Header text
	header.text = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	header.text:SetPoint("LEFT", header.arrow, "RIGHT", 5, 0)
	header.text:SetText("Add More Marks")
	header.text:SetTextColor(0.53, 0.53, 0.53)
	
	-- Arrow click button (always toggles expand/collapse)
	local arrowBtn = CreateFrame("Button", nil, header)
	arrowBtn:SetWidth(20)
	arrowBtn:SetHeight(20)
	arrowBtn:SetPoint("LEFT", 0, 0)
	arrowBtn:SetScript("OnClick", function()
		-- Only allow interaction if active
		if not TankMark.isSequentialActive then
			return
		end
		
		if TankMark.isSequentialExpanded then
			-- Collapse
			TankMark.sequentialInterface:Hide()
			header.arrow:SetTexture("Interface\\Buttons\\UI-PlusButton-Up")
			TankMark.isSequentialExpanded = false
			-- Header text returns to GREY when collapsed
			header.text:SetTextColor(0.53, 0.53, 0.53)
		else
			-- Expand
			TankMark.sequentialInterface:Show()
			header.arrow:SetTexture("Interface\\Buttons\\UI-MinusButton-Up")
			TankMark.isSequentialExpanded = true
			-- Header text becomes CYAN when expanded
			header.text:SetTextColor(0, 0.8, 1)
		end
	end)
	arrowBtn:Disable() -- Start disabled
	
	-- Header text click button (expands when collapsed, adds mark when expanded)
	local textBtn = CreateFrame("Button", nil, header)
	textBtn:SetWidth(218) -- 238 - 20 = 218 (leave arrow region exposed)
	textBtn:SetHeight(20)
	textBtn:SetPoint("LEFT", 20, 0)
	textBtn:SetScript("OnClick", function()
		-- Only allow interaction if active
		if not TankMark.isSequentialActive then
			return
		end
		
		-- Check GUID lock first
		if TankMark:HasGUIDLockForMobName(TankMark.editMob and TankMark.editMob:GetText() or "") then
			return
		end
		
		if TankMark.isSequentialExpanded then
			-- When expanded: clicking text ADDS a mark
			TankMark:OnAddMoreMarksClicked()
		else
			-- When collapsed: clicking text EXPANDS
			TankMark.sequentialInterface:Show()
			header.arrow:SetTexture("Interface\\Buttons\\UI-MinusButton-Up")
			TankMark.isSequentialExpanded = true
			header.text:SetTextColor(0, 0.8, 1)
		end
	end)
	
	-- Consolidated hover function
	local function HeaderOnEnter()
		if TankMark:HasGUIDLockForMobName(TankMark.editMob and TankMark.editMob:GetText() or "") then
			GameTooltip:SetOwner(header, "ANCHOR_RIGHT")
			GameTooltip:SetText("Sequential marking is unavailable because this mob has a GUID lock. Remove the GUID lock to enable sequential marks.", 1, 1, 1, 1, true)
			GameTooltip:Show()
		elseif TankMark.isSequentialActive then
			-- Show hover effect when active (regardless of expanded state)
			header.text:SetTextColor(0, 1, 1)
		end
	end
	
	local function HeaderOnLeave()
		GameTooltip:Hide()
		if TankMark.isSequentialActive then
			if TankMark.isSequentialExpanded then
				header.text:SetTextColor(0, 0.8, 1)
			else
				header.text:SetTextColor(0.53, 0.53, 0.53)
			end
		end
	end
	
	-- Apply hover to both arrow and text regions
	arrowBtn:SetScript("OnEnter", HeaderOnEnter)
	arrowBtn:SetScript("OnLeave", HeaderOnLeave)
	textBtn:SetScript("OnEnter", HeaderOnEnter)
	textBtn:SetScript("OnLeave", HeaderOnLeave)
	
	TankMark.addMoreMarksText = header.text
	TankMark.addMoreMarksHeader = header
	TankMark.addMoreMarksArrow = arrowBtn
	
	-- Sequential Interface Frame (wireframe: x=305.5, y=313, w=260.5, h=120)
	local seqFrame = CreateFrame("Frame", nil, parent)
	seqFrame:SetPoint("TOPLEFT", parent, "TOPLEFT", 265, -313)
	seqFrame:SetWidth(238)
	seqFrame:SetHeight(114)
	seqFrame:SetBackdrop({
		bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true, tileSize = 16, edgeSize = 16,
		insets = { left = 4, right = 4, top = 4, bottom = 4 }
	})
	seqFrame:SetBackdropColor(0.1, 0.1, 0.1, 0.8)
	seqFrame:Hide() -- Start collapsed
	
	TankMark.sequentialInterface = seqFrame
	
	-- Instructional text (shown when no marks exist)
	local emptyText = seqFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	emptyText:SetPoint("CENTER", 0, 0)
	emptyText:SetText("|cff888888Click header to add first mark|r")
	emptyText:Hide()
	
	TankMark.sequentialEmptyText = emptyText
	
	return seqFrame
end

-- ==========================================================
-- SEQUENTIAL MARKS SCROLL (Inside Right Column)
-- ==========================================================
local function CreateSequentialScroll(seqFrame)
	-- Sequential Scroll Frame (wireframe: x=313.64, y=321 → relative: x=8, y=-8)
	local seqScroll = CreateFrame("ScrollFrame", "TMSeqScrollFrame", seqFrame, "FauxScrollFrameTemplate")
	seqScroll:SetPoint("TOPLEFT", 5, -5)
	seqScroll:SetWidth(207)
	seqScroll:SetHeight(105)
	TankMark.sequentialScrollFrame = seqScroll
	
	local seqContent = CreateFrame("Frame", nil, seqScroll)
	seqContent:SetWidth(207)
	seqContent:SetHeight(168)  -- 7 rows * 24 = 168
	seqScroll:SetScrollChild(seqContent)
	
	seqScroll:SetScript("OnVerticalScroll", function()
		FauxScrollFrame_OnVerticalScroll(24, function() TankMark:RefreshSequentialRows() end)
	end)
	
	-- Create 4 sequential row frames (max 7 additional marks)
	for i = 1, 4 do
		local capturedIndex = i  -- Capture for closures
		
		local seqRow = CreateFrame("Frame", "TMSeqRow"..i, seqFrame)
		seqRow:SetWidth(187)
		seqRow:SetHeight(24)
		seqRow:SetPoint("TOPLEFT", 10, -8 - (i-1)*24)
		
		seqRow.number = seqRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		seqRow.number:SetPoint("LEFT", 2, 0)
		seqRow.number:SetText("|cff888888#"..(i+1).."|r")
		
		seqRow.iconBtn = CreateFrame("Button", nil, seqRow)
		seqRow.iconBtn:SetWidth(24)
		seqRow.iconBtn:SetHeight(24)
		seqRow.iconBtn:SetPoint("LEFT", seqRow.number, "RIGHT", 8, 0)
		
		seqRow.iconBtn.tex = seqRow.iconBtn:CreateTexture(nil, "ARTWORK")
		seqRow.iconBtn.tex:SetAllPoints()
		seqRow.iconBtn.tex:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
		TankMark:SetIconTexture(seqRow.iconBtn.tex, 8)
		
		local seqIconDrop = CreateFrame("Frame", "TMSeqIconDropDown"..i, seqRow.iconBtn, "UIDropDownMenuTemplate")
		UIDropDownMenu_Initialize(seqIconDrop, function()
			TankMark:InitSequentialIconMenu(capturedIndex)
		end, "MENU")
		
		seqRow.iconBtn:SetScript("OnClick", function()
			ToggleDropDownMenu(1, nil, seqIconDrop, "cursor", 0, 0)
		end)
		
		seqRow.ccBtn = CreateFrame("Button", nil, seqRow, "UIPanelButtonTemplate")
		seqRow.ccBtn:SetWidth(70)
		seqRow.ccBtn:SetHeight(20)
		seqRow.ccBtn:SetPoint("LEFT", seqRow.iconBtn, "RIGHT", 4, 0)
		seqRow.ccBtn:SetText("No CC")
		
		local seqCCDrop = CreateFrame("Frame", "TMSeqCCDropDown"..i, seqRow.ccBtn, "UIDropDownMenuTemplate")
		UIDropDownMenu_Initialize(seqCCDrop, function()
			TankMark:InitSequentialClassMenu(capturedIndex)
		end, "MENU")
		
		seqRow.ccBtn:SetScript("OnClick", function()
			ToggleDropDownMenu(1, nil, seqCCDrop, "cursor", 0, 0)
		end)
		
		seqRow.delBtn = CreateFrame("Button", nil, seqRow, "UIPanelButtonTemplate")
		seqRow.delBtn:SetWidth(70)  -- Match "No CC" button width
		seqRow.delBtn:SetHeight(20) -- Match "No CC" button height
		seqRow.delBtn:SetText("Remove")
		seqRow.delBtn:SetPoint("LEFT", seqRow.ccBtn, "RIGHT", 4, 0)
		seqRow.delBtn:SetScript("OnClick", function()
			TankMark:RemoveSequentialRow(capturedIndex)
		end)
		
		seqRow:Hide()
		TankMark.sequentialRows[i] = seqRow
	end
end

-- ==========================================================
-- MAIN ENTRY POINT
-- ==========================================================
function TankMark:CreateMobTab(parent)
	if not parent then
		TankMark:Print("|cffff0000Error:|r CreateMobTab called without parent frame.")
		return
	end
	
	-- CREATE CONTAINER FRAME FOR TAB 1
	local t1 = CreateFrame("Frame", "TMMobDatabaseTab", parent)
	t1:SetPoint("TOPLEFT", 0, 0)
	t1:SetPoint("BOTTOMRIGHT", 0, 0)
	t1:Hide()
	
	-- TOP SECTION: Zone controls (right-aligned)
	CreateZoneControls(t1)
	
	-- CENTER SECTION: Mob list
	local mobScrollFrame, listBg = CreateMobList(t1)
	
	-- Search box (centered below mob list)
	CreateSearchBox(t1, listBg)
	
	-- Horizontal divider (separates search from accordions)
	CreateMainDivider(t1)
	
	-- Vertical divider (separates left and right columns)
	CreateColumnDivider(t1)
	
	-- LEFT COLUMN: Add Mob Manually (accordion)
	local editorFrame = CreateMobEditorAccordion(t1)
	CreateMobEditorControls(editorFrame)
	
	-- RIGHT COLUMN: Add More Marks (accordion)
	local seqFrame = CreateSequentialAccordion(t1)
	CreateSequentialScroll(seqFrame)
	
	return t1
end
