-- TankMark: v0.21

-- File: TankMark_Options.lua

-- Configuration panel with tab system and popup dialogs

if not TankMark then return end

-- ==========================================================
-- LOCALIZATIONS
-- ==========================================================

local _ipairs = ipairs
local _getn = table.getn

-- ==========================================================
-- OPTIONS PANEL
-- ==========================================================

TankMark.optionsFrame = nil
TankMark.activeTab = nil

-- ==========================================================
-- STATIC POPUP DIALOGS
-- ==========================================================

-- Wipe Confirmation Popup (used for deletes)
StaticPopupDialogs["TANKMARK_WIPE_CONFIRM"] = {
	text = "%s",
	button1 = "Confirm",
	button2 = "Cancel",
	OnAccept = function()
		if TankMark.pendingWipeAction then
			TankMark.pendingWipeAction()
			TankMark.pendingWipeAction = nil
		end
	end,
	OnCancel = function()
		TankMark.pendingWipeAction = nil
	end,
	timeout = 0,
	whileDead = 1,
	hideOnEscape = 1,
	exclusive = 1,
}

-- ==========================================================
-- CREATE OPTIONS FRAME (Called Once)
-- ==========================================================

function TankMark:CreateOptionsFrame()
	if TankMark.optionsFrame then return end
	
	-- Create main frame
	local f = CreateFrame("Frame", "TankMarkOptions", UIParent)
	f:SetWidth(520)
	f:SetHeight(450)
	f:SetPoint("CENTER", 0, 0)
	f:SetBackdrop({
		bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
		edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
		tile = true,
		tileSize = 32,
		edgeSize = 32,
		insets = { left = 11, right = 12, top = 12, bottom = 11 }
	})
	f:EnableMouse(true)
	f:SetMovable(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", function() f:StartMoving() end)
	f:SetScript("OnDragStop", function() f:StopMovingOrSizing() end)
	f:Hide()
	
	-- Title
	local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("TOP", 0, -20)
	title:SetText("TankMark Configuration")
	
	-- Close Button
	local closeBtn = CreateFrame("Button", "TMCloseBtn", f, "UIPanelCloseButton")
	closeBtn:SetPoint("TOPRIGHT", -5, -5)
	closeBtn:SetScript("OnClick", function() f:Hide() end)
	
	-- ==========================================================
	-- TAB CONTENT (Load Modules)
	-- ==========================================================
	
	local tabFrames = {}
	
	-- Tab 1: Mob Database
	if TankMark.CreateMobTab then
		tabFrames[1] = TankMark:CreateMobTab(f)
	end
	
	-- Tab 2: Team Profiles
	if TankMark.CreateProfileTab then
		tabFrames[2] = TankMark:CreateProfileTab(f)
	end
	
	-- Tab 3: Data Management
	if TankMark.BuildDataManagementTab then
		tabFrames[3] = TankMark:BuildDataManagementTab(f)
		-- Initialize snapshot list once on creation
		if TankMark.RefreshSnapshotList then
			TankMark:RefreshSnapshotList()
		end
	end
	
	-- Tab 4: General Options
	if TankMark.BuildGeneralOptionsTab then
		tabFrames[4] = TankMark:BuildGeneralOptionsTab(f)
	end
	
	-- Store tab frames for later access
	TankMark.tabFrames = tabFrames
	
	-- ==========================================================
	-- TAB BUTTONS
	-- ==========================================================
	
	local tabs = {
		{ name = "Mob Database", index = 1 },
		{ name = "Team Profiles", index = 2 },
		{ name = "Data Management", index = 3 },
		{ name = "Options", index = 4 }
	}
	
	local tabButtons = {}
	for i = 1, _getn(tabs) do
		local tabInfo = tabs[i]
		local btn = CreateFrame("Button", "TMTab"..i, f, "UIPanelButtonTemplate")
		btn:SetWidth(120)
		btn:SetHeight(30)
		btn:SetText(tabInfo.name)
		
		-- Position below the frame
		if i == 1 then
			btn:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 10, 5)
		else
			btn:SetPoint("LEFT", tabButtons[i-1], "RIGHT", 5, 0)
		end
		
		-- Store index for closure
		local buttonIndex = i
		btn:SetScript("OnClick", function()
			TankMark:SwitchTab(buttonIndex)
		end)
		
		tabButtons[i] = btn
	end
	
	TankMark.tabButtons = tabButtons
	TankMark.optionsFrame = f
end

-- ==========================================================
-- TAB SWITCHING LOGIC
-- ==========================================================

function TankMark:SwitchTab(tabIndex)
	if not TankMark.tabFrames or not TankMark.tabButtons then return end
	
	-- Hide all tabs
	for i = 1, _getn(TankMark.tabFrames) do
		if TankMark.tabFrames[i] then
			TankMark.tabFrames[i]:Hide()
		end
	end
	
	-- Show selected tab
	if TankMark.tabFrames[tabIndex] then
		TankMark.tabFrames[tabIndex]:Show()
	end
	
	TankMark.activeTab = tabIndex
	
	-- Update button states
	for i = 1, _getn(TankMark.tabButtons) do
		if TankMark.tabButtons[i] then
			if i == tabIndex then
				TankMark.tabButtons[i]:Disable()
			else
				TankMark.tabButtons[i]:Enable()
			end
		end
	end
	
	-- Refresh data on tab open
	if tabIndex == 1 and TankMark.UpdateMobList then
		TankMark:UpdateMobList()
	elseif tabIndex == 2 then
		if TankMark.LoadProfileToCache then
			TankMark:LoadProfileToCache()
		end
		if TankMark.UpdateProfileList then
			TankMark:UpdateProfileList()
		end
	end
end

-- ==========================================================
-- SHOW OPTIONS (Called by /tmark c)
-- ==========================================================

function TankMark:ShowOptions()
	if not TankMark.optionsFrame then
		TankMark:CreateOptionsFrame()
	end
	
	if TankMark.optionsFrame:IsVisible() then
		TankMark.optionsFrame:Hide()
	else
		TankMark.optionsFrame:Show()
		
		-- Refresh zone dropdowns on open
		if TankMark.UpdateZoneDropdown then
			TankMark:UpdateZoneDropdown()
		end
		if TankMark.UpdateProfileZoneDropdown then
			TankMark:UpdateProfileZoneDropdown()
		end
		
		-- Switch to first tab by default
		if not TankMark.activeTab then
			TankMark:SwitchTab(1)
		else
			TankMark:SwitchTab(TankMark.activeTab)
		end
	end
end

-- ==========================================================
-- GENERAL OPTIONS TAB
-- ==========================================================

function TankMark:BuildGeneralOptionsTab(parent)
	local tab = CreateFrame("Frame", "TMOptionsTab", parent)
	tab:SetPoint("TOPLEFT", 15, -40)
	tab:SetPoint("BOTTOMRIGHT", -15, 50)
	tab:Hide()
	
	-- Title
	local title = tab:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("TOP", 0, -20)
	title:SetText("General Options")
	
	-- Mark Normals Checkbox
	local normalsCheck = CreateFrame("CheckButton", "TMNormalsCheck", tab, "UICheckButtonTemplate")
	normalsCheck:SetPoint("TOPLEFT", 30, -80)
	getglobal(normalsCheck:GetName().."Text"):SetText("Mark Normal/Non-Elite Mobs")
	normalsCheck:SetChecked(TankMark.MarkNormals)
	normalsCheck:SetScript("OnClick", function()
		TankMark.MarkNormals = this:GetChecked()
		TankMark:Print("Marking Normal Mobs: " .. (TankMark.MarkNormals and "|cff00ff00ON|r" or "|cffff0000OFF|r"))
	end)
	TankMark.normalsCheck = normalsCheck
	
	-- Version Info
	local versionInfo = tab:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	versionInfo:SetPoint("BOTTOM", 0, 20)
	versionInfo:SetText("|cff888888TankMark v0.21\nDatabase Resilience System|r")
	
	return tab
end
