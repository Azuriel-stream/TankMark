-- TankMark: v0.24 (Release Candidate)
-- File: TankMark_HUD.lua
-- [PHASE 2] Use cached zone lookups

if not TankMark then return end

-- ==========================================================
-- LOCALIZATIONS
-- ==========================================================

-- Import shared localizations
local L = TankMark.Locals

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
	local targetName = L._UnitName("target")
    local canAssign = (targetName and L._UnitIsPlayer("target"))
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
	for _, entry in L._ipairs(list) do
		if entry.mark == iconID then
			entry.tank = playerName
			found = true
			break
		end
	end
	
	if not found then
		L._tinsert(list, { mark = iconID, tank = playerName, healers = "" })
		-- Sort new list by ID desc (Skull first)
		L._tsort(list, function(a,b) return a.mark > b.mark end)
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
    
    -- [v0.22] Restore saved position or use default
    if TankMarkCharConfig and TankMarkCharConfig.HUD and TankMarkCharConfig.HUD.point then
        local pos = TankMarkCharConfig.HUD
        f:SetPoint(pos.point, pos.relativeTo or UIParent, pos.relativePoint, pos.xOffset, pos.yOffset)
    else
        -- Default position (first-time user)
        f:SetPoint("CENTER", UIParent, "CENTER", 200, 0)
    end
    
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
    f:SetScript("OnDragStop", function()
        this:StopMovingOrSizing()
        -- [v0.22] Save HUD position
        TankMark:SaveHUDPosition()
    end)
    
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
    
    -- Create 8 rows (Skull to Star)
    for i = 8, 1, -1 do
        local row = CreateFrame("Button", nil, f)
        row:SetWidth(180); row:SetHeight(20)
        row:SetID(i)
        
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetWidth(16); row.icon:SetHeight(16)
        row.icon:SetPoint("LEFT", row, "LEFT", 0, 0)
        row.icon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
        L._SetRaidTargetIconTexture(row.icon, i)
        
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
-- [v0.24] CLASS COLOR HELPER
-- ==========================================================

function TankMark:GetClassColor(class)
    -- Vanilla WoW class colors
    if class == "Warrior" then return "|cffC79C6E" end      -- Tan
    if class == "Paladin" then return "|cffF58CBA" end      -- Pink
    if class == "Hunter" then return "|cffABD473" end       -- Green
    if class == "Rogue" then return "|cffFFF569" end        -- Yellow
    if class == "Priest" then return "|cffFFFFFF" end       -- White
    if class == "Shaman" then return "|cff0070DE" end       -- Blue
    if class == "Mage" then return "|cff69CCF0" end         -- Light Blue
    if class == "Warlock" then return "|cff9482C9" end      -- Purple
    if class == "Druid" then return "|cffFF7D0A" end        -- Orange
    return "|cff00ff00"  -- Default green if class unknown
end

-- ==========================================================
-- [v0.24] HUD ROW RENDERING HELPER
-- ==========================================================

function TankMark:RenderHUDRow(row, markID, isProfileMark)
    local assignedPlayer = TankMark.sessionAssignments[markID]
    local activeMob = TankMark.activeMobNames[markID]
    local textToShow = nil
    
    if assignedPlayer then
        -- [v0.24] Apply class-colored names
        local unit = TankMark:FindUnitByName(assignedPlayer)
        local isInRaid = TankMark:IsPlayerInRaid(assignedPlayer)
        
        if unit and isInRaid then
            -- Get class color
            local class = L._UnitClass(unit)
            local classColor = TankMark:GetClassColor(class)
            textToShow = classColor .. assignedPlayer .. "|r"
        elseif isInRaid then
            -- In raid but unit not found (shouldn't happen, but fallback to green)
            textToShow = "|cff00ff00" .. assignedPlayer .. "|r"
        else
            -- Not in raid (red)
            textToShow = "|cffff0000" .. assignedPlayer .. "|r"
        end
    elseif activeMob then
        textToShow = "|cffffffff" .. activeMob .. "|r"
    end
    
    local isDisabled = TankMark.disabledMarks[markID]
    
    -- Apply Visual Disable (Dimming)
    if isDisabled then
        row.icon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
        L._SetRaidTargetIconTexture(row.icon, markID)
        row.icon:SetVertexColor(0.3, 0.3, 0.3)
        if textToShow then
            local plainText = L._gsub(textToShow, "|c%x%x%x%x%x%x%x%x", "")
            plainText = L._gsub(plainText, "|r", "")
            textToShow = "|cff888888" .. plainText .. " (OFF)|r"
        else
            textToShow = "|cff888888(Disabled)|r"
        end
    else
        row.icon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
        L._SetRaidTargetIconTexture(row.icon, markID)
        row.icon:SetVertexColor(1, 1, 1)
    end
    
    -- Default text for empty marks
    if not textToShow then
        textToShow = "|cff888888(Free)|r"
    end
    
    row.text:SetText(textToShow)
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
    
    local zone = TankMark:GetCachedZone()
    local tankMarks = {}
    local ccMarks = {}
    local added = {}
    
    -- 1. Build Lists from Profile (separate tank/CC)
    if TankMarkProfileDB and TankMarkProfileDB[zone] then
        for _, entry in L._ipairs(TankMarkProfileDB[zone]) do
            if entry.mark then
                added[entry.mark] = true
                local playerName = entry.tank
                
                -- [v0.24] Classify as tank or CC based on player class
                if playerName and playerName ~= "" and TankMark:IsPlayerCCClass(playerName) then
                    L._tinsert(ccMarks, entry.mark)
                else
                    L._tinsert(tankMarks, entry.mark)
                end
            end
        end
    end
    
    -- 2. Empty Profile Warning
	if L._tgetn(tankMarks) == 0 and L._tgetn(ccMarks) == 0 then
		local warningRow = TankMark.hudRows[8]
		warningRow.icon:SetTexture(nil)
		warningRow.text:SetText("|cffff0000NO PROFILE LOADED|r")
		warningRow:ClearAllPoints()
		warningRow:SetPoint("TOPLEFT", TankMark.hudFrame, "TOPLEFT", 10, -25)
		warningRow:Show()
		
		-- Hide all mark rows
		for i = 7, 1, -1 do TankMark.hudRows[i]:Hide() end
		
		-- [v0.24] Hide section headers
		if TankMark.hudFrame.tankHeader then TankMark.hudFrame.tankHeader:Hide() end
		if TankMark.hudFrame.ccHeader then TankMark.hudFrame.ccHeader:Hide() end
		
		TankMark.hudFrame:Show()
		TankMark.hudFrame:SetHeight(50)
		return
	end
    
    -- 3. Add Leftovers (marks not in profile)
    -- (Removed leftover marks - HUD only displays assigned marks)
    
    -- 4. Render Sections
    local lastVisibleRow = nil
    local activeRows = 0
    
    -- 4A. Render TANK Section
    if L._tgetn(tankMarks) > 0 then
        -- Create tank header if it doesn't exist
        if not TankMark.hudFrame.tankHeader then
            TankMark.hudFrame.tankHeader = TankMark.hudFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            TankMark.hudFrame.tankHeader:SetTextColor(1.0, 0.82, 0)
        end
        
        TankMark.hudFrame.tankHeader:SetText("TANKS")
        TankMark.hudFrame.tankHeader:ClearAllPoints()
        if not lastVisibleRow then
            TankMark.hudFrame.tankHeader:SetPoint("TOPLEFT", TankMark.hudFrame, "TOPLEFT", 10, -25)
        else
            TankMark.hudFrame.tankHeader:SetPoint("TOPLEFT", lastVisibleRow, "BOTTOMLEFT", 0, -5)
        end
        TankMark.hudFrame.tankHeader:Show()
        lastVisibleRow = TankMark.hudFrame.tankHeader
        activeRows = activeRows + 1
        
        -- Render tank marks
        for _, i in L._ipairs(tankMarks) do
            local row = TankMark.hudRows[i]
            TankMark:RenderHUDRow(row, i, added[i])
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", lastVisibleRow, "BOTTOMLEFT", 0, lastVisibleRow == TankMark.hudFrame.tankHeader and -2 or 0)
            row:Show()
            lastVisibleRow = row
            activeRows = activeRows + 1
        end
    else
        if TankMark.hudFrame.tankHeader then TankMark.hudFrame.tankHeader:Hide() end
    end
    
    -- 4B. Render CC Section
    if L._tgetn(ccMarks) > 0 then
        -- Create CC header if it doesn't exist
        if not TankMark.hudFrame.ccHeader then
            TankMark.hudFrame.ccHeader = TankMark.hudFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            TankMark.hudFrame.ccHeader:SetTextColor(1.0, 0.82, 0)
        end
        
        TankMark.hudFrame.ccHeader:SetText("CROWD CONTROL")
        TankMark.hudFrame.ccHeader:ClearAllPoints()
        if not lastVisibleRow then
            TankMark.hudFrame.ccHeader:SetPoint("TOPLEFT", TankMark.hudFrame, "TOPLEFT", 10, -25)
        else
            TankMark.hudFrame.ccHeader:SetPoint("TOPLEFT", lastVisibleRow, "BOTTOMLEFT", 0, -8)
        end
        TankMark.hudFrame.ccHeader:Show()
        lastVisibleRow = TankMark.hudFrame.ccHeader
        activeRows = activeRows + 1
        
        -- Render CC marks
        for _, i in L._ipairs(ccMarks) do
            local row = TankMark.hudRows[i]
            TankMark:RenderHUDRow(row, i, added[i])
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", lastVisibleRow, "BOTTOMLEFT", 0, lastVisibleRow == TankMark.hudFrame.ccHeader and -2 or 0)
            row:Show()
            lastVisibleRow = row
            activeRows = activeRows + 1
        end
    else
        if TankMark.hudFrame.ccHeader then TankMark.hudFrame.ccHeader:Hide() end
    end
    
    -- [v0.24] Hide all rows not rendered above (safety cleanup)
	for i = 1, 8 do
		if not added[i] then
			TankMark.hudRows[i]:Hide()
		end
	end
    
    if activeRows > 0 then
        TankMark.hudFrame:Show()
        TankMark.hudFrame:SetHeight((activeRows * 20) + 30)
    else
        TankMark.hudFrame:Hide()
    end
end

-- ==========================================================
-- [v0.22] HUD POSITION PERSISTENCE
-- ==========================================================

function TankMark:SaveHUDPosition()
    if not TankMark.hudFrame then return end
    
    local point, relativeTo, relativePoint, xOffset, yOffset = TankMark.hudFrame:GetPoint()
    
    -- Initialize if needed
    if not TankMarkCharConfig then TankMarkCharConfig = {} end
    if not TankMarkCharConfig.HUD then TankMarkCharConfig.HUD = {} end
    
    -- Save position (always anchor to UIParent for stability)
    TankMarkCharConfig.HUD.point = point
    TankMarkCharConfig.HUD.relativeTo = "UIParent"
    TankMarkCharConfig.HUD.relativePoint = relativePoint
    TankMarkCharConfig.HUD.xOffset = xOffset
    TankMarkCharConfig.HUD.yOffset = yOffset
end
