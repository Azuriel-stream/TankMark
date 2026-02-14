-- TankMark: v0.25
-- File: Core/TankMark_Assignment.lua
-- Module Version: 1.0
-- Last Updated: 2026-02-08
-- Mark assignment algorithms and player detection

if not TankMark then return end

-- Import shared localizations
local L = TankMark.Locals

-- ==========================================================
-- ASSIGNMENT HELPERS
-- ==========================================================

function TankMark:GetFreeTankIcon()
    local zone = TankMark:GetCachedZone()
    local list = TankMarkProfileDB[zone]
    if not list then return nil end
    
    for _, entry in L._ipairs(list) do
        local markID = entry.mark
        local tankName = entry.tank
        
        if markID and not TankMark.usedIcons[markID] and not TankMark.disabledMarks[markID] then
            -- [v0.24] Skip marks assigned to CC classes
            if tankName and tankName ~= "" then
                local u = TankMark:FindUnitByName(tankName)
                if u then
                    -- Only return mark if player is alive AND not a CC class
                    if not L._UnitIsDeadOrGhost(u) and not TankMark:IsPlayerCCClass(tankName) then
                        return markID
                    end
                end
            else
                -- No player assigned - mark is free for use
                return markID
            end
        end
    end
    
    return nil
end

function TankMark:FindUnitByName(name)
    if L._UnitName("player") == name then return "player" end
    for i = 1, 4 do
        if L._UnitName("party" .. i) == name then return "party" .. i end
    end
    for i = 1, 40 do
        if L._UnitName("raid" .. i) == name then return "raid" .. i end
    end
    return nil
end

-- [v0.24] Check if player is a CC-capable class
function TankMark:IsPlayerCCClass(playerName)
    if not playerName or playerName == "" then return false end
    
    local unit = TankMark:FindUnitByName(playerName)
    if not unit then return false end
    
    local class = L._UnitClass(unit)
    
    -- CC-capable classes (long-duration CC abilities)
    if class == "Mage" or class == "Warlock" or class == "Hunter" or
       class == "Priest" or class == "Druid" then
        return true
    end
    
    -- Shaman: Only Troll race can CC (Hex ability)
    if class == "Shaman" then
        local race = L._UnitRace(unit)
        return race == "Troll"
    end
    
    return false
end

-- [v0.26] Find CC player in Team Profile matching required class
-- FIX: Case-insensitive class comparison
function TankMark:FindCCPlayerForClass(requiredClass)
	local zone = TankMark:GetCachedZone()
	local list = TankMarkProfileDB[zone]
	if not list then return nil end
	
	-- [v0.26] Normalize required class to uppercase for comparison
	if requiredClass then
		requiredClass = L._strupper(requiredClass)
	end
	
	for _, entry in L._ipairs(list) do
		local playerName = entry.tank
		local markID = entry.mark
		
		if playerName and playerName ~= "" then
			local unit = TankMark:FindUnitByName(playerName)
			if unit then
				local _, playerClassEng = L._UnitClass(unit)
				
				-- [v0.26] FIX: Use English class token (always uppercase) instead of localized name
				-- Match required class (both now uppercase)
				if playerClassEng == requiredClass then
					-- Check if mark is available (not used and not disabled)
					if not TankMark.usedIcons[markID] and not TankMark.disabledMarks[markID] then
						-- Check if player is alive
						if not L._UnitIsDeadOrGhost(unit) then
							return markID
						end
					end
				end
			end
		end
	end
	
	return nil
end

-- [v0.24] Helper: Check if player is alive and in raid
function TankMark:IsPlayerAliveAndInRaid(playerName)
    if not playerName or playerName == "" then return false end
    
    -- Find unit token
    local unit = TankMark:FindUnitByName(playerName)
    if not unit then return false end -- Not in raid/party
    
    -- Check if alive (includes ghost check)
    if L._UnitIsDeadOrGhost(unit) then return false end
    
    return true
end

function TankMark:GetAssigneeForMark(markID)
    local zone = TankMark:GetCachedZone()
    local list = TankMarkProfileDB[zone]
    if not list then return nil end
    
    for _, entry in L._ipairs(list) do
        if entry.mark == markID then return entry.tank end
    end
    
    return nil
end

function TankMark:AssignCC(iconID, playerName, taskType)
    TankMark.sessionAssignments[iconID] = playerName
    TankMark.usedIcons[iconID] = true
    if TankMark.UpdateHUD then TankMark:UpdateHUD() end
end
