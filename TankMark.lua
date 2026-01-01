-- TankMark: v0.9-beta (Hybrid Core & SuperWoW Automation)
-- File: TankMark.lua

if not TankMark then
    TankMark = CreateFrame("Frame", "TankMarkFrame")
end

-- ==========================================================
-- LOCALIZATIONS
-- ==========================================================
local _strfind = string.find
local _gsub = string.gsub
local _pairs = pairs
local _UnitExists = UnitExists
local _UnitIsDead = UnitIsDead
local _GetRaidTargetIndex = GetRaidTargetIndex
local _UnitName = UnitName
local _SetRaidTarget = SetRaidTarget
local _UnitHealth = UnitHealth

-- ==========================================================
-- LOGIC ENGINE
-- ==========================================================

TankMark.IsSuperWoW = false
TankMark.visibleTargets = {} -- Cache for SuperWoW Scanner
TankMark.usedIcons = {}
TankMark.activeMobNames = {}
TankMark.activeGUIDs = {}
TankMark.activeMobIsCaster = {}
TankMark.sessionAssignments = {}
TankMark.IsActive = true
TankMark.DeathPattern = nil 

-- ==========================================================
-- 1. DRIVER ABSTRACTION LAYER (Standard Defaults)
-- ==========================================================

function TankMark:Driver_GetGUID(unit)
    local exists, guid = _UnitExists(unit)
    if exists and guid then return guid end
    return nil
end

function TankMark:Driver_ApplyMark(unitId, icon)
    if type(unitId) == "string" and _UnitExists(unitId) then
        _SetRaidTarget(unitId, icon)
    end
end

function TankMark:Driver_IsDistanceValid(unit)
    return CheckInteractDistance(unit, 4) -- ~28 yards
end

-- ==========================================================
-- 2. UTILITIES
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
    for _, child in ipairs(children) do
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
    -- 1. Wipe Internal Data
    TankMark.usedIcons = {}
    TankMark.sessionAssignments = {}
    TankMark.activeMobNames = {}
    TankMark.activeGUIDs = {}
    TankMark.visibleTargets = {}
    
    -- 2. SUPERWOW: Global Instant Wipe
    if TankMark.IsSuperWoW then
        for i = 1, 8 do
            local markUnit = "mark"..i
            if _UnitExists(markUnit) then
                _SetRaidTarget(markUnit, 0)
            end
        end
    end

    -- 3. STANDARD FALLBACK
    local function ClearUnit(unit)
        if _UnitExists(unit) and _GetRaidTargetIndex(unit) then 
            TankMark:Driver_ApplyMark(unit, 0)
        end
    end
    ClearUnit("target"); ClearUnit("mouseover")
    if UnitInRaid("player") then
        for i = 1, 40 do ClearUnit("raid"..i); ClearUnit("raid"..i.."target") end
    else
        for i = 1, 4 do ClearUnit("party"..i); ClearUnit("party"..i.."target") end
    end
    
    TankMark:Print("Session reset and ALL marks cleared.")
    if TankMark.UpdateHUD then TankMark:UpdateHUD() end
end

function TankMark:ResetSession() TankMark:ClearAllMarks() end

-- ==========================================================
-- 3. COMBAT LOG & SCANNER
-- ==========================================================

function TankMark:InitCombatLogParser()
    local pattern = _gsub(UNITDIESOTHER, "%%s", "(.*)")
    TankMark.DeathPattern = "^" .. pattern .. "$"
end

function TankMark:VerifyMarkExistence(iconID)
    if TankMark.IsSuperWoW then
        for guid, mark in pairs(TankMark.activeGUIDs) do
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
    if not TankMark.IsActive or not TankMark.DeathPattern then return end
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
                    
                    -- Trigger Automation
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
-- 4. MARKING LOGIC
-- ==========================================================

function TankMark:HandleMouseover()
    if IsControlKeyDown() then
        if _GetRaidTargetIndex("mouseover") then TankMark:UnmarkUnit("mouseover") end
        return 
    end

    if UnitIsDeadOrGhost("mouseover") or UnitIsPlayer("mouseover") or UnitIsFriend("player", "mouseover") then return end
    local cType = UnitCreatureType("mouseover")
    if cType == "Critter" or cType == "Non-combat Pet" then return end

    local zone = GetRealZoneText()
    if not TankMarkDB.Zones[zone] and not TankMarkDB.StaticGUIDs[zone] then return end

    local guid = TankMark:Driver_GetGUID("mouseover")
    local currentIcon = _GetRaidTargetIndex("mouseover")

    if currentIcon then
        if not TankMark.usedIcons[currentIcon] or (guid and not TankMark.activeGUIDs[guid]) then
            TankMark.usedIcons[currentIcon] = true
            TankMark.activeMobNames[currentIcon] = _UnitName("mouseover")
            TankMark.activeMobIsCaster[currentIcon] = (UnitPowerType("mouseover") == 0)
            if guid then TankMark.activeGUIDs[guid] = currentIcon end
            if TankMark.UpdateHUD then TankMark:UpdateHUD() end
        end
        return 
    end

    if guid and TankMark.activeGUIDs[guid] then return end

    if guid and TankMarkDB.StaticGUIDs[zone] and TankMarkDB.StaticGUIDs[zone][guid] then
        local lockedIcon = TankMarkDB.StaticGUIDs[zone][guid]
        TankMark:Driver_ApplyMark("mouseover", lockedIcon)
        TankMark:RegisterMarkUsage(lockedIcon, _UnitName("mouseover"), guid, (UnitPowerType("mouseover") == 0))
        return
    end

    local mobName = _UnitName("mouseover")
    if not mobName then return end
    
    local mobData = nil
    if TankMarkDB.Zones[zone] and TankMarkDB.Zones[zone][mobName] then
        mobData = TankMarkDB.Zones[zone][mobName]
    end

    if mobData then
        mobData.name = mobName
        TankMark:ProcessKnownMob(mobData, guid)
    else
        TankMark:ProcessUnknownMob()
    end
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
                for _, iconID in ipairs(fallbackOrder) do
                    if not TankMark.usedIcons[iconID] then
                        iconToApply = iconID; break
                    else
                        local ownerName = TankMark.activeMobNames[iconID]
                        local ownerPrio = TankMark:GetMobPriority(ownerName)
                        if mobData.prio < ownerPrio then
                            TankMark:EvictMarkOwner(iconID)
                            iconToApply = iconID; break
                        end
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
        local target = guid or "mouseover"
        TankMark:Driver_ApplyMark(target, iconToApply)
        TankMark:RegisterMarkUsage(iconToApply, mobData.name, guid, (UnitPowerType("mouseover") == 0))
    end
end

function TankMark:ProcessUnknownMob()
    local iconToApply = nil
    local isCaster = (UnitPowerType("mouseover") == 0)

    if isCaster then
        local preferredIcons = {8, 7}
        for _, iconID in ipairs(preferredIcons) do
            if not TankMark.usedIcons[iconID] then
                iconToApply = iconID; break
            else
                local ownerName = TankMark.activeMobNames[iconID]
                local ownerPrio = TankMark:GetMobPriority(ownerName)
                local ownerIsCaster = TankMark.activeMobIsCaster[iconID]
                if ownerPrio >= 99 and not ownerIsCaster then
                    TankMark:EvictMarkOwner(iconID)
                    iconToApply = iconID; break
                end
            end
        end
    end

    if not iconToApply then iconToApply = TankMark:GetNextFreeKillIcon() end

    if iconToApply then
        local guid = TankMark:Driver_GetGUID("mouseover")
        local target = guid or "mouseover"
        TankMark:Driver_ApplyMark(target, iconToApply)
        TankMark:RegisterMarkUsage(iconToApply, _UnitName("mouseover"), guid, isCaster)
    end
end

function TankMark:GetFreeTankIcon()
    local zone = GetRealZoneText()
    for i = 1, 8 do
        if not TankMark.usedIcons[i] then
            local assignedName = nil
            if TankMarkDB.Profiles[zone] then assignedName = TankMarkDB.Profiles[zone][i] end
            if assignedName and assignedName ~= "" then return i end
        end
    end
    return nil
end

function TankMark:GetNextFreeKillIcon()
    local killPriority = {8, 7, 2, 1, 3, 4, 6, 5}
    for _, iconID in ipairs(killPriority) do
        if not TankMark.usedIcons[iconID] then return iconID end
    end
    return nil
end

function TankMark:AssignCC(iconID, playerName, taskType)
    TankMark.sessionAssignments[iconID] = playerName
    TankMark.usedIcons[iconID] = true
    if TankMark.UpdateHUD then TankMark:UpdateHUD() end
end

-- ==========================================================
-- 5. DEATH HANDLER & SMART AUTOMATION
-- ==========================================================

function TankMark:HandleDeath(unitID)
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
-- 6. SUPERWOW DRIVER INITIALIZATION
-- ==========================================================

function TankMark:InitDriver()
    if type(SUPERWOW_VERSION) ~= "nil" then
        TankMark.IsSuperWoW = true
        TankMark:Print("SuperWoW Detected: |cff00ff00Enhanced Driver Loaded.|r")
        
        TankMark.Driver_GetGUID = function(self, unit)
            local exists, guid = _UnitExists(unit)
            if exists then return guid end 
            return nil
        end

        TankMark.Driver_ApplyMark = function(self, target, icon)
            _SetRaidTarget(target, icon)
        end
        
        TankMark:StartSuperScanner()
        
    else
        TankMark:Print("Standard Client Detected: Loaded Standard Driver.")
    end
end

-- ==========================================================
-- 7. SUPERWOW FEATURES
-- ==========================================================

function TankMark:StartSuperScanner()
    local f = CreateFrame("Frame", "TMScannerFrame")
    local elapsed = 0
    f:SetScript("OnUpdate", function()
        elapsed = elapsed + arg1
        if elapsed < 0.2 then return end 
        elapsed = 0
        TankMark.visibleTargets = {} 
        local frames = {WorldFrame:GetChildren()}
        for _, plate in ipairs(frames) do
            if plate:IsVisible() and TankMark:IsNameplate(plate) then
                local guid = plate:GetName(1)
                if guid then TankMark.visibleTargets[guid] = true end
            end
        end
    end)
end

function TankMark:SmartDecideNextSkull()
    for guid, mark in pairs(TankMark.activeGUIDs) do
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
    
    for guid, _ in pairs(TankMark.visibleTargets) do
        if not _UnitIsDead(guid) and not _GetRaidTargetIndex(guid) then
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
        TankMark:Driver_ApplyMark(bestGUID, 8)
        local name = _UnitName(bestGUID)
        TankMark:RegisterMarkUsage(8, name, bestGUID, false)
        TankMark:Print("Auto-Assigned SKULL to " .. name .. " (Lowest HP).")
    end
end

-- ==========================================================
-- 8. COMMANDS & EVENTS
-- ==========================================================

function TankMark:GetAssigneeForMark(markID)
    local zone = GetRealZoneText()
    if TankMarkDB.Profiles[zone] and TankMarkDB.Profiles[zone][markID] then
        local assignedName = TankMarkDB.Profiles[zone][markID]
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
            if name and not IsPlayerBusy(name) then table.insert(candidates, name) end
        end
    end
    if UnitInRaid("player") then
        for i = 1, GetNumRaidMembers() do CheckUnit("raid"..i) end
    else
        local _, pClass = UnitClass("player")
        if pClass == requiredClass then 
            local name = _UnitName("player")
            if name and not IsPlayerBusy(name) then table.insert(candidates, name) end
        end
        for i = 1, GetNumPartyMembers() do CheckUnit("party"..i) end
    end
    if table.getn(candidates) > 0 then
        return candidates[math.random(table.getn(candidates))]
    end
    return nil
end

function TankMark:SlashHandler(msg)
    local cmd, args = string.match(msg, "^(%S*)%s*(.*)$");
    cmd = string.lower(cmd or "")
    local iconNames = {
        ["skull"] = 8, ["cross"] = 7, ["square"] = 6, ["moon"] = 5,
        ["triangle"] = 4, ["diamond"] = 3, ["circle"] = 2, ["star"] = 1
    }
    if cmd == "reset" or cmd == "r" then TankMark:ResetSession()
    elseif cmd == "announce" or cmd == "a" then
        if TankMark.AnnounceAssignments then TankMark:AnnounceAssignments() end
    elseif cmd == "zone" or cmd == "debug" then
        local currentZone = GetRealZoneText()
        TankMark:Print("Current Zone: " .. currentZone)
        TankMark:Print("Driver Mode: " .. (TankMark.IsSuperWoW and "|cff00ff00SuperWoW|r" or "|cffffaa00Standard|r"))
        if TankMark.IsSuperWoW then
            local count = 0
            for k,v in pairs(TankMark.visibleTargets) do count = count + 1 end
            TankMark:Print("Scanner: " .. count .. " visible targets tracked.")
        end
    elseif cmd == "assign" then
        local markStr, targetPlayer = string.match(args, "^(%S+)%s+(%S+)$")
        if markStr and targetPlayer then
            markStr = string.lower(markStr)
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
            TankMark:Print("Usage: /tm assign [mark] [player]")
        end
    elseif cmd == "config" or cmd == "c" then
        if TankMark.ShowOptions then TankMark:ShowOptions() end
    elseif cmd == "sync" or cmd == "share" then
        if TankMark.BroadcastZone then TankMark:BroadcastZone() end
    else
        TankMark:Print("Commands: /tm reset, /tm announce, /tm assign [mark] [player]")
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
        TankMark:Print("TankMark v0.9-beta Loaded.")
    elseif (event == "UPDATE_MOUSEOVER_UNIT") then
        if TankMark.IsActive then TankMark:HandleMouseover() end
    elseif (event == "UNIT_HEALTH") then
        TankMark:HandleDeath(arg1)
    elseif (event == "CHAT_MSG_COMBAT_HOSTILE_DEATH") then
        TankMark:HandleCombatLog(arg1)
    elseif (event == "CHAT_MSG_ADDON") then
        if TankMark.HandleSync then TankMark:HandleSync(arg1, arg2, arg4) end
    end
end)

TankMark:RegisterEvent("CHAT_MSG_COMBAT_HOSTILE_DEATH")

SLASH_TANKMARK1 = "/tm"
SLASH_TANKMARK2 = "/tankmark"
SlashCmdList["TANKMARK"] = function(msg) TankMark:SlashHandler(msg) end