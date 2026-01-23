-- TankMark: v0.21
-- File: TankMark_Data.lua
-- [v0.21] Database initialization, snapshot system, and corruption detection

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
local _remove = table.remove
local _ipairs = ipairs
local _pairs = pairs
local _getn = table.getn

-- ==========================================================
-- SESSION STATE
-- ==========================================================
TankMark.sessionAssignments = {}
TankMark.runtimeCache = { classRoster = {} }
TankMark.activeDB = nil  -- [v0.21] Merged zone cache (Defaults + User DB)

-- ==========================================================
-- DATABASE INITIALIZATION
-- ==========================================================
function TankMark:InitializeDB()
    -- 1. Mob Database
    if not TankMarkDB then TankMarkDB = {} end
    if not TankMarkDB.Zones then TankMarkDB.Zones = {} end
    if not TankMarkDB.StaticGUIDs then TankMarkDB.StaticGUIDs = {} end
    
    -- 2. Profile Database
    if not TankMarkProfileDB then TankMarkProfileDB = {} end
    
    -- 3. [v0.21] Snapshot Database
    if not TankMarkDB_Snapshot then TankMarkDB_Snapshot = {} end
    
    -- 4. [v0.22] Character-Specific UI Settings
    if not TankMarkCharConfig then TankMarkCharConfig = {} end
    if not TankMarkCharConfig.HUD then TankMarkCharConfig.HUD = {} end
    
    -- 5. [v0.21] Corruption Detection
    local isCorrupt, errors = TankMark:ValidateDB()
    if isCorrupt then
        TankMark:ShowCorruptionDialog(errors)
        return
    end
    
    TankMark:Print("Database initialized (v0.21 Resilience System active).")
end

-- ==========================================================
-- [v0.21] CORRUPTION DETECTION (Layer 3)
-- ==========================================================
function TankMark:ValidateDB()
	local errors = {}
	local isCorrupt = false
	
	-- Check 1: Primary DB exists
	if not TankMarkDB or type(TankMarkDB) ~= "table" then
		_insert(errors, "Primary database missing or corrupt")
		isCorrupt = true
		return isCorrupt, errors
	end
	
	-- Check 2: Required keys exist
	if not TankMarkDB.Zones or type(TankMarkDB.Zones) ~= "table" then
		_insert(errors, "Zones table missing or corrupt")
		isCorrupt = true
	end
	
	if not TankMarkDB.StaticGUIDs or type(TankMarkDB.StaticGUIDs) ~= "table" then
		_insert(errors, "StaticGUIDs table missing or corrupt")
		isCorrupt = true
	end
	
	-- Check 3: Data type validation (sample check for first zone)
	if TankMarkDB.Zones and type(TankMarkDB.Zones) == "table" then
		for zoneName, mobs in _pairs(TankMarkDB.Zones) do
			if type(mobs) ~= "table" then
				_insert(errors, "Zone '" .. zoneName .. "' has invalid data")
				isCorrupt = true
				break
			end
			
			-- Sample mob validation (check first mob only for performance)
			for mobName, data in _pairs(mobs) do
				if type(data) ~= "table" or not data.prio or not data.mark then
					_insert(errors, "Mob '" .. mobName .. "' in zone '" .. zoneName .. "' has invalid structure")
					isCorrupt = true
				end
				break -- Only check first mob per zone
			end
			
			if isCorrupt then break end
		end
	end
	
	return isCorrupt, errors
end

function TankMark:ShowCorruptionDialog(errors)
	local errorText = "Database corruption detected!\n\n"
	for i, err in _ipairs(errors) do
		errorText = errorText .. "- " .. err .. "\n"
	end
	errorText = errorText .. "\nChoose recovery option:"
	
	StaticPopupDialogs["TANKMARK_CORRUPTION"] = {
		text = errorText,
		button1 = "Restore Snapshot",
		button2 = "Merge Defaults",
		button3 = "Start Fresh",
		OnAccept = function()
			TankMark:RestoreFromSnapshot(1)
		end,
		OnCancel = function()
			TankMark:MergeDefaults()
		end,
		OnAlt = function()
			-- Wipe and reinitialize
			TankMarkDB = {Zones = {}, StaticGUIDs = {}}
			TankMarkProfileDB = {}
			TankMark:Print("Database wiped. Starting fresh.")
		end,
		timeout = 0,
		whileDead = 1,
		hideOnEscape = nil, -- Force user to choose
	}
	
	StaticPopup_Show("TANKMARK_CORRUPTION")
end

-- ==========================================================
-- [v0.21] SNAPSHOT SYSTEM (Layer 2)
-- ==========================================================
function TankMark:CreateSnapshot()
	if not TankMarkDB_Snapshot then TankMarkDB_Snapshot = {} end
	
	-- Deep copy helper (Lua 5.0 compatible)
	local function DeepCopy(original)
		if type(original) ~= "table" then return original end
		local copy = {}
		for k, v in _pairs(original) do
			copy[k] = DeepCopy(v)
		end
		return copy
	end
	
	-- Build snapshot
	local snapshot = {
		timestamp = time(),
		zones = DeepCopy(TankMarkDB.Zones),
		guids = DeepCopy(TankMarkDB.StaticGUIDs),
		profile = nil -- Add current zone profile if in a known zone
	}
	
	-- Capture current zone profile
	local currentZone = TankMark:GetCachedZone()
	if currentZone and TankMarkProfileDB[currentZone] then
		snapshot.profile = {
			zone = currentZone,
			data = DeepCopy(TankMarkProfileDB[currentZone])
		}
	end
	
	-- Insert at front of list
	_insert(TankMarkDB_Snapshot, 1, snapshot)
	
	-- Keep only last 3 snapshots
	while _getn(TankMarkDB_Snapshot) > 3 do
		_remove(TankMarkDB_Snapshot)
	end
	
	TankMark:Print("Snapshot created (" .. _getn(TankMarkDB_Snapshot) .. "/3 slots used).")
end

function TankMark:RestoreFromSnapshot(index)
	if not TankMarkDB_Snapshot or not TankMarkDB_Snapshot[index] then
		TankMark:Print("|cffff0000Error:|r No snapshot found at index " .. index)
		return
	end
	
	local snapshot = TankMarkDB_Snapshot[index]
	
	-- Deep copy helper
	local function DeepCopy(original)
		if type(original) ~= "table" then return original end
		local copy = {}
		for k, v in _pairs(original) do
			copy[k] = DeepCopy(v)
		end
		return copy
	end
	
	-- Restore data
	TankMarkDB.Zones = DeepCopy(snapshot.zones)
	TankMarkDB.StaticGUIDs = DeepCopy(snapshot.guids)
	
	-- Restore profile if present
	if snapshot.profile then
		TankMarkProfileDB[snapshot.profile.zone] = DeepCopy(snapshot.profile.data)
	end
	
	-- Count restored mobs
	local mobCount = 0
	for _, mobs in _pairs(TankMarkDB.Zones) do
		for _ in _pairs(mobs) do
			mobCount = mobCount + 1
		end
	end
	
	TankMark:Print("|cff00ff00Restored:|r " .. mobCount .. " mobs from snapshot (age: " .. TankMark:FormatTimestamp(snapshot.timestamp) .. ")")
	
	-- Refresh UI if open
	if TankMark.UpdateMobList then TankMark:UpdateMobList() end
	if TankMark.UpdateHUD then TankMark:UpdateHUD() end
end

function TankMark:MergeDefaults()
	if not TankMarkDefaults then
		TankMark:Print("|cffff0000Error:|r Default database not loaded.")
		return
	end
	
	local added = 0
	
	for zoneName, defaultMobs in _pairs(TankMarkDefaults) do
		if not TankMarkDB.Zones[zoneName] then
			TankMarkDB.Zones[zoneName] = {}
		end
		
		for mobName, mobData in _pairs(defaultMobs) do
			if not TankMarkDB.Zones[zoneName][mobName] then
				-- Deep copy to avoid reference issues
				TankMarkDB.Zones[zoneName][mobName] = {
					prio = mobData.prio,
					mark = mobData.mark,
					type = mobData.type,
					class = mobData.class
				}
				added = added + 1
			end
		end
	end
	
	TankMark:Print("|cff00ff00Merged:|r " .. added .. " mobs from default database.")
	
	-- Refresh UI
	if TankMark.UpdateMobList then TankMark:UpdateMobList() end
end

-- ==========================================================
-- [v0.21] LAZY-LOAD ZONE DATA (Layer 1 Integration)
-- ==========================================================
function TankMark:LoadZoneData(zoneName)
	if not zoneName then return end
	
	-- Build merged view for current zone
	TankMark.activeDB = {}
	
	-- Priority 1: User data (always wins)
	if TankMarkDB.Zones[zoneName] then
		for mobName, data in _pairs(TankMarkDB.Zones[zoneName]) do
			TankMark.activeDB[mobName] = data
		end
	end
	
	-- Priority 2: Default data (fill gaps only)
	if TankMarkDefaults and TankMarkDefaults[zoneName] then
		for mobName, data in _pairs(TankMarkDefaults[zoneName]) do
			if not TankMark.activeDB[mobName] then
				TankMark.activeDB[mobName] = data
			end
		end
	end
end

-- ==========================================================
-- HELPER FUNCTIONS
-- ==========================================================
-- [v0.21] Refresh activeDB when database changes via config UI
function TankMark:RefreshActiveDB()
    local zone = TankMark:GetCachedZone()
    if zone then
        TankMark:LoadZoneData(zone)
    end
end

function TankMark:FormatTimestamp(timestamp)
	local diff = time() - timestamp
	
	if diff < 60 then
		return diff .. " seconds ago"
	elseif diff < 3600 then
		return math.floor(diff / 60) .. " minutes ago"
	elseif diff < 86400 then
		return math.floor(diff / 3600) .. " hours ago"
	else
		return math.floor(diff / 86400) .. " days ago"
	end
end

-- Legacy adapter for existing code
function TankMark:GetProfileData(zone, iconID)
	if not TankMarkProfileDB[zone] then return nil end
	
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

-- ==========================================================
-- ROSTER MANAGEMENT
-- ==========================================================
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
