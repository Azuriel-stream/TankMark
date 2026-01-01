-- TankMark: v0.8-dev (Dual-Layer Data)
-- File: TankMark_Data.lua

if not TankMark then
    TankMark = CreateFrame("Frame", "TankMarkFrame")
end

TankMark:RegisterEvent("ADDON_LOADED")
TankMark:RegisterEvent("PLAYER_LOGIN")
TankMark:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
TankMark:RegisterEvent("UNIT_HEALTH")
TankMark:RegisterEvent("CHAT_MSG_ADDON")

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
    TankMark:Print("Database initialized (v0.8-dev).")
end

function TankMark:Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ccff[TankMark]|r " .. msg)
end

-- IsMarkAlive removed in v0.8 (Superseded by internal cache & local VerifyMarkExistence)

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
                table.insert(TankMark.runtimeCache.classRoster[classEng], name)
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

    for _, playerName in ipairs(candidates) do
        local isAssigned = false
        for _, assignedName in pairs(TankMark.sessionAssignments) do
            if assignedName == playerName then 
                isAssigned = true 
                break 
            end
        end
        if not isAssigned then return playerName end
    end
    return nil 
end