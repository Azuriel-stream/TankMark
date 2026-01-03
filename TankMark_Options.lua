-- TankMark: v0.13-dev (Smart Assignment UI)
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
TankMark.classDropDown = nil 
TankMark.lockBtn = nil 
TankMark.saveBtn = nil
TankMark.cancelBtn = nil
TankMark.isZoneListMode = false 
TankMark.lockViewZone = nil 
TankMark.scrollFrame = nil 
TankMark.searchBox = nil 
TankMark.zoneModeCheck = nil
TankMark.editingLockGUID = nil

-- Smart Logic State
TankMark.detectedCreatureType = nil
TankMark.isLockActive = false

-- ==========================================================
-- SMART MAPPINGS
-- ==========================================================
-- Maps Class -> { Default Icon, Default Prio }
local CLASS_DEFAULTS = {
    ["MAGE"]    = { icon = 5, prio = 3 }, -- Moon (Poly)
    ["WARLOCK"] = { icon = 3, prio = 3 }, -- Diamond (Banish/Seduce)
    ["DRUID"]   = { icon = 4, prio = 3 }, -- Triangle (Hibernate/Root)
    ["ROGUE"]   = { icon = 1, prio = 3 }, -- Star (Sap)
    ["PRIEST"]  = { icon = 6, prio = 3 }, -- Square (Shackle)
    ["HUNTER"]  = { icon = 2, prio = 3 }, -- Circle (Trap)
    ["KILL"]    = { icon = 8, prio = 1 }  -- Skull (No CC)
}

-- Maps Creature Type -> Valid CC Classes
local CC_MAP = {
    ["Humanoid"]  = { "MAGE", "ROGUE", "WARLOCK", "PRIEST" }, -- Poly, Sap, Seduce, MC
    ["Beast"]     = { "MAGE", "DRUID", "HUNTER" },            -- Poly, Hibernate, Trap
    ["Elemental"] = { "WARLOCK" },                            -- Banish
    ["Demon"]     = { "WARLOCK" },                            -- Banish/Enslave
    ["Undead"]    = { "PRIEST" },                             -- Shackle
    ["Dragonkin"] = { "DRUID" }                               -- Hibernate
}
local ALL_CLASSES = { "MAGE", "WARLOCK", "DRUID", "ROGUE", "PRIEST", "HUNTER", "WARRIOR", "SHAMAN", "PALADIN" }

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
    -- Manual construction for visual stability
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

-- ==========================================================
-- 2. SMART UI LOGIC
-- ==========================================================

function TankMark:UpdateClassButton()
    if not TankMark.classBtn then return end
    if TankMark.selectedClass then
        TankMark.classBtn:SetText(TankMark.selectedClass)
        TankMark.classBtn:SetTextColor(0, 1, 0) -- Green for CC
    else
        TankMark.classBtn:SetText("No CC (Kill)")
        TankMark.classBtn:SetTextColor(1, 0.82, 0) -- Gold for Standard
    end
end

function TankMark:ApplySmartDefaults(className)
    local defaults = className and CLASS_DEFAULTS[className] or CLASS_DEFAULTS["KILL"]
    
    -- Update Icon
    TankMark.selectedIcon = defaults.icon
    if TankMark.iconBtn and TankMark.iconBtn.tex then
        SetRaidTargetIconTexture(TankMark.iconBtn.tex, TankMark.selectedIcon)
    end
    
    -- Update Prio
    if TankMark.editPrio then
        TankMark.editPrio:SetText(tostring(defaults.prio))
    end
end

function TankMark:ToggleLockState()
    if not UnitExists("target") and not TankMark.editingLockGUID then 
        TankMark:Print("Error: You must target a mob to lock it.")
        return 
    end
    
    TankMark.isLockActive = not TankMark.isLockActive
    
    if TankMark.lockBtn then
        if TankMark.isLockActive then
            TankMark.lockBtn:SetText("|cff00ff00LOCKED|r")
            TankMark.lockBtn:LockHighlight() -- Visually depressed
        else
            TankMark.lockBtn:SetText("Lock Mark")
            TankMark.lockBtn:UnlockHighlight()
        end
    end
end

function TankMark:ResetEditor()
    -- Clear Fields
    if TankMark.editMob then TankMark.editMob:SetText("") end
    if TankMark.editPrio then TankMark.editPrio:SetText("1") end
    
    -- Reset Flags
    TankMark.editingLockGUID = nil
    TankMark.detectedCreatureType = nil
    TankMark.isLockActive = false
    
    -- Reset Smart Elements
    TankMark.selectedClass = nil
    TankMark:UpdateClassButton()
    
    -- Reset Icon to Skull
    TankMark.selectedIcon = 8
    if TankMark.iconBtn and TankMark.iconBtn.tex then
        SetRaidTargetIconTexture(TankMark.iconBtn.tex, 8)
    end
    
    -- Reset Lock Button
    if TankMark.lockBtn then
        TankMark.lockBtn:SetText("Lock Mark")
        TankMark.lockBtn:UnlockHighlight()
        TankMark.lockBtn:Disable() 
    end
    
    -- Reset Save Button [NEW: Disable on Reset]
    if TankMark.saveBtn then 
        TankMark.saveBtn:SetText("Save") 
        TankMark.saveBtn:Disable() 
    end
    if TankMark.cancelBtn then TankMark.cancelBtn:Hide() end
end

-- ==========================================================
-- 3. ZONE BROWSER & LIST
-- ==========================================================

function TankMark:SetDropdownState(enabled)
    if not TankMark.zoneDropDown then return end
    local name = TankMark.zoneDropDown:GetName()
    local btn = _getglobal(name.."Button")
    local txt = _getglobal(name.."Text")
    
    if enabled then
        if btn then btn:Enable(); btn:Show() end
        TankMark.zoneDropDown:EnableMouse(true)
        if txt then txt:SetVertexColor(1, 1, 1) end 
    else
        if btn then btn:Disable() end
        TankMark.zoneDropDown:EnableMouse(false)
        if txt then txt:SetVertexColor(0.5, 0.5, 0.5) end 
    end
end

function TankMark:ToggleZoneBrowser()
    TankMark.isZoneListMode = not TankMark.isZoneListMode
    TankMark.lockViewZone = nil 
    
    -- Full Reset of Editor when switching views
    TankMark:ResetEditor()
    
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
    TankMark:ResetEditor()
    TankMark:UpdateMobList()
end

function TankMark:UpdateMobList()
    if not TankMark.optionsFrame or not TankMark.optionsFrame:IsVisible() then return end
    TankMark:ValidateDB()

    local zone = UIDropDownMenu_GetText(TankMark.zoneDropDown) or GetRealZoneText()
    local listData = {}
    
    local filter = ""
    if TankMark.searchBox then filter = _lower(TankMark.searchBox:GetText()) end

    -- [MODE 1] LOCKS VIEW
    if TankMark.isZoneListMode and TankMark.lockViewZone then
        local z = TankMark.lockViewZone
        _insert(listData, { type="BACK", label=".. Back to Zones" })
        if TankMarkDB.StaticGUIDs[z] then
            for guid, data in _pairs(TankMarkDB.StaticGUIDs[z]) do
                local icon = (type(data) == "table") and data.mark or data
                local mobName = (type(data) == "table") and data.name or "Unknown Mob"
                _insert(listData, { type="LOCK", guid=guid, mark=icon, name=mobName })
            end
        end
        _sort(listData, function(a,b) 
            if a.type=="BACK" then return true end; if b.type=="BACK" then return false end
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
                _insert(listData, { name=name, prio=info.prio, mark=info.mark, type=info.type, class=info.class })
            end
        end
        _sort(listData, function(a, b) 
            if a.prio == b.prio then return a.name < b.name end
            return a.prio < b.prio 
        end)
    end

    local numItems = _getn(listData)
    local MAX_ROWS = 9 
    FauxScrollFrame_Update(TankMark.scrollFrame, numItems, MAX_ROWS, 22)
    local offset = FauxScrollFrame_GetOffset(TankMark.scrollFrame)

    for i = 1, MAX_ROWS do
        local index = offset + i
        local row = TankMark.mobRows[i]
        if row then
            if index <= numItems then
                local data = listData[index]
                row.icon:Hide(); row.del:Hide(); row.edit:Hide()
                row.text:SetTextColor(1,1,1)
                row:SetScript("OnClick", nil)
                
                if data.type == "BACK" then
                    row.text:SetText("|cffffd200<< Back to Zones|r")
                    row.icon:Show(); row.icon:SetTexture("Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Up")
                    row.icon:SetTexCoord(0, 1, 0, 1)
                    row:SetScript("OnClick", function() 
                        TankMark.lockViewZone = nil; TankMark:ResetEditor(); TankMark:UpdateMobList()
                        PlaySound("igMainMenuOptionCheckBoxOn")
                    end)
                elseif data.type == "LOCK" then
                    row.icon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
                    SetRaidTargetIconTexture(row.icon, data.mark); row.icon:Show()
                    row.text:SetText(data.name .. " |cff888888(" .. string.sub(data.guid, -6) .. ")|r")
                    row.del:Show(); row.del:SetText("X"); row.del:SetWidth(20)
                    row.del:SetScript("OnClick", function() TankMark:RequestDeleteLock(data.guid, data.name) end)
                    row.edit:Show(); row.edit:SetText("E"); row.edit:SetWidth(20)
                    row.edit:SetScript("OnClick", function()
                        -- [EDIT MODE: LOCK]
                        TankMark.editMob:SetText(data.name or "Unknown")
                        TankMark.selectedIcon = data.mark
                        TankMark.editingLockGUID = data.guid
                        TankMark.selectedClass = nil
                        
                        -- Update Visuals
                        TankMark:UpdateClassButton()
                        if TankMark.iconBtn then SetRaidTargetIconTexture(TankMark.iconBtn.tex, data.mark) end
                        
                        -- [NEW] Wake Up Save Button
                        TankMark.saveBtn:SetText("Update")
                        TankMark.saveBtn:Enable()
                        TankMark.cancelBtn:Show()
                        
                        -- Disable Smart Features in Edit Mode
                        TankMark.lockBtn:Disable()
                        TankMark.lockBtn:SetText("Locked")
                        
                        TankMark:Print("Editing lock: " .. data.name)
                    end)
                elseif data.type == "ZONE" then
                    local info = (data.lockCount > 0) and (" |cff00ff00("..data.lockCount.." locks)|r") or ""
                    row.text:SetText("|cffffd200" .. data.label .. "|r" .. info)
                    row.del:Show(); row.del:SetText("|cffff0000Delete|r"); row.del:SetWidth(60)
                    row.del:SetScript("OnClick", function() TankMark:RequestDeleteZone(data.label) end)
                    row.edit:Show(); row.edit:SetText("Locks"); row.edit:SetWidth(50)
                    row.edit:SetScript("OnClick", function() TankMark:ViewLocksForZone(data.label) end)
                else
                    -- Standard Mob Entry
                    row.icon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
                    SetRaidTargetIconTexture(row.icon, data.mark); row.icon:Show()
                    local c = (data.type=="CC") and "|cff00ccff" or "|cffffffff"
                    row.text:SetText("|cff888888["..data.prio.."]|r " .. c .. data.name .. "|r")
                    row.del:Show(); row.del:SetText("X"); row.del:SetWidth(20)
                    row.del:SetScript("OnClick", function() TankMark:RequestDeleteMob(zone, data.name) end)
                    row.edit:Show(); row.edit:SetText("E"); row.edit:SetWidth(20)
                    row.edit:SetScript("OnClick", function()
                        -- [EDIT MODE: MOB]
                        TankMark.editMob:SetText(data.name)
                        TankMark.editPrio:SetText(data.prio)
                        TankMark.selectedIcon = data.mark
                        TankMark.selectedClass = data.class
                        
                        TankMark:UpdateClassButton()
                        if TankMark.iconBtn then SetRaidTargetIconTexture(TankMark.iconBtn.tex, data.mark) end
                        
                        -- [NEW] Wake Up Save Button
                        TankMark.saveBtn:SetText("Update")
                        TankMark.saveBtn:Enable()
                        TankMark.cancelBtn:Show()
                        TankMark.lockBtn:Disable() 
                    end)
                end
                row:Show()
            else row:Hide() end
        end
    end
end

-- ==========================================================
-- 4. SAVE & DELETE LOGIC
-- ==========================================================

function TankMark:SaveFormData()
    TankMark:ValidateDB()
    local zone
    if TankMark.editingLockGUID and TankMark.lockViewZone then
        zone = TankMark.lockViewZone
    else
        zone = TankMark.zoneDropDown and UIDropDownMenu_GetText(TankMark.zoneDropDown) or ""
    end
    
    if zone == "Manage Saved Zones" then
        TankMark:Print("Error: Select a valid zone.")
        return
    end
    
    local mob = TankMark.editMob:GetText()
    local prio = tonumber(TankMark.editPrio:GetText()) or 1
    local icon = TankMark.selectedIcon
    local classReq = TankMark.selectedClass 
    
    if zone == "" or mob == "" or mob == "Mob Name" then return end
    if not TankMarkDB.Zones[zone] then TankMarkDB.Zones[zone] = {} end

    -- CASE 1: Updating Existing Lock
    if TankMark.editingLockGUID then
        if not TankMarkDB.StaticGUIDs[zone] then TankMarkDB.StaticGUIDs[zone] = {} end
        TankMarkDB.StaticGUIDs[zone][TankMark.editingLockGUID] = { ["mark"] = icon, ["name"] = mob }
        TankMark:Print("Updated lock: " .. mob)
        TankMark:ResetEditor()
        TankMark:UpdateMobList()
        return
    end
    
    -- CASE 2: Creating New Lock
    if TankMark.isLockActive then
        local exists, guid = UnitExists("target")
        if exists and guid and not UnitIsPlayer("target") and UnitName("target") == mob then
            if not TankMarkDB.StaticGUIDs[zone] then TankMarkDB.StaticGUIDs[zone] = {} end
            TankMarkDB.StaticGUIDs[zone][guid] = { ["mark"] = icon, ["name"] = mob }
            TankMark:Print("|cff00ff00LOCKED GUID|r for: " .. mob)
        else
            TankMark:Print("|cffff0000Error:|r Target lost or name mismatch. Lock failed.")
            return
        end
    end

    -- CASE 3: Save/Update Standard DB
    local mobType = classReq and "CC" or "KILL"
    TankMarkDB.Zones[zone][mob] = { 
        ["prio"] = prio, ["mark"] = icon, ["class"] = classReq, ["type"] = mobType 
    }
    
    TankMark:Print("Saved: " .. mob .. " (Prio: "..prio..", Mark: "..icon..")")
    TankMark:ResetEditor()
    TankMark.isZoneListMode = false 
    TankMark:UpdateMobList()
end

function TankMark:RequestDeleteMob(zone, mob)
    TankMark:ValidateDB()
    TankMark.pendingWipeAction = function()
        if TankMarkDB.Zones[zone] then
            TankMarkDB.Zones[zone][mob] = nil
            TankMark:UpdateMobList()
            TankMark:Print("Removed mob: " .. mob)
        end
    end
    StaticPopup_Show("TANKMARK_WIPE_CONFIRM", "Delete Mob from DB:\n|cffff0000" .. mob .. "|r?")
end

function TankMark:RequestDeleteLock(guid, name)
    TankMark:ValidateDB()
    local z = TankMark.lockViewZone
    TankMark.pendingWipeAction = function()
        if z and TankMarkDB.StaticGUIDs[z] then
            TankMarkDB.StaticGUIDs[z][guid] = nil
            TankMark:UpdateMobList()
            TankMark:Print("Removed lock for: " .. (name or "GUID"))
        end
    end
    StaticPopup_Show("TANKMARK_WIPE_CONFIRM", "Remove Lock for:\n|cffff0000" .. (name or "Unknown") .. "|r?")
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

-- ==========================================================
-- 5. DROPDOWN INIT
-- ==========================================================

function TankMark:InitClassMenu()
    local info = {}
    
    -- 1. No CC Option
    info = {}
    info.text = "|cffffffffNo CC (Kill Target)|r"
    info.func = function() 
        TankMark.selectedClass = nil
        TankMark:UpdateClassButton()
        TankMark:ApplySmartDefaults("KILL")
    end
    UIDropDownMenu_AddButton(info)
    
    -- 2. Smart Recommendations (Based on Creature Type)
    if TankMark.detectedCreatureType and CC_MAP[TankMark.detectedCreatureType] then
        info = {}; info.text = "--- Recommended ---"; info.isTitle = 1; UIDropDownMenu_AddButton(info)
        
        for _, class in _ipairs(CC_MAP[TankMark.detectedCreatureType]) do
            local capturedClass = class -- [FIX] Capture variable for closure
            info = {}
            info.text = "|cff00ff00" .. capturedClass .. "|r"
            info.func = function()
                TankMark.selectedClass = capturedClass
                TankMark:UpdateClassButton()
                TankMark:ApplySmartDefaults(capturedClass)
            end
            UIDropDownMenu_AddButton(info)
        end
    end
    
    -- 3. All Classes
    info = {}; info.text = "--- All Classes ---"; info.isTitle = 1; UIDropDownMenu_AddButton(info)
    for _, class in _ipairs(ALL_CLASSES) do
        local capturedClass = class -- [FIX] Capture variable for closure
        info = {}
        info.text = capturedClass
        info.func = function()
            TankMark.selectedClass = capturedClass
            TankMark:UpdateClassButton()
            TankMark:ApplySmartDefaults(capturedClass)
        end
        UIDropDownMenu_AddButton(info)
    end
end

function TankMark:InitIconMenu()
    local iconNames = {
        [8] = "|cffffffffSkull|r",
        [7] = "|cffff0000Cross|r",
        [6] = "|cff00ccffSquare|r",
        [5] = "|cffaabbccMoon|r",
        [4] = "|cff00ff00Triangle|r",
        [3] = "|cffff00ffDiamond|r",
        [2] = "|cffffaa00Circle|r",
        [1] = "|cffffff00Star|r"
    }
    -- Order: Skull down to Star
    for i = 8, 1, -1 do
        local capturedIcon = i -- [Fix] Capture variable for closure
        local info = {}
        info.text = iconNames[i]
        info.func = function()
            TankMark.selectedIcon = capturedIcon
            if TankMark.iconBtn and TankMark.iconBtn.tex then
                SetRaidTargetIconTexture(TankMark.iconBtn.tex, TankMark.selectedIcon)
            end
            CloseDropDownMenus()
        end
        info.checked = (TankMark.selectedIcon == i)
        UIDropDownMenu_AddButton(info)
    end
end

-- ==========================================================
-- 6. UI CONSTRUCTION
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
    t:SetPoint("TOP", 0, -15); t:SetText("TankMark Configuration")
    local cb = CreateFrame("Button", nil, f, "UIPanelCloseButton"); cb:SetPoint("TOPRIGHT", -5, -5)

    -- === TAB 1 ===
    local t1 = CreateFrame("Frame", nil, f)
    t1:SetPoint("TOPLEFT", 15, -40); t1:SetPoint("BOTTOMRIGHT", -15, 50)
    
    -- Dropdown & Checkbox
    local drop = CreateFrame("Frame", "TMZoneDropDown", t1, "UIDropDownMenuTemplate")
    drop:SetPoint("TOPLEFT", 0, -10); UIDropDownMenu_SetWidth(150, drop)
    UIDropDownMenu_Initialize(drop, function()
        local curr = GetRealZoneText()
        local info = {}; info.text = curr
        info.func = function() UIDropDownMenu_SetSelectedID(drop, this:GetID()); TankMark:UpdateMobList() end
        UIDropDownMenu_AddButton(info)
        for zName, _ in _pairs(TankMarkDB.Zones) do
            if zName ~= curr then
                info = {}; info.text = zName
                info.func = function() UIDropDownMenu_SetSelectedID(drop, this:GetID()); TankMark:UpdateMobList() end
                UIDropDownMenu_AddButton(info)
            end
        end
    end)
    UIDropDownMenu_SetText(GetRealZoneText(), drop); TankMark.zoneDropDown = drop

    local mzCheck = CreateFrame("CheckButton", "TM_ManageZonesCheck", t1, "UICheckButtonTemplate")
    mzCheck:SetWidth(24); mzCheck:SetHeight(24); mzCheck:SetPoint("LEFT", drop, "RIGHT", 10, 2)
    _G[mzCheck:GetName().."Text"]:SetText("Manage Zones")
    mzCheck:SetScript("OnClick", function() TankMark:ToggleZoneBrowser(); PlaySound("igMainMenuOptionCheckBoxOn") end)
    TankMark.zoneModeCheck = mzCheck

    -- Scroll List
    local sf = CreateFrame("ScrollFrame", "TankMarkScrollFrame", t1, "FauxScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", 10, -50); sf:SetWidth(380); sf:SetHeight(200)
    local listBg = CreateFrame("Frame", nil, t1)
    listBg:SetPoint("TOPLEFT", sf, -5, 5); listBg:SetPoint("BOTTOMRIGHT", sf, 25, -5)
    listBg:SetBackdrop({ bgFile="Interface\\Tooltips\\UI-Tooltip-Background", edgeFile="Interface\\Tooltips\\UI-Tooltip-Border", tile=true, tileSize=16, edgeSize=16, insets={left=4, right=4, top=4, bottom=4} })
    listBg:SetBackdropColor(0,0,0,0.5)
    sf:SetScript("OnVerticalScroll", function() FauxScrollFrame_OnVerticalScroll(22, function() TankMark:UpdateMobList() end) end)
    TankMark.scrollFrame = sf

    -- Rows
    for i = 1, 9 do 
        local row = CreateFrame("Button", nil, t1) 
        row:SetWidth(380); row:SetHeight(22); row:SetPoint("TOPLEFT", 10, -50 - ((i-1)*22))
        row.icon = row:CreateTexture(nil, "ARTWORK"); row.icon:SetWidth(18); row.icon:SetHeight(18); row.icon:SetPoint("LEFT", 0, 0)
        row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); row.text:SetPoint("LEFT", row.icon, "RIGHT", 5, 0)
        row.del = CreateFrame("Button", nil, row, "UIPanelButtonTemplate"); row.del:SetWidth(20); row.del:SetHeight(18); row.del:SetPoint("RIGHT", -5, 0); row.del:SetText("X")
        row.edit = CreateFrame("Button", nil, row, "UIPanelButtonTemplate"); row.edit:SetWidth(20); row.edit:SetHeight(18); row.edit:SetPoint("RIGHT", row.del, "LEFT", -2, 0); row.edit:SetText("E")
        row:Hide(); TankMark.mobRows[i] = row
    end

    -- Search
    local searchLabel = t1:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    searchLabel:SetPoint("TOPLEFT", listBg, "BOTTOMLEFT", 5, -8); searchLabel:SetText("Search:")
    local sBox = TankMark:CreateEditBox(t1, "", 150); sBox:SetPoint("LEFT", searchLabel, "RIGHT", 8, 0)
    sBox:SetScript("OnTextChanged", function() TankMark:UpdateMobList() end)
    TankMark.searchBox = sBox
    local sClear = CreateFrame("Button", nil, sBox, "UIPanelCloseButton"); sClear:SetWidth(20); sClear:SetHeight(20); sClear:SetPoint("LEFT", sBox, "RIGHT", 2, 0)
    sClear:SetScript("OnClick", function() sBox:SetText(""); sBox:ClearFocus(); TankMark:UpdateMobList() end)

    -- ======================================================
    -- SMART ASSIGNMENT ROW (Refactored)
    -- ======================================================
    local addGroup = CreateFrame("Frame", nil, t1)
    addGroup:SetPoint("BOTTOMLEFT", 10, 0); addGroup:SetWidth(400); addGroup:SetHeight(90)
    local div = addGroup:CreateTexture(nil, "ARTWORK"); div:SetHeight(1); div:SetWidth(380); div:SetPoint("TOP", 0, 0); div:SetTexture(1,1,1,0.2)

    -- [Row 1] Name & Target
    local nameBox = TankMark:CreateEditBox(addGroup, "Mob Name", 200)
    nameBox:SetPoint("TOPLEFT", 0, -30); TankMark.editMob = nameBox
    
    -- [NEW] Disable Save if name empty
    nameBox:SetScript("OnTextChanged", function()
        local text = this:GetText()
        if text and text ~= "" then
            if TankMark.saveBtn then TankMark.saveBtn:Enable() end
        else
            if TankMark.saveBtn then TankMark.saveBtn:Disable() end
        end
    end)
    
    local targetBtn = CreateFrame("Button", nil, addGroup, "UIPanelButtonTemplate")
    targetBtn:SetWidth(60); targetBtn:SetHeight(20); targetBtn:SetPoint("LEFT", nameBox, "RIGHT", 5, 0); targetBtn:SetText("Target")
    targetBtn:SetScript("OnClick", function()
        if UnitExists("target") then 
            nameBox:SetText(UnitName("target"))
            -- SMART DETECTION
            TankMark.detectedCreatureType = UnitCreatureType("target")
            TankMark:Print("Target Type: " .. (TankMark.detectedCreatureType or "Unknown"))
            -- [NEW] Wake up buttons
            if TankMark.lockBtn then TankMark.lockBtn:Enable() end
            if TankMark.saveBtn then TankMark.saveBtn:Enable() end
        end
    end)
    
    -- [Row 2] Smart Controls
    -- 1. Role/Class Dropdown
    local cBtn = CreateFrame("Button", nil, addGroup, "UIPanelButtonTemplate")
    cBtn:SetWidth(100); cBtn:SetHeight(24); cBtn:SetPoint("TOPLEFT", 0, -65); cBtn:SetText("No CC (Kill)")
    local cDrop = CreateFrame("Frame", "TMClassDropDown", cBtn, "UIDropDownMenuTemplate")
    UIDropDownMenu_Initialize(cDrop, function() TankMark:InitClassMenu() end, "MENU")
    cBtn:SetScript("OnClick", function() ToggleDropDownMenu(1, nil, cDrop, "cursor", 0, 0) end)
    TankMark.classBtn = cBtn
    
    -- 2. Icon Selector
    local iconSel = CreateFrame("Button", nil, addGroup)
    iconSel:SetWidth(24); iconSel:SetHeight(24); iconSel:SetPoint("LEFT", cBtn, "RIGHT", 10, 0)
    local iconTex = iconSel:CreateTexture(nil, "ARTWORK"); iconTex:SetAllPoints(); iconSel.tex = iconTex
    iconTex:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons"); SetRaidTargetIconTexture(iconTex, TankMark.selectedIcon)
    local iconDrop = CreateFrame("Frame", "TMIconDropDown", iconSel, "UIDropDownMenuTemplate")
    UIDropDownMenu_Initialize(iconDrop, function() TankMark:InitIconMenu() end, "MENU")
    iconSel:SetScript("OnClick", function()
        ToggleDropDownMenu(1, nil, iconDrop, "cursor", 0, 0)
    end)
    TankMark.iconBtn = iconSel
    
    -- 3. Prio Box
    local prioBox = TankMark:CreateEditBox(addGroup, "Prio", 25)
    prioBox:SetPoint("LEFT", iconSel, "RIGHT", 10, 0); prioBox:SetText("1"); prioBox:SetNumeric(true)
    TankMark.editPrio = prioBox
    
    -- 4. Lock Button (Toggle)
    local lBtn = CreateFrame("Button", nil, addGroup, "UIPanelButtonTemplate")
    lBtn:SetWidth(75); lBtn:SetHeight(24); lBtn:SetPoint("LEFT", prioBox, "RIGHT", 10, 0); lBtn:SetText("Lock Mark")
    lBtn:SetScript("OnClick", function() TankMark:ToggleLockState() end)
    lBtn:Disable() 
    TankMark.lockBtn = lBtn
    
    -- 5. Save Button [NEW: Disabled Default]
    local saveBtn = CreateFrame("Button", nil, addGroup, "UIPanelButtonTemplate")
    saveBtn:SetWidth(50); saveBtn:SetHeight(24); saveBtn:SetPoint("LEFT", lBtn, "RIGHT", 5, 0); saveBtn:SetText("Save")
    saveBtn:SetScript("OnClick", function() TankMark:SaveFormData() end)
    saveBtn:Disable()
    TankMark.saveBtn = saveBtn
    
    -- 6. Cancel Button
    local cancelBtn = CreateFrame("Button", nil, addGroup, "UIPanelButtonTemplate")
    cancelBtn:SetWidth(20); cancelBtn:SetHeight(24); cancelBtn:SetPoint("LEFT", saveBtn, "RIGHT", 2, 0); cancelBtn:SetText("X")
    cancelBtn:SetScript("OnClick", function() TankMark:ResetEditor() end)
    cancelBtn:Hide() 
    TankMark.cancelBtn = cancelBtn

    TankMark.optionsFrame = f
    
    -- === TAB 2 (Profile) ===
    local t2 = CreateFrame("Frame", nil, f)
    t2:SetPoint("TOPLEFT", 15, -40); t2:SetPoint("BOTTOMRIGHT", -15, 50); t2:Hide(); TankMark.tab2 = t2
    local pZone = TankMark:CreateEditBox(t2, "Profile Zone", 200); pZone:SetPoint("TOPLEFT", 50, -30)
    pZone:SetScript("OnEnterPressed", function() this:ClearFocus(); TankMark:RefreshProfileUI() end); TankMark.profileZone = pZone
    local pSave = CreateFrame("Button", nil, t2, "UIPanelButtonTemplate"); pSave:SetWidth(100); pSave:SetHeight(30); pSave:SetPoint("LEFT", pZone, "RIGHT", 10, 0); pSave:SetText("Save Profile")
    pSave:SetScript("OnClick", function() TankMark:SaveAllProfiles() end)
    local wipeProf = CreateFrame("Button", nil, t2, "UIPanelButtonTemplate"); wipeProf:SetWidth(120); wipeProf:SetHeight(22); wipeProf:SetPoint("BOTTOM", 0, 10); wipeProf:SetText("|cffff0000Wipe Profile|r")
    wipeProf:SetScript("OnClick", function() TankMark:RequestWipeProfile() end)
    
    local pY = -80; local pX = 20
    for i = 8, 1, -1 do
        local row = CreateFrame("Frame", nil, t2); row:SetWidth(200); row:SetHeight(30); row:SetPoint("TOPLEFT", pX, pY)
        local ico = row:CreateTexture(nil, "ARTWORK"); ico:SetWidth(20); ico:SetHeight(20); ico:SetPoint("LEFT", 0, 0)
        ico:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons"); SetRaidTargetIconTexture(ico, i)
        local eb = TankMark:CreateEditBox(row, "", 90); eb:SetPoint("LEFT", ico, "RIGHT", 5, 0); row.edit = eb
        local btn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate"); btn:SetWidth(50); btn:SetHeight(20); btn:SetPoint("LEFT", eb, "RIGHT", 2, 0); btn:SetText("Target"); btn:SetFont("Fonts\\FRIZQT__.TTF", 9)
        btn:SetScript("OnClick", function() if UnitExists("target") and UnitIsPlayer("target") then eb:SetText(UnitName("target")) end end)
        TankMark.profileRows[i] = row
        pY = pY - 40; if i == 5 then pY = -80; pX = 225 end 
    end

    -- Tabs & Master
    TankMark.tab1 = t1
    local tab1 = CreateFrame("Button", nil, f, "UIPanelButtonTemplate"); tab1:SetWidth(120); tab1:SetHeight(30); tab1:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 10, 5); tab1:SetText("Mob Database")
    tab1:SetScript("OnClick", function() TankMark.currentTab = 1; TankMark:UpdateTabs() end)
    local tab2 = CreateFrame("Button", nil, f, "UIPanelButtonTemplate"); tab2:SetWidth(120); tab2:SetHeight(30); tab2:SetPoint("LEFT", tab1, "RIGHT", 5, 0); tab2:SetText("Team Profiles")
    tab2:SetScript("OnClick", function() TankMark.currentTab = 2; TankMark:UpdateTabs() end)
    
    local mc = CreateFrame("CheckButton", "TM_MasterToggle", f, "UICheckButtonTemplate"); mc:SetWidth(24); mc:SetHeight(24); mc:SetPoint("TOPLEFT", 15, -10)
    _G[mc:GetName().."Text"]:SetText("Enable TankMark"); mc:SetChecked(TankMark.IsActive and 1 or nil)
    mc:SetScript("OnClick", function() TankMark.IsActive = this:GetChecked() and true or false; TankMark:Print("Auto-Marking " .. (TankMark.IsActive and "|cff00ff00ON|r" or "|cffff0000OFF|r")) end)
    
    TankMark:Print("TankMark v0.13-dev Options Loaded.")
end

function TankMark:ShowOptions()
    if not TankMark.optionsFrame then TankMark:CreateOptionsFrame() end
    TankMark.optionsFrame:Show()
    TankMark:ValidateDB()
    if TankMark.editPrio then TankMark.editPrio:ClearFocus() end
    if TankMark.searchBox then TankMark.searchBox:ClearFocus() end
    if TankMark.zoneModeCheck then TankMark.zoneModeCheck:SetChecked(TankMark.isZoneListMode) end
    local cz = GetRealZoneText()
    if cz and cz ~= "" then
        if TankMark.profileZone then TankMark.profileZone:SetText(cz) end
    end
    TankMark:UpdateTabs()
end