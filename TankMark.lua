-- TankMark: v0.1-dev
-- File: TankMark.lua
-- Description: Core event handling and logic engine.

-- Ensure the main frame is accessible
if not TankMark then
    TankMark = CreateFrame("Frame", "TankMarkFrame")
end

-- ==========================================================
-- LOGIC ENGINE & MARKING SYSTEM (Module 2)
-- ==========================================================

-- Runtime state for "Used Icons"
TankMark.usedIcons = {}
TankMark.activeMobNames = {}

function TankMark:ResetSession()
    TankMark.usedIcons = {}
    TankMark.sessionAssignments = {}
    TankMark.activeMobNames = {} -- (Keep this here too to clear it on reset)
    
    TankMark:Print("Targeting session reset. Ready for new pack.")
    
    if TankMark.UpdateHUD then TankMark:UpdateHUD() end
end

function TankMark:HandleMouseover()
    -- 1. Validation Filters
    if UnitIsDeadOrGhost("mouseover") then return end
    if UnitIsPlayer("mouseover") then return end
    if UnitIsFriend("player", "mouseover") then return end
    
    -- DEBUG: Print exactly what the addon sees
    -- local mobName = UnitName("mouseover")
    -- local zone = GetRealZoneText()
    
    -- Only print if we actually have a name (avoids spam on empty space)
    -- if mobName then
    --     TankMark:Print("DEBUG: Mouseover detected on '" .. mobName .. "' in zone '" .. zone .. "'")
    -- end

    if GetRaidTargetIndex("mouseover") then return end

    -- 2. Identification
    local zone = GetRealZoneText()
    local mobName = UnitName("mouseover")
    local mobData = nil

    -- 3. Database Lookup
    if TankMarkDB.Zones[zone] and TankMarkDB.Zones[zone][mobName] then
        mobData = TankMarkDB.Zones[zone][mobName]
    end

    -- 4. Decision Making
    if mobData then
        TankMark:ProcessKnownMob(mobData)
    else
        TankMark:ProcessUnknownMob()
    end
end

function TankMark:ProcessKnownMob(mobData)
    local iconToApply = nil
    
    if mobData.type == "CC" then
        local assignedPlayer = TankMark:GetFirstAvailableBackup(mobData.class)
        
        if assignedPlayer then
            if not TankMark.usedIcons[mobData.mark] then
                iconToApply = mobData.mark
                TankMark:AssignCC(iconToApply, assignedPlayer, mobData.type)
            end
        else
            -- Fallback
            iconToApply = TankMark:GetNextFreeKillIcon()
        end
    else
        -- Kill Target
        if not TankMark.usedIcons[mobData.mark] then
            iconToApply = mobData.mark
        else
            iconToApply = TankMark:GetNextFreeKillIcon()
        end
    end

    if iconToApply then
        SetRaidTarget("mouseover", iconToApply)
        TankMark.usedIcons[iconToApply] = true

        -- NEW: Save Name & Update HUD
        TankMark.activeMobNames[iconToApply] = UnitName("mouseover")
        if TankMark.UpdateHUD then TankMark:UpdateHUD() end
    end
end

function TankMark:ProcessUnknownMob()
    local iconToApply = nil
    if UnitPowerType("mouseover") == 0 then -- Mana
        iconToApply = TankMark:GetNextFreeKillIcon()
    end
    if iconToApply then
        SetRaidTarget("mouseover", iconToApply)
        TankMark.usedIcons[iconToApply] = true

        -- NEW: Save Name & Update HUD
        TankMark.activeMobNames[iconToApply] = UnitName("mouseover")
        if TankMark.UpdateHUD then TankMark:UpdateHUD() end
    end
end

function TankMark:GetNextFreeKillIcon()
    local killPriority = {8, 7, 2, 1}
    for _, iconID in ipairs(killPriority) do
        if not TankMark.usedIcons[iconID] then
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
-- MODULE 3: THE WATCHDOG (Combat Monitor)
-- ==========================================================

function TankMark:HandleDeath(unitID)
    -- 1. Filter: We only care about players who actually died
    if not UnitIsPlayer(unitID) then return end
    if UnitHealth(unitID) > 0 then return end -- They are still alive

    local deadPlayerName = UnitName(unitID)
    if not deadPlayerName then return end

    -- 2. Check: Did this player have an active assignment?
    local assignedIcon = nil
    for icon, assignedTo in pairs(TankMark.sessionAssignments) do
        if assignedTo == deadPlayerName then
            assignedIcon = icon
            break
        end
    end

    -- If they had no job, we don't care.
    if not assignedIcon then return end

    -- 3. Validation: Is the mob they were handling actually still alive?
    -- We use the blind scanner to check raid targets.
    if TankMark:IsMarkAlive(assignedIcon) then
        
        -- 4. Reassignment: Find a backup
        -- We need to know what CLASS is required. 
        -- Since we don't store the class in the assignment table yet, 
        -- we will try to find a player of the SAME CLASS as the one who died.
        local _, classEng = UnitClass(unitID)
        local backupPlayer = TankMark:GetFirstAvailableBackup(classEng)

        if backupPlayer then
            -- Update the session memory
            TankMark.sessionAssignments[assignedIcon] = backupPlayer
            
            -- 5. Notification: Whisper the backup
            -- Using "RAID_WARNING" style urgency in a private whisper
            local iconString = "{rt"..assignedIcon.."}"
            local msg = "ALERT: " .. deadPlayerName .. " died! You are now assigned to " .. iconString .. "."
            
            SendChatMessage(msg, "WHISPER", nil, backupPlayer)
            
            -- Optional: Announce to leader locally
            TankMark:Print("Reassigned " .. iconString .. " to " .. backupPlayer)
        else
            -- No backups found! Warn the leader.
            TankMark:Print("|cffff0000CRITICAL:|r " .. deadPlayerName .. " died. No backups found for " .. "{rt"..assignedIcon.."}!")
        end
    end
end

-- ==========================================================
-- SLASH COMMANDS
-- ==========================================================

function TankMark:SlashHandler(msg)
    -- 1. Split the command from the arguments
    local cmd, args = string.match(msg, "^(%S*)%s*(.*)$");
    cmd = string.lower(cmd or "")
    
    -- Helper Map: Allows user to type "moon" instead of "5"
    local iconNames = {
        ["skull"] = 8, ["cross"] = 7, ["square"] = 6, ["moon"] = 5,
        ["triangle"] = 4, ["diamond"] = 3, ["circle"] = 2, ["star"] = 1
    }

    -- 2. Command Routing
    if cmd == "reset" or cmd == "r" then
        TankMark:ResetSession()
        
    elseif cmd == "announce" or cmd == "a" then
        TankMark:AnnounceAssignments()

    elseif cmd == "zone" or cmd == "debug" then
        local currentZone = GetRealZoneText()
        TankMark:Print("Current Zone ID: " .. currentZone)

    -- NEW: The Assign Command
    elseif cmd == "assign" then
        -- Parse arguments: Expecting "[mark] [player]"
        local markStr, targetPlayer = string.match(args, "^(%S+)%s+(%S+)$")
        
        if markStr and targetPlayer then
            markStr = string.lower(markStr)
            
            -- Convert input to a number (handles "5" or "moon")
            local iconID = tonumber(markStr) or iconNames[markStr]
            
            if iconID and iconID >= 1 and iconID <= 8 then
                -- EXECUTE ASSIGNMENT
                TankMark.sessionAssignments[iconID] = targetPlayer
                -- Mark this icon as 'used' so we don't auto-assign it to a random mob immediately
                TankMark.usedIcons[iconID] = true 
                
                TankMark:Print("Manually assigned {rt"..iconID.."} to " .. targetPlayer)

                if TankMark.UpdateHUD then TankMark:UpdateHUD() end
            else
                TankMark:Print("Invalid mark. Use numbers (1-8) or names (skull, moon, etc).")
            end
        else
            TankMark:Print("Usage: /tm assign [mark] [player]")
        end

    elseif cmd == "config" or cmd == "c" then
        if TankMark.ShowOptions then
            TankMark:ShowOptions()
        else
            TankMark:Print("Options module not loaded.")
        end

    elseif cmd == "sync" or cmd == "share" then
        if TankMark.BroadcastZone then
            TankMark:BroadcastZone()
        else
            TankMark:Print("Sync module not loaded.")
        end

    else
        TankMark:Print("Commands: /tm reset, /tm announce, /tm assign [mark] [player]")
    end
end

function TankMark:AnnounceAssignments()
    -- 1. Auto-detect the correct channel
    local channel = "SAY" -- Default to SAY for solo testing
    
    if GetNumRaidMembers() > 0 then
        channel = "RAID"
    elseif GetNumPartyMembers() > 0 then
        channel = "PARTY"
    end

    -- 2. Send the header
    SendChatMessage("TankMark Assignments:", channel)
    
    -- 3. Send the assignments
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
-- EVENT HANDLER (The Traffic Controller)
-- ==========================================================
TankMark:SetScript("OnEvent", function()
    if (event == "ADDON_LOADED" and arg1 == "TankMark") then
        if TankMark.InitializeDB then TankMark:InitializeDB() end
    
    elseif (event == "PLAYER_LOGIN") then
        if TankMark.UpdateRoster then TankMark:UpdateRoster() end
        TankMark:Print("Loaded. Type /tm reset to start a pack.")

    elseif (event == "UPDATE_MOUSEOVER_UNIT") then
        TankMark:HandleMouseover()

    elseif (event == "UNIT_HEALTH") then
        TankMark:HandleDeath(arg1)
    
    elseif (event == "CHAT_MSG_ADDON") then
        -- arg1=prefix, arg2=message, arg3=channel, arg4=sender
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