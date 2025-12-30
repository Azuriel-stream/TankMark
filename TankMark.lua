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
        TankMark.activeMobNames[iconToApply] = UnitName("mouseover")
        
        -- v0.4: AUTO-ASSIGN PLAYER
        -- Only assign if we haven't manually assigned this icon this session
        if not TankMark.sessionAssignments[iconToApply] then
            local assignee = TankMark:GetAssigneeForMark(iconToApply)
            if assignee then
                TankMark.sessionAssignments[iconToApply] = assignee
                -- Optional: Announce to chat? (Maybe too spammy, stick to HUD for now)
            end
        end
        
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
        TankMark.activeMobNames[iconToApply] = UnitName("mouseover")
        
        -- v0.4: AUTO-ASSIGN PLAYER
        -- Only assign if we haven't manually assigned this icon this session
        if not TankMark.sessionAssignments[iconToApply] then
            local assignee = TankMark:GetAssigneeForMark(iconToApply)
            if assignee then
                TankMark.sessionAssignments[iconToApply] = assignee
                -- Optional: Announce to chat? (Maybe too spammy, stick to HUD for now)
            end
        end
        
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
        if TankMark.AnnounceAssignments then
            TankMark:AnnounceAssignments()
        end

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
-- MODULE 4: AUTO-ASSIGNMENT LOGIC
-- ==========================================================

function TankMark:GetAssigneeForMark(markID)
    local zone = GetRealZoneText()
    
    -- 1. CHECK PROFILE ASSIGNMENT (Priority)
    -- If a player is explicitly named in the profile, they get the job 
    -- even if they are already assigned elsewhere (Manual Override).
    if TankMarkDB.Profiles[zone] and TankMarkDB.Profiles[zone][markID] then
        local assignedName = TankMarkDB.Profiles[zone][markID]
        
        -- Validate Player Presence
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
    
    -- 2. FALLBACK: RANDOM CLASS PICK (With "Busy" Check)
    local requiredClass = TankMark.MarkClassDefaults[markID]
    if not requiredClass then return nil end 
    
    local candidates = {}
    
    -- Helper function to check if player is already working
    local function IsPlayerBusy(name)
        for otherMark, assignee in pairs(TankMark.sessionAssignments) do
            -- If this player is assigned to another mark (not the current one), they are busy
            if assignee == name and otherMark ~= markID then
                return true
            end
        end
        return false
    end
    
    -- Build Candidate List
    if UnitInRaid("player") then
        for i = 1, GetNumRaidMembers() do
            local name = UnitName("raid"..i)
            local _, class = UnitClass("raid"..i)
            
            -- Must be correct class, alive, AND NOT BUSY
            if class == requiredClass and not UnitIsDeadOrGhost("raid"..i) then
                if name and not IsPlayerBusy(name) then 
                    table.insert(candidates, name) 
                end
            end
        end
    else
        -- Check Player
        local _, pClass = UnitClass("player")
        if pClass == requiredClass then 
            local name = UnitName("player")
            if name and not IsPlayerBusy(name) then 
                table.insert(candidates, name) 
            end
        end
        -- Check Party
        for i = 1, GetNumPartyMembers() do
            local _, class = UnitClass("party"..i)
            if class == requiredClass and not UnitIsDeadOrGhost("party"..i) then
                local name = UnitName("party"..i)
                if name and not IsPlayerBusy(name) then 
                    table.insert(candidates, name) 
                end
            end
        end
    end
    
    -- Pick a random candidate from the "Available" pool
    if table.getn(candidates) > 0 then
        return candidates[math.random(table.getn(candidates))]
    end
    
    return nil -- No free players found
end

-- ==========================================================
-- MODULE 5: ANNOUNCEMENTS
-- ==========================================================

TankMark.MarkNames = {
    [8] = "SKULL",
    [7] = "CROSS",
    [6] = "SQUARE",
    [5] = "MOON",
    [4] = "TRIANGLE",
    [3] = "DIAMOND",
    [2] = "CIRCLE",
    [1] = "STAR"
}

-- Standard Raid Target Colors (Approximate)
TankMark.MarkColors = {
    [8] = "|cffffffff", -- Skull: White
    [7] = "|cffff0000", -- Cross: Red
    [6] = "|cff00ccff", -- Square: Blue
    [5] = "|cffaabbcc", -- Moon: Silver/Grey-ish
    [4] = "|cff00ff00", -- Triangle: Green
    [3] = "|cffff00ff", -- Diamond: Purple
    [2] = "|cffffaa00", -- Circle: Orange
    [1] = "|cffffff00"  -- Star: Yellow
}

function TankMark:AnnounceAssignments()
    -- 1. Determine Channel
    local channel = "PARTY"
    if UnitInRaid("player") then
        if IsRaidLeader() or IsRaidOfficer() then
            channel = "RAID_WARNING"
        else
            channel = "RAID"
        end
    elseif GetNumPartyMembers() > 0 then
        channel = "PARTY"
    else
        channel = "SAY" 
    end

    -- 2. Scan and Broadcast
    local hasAnnounced = false
    
    for i = 8, 1, -1 do
        local markName = TankMark.MarkNames[i]
        local color = TankMark.MarkColors[i]
        local player = TankMark.sessionAssignments[i]
        local mob = TankMark.activeMobNames[i]
        
        -- Combine Color + Name + Reset Code (|r)
        local coloredMark = color .. markName .. "|r"
        
        if player then
            -- Format: "Xaryu is on [Colored Mark]"
            SendChatMessage(player .. " is on " .. coloredMark, channel)
            hasAnnounced = true
        elseif mob then
            -- Format: "Target [Colored Mark] (Mob Name)"
            SendChatMessage("Target " .. coloredMark .. " (" .. mob .. ")", channel)
            hasAnnounced = true
        end
    end
    
    if not hasAnnounced then
        TankMark:Print("No active assignments to announce.")
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