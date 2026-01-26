-- TankMark: v0.23
-- File: TankMark_Config_Mobs.lua
-- Mob Database configuration UI with sequential marking support

if not TankMark then return end

-- ==========================================================
-- LOCALIZATIONS
-- ==========================================================

local _pairs = pairs
local _ipairs = ipairs
local _insert = table.insert
local _remove = table.remove
local _sort = table.sort
local _getn = table.getn
local _lower = string.lower
local _strfind = string.find
local _gsub = string.gsub

-- ==========================================================
-- STATE
-- ==========================================================

TankMark.mobRows = {}
TankMark.selectedIcon = 8
TankMark.selectedClass = nil
TankMark.isZoneListMode = false
TankMark.lockViewZone = nil
TankMark.editingLockGUID = nil
TankMark.detectedCreatureType = nil
TankMark.isLockActive = false

-- [v0.23] Sequential marking state
TankMark.editingSequentialMarks = {}  -- Array of {icon, class, type}
TankMark.sequentialRows = {}  -- UI frame pool (max 7 additional marks)
TankMark.isAddMobExpanded = false  -- Accordion state

-- ==========================================================
-- UI REFERENCES
-- ==========================================================

TankMark.scrollFrame = nil
TankMark.searchBox = nil
TankMark.zoneDropDown = nil
TankMark.zoneModeCheck = nil
TankMark.editMob = nil
TankMark.editPrio = nil
TankMark.saveBtn = nil
TankMark.cancelBtn = nil
TankMark.lockBtn = nil
TankMark.classBtn = nil
TankMark.iconBtn = nil
TankMark.addMobHeader = nil
TankMark.addMobInterface = nil
TankMark.sequentialScrollFrame = nil
TankMark.addMoreMarksText = nil

-- ==========================================================
-- LOGIC CONSTANTS
-- ==========================================================

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

local CC_MAP = {
    ["Humanoid"] = { "MAGE", "ROGUE", "WARLOCK", "PRIEST" },
    ["Beast"] = { "MAGE", "DRUID", "HUNTER" },
    ["Elemental"] = { "WARLOCK" },
    ["Demon"] = { "WARLOCK" },
    ["Undead"] = { "PRIEST" },
    ["Dragonkin"] = { "DRUID" }
}

local ALL_CLASSES = { "MAGE", "WARLOCK", "DRUID", "ROGUE", "PRIEST", "HUNTER", "WARRIOR", "SHAMAN", "PALADIN" }

-- ==========================================================
-- MENUS
-- ==========================================================

function TankMark:InitIconMenu()
    local iconNames = {
        [8] = "|cffffffffSkull|r",
        [7] = "|cffff0000Cross|r",
        [6] = "|cff00ccffSquare|r",
        [5] = "|cffaabbccMoon|r",
        [4] = "|cff00ff00Triangle|r",
        [3] = "|cffff00ffDiamond|r",
        [2] = "|cffffaa00Circle|r",
        [1] = "|cffffff00Star|r"
    }
    
    -- [v0.23] IGNORE option only for single-mark mobs
    if _getn(TankMark.editingSequentialMarks) == 0 then
        iconNames[0] = "|cff888888Disabled (Ignore)|r"
    end
    
    for i = 8, 0, -1 do
        if iconNames[i] then  -- Skip 0 if sequential marks exist
            local capturedIcon = i
            local info = {}
            info.text = iconNames[i]
            info.func = function()
                TankMark.selectedIcon = capturedIcon
                if TankMark.iconBtn and TankMark.iconBtn.tex then
                    TankMark:SetIconTexture(TankMark.iconBtn.tex, TankMark.selectedIcon)
                    TankMark:UpdateClassButton()
                end
                
                -- [v0.23] If IGNORE selected, set prio = 9
                if capturedIcon == 0 and TankMark.editPrio then
                    TankMark.editPrio:SetText("9")
                end
                
                CloseDropDownMenus()
            end
            info.checked = (TankMark.selectedIcon == i)
            UIDropDownMenu_AddButton(info)
        end
    end
end

function TankMark:InitClassMenu()
    local info = {}
    
    -- [v0.23] IGNORE option only for single-mark mobs
    if _getn(TankMark.editingSequentialMarks) == 0 then
        info = {
            text = "|cff888888IGNORE (Do Not Mark)|r",
            func = function()
                TankMark.selectedClass = nil
                TankMark:UpdateClassButton()
                TankMark.classBtn:SetText("IGNORED")
                TankMark.classBtn:SetTextColor(0.5, 0.5, 0.5)
                TankMark:ApplySmartDefaults("IGNORE")
            end
        }
        UIDropDownMenu_AddButton(info)
    end
    
    info = {
        text = "|cffffffffNo CC (Kill Target)|r",
        func = function()
            TankMark.selectedClass = nil
            TankMark:UpdateClassButton()
            TankMark:ApplySmartDefaults("KILL")
        end
    }
    UIDropDownMenu_AddButton(info)
    
    if TankMark.detectedCreatureType and CC_MAP[TankMark.detectedCreatureType] then
        info = { text = "--- Recommended ---", isTitle = 1 }
        UIDropDownMenu_AddButton(info)
        
        for _, class in _ipairs(CC_MAP[TankMark.detectedCreatureType]) do
            local capturedClass = class
            info = {
                text = "|cff00ff00" .. capturedClass .. "|r",
                func = function()
                    TankMark.selectedClass = capturedClass
                    TankMark:UpdateClassButton()
                    TankMark:ApplySmartDefaults(capturedClass)
                end
            }
            UIDropDownMenu_AddButton(info)
        end
    end
    
    info = { text = "--- All Classes ---", isTitle = 1 }
    UIDropDownMenu_AddButton(info)
    
    for _, class in _ipairs(ALL_CLASSES) do
        local capturedClass = class
        info = {
            text = capturedClass,
            func = function()
                TankMark.selectedClass = capturedClass
                TankMark:UpdateClassButton()
                TankMark:ApplySmartDefaults(capturedClass)
            end
        }
        UIDropDownMenu_AddButton(info)
    end
end

-- [v0.23] Initialize sequential row CC menu
function TankMark:InitSequentialClassMenu(seqIndex)
    local info = {}
    
    -- No IGNORE option for sequential rows
    info = {
        text = "|cffffffffNo CC (Kill Target)|r",
        func = function()
            if TankMark.editingSequentialMarks[seqIndex] then
                TankMark.editingSequentialMarks[seqIndex].class = nil
                TankMark.editingSequentialMarks[seqIndex].type = "KILL"
                TankMark:RefreshSequentialRows()
            end
        end
    }
    UIDropDownMenu_AddButton(info)
    
    if TankMark.detectedCreatureType and CC_MAP[TankMark.detectedCreatureType] then
        info = { text = "--- Recommended ---", isTitle = 1 }
        UIDropDownMenu_AddButton(info)
        
        for _, class in _ipairs(CC_MAP[TankMark.detectedCreatureType]) do
            local capturedClass = class
            info = {
                text = "|cff00ff00" .. capturedClass .. "|r",
                func = function()
                    if TankMark.editingSequentialMarks[seqIndex] then
                        TankMark.editingSequentialMarks[seqIndex].class = capturedClass
                        TankMark.editingSequentialMarks[seqIndex].type = "CC"
                        TankMark:RefreshSequentialRows()
                    end
                end
            }
            UIDropDownMenu_AddButton(info)
        end
    end
    
    info = { text = "--- All Classes ---", isTitle = 1 }
    UIDropDownMenu_AddButton(info)
    
    for _, class in _ipairs(ALL_CLASSES) do
        local capturedClass = class
        info = {
            text = capturedClass,
            func = function()
                if TankMark.editingSequentialMarks[seqIndex] then
                    TankMark.editingSequentialMarks[seqIndex].class = capturedClass
                    TankMark.editingSequentialMarks[seqIndex].type = "CC"
                    TankMark:RefreshSequentialRows()
                end
            end
        }
        UIDropDownMenu_AddButton(info)
    end
end

-- [v0.23] Initialize sequential row icon menu
function TankMark:InitSequentialIconMenu(seqIndex)
    local iconNames = {
        [8] = "|cffffffffSkull|r",
        [7] = "|cffff0000Cross|r",
        [6] = "|cff00ccffSquare|r",
        [5] = "|cffaabbccMoon|r",
        [4] = "|cff00ff00Triangle|r",
        [3] = "|cffff00ffDiamond|r",
        [2] = "|cffffaa00Circle|r",
        [1] = "|cffffff00Star|r"
    }
    
    -- No IGNORE option for sequential marks
    for i = 8, 1, -1 do
        local capturedIcon = i
        local info = {}
        info.text = iconNames[i]
        info.func = function()
            if TankMark.editingSequentialMarks[seqIndex] then
                TankMark.editingSequentialMarks[seqIndex].icon = capturedIcon
                TankMark:RefreshSequentialRows()
            end
            CloseDropDownMenus()
        end
        info.checked = (TankMark.editingSequentialMarks[seqIndex] and TankMark.editingSequentialMarks[seqIndex].icon == i)
        UIDropDownMenu_AddButton(info)
    end
end

-- ==========================================================
-- TAB CONSTRUCTION
-- ==========================================================

function TankMark:CreateMobTab(parent)
    local t1 = CreateFrame("Frame", nil, parent)
    t1:SetPoint("TOPLEFT", parent, "TOPLEFT", 15, -40)
    t1:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -15, 50)
    
    -- Zone Dropdown
    local drop = CreateFrame("Frame", "TMZoneDropDown", t1, "UIDropDownMenuTemplate")
    drop:SetPoint("TOPLEFT", 0, -10)
    UIDropDownMenu_SetWidth(150, drop)
    UIDropDownMenu_Initialize(drop, function()
		local curr = GetRealZoneText()
		local info = {}
		
		-- Current zone (first)
		info.text = curr
		info.func = function()
			-- Get the currently displayed zone BEFORE changing
			local previousZone = UIDropDownMenu_GetText(TankMark.zoneDropDown)
			
			UIDropDownMenu_SetSelectedID(drop, this:GetID())
			
			-- Only reset editor if switching to a DIFFERENT zone
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
					-- Get the currently displayed zone BEFORE changing
					local previousZone = UIDropDownMenu_GetText(TankMark.zoneDropDown)
					
					UIDropDownMenu_SetSelectedID(drop, this:GetID())
					
					-- Only reset editor if switching to a DIFFERENT zone
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
    local mzCheck = CreateFrame("CheckButton", "TM_ManageZonesCheck", t1, "UICheckButtonTemplate")
    mzCheck:SetWidth(24)
    mzCheck:SetHeight(24)
    mzCheck:SetPoint("LEFT", drop, "RIGHT", 10, 2)
    _G[mzCheck:GetName().."Text"]:SetText("Manage Zones")
    mzCheck:SetScript("OnClick", function()
        TankMark:ToggleZoneBrowser()
        PlaySound("igMainMenuOptionCheckBoxOn")
    end)
    TankMark.zoneModeCheck = mzCheck
    
    -- Add Zone Button
    local addZoneBtn = CreateFrame("Button", "TMAddZoneBtn", t1, "UIPanelButtonTemplate")
    addZoneBtn:SetWidth(80)
    addZoneBtn:SetHeight(24)
    addZoneBtn:SetPoint("TOPLEFT", drop, "TOPRIGHT", 130, -2)
    addZoneBtn:SetText("Add Zone")
    addZoneBtn:SetScript("OnClick", function()
        TankMark:ShowAddCurrentZoneDialog()
    end)
    
    -- Mob List Scroll Frame (REDUCED TO 6 ROWS)
    local sf = CreateFrame("ScrollFrame", "TankMarkScrollFrame", t1, "FauxScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", 10, -50)
    sf:SetWidth(380)
    sf:SetHeight(132)  -- 6 rows × 22px = 132px (was 198px for 9 rows)
    
    local listBg = CreateFrame("Frame", nil, t1)
    listBg:SetPoint("TOPLEFT", sf, -5, 5)
    listBg:SetPoint("BOTTOMRIGHT", sf, 25, -5)
    listBg:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })
    listBg:SetBackdropColor(0, 0, 0, 0.5)
    
    sf:SetScript("OnVerticalScroll", function()
        FauxScrollFrame_OnVerticalScroll(22, function() TankMark:UpdateMobList() end)
    end)
    TankMark.scrollFrame = sf
    
    -- Mob Rows (CREATE 6 INSTEAD OF 9)
    for i = 1, 6 do
        local row = CreateFrame("Button", "TMMobRow"..i, t1)
        row:SetWidth(380)
        row:SetHeight(22)
        row:SetPoint("TOPLEFT", 10, -50 - ((i-1)*22))
        
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
    
    -- Search Box
    local searchLabel = t1:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    searchLabel:SetPoint("TOPLEFT", listBg, "BOTTOMLEFT", 5, -8)
    searchLabel:SetText("Search:")
    
    local sBox = TankMark:CreateEditBox(t1, "", 150)
    sBox:SetPoint("LEFT", searchLabel, "RIGHT", 8, 0)
    sBox:SetScript("OnTextChanged", function() TankMark:UpdateMobList() end)
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
    
    -- ==========================================================
    -- [v0.23] NEW EDIT INTERFACE (ACCORDION + SEQUENTIAL MARKS)
    -- ==========================================================
    
    local editSectionTop = -230  -- Fixed position
    
    -- Divider Line
    local div = t1:CreateTexture(nil, "ARTWORK")
    div:SetHeight(1)
    div:SetWidth(380)
    div:SetPoint("TOPLEFT", 10, editSectionTop)
    div:SetTexture(1, 1, 1, 0.2)
    
	-- [v0.23] ACCORDION HEADER: "+ Add a mob manually"
	local addMobHeader = CreateFrame("Button", "TMAddMobHeader", t1)
	addMobHeader:SetWidth(200)
	addMobHeader:SetHeight(20)
	addMobHeader:SetPoint("TOPLEFT", 10, editSectionTop - 10)

	-- Plus/Minus icon
	addMobHeader.arrow = addMobHeader:CreateTexture(nil, "ARTWORK")
	addMobHeader.arrow:SetWidth(16)
	addMobHeader.arrow:SetHeight(16)
	addMobHeader.arrow:SetPoint("LEFT", 0, 0)
	addMobHeader.arrow:SetTexture("Interface\\Buttons\\UI-PlusButton-Up")

	-- Text label
	addMobHeader.text = addMobHeader:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	addMobHeader.text:SetPoint("LEFT", addMobHeader.arrow, "RIGHT", 5, 0)
	addMobHeader.text:SetText("|cff00ccffAdd a mob manually|r")

	-- Hover effects
	addMobHeader:SetScript("OnEnter", function()
		this.text:SetTextColor(0, 1, 1)
	end)
	addMobHeader:SetScript("OnLeave", function()
		this.text:SetTextColor(0, 0.8, 1)
	end)

	-- Click handler (existing code - keep as is)
	addMobHeader:SetScript("OnClick", function()
		if TankMark.isAddMobExpanded then
			-- Collapse
			TankMark.addMobInterface:Hide()
			addMobHeader.arrow:SetTexture("Interface\\Buttons\\UI-PlusButton-Up")
			TankMark.isAddMobExpanded = false
		else
			-- Expand
			TankMark.addMobInterface:Show()
			addMobHeader.arrow:SetTexture("Interface\\Buttons\\UI-MinusButton-Up")
			TankMark.isAddMobExpanded = true
		end
	end)

	TankMark.addMobHeader = addMobHeader
    
    -- [v0.23] MAIN EDIT INTERFACE (Hidden by default)
    local addGroup = CreateFrame("Frame", nil, t1)
    addGroup:SetPoint("TOPLEFT", addMobHeader, "BOTTOMLEFT", 20, -5)
    addGroup:SetWidth(380)
    addGroup:SetHeight(120)  -- Increased height for sequential marks
    addGroup:Hide()
    TankMark.addMobInterface = addGroup
    
    -- Mob Name Input
    local nameBox = TankMark:CreateEditBox(addGroup, "Mob Name", 180)
    nameBox:SetPoint("TOPLEFT", 0, -5)
    TankMark.editMob = nameBox
    nameBox:SetScript("OnTextChanged", function()
        local text = this:GetText()
        if text and text ~= "" and text ~= "Mob Name" then
            if TankMark.saveBtn then TankMark.saveBtn:Enable() end
            
            -- [v0.23] Check GUID lock conflict
			if TankMark:HasGUIDLockForMobName(text) and TankMark.addMoreMarksText then
				TankMark.addMoreMarksText:SetTextColor(0.5, 0.5, 0.5)
				-- Disable the button that wraps the text
				if TankMark.addMoreMarksBtn then
					TankMark.addMoreMarksBtn:Disable()
				end
			elseif TankMark.addMoreMarksText and TankMark.addMoreMarksText:IsVisible() then
				TankMark.addMoreMarksText:SetTextColor(0, 0.8, 1)
				-- Enable the button
				if TankMark.addMoreMarksBtn then
					TankMark.addMoreMarksBtn:Enable()
				end
			end
        else
            if TankMark.saveBtn then TankMark.saveBtn:Disable() end
        end
    end)
    
    -- Target Button
    local targetBtn = CreateFrame("Button", "TMTargetBtn", addGroup, "UIPanelButtonTemplate")
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
    
    -- Second Row: Icon + Priority + CC + Lock + Save/Update + Cancel
    local row2Top = -40
    
    -- Icon Selector
    local iconSel = CreateFrame("Button", nil, addGroup)
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
    
    -- Priority Input + Spinner Buttons
    local prioBox = TankMark:CreateEditBox(addGroup, "Prio", 30)
    prioBox:SetPoint("LEFT", iconSel, "RIGHT", 10, 0)
    prioBox:SetText("1")
    prioBox:SetNumeric(true)
    TankMark.editPrio = prioBox
    
    -- Priority Up Button (▲)
    local prioUp = CreateFrame("Button", nil, addGroup)
    prioUp:SetWidth(16)
    prioUp:SetHeight(12)
    prioUp:SetPoint("LEFT", prioBox, "RIGHT", 2, 6)
    prioUp:SetNormalTexture("Interface\\Buttons\\UI-ScrollBar-ScrollUpButton-Up")
    prioUp:SetScript("OnClick", function()
        local current = tonumber(prioBox:GetText()) or 1
        prioBox:SetText(math.min(current + 1, 9))
    end)
    
    -- Priority Down Button (▼)
    local prioDown = CreateFrame("Button", nil, addGroup)
    prioDown:SetWidth(16)
    prioDown:SetHeight(12)
    prioDown:SetPoint("LEFT", prioBox, "RIGHT", 2, -6)
    prioDown:SetNormalTexture("Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Up")
    prioDown:SetScript("OnClick", function()
        local current = tonumber(prioBox:GetText()) or 1
        prioBox:SetText(math.max(current - 1, 1))
    end)
    
    -- CC Button
    local cBtn = CreateFrame("Button", "TMClassBtn", addGroup, "UIPanelButtonTemplate")
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
    local lBtn = CreateFrame("Button", "TMLockBtn", addGroup, "UIPanelButtonTemplate")
    lBtn:SetWidth(75)
    lBtn:SetHeight(20)
    lBtn:SetPoint("LEFT", cBtn, "RIGHT", 5, 0)
    lBtn:SetText("Lock Mark")
    lBtn:SetScript("OnClick", function() TankMark:ToggleLockState() end)
    lBtn:Disable()

	-- Add tooltip for when disabled due to sequential marks
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
    local saveBtn = CreateFrame("Button", "TMSaveBtn", addGroup, "UIPanelButtonTemplate")
    saveBtn:SetWidth(50)
    saveBtn:SetHeight(20)
    saveBtn:SetPoint("LEFT", lBtn, "RIGHT", 5, 0)
    saveBtn:SetText("Save")
    saveBtn:SetScript("OnClick", function() TankMark:SaveFormData() end)
    saveBtn:Disable()
    TankMark.saveBtn = saveBtn
    
    -- Cancel Button
    local cancelBtn = CreateFrame("Button", "TMCancelBtn", addGroup, "UIPanelButtonTemplate")
    cancelBtn:SetWidth(20)
    cancelBtn:SetHeight(20)
    cancelBtn:SetPoint("LEFT", saveBtn, "RIGHT", 2, 0)
    cancelBtn:SetText("X")
    cancelBtn:SetScript("OnClick", function() TankMark:ResetEditor() end)
    cancelBtn:Hide()
    TankMark.cancelBtn = cancelBtn
    
    -- [v0.23] SEQUENTIAL MARKS SECTION
    
    -- Divider Label: "Marking Sequence:"
    local seqLabel = addGroup:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    seqLabel:SetPoint("TOPLEFT", 0, -60)
    seqLabel:SetText("|cff888888Marking Sequence:|r")
    
    -- "+ Add More Marks" Clickable Text
	local addMoreText = addGroup:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	addMoreText:SetPoint("TOPLEFT", seqLabel, "BOTTOMLEFT", 0, -5)
	addMoreText:SetText("|cff00ccff+ Add More Marks|r")
	addMoreText:Show()  -- Show by default
	TankMark.addMoreMarksText = addMoreText

	-- Make it clickable
	local addMoreBtn = CreateFrame("Button", nil, addGroup)
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

	-- Store button reference globally
	TankMark.addMoreMarksBtn = addMoreBtn

	-- Store button reference for enable/disable
	addMoreText.clickFrame = addMoreBtn
    
    -- Sequential Marks Scroll Frame (max 3 visible rows)
	local seqScroll = CreateFrame("ScrollFrame", "TMSeqScrollFrame", addGroup, "FauxScrollFrameTemplate")
	seqScroll:SetWidth(360)
	seqScroll:SetHeight(72)  -- 3 rows × 24px
	seqScroll:SetPoint("TOPLEFT", addMoreText, "BOTTOMLEFT", 0, -5)
	seqScroll:Hide()
	TankMark.sequentialScrollFrame = seqScroll

	-- CREATE SCROLL CHILD (the actual content container)
	local seqContent = CreateFrame("Frame", nil, seqScroll)
	seqContent:SetWidth(360)
	seqContent:SetHeight(168)  -- 7 rows × 24px (full content height)
	seqScroll:SetScrollChild(seqContent)

	seqScroll:SetScript("OnVerticalScroll", function()
		FauxScrollFrame_OnVerticalScroll(24, function()
			TankMark:RefreshSequentialRows()
		end)
	end)

	-- Create 7 sequential row frames (max additional marks)
	TankMark.sequentialRows = {}
	for i = 1, 7 do
		local seqRow = CreateFrame("Frame", "TMSeqRow"..i, seqContent)
		seqRow:SetWidth(340)
		seqRow:SetHeight(24)
		seqRow:SetPoint("TOPLEFT", 0, -((i-1)*24))
		
		-- Row number badge
		seqRow.number = seqRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		seqRow.number:SetPoint("LEFT", 5, 0)
		seqRow.number:SetText("|cff888888#" .. (i + 1) .. "|r")
		
		-- Icon selector
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
			
			-- Reinitialize menu with current dataIndex
			UIDropDownMenu_Initialize(seqIconDrop, function() 
				TankMark:InitSequentialIconMenu(rowIndex)
			end, "MENU")
			ToggleDropDownMenu(1, nil, seqIconDrop, "cursor", 0, 0)
		end)
		
		-- CC Button
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
			
			-- Reinitialize menu with current dataIndex
			UIDropDownMenu_Initialize(seqClassDrop, function() 
				TankMark:InitSequentialClassMenu(rowIndex)
			end, "MENU")
			ToggleDropDownMenu(1, nil, seqClassDrop, "cursor", 0, 0)
		end)
		
		-- Remove button [X]
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
    return t1
end
