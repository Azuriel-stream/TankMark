-- TankMark: v0.4.3-dev
-- File: TankMark_Options.lua
-- Description: The GUI Configuration Panel (Final Visual Fix: Scrollbar overlap)

if not TankMark then return end

TankMark.optionsFrame = nil
TankMark.selectedIcon = 8 
TankMark.currentTab = 1
TankMark.mobRows = {} 
TankMark.profileRows = {}

-- ==========================================================
-- 1. HELPER FUNCTIONS
-- ==========================================================

function TankMark:CreateEditBox(parent, title, width)
    local eb = CreateFrame("EditBox", nil, parent)
    eb:SetAutoFocus(false)
    eb:SetWidth(width)
    eb:SetHeight(20)
    eb:SetFontObject("GameFontHighlight")
    eb:SetTextInsets(8, 8, 0, 0)

    eb:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 5, right = 5, top = 5, bottom = 5 }
    })
    eb:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
    eb:SetBackdropColor(0, 0, 0, 0.8)

    local label = eb:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    label:SetPoint("BOTTOMLEFT", eb, "TOPLEFT", -5, 2)
    label:SetText(title)
    
    eb:SetScript("OnEscapePressed", function() eb:ClearFocus() end)
    eb:SetScript("OnEditFocusGained", function() this:HighlightText() end)
    eb:SetScript("OnEditFocusLost", function() this:HighlightText(0,0) end)
    
    return eb
end

function TankMark:UpdateTabs()
    if TankMark.currentTab == 1 then
        TankMark.tab1:Show()
        TankMark.tab2:Hide()
        TankMark:RefreshMobList() 
    else
        TankMark.tab1:Hide()
        TankMark.tab2:Show()
        TankMark:RefreshProfileUI() 
    end
end

-- ==========================================================
-- 2. TAB 1 LOGIC: MOB DATABASE
-- ==========================================================

function TankMark:RefreshMobList()
    if not TankMark.scrollChild then return end
    
    for _, row in pairs(TankMark.mobRows) do row:Hide() end
    
    local zone = TankMark.editZone:GetText()
    if not zone or not TankMarkDB.Zones[zone] then return end
    
    local mobList = {}
    for mobName, data in pairs(TankMarkDB.Zones[zone]) do
        table.insert(mobList, {name = mobName, prio = data.prio, mark = data.mark})
    end
    table.sort(mobList, function(a,b) return a.prio < b.prio end)
    
    local yOffset = -5
    for i, data in ipairs(mobList) do
        local mobName = data.name; local mobZone = zone
        local row = TankMark.mobRows[i]
        
        if not row then
            row = CreateFrame("Frame", nil, TankMark.scrollChild)
            row:SetWidth(260); row:SetHeight(20)
            
            row.icon = row:CreateTexture(nil, "ARTWORK")
            row.icon:SetWidth(16); row.icon:SetHeight(16)
            row.icon:SetPoint("LEFT", 5, 0)
            row.icon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
            
            row.text = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
            row.text:SetPoint("LEFT", row.icon, "RIGHT", 5, 0)
            
            row.del = CreateFrame("Button", nil, row, "UIPanelCloseButton")
            row.del:SetWidth(20); row.del:SetHeight(20)
            -- VISUAL FIX: Increased offset from -5 to -25 to clear scrollbar
            row.del:SetPoint("RIGHT", -10, 0)
            
            TankMark.mobRows[i] = row
        end
        
        row:SetPoint("TOPLEFT", TankMark.scrollChild, "TOPLEFT", 5, yOffset)
        SetRaidTargetIconTexture(row.icon, data.mark)
        row.text:SetText("(Prio " .. data.prio .. ") " .. data.name)
        row.del:SetScript("OnClick", function() TankMark:DeleteMob(mobZone, mobName) end)
        row:Show()
        yOffset = yOffset - 20
    end
end

function TankMark:SaveFormData()
    local zone = TankMark.editZone:GetText()
    local mob = TankMark.editMob:GetText()
    local prio = tonumber(TankMark.editPrio:GetText()) or 1
    local icon = TankMark.selectedIcon
    
    if zone == "" or mob == "" then return end
    if not TankMarkDB.Zones[zone] then TankMarkDB.Zones[zone] = {} end
    
    TankMarkDB.Zones[zone][mob] = { ["prio"] = prio, ["mark"] = icon }
    TankMark:Print("Saved: " .. mob)
    TankMark.editMob:SetText("")
    TankMark:RefreshMobList()
end

function TankMark:DeleteMob(zone, mob)
    if TankMarkDB.Zones[zone] then
        TankMarkDB.Zones[zone][mob] = nil
        TankMark:RefreshMobList()
    end
end

-- ==========================================================
-- 3. TAB 2 LOGIC: TEAM PROFILES
-- ==========================================================

function TankMark:SaveAllProfiles()
    local zone = TankMark.profileZone:GetText()
    if not zone or zone == "" then 
        TankMark:Print("Error: Profile Zone cannot be empty.")
        return 
    end
    
    if not TankMarkDB.Profiles[zone] then TankMarkDB.Profiles[zone] = {} end
    
    -- Loop through all 8 rows
    for i = 1, 8 do
        if TankMark.profileRows[i] then
            local text = TankMark.profileRows[i].edit:GetText()
            
            -- 1. Update Database
            if text == "" then 
                TankMarkDB.Profiles[zone][i] = nil
            else
                TankMarkDB.Profiles[zone][i] = text
            end
            
            -- 2. Update Live Session (The Fix)
            -- If we are in the zone we are editing, apply changes immediately
            if zone == GetRealZoneText() then
                if text == "" then
                    -- If removed in config, remove from session
                    TankMark.sessionAssignments[i] = nil
                else
                    -- If changed in config, overwrite session
                    TankMark.sessionAssignments[i] = text
                end
            end
        end
    end
    
    -- 3. Refresh HUD to show changes
    if TankMark.UpdateHUD then TankMark:UpdateHUD() end
    
    TankMark:Print("Profile saved & session updated for: " .. zone)
end

function TankMark:RefreshProfileUI()
    local zone = TankMark.profileZone:GetText()
    if not TankMarkDB.Profiles[zone] then TankMarkDB.Profiles[zone] = {} end
    
    local data = TankMarkDB.Profiles[zone]
    
    for i = 1, 8 do
        local row = TankMark.profileRows[i]
        local assignedName = data[i] or ""
        row.edit:SetText(assignedName)
    end
end

-- ==========================================================
-- 4. MAIN FRAME CONSTRUCTION
-- ==========================================================

function TankMark:CreateOptionsFrame()
    local f = CreateFrame("Frame", "TankMarkOptions", UIParent)
    f:SetWidth(600); f:SetHeight(400)
    f:SetPoint("CENTER", 0, 0)
    f:SetFrameStrata("HIGH")
    f:EnableMouse(true); f:SetMovable(true)
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
    txt:SetText("TankMark Configuration")

    -- Close Button
    local cb = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    cb:SetPoint("TOPRIGHT", f, "TOPRIGHT", -5, -5)
    cb:SetScript("OnClick", function() f:Hide() end)

    -- === TABS ===
    local tab1 = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    tab1:SetWidth(120); tab1:SetHeight(30)
    tab1:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 10, 5) 
    tab1:SetText("Mob Database")
    tab1:SetScript("OnClick", function() TankMark.currentTab = 1; TankMark:UpdateTabs() end)
    
    local tab2 = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    tab2:SetWidth(120); tab2:SetHeight(30)
    tab2:SetPoint("LEFT", tab1, "RIGHT", 5, 0)
    tab2:SetText("Team Profiles")
    tab2:SetScript("OnClick", function() TankMark.currentTab = 2; TankMark:UpdateTabs() end)

    -- ==========================================================
    -- TAB 1 CONTENT (The Mob Editor)
    -- ==========================================================
    local t1 = CreateFrame("Frame", nil, f)
    t1:SetPoint("TOPLEFT", 15, -40)
    t1:SetPoint("BOTTOMRIGHT", -15, 50)
    TankMark.tab1 = t1
    
    f.editZone = TankMark:CreateEditBox(t1, "Zone Name", 200)
    f.editZone:SetPoint("TOPLEFT", t1, "TOPLEFT", 15, -20)
    f.editZone:SetScript("OnEnterPressed", function() this:ClearFocus(); TankMark:RefreshMobList() end)
    
    f.editMob = TankMark:CreateEditBox(t1, "Mob Name", 200)
    f.editMob:SetPoint("TOPLEFT", f.editZone, "BOTTOMLEFT", 0, -30)
    
    f.editPrio = TankMark:CreateEditBox(t1, "Prio (1-5)", 50)
    f.editPrio:SetPoint("TOPLEFT", f.editMob, "BOTTOMLEFT", 0, -30)
    f.editPrio:SetNumeric(true); f.editPrio:SetText("1")
    
    local ib = CreateFrame("Button", nil, t1)
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

    local sb = CreateFrame("Button", nil, t1, "UIPanelButtonTemplate")
    sb:SetWidth(100); sb:SetHeight(30)
    sb:SetPoint("TOPLEFT", f.editPrio, "BOTTOMLEFT", 0, -30)
    sb:SetText("Save Mob")
    sb:SetScript("OnClick", function() TankMark:SaveFormData() end)
    
    local listBg = CreateFrame("Frame", nil, t1)
    listBg:SetWidth(280); listBg:SetHeight(230)
    listBg:SetPoint("TOPRIGHT", t1, "TOPRIGHT", -10, -20)
    listBg:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 5, right = 5, top = 5, bottom = 5 }
    })
    listBg:SetBackdropColor(0, 0, 0, 0.5)
    
    local scrollFrame = CreateFrame("ScrollFrame", "TMScrollFrame", listBg, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 0, -5)
    scrollFrame:SetPoint("BOTTOMRIGHT", -30, 5)
    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetWidth(260); scrollChild:SetHeight(500)
    scrollFrame:SetScrollChild(scrollChild)
    TankMark.scrollChild = scrollChild

    -- ==========================================================
    -- TAB 2 CONTENT (The Profile Editor)
    -- ==========================================================
    local t2 = CreateFrame("Frame", nil, f)
    t2:SetPoint("TOPLEFT", 15, -40)
    t2:SetPoint("BOTTOMRIGHT", -15, 50)
    t2:Hide() 
    TankMark.tab2 = t2
    
    local pZone = TankMark:CreateEditBox(t2, "Profile Zone (Type to change)", 250)
    pZone:SetPoint("TOP", t2, "TOP", 0, -30) 
    pZone:SetScript("OnEnterPressed", function() this:ClearFocus(); TankMark:RefreshProfileUI() end)
    TankMark.profileZone = pZone
    
    local pSave = CreateFrame("Button", nil, t2, "UIPanelButtonTemplate")
    pSave:SetWidth(120); pSave:SetHeight(30)
    pSave:SetPoint("LEFT", pZone, "RIGHT", 20, 0)
    pSave:SetText("Save Profile")
    pSave:SetScript("OnClick", function() TankMark:SaveAllProfiles() end)
    
    local pY = -80
    local pX = 20
    
    for i = 8, 1, -1 do
        local row = CreateFrame("Frame", nil, t2)
        row:SetWidth(260); row:SetHeight(30)
        row:SetPoint("TOPLEFT", t2, "TOPLEFT", pX, pY)
        
        local ico = row:CreateTexture(nil, "ARTWORK")
        ico:SetWidth(20); ico:SetHeight(20)
        ico:SetPoint("LEFT", 0, 0)
        ico:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
        SetRaidTargetIconTexture(ico, i)
        
        local eb = TankMark:CreateEditBox(row, "", 120)
        eb:SetPoint("LEFT", ico, "RIGHT", 10, 0)
        row.edit = eb
        
        local btn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        btn:SetWidth(60); btn:SetHeight(20)
        btn:SetPoint("LEFT", eb, "RIGHT", 5, 0)
        btn:SetText("Target")
        btn:SetFont("Fonts\\FRIZQT__.TTF", 10)
        btn:SetScript("OnClick", function()
            if UnitExists("target") and UnitIsPlayer("target") then
                eb:SetText(UnitName("target"))
            end
        end)
        
        TankMark.profileRows[i] = row
        
        pY = pY - 40
        if i == 5 then 
            pY = -80
            pX = 300
        end
    end

    TankMark.editZone = f.editZone
    TankMark.editMob = f.editMob
    TankMark.editPrio = f.editPrio
    TankMark.optionsFrame = f

    TankMark:Print("Options frame updated (v0.4.3).")
end

function TankMark:ShowOptions()
    if not TankMark.optionsFrame then TankMark:CreateOptionsFrame() end
    
    if not TankMark.optionsFrame:IsVisible() then
        TankMark.optionsFrame:Show()
    end
    
    local cz = GetRealZoneText()
    if cz and cz ~= "" then
        TankMark.editZone:SetText(cz)
        TankMark.profileZone:SetText(cz)
    end
    
    TankMark:UpdateTabs()
end