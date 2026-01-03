-- TankMark: v0.14 (HUD & Context Menu)
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
    
    -- Master Toggle (Enable/Disable)
    info = {}
    info.text = "Enable Auto-Marking"
    info.checked = TankMark.IsActive
    info.func = function() 
        TankMark.IsActive = not TankMark.IsActive
        -- Refresh the menu to show new check state
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

    -- Unmark Target (New)
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
    
    -- Right Click Handler
    f:SetScript("OnMouseUp", function()
        if arg1 == "RightButton" then
            ToggleDropDownMenu(1, nil, TankMark.menuFrame, "cursor", 0, 0)
        end
    end)
    
    f.header = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.header:SetPoint("TOP", f, "TOP", 0, -5)
    f.header:SetText("TankMark HUD")

    for i = 8, 1, -1 do
        local row = CreateFrame("Frame", nil, f)
        row:SetWidth(180); row:SetHeight(20)
        
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetWidth(16); row.icon:SetHeight(16)
        row.icon:SetPoint("LEFT", row, "LEFT", 0, 0)
        row.icon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
        SetRaidTargetIconTexture(row.icon, i)
        
        row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        row.text:SetPoint("LEFT", row.icon, "RIGHT", 5, 0)
        row.text:SetText("")
        
        row:Hide() 
        TankMark.hudRows[i] = row
    end
    
    TankMark.hudFrame = f
    TankMark:UpdateHUD()
end

-- ==========================================================
-- 3. UPDATE LOGIC
-- ==========================================================
function TankMark:UpdateHUD()
    if not TankMark.hudFrame then TankMark:CreateHUD() end
    
    local activeRows = 0
    local lastVisibleRow = nil 
    
    for i = 8, 1, -1 do
        local row = TankMark.hudRows[i]
        local assignedPlayer = TankMark.sessionAssignments[i]
        local activeMob = TankMark.activeMobNames[i]
        local textToShow = nil
        
        if assignedPlayer then
            textToShow = "|cff00ff00" .. assignedPlayer .. "|r"
        elseif activeMob then
            textToShow = "|cffffffff" .. activeMob .. "|r"
        end
        
        if textToShow then
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