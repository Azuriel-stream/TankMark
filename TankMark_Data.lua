-- TankMark: v0.14 (Core Data & Events)
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
    if not TankMarkDB then TankMarkDB = {} end
    if not TankMarkDB.Zones then TankMarkDB.Zones = {} end
    if not TankMarkDB.StaticGUIDs then TankMarkDB.StaticGUIDs = {} end
    if not TankMarkDB.Profiles then TankMarkDB.Profiles = {} end
    TankMark:Print("Database initialized (v0.14).")
end

-- [v0.14] Helper to safely get profile data (Migration Layer)
function TankMark:GetProfileData(zone, iconID)
    if not TankMarkDB.Profiles[zone] then return nil end
    local data = TankMarkDB.Profiles[zone][iconID]
    
    -- Legacy Format: String -> Convert to Table
    if type(data) == "string" then
        return { tank = data, healers = "" }
    elseif type(data) == "table" then
        return data
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
            -- v0.14: Check if assigned as tank (string or table)
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