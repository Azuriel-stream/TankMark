-- TankMark: v0.7-alpha (Dual-Layer Data)
-- File: TankMark.lua
-- Description: Core event handling, Dual-Layer Logic, and Nameplate Scanning.

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

-- ==========================================================
-- 1. UTILITIES (Nameplates & GUIDs) - NEW v0.7
-- ==========================================================

function TankMark:GetUnitGUID(unit)
    local exists, guid = UnitExists(unit)
    if exists and guid then return guid end
    return nil
end

-- NEW: Robust Nameplate Detector (Works with pfUI/Shagu/Stock)
function TankMark:IsNameplate(frame)
    if not frame or not frame.GetChildren or not frame:IsVisible() then return false end
    
    local children = {frame:GetChildren()}
    for _, child in ipairs(children) do
        -- Duck-Typing: Check for StatusBar methods
        if child.GetValue and child.GetMinMaxValues and child.SetMinMaxValues then
            return true
        end
    end
    return false
end

-- NEW: Find the visible nameplate with the lowest Health %
function TankMark:GetLowestHPUnit()
    local bestFrame = nil
    local lowestPct = 100
    
    local frames = {WorldFrame:GetChildren()}
    for _, f in ipairs(frames) do
        if TankMark:IsNameplate(f) then
            local children = {f:GetChildren()}
            for _, child in ipairs(children) do
                if child.GetValue and child.GetMinMaxValues then
                    local min, max = child:GetMinMaxValues()
                    local curr = child:GetValue()
                    
                    if max > 0 then
                        local pct = (curr / max) * 100
                        -- Logic: Ignore full HP mobs (not engaged) and dead mobs
                        if pct < 99 and pct > 0 and pct < lowestPct then
                            lowestPct = pct
                            bestFrame = f
                        end
                    end
                    break 
                end
            end
        end
    end
    return bestFrame
end

-- NEW: Clear specific unit marks
function TankMark:UnmarkUnit(unit)
    local currentIcon = GetRaidTargetIndex(unit)
    local guid = TankMark:GetUnitGUID(unit)
    
    SetRaidTarget(unit, 0)
    
    if currentIcon then
        TankMark.usedIcons[currentIcon] = nil
        TankMark.activeMobNames[currentIcon] = nil
    end
    if guid then TankMark.activeGUIDs[guid] = nil end
    if TankMark.UpdateHUD then TankMark:UpdateHUD() end
end

-- NEW: The Global Wipe
function TankMark:ClearAllMarks()
    TankMark.usedIcons = {}
    TankMark.sessionAssignments = {}
    TankMark.activeMobNames = {}
    TankMark.activeGUIDs = {}
    
    local function ClearUnit(unit)
        if UnitExists(unit) and GetRaidTargetIndex(unit) then
            SetRaidTarget(unit, 0)
        end
    end

    ClearUnit("target")
    ClearUnit("mouseover")
    
    if UnitInRaid("player") then
        for i = 1, 40 do ClearUnit("raid"..i); ClearUnit("raid"..i.."target") end
    else
        for i = 1, 4 do ClearUnit("party"..i); ClearUnit("party"..i.."target") end
    end
    
    TankMark:Print("Session reset and visible marks cleared.")
    if TankMark.UpdateHUD then TankMark:UpdateHUD() end
end

function TankMark:ResetSession()
    TankMark:ClearAllMarks()
end

-- ==========================================================
-- 2. CORE MARKING LOGIC (Refactored for v0.7)
-- ==========================================================

function TankMark:HandleMouseover()
    -- 0. SAFETY CHECKS
    if IsControlKeyDown() then
        if GetRaidTargetIndex("mouseover") then TankMark:UnmarkUnit("mouseover") end
        return 
    end

    if UnitIsDeadOrGhost("mouseover") then return end
    if UnitIsPlayer("mouseover") then return end
    if UnitIsFriend("player", "mouseover") then return end

    -- 1. CRITTER FILTER (New for v0.7)
    local cType = UnitCreatureType("mouseover")
    if cType == "Critter" or cType == "Non-combat Pet" then return end

    -- 2. ZONE FILTER (New for v0.7)
    local zone = GetRealZoneText()
    -- If we have NO data for this zone, we do nothing (Passive Mode)
    if not TankMarkDB.Zones[zone] and not TankMarkDB.StaticGUIDs[zone] then
        return 
    end

    local guid = TankMark:GetUnitGUID("mouseover")
    local currentIcon = GetRaidTargetIndex("mouseover")

    -- 3. ADOPTION
    if currentIcon then
        if not TankMark.usedIcons[currentIcon] or (guid and not TankMark.activeGUIDs[guid]) then
            TankMark.usedIcons[currentIcon] = true
            TankMark.activeMobNames[currentIcon] = UnitName("mouseover")
            if guid then TankMark.activeGUIDs[guid] = currentIcon end
            if TankMark.UpdateHUD then TankMark:UpdateHUD() end
        end
        return 
    end

    if guid and TankMark.activeGUIDs[guid] then return end

    -- 4. LAYER 1: STATIC OVERRIDES
    if guid and TankMarkDB.StaticGUIDs[zone] and TankMarkDB.StaticGUIDs[zone][guid] then
        local lockedIcon = TankMarkDB.StaticGUIDs[zone][guid]
        
        SetRaidTarget("mouseover", lockedIcon)
        TankMark:RegisterMarkUsage(lockedIcon, UnitName("mouseover"), guid)
        return
    end

    -- 5. LAYER 2: TEMPLATES
    local mobName = UnitName("mouseover")
    if not mobName then return end -- Nil safety
    
    local mobData = nil
    if TankMarkDB.Zones[zone] and TankMarkDB.Zones[zone][mobName] then
        mobData = TankMarkDB.Zones[zone][mobName]
    end

    if mobData then
        TankMark:ProcessKnownMob(mobData, guid)
    else
        TankMark:ProcessUnknownMob()
    end
end

function TankMark:RegisterMarkUsage(icon, name, guid)
    TankMark.usedIcons[icon] = true
    TankMark.activeMobNames[icon] = name
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
            -- CC Logic
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
        -- Kill Target Logic with SMART STEAL (v0.7)
        if not TankMark.usedIcons[mobData.mark] then
            iconToApply = mobData.mark
        elseif mobData.prio <= 2 then
            -- High Prio Steal: If mark is taken but this mob is Prio 1/2, take it.
            iconToApply = mobData.mark
        else
            iconToApply = TankMark:GetNextFreeKillIcon()
        end
    end

    if iconToApply then
        SetRaidTarget("mouseover", iconToApply)
        TankMark:RegisterMarkUsage(iconToApply, mobData.name, guid)
    end
end

function TankMark:ProcessUnknownMob()
    local iconToApply = TankMark:GetNextFreeKillIcon()
    if iconToApply then
        SetRaidTarget("mouseover", iconToApply)
        TankMark:RegisterMarkUsage(iconToApply, UnitName("mouseover"), TankMark:GetUnitGUID("mouseover"))
    end
end

function TankMark:GetFreeTankIcon()
    local zone = GetRealZoneText()
    for i = 1, 8 do
        if not TankMark.usedIcons[i] then
            local assignedName = nil
            if TankMarkDB.Profiles[zone] then
                assignedName = TankMarkDB.Profiles[zone][i]
            end
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
-- MODULE 3: THE WATCHDOG (Combat Monitor)
-- ==========================================================

function TankMark:HandleDeath(unitID)
    -- PART A: MOB DEATH
    if not UnitIsPlayer(unitID) then
        local icon = GetRaidTargetIndex(unitID)
        if icon and UnitHealth(unitID) <= 0 then
            TankMark.usedIcons[icon] = nil
            TankMark.activeMobNames[icon] = nil
            
            local guid = TankMark:GetUnitGUID(unitID)
            if guid then TankMark.activeGUIDs[guid] = nil end
            
            -- v0.7: Auto-Chain Logic (If Skull dies, free it immediately for next target)
            if (icon == 8 or icon == 7) and TankMark.IsActive then
                -- Logic is handled by simply freeing the icon. 
                -- The next mouseover will instantly grab the now-free Skull.
            end
            
            if TankMark.UpdateHUD then TankMark:UpdateHUD() end
        end
        return
    end

    -- PART B: PLAYER DEATH
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
        TankMark:ResetSession()
        
    elseif cmd == "announce" or cmd == "a" then
        if TankMark.AnnounceAssignments then TankMark:AnnounceAssignments() end

    elseif cmd == "zone" or cmd == "debug" then
        local currentZone = GetRealZoneText()
        TankMark:Print("Current Zone: " .. currentZone)
        
        -- DEBUG: Verbose Scan
        local frames = {WorldFrame:GetChildren()}
        local plateCount = 0
        local injuredCount = 0
        
        for _, f in ipairs(frames) do
            if TankMark:IsNameplate(f) then
                plateCount = plateCount + 1
                
                -- Check HP
                local children = {f:GetChildren()}
                for _, child in ipairs(children) do
                    if child.GetValue and child.GetMinMaxValues then
                        local min, max = child:GetMinMaxValues()
                        local curr = child:GetValue()
                        local pct = (max > 0) and ((curr/max)*100) or 0
                        
                        if pct < 99 then 
                            injuredCount = injuredCount + 1 
                        end
                        break
                    end
                end
            end
        end
        
        TankMark:Print("Debug Result:")
        TankMark:Print("- Total Visible Nameplates: " .. plateCount)
        TankMark:Print("- Injured Candidates (<99%): " .. injuredCount)
        
        if plateCount > 0 and injuredCount == 0 then
             TankMark:Print("(Scanner is working, but mobs are at Full Health)")
        end

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
-- EVENTS
-- ==========================================================

TankMark:SetScript("OnEvent", function()
    if (event == "ADDON_LOADED" and arg1 == "TankMark") then
        if TankMark.InitializeDB then TankMark:InitializeDB() end
    
    elseif (event == "PLAYER_LOGIN") then
        math.randomseed(time())
        if TankMark.UpdateRoster then TankMark:UpdateRoster() end
        TankMark:Print("TankMark v0.7-dev Loaded (Full Logic).")

    elseif (event == "UPDATE_MOUSEOVER_UNIT") then
        if TankMark.IsActive then TankMark:HandleMouseover() end

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