-- TankMark: v0.9-dev (Hybrid Driver Core)
-- File: TankMark.lua
-- Description: Core event handling with Driver Abstraction (Standard vs SuperWoW).

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

-- ==========================================================
-- DRIVER STATE & LOGIC ENGINE
-- ==========================================================

TankMark.IsSuperWoW = false
TankMark.usedIcons = {}
TankMark.activeMobNames = {}
TankMark.activeGUIDs = {}
TankMark.activeMobIsCaster = {}
TankMark.sessionAssignments = {}
TankMark.IsActive = true
TankMark.DeathPattern = nil 

-- ==========================================================
-- 1. DRIVER ABSTRACTION LAYER (DEFAULT / STANDARD)
-- These methods are the "Standard 1.12" implementation.
-- They will be overwritten if SuperWoW is detected.
-- ==========================================================

-- Standard: GetGUID relies on UnitExists usually returning nil/1.
-- In standard 1.12, we rarely get a real GUID unless using workarounds.
function TankMark:Driver_GetGUID(unit)
    local exists, guid = _UnitExists(unit)
    -- In standard vanilla, 'guid' is usually nil. 
    -- If user has a specialized addon/patch, it might return something.
    if exists and guid then return guid end
    return nil
end

-- Standard: ApplyMark requires a valid UnitID (target, mouseover, raidN).
function TankMark:Driver_ApplyMark(unitId, icon)
    -- Safety: Ensure unitId is a string and valid unit
    if type(unitId) == "string" and _UnitExists(unitId) then
        _SetRaidTarget(unitId, icon)
    end
end

-- Standard: Distance check is hard. We rely on "IsVisible" or range hacks.
function TankMark:Driver_IsDistanceValid(unit)
    return CheckInteractDistance(unit, 4) -- Approx 28 yards
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
    local guid = TankMark:Driver_GetGUID(unit) -- ABSTRACTION USAGE
    
    TankMark:Driver_ApplyMark(unit, 0) -- ABSTRACTION USAGE
    
    if currentIcon then
        TankMark.usedIcons[currentIcon] = nil
        TankMark.activeMobNames[currentIcon] = nil
    end
    if guid then TankMark.activeGUIDs[guid] = nil end
    if TankMark.UpdateHUD then TankMark:UpdateHUD() end
end

function TankMark:ClearAllMarks()
    TankMark.usedIcons = {}
    TankMark.sessionAssignments = {}
    TankMark.activeMobNames = {}
    TankMark.activeGUIDs = {}
    
    local function ClearUnit(unit)
        if _UnitExists(unit) and _GetRaidTargetIndex(unit) then 
            TankMark:Driver_ApplyMark(unit, 0) -- ABSTRACTION USAGE
        end
    end
    ClearUnit("target"); ClearUnit("mouseover")
    if UnitInRaid("player") then
        for i = 1, 40 do ClearUnit("raid"..i); ClearUnit("raid"..i.."target") end
    else
        for i = 1, 4 do ClearUnit("party"..i); ClearUnit("party"..i.."target") end
    end
    TankMark:Print("Session reset and visible marks cleared.")
    if TankMark.UpdateHUD then TankMark:UpdateHUD() end
end

function TankMark:ResetSession() TankMark:ClearAllMarks() end

-- ==========================================================
-- 3. COMBAT LOG PARSER
-- ==========================================================

function TankMark:InitCombatLogParser()
    local pattern = _gsub(UNITDIESOTHER, "%%s", "(.*)")
    TankMark.DeathPattern = "^" .. pattern .. "$"
end

function TankMark:VerifyMarkExistence(iconID)
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
                    TankMark.usedIcons[iconID] = nil
                    TankMark.activeMobNames[iconID] = nil
                    TankMark.activeMobIsCaster[iconID] = nil
                    for guid, mark in _pairs(TankMark.activeGUIDs) do
                        if mark == iconID then TankMark.activeGUIDs[guid] = nil end
                    end
                    if TankMark.UpdateHUD then TankMark:UpdateHUD() end
                    return 
                end
            end
        end
    end
end

-- ==========================================================
-- 4. CORE MARKING LOGIC (Refactored for Abstraction)
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

    local guid = TankMark:Driver_GetGUID("mouseover") -- ABSTRACTION USAGE
    local currentIcon = _GetRaidTargetIndex("mouseover")

    -- A. EXISTING MARKS
    if currentIcon then
        if not TankMark.usedIcons[currentIcon] or (guid and not TankMark.activeGUIDs[guid]) then
            TankMark.usedIcons[currentIcon] = true
            TankMark.activeMobNames[currentIcon] = _UnitName("mouseover")
            TankMark.activeMobIsCaster[currentIcon] = (UnitPowerType("mouseover") == 0)
            if guid then TankMark.activeGUIDs[guid] = currentIcon end
            if TankMark.UpdateHUD then TankMark:UpdateHUD() end
        end

        -- PROMOTION LOGIC (Cycle CROSS -> SKULL)
        if currentIcon == 7 and not TankMark.usedIcons[8] then
            TankMark:Driver_ApplyMark("mouseover", 8) -- ABSTRACTION USAGE
            TankMark:EvictMarkOwner(7)
            TankMark:RegisterMarkUsage(8, _UnitName("mouseover"), guid, (UnitPowerType("mouseover") == 0))
        end
        return 
    end

    if guid and TankMark.activeGUIDs[guid] then return end

    -- B. NEW MARKS (Static & Templates)
    if guid and TankMarkDB.StaticGUIDs[zone] and TankMarkDB.StaticGUIDs[zone][guid] then
        local lockedIcon = TankMarkDB.StaticGUIDs[zone][guid]
        TankMark:Driver_ApplyMark("mouseover", lockedIcon) -- ABSTRACTION USAGE
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
    
    if mobData.type == "CC" then
        local freeTankIcon = TankMark:GetFreeTankIcon()
        if freeTankIcon then
            iconToApply = freeTankIcon
        else
            local assignedPlayer = TankMark:GetFirstAvailableBackup(mobData.class)
            if assignedPlayer then
                if not TankMark.usedIcons[mobData.mark] then
                    iconToApply = mobData.mark
                    TankMark:AssignCC(iconToApply, assignedPlayer, mobData.type)
                end
            else
                iconToApply = TankMark:GetNextFreeKillIcon()
            end
        end
    else
        -- KILL TARGET LOGIC
        if not TankMark.usedIcons[mobData.mark] then
            iconToApply = mobData.mark
        elseif mobData.prio <= 2 then
            local currentOwnerName = TankMark.activeMobNames[mobData.mark]
            if currentOwnerName ~= mobData.name then
                TankMark:EvictMarkOwner(mobData.mark)
                iconToApply = mobData.mark
            else
                -- Cascade
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

    if iconToApply then
        TankMark:Driver_ApplyMark("mouseover", iconToApply) -- ABSTRACTION USAGE
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
        TankMark:Driver_ApplyMark("mouseover", iconToApply) -- ABSTRACTION USAGE
        TankMark:RegisterMarkUsage(iconToApply, _UnitName("mouseover"), TankMark:GetUnitGUID("mouseover"), isCaster)
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
-- 5. THE WATCHDOG (DEATH MONITOR)
-- ==========================================================

function TankMark:HandleDeath(unitID)
    if not UnitIsPlayer(unitID) then
        local icon = _GetRaidTargetIndex(unitID)
        local hp = UnitHealth(unitID)
        
        if icon and hp and hp <= 0 then
            TankMark.usedIcons[icon] = nil
            TankMark.activeMobNames[icon] = nil
            TankMark.activeMobIsCaster[icon] = nil
            local guid = TankMark:Driver_GetGUID(unitID) -- ABSTRACTION USAGE
            if guid then TankMark.activeGUIDs[guid] = nil end
            if TankMark.UpdateHUD then TankMark:UpdateHUD() end
        end
        return
    end

    local hp = UnitHealth(unitID)
    if hp and hp > 0 then return end 

    local deadPlayerName = _UnitName(unitID)
    if not deadPlayerName then return end

    local assignedIcon = nil
    for icon, assignedTo in _pairs(TankMark.sessionAssignments) do
        if assignedTo == deadPlayerName then
            assignedIcon = icon
            break
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
        else
            TankMark:Print("|cffff0000CRITICAL:|r " .. deadPlayerName .. " died. No backups found for " .. "{rt"..assignedIcon.."}!")
        end
    end
end

-- ==========================================================
-- 6. INITIALIZATION & DRIVER LOADING
-- ==========================================================

function TankMark:InitDriver()
    -- Check for SuperWoW global
    if type(SUPERWOW_VERSION) ~= "nil" then
        TankMark.IsSuperWoW = true
        TankMark:Print("SuperWoW Detected: |cff00ff00Enhanced Driver Loaded.|r")
        
        -- OVERRIDE: Driver_GetGUID
        -- Source 16: "UnitExists now also returns GUID of unit"
        TankMark.Driver_GetGUID = function(self, unit)
            local exists, guid = _UnitExists(unit)
            if exists then return guid end -- Use the GUID string returned by API
            return nil
        end

        -- OVERRIDE: Driver_ApplyMark
        -- Source 44: SetRaidTarget accepts GUID
        TankMark.Driver_ApplyMark = function(self, target, icon)
            _SetRaidTarget(target, icon) -- 'target' can be a GUID string now
        end

        -- OVERRIDE: Driver_IsDistanceValid
        -- Source 32: SpellInfo gives max range? Or CheckInteractDistance works on GUID?
        -- We can try simple interaction check first.
        TankMark.Driver_IsDistanceValid = function(self, unit)
            return CheckInteractDistance(unit, 4)
        end
        
    else
        TankMark:Print("Standard Client Detected: Loaded Standard Driver.")
    end
end

-- ==========================================================
-- 7. COMMANDS & EVENTS
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

    if cmd == "reset" or cmd == "r" then
        TankMark:ResetSession()
        
    elseif cmd == "announce" or cmd == "a" then
        if TankMark.AnnounceAssignments then TankMark:AnnounceAssignments() end

    elseif cmd == "zone" or cmd == "debug" then
        local currentZone = GetRealZoneText()
        TankMark:Print("Current Zone: " .. currentZone)
        TankMark:Print("Driver Mode: " .. (TankMark.IsSuperWoW and "|cff00ff00SuperWoW|r" or "|cffffaa00Standard|r"))
        
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

-- ==========================================================
-- 8. EVENTS
-- ==========================================================

TankMark:SetScript("OnEvent", function()
    if (event == "ADDON_LOADED" and arg1 == "TankMark") then
        if TankMark.InitializeDB then TankMark:InitializeDB() end
    
    elseif (event == "PLAYER_LOGIN") then
        math.randomseed(time())
        if TankMark.UpdateRoster then TankMark:UpdateRoster() end
        TankMark:InitCombatLogParser()
        
        -- NEW v0.9: Initialize Driver Detection
        TankMark:InitDriver()
        
        TankMark:Print("TankMark v0.9-dev Loaded.")

    elseif (event == "UPDATE_MOUSEOVER_UNIT") then
        if TankMark.IsActive then TankMark:HandleMouseover() end

    elseif (event == "UNIT_HEALTH") then
        TankMark:HandleDeath(arg1)

    elseif (event == "CHAT_MSG_COMBAT_HOSTILE_DEATH") then
        TankMark:HandleCombatLog(arg1)
    
    elseif (event == "CHAT_MSG_ADDON") then
        if TankMark.HandleSync then
            TankMark:HandleSync(arg1, arg2, arg4)
        end
    end
end)

TankMark:RegisterEvent("CHAT_MSG_COMBAT_HOSTILE_DEATH")

SLASH_TANKMARK1 = "/tm"
SLASH_TANKMARK2 = "/tankmark"
SlashCmdList["TANKMARK"] = function(msg)
    TankMark:SlashHandler(msg)
end