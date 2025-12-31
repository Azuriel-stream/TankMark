-- TankMark: v0.7-alpha (Fix: Lua 5.0 Closures)
-- File: TankMark_Options.lua

if not TankMark then return end

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
TankMark.selectedIcon = 8 
TankMark.selectedClass = nil 
TankMark.currentTab = 1
TankMark.mobRows = {} 
TankMark.profileRows = {}
TankMark.iconBtn = nil 
TankMark.classBtn = nil 
TankMark.lockCheck = nil 
TankMark.isZoneListMode = false 

local CLASS_LIST = { "WARRIOR", "MAGE", "WARLOCK", "HUNTER", "DRUID", "PRIEST", "ROGUE", "SHAMAN", "PALADIN" }

-- ==========================================================
-- 1. HELPER FUNCTIONS
-- ==========================================================

function TankMark:CreateEditBox(parent, title, width)
    local eb = CreateFrame("EditBox", nil, parent)
    eb:SetAutoFocus(false)
    eb:SetWidth(width); eb:SetHeight(20)
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
        TankMark.tab1:Show(); TankMark.tab2:Hide()
        TankMark:RefreshMobList() 
    else
        TankMark.tab1:Hide(); TankMark.tab2:Show()
        TankMark:RefreshProfileUI() 
    end
end

function TankMark:UpdateClassButton()
    if not TankMark.classBtn then return end
    if TankMark.selectedClass then
        TankMark.classBtn:SetText(TankMark.selectedClass)
        TankMark.classBtn.label:SetText("|cff00ff00CC Class:|r") 
    else
        TankMark.classBtn:SetText("ANY")
        TankMark.classBtn.label:SetText("CC Class:") 
    end
end

-- ==========================================================
-- 2. TAB 1 LOGIC: MOB DATABASE & ZONE BROWSER
-- ==========================================================

function TankMark:LoadMobForEdit(zone, mobName)
    if not TankMarkDB.Zones[zone] or not TankMarkDB.Zones[zone][mobName] then return end
    local data = TankMarkDB.Zones[zone][mobName]
    
    TankMark.editMob:SetText(mobName)
    TankMark.editPrio:SetText(data.prio)
    TankMark.selectedIcon = data.mark
    if TankMark.iconBtn and TankMark.iconBtn.tex then
        SetRaidTargetIconTexture(TankMark.iconBtn.tex, TankMark.selectedIcon)
    end
    TankMark.selectedClass = data.class 
    TankMark:UpdateClassButton()
    TankMark:Print("Loaded [" .. mobName .. "] for editing.")
end

function TankMark:ToggleZoneBrowser()
    TankMark.isZoneListMode = not TankMark.isZoneListMode
    TankMark:RefreshMobList()
end

function TankMark:SelectZone(zoneName)
    if TankMark.editZone then
        TankMark.editZone:SetText(zoneName)
        TankMark.isZoneListMode = false 
        TankMark:RefreshMobList()
    end
end

function TankMark:RequestDeleteZone(zoneName)
    TankMark.pendingWipeAction = function()
        TankMarkDB.Zones[zoneName] = nil
        TankMark:Print("Deleted zone: " .. zoneName)
        TankMark:RefreshMobList()
    end
    StaticPopup_Show("TANKMARK_WIPE_CONFIRM", "Delete ENTIRE ZONE:\n|cffff0000" .. zoneName .. "|r?")
end

function TankMark:RefreshMobList()
    if not TankMark.scrollChild then return end
    
    for _, row in pairs(TankMark.mobRows) do row:Hide() end
    
    local listData = {}
    local isZoneMode = TankMark.isZoneListMode
    
    if isZoneMode then
        -- === MODE: ZONE BROWSER ===
        if TankMark.listHeader then TankMark.listHeader:SetText("Browsing: All Zones") end
        
        for zoneName, _ in pairs(TankMarkDB.Zones) do
            table.insert(listData, { label = zoneName, type = "ZONE" })
        end
        table.sort(listData, function(a,b) return a.label < b.label end)
        
    else
        -- === MODE: MOB LIST ===
        local zone = TankMark.editZone and TankMark.editZone:GetText() or ""
        if TankMark.listHeader then
            TankMark.listHeader:SetText("Database: " .. (zone ~= "" and zone or "Unknown Zone"))
        end
        
        if zone and TankMarkDB.Zones[zone] then
            for mobName, data in pairs(TankMarkDB.Zones[zone]) do
                table.insert(listData, {
                    label = mobName, 
                    type = "MOB", 
                    prio = data.prio, 
                    mark = data.mark, 
                    class = data.class,
                    zone = zone 
                })
            end
            table.sort(listData, function(a,b) return a.prio < b.prio end)
        end
    end
    
    local totalHeight = (table.getn(listData) * 20) + 20
    if totalHeight < 230 then totalHeight = 230 end
    TankMark.scrollChild:SetHeight(totalHeight)

    local yOffset = -5
    for i, data in ipairs(listData) do
        local row = TankMark.mobRows[i]
        
        if not row then
            row = CreateFrame("Frame", nil, TankMark.scrollChild)
            row:SetWidth(260); row:SetHeight(20)
            
            row.icon = row:CreateTexture(nil, "ARTWORK")
            row.icon:SetWidth(16); row.icon:SetHeight(16)
            row.icon:SetPoint("LEFT", 5, 0)
            row.icon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
            
            row.text = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
            
            row.del = CreateFrame("Button", nil, row, "UIPanelCloseButton")
            row.del:SetWidth(20); row.del:SetHeight(20)
            row.del:SetPoint("RIGHT", -25, 0)
            
            row.edit = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
            row.edit:SetWidth(20); row.edit:SetHeight(20)
            row.edit:SetPoint("RIGHT", row.del, "LEFT", -2, 0)
            row.edit:SetText("E")
            row.edit:SetFont("Fonts\\FRIZQT__.TTF", 10)

            TankMark.mobRows[i] = row
        end
        
        row:SetPoint("TOPLEFT", TankMark.scrollChild, "TOPLEFT", 5, yOffset)
        
        if data.type == "ZONE" then
            -- Zone Visuals
            row.icon:SetTexture(nil) 
            row.text:SetPoint("LEFT", 5, 0) 
            row.text:SetText("|cffffd200" .. data.label .. "|r")
            
            -- FIX: Capture value locally for closure
            local clickZone = data.label
            
            row.del:SetScript("OnClick", function() TankMark:RequestDeleteZone(clickZone) end)
            row.edit:SetScript("OnClick", function() TankMark:SelectZone(clickZone) end)
            
        else
            -- Mob Visuals
            row.icon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
            SetRaidTargetIconTexture(row.icon, data.mark)
            row.text:SetPoint("LEFT", row.icon, "RIGHT", 5, 0) 
            
            local displayStr = "(Prio " .. data.prio .. ") " .. data.label
            if data.class then displayStr = displayStr .. " |cff00ff00[" .. string.sub(data.class, 1, 3) .. "]|r" end
            row.text:SetText(displayStr)
            
            -- FIX: Capture values locally for closure
            local clickZone = data.zone
            local clickMob = data.label
            
            row.del:SetScript("OnClick", function() TankMark:DeleteMob(clickZone, clickMob) end)
            row.edit:SetScript("OnClick", function() TankMark:LoadMobForEdit(clickZone, clickMob) end)
        end
        
        row:Show()
        yOffset = yOffset - 20
    end
end

function TankMark:SaveFormData()
    local zone = TankMark.editZone:GetText()
    local mob = TankMark.editMob:GetText()
    local prio = tonumber(TankMark.editPrio:GetText()) or 1
    local icon = TankMark.selectedIcon
    local classReq = TankMark.selectedClass 
    
    if zone == "" or mob == "" then return end
    if not TankMarkDB.Zones[zone] then TankMarkDB.Zones[zone] = {} end
    
    if TankMark.lockCheck and TankMark.lockCheck:GetChecked() then
        local exists, guid = UnitExists("target")
        if exists and guid and not UnitIsPlayer("target") and UnitName("target") == mob then
            if not TankMarkDB.StaticGUIDs[zone] then TankMarkDB.StaticGUIDs[zone] = {} end
            TankMarkDB.StaticGUIDs[zone][guid] = icon
            TankMark:Print("LOCKED GUID for: " .. mob)
            TankMark.lockCheck:SetChecked(nil) 
        else
            TankMark:Print("Warning: To lock GUID, you must target the mob.")
        end
    end

    local mobType = classReq and "CC" or "KILL"
    TankMarkDB.Zones[zone][mob] = { 
        ["prio"] = prio, ["mark"] = icon, ["class"] = classReq, ["type"] = mobType 
    }
    
    TankMark:Print("Saved: " .. mob .. " ("..mobType..")")
    TankMark.editMob:SetText("")
    TankMark.selectedClass = nil
    TankMark:UpdateClassButton()
    
    TankMark.isZoneListMode = false 
    TankMark:RefreshMobList()
end

function TankMark:DeleteMob(zone, mob)
    if TankMarkDB.Zones[zone] then
        TankMarkDB.Zones[zone][mob] = nil
        TankMark:RefreshMobList()
    end
end

function TankMark:RequestWipeZone()
    local zone = TankMark.editZone:GetText()
    if zone and zone ~= "" and TankMarkDB.Zones[zone] then
        TankMark.pendingWipeAction = function()
            TankMarkDB.Zones[zone] = {}
            TankMark:Print("Wiped all data for zone: " .. zone)
            TankMark:RefreshMobList()
        end
        StaticPopup_Show("TANKMARK_WIPE_CONFIRM", "Are you sure you want to WIPE the database for: |cffff0000" .. zone .. "|r?")
    else
        TankMark:Print("No data to wipe for this zone.")
    end
end

-- ==========================================================
-- 3. TAB 2 LOGIC: TEAM PROFILES
-- ==========================================================

function TankMark:SaveAllProfiles()
    local zone = TankMark.profileZone:GetText()
    if not zone or zone == "" then return end
    
    if not TankMarkDB.Profiles[zone] then TankMarkDB.Profiles[zone] = {} end
    
    for i = 1, 8 do
        if TankMark.profileRows[i] then
            local text = TankMark.profileRows[i].edit:GetText()
            TankMarkDB.Profiles[zone][i] = (text ~= "") and text or nil
            
            if zone == GetRealZoneText() then
                TankMark.sessionAssignments[i] = (text ~= "") and text or nil
            end
        end
    end
    if TankMark.UpdateHUD then TankMark:UpdateHUD() end
    TankMark:Print("Profile saved for: " .. zone)
end

function TankMark:RefreshProfileUI()
    local zone = TankMark.profileZone:GetText()
    if not TankMarkDB.Profiles[zone] then TankMarkDB.Profiles[zone] = {} end
    local data = TankMarkDB.Profiles[zone]
    for i = 1, 8 do
        TankMark.profileRows[i].edit:SetText(data[i] or "")
    end
end

function TankMark:RequestWipeProfile()
    local zone = TankMark.profileZone:GetText()
    if zone and zone ~= "" and TankMarkDB.Profiles[zone] then
        TankMark.pendingWipeAction = function()
            TankMarkDB.Profiles[zone] = {}
            TankMark:Print("Wiped team profile for zone: " .. zone)
            TankMark:RefreshProfileUI()
        end
        StaticPopup_Show("TANKMARK_WIPE_CONFIRM", "Are you sure you want to WIPE the profile for: |cffff0000" .. zone .. "|r?")
    else
        TankMark:Print("No profile data to wipe.")
    end
end

-- ==========================================================
-- 4. MAIN FRAME CONSTRUCTION
-- ==========================================================

function TankMark:CreateOptionsFrame()
    local f = CreateFrame("Frame", "TankMarkOptions", UIParent)
    f:SetWidth(600); f:SetHeight(400)
    f:SetPoint("CENTER", 0, 0); f:SetFrameStrata("HIGH")
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

    local t = f:CreateTexture(nil, "ARTWORK")
    t:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Header")
    t:SetWidth(400); t:SetHeight(64)
    t:SetPoint("TOP", f, "TOP", 0, 12)
    local txt = f:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    txt:SetPoint("TOP", t, "TOP", 0, -14)
    txt:SetText("TankMark Config (v0.7-alpha)")

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
    -- TAB 1 CONTENT
    -- ==========================================================
    local t1 = CreateFrame("Frame", nil, f)
    t1:SetPoint("TOPLEFT", 15, -40); t1:SetPoint("BOTTOMRIGHT", -15, 50)
    TankMark.tab1 = t1
    
    f.editZone = TankMark:CreateEditBox(t1, "Zone Name", 160)
    f.editZone:SetPoint("TOPLEFT", t1, "TOPLEFT", 15, -20)
    f.editZone:SetScript("OnEnterPressed", function() this:ClearFocus(); TankMark:RefreshMobList() end)
    
    local browseBtn = CreateFrame("Button", nil, t1, "UIPanelButtonTemplate")
    browseBtn:SetWidth(70); browseBtn:SetHeight(22)
    browseBtn:SetPoint("LEFT", f.editZone, "RIGHT", 5, 0)
    browseBtn:SetText("Browse")
    browseBtn:SetScript("OnClick", function() TankMark:ToggleZoneBrowser() end)
    
    f.editMob = TankMark:CreateEditBox(t1, "Mob Name", 200)
    f.editMob:SetPoint("TOPLEFT", f.editZone, "BOTTOMLEFT", 0, -30)
    
    local mobTargetBtn = CreateFrame("Button", nil, t1, "UIPanelButtonTemplate")
    mobTargetBtn:SetWidth(60); mobTargetBtn:SetHeight(20)
    mobTargetBtn:SetPoint("LEFT", f.editMob, "RIGHT", 5, 0)
    mobTargetBtn:SetText("Target")
    mobTargetBtn:SetFont("Fonts\\FRIZQT__.TTF", 10)
    mobTargetBtn:SetScript("OnClick", function()
        if UnitExists("target") and not UnitIsPlayer("target") then
            f.editMob:SetText(UnitName("target"))
        end
    end)
    
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
    TankMark.iconBtn = ib

    local cBtn = CreateFrame("Button", nil, t1, "UIPanelButtonTemplate")
    cBtn:SetWidth(80); cBtn:SetHeight(24)
    cBtn:SetPoint("LEFT", ib, "RIGHT", 20, 0)
    cBtn:SetText("ANY")
    cBtn.label = cBtn:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    cBtn.label:SetPoint("BOTTOM", cBtn, "TOP", 0, 3)
    cBtn.label:SetText("CC Class:")
    cBtn:SetScript("OnClick", function()
        local current = TankMark.selectedClass
        local nextClass = nil
        if not current then nextClass = CLASS_LIST[1] 
        else
            for i, c in ipairs(CLASS_LIST) do
                if c == current then
                    nextClass = (i < table.getn(CLASS_LIST)) and CLASS_LIST[i+1] or nil
                    break
                end
            end
        end
        TankMark.selectedClass = nextClass
        TankMark:UpdateClassButton()
    end)
    cBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    cBtn:SetScript("OnMouseUp", function() if arg1 == "RightButton" then TankMark.selectedClass = nil; TankMark:UpdateClassButton() end end)
    TankMark.classBtn = cBtn
    
    local lockCheck = CreateFrame("CheckButton", "TMLockCheck", t1, "UICheckButtonTemplate")
    lockCheck:SetWidth(24); lockCheck:SetHeight(24)
    lockCheck:SetPoint("TOPLEFT", f.editPrio, "BOTTOMLEFT", 0, -20)
    _G[lockCheck:GetName().."Text"]:SetText("Lock GUID (Require Target)")
    TankMark.lockCheck = lockCheck

    local sb = CreateFrame("Button", nil, t1, "UIPanelButtonTemplate")
    sb:SetWidth(100); sb:SetHeight(30)
    sb:SetPoint("LEFT", lockCheck, "RIGHT", 130, 0)
    sb:SetText("Save Mob")
    sb:SetScript("OnClick", function() TankMark:SaveFormData() end)
    
    local wipeBtn = CreateFrame("Button", nil, t1, "UIPanelButtonTemplate")
    wipeBtn:SetWidth(100); wipeBtn:SetHeight(22)
    wipeBtn:SetPoint("BOTTOMLEFT", t1, "BOTTOMLEFT", 15, 10)
    wipeBtn:SetText("|cffff0000Wipe Zone DB|r")
    wipeBtn:SetScript("OnClick", function() TankMark:RequestWipeZone() end)

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
    
    local lh = listBg:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lh:SetPoint("BOTTOMLEFT", listBg, "TOPLEFT", 5, 2)
    lh:SetText("Database: None")
    TankMark.listHeader = lh
    
    local scrollFrame = CreateFrame("ScrollFrame", "TMScrollFrame", listBg, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 0, -5); scrollFrame:SetPoint("BOTTOMRIGHT", -30, 5)
    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetWidth(260); scrollChild:SetHeight(230) 
    scrollFrame:SetScrollChild(scrollChild)
    TankMark.scrollChild = scrollChild

    -- ==========================================================
    -- TAB 2 CONTENT
    -- ==========================================================
    local t2 = CreateFrame("Frame", nil, f)
    t2:SetPoint("TOPLEFT", 15, -40); t2:SetPoint("BOTTOMRIGHT", -15, 50)
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
    
    local wipeProfBtn = CreateFrame("Button", nil, t2, "UIPanelButtonTemplate")
    wipeProfBtn:SetWidth(120); wipeProfBtn:SetHeight(22)
    wipeProfBtn:SetPoint("BOTTOM", t2, "BOTTOM", 0, 10)
    wipeProfBtn:SetText("|cffff0000Wipe Profile|r")
    wipeProfBtn:SetScript("OnClick", function() TankMark:RequestWipeProfile() end)
    
    local pY = -80; local pX = 20
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
        if i == 5 then pY = -80; pX = 300 end
    end

    TankMark.editZone = f.editZone; TankMark.editMob = f.editMob
    TankMark.editPrio = f.editPrio; TankMark.optionsFrame = f

    TankMark:Print("Options frame updated (v0.7-alpha).")
end

function TankMark:ShowOptions()
    if not TankMark.optionsFrame then TankMark:CreateOptionsFrame() end
    if not TankMark.optionsFrame:IsVisible() then TankMark.optionsFrame:Show() end
    
    local cz = GetRealZoneText()
    if cz and cz ~= "" then
        TankMark.editZone:SetText(cz)
        TankMark.profileZone:SetText(cz)
    end
    TankMark:UpdateTabs()
end