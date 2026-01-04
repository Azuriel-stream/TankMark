-- TankMark: v0.15 (HUD & Context Menu)
-- File: TankMark_HUD.lua

if not TankMark then return end

TankMark.hudFrame = nil
TankMark.hudRows = {}
TankMark.menuFrame = nil

-- ==========================================================
-- 1. MENU INITIALIZATION
-- ==========================================================
function TankMark:InitMenu()
    local info = {}
    
    -- Header
    info = {}
    info.text = "TankMark Actions"
    info.isTitle = 1
    UIDropDownMenu_AddButton(info, 1)
    
    -- Master Toggle
    info = {}
    info.text = "Enable Auto-Marking"
    info.checked = TankMark.IsActive
    info.func = function() 
        TankMark.IsActive = not TankMark.IsActive
        CloseDropDownMenus()
        ToggleDropDownMenu(1, nil, TankMark.menuFrame, "cursor", 0, 0)
        TankMark:Print("Auto-Marking is now: " .. (TankMark.IsActive and "|cff00ff00ON|r" or "|cffff0000OFF|r"))
    end
    UIDropDownMenu_AddButton(info, 1)

    -- Separator
    info = {}
    info.text = ""
    info.isTitle = 1
    UIDropDownMenu_AddButton(info, 1)
    
    -- Enable All
    info = {}
    info.text = "Enable All Marks"
    info.func = function() 
        TankMark.disabledMarks = {} 
        TankMark:UpdateHUD() 
    end
    info.notCheckable = 1
    UIDropDownMenu_AddButton(info, 1)

    -- Announce
    info = {}
    info.text = "Announce Assignments"
    info.func = function() TankMark:AnnounceAssignments() end
    info.notCheckable = 1
    UIDropDownMenu_AddButton(info, 1)
    
    -- Sync
    info = {}
    info.text = "Sync Zone Data"
    info.func = function() TankMark:BroadcastZone() end
    info.notCheckable = 1
    UIDropDownMenu_AddButton(info, 1)
    
    -- Config
    info = {}
    info.text = "Open Configuration"
    info.func = function() TankMark:ShowOptions() end
    info.notCheckable = 1
    UIDropDownMenu_AddButton(info, 1)
    
    -- Separator
    info = {}
    info.text = ""
    info.isTitle = 1
    UIDropDownMenu_AddButton(info, 1)

    -- Unmark Target
    info = {}
    info.text = "Unmark Current Target"
    info.func = function() SetRaidTarget("target", 0) end
    info.notCheckable = 1
    UIDropDownMenu_AddButton(info, 1)
    
    -- Reset Session
    info = {}
    info.text = "|cffff0000Reset Session|r"
    info.func = function() TankMark:ResetSession() end
    info.notCheckable = 1
    UIDropDownMenu_AddButton(info, 1)
    
    -- Close
    info = {}
    info.text = "Close Menu"
    info.func = function() CloseDropDownMenus() end
    info.notCheckable = 1
    UIDropDownMenu_AddButton(info, 1)
end

-- ==========================================================
-- 2. FRAME CREATION
-- ==========================================================
function TankMark:CreateHUD()
    TankMark.menuFrame = CreateFrame("Frame", "TankMarkHUDMenu", UIParent, "UIDropDownMenuTemplate")
    UIDropDownMenu_Initialize(TankMark.menuFrame, function() TankMark:InitMenu() end, "MENU")

    local f = CreateFrame("Frame", "TankMarkHUD", UIParent)
    f:SetWidth(200); f:SetHeight(150)
    f:SetPoint("CENTER", UIParent, "CENTER", 200, 0) 
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
    f:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)
    
    f:SetScript("OnMouseUp", function()
        if arg1 == "RightButton" then
            ToggleDropDownMenu(1, nil, TankMark.menuFrame, "cursor", 0, 0)
        end
    end)
    
    f.header = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.header:SetPoint("TOP", f, "TOP", 0, -5)
    f.header:SetText("TankMark HUD")

    for i = 8, 1, -1 do
        local row = CreateFrame("Button", nil, f) 
        row:SetWidth(180); row:SetHeight(20)
        row:SetID(i) 
        
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetWidth(16); row.icon:SetHeight(16)
        row.icon:SetPoint("LEFT", row, "LEFT", 0, 0)
        row.icon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
        SetRaidTargetIconTexture(row.icon, i)
        
        row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        row.text:SetPoint("LEFT", row.icon, "RIGHT", 5, 0)
        row.text:SetText("")
        
        row:EnableMouse(true)
        row:RegisterForClicks("LeftButtonUp")
        row:SetScript("OnClick", function() 
            TankMark:ToggleMarkState(this:GetID()) 
        end)
        
        row:Hide() 
        TankMark.hudRows[i] = row
    end
    
    TankMark.hudFrame = f
    TankMark:UpdateHUD()
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
    
    local activeRows = 0
    local lastVisibleRow = nil 
    local zone = GetRealZoneText()
    
    local renderList = {}
    local added = {} -- Tracks if mark exists in Profile
    
    -- 1. Build List from Profile
    if TankMarkProfileDB and TankMarkProfileDB[zone] then
        for _, entry in ipairs(TankMarkProfileDB[zone]) do
            if entry.mark then
                table.insert(renderList, entry.mark)
                added[entry.mark] = true
            end
        end
    end
    
    -- 2. Empty Profile Warning
    if table.getn(renderList) == 0 then
        local warningRow = TankMark.hudRows[8] 
        warningRow.icon:SetTexture(nil) 
        warningRow.text:SetText("|cffff0000NO PROFILE LOADED|r")
        warningRow:ClearAllPoints()
        warningRow:SetPoint("TOPLEFT", TankMark.hudFrame, "TOPLEFT", 10, -25)
        warningRow:Show()
        for i = 7, 1, -1 do TankMark.hudRows[i]:Hide() end
        TankMark.hudFrame:Show()
        TankMark.hudFrame:SetHeight(50)
        return
    end
    
    -- 3. Add Leftovers (Standard desc order)
    for i = 8, 1, -1 do
        if not added[i] then
            table.insert(renderList, i)
        end
    end
    
    -- 4. Render Loop
    for _, i in ipairs(renderList) do
        local row = TankMark.hudRows[i]
        local assignedPlayer = TankMark.sessionAssignments[i]
        local activeMob = TankMark.activeMobNames[i]
        
        local textToShow = nil
        
        if assignedPlayer then
            textToShow = "|cff00ff00" .. assignedPlayer .. "|r"
        elseif activeMob then
            textToShow = "|cffffffff" .. activeMob .. "|r"
        end
        
        -- [FIX] Logic Check:
        -- Show row if:
        -- A. It is part of the Profile (added[i]) -> Show even if empty
        -- B. It has an active assignment/mob (hasText)
        -- C. It is disabled (to allow re-enabling)
        
        local isProfileMark = added[i]
        local hasAssignment = (textToShow ~= nil)
        local isDisabled = TankMark.disabledMarks[i]
        
        -- Apply Visual Disable (Dimming)
        if isDisabled then
            row.icon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
            SetRaidTargetIconTexture(row.icon, i)
            row.icon:SetVertexColor(0.3, 0.3, 0.3)
            
            if textToShow then
                local plainText = string.gsub(textToShow, "|c%x%x%x%x%x%x%x%x", "")
                plainText = string.gsub(plainText, "|r", "")
                textToShow = "|cff888888" .. plainText .. " (OFF)|r"
            else
                textToShow = "|cff888888(Disabled)|r"
            end
        else
            row.icon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
            SetRaidTargetIconTexture(row.icon, i)
            row.icon:SetVertexColor(1, 1, 1)
        end
        
        -- Display Decision
        if isProfileMark or hasAssignment or isDisabled then
            -- [FIX] If from profile but empty, show placeholder
            if not textToShow then 
                textToShow = "|cff888888(Free)|r" 
            end
            
            row.text:SetText(textToShow)
            row:ClearAllPoints()
            if not lastVisibleRow then
                row:SetPoint("TOPLEFT", TankMark.hudFrame, "TOPLEFT", 10, -25)
            else
                row:SetPoint("TOPLEFT", lastVisibleRow, "BOTTOMLEFT", 0, 0)
            end
            row:Show()
            lastVisibleRow = row
            activeRows = activeRows + 1
        else
            row:Hide()
        end
    end
    
    if activeRows > 0 then
        TankMark.hudFrame:Show()
        TankMark.hudFrame:SetHeight((activeRows * 20) + 30)
    else
        TankMark.hudFrame:Hide()
    end
end