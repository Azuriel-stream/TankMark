-- TankMark: v0.14 (Hybrid Driver, TWA Sync & Normal Filter)
-- File: TankMark.lua

if not TankMark then
    TankMark = CreateFrame("Frame", "TankMarkFrame")
end

-- ==========================================================
-- LOCALIZATIONS & PERFORMANCE
-- ==========================================================
local _strfind = string.find
local _gsub = string.gsub
local _lower = string.lower
local _strfind = string.find
-- local _match = string.match
local _format = string.format

local _insert = table.insert
local _pairs = pairs
local _ipairs = ipairs
local _getn = table.getn

local _random = math.random

local _UnitExists = UnitExists
local _UnitIsDead = UnitIsDead
local _GetRaidTargetIndex = GetRaidTargetIndex
local _UnitName = UnitName
local _SetRaidTarget = SetRaidTarget
local _UnitHealth = UnitHealth
local _IsSpellInRange = IsSpellInRange
local _CheckInteractDistance = CheckInteractDistance
local _UnitClassification = UnitClassification 
local _getglobal = getglobal

-- Helper: Table Wipe for Lua 5.0 (Reduces Garbage)
local function table_wipe(t)
    if not t then return end
    for k in pairs(t) do t[k] = nil end
end

-- ==========================================================
-- LOGIC VARIABLES
-- ==========================================================
TankMark.IsSuperWoW = false
TankMark.visibleTargets = {} 
TankMark.usedIcons = {}
TankMark.activeMobNames = {}
TankMark.activeGUIDs = {}
TankMark.activeMobIsCaster = {}
TankMark.sessionAssignments = {}
TankMark.IsActive = true 
TankMark.MarkNormals = false 
TankMark.DeathPattern = nil 
TankMark.RangeSpellID = nil     
TankMark.RangeSpellIndex = nil  
TankMark.IsRecorderActive = false 

-- ==========================================================
-- RANGE SYSTEM (Turtle WoW / SuperWoW Optimized)
-- ==========================================================

function TankMark:ScanForRangeSpell()
    -- 1. SuperWoW Path (Use Hex ID 16707)
    if TankMark.IsSuperWoW then
        TankMark.RangeSpellID = 16707
        TankMark.RangeSpellIndex = nil
        TankMark:Print("Range Extension: Active (~40y).")
        return
    end

    -- 2. Standard Client Path (Scan for Name -> Store Index)
    local longRangeSpells = {
        ["Fireball"] = 35, ["Frostbolt"] = 30, ["Shadow Bolt"] = 30,
        ["Wrath"] = 30, ["Lightning Bolt"] = 30, ["Starfire"] = 30,
        ["Shoot"] = 30, ["Shoot Bow"] = 30, ["Shoot Gun"] = 30, ["Shoot Crossbow"] = 30,
        ["Hunter's Mark"] = 100, ["Mind Blast"] = 30, ["Smite"] = 30
    }

    local bestName = nil
    local bestRange = 0
    local bestIndex = nil

    local i = 1
    while true do
       if i > 1000 then break end -- Safety Cap
       local spellName, rank = GetSpellName(i, "spell")
       if not spellName then break end
       
       if longRangeSpells[spellName] then
           local range = longRangeSpells[spellName]
           if range > bestRange then
               bestRange = range
               bestName = spellName
               bestIndex = i
           end
       end
       i = i + 1
    end
    
    if bestIndex then
        TankMark.RangeSpellIndex = bestIndex
        TankMark.RangeSpellID = nil
        TankMark:Print("Range Extension: Legacy Mode (" .. bestName .. " ~" .. bestRange .. "y).")
    else
        TankMark.RangeSpellIndex = nil
        TankMark.RangeSpellID = nil
    end
end

function TankMark:Driver_IsDistanceValid(unitOrGuid)
    -- 1. SuperWoW Logic (ID based)
    if TankMark.IsSuperWoW and TankMark.RangeSpellID and _IsSpellInRange then
        local inRange = _IsSpellInRange(TankMark.RangeSpellID, unitOrGuid)
        if inRange == 1 then return true end
    
    -- 2. Standard Logic (Index based)
    elseif TankMark.RangeSpellIndex and _IsSpellInRange then
        local inRange = _IsSpellInRange(TankMark.RangeSpellIndex, "spell", unitOrGuid)
        if inRange == 1 then return true end
    end

    -- 3. Fallback (28 yards)
    if type(unitOrGuid) == "string" and not _strfind(unitOrGuid, "^0x") then
        return _CheckInteractDistance(unitOrGuid, 4)
    end
    
    return false 
end

-- ==========================================================
-- PERMISSIONS
-- ==========================================================

function TankMark:HasPermissions()
    local numRaid = GetNumRaidMembers()
    local numParty = GetNumPartyMembers()
    
    if numRaid == 0 and numParty == 0 then return true end -- Solo

    if numRaid > 0 then
        return (IsRaidLeader() or IsRaidOfficer())
    elseif numParty > 0 then
        return IsPartyLeader()
    end
    return false
end

function TankMark:CanAutomate()
    if not TankMark.IsActive then return false end
    return TankMark:HasPermissions()
end

-- ==========================================================
-- DRIVER
-- ==========================================================

function TankMark:Driver_GetGUID(unit)
    local exists, guid = _UnitExists(unit)
    if exists and guid then return guid end
    return nil
end

function TankMark:Driver_ApplyMark(unitOrGuid, icon)
    if TankMark:CanAutomate() then
        _SetRaidTarget(unitOrGuid, icon)
    end
end

-- ==========================================================
-- UTILITIES
-- ==========================================================

TankMark.MarkInfo = {
    [8] = { name = "SKULL",    color = "|cffffffff" },
    [7] = { name = "CROSS",    color = "|cffff0000" },
    [6] = { name = "SQUARE",   color = "|cff00ccff" },
    [5] = { name = "MOON",     color = "|cffaabbcc" },
    [4] = { name = "TRIANGLE", color = "|cff00ff00" },
    [3] = { name = "DIAMOND",  color = "|cffff00ff" },
    [2] = { name = "CIRCLE",   color = "|cffffaa00" },
    [1] = { name = "STAR",     color = "|cffffff00" }
}

function TankMark:GetMarkString(iconID)
    local info = TankMark.MarkInfo[iconID]
    if info then return info.color .. info.name .. "|r" end
    return "Mark " .. iconID
end

function TankMark:IsNameplate(frame)
    if not frame or not frame.GetChildren or not frame:IsVisible() then return false end
    local children = {frame:GetChildren()}
    for _, child in _ipairs(children) do
        if child.GetValue and child.GetMinMaxValues and child.SetMinMaxValues then return true end
    end
    return false
end

function TankMark:GetMobPriority(name)
    local zone = GetRealZoneText()
    if TankMarkDB.Zones[zone] and TankMarkDB.Zones[zone][name] then
        return TankMarkDB.Zones[zone][name].prio
    end
    return 99
end

function TankMark:EvictMarkOwner(iconID)
    local oldName = TankMark.activeMobNames[iconID]
    TankMark.activeMobNames[iconID] = nil
    TankMark.usedIcons[iconID] = nil
    TankMark.activeMobIsCaster[iconID] = nil
    for guid, mark in _pairs(TankMark.activeGUIDs) do
        if mark == iconID then TankMark.activeGUIDs[guid] = nil end
    end
end

function TankMark:UnmarkUnit(unit)
    if not TankMark:CanAutomate() then return end
    local currentIcon = _GetRaidTargetIndex(unit)
    local guid = TankMark:Driver_GetGUID(unit)
    TankMark:Driver_ApplyMark(unit, 0)
    if currentIcon then
        TankMark.usedIcons[currentIcon] = nil
        TankMark.activeMobNames[currentIcon] = nil
    end
    if guid then TankMark.activeGUIDs[guid] = nil end
    if TankMark.UpdateHUD then TankMark:UpdateHUD() end
end

function TankMark:ClearAllMarks()
    -- 1. Always wipe Local State
    TankMark.usedIcons = {}
    TankMark.sessionAssignments = {}
    TankMark.activeMobNames = {}
    TankMark.activeGUIDs = {}
    TankMark.visibleTargets = {}
    
    -- 2. Check Permissions for Server Wipe
    if TankMark:HasPermissions() then
        if TankMark.IsSuperWoW then
            for i = 1, 8 do
                if _UnitExists("mark"..i) then _SetRaidTarget("mark"..i, 0) end
            end
        end

        local function ClearUnit(unit)
            if _UnitExists(unit) and _GetRaidTargetIndex(unit) then 
                -- We call SetRaidTarget direct here to bypass CanAutomate check
                _SetRaidTarget(unit, 0)
            end
        end
        ClearUnit("target"); ClearUnit("mouseover")
        if UnitInRaid("player") then
            for i = 1, 40 do ClearUnit("raid"..i); ClearUnit("raid"..i.."target") end
        else
            for i = 1, 4 do ClearUnit("party"..i); ClearUnit("party"..i.."target") end
        end
        TankMark:Print("Session reset and ALL marks cleared.")
    else
        TankMark:Print("Session reset (Local HUD only - No permission to clear in-game marks).")
    end

    if TankMark.UpdateHUD then TankMark:UpdateHUD() end
end

function TankMark:ResetSession() TankMark:ClearAllMarks() end

-- ==========================================================
-- LOGIC & COMBAT
-- ==========================================================

function TankMark:InitCombatLogParser()
    local pattern = _gsub(UNITDIESOTHER, "%%s", "(.*)")
    TankMark.DeathPattern = "^" .. pattern .. "$"
end

function TankMark:VerifyMarkExistence(iconID)
    if TankMark.IsSuperWoW then
        for guid, mark in _pairs(TankMark.activeGUIDs) do
            if mark == iconID then
                if _UnitExists(guid) and not _UnitIsDead(guid) then return true end
            end
        end
    end
    local numRaid = GetNumRaidMembers()
    local numParty = GetNumPartyMembers()
    local function Check(unit)
        return _UnitExists(unit) and _GetRaidTargetIndex(unit) == iconID and not _UnitIsDead(unit)
    end
    if Check("target") then return true end
    if Check("mouseover") then return true end
    if numRaid > 0 then
        for i = 1, 40 do if Check("raid"..i.."target") then return true end end
    elseif numParty > 0 then
        for i = 1, 4 do if Check("party"..i.."target") then return true end end
    end
    return false
end

function TankMark:HandleCombatLog(msg)
    if not TankMark:CanAutomate() or not TankMark.DeathPattern then return end
    local _, _, deadMobName = _strfind(msg, TankMark.DeathPattern)
    
    if deadMobName then
        for iconID, name in _pairs(TankMark.activeMobNames) do
            if name == deadMobName then
                if not TankMark:VerifyMarkExistence(iconID) then
                    local guidToClear = nil
                    for guid, mark in _pairs(TankMark.activeGUIDs) do
                        if mark == iconID then guidToClear = guid end
                    end
                    TankMark.usedIcons[iconID] = nil
                    TankMark.activeMobNames[iconID] = nil
                    TankMark.activeMobIsCaster[iconID] = nil
                    if guidToClear then TankMark.activeGUIDs[guidToClear] = nil end
                    if TankMark.UpdateHUD then TankMark:UpdateHUD() end
                    if TankMark.IsSuperWoW and iconID == 8 then
                        TankMark:SmartDecideNextSkull()
                    end
                    return 
                end
            end
        end
    end
end

-- ==========================================================
-- CORE PROCESSING & RECORDER
-- ==========================================================

function TankMark:RecordUnit(guid)
    local name = _UnitName(guid)
    if not name then return end
    
    local zone = GetRealZoneText()
    if not TankMarkDB.Zones[zone] then TankMarkDB.Zones[zone] = {} end
    
    if not TankMarkDB.Zones[zone][name] then
        TankMarkDB.Zones[zone][name] = { 
            ["prio"] = 1, 
            ["mark"] = 8, 
            ["type"] = "KILL", 
            ["class"] = nil 
        }
        TankMark:Print("Recorder: Captured [" .. name .. "]")
        
        if TankMark.UpdateMobList then TankMark:UpdateMobList() end
    end
end

function TankMark:ProcessUnit(guid, mode)
    if not guid then return end

    -- 1. Sanity Checks
    if _UnitIsDead(guid) then return end
    if UnitIsPlayer(guid) or UnitIsFriend("player", guid) then return end
    local cType = UnitCreatureType(guid)
    if cType == "Critter" or cType == "Non-combat Pet" then return end

    -- [v0.14] Normal/Trivial Mob Filter
    if not TankMark.MarkNormals then
        local cls = _UnitClassification(guid)
        if not cls and guid == TankMark:Driver_GetGUID("mouseover") then
            cls = _UnitClassification("mouseover")
        end
        
        if cls == "normal" or cls == "trivial" or cls == "minus" then
            return -- Ignore normal mobs unless toggle is on
        end
    end

    -- Recorder Hook
    if TankMark.IsRecorderActive then
        TankMark:RecordUnit(guid)
    end

    -- 2. Check Database Existence
    local zone = GetRealZoneText()
    if not TankMark.IsRecorderActive and not TankMarkDB.Zones[zone] and not TankMarkDB.StaticGUIDs[zone] then return end

    -- 3. Check Current Mark
    local currentIcon = _GetRaidTargetIndex(guid)
    if currentIcon then
        if not TankMark.usedIcons[currentIcon] or not TankMark.activeGUIDs[guid] then
            TankMark:RegisterMarkUsage(currentIcon, _UnitName(guid), guid, (UnitPowerType(guid) == 0))
        end
        return 
    end

    if TankMark.activeGUIDs[guid] then return end

    -- 5. Range Check
    if mode == "PASSIVE" then
        if not TankMark:Driver_IsDistanceValid(guid) then return end
    end

    -- 6. Logic: Static GUID Lock
    if TankMarkDB.StaticGUIDs[zone] and TankMarkDB.StaticGUIDs[zone][guid] then
        local lockData = TankMarkDB.StaticGUIDs[zone][guid]
        local lockedIcon = nil
        
        if type(lockData) == "table" then
            lockedIcon = lockData.mark
        elseif type(lockData) == "number" then
            lockedIcon = lockData
        end
        
        if lockedIcon and lockedIcon > 0 then
            TankMark:Driver_ApplyMark(guid, lockedIcon)
            TankMark:RegisterMarkUsage(lockedIcon, _UnitName(guid), guid, (UnitPowerType(guid) == 0))
            return
        end
    end

    -- 7. Logic: Mob Name Lookup
    local mobName = _UnitName(guid)
    if not mobName then return end
    
    local mobData = nil
    if TankMarkDB.Zones[zone] and TankMarkDB.Zones[zone][mobName] then
        mobData = TankMarkDB.Zones[zone][mobName]
    end

    if mobData then
        mobData.name = mobName
        TankMark:ProcessKnownMob(mobData, guid)
    else
        if mode == "FORCE" then 
            TankMark:ProcessUnknownMob(guid) 
        end
    end
end

function TankMark:HandleMouseover()
    if not TankMark:CanAutomate() and not TankMark.IsRecorderActive then return end

    if IsControlKeyDown() then
        if _GetRaidTargetIndex("mouseover") then TankMark:UnmarkUnit("mouseover") end
        return 
    end

    if IsShiftKeyDown() then
        local guid = TankMark:Driver_GetGUID("mouseover")
        if guid then TankMark:ProcessUnit(guid, "FORCE") end
        return
    end

    local guid = TankMark:Driver_GetGUID("mouseover")
    if guid then TankMark:ProcessUnit(guid, "PASSIVE") end
end

function TankMark:RegisterMarkUsage(icon, name, guid, isCaster)
    TankMark.usedIcons[icon] = true
    TankMark.activeMobNames[icon] = name
    TankMark.activeMobIsCaster[icon] = isCaster
    if guid then TankMark.activeGUIDs[guid] = icon end
    
    if not TankMark.sessionAssignments[icon] then
        local assignee = TankMark:GetAssigneeForMark(icon)
        if assignee then TankMark.sessionAssignments[icon] = assignee end
    end
    if TankMark.UpdateHUD then TankMark:UpdateHUD() end
end

function TankMark:ProcessKnownMob(mobData, guid)
    -- [NEW] IGNORE LOGIC: Mark 0 = Do Not Process
    if mobData.mark == 0 then return end

    local iconToApply = nil
    
    if mobData.type == "KILL" then
        if not TankMark.usedIcons[mobData.mark] then
            iconToApply = mobData.mark
        elseif mobData.prio <= 2 then
            local currentOwnerName = TankMark.activeMobNames[mobData.mark]
            if currentOwnerName ~= mobData.name then
                TankMark:EvictMarkOwner(mobData.mark)
                iconToApply = mobData.mark
            else
                local fallbackOrder = {7, 2, 1, 3, 4, 6, 5} 
                for _, iconID in _ipairs(fallbackOrder) do
                    if not TankMark.usedIcons[iconID] then
                        iconToApply = iconID; break
                    end
                end
            end
        else
            iconToApply = TankMark:GetNextFreeKillIcon()
        end
    end
    
    if mobData.type == "CC" then
        if not TankMark.usedIcons[mobData.mark] then
            local assignedPlayer = TankMark:GetFirstAvailableBackup(mobData.class)
            if assignedPlayer then
                 iconToApply = mobData.mark
                 TankMark:AssignCC(iconToApply, assignedPlayer, mobData.type)
            end
        end
    end

    if iconToApply then
        TankMark:Driver_ApplyMark(guid, iconToApply)
        TankMark:RegisterMarkUsage(iconToApply, mobData.name, guid, (UnitPowerType(guid) == 0))
    end
end

function TankMark:ProcessUnknownMob(guid)
    local isCaster = (UnitPowerType(guid) == 0)
    local iconToApply = nil
    if isCaster then
        local preferredIcons = {8, 7}
        for _, iconID in _ipairs(preferredIcons) do
            if not TankMark.usedIcons[iconID] then
                iconToApply = iconID; break
            end
        end
    end
    if not iconToApply then iconToApply = TankMark:GetNextFreeKillIcon() end
    if iconToApply then
        TankMark:Driver_ApplyMark(guid, iconToApply)
        TankMark:RegisterMarkUsage(iconToApply, _UnitName(guid), guid, isCaster)
    end
end

function TankMark:GetFreeTankIcon()
    local zone = GetRealZoneText()
    for i = 1, 8 do
        if not TankMark.usedIcons[i] then
            local assignedName = nil
            if TankMarkDB.Profiles[zone] then 
                -- [FIX] Handle new table format
                local entry = TankMarkDB.Profiles[zone][i]
                if type(entry) == "table" then
                    assignedName = entry.tank
                elseif type(entry) == "string" then
                    assignedName = entry
                end
            end
            if assignedName and assignedName ~= "" then return i end
        end
    end
    return nil
end

function TankMark:GetNextFreeKillIcon()
    local killPriority = {8, 7, 2, 1, 3, 4, 6, 5}
    for _, iconID in _ipairs(killPriority) do
        if TankMark.usedIcons[iconID] then
            if not TankMark:VerifyMarkExistence(iconID) then
                TankMark.usedIcons[iconID] = nil
                TankMark.activeMobNames[iconID] = nil
                return iconID
            end
        else
            return iconID
        end
    end
    return nil
end

function TankMark:AssignCC(iconID, playerName, taskType)
    TankMark.sessionAssignments[iconID] = playerName
    TankMark.usedIcons[iconID] = true
    if TankMark.UpdateHUD then TankMark:UpdateHUD() end
end

-- ==========================================================
-- DEATH HANDLER & SMART AUTOMATION
-- ==========================================================

function TankMark:HandleDeath(unitID)
    if not TankMark:CanAutomate() then return end

    if not UnitIsPlayer(unitID) then
        local icon = _GetRaidTargetIndex(unitID)
        local hp = _UnitHealth(unitID)
        
        if icon and hp and hp <= 0 then
            TankMark.usedIcons[icon] = nil
            TankMark.activeMobNames[icon] = nil
            TankMark.activeMobIsCaster[icon] = nil
            local guid = TankMark:Driver_GetGUID(unitID)
            if guid then TankMark.activeGUIDs[guid] = nil end
            if TankMark.UpdateHUD then TankMark:UpdateHUD() end
            
            if TankMark.IsSuperWoW and icon == 8 then
                TankMark:SmartDecideNextSkull()
            end
        end
        return
    end

    local hp = _UnitHealth(unitID)
    if hp and hp > 0 then return end 

    local deadPlayerName = _UnitName(unitID)
    if not deadPlayerName then return end

    local assignedIcon = nil
    for icon, assignedTo in _pairs(TankMark.sessionAssignments) do
        if assignedTo == deadPlayerName then
            assignedIcon = icon; break
        end
    end
    if not assignedIcon then return end

    if TankMark.usedIcons[assignedIcon] then
        local _, classEng = UnitClass(unitID)
        local backupPlayer = TankMark:GetFirstAvailableBackup(classEng)
        if backupPlayer then
            TankMark.sessionAssignments[assignedIcon] = backupPlayer
            local markStr = TankMark:GetMarkString(assignedIcon)
            local msg = "ALERT: " .. deadPlayerName .. " died! You are now assigned to " .. markStr .. "."
            SendChatMessage(msg, "WHISPER", nil, backupPlayer)
            TankMark:Print("Reassigned " .. markStr .. " to " .. backupPlayer)
            if TankMark.UpdateHUD then TankMark:UpdateHUD() end
        end
    end
end

-- ==========================================================
-- SUPERWOW FEATURES
-- ==========================================================

function TankMark:InitDriver()
    if type(SUPERWOW_VERSION) ~= "nil" then
        TankMark.IsSuperWoW = true
        TankMark:Print("SuperWoW Detected: |cff00ff00v0.12 Hybrid Driver Loaded.|r")
        TankMark:StartSuperScanner()
    else
        TankMark:Print("Standard Client: Hybrid features disabled. Falling back to v0.10 driver.")
    end
end

function TankMark:StartSuperScanner()
    local f = CreateFrame("Frame", "TMScannerFrame")
    local elapsed = 0
    TankMark.visibleTargets = {} 

    f:SetScript("OnUpdate", function()
        -- [OPTIMIZATION] Throttle increased 0.25 -> 0.5s
        elapsed = elapsed + arg1
        if elapsed < 0.5 then return end 
        elapsed = 0
        
        -- [OPTIMIZATION] Only run if active & in group (or recording)
        if not TankMark.IsRecorderActive then
            if not TankMark:CanAutomate() then return end
            if GetNumRaidMembers() == 0 and GetNumPartyMembers() == 0 then return end
        end
        
        table_wipe(TankMark.visibleTargets) 
        
        -- SuperWoW Feature: frame:GetName(1) -> GUID
        local frames = {WorldFrame:GetChildren()}
        for _, plate in _ipairs(frames) do
            if plate:IsVisible() and TankMark:IsNameplate(plate) then
                local guid = plate:GetName(1)
                if guid then 
                    TankMark.visibleTargets[guid] = true 
                    if not TankMark.activeGUIDs[guid] then
                        TankMark:ProcessUnit(guid, "SCANNER")
                    end
                end
            end
        end
    end)
end

function TankMark:SmartDecideNextSkull()
    for guid, mark in _pairs(TankMark.activeGUIDs) do
        if mark == 7 and TankMark.visibleTargets[guid] then
             if not _UnitIsDead(guid) then
                 TankMark:Driver_ApplyMark(guid, 8)
                 TankMark:EvictMarkOwner(7)
                 TankMark:RegisterMarkUsage(8, _UnitName(guid), guid, false)
                 TankMark:Print("Auto-Promoted " .. _UnitName(guid) .. " to SKULL.")
                 return
             end
        end
    end
    
    local bestGUID = nil
    local lowestHP = 999999
    local zone = GetRealZoneText()
    
    if not TankMarkDB.Zones[zone] then return end
    
    for guid, _ in _pairs(TankMark.visibleTargets) do
        local currentMark = _GetRaidTargetIndex(guid)
        if not _UnitIsDead(guid) and (not currentMark or currentMark <= 6) then
            local name = _UnitName(guid)
            if name and TankMarkDB.Zones[zone][name] then
                local data = TankMarkDB.Zones[zone][name]
                if data.prio == 1 then
                    local hp = _UnitHealth(guid)
                    if hp and hp < lowestHP and hp > 0 then
                        lowestHP = hp
                        bestGUID = guid
                    end
                end
            end
        end
    end
    
    if bestGUID then
        local oldMark = _GetRaidTargetIndex(bestGUID)
        if oldMark then TankMark:EvictMarkOwner(oldMark) end
        TankMark:Driver_ApplyMark(bestGUID, 8)
        local name = _UnitName(bestGUID)
        TankMark:RegisterMarkUsage(8, name, bestGUID, false)
        TankMark:Print("Auto-Assigned SKULL to " .. name .. " (Lowest HP).")
    end
end

-- ==========================================================
-- COMMANDS & EVENTS
-- ==========================================================

function TankMark:GetAssigneeForMark(markID)
    local zone = GetRealZoneText()
    if TankMarkDB.Profiles[zone] and TankMarkDB.Profiles[zone][markID] then
        -- [FIX] Logic Breakdown: Separate Table vs String
        local profileEntry = TankMarkDB.Profiles[zone][markID]
        local assignedName = nil
        
        if type(profileEntry) == "table" then
            assignedName = profileEntry.tank
        elseif type(profileEntry) == "string" then
            assignedName = profileEntry
        end

        if assignedName and assignedName ~= "" then
            if UnitInRaid("player") then
                for i = 1, GetNumRaidMembers() do
                    if _UnitName("raid"..i) == assignedName then return assignedName end
                end
            else
                if _UnitName("player") == assignedName then return assignedName end
                for i = 1, GetNumPartyMembers() do
                    if _UnitName("party"..i) == assignedName then return assignedName end
                end
            end
        end
    end

    local requiredClass = TankMark.MarkClassDefaults[markID]
    if not requiredClass then return nil end 
    local candidates = {}
    local function IsPlayerBusy(name)
        for otherMark, assignee in _pairs(TankMark.sessionAssignments) do
            if assignee == name and otherMark ~= markID then return true end
        end
        return false
    end
    local function CheckUnit(unit)
        local _, class = UnitClass(unit)
        if class == requiredClass and not UnitIsDeadOrGhost(unit) then
            local name = _UnitName(unit)
            if name and not IsPlayerBusy(name) then _insert(candidates, name) end
        end
    end
    if UnitInRaid("player") then
        for i = 1, GetNumRaidMembers() do CheckUnit("raid"..i) end
    else
        local _, pClass = UnitClass("player")
        if pClass == requiredClass then 
            local name = _UnitName("player")
            if name and not IsPlayerBusy(name) then _insert(candidates, name) end
        end
        for i = 1, GetNumPartyMembers() do CheckUnit("party"..i) end
    end
    if _getn(candidates) > 0 then
        return candidates[_random(_getn(candidates))] -- [FIX] Localized math.random
    end
    return nil
end

function TankMark:SlashHandler(msg)
    -- [FIX] Use string.find instead of string.match for Lua 5.0
    -- find returns: start, end, capture1, capture2...
    local _, _, cmd, args = _strfind(msg, "^(%S*)%s*(.*)$")
    
    cmd = _lower(cmd or "")
    local iconNames = {
        ["skull"] = 8, ["cross"] = 7, ["square"] = 6, ["moon"] = 5,
        ["triangle"] = 4, ["diamond"] = 3, ["circle"] = 2, ["star"] = 1
    }
    
    if cmd == "reset" or cmd == "r" then TankMark:ResetSession()
    elseif cmd == "announce" or cmd == "a" then
        if TankMark.AnnounceAssignments then TankMark:AnnounceAssignments() end
    elseif cmd == "on" or cmd == "enable" then
        TankMark.IsActive = true
        TankMark:Print("Auto-Marking |cff00ff00ENABLED|r.")
    elseif cmd == "off" or cmd == "disable" then
        TankMark.IsActive = false
        TankMark:Print("Auto-Marking |cffff0000DISABLED|r.")
    elseif cmd == "normals" then
        TankMark.MarkNormals = not TankMark.MarkNormals
        TankMark:Print("Marking Normal Mobs: " .. (TankMark.MarkNormals and "|cff00ff00ON|r" or "|cffff0000OFF|r"))
        if TankMark.optionsFrame and TankMark.optionsFrame:IsVisible() then
             if TankMark.normalsCheck then TankMark.normalsCheck:SetChecked(TankMark.MarkNormals) end
        end
    elseif cmd == "recorder" then
        if args == "start" then
            TankMark.IsRecorderActive = true
            TankMark:Print("Flight Recorder: |cff00ff00ENABLED|r. Adding new mobs to DB.")
        elseif args == "stop" then
            TankMark.IsRecorderActive = false
            TankMark:Print("Flight Recorder: |cffff0000DISABLED|r.")
        else
            TankMark:Print("Usage: /tmark recorder start | stop")
        end
    elseif cmd == "zone" or cmd == "debug" then
        local currentZone = GetRealZoneText()
        TankMark:Print("Current Zone: " .. currentZone)
        TankMark:Print("Driver Mode: " .. (TankMark.IsSuperWoW and "|cff00ff00SuperWoW|r" or "|cffffaa00Standard|r"))
        if TankMark.IsSuperWoW then
            local count = 0
            for k,v in _pairs(TankMark.visibleTargets) do count = count + 1 end
            TankMark:Print("Scanner: " .. count .. " visible targets tracked.")
        end
    elseif cmd == "assign" then
        -- [FIX] Lua 5.0 compatible parsing
        local _, _, markStr, targetPlayer = _strfind(args, "^(%S+)%s+(%S+)$")
        
        if markStr and targetPlayer then
            markStr = _lower(markStr)
            local iconID = tonumber(markStr) or iconNames[markStr]
            if iconID and iconID >= 1 and iconID <= 8 then
                TankMark.sessionAssignments[iconID] = targetPlayer
                TankMark.usedIcons[iconID] = true 
                TankMark:Print("Manually assigned " .. TankMark:GetMarkString(iconID) .. " to " .. targetPlayer)
                if TankMark.UpdateHUD then TankMark:UpdateHUD() end
            else
                TankMark:Print("Invalid mark.")
            end
        else
            TankMark:Print("Usage: /tmark assign [mark] [player]")
        end
    elseif cmd == "config" or cmd == "c" then
        if TankMark.ShowOptions then TankMark:ShowOptions() end
    elseif cmd == "sync" or cmd == "share" then
        if TankMark.BroadcastZone then TankMark:BroadcastZone() end
    else
        TankMark:Print("Commands: /tmark reset, /tmark on, /tmark off, /tmark assign, /tmark recorder")
    end
end

function TankMark:AnnounceAssignments()
    local channel = "SAY" 
    if GetNumRaidMembers() > 0 then channel = "RAID"
    elseif GetNumPartyMembers() > 0 then channel = "PARTY" end
    SendChatMessage("TankMark Assignments:", channel)
    for i = 8, 1, -1 do
        local player = TankMark.sessionAssignments[i]
        if player then
             local markStr = TankMark:GetMarkString(i)
             local msg = markStr .. " assigned to " .. player
             SendChatMessage(msg, channel)
        end
    end
end

TankMark:SetScript("OnEvent", function()
    if (event == "ADDON_LOADED" and arg1 == "TankMark") then
        if TankMark.InitializeDB then TankMark:InitializeDB() end
    elseif (event == "PLAYER_LOGIN") then
        math.randomseed(time())
        if TankMark.UpdateRoster then TankMark:UpdateRoster() end
        TankMark:InitCombatLogParser()
        TankMark:InitDriver()
        TankMark:ScanForRangeSpell() 
        TankMark:Print("TankMark v0.14 (TWA Integration Active) Loaded.")
    elseif (event == "UPDATE_MOUSEOVER_UNIT") then
        TankMark:HandleMouseover()
    elseif (event == "UNIT_HEALTH") then
        TankMark:HandleDeath(arg1)
    elseif (event == "CHAT_MSG_COMBAT_HOSTILE_DEATH") then
        TankMark:HandleCombatLog(arg1)
    elseif (event == "CHAT_MSG_ADDON") then
        if TankMark.HandleSync then TankMark:HandleSync(arg1, arg2, arg4) end
    end
end)

TankMark:RegisterEvent("CHAT_MSG_COMBAT_HOSTILE_DEATH")

SLASH_TANKMARK1 = "/tmark"
SLASH_TANKMARK2 = "/tankmark"
SlashCmdList["TANKMARK"] = function(msg) TankMark:SlashHandler(msg) end