-- TankMark: v0.6-dev
-- File: TankMark.lua
-- Description: Core event handling, Dual-Layer Logic, and Dynamic Tanking.

if not TankMark then
    TankMark = CreateFrame("Frame", "TankMarkFrame")
end

-- ==========================================================
-- LOGIC ENGINE & MARKING SYSTEM
-- ==========================================================

-- Runtime state
TankMark.usedIcons = {}
TankMark.activeMobNames = {}
TankMark.activeGUIDs = {}
TankMark.sessionAssignments = {}
TankMark.IsActive = true

-- HELPER: Extract GUID from custom API
function TankMark:GetUnitGUID(unit)
    local exists, guid = UnitExists(unit)
    if exists and guid then
        return guid
    end
    return nil
end

-- NEW: Unmark a specific target (Ctrl + Mouseover action)
function TankMark:UnmarkUnit(unit)
    local currentIcon = GetRaidTargetIndex(unit)
    local guid = TankMark:GetUnitGUID(unit)
    
    -- 1. Clear Visuals
    SetRaidTarget(unit, 0)
    
    -- 2. Clear Internal Data
    if currentIcon then
        TankMark.usedIcons[currentIcon] = nil
        TankMark.activeMobNames[currentIcon] = nil
    end
    
    if guid then
        TankMark.activeGUIDs[guid] = nil
    end
    
    if TankMark.UpdateHUD then TankMark:UpdateHUD() end
end

-- NEW: The Global Wipe (Reset All)
function TankMark:ClearAllMarks()
    -- 1. Clear Internal Memory
    TankMark.usedIcons = {}
    TankMark.sessionAssignments = {}
    TankMark.activeMobNames = {}
    TankMark.activeGUIDs = {}
    
    -- 2. Clear Visuals (Best Effort Scan)
    local function ClearUnit(unit)
        if UnitExists(unit) and GetRaidTargetIndex(unit) then
            SetRaidTarget(unit, 0)
        end
    end

    ClearUnit("target")
    ClearUnit("mouseover")
    
    if UnitInRaid("player") then
        for i = 1, 40 do 
            ClearUnit("raid"..i)
            ClearUnit("raid"..i.."target")
        end
    else
        for i = 1, 4 do 
            ClearUnit("party"..i)
            ClearUnit("party"..i.."target")
        end
    end
    
    TankMark:Print("Session reset and visible marks cleared.")
    if TankMark.UpdateHUD then TankMark:UpdateHUD() end
end

-- Alias for backward compatibility
function TankMark:ResetSession()
    TankMark:ClearAllMarks()
end

function TankMark:HandleMouseover()
    -- 0. MODIFIER CHECK: UNMARK
    if IsControlKeyDown() then
        if GetRaidTargetIndex("mouseover") then
            TankMark:UnmarkUnit("mouseover")
        end
        return -- Stop processing
    end

    -- 1. Validation Filters
    if UnitIsDeadOrGhost("mouseover") then return end
    if UnitIsPlayer("mouseover") then return end
    if UnitIsFriend("player", "mouseover") then return end

    local guid = TankMark:GetUnitGUID("mouseover")
    local currentIcon = GetRaidTargetIndex("mouseover")
    local zone = GetRealZoneText()

    -- 2. ADOPTION (Sync with Server Reality)
    if currentIcon then
        if not TankMark.usedIcons[currentIcon] or (guid and not TankMark.activeGUIDs[guid]) then
            TankMark.usedIcons[currentIcon] = true
            TankMark.activeMobNames[currentIcon] = UnitName("mouseover")
            if guid then TankMark.activeGUIDs[guid] = currentIcon end
            if TankMark.UpdateHUD then TankMark:UpdateHUD() end
        end
        return 
    end

    -- 3. PRECISION LOCK (Don't double mark the same entity)
    if guid and TankMark.activeGUIDs[guid] then return end

    -- 4. LAYER 1 CHECK: STATIC OVERRIDES (The "Lock")
    if guid and TankMarkDB.StaticGUIDs[zone] and TankMarkDB.StaticGUIDs[zone][guid] then
        local lockedIcon = TankMarkDB.StaticGUIDs[zone][guid]
        
        -- Force Apply (Overrides usage checks because it's a Lock)
        SetRaidTarget("mouseover", lockedIcon)
        TankMark.usedIcons[lockedIcon] = true
        TankMark.activeMobNames[lockedIcon] = UnitName("mouseover")
        TankMark.activeGUIDs[guid] = lockedIcon
        
        -- Auto-Assign Player if needed
        if not TankMark.sessionAssignments[lockedIcon] then
            local assignee = TankMark:GetAssigneeForMark(lockedIcon)
            if assignee then TankMark.sessionAssignments[lockedIcon] = assignee end
        end
        
        if TankMark.UpdateHUD then TankMark:UpdateHUD() end
        return -- Skip Layer 2
    end

    -- 5. LAYER 2 CHECK: TEMPLATES (Name + Prio)
    local mobName = UnitName("mouseover")
    local mobData = nil
    if TankMarkDB.Zones[zone] and TankMarkDB.Zones[zone][mobName] then
        mobData = TankMarkDB.Zones[zone][mobName]
    end

    if mobData then
        TankMark:ProcessKnownMob(mobData)
    else
        TankMark:ProcessUnknownMob()
    end
end

function TankMark:ProcessKnownMob(mobData)
    local iconToApply = nil
    
    if mobData.type == "CC" then
        -- DYNAMIC TANK LOGIC
        local freeTankIcon = TankMark:GetFreeTankIcon()
        
        if freeTankIcon then
            -- Override! Treat as Kill Target for the free tank.
            iconToApply = freeTankIcon
        else
            -- No free tanks, proceed with CC
            local assignedPlayer = TankMark:GetFirstAvailableBackup(mobData.class)
            if assignedPlayer then
                if not TankMark.usedIcons[mobData.mark] then
                    iconToApply = mobData.mark
                    TankMark:AssignCC(iconToApply, assignedPlayer, mobData.type)
                end
            else
                -- No CC player available either? Just mark it for death.
                iconToApply = TankMark:GetNextFreeKillIcon()
            end
        end
    else
        -- Kill Target Logic
        if not TankMark.usedIcons[mobData.mark] then
            iconToApply = mobData.mark
        else
            iconToApply = TankMark:GetNextFreeKillIcon()
        end
    end

    if iconToApply then
        TankMark:ApplyMark(iconToApply)
    end
end

function TankMark:ProcessUnknownMob()
    -- CHANGED: Now attempts to mark ALL hostile mobs, not just Mana users.
    local iconToApply = TankMark:GetNextFreeKillIcon()
    
    if iconToApply then
        TankMark:ApplyMark(iconToApply)
    end
end

-- Shared Application Logic
function TankMark:ApplyMark(icon)
    SetRaidTarget("mouseover", icon)
    TankMark.usedIcons[icon] = true
    TankMark.activeMobNames[icon] = UnitName("mouseover")
    
    local guid = TankMark:GetUnitGUID("mouseover")
    if guid then TankMark.activeGUIDs[guid] = icon end
    
    if not TankMark.sessionAssignments[icon] then
        local assignee = TankMark:GetAssigneeForMark(icon)
        if assignee then TankMark.sessionAssignments[icon] = assignee end
    end
    
    if TankMark.UpdateHUD then TankMark:UpdateHUD() end
end

-- FIXED: Dynamic Tank Finder now checks DB Profiles (Permanent) vs Used Icons (Session)
function TankMark:GetFreeTankIcon()
    local zone = GetRealZoneText()
    
    for i = 1, 8 do
        -- 1. Check if this icon is "Used" in the live fight
        if not TankMark.usedIcons[i] then
            
            -- 2. Check if the DB Profile has a player assigned (Static Assignment)
            local assignedName = nil
            if TankMarkDB.Profiles[zone] then
                assignedName = TankMarkDB.Profiles[zone][i]
            end
            
            -- 3. If a player is assigned in the profile, we consider them a "Tank" 
            -- (or at least a permanent assignee) who is currently free.
            if assignedName and assignedName ~= "" then
                return i
            end
        end
    end
    return nil
end

function TankMark:GetNextFreeKillIcon()
    -- local killPriority = {8, 7, 2, 1, 3, 4} -- Expanded list
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
-- MODULE 3: THE WATCHDOG (Combat Monitor)
-- ==========================================================

function TankMark:HandleDeath(unitID)
    -- PART A: MOB DEATH (Recycling Logic)
    if not UnitIsPlayer(unitID) then
        local icon = GetRaidTargetIndex(unitID)
        if icon and UnitHealth(unitID) <= 0 then
            -- Free the Icon
            TankMark.usedIcons[icon] = nil
            TankMark.activeMobNames[icon] = nil
            
            -- Clear the GUID Lock
            local guid = TankMark:GetUnitGUID(unitID)
            if guid then TankMark.activeGUIDs[guid] = nil end
            
            if TankMark.UpdateHUD then TankMark:UpdateHUD() end
        end
        return
    end

    -- PART B: PLAYER DEATH (Reassignment Logic)
    if UnitHealth(unitID) > 0 then return end 

    local deadPlayerName = UnitName(unitID)
    if not deadPlayerName then return end

    local assignedIcon = nil
    for icon, assignedTo in pairs(TankMark.sessionAssignments) do
        if assignedTo == deadPlayerName then
            assignedIcon = icon
            break
        end
    end

    if not assignedIcon then return end

    if TankMark:IsMarkAlive(assignedIcon) then
        local _, classEng = UnitClass(unitID)
        local backupPlayer = TankMark:GetFirstAvailableBackup(classEng)

        if backupPlayer then
            TankMark.sessionAssignments[assignedIcon] = backupPlayer
            local iconString = "{rt"..assignedIcon.."}"
            local msg = "ALERT: " .. deadPlayerName .. " died! You are now assigned to " .. iconString .. "."
            SendChatMessage(msg, "WHISPER", nil, backupPlayer)
            TankMark:Print("Reassigned " .. iconString .. " to " .. backupPlayer)
        else
            TankMark:Print("|cffff0000CRITICAL:|r " .. deadPlayerName .. " died. No backups found for " .. "{rt"..assignedIcon.."}!")
        end
    end
end

-- ==========================================================
-- SLASH COMMANDS
-- ==========================================================

function TankMark:SlashHandler(msg)
    local cmd, args = string.match(msg, "^(%S*)%s*(.*)$");
    cmd = string.lower(cmd or "")
    
    local iconNames = {
        ["skull"] = 8, ["cross"] = 7, ["square"] = 6, ["moon"] = 5,
        ["triangle"] = 4, ["diamond"] = 3, ["circle"] = 2, ["star"] = 1
    }

    if cmd == "reset" or cmd == "r" then
        TankMark:ResetSession() -- Now calls ClearAllMarks
        
    elseif cmd == "announce" or cmd == "a" then
        if TankMark.AnnounceAssignments then TankMark:AnnounceAssignments() end

    elseif cmd == "zone" or cmd == "debug" then
        local currentZone = GetRealZoneText()
        TankMark:Print("Current Zone ID: " .. currentZone)

    elseif cmd == "assign" then
        local markStr, targetPlayer = string.match(args, "^(%S+)%s+(%S+)$")
        if markStr and targetPlayer then
            markStr = string.lower(markStr)
            local iconID = tonumber(markStr) or iconNames[markStr]
            if iconID and iconID >= 1 and iconID <= 8 then
                TankMark.sessionAssignments[iconID] = targetPlayer
                TankMark.usedIcons[iconID] = true 
                TankMark:Print("Manually assigned {rt"..iconID.."} to " .. targetPlayer)
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
             local iconString = "{rt"..i.."}"
             local msg = iconString .. " assigned to " .. player
             SendChatMessage(msg, channel)
        end
    end
end

-- ==========================================================
-- MODULE 4: AUTO-ASSIGNMENT LOGIC
-- ==========================================================

function TankMark:GetAssigneeForMark(markID)
    local zone = GetRealZoneText()
    
    -- 1. CHECK PROFILE ASSIGNMENT
    if TankMarkDB.Profiles[zone] and TankMarkDB.Profiles[zone][markID] then
        local assignedName = TankMarkDB.Profiles[zone][markID]
        if UnitInRaid("player") then
            for i = 1, GetNumRaidMembers() do
                if UnitName("raid"..i) == assignedName then return assignedName end
            end
        else
            if UnitName("player") == assignedName then return assignedName end
            for i = 1, GetNumPartyMembers() do
                if UnitName("party"..i) == assignedName then return assignedName end
            end
        end
    end
    
    -- 2. FALLBACK
    local requiredClass = TankMark.MarkClassDefaults[markID]
    if not requiredClass then return nil end 
    
    local candidates = {}
    
    local function IsPlayerBusy(name)
        for otherMark, assignee in pairs(TankMark.sessionAssignments) do
            if assignee == name and otherMark ~= markID then return true end
        end
        return false
    end
    
    local function CheckUnit(unit)
        local _, class = UnitClass(unit)
        if class == requiredClass and not UnitIsDeadOrGhost(unit) then
            local name = UnitName(unit)
            if name and not IsPlayerBusy(name) then 
                table.insert(candidates, name) 
            end
        end
    end

    if UnitInRaid("player") then
        for i = 1, GetNumRaidMembers() do CheckUnit("raid"..i) end
    else
        local _, pClass = UnitClass("player")
        if pClass == requiredClass then 
            local name = UnitName("player")
            if name and not IsPlayerBusy(name) then table.insert(candidates, name) end
        end
        for i = 1, GetNumPartyMembers() do CheckUnit("party"..i) end
    end
    
    if table.getn(candidates) > 0 then
        return candidates[math.random(table.getn(candidates))]
    end
    
    return nil
end

-- ==========================================================
-- MODULE 5: EVENTS
-- ==========================================================

TankMark.MarkNames = {
    [8] = "SKULL", [7] = "CROSS", [6] = "SQUARE", [5] = "MOON",
    [4] = "TRIANGLE", [3] = "DIAMOND", [2] = "CIRCLE", [1] = "STAR"
}

TankMark.MarkColors = {
    [8] = "|cffffffff", [7] = "|cffff0000", [6] = "|cff00ccff", [5] = "|cffaabbcc",
    [4] = "|cff00ff00", [3] = "|cffff00ff", [2] = "|cffffaa00", [1] = "|cffffff00"
}

TankMark:SetScript("OnEvent", function()
    if (event == "ADDON_LOADED" and arg1 == "TankMark") then
        if TankMark.InitializeDB then TankMark:InitializeDB() end
    
    elseif (event == "PLAYER_LOGIN") then
        if TankMark.UpdateRoster then TankMark:UpdateRoster() end
        TankMark:Print("Loaded. Hold Ctrl+Mouseover to unmark.")

    elseif (event == "UPDATE_MOUSEOVER_UNIT") then
        if not TankMark.IsActive then return end
        TankMark:HandleMouseover()

    elseif (event == "UNIT_HEALTH") then
        TankMark:HandleDeath(arg1)
    
    elseif (event == "CHAT_MSG_ADDON") then
        if TankMark.HandleSync then
            TankMark:HandleSync(arg1, arg2, arg4)
        end
    end
end)

-- Register Slash Commands
SLASH_TANKMARK1 = "/tm"
SLASH_TANKMARK2 = "/tankmark"
SlashCmdList["TANKMARK"] = function(msg)
    TankMark:SlashHandler(msg)
end