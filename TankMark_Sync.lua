-- TankMark: v0.13-dev (Full Data Sync with Locks)
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
        SendAddonMessage(msgData.prefix, msgData.text, msgData.channel)
        TankMark.LastSendTime = now
    end
end)

function TankMark:QueueMessage(prefix, text, channel)
    table.insert(TankMark.MsgQueue, {prefix=prefix, text=text, channel=channel})
    throttleFrame:Show()
end

-- ==========================================================
-- 1. BROADCAST (Sender)
-- ==========================================================
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
            
            -- Payload: M;Zone;Mob;Prio;Mark;Type;Class
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
            
            -- Payload: L;Zone;GUID;Mark;Name
            local payload = "L;" .. zone .. ";" .. guid .. ";" .. mark .. ";" .. name
            TankMark:QueueMessage(SYNC_PREFIX, payload, channel)
            count = count + 1
        end
    end
    
    TankMark:Print("Sync: Queued " .. count .. " items (Mobs & Locks) for zone: " .. zone)
end

-- ==========================================================
-- 2. RECEIVER (Import)
-- ==========================================================
function TankMark:HandleSync(prefix, msg, sender)
    if sender == UnitName("player") then return end
    if prefix ~= SYNC_PREFIX then return end
    
    if not TankMark:IsTrustedSender(sender) then return end
    
    local dataType = string.sub(msg, 1, 1) -- 'M' or 'L'
    local content = string.sub(msg, 3)     -- Strip prefix + separator
    
    if dataType == "M" then
        -- FORMAT: Zone;Mob;Prio;Mark;Type;Class
        local zone, mob, prio, mark, mType, mClass = string.match(content, "^(.-);(.-);(%d+);(%d+);(.-);(.-)$")
        
        if zone and mob and prio and mark then
            prio = tonumber(prio)
            mark = tonumber(mark)
            
            if mClass == "NIL" then mClass = nil end
            if not mType or mType == "" then mType = "KILL" end
            
            if not TankMarkDB.Zones[zone] then TankMarkDB.Zones[zone] = {} end
            
            TankMarkDB.Zones[zone][mob] = { 
                ["prio"] = prio, 
                ["mark"] = mark, 
                ["type"] = mType, 
                ["class"] = mClass 
            }
        end
        
    elseif dataType == "L" then
        -- FORMAT: Zone;GUID;Mark;Name
        local zone, guid, mark, name = string.match(content, "^(.-);(.-);(%d+);(.-)$")
        
        if zone and guid and mark then
            mark = tonumber(mark)
            
            if not TankMarkDB.StaticGUIDs[zone] then TankMarkDB.StaticGUIDs[zone] = {} end
            
            -- Save Lock
            TankMarkDB.StaticGUIDs[zone][guid] = { 
                ["mark"] = mark, 
                ["name"] = name or "Synced Lock"
            }
        end
    end
    
    -- Live UI Update
    if TankMark.optionsFrame and TankMark.optionsFrame:IsVisible() then
        if TankMark.UpdateMobList then TankMark:UpdateMobList() end
    end
end