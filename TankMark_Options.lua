-- TankMark: v0.11-RC8 (Fix: Input Focus Bug)
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
TankMark.scrollFrame = nil 
TankMark.searchBox = nil 

local CLASS_LIST = { "WARRIOR", "MAGE", "WARLOCK", "HUNTER", "DRUID", "PRIEST", "ROGUE", "SHAMAN", "PALADIN" }

-- ==========================================================
-- LOCALIZATIONS
-- ==========================================================
local _pairs = pairs
local _ipairs = ipairs
local _insert = table.insert
local _sort = table.sort
local _getn = table.getn
local _format = string.format
local _lower = string.lower
local _strfind = string.find

-- ==========================================================
-- 1. HELPER FUNCTIONS
-- ==========================================================

function TankMark:CreateEditBox(parent, title, w)
    local eb = CreateFrame("EditBox", nil, parent)
    eb:SetWidth(w); eb:SetHeight(20)
    eb:SetFontObject(GameFontHighlightSmall)
    eb:SetAutoFocus(false) -- Critical: Prevents stealing focus
    eb:SetTextInsets(5, 5, 0, 0)
    
    local left = eb:CreateTexture(nil, "BACKGROUND")
    left:SetTexture("Interface\\Common\\Common-Input-Border")
    left:SetTexCoord(0, 0.0625, 0, 0.625)
    left:SetWidth(8); left:SetHeight(20)
    left:SetPoint("LEFT", 0, 0)
    
    local right = eb:CreateTexture(nil, "BACKGROUND")
    right:SetTexture("Interface\\Common\\Common-Input-Border")
    right:SetTexCoord(0.9375, 1, 0, 0.625)
    right:SetWidth(8); right:SetHeight(20)
    right:SetPoint("RIGHT", 0, 0)
    
    local mid = eb:CreateTexture(nil, "BACKGROUND")
    mid:SetTexture("Interface\\Common\\Common-Input-Border")
    mid:SetTexCoord(0.0625, 0.9375, 0, 0.625)
    mid:SetHeight(20)
    mid:SetPoint("LEFT", left, "RIGHT", 0, 0)
    mid:SetPoint("RIGHT", right, "LEFT", 0, 0)
    
    local label = eb:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    label:SetPoint("BOTTOMLEFT", eb, "TOPLEFT", -5, 2)
    label:SetText(title or "") 
    
    -- FIXED: Clear focus on Enter or Escape
    eb:SetScript("OnEscapePressed", function() eb:ClearFocus() end)
    eb:SetScript("OnEnterPressed", function() eb:ClearFocus() end)
    return eb
end

function TankMark:UpdateTabs()
    if TankMark.currentTab == 1 then
        if TankMark.tab1 then TankMark.tab1:Show() end
        if TankMark.tab2 then TankMark.tab2:Hide() end
        TankMark:UpdateMobList() 
    else
        if TankMark.tab1 then TankMark.tab1:Hide() end
        if TankMark.tab2 then TankMark.tab2:Show() end
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

function TankMark:ToggleZoneBrowser()
    TankMark.isZoneListMode = not TankMark.isZoneListMode
    if TankMark.searchBox then TankMark.searchBox:SetText("") end
    TankMark:UpdateMobList()
end

function TankMark:SelectZone(zoneName)
    if TankMark.zoneDropDown then
        UIDropDownMenu_SetText(zoneName, TankMark.zoneDropDown)
        TankMark.isZoneListMode = false 
        TankMark:UpdateMobList()
    end
end

function TankMark:RequestDeleteZone(zoneName)
    TankMark.pendingWipeAction = function()
        TankMarkDB.Zones[zoneName] = nil
        TankMark:Print("Deleted zone: " .. zoneName)
        TankMark:UpdateMobList()
    end
    StaticPopup_Show("TANKMARK_WIPE_CONFIRM", "Delete ENTIRE ZONE:\n|cffff0000" .. zoneName .. "|r?")
end

function TankMark:UpdateMobList()
    if not TankMark.optionsFrame or not TankMark.optionsFrame:IsVisible() then return end

    local zone = UIDropDownMenu_GetText(TankMark.zoneDropDown) or GetRealZoneText()
    local listData = {}
    
    local filter = ""
    if TankMark.searchBox then
        filter = _lower(TankMark.searchBox:GetText())
    end

    if TankMark.isZoneListMode then
        for zoneName, _ in _pairs(TankMarkDB.Zones) do
            if filter == "" or _strfind(_lower(zoneName), filter, 1, true) then
                _insert(listData, { label = zoneName, type = "ZONE" })
            end
        end
        _sort(listData, function(a,b) return a.label < b.label end)
    else
        local mobsData = TankMarkDB.Zones[zone] or {}
        for name, info in _pairs(mobsData) do
            if filter == "" or _strfind(_lower(name), filter, 1, true) then
                _insert(listData, { 
                    name = name, 
                    prio = info.prio, 
                    mark = info.mark, 
                    type = info.type,
                    class = info.class
                })
            end
        end
        _sort(listData, function(a, b) 
            if a.prio == b.prio then return a.name < b.name end
            return a.prio < b.prio 
        end)
    end

    local numItems = _getn(listData)
    local MAX_ROWS = 10
    local ROW_HEIGHT = 22
    
    FauxScrollFrame_Update(TankMark.scrollFrame, numItems, MAX_ROWS, ROW_HEIGHT)
    local offset = FauxScrollFrame_GetOffset(TankMark.scrollFrame)

    for i = 1, MAX_ROWS do
        local index = offset + i
        local row = TankMark.mobRows[i]
        
        if row then
            if index <= numItems then
                local data = listData[index]
                
                if TankMark.isZoneListMode then
                    row.icon:Hide()
                    row.text:SetText("|cffffd200" .. data.label .. "|r")
                    local clickZone = data.label
                    row.del:SetScript("OnClick", function() TankMark:RequestDeleteZone(clickZone) end)
                    row.edit:SetText("GO")
                    row.edit:SetScript("OnClick", function() TankMark:SelectZone(clickZone) end)
                else
                    SetRaidTargetIconTexture(row.icon, data.mark)
                    row.icon:Show()
                    local color = "|cffffffff"
                    if data.type == "CC" then color = "|cff00ccff" end
                    local markInfo = TankMark.MarkInfo[data.mark]
                    local markName = markInfo and markInfo.name or "?"
                    row.text:SetText(color .. data.name .. "|r  (" .. markName .. ")")
                    
                    local clickMob = data.name
                    row.del:SetScript("OnClick", function() 
                        TankMarkDB.Zones[zone][clickMob] = nil
                        TankMark:UpdateMobList()
                        TankMark:Print("Removed " .. clickMob)
                    end)
                    
                    row.edit:SetText("E")
                    row.edit:SetScript("OnClick", function() 
                        TankMark.editMob:SetText(clickMob)
                        TankMark.editPrio:SetText(data.prio)
                        TankMark.selectedIcon = data.mark
                        TankMark.selectedClass = data.class
                        TankMark:UpdateClassButton()
                        if TankMark.iconBtn then SetRaidTargetIconTexture(TankMark.iconBtn.tex, data.mark) end
                    end)
                end
                row:Show()
            else
                row:Hide()
            end
        end
    end
end

function TankMark:SaveFormData()
    local zone = TankMark.zoneDropDown and UIDropDownMenu_GetText(TankMark.zoneDropDown) or ""
    local mob = TankMark.editMob:GetText()
    local prio = tonumber(TankMark.editPrio:GetText()) or 1
    local icon = TankMark.selectedIcon
    local classReq = TankMark.selectedClass 
    
    if zone == "" or mob == "" or mob == "Mob Name" then return end
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
    TankMark:UpdateMobList()
end

function TankMark:DeleteMob(zone, mob)
    if TankMarkDB.Zones[zone] then
        TankMarkDB.Zones[zone][mob] = nil
        TankMark:UpdateMobList()
    end
end

function TankMark:RequestWipeZone()
    local zone = UIDropDownMenu_GetText(TankMark.zoneDropDown)
    if zone and zone ~= "" and TankMarkDB.Zones[zone] then
        TankMark.pendingWipeAction = function()
            TankMarkDB.Zones[zone] = {}
            TankMark:Print("Wiped all data for zone: " .. zone)
            TankMark:UpdateMobList()
        end
        StaticPopup_Show("TANKMARK_WIPE_CONFIRM", "Are you sure you want to WIPE the database for: |cffff0000" .. zone .. "|r?")
    else
        TankMark:Print("No data to wipe for this zone.")
    end
end

-- ==========================================================
-- 3. TAB 2 LOGIC: TEAM PROFILES (FIXED LAYOUT)
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
        if TankMark.profileRows[i] then
            TankMark.profileRows[i].edit:SetText(data[i] or "")
        end
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
    if TankMark.optionsFrame then return end
    
    local f = CreateFrame("Frame", "TankMarkOptions", UIParent)
    f:SetWidth(450); f:SetHeight(480) 
    f:SetPoint("CENTER", 0, 0)
    f:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 }
    })
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function() f:StartMoving() end)
    f:SetScript("OnDragStop", function() f:StopMovingOrSizing() end)
    f:Hide()

    local t = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    t:SetPoint("TOP", 0, -15)
    t:SetText("TankMark Configuration")
    
    local cb = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    cb:SetPoint("TOPRIGHT", -5, -5)

    -- === TAB 1 CONTAINER ===
    local t1 = CreateFrame("Frame", nil, f)
    t1:SetPoint("TOPLEFT", 15, -40)
    t1:SetPoint("BOTTOMRIGHT", -15, 50)
    
    -- ZONE DROPDOWN
    local drop = CreateFrame("Frame", "TMZoneDropDown", t1, "UIDropDownMenuTemplate")
    drop:SetPoint("TOPLEFT", 0, -10)
    UIDropDownMenu_SetWidth(150, drop)
    UIDropDownMenu_Initialize(drop, function()
        local curr = GetRealZoneText()
        local info = {}
        info.text = curr
        info.func = function() 
            UIDropDownMenu_SetSelectedID(drop, this:GetID())
            TankMark:UpdateMobList() 
        end
        UIDropDownMenu_AddButton(info)
        
        for zName, _ in _pairs(TankMarkDB.Zones) do
            if zName ~= curr then
                info = {}
                info.text = zName
                info.func = function() 
                    UIDropDownMenu_SetSelectedID(drop, this:GetID())
                    TankMark:UpdateMobList() 
                end
                UIDropDownMenu_AddButton(info)
            end
        end
    end)
    UIDropDownMenu_SetText(GetRealZoneText(), drop) 
    TankMark.zoneDropDown = drop

    -- SCROLL LIST
    local sf = CreateFrame("ScrollFrame", "TankMarkScrollFrame", t1, "FauxScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", 15, -50)
    sf:SetWidth(380)
    sf:SetHeight(220) 
    
    local listBg = CreateFrame("Frame", nil, t1)
    listBg:SetPoint("TOPLEFT", sf, -5, 5)
    listBg:SetPoint("BOTTOMRIGHT", sf, 25, -5)
    listBg:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })
    listBg:SetBackdropColor(0, 0, 0, 0.5)

    sf:SetScript("OnVerticalScroll", function() 
        FauxScrollFrame_OnVerticalScroll(22, function() TankMark:UpdateMobList() end) 
    end)
    TankMark.scrollFrame = sf

    -- CREATE ROWS
    for i = 1, 10 do
        local row = CreateFrame("Button", nil, t1) 
        row:SetWidth(380)
        row:SetHeight(22)
        row:SetPoint("TOPLEFT", 15, -50 - ((i-1)*22))
        
        local icon = row:CreateTexture(nil, "ARTWORK")
        icon:SetWidth(18); icon:SetHeight(18)
        icon:SetPoint("LEFT", 0, 0)
        row.icon = icon
        
        local txt = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        txt:SetPoint("LEFT", icon, "RIGHT", 5, 0)
        row.text = txt
        
        local del = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        del:SetWidth(20); del:SetHeight(18)
        del:SetPoint("RIGHT", -5, 0)
        del:SetText("X")
        row.del = del
        
        local editBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        editBtn:SetWidth(20); editBtn:SetHeight(18)
        editBtn:SetPoint("RIGHT", del, "LEFT", -2, 0)
        editBtn:SetText("E")
        row.edit = editBtn
        
        row:Hide()
        TankMark.mobRows[i] = row
    end

    -- SEARCH BOX
    local searchLabel = t1:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    searchLabel:SetPoint("TOPLEFT", listBg, "BOTTOMLEFT", 5, -8) 
    searchLabel:SetText("Search:")

    local sBox = TankMark:CreateEditBox(t1, "", 150)
    sBox:SetPoint("LEFT", searchLabel, "RIGHT", 8, 0)
    sBox:SetScript("OnTextChanged", function() 
        TankMark:UpdateMobList() 
    end)
    
    local sClear = CreateFrame("Button", nil, sBox, "UIPanelCloseButton")
    sClear:SetWidth(20); sClear:SetHeight(20)
    sClear:SetPoint("LEFT", sBox, "RIGHT", 2, 0)
    sClear:SetScript("OnClick", function() 
        sBox:SetText("")
        sBox:ClearFocus()
        TankMark:UpdateMobList()
    end)
    TankMark.searchBox = sBox

    -- ======================================================
    -- ADD NEW MOB SECTION
    -- ======================================================
    local addGroup = CreateFrame("Frame", nil, t1)
    addGroup:SetPoint("BOTTOMLEFT", 5, -5) 
    addGroup:SetWidth(410); addGroup:SetHeight(80)
    
    local nameBox = TankMark:CreateEditBox(addGroup, "Mob Name", 110)
    nameBox:SetPoint("TOPLEFT", 0, -10)
    TankMark.editMob = nameBox 
    
    local targetBtn = CreateFrame("Button", nil, addGroup, "UIPanelButtonTemplate")
    targetBtn:SetWidth(50); targetBtn:SetHeight(20)
    targetBtn:SetPoint("LEFT", nameBox, "RIGHT", 5, 0)
    targetBtn:SetText("Target")
    targetBtn:SetScript("OnClick", function()
        if UnitExists("target") then nameBox:SetText(UnitName("target")) end
    end)
    
    local iconSel = CreateFrame("Button", nil, addGroup)
    iconSel:SetWidth(24); iconSel:SetHeight(24)
    iconSel:SetPoint("LEFT", targetBtn, "RIGHT", 5, 0)
    local iconTex = iconSel:CreateTexture(nil, "ARTWORK")
    iconTex:SetAllPoints()
    iconTex:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
    SetRaidTargetIconTexture(iconTex, TankMark.selectedIcon)
    iconSel:SetScript("OnClick", function()
        TankMark.selectedIcon = TankMark.selectedIcon - 1
        if TankMark.selectedIcon < 1 then TankMark.selectedIcon = 8 end
        SetRaidTargetIconTexture(iconTex, TankMark.selectedIcon)
    end)
    TankMark.iconBtn = iconSel
    
    local cBtn = CreateFrame("Button", nil, addGroup, "UIPanelButtonTemplate")
    cBtn:SetWidth(70); cBtn:SetHeight(24)
    cBtn:SetPoint("LEFT", iconSel, "RIGHT", 5, 0)
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

    local addBtn = CreateFrame("Button", nil, addGroup, "UIPanelButtonTemplate")
    addBtn:SetWidth(70); addBtn:SetHeight(24)
    addBtn:SetPoint("LEFT", cBtn, "RIGHT", 5, 0)
    addBtn:SetText("Add/Save")
    addBtn:SetScript("OnClick", function() TankMark:SaveFormData() end)
    
    -- FIXED: CreateEditBox used for hidden prio box to prevent Focus Stealing
    TankMark.editPrio = TankMark:CreateEditBox(f, "", 0)
    TankMark.editPrio:SetText("1") 
    TankMark.editPrio:Hide()

    TankMark.optionsFrame = f
    
    -- === TAB 2 INIT ===
    local t2 = CreateFrame("Frame", nil, f)
    t2:SetPoint("TOPLEFT", 15, -40); t2:SetPoint("BOTTOMRIGHT", -15, 50)
    t2:Hide()
    TankMark.tab2 = t2
    
    local pZone = TankMark:CreateEditBox(t2, "Profile Zone", 200) 
    pZone:SetPoint("TOPLEFT", t2, "TOPLEFT", 50, -30) 
    pZone:SetScript("OnEnterPressed", function() this:ClearFocus(); TankMark:RefreshProfileUI() end)
    TankMark.profileZone = pZone
    
    local pSave = CreateFrame("Button", nil, t2, "UIPanelButtonTemplate")
    pSave:SetWidth(100); pSave:SetHeight(30)
    pSave:SetPoint("LEFT", pZone, "RIGHT", 10, 0)
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
        row:SetWidth(200); row:SetHeight(30)
        row:SetPoint("TOPLEFT", t2, "TOPLEFT", pX, pY)
        
        local ico = row:CreateTexture(nil, "ARTWORK")
        ico:SetWidth(20); ico:SetHeight(20)
        ico:SetPoint("LEFT", 0, 0)
        ico:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
        SetRaidTargetIconTexture(ico, i)
        
        local eb = TankMark:CreateEditBox(row, "", 90) 
        eb:SetPoint("LEFT", ico, "RIGHT", 5, 0)
        row.edit = eb
        
        local btn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        btn:SetWidth(50); btn:SetHeight(20)
        btn:SetPoint("LEFT", eb, "RIGHT", 2, 0)
        btn:SetText("Target")
        btn:SetFont("Fonts\\FRIZQT__.TTF", 9)
        btn:SetScript("OnClick", function()
            if UnitExists("target") and UnitIsPlayer("target") then
                eb:SetText(UnitName("target"))
            end
        end)
        
        TankMark.profileRows[i] = row
        pY = pY - 40
        if i == 5 then pY = -80; pX = 225 end 
    end

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
    
    TankMark.tab1 = t1 
    
    -- Master Toggle
    local masterCheck = CreateFrame("CheckButton", "TM_MasterToggle", f, "UICheckButtonTemplate")
    masterCheck:SetWidth(24); masterCheck:SetHeight(24)
    masterCheck:SetPoint("TOPLEFT", f, "TOPLEFT", 15, -10)
    _G[masterCheck:GetName().."Text"]:SetText("Enable TankMark")
    masterCheck:SetChecked(TankMark.IsActive and 1 or nil)
    masterCheck:SetScript("OnClick", function()
        TankMark.IsActive = this:GetChecked() and true or false
        TankMark:Print("Auto-Marking " .. (TankMark.IsActive and "|cff00ff00ON|r" or "|cffff0000OFF|r"))
    end)
    
    TankMark:Print("Options frame updated (v0.11-RC8).")
end

function TankMark:ShowOptions()
    if not TankMark.optionsFrame then TankMark:CreateOptionsFrame() end
    TankMark.optionsFrame:Show()
    
    -- Safety: Clear focus from any hidden elements
    if TankMark.editPrio then TankMark.editPrio:ClearFocus() end
    if TankMark.searchBox then TankMark.searchBox:ClearFocus() end
    
    local cz = GetRealZoneText()
    if cz and cz ~= "" then
        if TankMark.editZone then TankMark.editZone:SetText(cz) end
        if TankMark.profileZone then TankMark.profileZone:SetText(cz) end
    end
    
    TankMark:UpdateTabs()
end