-- TankMark: v0.16-dev (Main Options Container)
-- File: TankMark_Options.lua

if not TankMark then return end

-- Localizations
local _pairs = pairs
local _getglobal = getglobal

-- ==========================================================
-- 0. CONFIRMATION DIALOG SETUP
-- ==========================================================
StaticPopupDialogs["TANKMARK_WIPE_CONFIRM"] = {
    text = "%s", 
    button1 = "Yes",
    button2 = "No",
    OnAccept = function()
        if TankMark.pendingWipeAction then 
            TankMark.pendingWipeAction()
            TankMark.pendingWipeAction = nil
        end
    end,
    timeout = 0,
    whileDead = 1,
    hideOnEscape = 1,
}

TankMark.optionsFrame = nil
TankMark.currentTab = 1
TankMark.tab1 = nil
TankMark.tab2 = nil

function TankMark:ValidateDB()
    if not TankMarkDB then TankMarkDB = {} end
    if not TankMarkDB.Zones then TankMarkDB.Zones = {} end
    if not TankMarkDB.StaticGUIDs then TankMarkDB.StaticGUIDs = {} end
    if not TankMarkProfileDB then TankMarkProfileDB = {} end
end

function TankMark:UpdateTabs()
    if TankMark.currentTab == 1 then
        if TankMark.tab1 then TankMark.tab1:Show() end
        if TankMark.tab2 then TankMark.tab2:Hide() end
        -- Tab 1 Logic
        if TankMark.UpdateMobList then TankMark:UpdateMobList() end
    else
        if TankMark.tab1 then TankMark.tab1:Hide() end
        if TankMark.tab2 then TankMark.tab2:Show() end
        -- Tab 2 Logic
        if TankMark.LoadProfileToCache then TankMark:LoadProfileToCache() end
        if TankMark.UpdateProfileList then TankMark:UpdateProfileList() end
        
        if TankMark.UpdateHUD then TankMark:UpdateHUD() end
    end
end

function TankMark:CreateOptionsFrame()
    if TankMark.optionsFrame then return end
    TankMark:ValidateDB()
    
    local f = CreateFrame("Frame", "TankMarkOptions", UIParent)
    f:SetWidth(450); f:SetHeight(480) 
    f:SetPoint("CENTER", 0, 0)
    f:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 }
    })
    f:EnableMouse(true); f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function() f:StartMoving() end)
    f:SetScript("OnDragStop", function() f:StopMovingOrSizing() end)
    f:Hide()

    local t = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    t:SetPoint("TOP", 0, -15); t:SetText("TankMark Configuration")
    local cb = CreateFrame("Button", "TMCloseBtn", f, "UIPanelCloseButton"); cb:SetPoint("TOPRIGHT", -5, -5)

    -- === LOAD MODULES ===
    -- We assume functions are available from loaded files
    
    if TankMark.CreateMobTab then
        TankMark.tab1 = TankMark:CreateMobTab(f)
    end
    
    if TankMark.CreateProfileTab then
        TankMark.tab2 = TankMark:CreateProfileTab(f)
    end

    -- === TABS ===
    local tab1 = CreateFrame("Button", "TMTab1", f, "UIPanelButtonTemplate"); tab1:SetWidth(120); tab1:SetHeight(30); tab1:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 10, 5); tab1:SetText("Mob Database")
    tab1:SetScript("OnClick", function() TankMark.currentTab = 1; TankMark:UpdateTabs() end)
    
    local tab2 = CreateFrame("Button", "TMTab2", f, "UIPanelButtonTemplate"); tab2:SetWidth(120); tab2:SetHeight(30); tab2:SetPoint("LEFT", tab1, "RIGHT", 5, 0); tab2:SetText("Team Profiles")
    tab2:SetScript("OnClick", function() TankMark.currentTab = 2; TankMark:UpdateTabs() end)
    
    local mc = CreateFrame("CheckButton", "TM_MasterToggle", f, "UICheckButtonTemplate"); mc:SetWidth(24); mc:SetHeight(24); mc:SetPoint("TOPLEFT", 15, -10)
    _G[mc:GetName().."Text"]:SetText("Enable TankMark"); mc:SetChecked(TankMark.IsActive and 1 or nil)
    mc:SetScript("OnClick", function() TankMark.IsActive = this:GetChecked() and true or false; TankMark:Print("Auto-Marking " .. (TankMark.IsActive and "|cff00ff00ON|r" or "|cffff0000OFF|r")) end)
    
    TankMark.optionsFrame = f
    TankMark:Print("TankMark v0.16 Configuration Loaded.")
end

function TankMark:ShowOptions()
    if not TankMark.optionsFrame then TankMark:CreateOptionsFrame() end
    TankMark.optionsFrame:Show()
    TankMark:ValidateDB()
    
    -- Cleanup focus from other modules if they exist
    if TankMark.editPrio then TankMark.editPrio:ClearFocus() end
    if TankMark.searchBox then TankMark.searchBox:ClearFocus() end
    if TankMark.zoneModeCheck then TankMark.zoneModeCheck:SetChecked(TankMark.isZoneListMode) end
    
    local cz = GetRealZoneText()
    if TankMark.profileZoneDropdown then UIDropDownMenu_SetText(cz, TankMark.profileZoneDropdown) end
    TankMark:UpdateTabs()
end