-- TankMark: v0.18-dev (Release Candidate)
-- File: TankMark_Scanner.lua
-- [PHASE 2] Made scanner throttle interval configurable

if not TankMark then return end

-- Localizations
local _IsSpellInRange = IsSpellInRange
local _CheckInteractDistance = CheckInteractDistance
local _strfind = string.find
local _ipairs = ipairs
local _pairs = pairs

-- [PHASE 2] Configurable scan interval (in seconds)
-- Increase this value if experiencing performance issues with large nameplate counts
local SCAN_INTERVAL = 0.5

-- State
TankMark.visibleTargets = {}
TankMark.RangeSpellID = nil
TankMark.RangeSpellIndex = nil
TankMark.IsSuperWoW = false

-- ==========================================================
-- SUPERWOW INITIALIZATION
-- ==========================================================
function TankMark:InitDriver()
	-- Check global variable exposed by SuperWoW
	if type(SUPERWOW_VERSION) ~= "nil" then
		TankMark.IsSuperWoW = true
		TankMark:Print("SuperWoW Detected: |cff00ff00v0.12 Hybrid Driver Loaded.|r")
		TankMark:StartSuperScanner()
	else
		TankMark:Print("Standard Client: Hybrid features disabled. Falling back to v0.10 driver.")
	end
end

function TankMark:StartSuperScanner()
	local f = CreateFrame("Frame", "TMScannerFrame")
	local elapsed = 0
	TankMark.visibleTargets = {}
	
	f:SetScript("OnUpdate", function()
		-- [PHASE 2] Use configurable throttle interval
		elapsed = elapsed + arg1
		if elapsed < SCAN_INTERVAL then return end
		elapsed = 0
		
		-- Only run if active & in group (or recording)
		if not TankMark.IsRecorderActive then
			if not TankMark:CanAutomate() then return end
			if GetNumRaidMembers() == 0 and GetNumPartyMembers() == 0 then return end
		end
		
		-- Wipe table manually (Lua 5.0)
		for k in _pairs(TankMark.visibleTargets) do TankMark.visibleTargets[k] = nil end
		
		-- SuperWoW Feature: frame:GetName(1) -> GUID
		local frames = {WorldFrame:GetChildren()}
		for _, plate in _ipairs(frames) do
			if plate:IsVisible() and TankMark:IsNameplate(plate) then
				local guid = plate:GetName(1)
				if guid then
					TankMark.visibleTargets[guid] = true
					if not TankMark.activeGUIDs[guid] then
						TankMark:ProcessUnit(guid, "SCANNER")
					end
				end
			end
		end
		
		if TankMark.IsSuperWoW and TankMark.ReviewSkullState then
			TankMark:ReviewSkullState()
		end
	end)
end

function TankMark:IsNameplate(frame)
	if not frame or not frame.GetChildren or not frame:IsVisible() then return false end
	local children = {frame:GetChildren()}
	for _, child in _ipairs(children) do
		if child.GetValue and child.GetMinMaxValues and child.SetMinMaxValues then return true end
	end
	return false
end

-- ==========================================================
-- RANGE SYSTEM
-- ==========================================================
function TankMark:ScanForRangeSpell()
	-- 1. SuperWoW Path (Use Hex ID 16707)
	if TankMark.IsSuperWoW then
		TankMark.RangeSpellID = 16707
		TankMark.RangeSpellIndex = nil
		TankMark:Print("Range Extension: Active (~40y).")
		return
	end
	
	-- 2. Standard Client Path (Scan for Name -> Store Index)
	local longRangeSpells = {
		["Fireball"] = 35, ["Frostbolt"] = 30, ["Shadow Bolt"] = 30,
		["Wrath"] = 30, ["Lightning Bolt"] = 30, ["Starfire"] = 30,
		["Shoot"] = 30, ["Shoot Bow"] = 30, ["Shoot Gun"] = 30, ["Shoot Crossbow"] = 30,
		["Hunter's Mark"] = 100, ["Mind Blast"] = 30, ["Smite"] = 30
	}
	
	local bestName = nil
	local bestRange = 0
	local bestIndex = nil
	local i = 1
	
	while true do
		if i > 1000 then break end -- Safety Cap
		local spellName, rank = GetSpellName(i, "spell")
		if not spellName then break end
		
		if longRangeSpells[spellName] then
			local range = longRangeSpells[spellName]
			if range > bestRange then
				bestRange = range
				bestName = spellName
				bestIndex = i
			end
		end
		i = i + 1
	end
	
	if bestIndex then
		TankMark.RangeSpellIndex = bestIndex
		TankMark.RangeSpellID = nil
		TankMark:Print("Range Extension: Legacy Mode (" .. bestName .. " ~" .. bestRange .. "y).")
	else
		TankMark.RangeSpellIndex = nil
		TankMark.RangeSpellID = nil
	end
end

function TankMark:Driver_IsDistanceValid(unitOrGuid)
	-- 1. SuperWoW Logic (ID based)
	if TankMark.IsSuperWoW and TankMark.RangeSpellID and _IsSpellInRange then
		local inRange = _IsSpellInRange(TankMark.RangeSpellID, unitOrGuid)
		if inRange == 1 then return true end
	
	-- 2. Standard Logic (Index based)
	elseif TankMark.RangeSpellIndex and _IsSpellInRange then
		local inRange = _IsSpellInRange(TankMark.RangeSpellIndex, "spell", unitOrGuid)
		if inRange == 1 then return true end
	end
	
	-- 3. Fallback (28 yards)
	if type(unitOrGuid) == "string" and not _strfind(unitOrGuid, "^0x") then
		return _CheckInteractDistance(unitOrGuid, 4)
	end
	
	return false
end
