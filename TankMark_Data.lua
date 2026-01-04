-- TankMark: v0.15-dev (Ordered Profiles)
-- File: TankMark_Data.lua

if not TankMark then
    TankMark = CreateFrame("Frame", "TankMarkFrame")
end

TankMark:RegisterEvent("ADDON_LOADED")
TankMark:RegisterEvent("PLAYER_LOGIN")
TankMark:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
TankMark:RegisterEvent("UNIT_HEALTH")
TankMark:RegisterEvent("CHAT_MSG_ADDON")

-- ==========================================================
-- LOCALIZATIONS
-- ==========================================================
local _insert = table.insert
local _ipairs = ipairs
local _pairs = pairs

TankMark.sessionAssignments = {} 
TankMark.runtimeCache = { classRoster = {} }

-- Defaults
TankMark.MarkClassDefaults = {
    [1] = "WARRIOR", [2] = "WARRIOR", [3] = "WARLOCK", [4] = "WARLOCK", 
    [5] = "MAGE", [6] = "MAGE", [7] = nil, [8] = nil
}

function TankMark:InitializeDB()
    -- 1. Mob Database (RETAINED)
    if not TankMarkDB then TankMarkDB = {} end
    if not TankMarkDB.Zones then TankMarkDB.Zones = {} end
    if not TankMarkDB.StaticGUIDs then TankMarkDB.StaticGUIDs = {} end
    
    -- 2. Profile Database (RESET for v0.15 Structure)
    -- We assume any existing data is incompatible v0.14 data and ignore it.
    -- Structure: TankMarkProfileDB[zone] = { {mark=8, tank="Name", ...}, {mark=7, ...} }
    if not TankMarkProfileDB then TankMarkProfileDB = {} end
    
    TankMark:Print("Database initialized (v0.15 Ordered Lists).")
end

-- [v0.15] Adapter: Scans the ordered list to find data for a specific Icon ID
-- This keeps current logic (TankMark.lua) working until Phase 3.
function TankMark:GetProfileData(zone, iconID)
    if not TankMarkProfileDB[zone] then return nil end
    
    -- Scan the ordered array
    for _, entry in _ipairs(TankMarkProfileDB[zone]) do
        if entry.mark == iconID then
            return entry
        end
    end
    
    return nil
end

function TankMark:Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ccff[TankMark]|r " .. msg)
end

function TankMark:UpdateRoster()
    TankMark.runtimeCache.classRoster = {} 
    
    local function addPlayer(unitID)
        if UnitExists(unitID) and UnitIsConnected(unitID) then
            local _, classEng = UnitClass(unitID) 
            local name = UnitName(unitID)
            if classEng and name then
                if not TankMark.runtimeCache.classRoster[classEng] then
                    TankMark.runtimeCache.classRoster[classEng] = {}
                end
                _insert(TankMark.runtimeCache.classRoster[classEng], name)
            end
        end
    end

    local numRaid = GetNumRaidMembers()
    if numRaid > 0 then
        for i=1, 40 do addPlayer("raid"..i) end
    else
        for i=1, 4 do addPlayer("party"..i) end
        addPlayer("player") 
    end
end

function TankMark:GetFirstAvailableBackup(requiredClass)
    if not requiredClass then return nil end
    TankMark:UpdateRoster() 
    local candidates = TankMark.runtimeCache.classRoster[requiredClass]
    if not candidates then return nil end

    for _, playerName in _ipairs(candidates) do
        local isAssigned = false
        for _, data in _pairs(TankMark.sessionAssignments) do
            local assignedName = (type(data) == "table") and data.tank or data
            if assignedName == playerName then 
                isAssigned = true 
                break 
            end
        end
        if not isAssigned then return playerName end
    end
    return nil 
end