-- TankMark: v0.27
-- File: TankMark_Config_Profiles_UI.lua
-- UI frame construction for Team Profiles tab

if not TankMark then return end

-- ==========================================================
-- LOCALIZATIONS
-- ==========================================================

local L = TankMark.Locals

-- ==========================================================
-- TAB CONSTRUCTION
-- ==========================================================

function TankMark:CreateProfileTab(parent)
	local t2 = CreateFrame("Frame", nil, parent)
	t2:SetPoint("TOPLEFT", 15, -40)
	t2:SetPoint("BOTTOMRIGHT", -15, 30)
	t2:Hide()

	-- ----------------------------------------------------------
	-- ZONE DROPDOWN
	-- ----------------------------------------------------------
	local pDrop = CreateFrame("Frame", "TMProfileZoneDropDown", t2, "UIDropDownMenuTemplate")
	pDrop:SetPoint("TOPLEFT", 0, -10)
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

	-- ----------------------------------------------------------
	-- [v0.27] MANAGE PROFILES CHECKBOX
	-- ----------------------------------------------------------
	local mpCheck = CreateFrame("CheckButton", "TMManageProfilesCheck", t2, "UICheckButtonTemplate")
	mpCheck:SetWidth(24)
	mpCheck:SetHeight(24)
	mpCheck:SetPoint("TOPLEFT", t2, "TOPLEFT", 200, -13)

	local mpLabel = getglobal(mpCheck:GetName() .. "Text")
	mpLabel:SetText("Manage Profiles")
	mpLabel:ClearAllPoints()
	mpLabel:SetPoint("LEFT", mpCheck, "RIGHT", 2, 0)

	mpCheck:SetScript("OnClick", function()
		TankMark:ToggleProfileZoneBrowser()
		L._PlaySound("igMainMenuOptionCheckBoxOn")
	end)
	TankMark.profileZoneModeCheck = mpCheck

	-- ----------------------------------------------------------
	-- COLUMN HEADERS
	-- ----------------------------------------------------------
	local ph1 = t2:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
	ph1:SetText("Icon")
	ph1:SetPoint("TOPLEFT", 21, -45)

	local ph2 = t2:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
	ph2:SetText("Assigned Tank")
	ph2:SetPoint("TOPLEFT", 55, -45)

	local ph3 = t2:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
	ph3:SetText("Assigned Healers")
	ph3:SetPoint("TOPLEFT", 202, -45)

	local ph4 = t2:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
	ph4:SetText("CC")
	ph4:SetPoint("TOPLEFT", 326, -45)

	-- ----------------------------------------------------------
	-- SCROLL FRAME + BACKGROUND
	-- ----------------------------------------------------------
	local psf = CreateFrame("ScrollFrame", "TankMarkProfileScroll", t2, "FauxScrollFrameTemplate")
	psf:SetPoint("TOPLEFT", 16, -60)
	psf:SetWidth(426)
	psf:SetHeight(270)

	local plistBg = CreateFrame("Frame", nil, t2)
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
		FauxScrollFrame_OnVerticalScroll(44, function() TankMark:UpdateProfileList() end)
	end)
	TankMark.profileScroll = psf

	-- ----------------------------------------------------------
	-- PROFILE ROWS (pool of 8)
	-- ----------------------------------------------------------
	for i = 1, 8 do
		local row = CreateFrame("Frame", nil, t2)
		row:SetWidth(426)
		row:SetHeight(44)
		row:SetPoint("TOPLEFT", 16, -60 - ((i - 1) * 44))

		-- [v0.27] Zone label for zone browser mode (hidden by default)
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
		ibtn:SetPoint("LEFT", 5, 0)
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
		del:SetWidth(55)   -- matches zone browser "Delete" width
		del:SetHeight(32)
		del:SetPoint("RIGHT", row, "RIGHT", -5, 0)
		del:SetText("Delete")
		del:SetScript("OnClick", function()
			TankMark:ProfileDeleteRow(row.index)
		end)
		row.del = del

		TankMark.profileRows[i] = row
		row:Hide()
	end

	-- ----------------------------------------------------------
	-- BOTTOM ACTION BUTTONS
	-- ----------------------------------------------------------
	local addBtn = CreateFrame("Button", "TMProfileAddBtn", t2, "UIPanelButtonTemplate")
	addBtn:SetWidth(75)
	addBtn:SetHeight(24)
	addBtn:SetPoint("BOTTOMLEFT", 16, 5)
	addBtn:SetText("Add Mark")
	addBtn:SetScript("OnClick", function()
		TankMark:ProfileAddRow()
	end)
	TankMark.profileAddBtn = addBtn

	local templateBtn = CreateFrame("Button", "TMProfileTemplateBtn", t2, "UIPanelButtonTemplate")
	templateBtn:SetWidth(85)
	templateBtn:SetHeight(24)
	templateBtn:SetPoint("LEFT", addBtn, "RIGHT", 5, 0)
	templateBtn:SetText("Use Template")
	templateBtn:SetScript("OnClick", function()
		TankMark:ShowTemplateMenu()
	end)

	local copyBtn = CreateFrame("Button", "TMProfileCopyBtn", t2, "UIPanelButtonTemplate")
	copyBtn:SetWidth(75)
	copyBtn:SetHeight(24)
	copyBtn:SetPoint("LEFT", templateBtn, "RIGHT", 5, 0)
	copyBtn:SetText("Copy From")
	copyBtn:SetScript("OnClick", function()
		TankMark:ShowCopyProfileDialog()
	end)

	local resetPBtn = CreateFrame("Button", "TMProfileResetBtn", t2, "UIPanelButtonTemplate")
	resetPBtn:SetWidth(60)
	resetPBtn:SetHeight(24)
	resetPBtn:SetPoint("LEFT", copyBtn, "RIGHT", 5, 0)
	resetPBtn:SetText("Reset")
	resetPBtn:SetScript("OnClick", function()
		TankMark:RequestResetProfile()
	end)

	local deletePBtn = CreateFrame("Button", "TMProfileDeleteBtn", t2, "UIPanelButtonTemplate")
	deletePBtn:SetWidth(80)
	deletePBtn:SetHeight(24)
	deletePBtn:SetPoint("LEFT", resetPBtn, "RIGHT", 5, 0)
	deletePBtn:SetText("Drop Profile")
	deletePBtn:SetScript("OnClick", function()
		TankMark:RequestDeleteProfile()
	end)

	local savePBtn = CreateFrame("Button", "TMProfileSaveBtn", t2, "UIPanelButtonTemplate")
	savePBtn:SetWidth(80)
	savePBtn:SetHeight(24)
	savePBtn:SetPoint("LEFT", deletePBtn, "RIGHT", 5, 0)
	savePBtn:SetText("Save Profile")
	savePBtn:SetScript("OnClick", function()
		TankMark:SaveProfileCache()
	end)

	return t2
end