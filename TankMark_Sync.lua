-- TankMark: v0.12 (Full Data Sync)
-- File: TankMark_Sync.lua

if not TankMark then return end

local SYNC_PREFIX = "TM_SYNC"

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
-- THROTTLE ENGINE
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
        SendAddonMessage(msgData.prefix, msgData.payload, msgData.channel)
        TankMark.LastSendTime = now
    end
end)

function TankMark:QueueMessage(prefix, payload, channel)
    table.insert(TankMark.MsgQueue, {
        ["prefix"] = prefix,
        ["payload"] = payload,
        ["channel"] = channel
    })
    if not throttleFrame:IsVisible() then throttleFrame:Show() end
end

-- ==========================================================
-- 1. SENDER (Broadcast)
-- ==========================================================
function TankMark:BroadcastZone()
    local zone = GetRealZoneText()
    local zoneTable = TankMarkDB.Zones[zone]
    
    if not zoneTable then
        TankMark:Print("No data found for zone: " .. zone)
        return
    end
    
    local channel = "PARTY"
    if UnitInRaid("player") then channel = "RAID"
    elseif GetNumPartyMembers() == 0 then
        TankMark:Print("You must be in a group to broadcast.")
        return
    end
    
    TankMark:Print("Queueing broadcast for: " .. zone .. "...")
    
    local count = 0
    for mobName, data in pairs(zoneTable) do
        -- SAFETY: Handle nil values for Class
        local safeClass = data.class or "NIL"
        local safeType = data.type or "KILL"
        
        -- FORMAT: Zone;Mob;Prio;Mark;Type;Class
        local payload = zone .. ";" .. mobName .. ";" .. data.prio .. ";" .. data.mark .. ";" .. safeType .. ";" .. safeClass
        
        TankMark:QueueMessage(SYNC_PREFIX, payload, channel)
        count = count + 1
    end
    
    TankMark:Print("Queued " .. count .. " items. Sending over ~" .. math.ceil(count * THROTTLE_INTERVAL) .. "s.")
end

-- ==========================================================
-- 2. RECEIVER (Import)
-- ==========================================================
function TankMark:HandleSync(prefix, msg, sender)
    if sender == UnitName("player") then return end
    if prefix ~= SYNC_PREFIX then return end
    
    if not TankMark:IsTrustedSender(sender) then return end
    
    -- FORMAT: Zone;Mob;Prio;Mark;Type;Class
    local zone, mob, prio, mark, mType, mClass = string.match(msg, "^(.-);(.-);(%d+);(%d+);(.-);(.-)$")
    
    if zone and mob and prio and mark then
        prio = tonumber(prio)
        mark = tonumber(mark)
        
        -- Restore NIL class to actual nil
        if mClass == "NIL" then mClass = nil end
        if not mType or mType == "" then mType = "KILL" end
        
        if not TankMarkDB.Zones[zone] then TankMarkDB.Zones[zone] = {} end
        
        -- Save full data structure
        TankMarkDB.Zones[zone][mob] = {
            ["prio"] = prio,
            ["mark"] = mark,
            ["type"] = mType,
            ["class"] = mClass
        }
        
        -- Refresh UI if open
        if TankMark.UpdateMobList then TankMark:UpdateMobList() end
    end
end