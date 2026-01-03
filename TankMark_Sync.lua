-- TankMark: v0.14 (Full Data Sync + TWA Integration)
-- File: TankMark_Sync.lua

if not TankMark then return end

local SYNC_PREFIX = "TM_SYNC"
local TWA_BW_PREFIX = "TWABW"

-- ==========================================================
-- LOCALIZATIONS (Performance & Constraints)
-- ==========================================================
local _strfind = string.find
local _gsub = string.gsub
local _sub = string.sub
local _match = string.match
local _gfind = string.gfind
local _format = string.format
local _tonumber = tonumber
local _insert = table.insert
local _remove = table.remove
local _getn = table.getn

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
    
    -- 1. Strip Prefix
    local _, _, content = _strfind(msg, "^BWSynch=(.*)")
    if not content or content == "start" or content == "end" then return end
    
    -- 2. Parse Mark (Separator is " : ")
    local _, _, markName, rest = _strfind(content, "^(.-) : (.*)")
    if not markName or not TankMark.TWA_MarkMap[markName] then return end
    
    local iconID = TankMark.TWA_MarkMap[markName]
    
    -- 3. Parse Tanks vs Healers (Capture Method)
    -- Pattern: Capture everything until double pipes, then capture everything after label
    local _, _, tankPart, healPart = _strfind(rest, "^(.-)%s*[|][|]%s*Healers:%s*(.*)$")
    
    -- Fallback: If pattern didn't match, assume no healers
    if not tankPart then
        tankPart = rest
        healPart = ""
    end
    
    -- 4. Clean Tanks
    local tankStr = _gsub(tankPart, "-", "") -- Remove TWA placeholders
    tankStr = _gsub(tankStr, "[|]", "")      -- Remove any lingering pipes
    tankStr = _gsub(tankStr, "%s+", " ")     -- Normalize spaces
    tankStr = _gsub(tankStr, "^%s*(.-)%s*$", "%1") -- Trim
    
    -- 5. Clean Healers
    local healStr = ""
    if healPart then
        healStr = _gsub(healPart, "-", "")
        healStr = _gsub(healStr, "%s+", " ")
        healStr = _gsub(healStr, "^%s*(.-)%s*$", "%1")
    end
    
    -- Pick first valid tank name for TankMark automation
    local primaryTank = nil
    for word in _gfind(tankStr, "%S+") do
        if word ~= "" then primaryTank = word; break end
    end
    
    -- Store Data
    local zone = GetRealZoneText()
    if not TankMarkDB.Profiles[zone] then TankMarkDB.Profiles[zone] = {} end
    
    TankMarkDB.Profiles[zone][iconID] = {
        ["tank"] = primaryTank,
        ["healers"] = (healStr ~= "") and healStr or nil
    }
    
    -- Live Update (only if in the correct zone)
    if zone == GetRealZoneText() and primaryTank then
        TankMark.sessionAssignments[iconID] = primaryTank
        TankMark.usedIcons[iconID] = true
        if TankMark.UpdateHUD then TankMark:UpdateHUD() end
    elseif zone == GetRealZoneText() and not primaryTank then
        -- Clear live assignment if TWA sent empty
        TankMark.sessionAssignments[iconID] = nil
        TankMark.usedIcons[iconID] = nil
        if TankMark.UpdateHUD then TankMark:UpdateHUD() end
    end
    
    -- Refresh UI
    if TankMark.optionsFrame and TankMark.optionsFrame:IsVisible() then
        TankMark:RefreshProfileUI()
    end
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
    
    local dataType = _sub(msg, 1, 1) -- 'M' or 'L'
    local content = _sub(msg, 3)     -- Strip prefix + separator
    
    if dataType == "M" then
        -- (Existing Mob Sync Code...)
        local _, _, zone, mob, prio, mark, mType, mClass = _strfind(content, "^(.-);(.-);(%d+);(%d+);(.-);(.-)$")
        if zone and mob then
            if not TankMarkDB.Zones[zone] then TankMarkDB.Zones[zone] = {} end
            TankMarkDB.Zones[zone][mob] = { 
                ["prio"] = _tonumber(prio), 
                ["mark"] = _tonumber(mark), 
                ["type"] = mType, 
                ["class"] = (mClass ~= "NIL") and mClass or nil 
            }
        end
        
    elseif dataType == "L" then
        -- (Existing Lock Sync Code...)
        local _, _, zone, guid, mark, name = _strfind(content, "^(.-);(.-);(%d+);(.-)$")
        if zone and guid then
            if not TankMarkDB.StaticGUIDs[zone] then TankMarkDB.StaticGUIDs[zone] = {} end
            TankMarkDB.StaticGUIDs[zone][guid] = { 
                ["mark"] = _tonumber(mark), 
                ["name"] = name 
            }
        end
    end
end

-- ==========================================================
-- BROADCAST (Sender)
-- ==========================================================
TankMark.MsgQueue = {}
TankMark.LastSendTime = 0
local THROTTLE_INTERVAL = 0.3
local throttleFrame = CreateFrame("Frame", "TankMarkThrottleFrame")
throttleFrame:Hide()

throttleFrame:SetScript("OnUpdate", function()
    if _getn(TankMark.MsgQueue) == 0 then
        this:Hide(); return
    end
    local now = GetTime()
    if (now - TankMark.LastSendTime) >= THROTTLE_INTERVAL then
        local msgData = _remove(TankMark.MsgQueue, 1)
        SendAddonMessage(msgData.prefix, msgData.text, msgData.channel)
        TankMark.LastSendTime = now
    end
end)

function TankMark:QueueMessage(prefix, text, channel)
    _insert(TankMark.MsgQueue, {prefix=prefix, text=text, channel=channel})
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