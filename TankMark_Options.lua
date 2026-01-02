-- TankMark: v0.11 (Golden Master)
-- File: TankMark_Options.lua
-- Release Date: 2025-01-02

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
TankMark.classDropDown = nil 
TankMark.lockCheck = nil 
TankMark.isZoneListMode = false 
TankMark.lockViewZone = nil 
TankMark.scrollFrame = nil 
TankMark.searchBox = nil 
TankMark.zoneModeCheck = nil

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
local _getglobal = getglobal

-- ==========================================================
-- 1. HELPER FUNCTIONS
-- ==========================================================

function TankMark:CreateEditBox(parent, title, w)
    local eb = CreateFrame("EditBox", nil, parent)
    eb:SetWidth(w); eb:SetHeight(20)
    eb:SetFontObject(GameFontHighlightSmall)
    eb:SetAutoFocus(false) 
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
    
    eb:SetScript("OnEscapePressed", function() eb:ClearFocus() end)
    eb:SetScript("OnEnterPressed", function() eb:ClearFocus() end)
    return eb
end

-- [SAFETY] Self-Healing DB Check
function TankMark:ValidateDB()
    if not TankMarkDB then TankMarkDB = {} end
    if not TankMarkDB.Zones then TankMarkDB.Zones = {} end
    if not TankMarkDB.StaticGUIDs then TankMarkDB.StaticGUIDs = {} end
    if not TankMarkDB.Profiles then TankMarkDB.Profiles = {} end
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
        TankMark.classBtn:SetTextColor(0, 1, 0)
    else
        TankMark.classBtn:SetText("Any Class")
        TankMark.classBtn:SetTextColor(1, 0.82, 0) 
    end
end

-- ==========================================================
-- 2. TAB 1 LOGIC: MOB DATABASE & ZONE BROWSER
-- ==========================================================

function TankMark:SetDropdownState(enabled)
    if not TankMark.zoneDropDown then return end
    local name = TankMark.zoneDropDown:GetName()
    local btn = _getglobal(name.."Button")
    local txt = _getglobal(name.."Text")
    
    if enabled then
        if btn then 
            btn:Enable() 
            btn:Show() 
        end
        TankMark.zoneDropDown:EnableMouse(true)
        if txt then txt:SetVertexColor(1, 1, 1) end 
    else
        if btn then 
            btn:Disable() 
        end
        TankMark.zoneDropDown:EnableMouse(false)
        if txt then txt:SetVertexColor(0.5, 0.5, 0.5) end 
    end
end

function TankMark:ToggleZoneBrowser()
    TankMark.isZoneListMode = not TankMark.isZoneListMode
    TankMark.lockViewZone = nil -- Always reset drill-down
    
    if TankMark.searchBox then TankMark.searchBox:SetText("") end
    
    if TankMark.isZoneListMode then
         TankMark:SetDropdownState(false)
         UIDropDownMenu_SetText("Manage Saved Zones", TankMark.zoneDropDown)
    else
         TankMark:SetDropdownState(true)
         UIDropDownMenu_SetText(GetRealZoneText(), TankMark.zoneDropDown)
    end
    
    if TankMark.zoneModeCheck then 
        TankMark.zoneModeCheck:SetChecked(TankMark.isZoneListMode)
    end
    
    TankMark:UpdateMobList()
end

function TankMark:ViewLocksForZone(zoneName)
    TankMark.lockViewZone = zoneName
    TankMark:UpdateMobList()
end

function TankMark:SelectZone(zoneName)
    if TankMark.zoneDropDown then
        TankMark:SetDropdownState(true)
        UIDropDownMenu_SetText(zoneName, TankMark.zoneDropDown)
        TankMark.isZoneListMode = false 
        
        if TankMark.zoneModeCheck then 
            TankMark.zoneModeCheck:SetChecked(nil)
        end
        
        TankMark:UpdateMobList()
    end
end

function TankMark:DeleteLock(guid)
    TankMark:ValidateDB()
    local z = TankMark.lockViewZone
    if z and TankMarkDB.StaticGUIDs[z] then
        TankMarkDB.StaticGUIDs[z][guid] = nil
        TankMark:UpdateMobList()
    end
end

function TankMark:RequestDeleteZone(zoneName)
    TankMark:ValidateDB()
    TankMark.pendingWipeAction = function()
        TankMarkDB.Zones[zoneName] = nil
        TankMarkDB.StaticGUIDs[zoneName] = nil
        TankMark:Print("Deleted zone: " .. zoneName)
        TankMark:UpdateMobList()
    end
    StaticPopup_Show("TANKMARK_WIPE_CONFIRM", "Delete ENTIRE ZONE:\n|cffff0000" .. zoneName .. "|r?")
end

function TankMark:UpdateMobList()
    if not TankMark.optionsFrame or not TankMark.optionsFrame:IsVisible() then return end
    TankMark:ValidateDB()

    local zone = UIDropDownMenu_GetText(TankMark.zoneDropDown) or GetRealZoneText()
    local listData = {}
    
    local filter = ""
    if TankMark.searchBox then
        filter = _lower(TankMark.searchBox:GetText())
    end

    -- [MODE 1] LOCKS VIEW
    if TankMark.isZoneListMode and TankMark.lockViewZone then
        local z = TankMark.lockViewZone
        _insert(listData, { type="BACK", label=".. Back to Zones" })
        
        if TankMarkDB.StaticGUIDs[z] then
            for guid, icon in _pairs(TankMarkDB.StaticGUIDs[z]) do
                _insert(listData, { type="LOCK", guid=guid, mark=icon })
            end
        end
        _sort(listData, function(a,b) 
            if a.type == "BACK" then return true end
            if b.type == "BACK" then return false end
            return a.mark < b.mark 
        end)

    -- [MODE 2] ZONE MANAGER
    elseif TankMark.isZoneListMode then
        for zoneName, _ in _pairs(TankMarkDB.Zones) do
            if filter == "" or _strfind(_lower(zoneName), filter, 1, true) then
                local locks = 0
                if TankMarkDB.StaticGUIDs[zoneName] then
                    for k,v in _pairs(TankMarkDB.StaticGUIDs[zoneName]) do locks = locks + 1 end
                end
                _insert(listData, { label = zoneName, type = "ZONE", lockCount = locks })
            end
        end
        _sort(listData, function(a,b) return a.label < b.label end)

    -- [MODE 3] STANDARD LIST
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
    local MAX_ROWS = 9 
    local ROW_HEIGHT = 22
    
    FauxScrollFrame_Update(TankMark.scrollFrame, numItems, MAX_ROWS, ROW_HEIGHT)
    local offset = FauxScrollFrame_GetOffset(TankMark.scrollFrame)

    for i = 1, MAX_ROWS do
        local index = offset + i
        local row = TankMark.mobRows[i]
        
        if row then
            if index <= numItems then
                local data = listData[index]
                
                -- CLEAN ROW STATE
                row.icon:Hide()
                row.icon:SetTexture("") 
                row.icon:SetTexCoord(0, 1, 0, 1)
                
                row.del:Hide()
                row.edit:Hide()
                row.text:SetTextColor(1,1,1)
                row:SetScript("OnClick", nil)
                
                if data.type == "BACK" then
                    row.text:SetText("|cffffd200<< Back to Zones|r")
                    row.icon:Show()
                    row.icon:SetTexture("Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Up")
                    row:SetScript("OnClick", function() 
                        TankMark.lockViewZone = nil 
                        TankMark:UpdateMobList()
                        PlaySound("igMainMenuOptionCheckBoxOn")
                    end)
                    
                elseif data.type == "LOCK" then
                    SetRaidTargetIconTexture(row.icon, data.mark)
                    row.icon:Show()
                    row.text:SetText(data.guid)
                    row.del:Show()
                    row.del:SetWidth(20); row.del:SetText("X")
                    row.del:SetScript("OnClick", function() TankMark:DeleteLock(data.guid) end)

                elseif data.type == "ZONE" then
                    local lockInfo = (data.lockCount > 0) and (" |cff00ff00("..data.lockCount.." locks)|r") or ""
                    row.text:SetText("|cffffd200" .. data.label .. "|r" .. lockInfo)
                    
                    local clickZone = data.label
                    row.del:Show()
                    row.del:SetWidth(60) 
                    row.del:SetText("|cffff0000Delete|r")
                    row.del:SetScript("OnClick", function() TankMark:RequestDeleteZone(clickZone) end)
                    
                    row.edit:Show()
                    row.edit:SetWidth(50)
                    row.edit:SetText("Locks")
                    row.edit:SetScript("OnClick", function() TankMark:ViewLocksForZone(clickZone) end)
                    
                else
                    if data.mark then
                        SetRaidTargetIconTexture(row.icon, data.mark)
                        row.icon:Show()
                    else
                        row.icon:Hide()
                    end
                    local color = "|cffffffff"
                    if data.type == "CC" then color = "|cff00ccff" end
                    
                    row.text:SetText("|cff888888["..data.prio.."]|r " .. color .. data.name .. "|r")
                    
                    local clickMob = data.name
                    row.del:Show()
                    row.del:SetWidth(20); row.del:SetText("X")
                    row.del:SetScript("OnClick", function() 
                        TankMarkDB.Zones[zone][clickMob] = nil
                        TankMark:UpdateMobList()
                        TankMark:Print("Removed " .. clickMob)
                    end)
                    
                    row.edit:Show()
                    row.edit:SetWidth(20); row.edit:SetText("E")
                    row.edit:SetScript("OnClick", function() 
                        TankMark.editMob:SetText(clickMob)
                        TankMark.editPrio:SetText(data.prio)
                        TankMark.selectedIcon = data.mark
                        TankMark.selectedClass = data.class
                        TankMark:UpdateClassButton()
                        if TankMark.iconBtn and TankMark.iconBtn.tex then 
                            SetRaidTargetIconTexture(TankMark.iconBtn.tex, data.mark) 
                        end
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
    TankMark:ValidateDB()
    local zone = TankMark.zoneDropDown and UIDropDownMenu_GetText(TankMark.zoneDropDown) or ""
    local mob = TankMark.editMob:GetText()
    local prio = tonumber(TankMark.editPrio:GetText()) or 1
    local icon = TankMark.selectedIcon
    local classReq = TankMark.selectedClass 
    
    if zone == "" or mob == "" or mob == "Mob Name" then return end
    if not TankMarkDB.Zones[zone] then TankMarkDB.Zones[zone] = {} end
    
    -- Lock GUID Logic
    if TankMark.lockCheck and TankMark.lockCheck:GetChecked() then
        local exists, guid = UnitExists("target")
        if exists and guid and not UnitIsPlayer("target") and UnitName("target") == mob then
            if not TankMarkDB.StaticGUIDs[zone] then TankMarkDB.StaticGUIDs[zone] = {} end
            TankMarkDB.StaticGUIDs[zone][guid] = icon
            TankMark:Print("|cff00ff00LOCKED GUID|r for: " .. mob)
            TankMark.lockCheck:SetChecked(nil)
        else
            TankMark:Print("|cffff0000Error:|r To lock GUID, you must target the specific mob.")
        end
    end

    local mobType = classReq and "CC" or "KILL"
    TankMarkDB.Zones[zone][mob] = { 
        ["prio"] = prio, ["mark"] = icon, ["class"] = classReq, ["type"] = mobType 
    }
    
    TankMark:Print("Saved: " .. mob .. " (Prio: "..prio..", Mark: "..icon..")")
    
    -- Clear Form
    TankMark.editMob:SetText("")
    TankMark.editPrio:SetText("1") 
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
    TankMark:ValidateDB()
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
-- 3. TAB 2 LOGIC: TEAM PROFILES
-- ==========================================================

function TankMark:SaveAllProfiles()
    TankMark:ValidateDB()
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
    TankMark:ValidateDB()
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
    TankMark:ValidateDB()
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
-- 4. CLASS DROPDOWN INIT
-- ==========================================================
function TankMark:InitClassMenu()
    local info = {}
    
    -- Option: Any Class (Clear)
    info = {}
    info.text = "|cffffffffAny Class (Kill)|r"
    info.func = function() 
        TankMark.selectedClass = nil
        TankMark:UpdateClassButton()
    end
    UIDropDownMenu_AddButton(info)
    
    -- List Classes
    for _, class in _ipairs(CLASS_LIST) do
        info = {}
        info.text = class
        info.func = function()
            TankMark.selectedClass = class
            TankMark:UpdateClassButton()
        end
        info.checked = (TankMark.selectedClass == class)
        UIDropDownMenu_AddButton(info)
    end
end

-- ==========================================================
-- 5. MAIN FRAME CONSTRUCTION
-- ==========================================================

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

    -- [NEW] Manage Zones Checkbox
    local mzCheck = CreateFrame("CheckButton", "TM_ManageZonesCheck", t1, "UICheckButtonTemplate")
    mzCheck:SetWidth(24); mzCheck:SetHeight(24)
    mzCheck:SetPoint("LEFT", drop, "RIGHT", 10, 2)
    _G[mzCheck:GetName().."Text"]:SetText("Manage Zones")
    mzCheck:SetScript("OnClick", function()
        TankMark:ToggleZoneBrowser()
        PlaySound("igMainMenuOptionCheckBoxOn")
    end)
    TankMark.zoneModeCheck = mzCheck

    -- SCROLL LIST
    local sf = CreateFrame("ScrollFrame", "TankMarkScrollFrame", t1, "FauxScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", 15, -50)
    sf:SetWidth(380)
    sf:SetHeight(200) 
    
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
    for i = 1, 9 do 
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
    -- DOUBLE-DECKER ADD/EDIT SECTION (v0.11 Final)
    -- ======================================================
    local addGroup = CreateFrame("Frame", nil, t1)
    addGroup:SetPoint("BOTTOMLEFT", 15, 0)
    addGroup:SetWidth(400) 
    addGroup:SetHeight(90) 
    
    local div = addGroup:CreateTexture(nil, "ARTWORK")
    div:SetHeight(1)
    div:SetWidth(380) 
    div:SetPoint("TOP", addGroup, "TOP", 0, 0) 
    div:SetTexture(1, 1, 1)
    div:SetAlpha(0.2)

    -- === ROW 1: Name & Target ===
    
    -- 1. Mob Name
    local nameBox = TankMark:CreateEditBox(addGroup, "Mob Name", 210)
    nameBox:SetPoint("TOPLEFT", 0, -30) 
    TankMark.editMob = nameBox 
    
    -- 2. Target Button
    local targetBtn = CreateFrame("Button", nil, addGroup, "UIPanelButtonTemplate")
    targetBtn:SetWidth(60); targetBtn:SetHeight(20)
    targetBtn:SetPoint("LEFT", nameBox, "RIGHT", 5, 0)
    targetBtn:SetText("Target")
    targetBtn:SetScript("OnClick", function()
        if UnitExists("target") then nameBox:SetText(UnitName("target")) end
    end)
    
    -- === ROW 2: Prio, Icon, Class, Lock, Save ===
    
    -- 3. Priority Box
    local prioBox = TankMark:CreateEditBox(addGroup, "Prio", 30)
    prioBox:SetPoint("TOPLEFT", 0, -65) 
    prioBox:SetText("1")
    prioBox:SetMaxLetters(2)
    prioBox:SetNumeric(true)
    TankMark.editPrio = prioBox
    
    -- 4. Icon Selector
    local iconSel = CreateFrame("Button", nil, addGroup)
    iconSel:SetWidth(24); iconSel:SetHeight(24)
    iconSel:SetPoint("LEFT", prioBox, "RIGHT", 10, 0)
    local iconTex = iconSel:CreateTexture(nil, "ARTWORK")
    iconTex:SetAllPoints()
    iconSel.tex = iconTex 
    iconTex:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
    SetRaidTargetIconTexture(iconTex, TankMark.selectedIcon)
    
    iconSel:SetScript("OnClick", function()
        TankMark.selectedIcon = TankMark.selectedIcon - 1
        if TankMark.selectedIcon < 1 then TankMark.selectedIcon = 8 end
        SetRaidTargetIconTexture(iconTex, TankMark.selectedIcon)
    end)
    TankMark.iconBtn = iconSel

    -- 5. Class Dropdown Button
    local cBtn = CreateFrame("Button", nil, addGroup, "UIPanelButtonTemplate")
    cBtn:SetWidth(80); cBtn:SetHeight(24)
    cBtn:SetPoint("LEFT", iconSel, "RIGHT", 10, 0)
    cBtn:SetText("Any Class")
    
    local cDrop = CreateFrame("Frame", "TMClassDropDown", cBtn, "UIDropDownMenuTemplate")
    UIDropDownMenu_Initialize(cDrop, function() TankMark:InitClassMenu() end, "MENU")
    TankMark.classDropDown = cDrop
    
    cBtn:SetScript("OnClick", function()
        ToggleDropDownMenu(1, nil, cDrop, "cursor", 0, 0)
    end)
    TankMark.classBtn = cBtn

    -- 6. Lock Checkbox
    local lCheck = CreateFrame("CheckButton", nil, addGroup, "UICheckButtonTemplate")
    lCheck:SetWidth(24); lCheck:SetHeight(24)
    lCheck:SetPoint("LEFT", cBtn, "RIGHT", 5, 0)
    
    lCheck:SetScript("OnEnter", function() 
        GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
        GameTooltip:SetText("Lock GUID")
        GameTooltip:AddLine("Check this to permanently assign this mark\nto this SPECIFIC creature instance.\n(Requires Target)", 1, 1, 1)
        GameTooltip:Show()
    end)
    lCheck:SetScript("OnLeave", function() GameTooltip:Hide() end)
    TankMark.lockCheck = lCheck

    -- 7. Save Button
    local addBtn = CreateFrame("Button", nil, addGroup, "UIPanelButtonTemplate")
    addBtn:SetWidth(60); addBtn:SetHeight(24)
    addBtn:SetPoint("LEFT", lCheck, "RIGHT", 5, 0)
    addBtn:SetText("Save")
    addBtn:SetScript("OnClick", function() TankMark:SaveFormData() end)
    
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
    
    TankMark:Print("TankMark v0.11 Options Loaded.")
end

function TankMark:ShowOptions()
    if not TankMark.optionsFrame then TankMark:CreateOptionsFrame() end
    TankMark.optionsFrame:Show()
    TankMark:ValidateDB()
    
    -- Safety: Clear focus from any hidden elements
    if TankMark.editPrio then TankMark.editPrio:ClearFocus() end
    if TankMark.searchBox then TankMark.searchBox:ClearFocus() end
    
    -- Ensure checkbox matches state on show
    if TankMark.zoneModeCheck then 
        TankMark.zoneModeCheck:SetChecked(TankMark.isZoneListMode)
    end
    
    local cz = GetRealZoneText()
    if cz and cz ~= "" then
        if TankMark.editZone then TankMark.editZone:SetText(cz) end
        if TankMark.profileZone then TankMark.profileZone:SetText(cz) end
    end
    
    TankMark:UpdateTabs()
end