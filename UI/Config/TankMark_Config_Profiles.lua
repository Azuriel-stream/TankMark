-- TankMark: v0.21

-- File: TankMark_Config_Profiles.lua

-- Team Profiles configuration with templates and copy features

if not TankMark then return end

-- ==========================================================
-- LOCALIZATIONS
-- ==========================================================

-- Import shared localizations
local L = TankMark.Locals

-- ==========================================================
-- STATE
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

-- ==========================================================
-- DATA LOGIC
-- ==========================================================

function TankMark:LoadProfileToCache()
	if not TankMarkProfileDB then TankMarkProfileDB = {} end
	local zone = UIDropDownMenu_GetText(TankMark.profileZoneDropdown) or L._GetRealZoneText()
	TankMark:MigrateProfileRoles(zone)
	TankMark.profileCache = {}
	if TankMarkProfileDB[zone] then
		for _, entry in L._ipairs(TankMarkProfileDB[zone]) do
			L._tinsert(TankMark.profileCache, {
				mark = entry.mark or 8,
				tank = entry.tank or "",
				healers = entry.healers or "",
				role = entry.role or "TANK",
			})
		end
	end
end

function TankMark:SaveProfileCache()
	local zone = UIDropDownMenu_GetText(TankMark.profileZoneDropdown) or L._GetRealZoneText()
	TankMarkProfileDB[zone] = {}
	for i, entry in L._ipairs(TankMark.profileCache) do
		L._tinsert(TankMarkProfileDB[zone], {
			mark = entry.mark,
			tank = entry.tank,
			healers = entry.healers,
			role = entry.role or "TANK",
		})
	end
	
	-- Update session if current zone
	if zone == L._GetRealZoneText() then
		-- [v0.26] Do NOT pre-mark icons as used.
		-- Session assignments drive the HUD, usedIcons should reflect live mob marks only.
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
	local temp = TankMark.profileCache[index]
	TankMark.profileCache[index] = TankMark.profileCache[target]
	TankMark.profileCache[target] = temp
	TankMark:UpdateProfileList()
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
	
	-- Update UI
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
	
	-- Clear and rebuild cache
	TankMark.profileCache = {}
	for _, entry in L._ipairs(template) do
		L._tinsert(TankMark.profileCache, {
			mark = entry.mark,
			tank = entry.tank or "",
			healers = entry.healers or "",
			role = entry.role or "TANK",
		})
	end
	
	-- Reset scroll position
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
	
	-- Build list of zones that have profiles
	local sourceZones = {}
	for zoneName, profile in L._pairs(TankMarkProfileDB) do
		-- Skip current zone and empty profiles
		if zoneName ~= currentZone and type(profile) == "table" and L._tgetn(profile) > 0 then
			L._tinsert(sourceZones, zoneName)
		end
	end
	
	if L._tgetn(sourceZones) == 0 then
		TankMark:Print("|cffffaa00Notice:|r No other profiles found to copy from.")
		return
	end
	
	-- Sort zones alphabetically
	L._tsort(sourceZones)
	
	-- Create dropdown menu
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
	-- Debug: Print what we're looking for
	if not TankMarkProfileDB[sourceZone] then
		TankMark:Print("|cffff0000Error:|r Source profile '" .. sourceZone .. "' not found in database.")
		TankMark:Print("|cffffaa00Debug:|r Available zones:")
		for zName, _ in L._pairs(TankMarkProfileDB) do
			TankMark:Print("  - '" .. zName .. "'")
		end
		return
	end
	
	-- Check if source has data
	if L._tgetn(TankMarkProfileDB[sourceZone]) == 0 then
		TankMark:Print("|cffffaa00Notice:|r Source zone '" .. sourceZone .. "' has no profile data.")
		return
	end
	
	-- Deep copy profile
	TankMark.profileCache = {}
	for _, entry in L._ipairs(TankMarkProfileDB[sourceZone]) do
		L._tinsert(TankMark.profileCache, {
			mark = entry.mark,
			tank = entry.tank or "",
			healers = entry.healers or "",
			role = entry.role or "TANK",
		})
	end
	
	-- Reset scroll position
	if TankMark.profileScroll then
		FauxScrollFrame_SetOffset(TankMark.profileScroll, 0)
	end
	
	TankMark:UpdateProfileList()
	TankMark:Print("|cff00ff00Copied:|r " .. L._tgetn(TankMark.profileCache) .. " marks from '" .. sourceZone .. "'")
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
	local numItems = L._tgetn(list)
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

			-- Update CC checkbox state
			if row.ccCheck then
				if data.role == "CC" then
					row.ccCheck:SetChecked(true)
				else
					row.ccCheck:SetChecked(false)
				end
			end
			
			-- Apply roster validation color to tank name
			if data.tank and data.tank ~= "" then
				if TankMark:IsPlayerInRaid(data.tank) then
					row.tankEdit:SetTextColor(1, 1, 1) -- White (in raid)
				else
					row.tankEdit:SetTextColor(1, 0, 0) -- Red (not in raid)
				end
			else
				row.tankEdit:SetTextColor(0.7, 0.7, 0.7) -- Gray (empty)
			end
			
            -- Show/hide warning icon for offline healers
            if row.warnIcon then
                local showWarning = false
                if data.healers and data.healers ~= "" then
                    for healerName in L._gfind(data.healers, "[^ ]+") do
                        if not TankMark:IsPlayerInRaid(healerName) then
                            showWarning = true
                            break
                        end
                    end
                end
                
                if showWarning then
                    row.warnIcon:Show()
                else
                    row.warnIcon:Hide()
                end
            end

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
	
	-- Update "Add Mark" button state (8 mark limit)
	if TankMark.profileAddBtn then
		if numItems >= 8 then
			TankMark.profileAddBtn:Disable()
		else
			TankMark.profileAddBtn:Enable()
		end
	end
end

function TankMark:UpdateProfileZoneUI(zone)
    -- Safety check for the specific widget found in this file
    if not TankMark.profileZoneDropdown then return end
    
    -- Update the visual text on the dropdown button
    UIDropDownMenu_SetText(zone, TankMark.profileZoneDropdown)
    
    -- Reload the profile data into the cache for the new zone
    -- This function (lines 60+) uses UIDropDownMenu_GetText, so setting the text above is critical
    if TankMark.LoadProfileToCache then
        TankMark:LoadProfileToCache()
    end
    
    -- Refresh the visual rows
    if TankMark.UpdateProfileList then
        TankMark:UpdateProfileList()
    end
end

-- ==========================================================
-- TAB CONSTRUCTION
-- ==========================================================

function TankMark:CreateProfileTab(parent)
	local t2 = CreateFrame("Frame", nil, parent)
	t2:SetPoint("TOPLEFT", 15, -40)
	t2:SetPoint("BOTTOMRIGHT", -15, 30)
	t2:Hide()
	
	-- Zone Dropdown
	local pDrop = CreateFrame("Frame", "TMProfileZoneDropDown", t2, "UIDropDownMenuTemplate")
	pDrop:SetPoint("TOPLEFT", 0, -10)
	UIDropDownMenu_SetWidth(150, pDrop)
	UIDropDownMenu_Initialize(pDrop, function()
		local curr = L._GetRealZoneText()
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
		for zName, _ in L._pairs(TankMarkProfileDB) do
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
	UIDropDownMenu_SetText(L._GetRealZoneText(), pDrop)
	TankMark.profileZoneDropdown = pDrop
	
	-- Column Headers
	local ph1 = t2:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
	ph1:SetText("Icon")
	ph1:SetPoint("TOPLEFT", 15, -45)
	local ph2 = t2:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
	ph2:SetText("Assigned Tank")
	ph2:SetPoint("TOPLEFT", 49, -45)
	local ph3 = t2:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
	ph3:SetText("Assigned Healers")
	ph3:SetPoint("TOPLEFT", 196, -45)
	local ph4 = t2:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
	ph4:SetText("CC")
	ph4:SetPoint("TOPLEFT", 320, -45)
	
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
		local teb = TankMark:CreateEditBox(row, "", 110)
		teb:SetPoint("LEFT", ibtn, "RIGHT", 10, 0)
		row.tankEdit = teb
		teb:SetScript("OnTextChanged", function()
			if row.index and TankMark.profileCache[row.index] then
				TankMark.profileCache[row.index].tank = this:GetText()
			end
		end)
		
		-- Tank Target Button
		local tbtn = CreateFrame("Button", "TMProfileRowTarget"..i, row, "UIPanelButtonTemplate")
		tbtn:SetWidth(20)
		tbtn:SetHeight(20)
		tbtn:SetPoint("LEFT", teb, "RIGHT", 2, 0)
		tbtn:SetText("T")
		tbtn:SetScript("OnClick", function()
			if L._UnitExists("target") then
				local name = L._UnitName("target")
				teb:SetText(name)
				-- Auto-detect role from target's class
				if row.index and TankMark.profileCache[row.index] then
					local autoRole = TankMark:InferRoleFromClass(name)
					TankMark.profileCache[row.index].role = autoRole
					if row.ccCheck then
						row.ccCheck:SetChecked(autoRole == "CC")
					end
				end
			end
		end)
		
        -- Healer Edit Box
        local heb = TankMark:CreateEditBox(row, "", 90)
        heb:SetPoint("LEFT", tbtn, "RIGHT", 5, 0)
        row.healEdit = heb
        heb:SetScript("OnTextChanged", function()
            if row.index and TankMark.profileCache[row.index] then
                TankMark.profileCache[row.index].healers = this:GetText()
                -- Trigger update to refresh warning icon
                TankMark:UpdateProfileList()
            end
        end)

        -- Healer Target Button
        local hbtn = CreateFrame("Button", "TMProfileRowHealerTarget"..i, row, "UIPanelButtonTemplate")
        hbtn:SetWidth(20)
        hbtn:SetHeight(20)
        hbtn:SetPoint("LEFT", heb, "RIGHT", 2, 0)
        hbtn:SetText("T")
        hbtn:SetScript("OnClick", function()
            TankMark:AddHealerToRow(row.index)
        end)

        -- Warning Icon (for offline healers)
        local warnIcon = CreateFrame("Frame", "TMProfileRowWarning"..i, row)
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
            GameTooltip:AddLine(" ", 1, 1, 1) -- Spacing
            
            local hasOffline = false
            for healerName in L._gfind(healers, "[^ ]+") do
                local isOnline = TankMark:IsPlayerInRaid(healerName)
                if isOnline then
                    GameTooltip:AddLine(healerName .. " [Online]", 0, 1, 0)
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
		local ccCheck = CreateFrame("CheckButton", "TMProfileRowCC"..i, row, "UICheckButtonTemplate")
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
	addBtn:SetWidth(75)
	addBtn:SetHeight(24)
	addBtn:SetPoint("BOTTOMLEFT", 10, 5)
	addBtn:SetText("Add Mark")
	addBtn:SetScript("OnClick", function()
		TankMark:ProfileAddRow()
	end)
	TankMark.profileAddBtn = addBtn
	
	local templateBtn = CreateFrame("Button", "TMProfileTemplateBtn", t2, "UIPanelButtonTemplate")
	templateBtn:SetWidth(85)
	templateBtn:SetHeight(24)
	templateBtn:SetPoint("LEFT", addBtn, "RIGHT", 5, 0)
	templateBtn:SetText("Load Template")
	templateBtn:SetScript("OnClick", function()
		TankMark:ShowTemplateMenu()
	end)
	
	local copyBtn = CreateFrame("Button", "TMProfileCopyBtn", t2, "UIPanelButtonTemplate")
	copyBtn:SetWidth(75)
	copyBtn:SetHeight(24)
	copyBtn:SetPoint("LEFT", templateBtn, "RIGHT", 5, 0)
	copyBtn:SetText("Copy From...")
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
	deletePBtn:SetText("Delete Profile")
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
