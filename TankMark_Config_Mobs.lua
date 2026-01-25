-- TankMark: v0.23
-- File: TankMark_Config_Mobs.lua
-- Mob Database configuration UI with sequential marking support

if not TankMark then return end

-- ==========================================================
-- LOCALIZATIONS
-- ==========================================================

local _pairs = pairs
local _ipairs = ipairs
local _insert = table.insert
local _remove = table.remove
local _sort = table.sort
local _getn = table.getn
local _lower = string.lower
local _strfind = string.find
local _gsub = string.gsub

-- ==========================================================
-- STATE
-- ==========================================================

TankMark.mobRows = {}
TankMark.selectedIcon = 8
TankMark.selectedClass = nil
TankMark.isZoneListMode = false
TankMark.lockViewZone = nil
TankMark.editingLockGUID = nil
TankMark.detectedCreatureType = nil
TankMark.isLockActive = false

-- [v0.23] Sequential marking state
TankMark.editingSequentialMarks = {}  -- Array of {icon, class, type}
TankMark.sequentialRows = {}  -- UI frame pool (max 7 additional marks)
TankMark.isAddMobExpanded = false  -- Accordion state

-- ==========================================================
-- UI REFERENCES
-- ==========================================================

TankMark.scrollFrame = nil
TankMark.searchBox = nil
TankMark.zoneDropDown = nil
TankMark.zoneModeCheck = nil
TankMark.editMob = nil
TankMark.editPrio = nil
TankMark.saveBtn = nil
TankMark.cancelBtn = nil
TankMark.lockBtn = nil
TankMark.classBtn = nil
TankMark.iconBtn = nil
TankMark.addMobHeader = nil
TankMark.addMobInterface = nil
TankMark.sequentialScrollFrame = nil
TankMark.addMoreMarksText = nil

-- ==========================================================
-- LOGIC CONSTANTS
-- ==========================================================

local CLASS_DEFAULTS = {
    ["MAGE"] = { icon = 5, prio = 3 },
    ["WARLOCK"] = { icon = 3, prio = 3 },
    ["DRUID"] = { icon = 4, prio = 3 },
    ["ROGUE"] = { icon = 1, prio = 3 },
    ["PRIEST"] = { icon = 6, prio = 3 },
    ["HUNTER"] = { icon = 2, prio = 3 },
    ["KILL"] = { icon = 8, prio = 1 },
    ["IGNORE"] = { icon = 0, prio = 9 }
}

local CC_MAP = {
    ["Humanoid"] = { "MAGE", "ROGUE", "WARLOCK", "PRIEST" },
    ["Beast"] = { "MAGE", "DRUID", "HUNTER" },
    ["Elemental"] = { "WARLOCK" },
    ["Demon"] = { "WARLOCK" },
    ["Undead"] = { "PRIEST" },
    ["Dragonkin"] = { "DRUID" }
}

local ALL_CLASSES = { "MAGE", "WARLOCK", "DRUID", "ROGUE", "PRIEST", "HUNTER", "WARRIOR", "SHAMAN", "PALADIN" }

-- ==========================================================
-- LOGIC HELPERS
-- ==========================================================

function TankMark:UpdateClassButton()
    if not TankMark.classBtn then return end
    
    if TankMark.selectedClass then
        TankMark.classBtn:SetText(TankMark.selectedClass)
        TankMark.classBtn:SetTextColor(0, 1, 0)
    else
        TankMark.classBtn:SetText("No CC (Kill)")
        TankMark.classBtn:SetTextColor(1, 0.82, 0)
    end
    
    if TankMark.selectedIcon == 0 then
        TankMark.classBtn:SetText("IGNORED")
        TankMark.classBtn:SetTextColor(0.5, 0.5, 0.5)
    end
end

function TankMark:ApplySmartDefaults(className)
    local defaults = className and CLASS_DEFAULTS[className] or CLASS_DEFAULTS["KILL"]
    TankMark.selectedIcon = defaults.icon
    
    if TankMark.iconBtn and TankMark.iconBtn.tex then
        TankMark:SetIconTexture(TankMark.iconBtn.tex, TankMark.selectedIcon)
    end
    
    if TankMark.editPrio then
        TankMark.editPrio:SetText(tostring(defaults.prio))
    end
end

function TankMark:ToggleLockState()
    if not UnitExists("target") and not TankMark.editingLockGUID then
        TankMark:Print("|cffff0000Error:|r You must target a mob to lock it.")
        return
    end
    
    TankMark.isLockActive = not TankMark.isLockActive
    
    if TankMark.lockBtn then
        if TankMark.isLockActive then
            TankMark.lockBtn:SetText("|cff00ff00LOCKED|r")
            TankMark.lockBtn:LockHighlight()
        else
            TankMark.lockBtn:SetText("Lock Mark")
            TankMark.lockBtn:UnlockHighlight()
        end
    end
end

function TankMark:ResetEditor()
    if TankMark.editMob then TankMark.editMob:SetText("") end
    if TankMark.editPrio then TankMark.editPrio:SetText("1") end
    
    TankMark.editingLockGUID = nil
    TankMark.detectedCreatureType = nil
    TankMark.isLockActive = false
    TankMark.selectedClass = nil
    TankMark:UpdateClassButton()
    TankMark.selectedIcon = 8
    
    if TankMark.iconBtn and TankMark.iconBtn.tex then
        TankMark:SetIconTexture(TankMark.iconBtn.tex, 8)
    end
    
    if TankMark.lockBtn then
        TankMark.lockBtn:SetText("Lock Mark")
        TankMark.lockBtn:UnlockHighlight()
        TankMark.lockBtn:Disable()
    end
    
    if TankMark.saveBtn then
        TankMark.saveBtn:SetText("Save")
        TankMark.saveBtn:Disable()
    end
    
    if TankMark.cancelBtn then TankMark.cancelBtn:Hide() end
    
    -- [v0.23] Clear sequential marks
    TankMark.editingSequentialMarks = {}
    if TankMark.sequentialScrollFrame then
        TankMark.sequentialScrollFrame:Hide()
    end
    if TankMark.addMoreMarksText then
        TankMark.addMoreMarksText:Hide()
    end
    
    -- [v0.23] Collapse "Add manually" section
    TankMark.isAddMobExpanded = false
    if TankMark.addMobInterface then
        TankMark.addMobInterface:Hide()
    end
    if TankMark.addMobHeader and TankMark.addMobHeader.arrow then
        TankMark.addMobHeader.arrow:SetTexture("Interface\\Buttons\\UI-PlusButton-Up")
    end
end

function TankMark:SetDropdownState(enabled)
    if not TankMark.zoneDropDown then return end
    
    local name = TankMark.zoneDropDown:GetName()
    local btn = _G[name.."Button"]
    local txt = _G[name.."Text"]
    
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

-- ==========================================================
-- [v0.23] GUID LOCK DETECTION
-- ==========================================================

function TankMark:HasGUIDLockForMobName(mobName)
    if not mobName or mobName == "" then return false end
    return TankMark.guidLockIndex and TankMark.guidLockIndex[mobName] or false
end

-- ==========================================================
-- [v0.23] SEQUENTIAL MARKING HELPERS
-- ==========================================================

function TankMark:RefreshSequentialRows()
    if not TankMark.sequentialScrollFrame then return end
    
    local numMarks = _getn(TankMark.editingSequentialMarks)
    
    if numMarks == 0 then
        TankMark.sequentialScrollFrame:Hide()
        if TankMark.addMoreMarksText then
            TankMark.addMoreMarksText:SetText("|cff00ccff+ Add More Marks|r")
        end
        return
    end
    
    TankMark.sequentialScrollFrame:Show()
    
    local scrollChild = TankMark.sequentialScrollFrame:GetScrollChild()
    if scrollChild then
        scrollChild:Show()
    end
    
    -- Update scroll range (use actual count, max 3 visible)
    local visibleRows = math.min(numMarks, 3)
    FauxScrollFrame_Update(TankMark.sequentialScrollFrame, numMarks, visibleRows, 24)
    local offset = FauxScrollFrame_GetOffset(TankMark.sequentialScrollFrame)
    
    -- Force visibility after FauxScrollFrame_Update
    TankMark.sequentialScrollFrame:Show()
    if scrollChild then
        scrollChild:Show()
    end
    
    -- Update visible rows (max 3)
    for i = 1, 3 do
        local dataIndex = offset + i
        local row = TankMark.sequentialRows[i]
        
        if dataIndex <= numMarks then
            local seqData = TankMark.editingSequentialMarks[dataIndex]
            row:Show()
            
            -- Update row number (dataIndex + 1 because main row is #1)
            row.number:SetText("|cff888888#" .. (dataIndex + 1) .. "|r")
            
            -- Update icon
            TankMark:SetIconTexture(row.iconBtn.tex, seqData.icon)
            
            -- Update CC button
            if seqData.class then
                row.ccBtn:SetText(seqData.class)
                row.ccBtn:SetTextColor(0, 1, 0)
            else
                row.ccBtn:SetText("No CC (Kill)")
                row.ccBtn:SetTextColor(1, 0.82, 0)
            end
            
            -- Store dataIndex for delete button
            row.dataIndex = dataIndex
        else
            row:Hide()
        end
    end
end

function TankMark:OnAddMoreMarksClicked()
	-- ADD THIS AT THE START:
    if not TankMark.isAddMobExpanded then
        -- Auto-expand accordion
        if TankMark.addMobInterface then
            TankMark.addMobInterface:Show()
        end
        if TankMark.addMobHeader and TankMark.addMobHeader.arrow then
            TankMark.addMobHeader.arrow:SetTexture("Interface\\Buttons\\UI-MinusButton-Up")
        end
        TankMark.isAddMobExpanded = true
    end
    -- [v0.23] Reset IGNORE to SKULL when adding sequential marks
    if TankMark.selectedIcon == 0 then
        TankMark.selectedIcon = 8
        if TankMark.iconBtn and TankMark.iconBtn.tex then
            TankMark:SetIconTexture(TankMark.iconBtn.tex, 8)
        end
        if TankMark.editPrio then
            TankMark.editPrio:SetText("1")  -- Reset priority from 9 to 1
        end
        TankMark:UpdateClassButton()
    end
    
    -- Check limit (max 7 additional marks = 8 total)
    if _getn(TankMark.editingSequentialMarks) >= 7 then
        TankMark:Print("|cffff0000Error:|r Maximum 8 marks total (1 main + 7 additional).")
        return
    end
    
    -- Add new entry
    _insert(TankMark.editingSequentialMarks, {
        icon = 8,  -- Default to SKULL
        class = nil,
        type = "KILL"
    })
    
    TankMark:RefreshSequentialRows()
    
    -- Disable Lock button when sequential marks exist (instead of hiding)
    if TankMark.lockBtn then
        TankMark.lockBtn:Disable()
        TankMark.lockBtn:SetText("|cff888888Lock Mark|r")  -- Gray text
    end
end

function TankMark:RemoveSequentialRow(index)
    _remove(TankMark.editingSequentialMarks, index)
    TankMark:RefreshSequentialRows()
    
    -- Re-enable Lock button if no sequential marks remain
    if _getn(TankMark.editingSequentialMarks) == 0 and TankMark.lockBtn then
        TankMark.lockBtn:Enable()
        TankMark.lockBtn:SetText("Lock Mark")  -- Reset normal text
    end
end

-- ==========================================================
-- MOB LIST UPDATE
-- ==========================================================

function TankMark:UpdateMobList()
    if not TankMark.optionsFrame or not TankMark.optionsFrame:IsVisible() then return end
    if not TankMarkDB then TankMarkDB = {} end
    
    local db = TankMarkDB
    local zone = UIDropDownMenu_GetText(TankMark.zoneDropDown) or GetRealZoneText()
    local listData = {}
    local filter = ""
    
    if TankMark.searchBox then filter = _lower(TankMark.searchBox:GetText()) end
    
    -- Build list based on current mode
    if TankMark.isZoneListMode and TankMark.lockViewZone then
        -- Lock view for specific zone
        local z = TankMark.lockViewZone
        _insert(listData, { type="BACK", label="<< Back to Zones" })
        
        if db.StaticGUIDs[z] then
            for guid, data in _pairs(db.StaticGUIDs[z]) do
                local icon = (type(data) == "table") and data.mark or data
                local mobName = (type(data) == "table") and data.name or "Unknown Mob"
                _insert(listData, { type="LOCK", guid=guid, mark=icon, name=mobName })
            end
        end
        
        _sort(listData, function(a,b)
            if not a or not b then return false end
            if a.type=="BACK" then return true end
            if b.type=="BACK" then return false end
            local mA = a.mark or 0
            local mB = b.mark or 0
            return mA < mB
        end)
        
    elseif TankMark.isZoneListMode then
        -- Zone list mode
        for zoneName, _ in _pairs(db.Zones) do
            if filter == "" or _strfind(_lower(zoneName), filter, 1, true) then
                local locks = 0
                if db.StaticGUIDs[zoneName] then
                    for k,v in _pairs(db.StaticGUIDs[zoneName]) do locks = locks + 1 end
                end
                _insert(listData, { label = zoneName, type = "ZONE", lockCount = locks })
            end
        end
        
        _sort(listData, function(a,b) return a.label < b.label end)
        
    else
        -- Normal mob list for selected zone
        local mobsData = db.Zones[zone] or {}
        
        for name, info in _pairs(mobsData) do
            if filter == "" or _strfind(_lower(name), filter, 1, true) then
                -- [v0.23] Extract first mark from array for display
                local displayMark = info.marks and info.marks[1] or 8
                local isSequential = info.marks and _getn(info.marks) > 1
                
                _insert(listData, { 
                    name=name, 
                    prio=info.prio, 
                    mark=displayMark,
                    marks=info.marks,  -- Keep full array for editing
                    type=info.type, 
                    class=info.class,
                    isSequential=isSequential
                })
            end
        end
        
        _sort(listData, function(a, b)
            if not a or not b then return false end
            local pA = a.prio or 99
            local pB = b.prio or 99
            if pA == pB then
                return (a.name or "") < (b.name or "")
            end
            return pA < pB
        end)
    end
    
    -- Render list (6 rows instead of 9)
    local numItems = _getn(listData)
    local MAX_ROWS = 6
    FauxScrollFrame_Update(TankMark.scrollFrame, numItems, MAX_ROWS, 22)
    local offset = FauxScrollFrame_GetOffset(TankMark.scrollFrame)
    
    for i = 1, MAX_ROWS do
        local index = offset + i
        local row = TankMark.mobRows[i]
        
        if row then
            if index <= numItems then
                local data = listData[index]
                row.icon:Hide()
                row.del:Hide()
                row.edit:Hide()
                row.text:SetTextColor(1,1,1)
                row:SetScript("OnClick", nil)
                
                if data.type == "BACK" then
                    row.text:SetText("|cffffd200" .. data.label .. "|r")
                    row.icon:Show()
                    row.icon:SetTexture("Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Up")
                    row.icon:SetTexCoord(0, 1, 0, 1)
                    row:SetScript("OnClick", function()
                        TankMark.lockViewZone = nil
                        TankMark:ResetEditor()
                        TankMark:UpdateMobList()
                        PlaySound("igMainMenuOptionCheckBoxOn")
                    end)
                    
                elseif data.type == "LOCK" then
                    TankMark:SetIconTexture(row.icon, data.mark)
                    row.icon:Show()
                    row.text:SetText(data.name .. " |cff888888(" .. string.sub(data.guid, -6) .. ")|r")
                    row.del:Show()
                    row.del:SetText("X")
                    row.del:SetWidth(20)
                    row.del:SetScript("OnClick", function() TankMark:RequestDeleteLock(data.guid, data.name) end)
                    row.edit:Show()
                    row.edit:SetText("E")
                    row.edit:SetWidth(20)
                    row.edit:SetScript("OnClick", function()
                        TankMark.editMob:SetText(data.name or "Unknown")
                        TankMark.selectedIcon = data.mark
                        TankMark.editingLockGUID = data.guid
                        TankMark.selectedClass = nil
                        TankMark:UpdateClassButton()
                        if TankMark.iconBtn then TankMark:SetIconTexture(TankMark.iconBtn.tex, data.mark) end
                        TankMark.saveBtn:SetText("Update")
                        TankMark.saveBtn:Enable()
                        TankMark.cancelBtn:Show()
                        TankMark.lockBtn:Disable()
                        TankMark.lockBtn:SetText("Locked")
						-- Ensure accordion is expanded when editing
						if not TankMark.isAddMobExpanded then
							if TankMark.addMobHeader then
								-- Trigger the accordion click
								TankMark.addMobInterface:Show()
								TankMark.addMobHeader.arrow:SetTexture("Interface\\Buttons\\UI-MinusButton-Up")
								TankMark.isAddMobExpanded = true
							end
						end
                    end)
                    
                elseif data.type == "ZONE" then
                    local info = (data.lockCount > 0) and (" |cff00ff00(" .. data.lockCount .. " locks)|r") or ""
                    row.text:SetText("|cffffd200" .. data.label .. "|r" .. info)
                    row.del:Show()
                    row.del:SetText("|cffff0000Delete|r")
                    row.del:SetWidth(60)
                    row.del:SetScript("OnClick", function() TankMark:RequestDeleteZone(data.label) end)
                    row.edit:Show()
                    row.edit:SetText("Locks")
                    row.edit:SetWidth(50)
                    row.edit:SetScript("OnClick", function() TankMark:ViewLocksForZone(data.label) end)
                    
                else
                    TankMark:SetIconTexture(row.icon, data.mark)
                    row.icon:Show()
                    
                    local c = (data.type=="CC") and "|cff00ccff" or "|cffffffff"
                    -- [v0.23] Check if first mark is IGNORE (0)
					local firstMark = data.marks and data.marks[1] or 8
					if firstMark == 0 then
						c = "|cff888888"
					end
                    
                    -- [v0.23] Show indicator for sequential mobs
                    local seqIndicator = data.isSequential and " |cffffaa00[SEQ]|r" or ""
                    row.text:SetText("|cff888888[" .. data.prio .. "]|r " .. c .. data.name .. "|r" .. seqIndicator)
                    
                    row.del:Show()
                    row.del:SetText("X")
                    row.del:SetWidth(20)
                    row.del:SetScript("OnClick", function() TankMark:RequestDeleteMob(zone, data.name) end)
                    row.edit:Show()
                    row.edit:SetText("E")
                    row.edit:SetWidth(20)
                    row.edit:SetScript("OnClick", function()
                        -- Populate main row
                        TankMark.editMob:SetText(data.name)
                        TankMark.editPrio:SetText(data.prio)
                        TankMark.selectedIcon = data.mark
                        TankMark.selectedClass = data.class
                        TankMark:UpdateClassButton()
                        if TankMark.iconBtn then TankMark:SetIconTexture(TankMark.iconBtn.tex, data.mark) end
                        
                        -- [v0.23] Populate sequential marks (skip first mark as it's the main row)
                        TankMark.editingSequentialMarks = {}
                        if data.marks and _getn(data.marks) > 1 then
                            for i = 2, _getn(data.marks) do
                                _insert(TankMark.editingSequentialMarks, {
                                    icon = data.marks[i],
                                    class = data.class,  -- Share class (can be changed per row)
                                    type = data.type
                                })
                            end
                            TankMark:RefreshSequentialRows()
                            
                            -- Show '+ Add More Marks' text
                            if TankMark.addMoreMarksText then
                                TankMark.addMoreMarksText:Show()
                            end
                            
                            -- Disable Lock button when sequential marks exist (instead of hiding)
							if TankMark.lockBtn then
								TankMark.lockBtn:Disable()
								TankMark.lockBtn:SetText("|cff888888Lock Mark|r")  -- Gray text
							end
                        end
                        
                        -- Update UI state
                        TankMark.saveBtn:SetText("Update")
                        TankMark.saveBtn:Enable()
                        TankMark.cancelBtn:Show()
                        
                        -- Check GUID lock conflict
                        if TankMark:HasGUIDLockForMobName(data.name) then
                            if TankMark.addMoreMarksText then
                                TankMark.addMoreMarksText:SetTextColor(0.5, 0.5, 0.5)
                            end
							-- Disable the button, not the FontString
							if TankMark.addMoreMarksText.clickFrame then
								TankMark.addMoreMarksText.clickFrame:Disable()
							end
                        else
                            if TankMark.addMoreMarksText then
                                TankMark.addMoreMarksText:SetTextColor(0, 0.8, 1)
                            end
							-- Enable the button
							if TankMark.addMoreMarksText.clickFrame then
								TankMark.addMoreMarksText.clickFrame:Enable()
							end
                        end
                        
                        if not TankMark.editingLockGUID and TankMark.lockBtn then
                            TankMark.lockBtn:Enable()
                        end
						-- Ensure accordion is expanded when editing
						if not TankMark.isAddMobExpanded then
							if TankMark.addMobHeader and TankMark.addMobInterface then
								TankMark.addMobInterface:Show()
								TankMark.addMobHeader.arrow:SetTexture("Interface\\Buttons\\UI-MinusButton-Up")
								TankMark.isAddMobExpanded = true
							end
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

-- ==========================================================
-- SAVE FORM DATA
-- ==========================================================

function TankMark:SaveFormData()
    -- [v0.23] Handle GUID lock updates (existing logic)
    if TankMark.editingLockGUID then
        local zone = TankMark.lockViewZone or (TankMark.zoneDropDown and UIDropDownMenu_GetText(TankMark.zoneDropDown))
        if not zone or zone == "Manage Saved Zones" then
            TankMark:Print("|cffff0000Error:|r Invalid zone for GUID lock.")
            return
        end
        
        local mob = TankMark.editMob:GetText()
        local icon = TankMark.selectedIcon
        
        if not TankMarkDB.StaticGUIDs[zone] then TankMarkDB.StaticGUIDs[zone] = {} end
        TankMarkDB.StaticGUIDs[zone][TankMark.editingLockGUID] = { mark = icon, name = mob }
        
        TankMark:Print("|cff00ff00Updated:|r Lock for " .. mob)
        TankMark:ResetEditor()
        TankMark:UpdateMobList()
        return
    end
    
    -- Handle new GUID lock
    if TankMark.isLockActive then
        local zone = TankMark.zoneDropDown and UIDropDownMenu_GetText(TankMark.zoneDropDown) or ""
        if zone == "Manage Saved Zones" or zone == "" then
            TankMark:Print("|cffff0000Error:|r Select a valid zone.")
            return
        end
        
        local mob = _gsub(TankMark.editMob:GetText(), ";", "")
        local icon = TankMark.selectedIcon
        
        local exists, guid = UnitExists("target")
        if exists and guid and not UnitIsPlayer("target") and UnitName("target") == mob then
            if not TankMarkDB.StaticGUIDs[zone] then TankMarkDB.StaticGUIDs[zone] = {} end
            TankMarkDB.StaticGUIDs[zone][guid] = { mark = icon, name = mob }
            TankMark:Print("|cff00ff00LOCKED GUID|r for: " .. mob)
            
            -- Rebuild GUID lock index
            if TankMark.RebuildGUIDLockIndex then
                TankMark:RebuildGUIDLockIndex()
            end
        else
            TankMark:Print("|cffff0000Error:|r Target lost or name mismatch. Lock failed.")
            return
        end
    end
    
    -- [v0.23] Normal mob entry save
    local zone = TankMark.zoneDropDown and UIDropDownMenu_GetText(TankMark.zoneDropDown) or ""
    if zone == "Manage Saved Zones" or zone == "" then
        TankMark:Print("|cffff0000Error:|r Select a valid zone.")
        return
    end
    
    local rawMob = TankMark.editMob:GetText()
    local mob = _gsub(rawMob, ";", "")
    local prio = tonumber(TankMark.editPrio:GetText()) or 1
    
    if mob == "" or mob == "Mob Name" then return end
    
    -- [v0.23] Build mob entry with sequential marks
    local mobEntry = {
        prio = prio,
        marks = {},
        type = TankMark.selectedClass and "CC" or "KILL",
        class = TankMark.selectedClass
    }
    
    -- Add main row mark
    _insert(mobEntry.marks, TankMark.selectedIcon)
    
    -- Add sequential marks
    for i, seqData in _ipairs(TankMark.editingSequentialMarks) do
        _insert(mobEntry.marks, seqData.icon)
    end
    
    -- Validation: No IGNORE (mark = 0) in sequences
    if _getn(mobEntry.marks) > 1 then
        for _, mark in _ipairs(mobEntry.marks) do
            if mark == 0 then
                TankMark:Print("|cffff0000Error:|r Sequential marks cannot contain IGNORE.")
                return
            end
        end
    end
    
    -- Save to database
    if not TankMarkDB.Zones[zone] then TankMarkDB.Zones[zone] = {} end
    TankMarkDB.Zones[zone][mob] = mobEntry
    
    local markCountStr = (_getn(mobEntry.marks) > 1) and (", " .. _getn(mobEntry.marks) .. " marks") or ""
    TankMark:Print("|cff00ff00Saved:|r " .. mob .. " |cff888888(P" .. prio .. markCountStr .. ")|r")
    
    -- Refresh activeDB
    if TankMark.RefreshActiveDB then
        TankMark:RefreshActiveDB()
    end
    
    TankMark:ResetEditor()
    TankMark.isZoneListMode = false
    TankMark:UpdateMobList()
end

-- ==========================================================
-- POPUP ACTIONS
-- ==========================================================

function TankMark:RequestDeleteMob(zone, mob)
    TankMark.pendingWipeAction = function()
        if TankMarkDB.Zones[zone] then
            TankMarkDB.Zones[zone][mob] = nil
            TankMark:UpdateMobList()
            TankMark:Print("|cffff0000Removed:|r " .. mob)
        end
    end
    StaticPopup_Show("TANKMARK_WIPE_CONFIRM", "Delete mob from database?\n\n|cffff0000" .. mob .. "|r")
end

function TankMark:RequestDeleteLock(guid, name)
    local z = TankMark.lockViewZone
    TankMark.pendingWipeAction = function()
        if z and TankMarkDB.StaticGUIDs[z] then
            TankMarkDB.StaticGUIDs[z][guid] = nil
            TankMark:UpdateMobList()
            TankMark:Print("|cffff0000Removed:|r Lock for " .. (name or "GUID"))
            
            -- Rebuild GUID lock index
            if TankMark.RebuildGUIDLockIndex then
                TankMark:RebuildGUIDLockIndex()
            end
        end
    end
    StaticPopup_Show("TANKMARK_WIPE_CONFIRM", "Remove GUID lock?\n\n|cffff0000" .. (name or "Unknown") .. "|r")
end

function TankMark:RequestDeleteZone(zoneName)
    TankMark.pendingWipeAction = function()
        TankMarkDB.Zones[zoneName] = nil
        TankMarkDB.StaticGUIDs[zoneName] = nil
        TankMark:Print("|cffff0000Deleted:|r Zone '" .. zoneName .. "'")
        
        -- [v0.21] Refresh activeDB if we deleted the current zone
        local currentZone = TankMark:GetCachedZone()
        if zoneName == currentZone and TankMark.LoadZoneData then
            TankMark:LoadZoneData(currentZone)
        end
        
        TankMark:UpdateMobList()
    end
    StaticPopup_Show("TANKMARK_WIPE_CONFIRM", "Delete ENTIRE zone and all its data?\n\n|cffff0000" .. zoneName .. "|r")
end

-- ==========================================================
-- ADD CURRENT ZONE DIALOG
-- ==========================================================

function TankMark:ShowAddCurrentZoneDialog()
    local currentZone = GetRealZoneText()
    
    -- Check if zone already exists
    if TankMarkDB.Zones[currentZone] then
        TankMark:Print("|cffffaa00Notice:|r Zone '" .. currentZone .. "' already exists in database.")
        return
    end
    
    StaticPopupDialogs["TANKMARK_ADD_ZONE"] = {
        text = "Add current zone to database?\n\n|cff00ff00" .. currentZone .. "|r",
        button1 = "Add",
        button2 = "Cancel",
        OnAccept = function()
            TankMarkDB.Zones[currentZone] = {}
            TankMark:Print("|cff00ff00Added:|r Zone '" .. currentZone .. "' to database.")
            UIDropDownMenu_SetText(currentZone, TankMark.zoneDropDown)
            
            if TankMark.isZoneListMode then
                TankMark:ToggleZoneBrowser()
            end
            
            TankMark:UpdateMobList()
        end,
        timeout = 0,
        whileDead = 1,
        hideOnEscape = 1,
        exclusive = 1,
    }
    
    StaticPopup_Show("TANKMARK_ADD_ZONE")
end

-- ==========================================================
-- MENUS
-- ==========================================================

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
    
    -- [v0.23] IGNORE option only for single-mark mobs
    if _getn(TankMark.editingSequentialMarks) == 0 then
        iconNames[0] = "|cff888888Disabled (Ignore)|r"
    end
    
    for i = 8, 0, -1 do
        if iconNames[i] then  -- Skip 0 if sequential marks exist
            local capturedIcon = i
            local info = {}
            info.text = iconNames[i]
            info.func = function()
                TankMark.selectedIcon = capturedIcon
                if TankMark.iconBtn and TankMark.iconBtn.tex then
                    TankMark:SetIconTexture(TankMark.iconBtn.tex, TankMark.selectedIcon)
                    TankMark:UpdateClassButton()
                end
                
                -- [v0.23] If IGNORE selected, set prio = 9
                if capturedIcon == 0 and TankMark.editPrio then
                    TankMark.editPrio:SetText("9")
                end
                
                CloseDropDownMenus()
            end
            info.checked = (TankMark.selectedIcon == i)
            UIDropDownMenu_AddButton(info)
        end
    end
end

function TankMark:InitClassMenu()
    local info = {}
    
    -- [v0.23] IGNORE option only for single-mark mobs
    if _getn(TankMark.editingSequentialMarks) == 0 then
        info = {
            text = "|cff888888IGNORE (Do Not Mark)|r",
            func = function()
                TankMark.selectedClass = nil
                TankMark:UpdateClassButton()
                TankMark.classBtn:SetText("IGNORED")
                TankMark.classBtn:SetTextColor(0.5, 0.5, 0.5)
                TankMark:ApplySmartDefaults("IGNORE")
            end
        }
        UIDropDownMenu_AddButton(info)
    end
    
    info = {
        text = "|cffffffffNo CC (Kill Target)|r",
        func = function()
            TankMark.selectedClass = nil
            TankMark:UpdateClassButton()
            TankMark:ApplySmartDefaults("KILL")
        end
    }
    UIDropDownMenu_AddButton(info)
    
    if TankMark.detectedCreatureType and CC_MAP[TankMark.detectedCreatureType] then
        info = { text = "--- Recommended ---", isTitle = 1 }
        UIDropDownMenu_AddButton(info)
        
        for _, class in _ipairs(CC_MAP[TankMark.detectedCreatureType]) do
            local capturedClass = class
            info = {
                text = "|cff00ff00" .. capturedClass .. "|r",
                func = function()
                    TankMark.selectedClass = capturedClass
                    TankMark:UpdateClassButton()
                    TankMark:ApplySmartDefaults(capturedClass)
                end
            }
            UIDropDownMenu_AddButton(info)
        end
    end
    
    info = { text = "--- All Classes ---", isTitle = 1 }
    UIDropDownMenu_AddButton(info)
    
    for _, class in _ipairs(ALL_CLASSES) do
        local capturedClass = class
        info = {
            text = capturedClass,
            func = function()
                TankMark.selectedClass = capturedClass
                TankMark:UpdateClassButton()
                TankMark:ApplySmartDefaults(capturedClass)
            end
        }
        UIDropDownMenu_AddButton(info)
    end
end

-- [v0.23] Initialize sequential row CC menu
function TankMark:InitSequentialClassMenu(seqIndex)
    local info = {}
    
    -- No IGNORE option for sequential rows
    info = {
        text = "|cffffffffNo CC (Kill Target)|r",
        func = function()
            if TankMark.editingSequentialMarks[seqIndex] then
                TankMark.editingSequentialMarks[seqIndex].class = nil
                TankMark.editingSequentialMarks[seqIndex].type = "KILL"
                TankMark:RefreshSequentialRows()
            end
        end
    }
    UIDropDownMenu_AddButton(info)
    
    if TankMark.detectedCreatureType and CC_MAP[TankMark.detectedCreatureType] then
        info = { text = "--- Recommended ---", isTitle = 1 }
        UIDropDownMenu_AddButton(info)
        
        for _, class in _ipairs(CC_MAP[TankMark.detectedCreatureType]) do
            local capturedClass = class
            info = {
                text = "|cff00ff00" .. capturedClass .. "|r",
                func = function()
                    if TankMark.editingSequentialMarks[seqIndex] then
                        TankMark.editingSequentialMarks[seqIndex].class = capturedClass
                        TankMark.editingSequentialMarks[seqIndex].type = "CC"
                        TankMark:RefreshSequentialRows()
                    end
                end
            }
            UIDropDownMenu_AddButton(info)
        end
    end
    
    info = { text = "--- All Classes ---", isTitle = 1 }
    UIDropDownMenu_AddButton(info)
    
    for _, class in _ipairs(ALL_CLASSES) do
        local capturedClass = class
        info = {
            text = capturedClass,
            func = function()
                if TankMark.editingSequentialMarks[seqIndex] then
                    TankMark.editingSequentialMarks[seqIndex].class = capturedClass
                    TankMark.editingSequentialMarks[seqIndex].type = "CC"
                    TankMark:RefreshSequentialRows()
                end
            end
        }
        UIDropDownMenu_AddButton(info)
    end
end

-- [v0.23] Initialize sequential row icon menu
function TankMark:InitSequentialIconMenu(seqIndex)
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
    
    -- No IGNORE option for sequential marks
    for i = 8, 1, -1 do
        local capturedIcon = i
        local info = {}
        info.text = iconNames[i]
        info.func = function()
            if TankMark.editingSequentialMarks[seqIndex] then
                TankMark.editingSequentialMarks[seqIndex].icon = capturedIcon
                TankMark:RefreshSequentialRows()
            end
            CloseDropDownMenus()
        end
        info.checked = (TankMark.editingSequentialMarks[seqIndex] and TankMark.editingSequentialMarks[seqIndex].icon == i)
        UIDropDownMenu_AddButton(info)
    end
end

-- ==========================================================
-- TAB CONSTRUCTION
-- ==========================================================

function TankMark:CreateMobTab(parent)
    local t1 = CreateFrame("Frame", nil, parent)
    t1:SetPoint("TOPLEFT", parent, "TOPLEFT", 15, -40)
    t1:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -15, 50)
    
    -- Zone Dropdown
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
    
    -- Manage Zones Checkbox
    local mzCheck = CreateFrame("CheckButton", "TM_ManageZonesCheck", t1, "UICheckButtonTemplate")
    mzCheck:SetWidth(24)
    mzCheck:SetHeight(24)
    mzCheck:SetPoint("LEFT", drop, "RIGHT", 10, 2)
    _G[mzCheck:GetName().."Text"]:SetText("Manage Zones")
    mzCheck:SetScript("OnClick", function()
        TankMark:ToggleZoneBrowser()
        PlaySound("igMainMenuOptionCheckBoxOn")
    end)
    TankMark.zoneModeCheck = mzCheck
    
    -- Add Zone Button
    local addZoneBtn = CreateFrame("Button", "TMAddZoneBtn", t1, "UIPanelButtonTemplate")
    addZoneBtn:SetWidth(80)
    addZoneBtn:SetHeight(24)
    addZoneBtn:SetPoint("TOPLEFT", drop, "TOPRIGHT", 130, -2)
    addZoneBtn:SetText("Add Zone")
    addZoneBtn:SetScript("OnClick", function()
        TankMark:ShowAddCurrentZoneDialog()
    end)
    
    -- Mob List Scroll Frame (REDUCED TO 6 ROWS)
    local sf = CreateFrame("ScrollFrame", "TankMarkScrollFrame", t1, "FauxScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", 10, -50)
    sf:SetWidth(380)
    sf:SetHeight(132)  -- 6 rows × 22px = 132px (was 198px for 9 rows)
    
    local listBg = CreateFrame("Frame", nil, t1)
    listBg:SetPoint("TOPLEFT", sf, -5, 5)
    listBg:SetPoint("BOTTOMRIGHT", sf, 25, -5)
    listBg:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })
    listBg:SetBackdropColor(0, 0, 0, 0.5)
    
    sf:SetScript("OnVerticalScroll", function()
        FauxScrollFrame_OnVerticalScroll(22, function() TankMark:UpdateMobList() end)
    end)
    TankMark.scrollFrame = sf
    
    -- Mob Rows (CREATE 6 INSTEAD OF 9)
    for i = 1, 6 do
        local row = CreateFrame("Button", "TMMobRow"..i, t1)
        row:SetWidth(380)
        row:SetHeight(22)
        row:SetPoint("TOPLEFT", 10, -50 - ((i-1)*22))
        
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetWidth(18)
        row.icon:SetHeight(18)
        row.icon:SetPoint("LEFT", 0, 0)
        
        row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.text:SetPoint("LEFT", row.icon, "RIGHT", 5, 0)
        
        row.del = CreateFrame("Button", "TMMobRowDel"..i, row, "UIPanelButtonTemplate")
        row.del:SetWidth(20)
        row.del:SetHeight(18)
        row.del:SetPoint("RIGHT", -5, 0)
        row.del:SetText("X")
        
        row.edit = CreateFrame("Button", "TMMobRowEdit"..i, row, "UIPanelButtonTemplate")
        row.edit:SetWidth(20)
        row.edit:SetHeight(18)
        row.edit:SetPoint("RIGHT", row.del, "LEFT", -2, 0)
        row.edit:SetText("E")
        
        row:Hide()
        TankMark.mobRows[i] = row
    end
    
    -- Search Box
    local searchLabel = t1:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    searchLabel:SetPoint("TOPLEFT", listBg, "BOTTOMLEFT", 5, -8)
    searchLabel:SetText("Search:")
    
    local sBox = TankMark:CreateEditBox(t1, "", 150)
    sBox:SetPoint("LEFT", searchLabel, "RIGHT", 8, 0)
    sBox:SetScript("OnTextChanged", function() TankMark:UpdateMobList() end)
    TankMark.searchBox = sBox
    
    local sClear = CreateFrame("Button", "TMBSearchClear", sBox, "UIPanelCloseButton")
    sClear:SetWidth(20)
    sClear:SetHeight(20)
    sClear:SetPoint("LEFT", sBox, "RIGHT", 2, 0)
    sClear:SetScript("OnClick", function()
        sBox:SetText("")
        sBox:ClearFocus()
        TankMark:UpdateMobList()
    end)
    
    -- ==========================================================
    -- [v0.23] NEW EDIT INTERFACE (ACCORDION + SEQUENTIAL MARKS)
    -- ==========================================================
    
    local editSectionTop = -230  -- Fixed position
    
    -- Divider Line
    local div = t1:CreateTexture(nil, "ARTWORK")
    div:SetHeight(1)
    div:SetWidth(380)
    div:SetPoint("TOPLEFT", 10, editSectionTop)
    div:SetTexture(1, 1, 1, 0.2)
    
-- [v0.23] ACCORDION HEADER: "+ Add a mob manually"
	local addMobHeader = CreateFrame("Button", "TMAddMobHeader", t1)
	addMobHeader:SetWidth(200)
	addMobHeader:SetHeight(20)
	addMobHeader:SetPoint("TOPLEFT", 10, editSectionTop - 10)

	-- Plus/Minus icon
	addMobHeader.arrow = addMobHeader:CreateTexture(nil, "ARTWORK")
	addMobHeader.arrow:SetWidth(16)
	addMobHeader.arrow:SetHeight(16)
	addMobHeader.arrow:SetPoint("LEFT", 0, 0)
	addMobHeader.arrow:SetTexture("Interface\\Buttons\\UI-PlusButton-Up")

	-- Text label
	addMobHeader.text = addMobHeader:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	addMobHeader.text:SetPoint("LEFT", addMobHeader.arrow, "RIGHT", 5, 0)
	addMobHeader.text:SetText("|cff00ccffAdd a mob manually|r")

	-- Hover effects
	addMobHeader:SetScript("OnEnter", function()
		this.text:SetTextColor(0, 1, 1)
	end)
	addMobHeader:SetScript("OnLeave", function()
		this.text:SetTextColor(0, 0.8, 1)
	end)

	-- Click handler (existing code - keep as is)
	addMobHeader:SetScript("OnClick", function()
		if TankMark.isAddMobExpanded then
			-- Collapse
			TankMark.addMobInterface:Hide()
			addMobHeader.arrow:SetTexture("Interface\\Buttons\\UI-PlusButton-Up")
			TankMark.isAddMobExpanded = false
		else
			-- Expand
			TankMark.addMobInterface:Show()
			addMobHeader.arrow:SetTexture("Interface\\Buttons\\UI-MinusButton-Up")
			TankMark.isAddMobExpanded = true
		end
	end)

	TankMark.addMobHeader = addMobHeader
    
    -- [v0.23] MAIN EDIT INTERFACE (Hidden by default)
    local addGroup = CreateFrame("Frame", nil, t1)
    addGroup:SetPoint("TOPLEFT", addMobHeader, "BOTTOMLEFT", 20, -5)
    addGroup:SetWidth(380)
    addGroup:SetHeight(120)  -- Increased height for sequential marks
    addGroup:Hide()
    TankMark.addMobInterface = addGroup
    
    -- Mob Name Input
    local nameBox = TankMark:CreateEditBox(addGroup, "Mob Name", 180)
    nameBox:SetPoint("TOPLEFT", 0, -5)
    TankMark.editMob = nameBox
    nameBox:SetScript("OnTextChanged", function()
        local text = this:GetText()
        if text and text ~= "" and text ~= "Mob Name" then
            if TankMark.saveBtn then TankMark.saveBtn:Enable() end
            
            -- [v0.23] Check GUID lock conflict
			if TankMark:HasGUIDLockForMobName(text) and TankMark.addMoreMarksText then
				TankMark.addMoreMarksText:SetTextColor(0.5, 0.5, 0.5)
				-- Disable the button that wraps the text
				if TankMark.addMoreMarksBtn then
					TankMark.addMoreMarksBtn:Disable()
				end
			elseif TankMark.addMoreMarksText and TankMark.addMoreMarksText:IsVisible() then
				TankMark.addMoreMarksText:SetTextColor(0, 0.8, 1)
				-- Enable the button
				if TankMark.addMoreMarksBtn then
					TankMark.addMoreMarksBtn:Enable()
				end
			end
        else
            if TankMark.saveBtn then TankMark.saveBtn:Disable() end
        end
    end)
    
    -- Target Button
    local targetBtn = CreateFrame("Button", "TMTargetBtn", addGroup, "UIPanelButtonTemplate")
    targetBtn:SetWidth(60)
    targetBtn:SetHeight(20)
    targetBtn:SetPoint("LEFT", nameBox, "RIGHT", 5, 0)
    targetBtn:SetText("Target")
    targetBtn:SetScript("OnClick", function()
        if UnitExists("target") then
            nameBox:SetText(UnitName("target"))
            TankMark.detectedCreatureType = UnitCreatureType("target")
            
            local currentIcon = GetRaidTargetIndex("target")
            if currentIcon then
                TankMark.selectedIcon = currentIcon
                if TankMark.iconBtn and TankMark.iconBtn.tex then
                    TankMark:SetIconTexture(TankMark.iconBtn.tex, currentIcon)
                end
            end
            
            if TankMark.lockBtn then TankMark.lockBtn:Enable() end
            if TankMark.saveBtn then TankMark.saveBtn:Enable() end
        end
    end)
    
    -- Second Row: Icon + Priority + CC + Lock + Save/Update + Cancel
    local row2Top = -40
    
    -- Icon Selector
    local iconSel = CreateFrame("Button", nil, addGroup)
    iconSel:SetWidth(24)
    iconSel:SetHeight(24)
    iconSel:SetPoint("TOPLEFT", 0, row2Top)
    
    local iconTex = iconSel:CreateTexture(nil, "ARTWORK")
    iconTex:SetAllPoints()
    iconSel.tex = iconTex
    iconTex:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
    TankMark:SetIconTexture(iconTex, TankMark.selectedIcon)
    
    local iconDrop = CreateFrame("Frame", "TMIconDropDown", iconSel, "UIDropDownMenuTemplate")
    UIDropDownMenu_Initialize(iconDrop, function() TankMark:InitIconMenu() end, "MENU")
    iconSel:SetScript("OnClick", function()
        ToggleDropDownMenu(1, nil, iconDrop, "cursor", 0, 0)
    end)
    TankMark.iconBtn = iconSel
    
    -- Priority Input + Spinner Buttons
    local prioBox = TankMark:CreateEditBox(addGroup, "Prio", 30)
    prioBox:SetPoint("LEFT", iconSel, "RIGHT", 10, 0)
    prioBox:SetText("1")
    prioBox:SetNumeric(true)
    TankMark.editPrio = prioBox
    
    -- Priority Up Button (▲)
    local prioUp = CreateFrame("Button", nil, addGroup)
    prioUp:SetWidth(16)
    prioUp:SetHeight(12)
    prioUp:SetPoint("LEFT", prioBox, "RIGHT", 2, 6)
    prioUp:SetNormalTexture("Interface\\Buttons\\UI-ScrollBar-ScrollUpButton-Up")
    prioUp:SetScript("OnClick", function()
        local current = tonumber(prioBox:GetText()) or 1
        prioBox:SetText(math.min(current + 1, 9))
    end)
    
    -- Priority Down Button (▼)
    local prioDown = CreateFrame("Button", nil, addGroup)
    prioDown:SetWidth(16)
    prioDown:SetHeight(12)
    prioDown:SetPoint("LEFT", prioBox, "RIGHT", 2, -6)
    prioDown:SetNormalTexture("Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Up")
    prioDown:SetScript("OnClick", function()
        local current = tonumber(prioBox:GetText()) or 1
        prioBox:SetText(math.max(current - 1, 1))
    end)
    
    -- CC Button
    local cBtn = CreateFrame("Button", "TMClassBtn", addGroup, "UIPanelButtonTemplate")
    cBtn:SetWidth(90)
    cBtn:SetHeight(20)
    cBtn:SetPoint("LEFT", prioDown, "RIGHT", 10, 0)
    cBtn:SetText("No CC (Kill)")
    
    local cDrop = CreateFrame("Frame", "TMClassDropDown", cBtn, "UIDropDownMenuTemplate")
    UIDropDownMenu_Initialize(cDrop, function() TankMark:InitClassMenu() end, "MENU")
    cBtn:SetScript("OnClick", function()
        ToggleDropDownMenu(1, nil, cDrop, "cursor", 0, 0)
    end)
    TankMark.classBtn = cBtn
    
    -- Lock Button
    local lBtn = CreateFrame("Button", "TMLockBtn", addGroup, "UIPanelButtonTemplate")
    lBtn:SetWidth(75)
    lBtn:SetHeight(20)
    lBtn:SetPoint("LEFT", cBtn, "RIGHT", 5, 0)
    lBtn:SetText("Lock Mark")
    lBtn:SetScript("OnClick", function() TankMark:ToggleLockState() end)
    lBtn:Disable()

	-- Add tooltip for when disabled due to sequential marks
	lBtn:SetScript("OnEnter", function()
		if not this:IsEnabled() and _getn(TankMark.editingSequentialMarks) > 0 then
			GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
			GameTooltip:SetText("GUID locking is unavailable for mobs with sequential marks. Remove all sequential marks to enable locking.", 1, 1, 1, 1, true)
			GameTooltip:Show()
		end
	end)
	lBtn:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)

    TankMark.lockBtn = lBtn
    
    -- Save Button
    local saveBtn = CreateFrame("Button", "TMSaveBtn", addGroup, "UIPanelButtonTemplate")
    saveBtn:SetWidth(50)
    saveBtn:SetHeight(20)
    saveBtn:SetPoint("LEFT", lBtn, "RIGHT", 5, 0)
    saveBtn:SetText("Save")
    saveBtn:SetScript("OnClick", function() TankMark:SaveFormData() end)
    saveBtn:Disable()
    TankMark.saveBtn = saveBtn
    
    -- Cancel Button
    local cancelBtn = CreateFrame("Button", "TMCancelBtn", addGroup, "UIPanelButtonTemplate")
    cancelBtn:SetWidth(20)
    cancelBtn:SetHeight(20)
    cancelBtn:SetPoint("LEFT", saveBtn, "RIGHT", 2, 0)
    cancelBtn:SetText("X")
    cancelBtn:SetScript("OnClick", function() TankMark:ResetEditor() end)
    cancelBtn:Hide()
    TankMark.cancelBtn = cancelBtn
    
    -- [v0.23] SEQUENTIAL MARKS SECTION
    
    -- Divider Label: "Marking Sequence:"
    local seqLabel = addGroup:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    seqLabel:SetPoint("TOPLEFT", 0, -60)
    seqLabel:SetText("|cff888888Marking Sequence:|r")
    
    -- "+ Add More Marks" Clickable Text
	local addMoreText = addGroup:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	addMoreText:SetPoint("TOPLEFT", seqLabel, "BOTTOMLEFT", 0, -5)
	addMoreText:SetText("|cff00ccff+ Add More Marks|r")
	addMoreText:Show()  -- Show by default
	TankMark.addMoreMarksText = addMoreText

	-- Make it clickable
	local addMoreBtn = CreateFrame("Button", nil, addGroup)
	addMoreBtn:SetAllPoints(addMoreText)
	addMoreBtn:SetScript("OnClick", function()
		TankMark:OnAddMoreMarksClicked()
	end)
	addMoreBtn:SetScript("OnEnter", function()
		if TankMark:HasGUIDLockForMobName(nameBox:GetText()) then
			GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
			GameTooltip:SetText("Sequential marking is unavailable because this mob has a GUID lock. Remove the GUID lock to enable sequential marks.", 1, 1, 1, 1, true)
			GameTooltip:Show()
		else
			addMoreText:SetTextColor(0, 1, 1)
		end
	end)
	addMoreBtn:SetScript("OnLeave", function()
		GameTooltip:Hide()
		if not TankMark:HasGUIDLockForMobName(nameBox:GetText()) then
			addMoreText:SetTextColor(0, 0.8, 1)
		end
	end)

	-- Store button reference globally
	TankMark.addMoreMarksBtn = addMoreBtn

	-- Store button reference for enable/disable
	addMoreText.clickFrame = addMoreBtn
    
    -- Sequential Marks Scroll Frame (max 3 visible rows)
	local seqScroll = CreateFrame("ScrollFrame", "TMSeqScrollFrame", addGroup, "FauxScrollFrameTemplate")
	seqScroll:SetWidth(360)
	seqScroll:SetHeight(72)  -- 3 rows × 24px
	seqScroll:SetPoint("TOPLEFT", addMoreText, "BOTTOMLEFT", 0, -5)
	seqScroll:Hide()
	TankMark.sequentialScrollFrame = seqScroll

	-- CREATE SCROLL CHILD (the actual content container)
	local seqContent = CreateFrame("Frame", nil, seqScroll)
	seqContent:SetWidth(360)
	seqContent:SetHeight(168)  -- 7 rows × 24px (full content height)
	seqScroll:SetScrollChild(seqContent)

	seqScroll:SetScript("OnVerticalScroll", function()
		FauxScrollFrame_OnVerticalScroll(24, function()
			TankMark:RefreshSequentialRows()
		end)
	end)

	-- Create 7 sequential row frames (max additional marks)
	TankMark.sequentialRows = {}
	for i = 1, 7 do
		local seqRow = CreateFrame("Frame", "TMSeqRow"..i, seqContent)
		seqRow:SetWidth(340)
		seqRow:SetHeight(24)
		seqRow:SetPoint("TOPLEFT", 0, -((i-1)*24))
		
		-- Row number badge
		seqRow.number = seqRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		seqRow.number:SetPoint("LEFT", 5, 0)
		seqRow.number:SetText("|cff888888#" .. (i + 1) .. "|r")
		
		-- Icon selector
		seqRow.iconBtn = CreateFrame("Button", nil, seqRow)
		seqRow.iconBtn:SetWidth(24)
		seqRow.iconBtn:SetHeight(20)
		seqRow.iconBtn:SetPoint("LEFT", seqRow.number, "RIGHT", 10, 0)
		
		seqRow.iconBtn.tex = seqRow.iconBtn:CreateTexture(nil, "ARTWORK")
		seqRow.iconBtn.tex:SetAllPoints()
		seqRow.iconBtn.tex:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
		TankMark:SetIconTexture(seqRow.iconBtn.tex, 8)
		
		local seqIconDrop = CreateFrame("Frame", "TMSeqIconDrop"..i, seqRow.iconBtn, "UIDropDownMenuTemplate")
		UIDropDownMenu_Initialize(seqIconDrop, function() TankMark:InitSequentialIconMenu(i) end, "MENU")
		seqRow.iconBtn:SetScript("OnClick", function()
			local rowIndex = this:GetParent().dataIndex
			if not rowIndex then return end
			
			-- Reinitialize menu with current dataIndex
			UIDropDownMenu_Initialize(seqIconDrop, function() 
				TankMark:InitSequentialIconMenu(rowIndex)
			end, "MENU")
			ToggleDropDownMenu(1, nil, seqIconDrop, "cursor", 0, 0)
		end)
		
		-- CC Button
		seqRow.ccBtn = CreateFrame("Button", nil, seqRow, "UIPanelButtonTemplate")
		seqRow.ccBtn:SetWidth(90)
		seqRow.ccBtn:SetHeight(20)
		seqRow.ccBtn:SetPoint("LEFT", seqRow.iconBtn, "RIGHT", 10, 0)
		seqRow.ccBtn:SetText("No CC (Kill)")
		
		local seqClassDrop = CreateFrame("Frame", "TMSeqClassDrop"..i, seqRow.ccBtn, "UIDropDownMenuTemplate")
		UIDropDownMenu_Initialize(seqClassDrop, function() TankMark:InitSequentialClassMenu(i) end, "MENU")
		seqRow.ccBtn:SetScript("OnClick", function()
			local rowIndex = this:GetParent().dataIndex
			if not rowIndex then return end
			
			-- Reinitialize menu with current dataIndex
			UIDropDownMenu_Initialize(seqClassDrop, function() 
				TankMark:InitSequentialClassMenu(rowIndex)
			end, "MENU")
			ToggleDropDownMenu(1, nil, seqClassDrop, "cursor", 0, 0)
		end)
		
		-- Remove button [X]
		seqRow.delBtn = CreateFrame("Button", nil, seqRow, "UIPanelButtonTemplate")
		seqRow.delBtn:SetWidth(20)
		seqRow.delBtn:SetHeight(20)
		seqRow.delBtn:SetPoint("RIGHT", -5, 0)
		seqRow.delBtn:SetText("X")
		seqRow.delBtn:SetScript("OnClick", function()
			TankMark:RemoveSequentialRow(this:GetParent().dataIndex)
		end)
		
		seqRow:Hide()
		TankMark.sequentialRows[i] = seqRow
	end
    return t1
end
