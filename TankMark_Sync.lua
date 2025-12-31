-- TankMark: v0.7-dev
-- File: TankMark_Sync.lua

if not TankMark then return end

local SYNC_PREFIX = "TM_SYNC"

-- HELPER: Verify if a player is authorized to send data
function TankMark:IsTrustedSender(name)
    local numRaid = GetNumRaidMembers()
    
    if numRaid > 0 then
        -- RAID: Accept only Leader (2) or Assistant (1)
        for i = 1, 40 do
            local n, rank = GetRaidRosterInfo(i)
            if n == name then
                return (rank >= 1) -- True if Assist or Leader
            end
        end
    else
        -- PARTY: Accept only the Party Leader
        if GetNumPartyMembers() > 0 then
            -- Check party members
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
-- NEW: THROTTLE ENGINE
-- ==========================================================
TankMark.MsgQueue = {}
TankMark.LastSendTime = 0
local THROTTLE_INTERVAL = 0.3 -- Send 1 message every 0.3s

local throttleFrame = CreateFrame("Frame", "TankMarkThrottleFrame")
throttleFrame:Hide()

throttleFrame:SetScript("OnUpdate", function()
    -- If queue is empty, stop processing to save CPU
    if table.getn(TankMark.MsgQueue) == 0 then
        this:Hide()
        return
    end

    local now = GetTime()
    if (now - TankMark.LastSendTime) >= THROTTLE_INTERVAL then
        -- Pop the first message
        local msgData = table.remove(TankMark.MsgQueue, 1)
        
        -- Safe Send
        SendAddonMessage(msgData.prefix, msgData.payload, msgData.channel)
        
        TankMark.LastSendTime = now
    end
end)

-- Helper to enqueue messages
function TankMark:QueueMessage(prefix, payload, channel)
    table.insert(TankMark.MsgQueue, {
        ["prefix"] = prefix,
        ["payload"] = payload,
        ["channel"] = channel
    })
    
    -- Wake up the frame
    if not throttleFrame:IsVisible() then
        throttleFrame:Show()
    end
end

-- ==========================================================
-- 1. SENDER: Broadcast Current Zone (REFACTORED)
-- ==========================================================
function TankMark:BroadcastZone()
    local zone = GetRealZoneText()
    local zoneTable = TankMarkDB.Zones[zone]
    
    if not zoneTable then
        TankMark:Print("No data found for zone: " .. zone)
        return
    end
    
    -- Determine Channel
    local channel = "PARTY"
    if UnitInRaid("player") then 
        channel = "RAID"
    elseif GetNumPartyMembers() == 0 then
        TankMark:Print("You must be in a group to broadcast.")
        return
    end
    
    TankMark:Print("Queueing broadcast for: " .. zone .. "...")
    
    -- Loop and Enqueue
    local count = 0
    for mobName, data in pairs(zoneTable) do
        local payload = zone .. ";" .. mobName .. ";" .. data.prio .. ";" .. data.mark
        
        -- CHANGED: Use Queue instead of direct SendAddonMessage
        TankMark:QueueMessage(SYNC_PREFIX, payload, channel)
        
        count = count + 1
    end
    
    TankMark:Print("Queued " .. count .. " items. Sending over ~" .. math.ceil(count * THROTTLE_INTERVAL) .. "s.")
end

-- ==========================================================
-- 2. RECEIVER (Unchanged for now)
-- ==========================================================
function TankMark:HandleSync(prefix, msg, sender)
    if sender == UnitName("player") then return end
    if prefix ~= SYNC_PREFIX then return end
    
    if not TankMark:IsTrustedSender(sender) then
        -- Optional: specific debug print
        -- TankMark:Print("Blocked sync from unauthorized sender: " .. sender)
        return
    end
    
    local zone, mob, prio, mark = string.match(msg, "^(.-);(.-);(%d+);(%d+)$")
    
    if zone and mob and prio and mark then
        prio = tonumber(prio)
        mark = tonumber(mark)
        
        if not TankMarkDB.Zones[zone] then
            TankMarkDB.Zones[zone] = {}
        end
        
        TankMarkDB.Zones[zone][mob] = {
            ["prio"] = prio,
            ["mark"] = mark,
            ["type"] = "KILL"
        }
    end
end