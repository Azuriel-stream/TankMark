-- TankMark: v0.3-dev
-- File: TankMark_Options.lua
-- Description: The GUI Configuration Panel (Now with Database Viewer)

if not TankMark then return end

TankMark.optionsFrame = nil
TankMark.selectedIcon = 8 -- Default to Skull
TankMark.scrollChild = nil 
TankMark.mobRows = {} -- Store row frames to reuse them

-- ==========================================================
-- 1. HELPER FUNCTIONS
-- ==========================================================

function TankMark:CreateEditBox(parent, title, width)
    local eb = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    eb:SetAutoFocus(false)
    eb:SetWidth(width)
    eb:SetHeight(20)
    
    eb:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 5, right = 5, top = 5, bottom = 5 }
    })
    eb:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
    eb:SetBackdropColor(0, 0, 0, 0.8)

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
    
    -- Fill Mob Name
    if UnitExists("target") and not UnitIsPlayer("target") then
        TankMark.editMob:SetText(UnitName("target"))
    end
    
    -- REFRESH THE LIST
    TankMark:RefreshMobList()
end

-- ==========================================================
-- 2. MAIN LOGIC
-- ==========================================================

function TankMark:ShowOptions()
    if not TankMark.optionsFrame then
        TankMark:CreateOptionsFrame()
    end
    
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
    
    TankMark:Print("Saved: ["..mob.."] in ["..zone.."]")
    TankMark.editMob:SetText("")
    
    -- Refresh the list to show the new entry
    TankMark:RefreshMobList()
end

function TankMark:DeleteMob(zone, mob)
    if TankMarkDB.Zones[zone] and TankMarkDB.Zones[zone][mob] then
        TankMarkDB.Zones[zone][mob] = nil
        TankMark:Print("Deleted: " .. mob)
        TankMark:RefreshMobList()
    end
end

-- ==========================================================
-- 3. THE VIEWER (Scroll List)
-- ==========================================================

function TankMark:RefreshMobList()
    if not TankMark.scrollChild then return end
    
    -- 1. Hide all existing rows
    for _, row in pairs(TankMark.mobRows) do
        row:Hide()
    end
    
    -- 2. Get current zone from input box
    local zone = TankMark.editZone:GetText()
    if not zone or not TankMarkDB.Zones[zone] then return end
    
    -- 3. Create List of Mobs
    local mobList = {}
    for mobName, data in pairs(TankMarkDB.Zones[zone]) do
        table.insert(mobList, {name = mobName, prio = data.prio, mark = data.mark})
    end
    
    -- Sort by Priority (1 at top)
    table.sort(mobList, function(a,b) return a.prio < b.prio end)
    
    -- 4. Create/Update Rows
    local yOffset = -5
    for i, data in ipairs(mobList) do
        -- FIX: Capture the values locally so the button remembers the correct mob!
        local mobName = data.name
        local mobZone = zone
        
        -- Get or Create Row
        local row = TankMark.mobRows[i]
        if not row then
            row = CreateFrame("Frame", nil, TankMark.scrollChild)
            row:SetWidth(260)
            row:SetHeight(20)
            
            -- Icon
            row.icon = row:CreateTexture(nil, "ARTWORK")
            row.icon:SetWidth(16); row.icon:SetHeight(16)
            row.icon:SetPoint("LEFT", row, "LEFT", 5, 0)
            row.icon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
            
            -- Text
            row.text = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
            row.text:SetPoint("LEFT", row.icon, "RIGHT", 5, 0)
            
            -- Delete Button (X)
            row.del = CreateFrame("Button", nil, row, "UIPanelCloseButton")
            row.del:SetWidth(20); row.del:SetHeight(20)
            row.del:SetPoint("RIGHT", row, "RIGHT", -5, 0)
            
            TankMark.mobRows[i] = row
        end
        
        -- Update Row Data
        row:SetPoint("TOPLEFT", TankMark.scrollChild, "TOPLEFT", 5, yOffset)
        SetRaidTargetIconTexture(row.icon, data.mark)
        row.text:SetText("(Prio " .. data.prio .. ") " .. data.name)
        
        -- Update Delete Button Action using the CAPTURED variable (mobName)
        row.del:SetScript("OnClick", function() 
            TankMark:DeleteMob(mobZone, mobName) 
        end)
        
        row:Show()
        yOffset = yOffset - 20
    end
end

-- ==========================================================
-- 4. FRAME CONSTRUCTION
-- ==========================================================

function TankMark:CreateOptionsFrame()
    -- Main Window (Wider now: 600px)
    local f = CreateFrame("Frame", "TankMarkOptions", UIParent)
    f:SetWidth(600) 
    f:SetHeight(350) 
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
    t:SetWidth(400); t:SetHeight(64)
    t:SetPoint("TOP", f, "TOP", 0, 12)

    local txt = f:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    txt:SetPoint("TOP", t, "TOP", 0, -14)
    txt:SetText("TankMark Config & Database")

    -- Close Button
    local cb = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    cb:SetPoint("TOPRIGHT", f, "TOPRIGHT", -5, -5)
    cb:SetScript("OnClick", function() f:Hide() end)

    -- === LEFT SIDE: INPUT FORM ===
    f.editZone = TankMark:CreateEditBox(f, "Zone Name", 200)
    f.editZone:SetPoint("TOPLEFT", f, "TOPLEFT", 30, -50)
    -- Refresh list when Zone changes manually (on Enter)
    f.editZone:SetScript("OnEnterPressed", function() 
        this:ClearFocus()
        TankMark:RefreshMobList() 
    end)
    
    f.editMob = TankMark:CreateEditBox(f, "Mob Name", 200)
    f.editMob:SetPoint("TOPLEFT", f.editZone, "BOTTOMLEFT", 0, -30)
    
    f.editPrio = TankMark:CreateEditBox(f, "Prio (1-5)", 50)
    f.editPrio:SetPoint("TOPLEFT", f.editMob, "BOTTOMLEFT", 0, -30)
    f.editPrio:SetNumeric(true)
    f.editPrio:SetText("1")
    
    local ib = CreateFrame("Button", nil, f)
    ib:SetWidth(30); ib:SetHeight(30)
    ib:SetPoint("LEFT", f.editPrio, "RIGHT", 80, 0)
    ib.tex = ib:CreateTexture(nil, "ARTWORK")
    ib.tex:SetAllPoints(ib)
    ib.tex:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
    SetRaidTargetIconTexture(ib.tex, 8)
    ib:SetScript("OnClick", function()
        TankMark.selectedIcon = TankMark.selectedIcon - 1
        if TankMark.selectedIcon < 1 then TankMark.selectedIcon = 8 end
        SetRaidTargetIconTexture(this.tex, TankMark.selectedIcon)
    end)
    f.iconBtn = ib

    local sb = CreateFrame("Button", "TMSaveBtn", f, "UIPanelButtonTemplate")
    sb:SetWidth(100); sb:SetHeight(30)
    sb:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 30, 30)
    sb:SetText("Save Mob")
    sb:SetScript("OnClick", function() TankMark:SaveFormData() end)
    
    -- === RIGHT SIDE: SCROLL LIST ===
    
    -- 1. Background for List
    local listBg = CreateFrame("Frame", nil, f)
    listBg:SetWidth(280)
    listBg:SetHeight(250)
    listBg:SetPoint("TOPRIGHT", f, "TOPRIGHT", -30, -50)
    listBg:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 5, right = 5, top = 5, bottom = 5 }
    })
    listBg:SetBackdropColor(0, 0, 0, 0.5)
    
    -- Label
    local listHeader = listBg:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    listHeader:SetPoint("BOTTOMLEFT", listBg, "TOPLEFT", 0, 5)
    listHeader:SetText("Current Zone Database:")
    
    -- 2. ScrollFrame
    local scrollFrame = CreateFrame("ScrollFrame", "TMScrollFrame", listBg, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 0, -5)
    scrollFrame:SetPoint("BOTTOMRIGHT", -30, 5)
    
    -- 3. ScrollChild (The content inside the scroller)
    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetWidth(260)
    scrollChild:SetHeight(500) -- Initial height, effectively infinite
    scrollFrame:SetScrollChild(scrollChild)
    
    -- Save refs
    TankMark.editZone = f.editZone
    TankMark.editMob = f.editMob
    TankMark.editPrio = f.editPrio
    TankMark.optionsFrame = f
    TankMark.scrollChild = scrollChild

    TankMark:Print("Options frame created.")
end