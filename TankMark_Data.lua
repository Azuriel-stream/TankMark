-- TankMark: v0.1-dev
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

-- 3. Database Defaults
function TankMark:InitializeDB()
    if not TankMarkDB then TankMarkDB = {} end
    
    -- Global Settings
    if not TankMarkDB.Settings then
        TankMarkDB.Settings = {
            ["AnnounceChannel"] = "RAID", 
            ["WhisperBackups"] = true,
            ["AutoResetInCombat"] = false
        }
    end

    -- Assignments (0 or nil = Auto/First Available)
    if not TankMarkDB.Assignments then
        TankMarkDB.Assignments = {
            [8] = nil, -- Skull
            [7] = nil, -- Cross
            [6] = nil, -- Square
            [5] = nil, -- Moon
            [4] = nil, -- Triangle
            [3] = nil, -- Diamond
            [2] = nil, -- Circle
            [1] = nil  -- Star
        }
    end

    -- Zone Data (The "Brain")
    if not TankMarkDB.Zones then
        TankMarkDB.Zones = {
            ["Molten Core"] = {
                 ["Molten Giant"] = { ["prio"] = 1, ["mark"] = 8, ["type"] = "KILL" },
                 ["Lava Surger"] =  { ["prio"] = 3, ["mark"] = 3, ["type"] = "CC", ["class"] = "WARLOCK" },
            },
            ["Winterspring"] = {
                ["Cobalt Broodling"] = { ["prio"] = 1, ["mark"] = 8, ["type"] = "KILL" },
            },
        }
    end
    
    TankMark:Print("Database Initialized. v0.1-dev loaded.")
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