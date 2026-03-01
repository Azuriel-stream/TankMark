-- TankMark: v0.27
-- File: TankMark_Config_Profiles_UI.lua
-- UI frame construction for Team Profiles tab

if not TankMark then return end

-- ==========================================================
-- LOCALIZATIONS
-- ==========================================================

local L = TankMark.Locals

-- ==========================================================
-- TOP ROW: ZONE DROPDOWN + MANAGE PROFILES CHECKBOX + SAVE BUTTON
-- ==========================================================

local function CreateTopRow(parent)
	-- Zone Dropdown
	local pDrop = CreateFrame("Frame", "TMProfileZoneDropDown", parent, "UIDropDownMenuTemplate")
	pDrop:SetPoint("TOPLEFT", parent, "TOPLEFT", 44, -43)
	UIDropDownMenu_SetWidth(150, pDrop)
	UIDropDownMenu_Initialize(pDrop, function()
		local curr = L._GetRealZoneText()
		local info = {}

		info.text = curr
		info.func = function()
			UIDropDownMenu_SetSelectedID(pDrop, this:GetID())
			if TankMark.LoadProfileToCache then TankMark:LoadProfileToCache() end
			if TankMark.UpdateProfileList  then TankMark:UpdateProfileList()  end
		end
		UIDropDownMenu_AddButton(info)

		for zName, _ in L._pairs(TankMarkProfileDB) do
			if zName ~= curr then
				info = {}
				info.text = zName
				info.func = function()
					UIDropDownMenu_SetSelectedID(pDrop, this:GetID())
					if TankMark.LoadProfileToCache then TankMark:LoadProfileToCache() end
					if TankMark.UpdateProfileList  then TankMark:UpdateProfileList()  end
				end
				UIDropDownMenu_AddButton(info)
			end
		end
	end)
	UIDropDownMenu_SetText(L._GetRealZoneText(), pDrop)
	TankMark.profileZoneDropdown = pDrop

	-- Manage Profiles Checkbox
	local mpCheck = CreateFrame("CheckButton", "TMManageProfilesCheck", parent, "UICheckButtonTemplate")
	mpCheck:SetWidth(24)
	mpCheck:SetHeight(24)
	mpCheck:SetPoint("TOPLEFT", parent, "TOPLEFT", 243, -45)

	local mpLabel = getglobal(mpCheck:GetName() .. "Text")
	mpLabel:SetText("Manage Profiles")
	mpLabel:ClearAllPoints()
	mpLabel:SetPoint("LEFT", mpCheck, "RIGHT", 2, 0)

	mpCheck:SetScript("OnClick", function()
		TankMark:ToggleProfileZoneBrowser()
		L._PlaySound("igMainMenuOptionCheckBoxOn")
	end)
	TankMark.profileZoneModeCheck = mpCheck

	-- Save Profile Button (right of checkbox label)
	local savePBtn = CreateFrame("Button", "TMProfileSaveBtn", parent, "UIPanelButtonTemplate")
	savePBtn:SetWidth(80)
	savePBtn:SetHeight(24)
	savePBtn:SetPoint("TOPLEFT", parent, "TOPLEFT", 372, -45)
	savePBtn:SetText("Save Profile")
	savePBtn:SetScript("OnClick", function()
		TankMark:SaveProfileCache()
	end)
	TankMark.profileSaveBtn = savePBtn
end

-- ==========================================================
-- COLUMN HEADERS
-- ==========================================================

local function CreateColumnHeaders(parent)
	local ph1 = parent:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
	ph1:SetText("Icon")
	ph1:SetPoint("TOPLEFT", parent, "TOPLEFT", 47, -85)

	local ph2 = parent:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
	ph2:SetText("Assigned Tank")
	ph2:SetPoint("TOPLEFT", parent, "TOPLEFT", 87, -85)

	local ph3 = parent:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
	ph3:SetText("Assigned Healers")
	ph3:SetPoint("TOPLEFT", parent, "TOPLEFT", 225, -85)

	local ph4 = parent:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
	ph4:SetText("CC")
	ph4:SetPoint("TOPLEFT", parent, "TOPLEFT", 352, -85)
end

-- ==========================================================
-- LIST AREA: SCROLL FRAME + BACKGROUND
-- ==========================================================

local function CreateListArea(parent)
	local psf = CreateFrame("ScrollFrame", "TankMarkProfileScroll", parent, "FauxScrollFrameTemplate")
	psf:SetPoint("TOPLEFT", parent, "TOPLEFT", 37, -100)
	psf:SetWidth(426)
	psf:SetHeight(245)

	local plistBg = CreateFrame("Frame", nil, parent)
	plistBg:SetPoint("TOPLEFT",     psf, -5,  5)
	plistBg:SetPoint("BOTTOMRIGHT", psf, 25, -5)
	plistBg:SetBackdrop({
		bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile     = true,
		tileSize = 16,
		edgeSize = 16,
		insets   = {left = 4, right = 4, top = 4, bottom = 4}
	})
	plistBg:SetBackdropColor(0, 0, 0, 0.5)

	psf:SetScript("OnVerticalScroll", function()
		FauxScrollFrame_OnVerticalScroll(30, function() TankMark:UpdateProfileList() end)
	end)
	TankMark.profileScroll = psf

	return psf
end

-- ==========================================================
-- ROW POOL (pool of 8 reusable profile rows)
-- ==========================================================

local function CreateRowPool(parent)
	for i = 1, 8 do
		local row = CreateFrame("Frame", nil, parent)
		row:SetWidth(426)
		row:SetHeight(30)
		row:SetPoint("TOPLEFT", parent, "TOPLEFT", 40, -100 - ((i - 1) * 30))

		-- Zone label (shown in Manage Profiles / zone browser mode)
		local zoneLabel = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		zoneLabel:SetPoint("LEFT", row, "LEFT", 5, 0)
		zoneLabel:SetWidth(350)
		zoneLabel:SetJustifyH("LEFT")
		zoneLabel:Hide()
		row.zoneLabel = zoneLabel

		-- Icon Button
		local ibtn = CreateFrame("Button", "TMProfileRowIcon" .. i, row)
		ibtn:SetWidth(24)
		ibtn:SetHeight(24)
		ibtn:SetPoint("LEFT", row, "LEFT", 5, 0)
		local itex = ibtn:CreateTexture(nil, "ARTWORK")
		itex:SetAllPoints()
		ibtn:SetNormalTexture(itex)
		row.iconTex = itex
		local idrop = CreateFrame("Frame", "TMProfileRowIconMenu" .. i, ibtn, "UIDropDownMenuTemplate")
		ibtn:SetScript("OnClick", function()
			UIDropDownMenu_Initialize(idrop, function()
				TankMark:InitProfileIconMenu(idrop, row.index)
			end, "MENU")
			ToggleDropDownMenu(1, nil, idrop, "cursor", 0, 0)
		end)

		-- Tank Edit Box
		local teb = TankMark:CreateEditBox(row, "", 110)
		teb:SetPoint("LEFT", ibtn, "RIGHT", 10, 0)
		row.tankEdit = teb
		teb:SetScript("OnTextChanged", function()
			if row.index and TankMark.profileCache[row.index] then
				TankMark.profileCache[row.index].tank = this:GetText()
			end
		end)

		-- Tank Target Button
		local tbtn = CreateFrame("Button", "TMProfileRowTarget" .. i, row, "UIPanelButtonTemplate")
		tbtn:SetWidth(20)
		tbtn:SetHeight(20)
		tbtn:SetPoint("LEFT", teb, "RIGHT", 2, 0)
		tbtn:SetText("T")
		tbtn:SetScript("OnClick", function()
			if L._UnitExists("target") then
				local name = L._UnitName("target")
				teb:SetText(name)
				if row.index and TankMark.profileCache[row.index] then
					local autoRole = TankMark:InferRoleFromClass(name)
					TankMark.profileCache[row.index].role = autoRole
					if row.ccCheck then
						row.ccCheck:SetChecked(autoRole == "CC")
					end
				end
			end
		end)
		row.tankBtn = tbtn

		-- Healer Edit Box
		local heb = TankMark:CreateEditBox(row, "", 90)
		heb:SetPoint("LEFT", tbtn, "RIGHT", 5, 0)
		row.healEdit = heb
		heb:SetScript("OnTextChanged", function()
			if row.index and TankMark.profileCache[row.index] then
				TankMark.profileCache[row.index].healers = this:GetText()
				TankMark:UpdateProfileList()
			end
		end)

		-- Healer Target Button
		local hbtn = CreateFrame("Button", "TMProfileRowHealerTarget" .. i, row, "UIPanelButtonTemplate")
		hbtn:SetWidth(20)
		hbtn:SetHeight(20)
		hbtn:SetPoint("LEFT", heb, "RIGHT", 2, 0)
		hbtn:SetText("T")
		hbtn:SetScript("OnClick", function()
			TankMark:AddHealerToRow(row.index)
		end)
		row.healBtn = hbtn

		-- Warning Icon (offline healers)
		local warnIcon = CreateFrame("Frame", "TMProfileRowWarning" .. i, row)
		warnIcon:SetWidth(22)
		warnIcon:SetHeight(22)
		warnIcon:SetPoint("LEFT", hbtn, "RIGHT", 3, 0)
		local warnTex = warnIcon:CreateTexture(nil, "ARTWORK")
		warnTex:SetTexture("Interface\\DialogFrame\\DialogAlertIcon")
		warnTex:SetAllPoints()
		warnIcon.texture = warnTex
		warnIcon:EnableMouse(true)
		warnIcon:SetScript("OnEnter", function()
			if not row.index or not TankMark.profileCache[row.index] then return end
			local healers = TankMark.profileCache[row.index].healers
			if not healers or healers == "" then return end

			GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
			GameTooltip:AddLine("Healer Status:", 1, 1, 1)
			GameTooltip:AddLine(" ", 1, 1, 1)

			local hasOffline = false
			for healerName in L._gfind(healers, "[^ ]+") do
				local isOnline = TankMark:IsPlayerInRaid(healerName)
				if isOnline then
					GameTooltip:AddLine(healerName .. " [Online]",  0, 1, 0)
				else
					GameTooltip:AddLine(healerName .. " [OFFLINE]", 1, 0, 0)
					hasOffline = true
				end
			end

			if hasOffline then
				GameTooltip:AddLine(" ", 1, 1, 1)
				GameTooltip:AddLine("Offline healers won't trigger alerts", 1, 0.82, 0, 1)
			end
			GameTooltip:Show()
		end)
		warnIcon:SetScript("OnLeave", function()
			GameTooltip:Hide()
		end)
		warnIcon:Hide()
		row.warnIcon = warnIcon

		-- CC Checkbox
		local ccCheck = CreateFrame("CheckButton", "TMProfileRowCC" .. i, row, "UICheckButtonTemplate")
		ccCheck:SetWidth(20)
		ccCheck:SetHeight(20)
		ccCheck:SetPoint("LEFT", row, "LEFT", 310, 0)
		ccCheck:SetScript("OnClick", function()
			if row.index and TankMark.profileCache[row.index] then
				if ccCheck:GetChecked() then
					TankMark.profileCache[row.index].role = "CC"
				else
					TankMark.profileCache[row.index].role = "TANK"
				end
			end
		end)
		row.ccCheck = ccCheck

		-- Delete / Zone-Delete Button
		-- Permanently width 55. Text is always "Delete" in normal mode.
		-- Zone browser mode only swaps the OnClick script — no resize needed.
		local del = CreateFrame("Button", "TMProfileRowDel" .. i, row, "UIPanelButtonTemplate")
		del:SetWidth(55)
		del:SetHeight(24)
		del:SetPoint("RIGHT", row, "RIGHT", -5, 0)
		del:SetText("Delete")
		del:SetScript("OnClick", function()
			TankMark:ProfileDeleteRow(row.index)
		end)
		row.del = del

		TankMark.profileRows[i] = row
		row:Hide()
	end
end

-- ==========================================================
-- BOTTOM ACTION BUTTONS
-- ==========================================================

local function CreateBottomBar(parent)
	local addBtn = CreateFrame("Button", "TMProfileAddBtn", parent, "UIPanelButtonTemplate")
	addBtn:SetWidth(75)
	addBtn:SetHeight(24)
	addBtn:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 100, 70)
	addBtn:SetText("Add Mark")
	addBtn:SetScript("OnClick", function()
		TankMark:ProfileAddRow()
	end)
	TankMark.profileAddBtn = addBtn

	local templateBtn = CreateFrame("Button", "TMProfileTemplateBtn", parent, "UIPanelButtonTemplate")
	templateBtn:SetWidth(85)
	templateBtn:SetHeight(24)
	templateBtn:SetPoint("LEFT", addBtn, "RIGHT", 5, 0)
	templateBtn:SetText("Use Template")
	templateBtn:SetScript("OnClick", function()
		TankMark:ShowTemplateMenu()
	end)
	TankMark.profileTemplateBtn = templateBtn

	local copyBtn = CreateFrame("Button", "TMProfileCopyBtn", parent, "UIPanelButtonTemplate")
	copyBtn:SetWidth(75)
	copyBtn:SetHeight(24)
	copyBtn:SetPoint("LEFT", templateBtn, "RIGHT", 5, 0)
	copyBtn:SetText("Copy From")
	copyBtn:SetScript("OnClick", function()
		TankMark:ShowCopyProfileDialog()
	end)
	TankMark.profileCopyBtn = copyBtn

	local resetPBtn = CreateFrame("Button", "TMProfileResetBtn", parent, "UIPanelButtonTemplate")
	resetPBtn:SetWidth(60)
	resetPBtn:SetHeight(24)
	resetPBtn:SetPoint("LEFT", copyBtn, "RIGHT", 5, 0)
	resetPBtn:SetText("Reset")
	resetPBtn:SetScript("OnClick", function()
		TankMark:RequestResetProfile()
	end)
	TankMark.profileResetBtn = resetPBtn
end

-- ==========================================================
-- MAIN ENTRY POINT
-- ==========================================================

function TankMark:CreateProfileTab(parent)
	local t2 = CreateFrame("Frame", nil, parent)
	t2:SetPoint("TOPLEFT", 0, 0)
	t2:SetPoint("BOTTOMRIGHT", 0, 0)
	t2:Hide()

	-- Top row: zone dropdown + manage profiles checkbox + save button
	CreateTopRow(t2)

	-- Column headers: Icon / Assigned Tank / Assigned Healers / CC
	CreateColumnHeaders(t2)

	-- List area: scroll frame + background
	CreateListArea(t2)

	-- Row pool: 8 reusable profile rows
	CreateRowPool(t2)

	-- Bottom bar: Add Mark / Use Template / Copy From / Reset
	CreateBottomBar(t2)

	return t2
end