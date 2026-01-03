-- TankMark: v0.14 (Full Data Sync + TWA Integration)
-- File: TankMark_Sync.lua

if not TankMark then return end

local SYNC_PREFIX = "TM_SYNC"
local TWA_BW_PREFIX = "TWABW"
local TWA_PREFIX = "TWA"

-- ==========================================================
-- HELPER: Permissions
-- ==========================================================
function TankMark:IsTrustedSender(name)
    local numRaid = GetNumRaidMembers()
    if numRaid > 0 then
        for i = 1, 40 do
            local n, rank = GetRaidRosterInfo(i)
            if n == name then return (rank >= 1) end -- 1=Assist, 2=Leader
        end
    else
        if GetNumPartyMembers() > 0 then
            for i = 1, 4 do
                if UnitName("party"..i) == name and UnitIsPartyLeader("party"..i) then
                    return true
                end
            end
        end
    end
    return false
end

-- ==========================================================
-- TWA INTEGRATION (Receiver)
-- ==========================================================
TankMark.TWA_MarkMap = {
    ["Skull"]=8, ["Cross"]=7, ["Square"]=6, ["Moon"]=5,
    ["Triangle"]=4, ["Diamond"]=3, ["Circle"]=2, ["Star"]=1
}

function TankMark:HandleTWABW(msg, sender)
    -- Format: "BWSynch=Mark : Tank1 Tank2... || Healers: H1 H2..."
    -- Check for prefix
    local _, _, content = string.find(msg, "^BWSynch=(.*)")
    if not content or content == "start" or content == "end" then return end
    
    -- Parse Mark
    local _, _, markName, rest = string.find(content, "^(.-) : (.*)")
    if not markName or not TankMark.TWA_MarkMap[markName] then return end
    
    local iconID = TankMark.TWA_MarkMap[markName]
    
    -- Parse Tanks vs Healers
    -- Split by " || Healers: "
    local _, _, tankPart, healPart = string.find(rest, "(.*) || Healers: (.*)")
    if not tankPart then 
        tankPart = rest -- No healers?
        healPart = "" 
    end
    
    -- Clean Tanks
    local tankStr = string.gsub(tankPart, "-", "") -- Remove placeholders
    tankStr = string.gsub(tankStr, "%s+", " ") -- Normalize spaces
    tankStr = string.gsub(tankStr, "^%s*(.-)%s*$", "%1") -- Trim
    
    -- Clean Healers
    local healStr = ""
    if healPart then
        healStr = string.gsub(healPart, "-", "")
        healStr = string.gsub(healStr, "%s+", " ")
        healStr = string.gsub(healStr, "^%s*(.-)%s*$", "%1")
    end
    
    -- Pick first valid tank for TankMark (we only support 1 main assignee per icon for logic)
    local primaryTank = nil
    for word in string.gfind(tankStr, "%S+") do
        if word ~= "" then primaryTank = word; break end
    end
    
    -- Store
    local zone = GetRealZoneText()
    if not TankMarkDB.Profiles[zone] then TankMarkDB.Profiles[zone] = {} end
    
    TankMarkDB.Profiles[zone][iconID] = {
        ["tank"] = primaryTank,
        ["healers"] = (healStr ~= "") and healStr or nil
    }
    
    -- Live Update
    if zone == GetRealZoneText() and primaryTank then
        TankMark.sessionAssignments[iconID] = primaryTank
        TankMark.usedIcons[iconID] = true
        if TankMark.UpdateHUD then TankMark:UpdateHUD() end
    end
    
    if TankMark.optionsFrame and TankMark.optionsFrame:IsVisible() then
        TankMark:RefreshProfileUI()
    end
end

-- ==========================================================
-- TWA NATIVE INTEGRATION (Fallback)
-- ==========================================================
function TankMark:HandleTWA(msg, sender)
    -- TWA Native packets are complex. We only sniff 'Force Sync' payloads if we can identify them.
    -- This is highly experimental without specific opcodes.
    -- For now, relying on TWABW is safer as it's plain text.
    -- Placeholder for future expansion.
end

-- ==========================================================
-- CORE SYNC HANDLER
-- ==========================================================
function TankMark:HandleSync(prefix, msg, sender)
    if sender == UnitName("player") then return end
    
    if prefix == TWA_BW_PREFIX then
        if TankMark:IsTrustedSender(sender) then
            TankMark:HandleTWABW(msg, sender)
        end
        return
    end

    if prefix ~= SYNC_PREFIX then return end
    if not TankMark:IsTrustedSender(sender) then return end
    
    local dataType = string.sub(msg, 1, 1) -- 'M' or 'L'
    local content = string.sub(msg, 3)     -- Strip prefix + separator
    
    if dataType == "M" then
        -- (Existing Mob Sync Code...)
        local _, _, zone, mob, prio, mark, mType, mClass = string.find(content, "^(.-);(.-);(%d+);(%d+);(.-);(.-)$")
        if zone and mob then
            if not TankMarkDB.Zones[zone] then TankMarkDB.Zones[zone] = {} end
            TankMarkDB.Zones[zone][mob] = { 
                ["prio"] = tonumber(prio), 
                ["mark"] = tonumber(mark), 
                ["type"] = mType, 
                ["class"] = (mClass ~= "NIL") and mClass or nil 
            }
        end
        
    elseif dataType == "L" then
        -- (Existing Lock Sync Code...)
        local _, _, zone, guid, mark, name = string.find(content, "^(.-);(.-);(%d+);(.-)$")
        if zone and guid then
            if not TankMarkDB.StaticGUIDs[zone] then TankMarkDB.StaticGUIDs[zone] = {} end
            TankMarkDB.StaticGUIDs[zone][guid] = { 
                ["mark"] = tonumber(mark), 
                ["name"] = name 
            }
        end
    end
end

-- ==========================================================
-- BROADCAST (Sender) - Kept same as v0.13
-- ==========================================================
TankMark.MsgQueue = {}
TankMark.LastSendTime = 0
local THROTTLE_INTERVAL = 0.3
local throttleFrame = CreateFrame("Frame", "TankMarkThrottleFrame")
throttleFrame:Hide()

throttleFrame:SetScript("OnUpdate", function()
    if table.getn(TankMark.MsgQueue) == 0 then
        this:Hide(); return
    end
    local now = GetTime()
    if (now - TankMark.LastSendTime) >= THROTTLE_INTERVAL then
        local msgData = table.remove(TankMark.MsgQueue, 1)
        SendAddonMessage(msgData.prefix, msgData.text, msgData.channel)
        TankMark.LastSendTime = now
    end
end)

function TankMark:QueueMessage(prefix, text, channel)
    table.insert(TankMark.MsgQueue, {prefix=prefix, text=text, channel=channel})
    throttleFrame:Show()
end

function TankMark:BroadcastZone()
    if not TankMark:CanAutomate() then
        TankMark:Print("Error: You must be Raid Leader/Assist to sync.")
        return
    end
    
    local zone = GetRealZoneText()
    local count = 0
    local channel = "PARTY"
    if GetNumRaidMembers() > 0 then channel = "RAID" end
    
    -- A. Broadcast Mobs (Prefix: M)
    if TankMarkDB.Zones[zone] then
        for mob, data in pairs(TankMarkDB.Zones[zone]) do
            local safeClass = data.class or "NIL"
            local safeType = data.type or "KILL"
            local payload = "M;" .. zone .. ";" .. mob .. ";" .. data.prio .. ";" .. data.mark .. ";" .. safeType .. ";" .. safeClass
            TankMark:QueueMessage(SYNC_PREFIX, payload, channel)
            count = count + 1
        end
    end
    
    -- B. Broadcast Locks (Prefix: L)
    if TankMarkDB.StaticGUIDs[zone] then
        for guid, data in pairs(TankMarkDB.StaticGUIDs[zone]) do
            local mark = (type(data) == "table") and data.mark or data
            local name = (type(data) == "table") and data.name or "Unknown"
            local payload = "L;" .. zone .. ";" .. guid .. ";" .. mark .. ";" .. name
            TankMark:QueueMessage(SYNC_PREFIX, payload, channel)
            count = count + 1
        end
    end
    
    TankMark:Print("Sync: Queued " .. count .. " items (Mobs & Locks) for zone: " .. zone)
end