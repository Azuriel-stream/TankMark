-- Configuration panel with tab system and popup dialogs

if not TankMark then return end

-- ==========================================================
-- LOCALIZATIONS
-- ==========================================================

-- Import shared localizations
local L = TankMark.Locals

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
	for i = 1, L._tgetn(tabs) do
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
	for i = 1, L._tgetn(TankMark.tabFrames) do
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
	for i = 1, L._tgetn(TankMark.tabButtons) do
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
	elseif tabIndex == 4 then
		-- [v0.29] slice 6.2: refresh the Mob DB sharing trust list on open.
		if TankMark.RefreshTrustList then
			TankMark:RefreshTrustList()
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

-- [v0.29] slice 6.2: Mob DB sharing trust-list state. ONE backing table
-- (TankMarkDB.Trust, account-wide; see Core/TankMark_Trust.lua) shown as a
-- scrollable allow/block list. These file-locals are the row pool + scroll frame;
-- TankMark:RefreshTrustList paints the visible window. No wire/marking behavior --
-- the share-plane gates that read this table land in slice 6.4.
local TRUST_MAX_ROWS = 6
local TRUST_ROW_H    = 24
local trustScroll    = nil
local trustRows      = {}
local trustEmptyText = nil

-- Sorted snapshot of the trust table: trusted first, then blocked, each
-- alphabetical -- so the one table reads as an allow-list above a block-list.
local function BuildTrustList()
	local list = {}
	local t = TankMarkDB and TankMarkDB.Trust
	if t then
		for name, state in L._pairs(t) do
			local s = TankMark.Trust.Resolve(state)
			if s ~= TankMark.Trust.NEUTRAL then
				L._tinsert(list, { name = name, state = s })
			end
		end
	end
	L._tsort(list, function(a, b)
		if a.state ~= b.state then
			return a.state == TankMark.Trust.TRUSTED  -- trusted sorts first
		end
		return a.name < b.name
	end)
	return list
end

-- Public: repaint the trust list (tab OnShow + after any add/remove/toggle).
function TankMark:RefreshTrustList()
	if not trustScroll then return end
	local list = BuildTrustList()
	local n = L._tgetn(list)

	if trustEmptyText then
		if n == 0 then trustEmptyText:Show() else trustEmptyText:Hide() end
	end

	FauxScrollFrame_Update(trustScroll, n, TRUST_MAX_ROWS, TRUST_ROW_H)
	local offset = FauxScrollFrame_GetOffset(trustScroll)

	for i = 1, TRUST_MAX_ROWS do
		local row = trustRows[i]
		local dataIndex = offset + i
		if row then
			if dataIndex <= n then
				local entry = list[dataIndex]
				row.entryName  = entry.name
				row.entryState = entry.state
				if entry.state == TankMark.Trust.TRUSTED then
					row.name:SetText("|cff40ff40" .. entry.name .. "|r  |cff888888(trusted)|r")
					row.toggle:SetText("Block")
				else
					row.name:SetText("|cffff4040" .. entry.name .. "|r  |cff888888(blocked)|r")
					row.toggle:SetText("Trust")
				end
				row:Show()
			else
				row:Hide()
			end
		end
	end
end

-- Section builder: the "Mark Normals" checkbox (now persisted per-character via
-- TankMarkCharConfig.markNormals, read through the default-true accessor).
local function CreateMarkNormalsSection(tab)
	local normalsCheck = CreateFrame("CheckButton", "TMNormalsCheck", tab, "UICheckButtonTemplate")
	normalsCheck:SetPoint("TOPLEFT", 20, -50)
	getglobal(normalsCheck:GetName().."Text"):SetText("Mark Normal/Non-Elite Mobs")
	normalsCheck:SetChecked(TankMark:MarkNormalsEnabled())
	normalsCheck:SetScript("OnClick", function()
		if not TankMarkCharConfig then TankMarkCharConfig = {} end
		TankMarkCharConfig.markNormals = this:GetChecked() and true or false
		TankMark:Print("Marking Normal Mobs: " .. (TankMarkCharConfig.markNormals and "|cff00ff00ON|r" or "|cffff0000OFF|r"))
	end)
	TankMark.normalsCheck = normalsCheck
end

-- Section builder: the two persisted marking-automation toggles, stacked under the
-- Mark-Normals checkbox. Each writes its TankMarkCharConfig field directly -- the
-- same switch as /tmark smartmark|autocc -- and stores a ref so the slash handlers
-- and the tab OnShow can re-sync the box. (Pixel offsets are reload-tunable.)
local function CreateMarkingAutomationSection(tab)
	-- [v0.32] slice C: two of these modes are inert on a scanner-less platform
	-- (Ascension) -- Smart Pre-Marking is FORCED on (the two-sweep is the only batch
	-- path there) and Auto-CC needs the in-combat scanner that does not exist. Show
	-- them disabled at their EFFECTIVE value with a truthful legend, rather than as
	-- live controls that silently do nothing. Mark Normals (a decide-layer policy)
	-- stays a normal toggle on every platform.
	local scannerless = not TankMark.Platform.Caps.hasScanner

	-- Smart Pre-Marking: the PRE-FIGHT batch mode (pack-aware Shift+mouseover).
	local smartCheck = CreateFrame("CheckButton", "TMSmartMarkCheck", tab, "UICheckButtonTemplate")
	smartCheck:SetPoint("TOPLEFT", 20, -76)
	getglobal(smartCheck:GetName().."Text"):SetText("Smart Pre-Marking")
	smartCheck:SetScript("OnClick", function()
		if not TankMarkCharConfig then TankMarkCharConfig = {} end
		TankMarkCharConfig.smartMark = this:GetChecked() and true or false
		TankMark:Print("Smart pre-mark (pack-aware Shift+mouseover): " .. (TankMarkCharConfig.smartMark and "|cff00ff00ON|r" or "|cffff0000OFF|r"))
	end)
	TankMark.smartMarkCheck = smartCheck

	local smartLegend = tab:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	smartLegend:SetPoint("TOPLEFT", 44, -96)

	-- Auto-CC in Combat: the IN-COMBAT scanner mode (per-mob as nameplates appear).
	local autoCheck = CreateFrame("CheckButton", "TMAutoCCCheck", tab, "UICheckButtonTemplate")
	autoCheck:SetPoint("TOPLEFT", 20, -116)
	getglobal(autoCheck:GetName().."Text"):SetText("Auto-CC in Combat")
	autoCheck:SetScript("OnClick", function()
		if not TankMarkCharConfig then TankMarkCharConfig = {} end
		TankMarkCharConfig.autoCC = this:GetChecked() and true or false
		TankMark:Print("Auto-CC in combat (healers / elite casters): " .. (TankMarkCharConfig.autoCC and "|cff00ff00ON|r" or "|cffff0000OFF|r"))
	end)
	TankMark.autoCCCheck = autoCheck

	local autoLegend = tab:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	autoLegend:SetPoint("TOPLEFT", 44, -136)

	if scannerless then
		-- Locked at the effective state: Smart is always-on, Auto-CC never fires.
		smartCheck:SetChecked(true);  smartCheck:Disable()
		autoCheck:SetChecked(false);  autoCheck:Disable()
		smartLegend:SetText("Always on for this client - the pack plans on Shift+mouseover.")
		autoLegend:SetText("Needs an in-combat scanner - not available on this client.")
	else
		smartCheck:SetChecked(TankMark:SmartMarkEnabled())
		autoCheck:SetChecked(TankMark:AutoCCEnabled())
		smartLegend:SetText("Plans the whole pack on Shift+mouseover, before you engage.")
		autoLegend:SetText("Auto-sheeps healers / elite casters as they appear. Best for deliberate pulls.")
	end
end

-- Section builder: the Mob DB sharing trust list (add-by-name + scroll list).
local function CreateTrustSection(tab)
	-- Header + one-line legend (ASCII only -- 1.12 FontStrings drop Unicode).
	local hdr = tab:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	hdr:SetPoint("TOPLEFT", 20, -162)
	hdr:SetText("Mob DB Sharing - Trusted / Blocked Players")

	local legend = tab:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	legend:SetPoint("TOPLEFT", 20, -179)
	legend:SetText("Trusted = shares auto-import; Blocked = shares ignored.")

	-- Add-by-name row: EditBox + Trust / Block buttons.
	local addBox = TankMark:CreateEditBox(tab, "Add player name", 150)
	addBox:SetPoint("TOPLEFT", 24, -212)

	local function addWith(state)
		local name = L._gsub(addBox:GetText() or "", "%s", "")  -- names are single words
		if name == "" then return end
		TankMark.Trust.Set(name, state)
		addBox:SetText("")
		addBox:ClearFocus()
		TankMark:RefreshTrustList()
	end

	local trustBtn = CreateFrame("Button", "TMTrustAddTrust", tab, "UIPanelButtonTemplate")
	trustBtn:SetWidth(60); trustBtn:SetHeight(22)
	trustBtn:SetPoint("LEFT", addBox, "RIGHT", 14, 0)
	trustBtn:SetText("Trust")
	trustBtn:SetScript("OnClick", function() addWith(TankMark.Trust.TRUSTED) end)

	local blockBtn = CreateFrame("Button", "TMTrustAddBlock", tab, "UIPanelButtonTemplate")
	blockBtn:SetWidth(60); blockBtn:SetHeight(22)
	blockBtn:SetPoint("LEFT", trustBtn, "RIGHT", 6, 0)
	blockBtn:SetText("Block")
	blockBtn:SetScript("OnClick", function() addWith(TankMark.Trust.BLOCKED) end)

	-- Scroll list + tooltip-style backdrop.
	local sf = CreateFrame("ScrollFrame", "TankMarkTrustScroll", tab, "FauxScrollFrameTemplate")
	sf:SetPoint("TOPLEFT", 24, -244)
	sf:SetWidth(430)
	sf:SetHeight(TRUST_MAX_ROWS * TRUST_ROW_H)

	local bg = CreateFrame("Frame", nil, tab)
	bg:SetPoint("TOPLEFT", sf, -5, 5)
	bg:SetPoint("BOTTOMRIGHT", sf, 25, -5)
	bg:SetBackdrop({
		bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile     = true,
		tileSize = 16,
		edgeSize = 16,
		insets   = {left = 4, right = 4, top = 4, bottom = 4}
	})
	bg:SetBackdropColor(0, 0, 0, 0.5)

	sf:SetScript("OnVerticalScroll", function()
		FauxScrollFrame_OnVerticalScroll(TRUST_ROW_H, function() TankMark:RefreshTrustList() end)
	end)
	trustScroll = sf

	local empty = tab:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	empty:SetPoint("TOPLEFT", sf, "TOPLEFT", 8, -8)
	empty:SetText("No trusted or blocked players yet.")
	empty:Hide()
	trustEmptyText = empty

	-- Row pool: name + a state toggle + a remove (X).
	for i = 1, TRUST_MAX_ROWS do
		local row = CreateFrame("Frame", nil, tab)
		row:SetWidth(420)
		row:SetHeight(TRUST_ROW_H)
		row:SetPoint("TOPLEFT", sf, "TOPLEFT", 4, -((i - 1) * TRUST_ROW_H))

		local nameFS = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		nameFS:SetPoint("LEFT", row, "LEFT", 4, 0)
		nameFS:SetWidth(260); nameFS:SetJustifyH("LEFT")
		row.name = nameFS

		local rm = CreateFrame("Button", "TMTrustRowRemove" .. i, row, "UIPanelButtonTemplate")
		rm:SetWidth(22); rm:SetHeight(20)
		rm:SetPoint("RIGHT", row, "RIGHT", -6, 0)
		rm:SetText("X")
		rm:SetScript("OnClick", function()
			if row.entryName then
				TankMark.Trust.Clear(row.entryName)
				TankMark:RefreshTrustList()
			end
		end)
		row.remove = rm

		local tg = CreateFrame("Button", "TMTrustRowToggle" .. i, row, "UIPanelButtonTemplate")
		tg:SetWidth(56); tg:SetHeight(20)
		tg:SetPoint("RIGHT", rm, "LEFT", -6, 0)
		tg:SetScript("OnClick", function()
			if row.entryName then
				local flip = (row.entryState == TankMark.Trust.TRUSTED)
					and TankMark.Trust.BLOCKED or TankMark.Trust.TRUSTED
				TankMark.Trust.Set(row.entryName, flip)
				TankMark:RefreshTrustList()
			end
		end)
		row.toggle = tg

		row:Hide()
		trustRows[i] = row
	end
end

function TankMark:BuildGeneralOptionsTab(parent)
	local tab = CreateFrame("Frame", "TMOptionsTab", parent)
	tab:SetPoint("TOPLEFT", 15, -40)
	tab:SetPoint("BOTTOMRIGHT", -15, 50)
	tab:Hide()

	-- Title
	local title = tab:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("TOP", 0, -20)
	title:SetText("General Options")

	CreateMarkNormalsSection(tab)
	CreateMarkingAutomationSection(tab)
	CreateTrustSection(tab)

	-- [v0.30] Re-sync all three toggle checkboxes from their (persisted) accessors
	-- whenever the tab is shown. The panel is built once and cached, so a slash
	-- toggle made while it was closed would otherwise leave the box stale on reopen.
	-- Also repaints the trust list on show.
	tab:SetScript("OnShow", function()
		if TankMark.normalsCheck   then TankMark.normalsCheck:SetChecked(TankMark:MarkNormalsEnabled()) end
		-- [v0.32] slice C: only re-sync the two scanner-dependent toggles from prefs
		-- where they're live (Vanilla). On a scanner-less platform they're disabled
		-- at their effective value -- leave that forced visual alone.
		if TankMark.Platform.Caps.hasScanner then
			if TankMark.smartMarkCheck then TankMark.smartMarkCheck:SetChecked(TankMark:SmartMarkEnabled()) end
			if TankMark.autoCCCheck    then TankMark.autoCCCheck:SetChecked(TankMark:AutoCCEnabled()) end
		end
		TankMark:RefreshTrustList()
	end)

	TankMark:RefreshTrustList()
	return tab
end
