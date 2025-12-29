-- TankMark: v0.2-dev
-- File: TankMark_Options.lua
-- Description: The GUI Configuration Panel

if not TankMark then return end

TankMark.optionsFrame = nil
TankMark.selectedIcon = 8 -- Default to Skull

-- ==========================================================
-- 1. HELPER FUNCTIONS
-- ==========================================================

-- Helper: Create a styled EditBox using the safe Template
function TankMark:CreateEditBox(parent, title, width)
    -- Use "InputBoxTemplate" for stability, then style it
    local eb = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    eb:SetAutoFocus(false)
    eb:SetWidth(width)
    eb:SetHeight(20)
    
    -- Hide the default "InputBoxTemplate" textures (Left/Middle/Right)
    -- Note: In 1.12, we can't easily delete them, so we just strip the backdrop 
    -- and apply our own 'Dark Mode' look.
    
    -- Custom Backdrop (Dark Grey)
    eb:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 5, right = 5, top = 5, bottom = 5 }
    })
    eb:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
    eb:SetBackdropColor(0, 0, 0, 0.8) -- Darker background

    -- Label text
    local label = eb:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    label:SetPoint("BOTTOMLEFT", eb, "TOPLEFT", -5, 0)
    label:SetText(title)
    
    return eb
end

function TankMark:FillFormDefaults()
    if not TankMark.editZone then return end

    -- Fill Zone
    local currentZone = GetRealZoneText()
    if currentZone and currentZone ~= "" then
        TankMark.editZone:SetText(currentZone)
    end
    
    -- Fill Mob Name (if target exists and is not a player)
    if UnitExists("target") and not UnitIsPlayer("target") then
        TankMark.editMob:SetText(UnitName("target"))
    end
end

-- ==========================================================
-- 2. MAIN LOGIC
-- ==========================================================

function TankMark:ShowOptions()
    -- Create if missing
    if not TankMark.optionsFrame then
        TankMark:CreateOptionsFrame()
    end
    
    -- Safety Check: Did creation fail?
    if not TankMark.optionsFrame then
        TankMark:Print("Error: Could not create options frame.")
        return
    end

    -- Force show and fill
    if not TankMark.optionsFrame:IsVisible() then
        TankMark.optionsFrame:Show()
    end
    
    TankMark:FillFormDefaults()
end

function TankMark:SaveFormData()
    if not TankMark.editZone then return end
    
    local zone = TankMark.editZone:GetText()
    local mob = TankMark.editMob:GetText()
    local prio = tonumber(TankMark.editPrio:GetText()) or 1
    local icon = TankMark.selectedIcon
    
    if not zone or zone == "" then 
        TankMark:Print("Error: Zone Name is required.")
        return 
    end
    if not mob or mob == "" then 
        TankMark:Print("Error: Mob Name is required.")
        return 
    end
    
    -- Ensure Zone Table Exists
    if not TankMarkDB.Zones[zone] then
        TankMarkDB.Zones[zone] = {}
    end
    
    -- Save Data
    TankMarkDB.Zones[zone][mob] = {
        ["prio"] = prio,
        ["mark"] = icon,
        ["type"] = "KILL"
    }
    
    TankMark:Print("Saved: ["..mob.."] in ["..zone.."] = {rt"..icon.."}")
    TankMark.editMob:SetText("")
end

-- ==========================================================
-- 3. FRAME CONSTRUCTION
-- ==========================================================

function TankMark:CreateOptionsFrame()
    -- Main Window
    local f = CreateFrame("Frame", "TankMarkOptions", UIParent)
    f:SetWidth(350) 
    f:SetHeight(300) 
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    f:SetFrameStrata("HIGH")
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function() this:StartMoving() end)
    f:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)

    f:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 }
    })

    -- Header
    local t = f:CreateTexture(nil, "ARTWORK")
    t:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Header")
    t:SetWidth(300); t:SetHeight(64)
    t:SetPoint("TOP", f, "TOP", 0, 12)

    local txt = f:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    txt:SetPoint("TOP", t, "TOP", 0, -14)
    txt:SetText("TankMark Config")

    -- Close Button
    local cb = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    cb:SetPoint("TOPRIGHT", f, "TOPRIGHT", -5, -5)
    cb:SetScript("OnClick", function() f:Hide() end)

    -- === INPUTS ===
    -- 1. Zone Name
    f.editZone = TankMark:CreateEditBox(f, "Zone Name", 200)
    f.editZone:SetPoint("TOPLEFT", f, "TOPLEFT", 30, -50)
    
    -- 2. Mob Name
    f.editMob = TankMark:CreateEditBox(f, "Mob Name", 200)
    f.editMob:SetPoint("TOPLEFT", f.editZone, "BOTTOMLEFT", 0, -30)
    
    -- 3. Priority
    f.editPrio = TankMark:CreateEditBox(f, "Prio (1-5)", 50)
    f.editPrio:SetPoint("TOPLEFT", f.editMob, "BOTTOMLEFT", 0, -30)
    f.editPrio:SetNumeric(true)
    f.editPrio:SetText("1")
    
    -- 4. Icon Selector
    local ib = CreateFrame("Button", nil, f)
    ib:SetWidth(30); ib:SetHeight(30)
    ib:SetPoint("LEFT", f.editPrio, "RIGHT", 80, 0)
    
    ib.tex = ib:CreateTexture(nil, "ARTWORK")
    ib.tex:SetAllPoints(ib)
    ib.tex:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
    SetRaidTargetIconTexture(ib.tex, 8) -- Default Skull
    
    ib:SetScript("OnClick", function()
        TankMark.selectedIcon = TankMark.selectedIcon - 1
        if TankMark.selectedIcon < 1 then TankMark.selectedIcon = 8 end
        SetRaidTargetIconTexture(this.tex, TankMark.selectedIcon)
    end)
    f.iconBtn = ib

    local li = f:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    li:SetPoint("RIGHT", ib, "LEFT", -10, 0)
    li:SetText("Mark:")

    -- 5. Save Button
    local sb = CreateFrame("Button", "TMSaveBtn", f, "UIPanelButtonTemplate")
    sb:SetWidth(100); sb:SetHeight(30)
    sb:SetPoint("BOTTOM", f, "BOTTOM", 0, 30)
    sb:SetText("Save Mob")
    sb:SetScript("OnClick", function() TankMark:SaveFormData() end)

    -- Global refs
    TankMark.editZone = f.editZone
    TankMark.editMob = f.editMob
    TankMark.editPrio = f.editPrio
    TankMark.optionsFrame = f

    TankMark:Print("Options frame created successfully.")
end