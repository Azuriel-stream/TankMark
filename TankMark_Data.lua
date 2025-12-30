-- TankMark: v0.4-dev
-- Module: Database Initialization & Utility Functions
-- File: TankMark_Data.lua

-- 1. Addon Initialization
-- GLOBAL object so other files can see it (Removed 'local')
if not TankMark then
    TankMark = CreateFrame("Frame", "TankMarkFrame")
end

TankMark:RegisterEvent("ADDON_LOADED")
TankMark:RegisterEvent("PLAYER_LOGIN")
TankMark:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
TankMark:RegisterEvent("UNIT_HEALTH")
TankMark:RegisterEvent("CHAT_MSG_ADDON")

-- Internal Runtime Tables (Not saved to DB)
TankMark.sessionAssignments = {} -- Structure: { [iconID] = "PlayerName" }
TankMark.runtimeCache = {
    classRoster = {} -- Structure: { ["WARLOCK"] = {"PlayerA", "PlayerB"} }
}

-- 2. Constants & Configuration
local RAID_ICONS = {
    [8] = "|cffffffffSKULL|r",
    [7] = "|cffff0000CROSS|r",
    [6] = "|cff00ccffSQUARE|r",
    [5] = "|cff888888MOON|r",
    [4] = "|cff00ff00TRIANGLE|r",
    [3] = "|cffff00ffDIAMOND|r",
    [2] = "|cffff8800CIRCLE|r",
    [1] = "|cffffff00STAR|r",
}

-- Fallback Classes: If specific assignment is missing, pick one of these
TankMark.MarkClassDefaults = {
    [1] = "WARRIOR", -- Star: Usually a Tank
    [2] = "WARRIOR", -- Circle: Usually a Tank
    [3] = "WARLOCK", -- Diamond: Banish/Fear
    [4] = "WARLOCK", -- Triangle: Banish/Fear (or Druid Sleep?)
    [5] = "MAGE",    -- Moon: Sheep
    [6] = "MAGE",    -- Square: Sheep (or Hunter Trap?)
    [7] = nil,       -- Cross: Kill Target (No class fallback)
    [8] = nil        -- Skull: Kill Target (No class fallback)
}

-- 3. Database Defaults
function TankMark:InitializeDB()
    if not TankMarkDB then TankMarkDB = {} end
    
    -- 1. Mob Database (Existing)
    if not TankMarkDB.Zones then TankMarkDB.Zones = {} end
    
    -- 2. Roster Profiles (NEW for v0.4)
    -- Structure: TankMarkDB.Profiles["ZoneName"][IconID] = "PlayerName"
    if not TankMarkDB.Profiles then TankMarkDB.Profiles = {} end
    
    TankMark:Print("Database initialized.")
end

-- 4. Utility: Logging/Printing
function TankMark:Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ccff[TankMark]|r " .. msg)
end

function TankMark:Debug(msg)
    -- Uncomment for dev usage
    -- DEFAULT_CHAT_FRAME:AddMessage("|cff999999[TM-Debug]|r " .. msg)
end

-- 5. Utility: The "Blind" Scanner (Checks if a Mark is still alive)
function TankMark:IsMarkAlive(iconID)
    local numRaid = GetNumRaidMembers()
    local numParty = GetNumPartyMembers()
    
    local function checkTarget(unitID)
        if UnitExists(unitID) and GetRaidTargetIndex(unitID) == iconID then
            return unitID
        end
        return nil
    end

    local foundUnitID = nil

    if numRaid > 0 then
        for i = 1, 40 do
            foundUnitID = checkTarget("raid"..i.."target")
            if foundUnitID then break end
        end
    elseif numParty > 0 then
        for i = 1, 4 do -- FIXED: "do" instead of "then"
            foundUnitID = checkTarget("party"..i.."target")
            if foundUnitID then break end
        end
        if not foundUnitID then foundUnitID = checkTarget("target") end 
    else
        foundUnitID = checkTarget("target")
    end

    if foundUnitID then
        if UnitIsDeadOrGhost(foundUnitID) then
            return false 
        else
            return true 
        end
    end
    return true 
end

-- 6. Utility: Roster Scanner
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

-- 7. Utility: Get First Available Backup
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
        
        -- Assuming alive for v0.1 simplification
        local isAlive = true 

        if not isAssigned and isAlive then
            return playerName 
        end
    end

    return nil 
end