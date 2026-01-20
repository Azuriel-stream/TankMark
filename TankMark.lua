-- TankMark: v0.21-dev
-- File: TankMark.lua
-- Entry point, Event Handlers, and Slash Commands

if not TankMark then
    TankMark = CreateFrame("Frame", "TankMarkFrame")
end

-- ==========================================================
-- LOCALIZATIONS
-- ==========================================================
local _strfind = string.find
local _lower = string.lower
local _pairs = pairs
local _ipairs = ipairs
local _getn = table.getn

-- ==========================================================
-- ZONE CACHING
-- ==========================================================
TankMark.currentZone = nil

function TankMark:GetCachedZone()
    if not TankMark.currentZone then
        TankMark.currentZone = GetRealZoneText()
    end
    return TankMark.currentZone
end

-- ==========================================================
-- [v0.21] BATCH PROCESSING STATE
-- ==========================================================
TankMark.batchCandidates = {}
TankMark.isShiftHeld = false

-- ==========================================================
-- EVENT HANDLER
-- ==========================================================
function TankMark:HandleMouseover()
    if not _UnitExists("mouseover") then return end
    
    -- [v0.21] PRIORITY 1: Ctrl to unmark (always available)
    if IsControlKeyDown() then
        if _GetRaidTargetIndex("mouseover") then
            TankMark:UnmarkUnit("mouseover")
        end
        return
    end
    
    -- [v0.21] PRIORITY 2: Batch Processing (Shift key check BEFORE permission check)
    if IsShiftKeyDown() then
        -- Only available with SuperWoW
        if not TankMark.IsSuperWoW then
            TankMark:Print("|cffff0000Batch marking requires SuperWoW.|r")
            return
        end
        
        local guid = TankMark:Driver_GetGUID("mouseover")
        if guid then
            -- [v0.21] Initialize batch on first Shift+mouseover
            if not TankMark.batchPollingActive then
                TankMark.batchSequence = 0
                TankMark.batchCandidates = {}
            end
            
            TankMark:AddBatchCandidate(guid)
            
            -- [v0.21] Start polling for Shift release (Vanilla 1.12 workaround)
            if not TankMark.batchPollingActive then
                TankMark.batchPollingActive = true
                TankMark:StartBatchShiftPoller()
            end
        end
        return
    end
    
    -- [v0.21] PRIORITY 3: Flight Recorder (bypass permission check)
    if TankMark.IsRecorderActive then
        local guid = TankMark:Driver_GetGUID("mouseover")
        if guid then
            TankMark:RecordUnit(guid)
        end
        return
    end
    
    -- [v0.21] PRIORITY 4: Permission check for auto-marking
    if not TankMark:CanAutomate() then return end
    
    -- [v0.21] SuperWoW: Let Scanner handle marking (skip mouseover PASSIVE mode)
    if TankMark.IsSuperWoW then
        return
    end
    
    local guid = TankMark:Driver_GetGUID("mouseover")
    if guid then
        TankMark:ProcessUnit(guid, "PASSIVE")
    end
end

-- ==========================================================
-- [v0.21] BATCH SHIFT POLLING (Vanilla 1.12 Workaround)
-- ==========================================================
TankMark.batchPollingActive = false

function TankMark:StartBatchShiftPoller()
    if not TankMark.batchPollerFrame then
        TankMark.batchPollerFrame = CreateFrame("Frame")
    end
    
    TankMark.batchPollerFrame:SetScript("OnUpdate", function()
        -- Poll every frame to detect Shift release
        if not IsShiftKeyDown() then
            -- Shift released
            TankMark.batchPollingActive = false
            TankMark.batchPollerFrame:SetScript("OnUpdate", nil)
            
            if TankMark.ExecuteBatchMarking then
                TankMark:ExecuteBatchMarking()
            end
        end
    end)
end


TankMark:SetScript("OnEvent", function()
    if (event == "ADDON_LOADED" and arg1 == "TankMark") then
        if TankMark.InitializeDB then TankMark:InitializeDB() end
        
    elseif (event == "PLAYER_LOGIN") then
        math.randomseed(time())
        
        -- Initialize zone cache
        TankMark.currentZone = GetRealZoneText()
        
        -- [v0.21] Load zone data (merge defaults + user DB)
        if TankMark.LoadZoneData then
            TankMark:LoadZoneData(TankMark.currentZone)
        end
        
        if TankMark.UpdateRoster then TankMark:UpdateRoster() end
        
        -- Calls to Logic Engine
        TankMark:InitCombatLogParser()
        
        -- Calls to Scanner Module
        TankMark:InitDriver()
        TankMark:ScanForRangeSpell()
        
        TankMark:Print("TankMark v0.21-dev loaded.")
        
    elseif (event == "ZONE_CHANGED_NEW_AREA") then
        local oldZone = TankMark.currentZone
        TankMark.currentZone = GetRealZoneText()
        
        -- [v0.21] Load zone data for new zone
        if TankMark.LoadZoneData then
            TankMark:LoadZoneData(TankMark.currentZone)
        end
        
        -- Disable Flight Recorder on zone change (safety)
        if TankMark.IsRecorderActive then
            TankMark.IsRecorderActive = false
            TankMark:Print("|cffffaa00Flight Recorder:|r Auto-disabled (zone changed from '" .. (oldZone or "Unknown") .. "' to '" .. TankMark.currentZone .. "')")
            TankMark:Print("Use '/tmark recorder start' to re-enable for new zone.")
        end
        
    elseif (event == "UPDATE_MOUSEOVER_UNIT") then
        TankMark:HandleMouseover()
        
    elseif (event == "UNIT_HEALTH") then
        TankMark:HandleDeath(arg1)
        
    elseif (event == "RAID_ROSTER_UPDATE" or event == "PARTY_MEMBERS_CHANGED") then
        -- Update HUD colors when roster changes
        if TankMark.UpdateHUD then
            TankMark:UpdateHUD()
        end
        
        -- Update Profile tab colors if visible
        if TankMark.UpdateProfileList and TankMark.optionsFrame and TankMark.optionsFrame:IsVisible() then
            TankMark:UpdateProfileList()
        end
        
    elseif (event == "CHAT_MSG_COMBAT_HOSTILE_DEATH") then
        TankMark:HandleCombatLog(arg1)
        
    elseif (event == "CHAT_MSG_ADDON") then
        if TankMark.HandleSync then TankMark:HandleSync(arg1, arg2, arg4) end
    end
end)

TankMark:RegisterEvent("ADDON_LOADED")
TankMark:RegisterEvent("PLAYER_LOGIN")
TankMark:RegisterEvent("ZONE_CHANGED_NEW_AREA")
TankMark:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
TankMark:RegisterEvent("UNIT_HEALTH")
TankMark:RegisterEvent("CHAT_MSG_COMBAT_HOSTILE_DEATH")
TankMark:RegisterEvent("CHAT_MSG_ADDON")
TankMark:RegisterEvent("RAID_ROSTER_UPDATE")
TankMark:RegisterEvent("PARTY_MEMBERS_CHANGED")

-- ==========================================================
-- COMMANDS
-- ==========================================================
function TankMark:SlashHandler(msg)
    local _, _, cmd, args = _strfind(msg, "^(%S*)%s*(.*)$")
    cmd = _lower(cmd or "")
    
    local iconNames = {
        ["skull"] = 8, ["cross"] = 7, ["square"] = 6, ["moon"] = 5,
        ["triangle"] = 4, ["diamond"] = 3, ["circle"] = 2, ["star"] = 1
    }
    
    if cmd == "reset" or cmd == "r" then
        TankMark:ResetSession()
        
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
            local zone = TankMark:GetCachedZone()
            -- Create zone if it doesn't exist
            if not TankMarkDB.Zones[zone] then
                TankMarkDB.Zones[zone] = {}
                TankMark:Print("|cff00ff00Created:|r New zone '" .. zone .. "'")
            end
            TankMark.IsRecorderActive = true
            TankMark:Print("Flight Recorder: |cff00ff00ENABLED|r for '" .. zone .. "'. Mouseover mobs to record.")
        elseif args == "stop" then
            TankMark.IsRecorderActive = false
            TankMark:Print("Flight Recorder: |cffff0000DISABLED|r.")
        else
            TankMark:Print("Usage: /tmark recorder start | stop")
        end
        
    elseif cmd == "zone" or cmd == "debug" then
        local currentZone = TankMark:GetCachedZone()
        TankMark:Print("Current Zone: " .. currentZone)
        TankMark:Print("Driver Mode: " .. (TankMark.IsSuperWoW and "|cff00ff00SuperWoW|r" or "|cffffaa00Standard|r"))
        if TankMark.IsSuperWoW then
            local count = 0
            for k,v in _pairs(TankMark.visibleTargets) do count = count + 1 end
            TankMark:Print("Scanner: " .. count .. " visible targets tracked.")
        end
        
    elseif cmd == "assign" then
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
                TankMark:Print("|cffff0000Error:|r Invalid mark.")
            end
        else
            TankMark:Print("Usage: /tmark assign [mark] [player]")
        end
        
    elseif cmd == "config" or cmd == "c" then
        if TankMark.ShowOptions then TankMark:ShowOptions() end
        
    elseif cmd == "sync" or cmd == "share" then
        if TankMark.BroadcastZone then TankMark:BroadcastZone() end
        
    else
        TankMark:Print("|cff00ffffTankMark v0.21-dev Commands:|r")
        TankMark:Print("  |cffffffff/tmark reset|r - Clear all marks and reset session")
        TankMark:Print("  |cffffffff/tmark on|r | |cffffffff/tmark off|r - Toggle auto-marking")
        TankMark:Print("  |cffffffff/tmark normals|r - Toggle marking normal mobs")
        TankMark:Print("  |cffffffff/tmark recorder start|r | |cffffffff/tmark recorder stop|r - Flight recorder")
        TankMark:Print("  |cffffffff/tmark assign [mark] [player]|r - Manual assignment")
        TankMark:Print("  |cffffffff/tmark config|r - Open configuration panel")
        TankMark:Print("  |cffffffff/tmark announce|r - Broadcast assignments to chat")
        TankMark:Print("  |cffffffff/tmark sync|r - Share mob database with raid")
        TankMark:Print("  |cffffffff/tmark zone|r - Show current zone and driver info")
    end
end

-- ==========================================================
-- ROSTER VALIDATION
-- ==========================================================
function TankMark:IsPlayerInRaid(playerName)
    if not playerName or playerName == "" then return true end
    
    -- Check player
    if UnitName("player") == playerName then return true end
    
    -- Check raid
    local numRaid = GetNumRaidMembers()
    if numRaid > 0 then
        for i = 1, 40 do
            if UnitName("raid"..i) == playerName then
                return true
            end
        end
        return false
    end
    
    -- Check party
    local numParty = GetNumPartyMembers()
    if numParty > 0 then
        for i = 1, 4 do
            if UnitName("party"..i) == playerName then
                return true
            end
        end
        return false
    end
    
    -- Solo - always valid (can't check)
    return true
end

function TankMark:AnnounceAssignments()
    local zone = TankMark:GetCachedZone()
    local profile = TankMarkProfileDB[zone]
    if not profile or _getn(profile) == 0 then
        TankMark:Print("No profile assignments found for " .. zone .. ".")
        return
    end
    
    local channel = "SAY"
    if GetNumRaidMembers() > 0 then channel = "RAID"
    elseif GetNumPartyMembers() > 0 then channel = "PARTY" end
    
    SendChatMessage("== " .. zone .. " Assignments ==", channel)
    SendChatMessage("Mark || Tank || Healers", channel)
    
    for _, data in _ipairs(profile) do
        if data.mark and data.tank ~= "" then
            local info = TankMark.MarkInfo[data.mark]
            local markDisplay = ""
            if info then markDisplay = info.color .. info.name .. "|r"
            else markDisplay = "Mark " .. data.mark end
            
            local msg = markDisplay .. " || " .. data.tank
            if data.healers and data.healers ~= "" then
                msg = msg .. " || " .. data.healers
            else
                msg = msg .. " || -"
            end
            SendChatMessage(msg, channel)
        end
    end
end

SLASH_TANKMARK1 = "/tmark"
SLASH_TANKMARK2 = "/tankmark"
SlashCmdList["TANKMARK"] = function(msg) TankMark:SlashHandler(msg) end
