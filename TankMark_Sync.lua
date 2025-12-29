-- TankMark: v0.3-dev
-- File: TankMark_Sync.lua
-- Description: Handles sharing data between players via Addon Channel

if not TankMark then return end

local SYNC_PREFIX = "TM_SYNC"

-- ==========================================================
-- 1. SENDER: Broadcast Current Zone
-- ==========================================================
function TankMark:BroadcastZone()
    local zone = GetRealZoneText()
    local zoneTable = TankMarkDB.Zones[zone]
    
    if not zoneTable then
        TankMark:Print("No data found for zone: " .. zone)
        return
    end
    
    -- Determine Channel (RAID, PARTY, or BATTLEGROUND)
    local channel = "PARTY"
    if UnitInRaid("player") then 
        channel = "RAID"
    elseif GetNumPartyMembers() == 0 then
        TankMark:Print("You must be in a group to broadcast.")
        return
    end
    
    TankMark:Print("Broadcasting data for zone: " .. zone .. "...")
    
    -- Loop through every mob in this zone and send a message
    local count = 0
    for mobName, data in pairs(zoneTable) do
        -- Protocol Format: "ZoneName;MobName;Prio;Mark"
        local payload = zone .. ";" .. mobName .. ";" .. data.prio .. ";" .. data.mark
        
        SendAddonMessage(SYNC_PREFIX, payload, channel)
        count = count + 1
    end
    
    TankMark:Print("Sent " .. count .. " mob priorities to " .. channel .. ".")
end

-- ==========================================================
-- 2. RECEIVER: Process Incoming Data
-- ==========================================================
function TankMark:HandleSync(prefix, msg, sender)
    -- 1. Security Check: Ignore our own messages
    if sender == UnitName("player") then return end
    
    -- 2. Prefix Check: Is this for TankMark?
    if prefix ~= SYNC_PREFIX then return end
    
    -- 3. Parse Data
    -- Format: "ZoneName;MobName;Prio;Mark"
    -- Lua pattern matching to extract the 4 parts
    local zone, mob, prio, mark = string.match(msg, "^(.-);(.-);(%d+);(%d+)$")
    
    if zone and mob and prio and mark then
        -- Convert numbers
        prio = tonumber(prio)
        mark = tonumber(mark)
        
        -- 4. Save to Database
        if not TankMarkDB.Zones[zone] then
            TankMarkDB.Zones[zone] = {}
        end
        
        TankMarkDB.Zones[zone][mob] = {
            ["prio"] = prio,
            ["mark"] = mark,
            ["type"] = "KILL" -- Default
        }
        
        -- Optional: Print only once per batch (requires complex logic), 
        -- or just be silent. For dev, we print.
        -- TankMark:Print("Received data from " .. sender .. ": " .. mob)
    end
end