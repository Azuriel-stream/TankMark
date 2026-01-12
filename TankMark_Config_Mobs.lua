-- TankMark: v0.19-dev

-- File: TankMark_Config_Mobs.lua

-- Mob Database configuration UI with zone management

if not TankMark then return end

-- ==========================================================
-- LOCALIZATIONS
-- ==========================================================

local _pairs = pairs
local _ipairs = ipairs
local _insert = table.insert
local _sort = table.sort
local _getn = table.getn
local _lower = string.lower
local _strfind = string.find
local _gsub = string.gsub

-- ==========================================================
-- STATE
-- ==========================================================

TankMark.mobRows = {}
TankMark.selectedIcon = 8
TankMark.selectedClass = nil
TankMark.isZoneListMode = false
TankMark.lockViewZone = nil
TankMark.editingLockGUID = nil
TankMark.detectedCreatureType = nil
TankMark.isLockActive = false

-- ==========================================================
-- UI REFERENCES
-- ==========================================================

TankMark.scrollFrame = nil
TankMark.searchBox = nil
TankMark.zoneDropDown = nil
TankMark.zoneModeCheck = nil
TankMark.editMob = nil
TankMark.editPrio = nil
TankMark.saveBtn = nil
TankMark.cancelBtn = nil
TankMark.lockBtn = nil
TankMark.classBtn = nil
TankMark.iconBtn = nil

-- ==========================================================
-- LOGIC CONSTANTS
-- ==========================================================

local CLASS_DEFAULTS = {
	["MAGE"] = { icon = 5, prio = 3 },
	["WARLOCK"] = { icon = 3, prio = 3 },
	["DRUID"] = { icon = 4, prio = 3 },
	["ROGUE"] = { icon = 1, prio = 3 },
	["PRIEST"] = { icon = 6, prio = 3 },
	["HUNTER"] = { icon = 2, prio = 3 },
	["KILL"] = { icon = 8, prio = 1 },
	["IGNORE"] = { icon = 0, prio = 9 }
}

local CC_MAP = {
	["Humanoid"] = { "MAGE", "ROGUE", "WARLOCK", "PRIEST" },
	["Beast"] = { "MAGE", "DRUID", "HUNTER" },
	["Elemental"] = { "WARLOCK" },
	["Demon"] = { "WARLOCK" },
	["Undead"] = { "PRIEST" },
	["Dragonkin"] = { "DRUID" }
}

local ALL_CLASSES = { "MAGE", "WARLOCK", "DRUID", "ROGUE", "PRIEST", "HUNTER", "WARRIOR", "SHAMAN", "PALADIN" }

-- ==========================================================
-- LOGIC HELPERS
-- ==========================================================

function TankMark:UpdateClassButton()
	if not TankMark.classBtn then return end
	if TankMark.selectedClass then
		TankMark.classBtn:SetText(TankMark.selectedClass)
		TankMark.classBtn:SetTextColor(0, 1, 0)
	else
		TankMark.classBtn:SetText("No CC (Kill)")
		TankMark.classBtn:SetTextColor(1, 0.82, 0)
	end
	if TankMark.selectedIcon == 0 then
		TankMark.classBtn:SetText("IGNORED")
		TankMark.classBtn:SetTextColor(0.5, 0.5, 0.5)
	end
end

function TankMark:ApplySmartDefaults(className)
	local defaults = className and CLASS_DEFAULTS[className] or CLASS_DEFAULTS["KILL"]
	TankMark.selectedIcon = defaults.icon
	if TankMark.iconBtn and TankMark.iconBtn.tex then
		TankMark:SetIconTexture(TankMark.iconBtn.tex, TankMark.selectedIcon)
	end
	if TankMark.editPrio then
		TankMark.editPrio:SetText(tostring(defaults.prio))
	end
end

function TankMark:ToggleLockState()
	if not UnitExists("target") and not TankMark.editingLockGUID then
		TankMark:Print("|cffff0000Error:|r You must target a mob to lock it.")
		return
	end
	TankMark.isLockActive = not TankMark.isLockActive
	if TankMark.lockBtn then
		if TankMark.isLockActive then
			TankMark.lockBtn:SetText("|cff00ff00LOCKED|r")
			TankMark.lockBtn:LockHighlight()
		else
			TankMark.lockBtn:SetText("Lock Mark")
			TankMark.lockBtn:UnlockHighlight()
		end
	end
end

function TankMark:ResetEditor()
	if TankMark.editMob then TankMark.editMob:SetText("") end
	if TankMark.editPrio then TankMark.editPrio:SetText("1") end
	TankMark.editingLockGUID = nil
	TankMark.detectedCreatureType = nil
	TankMark.isLockActive = false
	TankMark.selectedClass = nil
	TankMark:UpdateClassButton()
	TankMark.selectedIcon = 8
	if TankMark.iconBtn and TankMark.iconBtn.tex then
		TankMark:SetIconTexture(TankMark.iconBtn.tex, 8)
	end
	if TankMark.lockBtn then
		TankMark.lockBtn:SetText("Lock Mark")
		TankMark.lockBtn:UnlockHighlight()
		TankMark.lockBtn:Disable()
	end
	if TankMark.saveBtn then
		TankMark.saveBtn:SetText("Save")
		TankMark.saveBtn:Disable()
	end
	if TankMark.cancelBtn then TankMark.cancelBtn:Hide() end
end

function TankMark:SetDropdownState(enabled)
	if not TankMark.zoneDropDown then return end
	local name = TankMark.zoneDropDown:GetName()
	local btn = _G[name.."Button"]
	local txt = _G[name.."Text"]
	if enabled then
		if btn then btn:Enable(); btn:Show() end
		TankMark.zoneDropDown:EnableMouse(true)
		if txt then txt:SetVertexColor(1, 1, 1) end
	else
		if btn then btn:Disable() end
		TankMark.zoneDropDown:EnableMouse(false)
		if txt then txt:SetVertexColor(0.5, 0.5, 0.5) end
	end
end

function TankMark:ToggleZoneBrowser()
	TankMark.isZoneListMode = not TankMark.isZoneListMode
	TankMark.lockViewZone = nil
	TankMark:ResetEditor()
	if TankMark.searchBox then TankMark.searchBox:SetText("") end
	if TankMark.isZoneListMode then
		TankMark:SetDropdownState(false)
		UIDropDownMenu_SetText("Manage Saved Zones", TankMark.zoneDropDown)
	else
		TankMark:SetDropdownState(true)
		UIDropDownMenu_SetText(GetRealZoneText(), TankMark.zoneDropDown)
	end
	if TankMark.zoneModeCheck then
		TankMark.zoneModeCheck:SetChecked(TankMark.isZoneListMode)
	end
	TankMark:UpdateMobList()
end

function TankMark:ViewLocksForZone(zoneName)
	TankMark.lockViewZone = zoneName
	TankMark:ResetEditor()
	TankMark:UpdateMobList()
end

-- ==========================================================
-- MOB LIST UPDATE
-- ==========================================================

function TankMark:UpdateMobList()
	if not TankMark.optionsFrame or not TankMark.optionsFrame:IsVisible() then return end
	if not TankMarkDB then TankMarkDB = {} end
	
	local db = TankMarkDB
	local zone = UIDropDownMenu_GetText(TankMark.zoneDropDown) or GetRealZoneText()
	local listData = {}
	local filter = ""
	if TankMark.searchBox then filter = _lower(TankMark.searchBox:GetText()) end
	
	-- Build list based on current mode
	if TankMark.isZoneListMode and TankMark.lockViewZone then
		-- Lock view for specific zone
		local z = TankMark.lockViewZone
		_insert(listData, { type="BACK", label="<< Back to Zones" })
		if db.StaticGUIDs[z] then
			for guid, data in _pairs(db.StaticGUIDs[z]) do
				local icon = (type(data) == "table") and data.mark or data
				local mobName = (type(data) == "table") and data.name or "Unknown Mob"
				_insert(listData, { type="LOCK", guid=guid, mark=icon, name=mobName })
			end
		end
		_sort(listData, function(a,b)
			if not a or not b then return false end
			if a.type=="BACK" then return true end
			if b.type=="BACK" then return false end
			local mA = a.mark or 0
			local mB = b.mark or 0
			return mA < mB
		end)
	elseif TankMark.isZoneListMode then
		-- Zone list mode
		for zoneName, _ in _pairs(db.Zones) do
			if filter == "" or _strfind(_lower(zoneName), filter, 1, true) then
				local locks = 0
				if db.StaticGUIDs[zoneName] then
					for k,v in _pairs(db.StaticGUIDs[zoneName]) do locks = locks + 1 end
				end
				_insert(listData, { label = zoneName, type = "ZONE", lockCount = locks })
			end
		end
		_sort(listData, function(a,b) return a.label < b.label end)
	else
		-- Normal mob list for selected zone
		local mobsData = db.Zones[zone] or {}
		for name, info in _pairs(mobsData) do
			if filter == "" or _strfind(_lower(name), filter, 1, true) then
				_insert(listData, { name=name, prio=info.prio, mark=info.mark, type=info.type, class=info.class })
			end
		end
		_sort(listData, function(a, b)
			if not a or not b then return false end
			local pA = a.prio or 99
			local pB = b.prio or 99
			if pA == pB then
				return (a.name or "") < (b.name or "")
			end
			return pA < pB
		end)
	end
	
	-- Render list
	local numItems = _getn(listData)
	local MAX_ROWS = 9
	FauxScrollFrame_Update(TankMark.scrollFrame, numItems, MAX_ROWS, 22)
	local offset = FauxScrollFrame_GetOffset(TankMark.scrollFrame)
	
	for i = 1, MAX_ROWS do
		local index = offset + i
		local row = TankMark.mobRows[i]
		if row then
			if index <= numItems then
				local data = listData[index]
				row.icon:Hide()
				row.del:Hide()
				row.edit:Hide()
				row.text:SetTextColor(1,1,1)
				row:SetScript("OnClick", nil)
				
				if data.type == "BACK" then
					row.text:SetText("|cffffd200" .. data.label .. "|r")
					row.icon:Show()
					row.icon:SetTexture("Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Up")
					row.icon:SetTexCoord(0, 1, 0, 1)
					row:SetScript("OnClick", function()
						TankMark.lockViewZone = nil
						TankMark:ResetEditor()
						TankMark:UpdateMobList()
						PlaySound("igMainMenuOptionCheckBoxOn")
					end)
				elseif data.type == "LOCK" then
					TankMark:SetIconTexture(row.icon, data.mark)
					row.icon:Show()
					row.text:SetText(data.name .. " |cff888888(" .. string.sub(data.guid, -6) .. ")|r")
					row.del:Show()
					row.del:SetText("X")
					row.del:SetWidth(20)
					row.del:SetScript("OnClick", function() TankMark:RequestDeleteLock(data.guid, data.name) end)
					row.edit:Show()
					row.edit:SetText("E")
					row.edit:SetWidth(20)
					row.edit:SetScript("OnClick", function()
						TankMark.editMob:SetText(data.name or "Unknown")
						TankMark.selectedIcon = data.mark
						TankMark.editingLockGUID = data.guid
						TankMark.selectedClass = nil
						TankMark:UpdateClassButton()
						if TankMark.iconBtn then TankMark:SetIconTexture(TankMark.iconBtn.tex, data.mark) end
						TankMark.saveBtn:SetText("Update")
						TankMark.saveBtn:Enable()
						TankMark.cancelBtn:Show()
						TankMark.lockBtn:Disable()
						TankMark.lockBtn:SetText("Locked")
					end)
				elseif data.type == "ZONE" then
					local info = (data.lockCount > 0) and (" |cff00ff00(" .. data.lockCount .. " locks)|r") or ""
					row.text:SetText("|cffffd200" .. data.label .. "|r" .. info)
					row.del:Show()
					row.del:SetText("|cffff0000Delete|r")
					row.del:SetWidth(60)
					row.del:SetScript("OnClick", function() TankMark:RequestDeleteZone(data.label) end)
					row.edit:Show()
					row.edit:SetText("Locks")
					row.edit:SetWidth(50)
					row.edit:SetScript("OnClick", function() TankMark:ViewLocksForZone(data.label) end)
				else
					TankMark:SetIconTexture(row.icon, data.mark)
					row.icon:Show()
					local c = (data.type=="CC") and "|cff00ccff" or "|cffffffff"
					if data.mark == 0 then c = "|cff888888" end
					row.text:SetText("|cff888888[" .. data.prio .. "]|r " .. c .. data.name .. "|r")
					row.del:Show()
					row.del:SetText("X")
					row.del:SetWidth(20)
					row.del:SetScript("OnClick", function() TankMark:RequestDeleteMob(zone, data.name) end)
					row.edit:Show()
					row.edit:SetText("E")
					row.edit:SetWidth(20)
					row.edit:SetScript("OnClick", function()
						TankMark.editMob:SetText(data.name)
						TankMark.editPrio:SetText(data.prio)
						TankMark.selectedIcon = data.mark
						TankMark.selectedClass = data.class
						TankMark:UpdateClassButton()
						if TankMark.iconBtn then TankMark:SetIconTexture(TankMark.iconBtn.tex, data.mark) end
						TankMark.saveBtn:SetText("Update")
						TankMark.saveBtn:Enable()
						TankMark.cancelBtn:Show()
						TankMark.lockBtn:Disable()
					end)
				end
				row:Show()
			else
				row:Hide()
			end
		end
	end
end

-- ==========================================================
-- SAVE FORM DATA
-- ==========================================================

function TankMark:SaveFormData()
	local zone
	if TankMark.editingLockGUID and TankMark.lockViewZone then
		zone = TankMark.lockViewZone
	else
		zone = TankMark.zoneDropDown and UIDropDownMenu_GetText(TankMark.zoneDropDown) or ""
	end
	
	if zone == "Manage Saved Zones" then
		TankMark:Print("|cffff0000Error:|r Select a valid zone.")
		return
	end
	
	local rawMob = TankMark.editMob:GetText()
	local mob = _gsub(rawMob, ";", "")
	local prio = tonumber(TankMark.editPrio:GetText()) or 1
	local icon = TankMark.selectedIcon
	local classReq = TankMark.selectedClass
	
	if zone == "" or mob == "" or mob == "Mob Name" then return end
	
	if not TankMarkDB.Zones[zone] then TankMarkDB.Zones[zone] = {} end
	
	-- Handle GUID lock updates
	if TankMark.editingLockGUID then
		if not TankMarkDB.StaticGUIDs[zone] then TankMarkDB.StaticGUIDs[zone] = {} end
		TankMarkDB.StaticGUIDs[zone][TankMark.editingLockGUID] = { mark = icon, name = mob }
		TankMark:Print("|cff00ff00Updated:|r Lock for " .. mob)
		TankMark:ResetEditor()
		TankMark:UpdateMobList()
		return
	end
	
	-- Handle new GUID lock
	if TankMark.isLockActive then
		local exists, guid = UnitExists("target")
		if exists and guid and not UnitIsPlayer("target") and UnitName("target") == mob then
			if not TankMarkDB.StaticGUIDs[zone] then TankMarkDB.StaticGUIDs[zone] = {} end
			TankMarkDB.StaticGUIDs[zone][guid] = { mark = icon, name = mob }
			TankMark:Print("|cff00ff00LOCKED GUID|r for: " .. mob)
		else
			TankMark:Print("|cffff0000Error:|r Target lost or name mismatch. Lock failed.")
			return
		end
	end
	
	-- Save mob entry
	local mobType = classReq and "CC" or "KILL"
	TankMarkDB.Zones[zone][mob] = {
		prio = prio,
		mark = icon,
		class = classReq,
		type = mobType
	}
	
	TankMark:Print("|cff00ff00Saved:|r " .. mob .. " |cff888888(P" .. prio .. ", Mark: " .. icon .. ")|r")
	TankMark:ResetEditor()
	TankMark.isZoneListMode = false
	TankMark:UpdateMobList()
end

-- ==========================================================
-- POPUP ACTIONS
-- ==========================================================

function TankMark:RequestDeleteMob(zone, mob)
	TankMark.pendingWipeAction = function()
		if TankMarkDB.Zones[zone] then
			TankMarkDB.Zones[zone][mob] = nil
			TankMark:UpdateMobList()
			TankMark:Print("|cffff0000Removed:|r " .. mob)
		end
	end
	StaticPopup_Show("TANKMARK_WIPE_CONFIRM", "Delete mob from database?\n\n|cffff0000" .. mob .. "|r")
end

function TankMark:RequestDeleteLock(guid, name)
	local z = TankMark.lockViewZone
	TankMark.pendingWipeAction = function()
		if z and TankMarkDB.StaticGUIDs[z] then
			TankMarkDB.StaticGUIDs[z][guid] = nil
			TankMark:UpdateMobList()
			TankMark:Print("|cffff0000Removed:|r Lock for " .. (name or "GUID"))
		end
	end
	StaticPopup_Show("TANKMARK_WIPE_CONFIRM", "Remove GUID lock?\n\n|cffff0000" .. (name or "Unknown") .. "|r")
end

function TankMark:RequestDeleteZone(zoneName)
	TankMark.pendingWipeAction = function()
		TankMarkDB.Zones[zoneName] = nil
		TankMarkDB.StaticGUIDs[zoneName] = nil
		TankMark:Print("|cffff0000Deleted:|r Zone '" .. zoneName .. "'")
		TankMark:UpdateMobList()
	end
	StaticPopup_Show("TANKMARK_WIPE_CONFIRM", "Delete ENTIRE zone and all its data?\n\n|cffff0000" .. zoneName .. "|r")
end

-- ==========================================================
-- ADD CURRENT ZONE DIALOG
-- ==========================================================

function TankMark:ShowAddCurrentZoneDialog()
	local currentZone = GetRealZoneText()
	
	-- Check if zone already exists
	if TankMarkDB.Zones[currentZone] then
		TankMark:Print("|cffffaa00Notice:|r Zone '" .. currentZone .. "' already exists in database.")
		return
	end
	
	StaticPopupDialogs["TANKMARK_ADD_ZONE"] = {
		text = "Add current zone to database?\n\n|cff00ff00" .. currentZone .. "|r",
		button1 = "Add",
		button2 = "Cancel",
		OnAccept = function()
			TankMarkDB.Zones[currentZone] = {}
			TankMark:Print("|cff00ff00Added:|r Zone '" .. currentZone .. "' to database.")
			UIDropDownMenu_SetText(currentZone, TankMark.zoneDropDown)
			if TankMark.isZoneListMode then
				TankMark:ToggleZoneBrowser()
			end
			TankMark:UpdateMobList()
		end,
		timeout = 0,
		whileDead = 1,
		hideOnEscape = 1,
		exclusive = 1,
	}
	StaticPopup_Show("TANKMARK_ADD_ZONE")
end

-- ==========================================================
-- MENUS
-- ==========================================================

function TankMark:InitIconMenu()
	local iconNames = {
		[8] = "|cffffffffSkull|r",
		[7] = "|cffff0000Cross|r",
		[6] = "|cff00ccffSquare|r",
		[5] = "|cffaabbccMoon|r",
		[4] = "|cff00ff00Triangle|r",
		[3] = "|cffff00ffDiamond|r",
		[2] = "|cffffaa00Circle|r",
		[1] = "|cffffff00Star|r",
		[0] = "|cff888888Disabled (Ignore)|r"
	}
	for i = 8, 0, -1 do
		local capturedIcon = i
		local info = {}
		info.text = iconNames[i]
		info.func = function()
			TankMark.selectedIcon = capturedIcon
			if TankMark.iconBtn and TankMark.iconBtn.tex then
				TankMark:SetIconTexture(TankMark.iconBtn.tex, TankMark.selectedIcon)
				TankMark:UpdateClassButton()
			end
			CloseDropDownMenus()
		end
		info.checked = (TankMark.selectedIcon == i)
		UIDropDownMenu_AddButton(info)
	end
end

function TankMark:InitClassMenu()
	local info = {}
	
	info = {
		text = "|cff888888IGNORE (Do Not Mark)|r",
		func = function()
			TankMark.selectedClass = nil
			TankMark:UpdateClassButton()
			TankMark.classBtn:SetText("IGNORED")
			TankMark.classBtn:SetTextColor(0.5, 0.5, 0.5)
			TankMark:ApplySmartDefaults("IGNORE")
		end
	}
	UIDropDownMenu_AddButton(info)
	
	info = {
		text = "|cffffffffNo CC (Kill Target)|r",
		func = function()
			TankMark.selectedClass = nil
			TankMark:UpdateClassButton()
			TankMark:ApplySmartDefaults("KILL")
		end
	}
	UIDropDownMenu_AddButton(info)
	
	if TankMark.detectedCreatureType and CC_MAP[TankMark.detectedCreatureType] then
		info = { text = "--- Recommended ---", isTitle = 1 }
		UIDropDownMenu_AddButton(info)
		for _, class in _ipairs(CC_MAP[TankMark.detectedCreatureType]) do
			local capturedClass = class
			info = {
				text = "|cff00ff00" .. capturedClass .. "|r",
				func = function()
					TankMark.selectedClass = capturedClass
					TankMark:UpdateClassButton()
					TankMark:ApplySmartDefaults(capturedClass)
				end
			}
			UIDropDownMenu_AddButton(info)
		end
	end
	
	info = { text = "--- All Classes ---", isTitle = 1 }
	UIDropDownMenu_AddButton(info)
	for _, class in _ipairs(ALL_CLASSES) do
		local capturedClass = class
		info = {
			text = capturedClass,
			func = function()
				TankMark.selectedClass = capturedClass
				TankMark:UpdateClassButton()
				TankMark:ApplySmartDefaults(capturedClass)
			end
		}
		UIDropDownMenu_AddButton(info)
	end
end

-- ==========================================================
-- TAB CONSTRUCTION
-- ==========================================================

function TankMark:CreateMobTab(parent)
	local t1 = CreateFrame("Frame", nil, parent)
	t1:SetPoint("TOPLEFT", parent, "TOPLEFT", 15, -40)
	t1:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -15, 50)
	
	-- Zone Dropdown
	local drop = CreateFrame("Frame", "TMZoneDropDown", t1, "UIDropDownMenuTemplate")
	drop:SetPoint("TOPLEFT", 0, -10)
	UIDropDownMenu_SetWidth(150, drop)
	UIDropDownMenu_Initialize(drop, function()
		local curr = GetRealZoneText()
		local info = {}
		info.text = curr
		info.func = function()
			UIDropDownMenu_SetSelectedID(drop, this:GetID())
			TankMark:UpdateMobList()
		end
		UIDropDownMenu_AddButton(info)
		for zName, _ in _pairs(TankMarkDB.Zones) do
			if zName ~= curr then
				info = {}
				info.text = zName
				info.func = function()
					UIDropDownMenu_SetSelectedID(drop, this:GetID())
					TankMark:UpdateMobList()
				end
				UIDropDownMenu_AddButton(info)
			end
		end
	end)
	UIDropDownMenu_SetText(GetRealZoneText(), drop)
	TankMark.zoneDropDown = drop
	
	-- Manage Zones Checkbox
	local mzCheck = CreateFrame("CheckButton", "TM_ManageZonesCheck", t1, "UICheckButtonTemplate")
	mzCheck:SetWidth(24)
	mzCheck:SetHeight(24)
	mzCheck:SetPoint("LEFT", drop, "RIGHT", 10, 2)
	_G[mzCheck:GetName().."Text"]:SetText("Manage Zones")
	mzCheck:SetScript("OnClick", function()
		TankMark:ToggleZoneBrowser()
		PlaySound("igMainMenuOptionCheckBoxOn")
	end)
	TankMark.zoneModeCheck = mzCheck
	
	-- Add Zone Button
	local addZoneBtn = CreateFrame("Button", "TMAddZoneBtn", t1, "UIPanelButtonTemplate")
	addZoneBtn:SetWidth(80)
	addZoneBtn:SetHeight(24)
	addZoneBtn:SetPoint("TOPLEFT", drop, "TOPRIGHT", 130, -2)
	addZoneBtn:SetText("Add Zone")
	addZoneBtn:SetScript("OnClick", function()
		TankMark:ShowAddCurrentZoneDialog()
	end)
	
	-- Mob List Scroll Frame
	local sf = CreateFrame("ScrollFrame", "TankMarkScrollFrame", t1, "FauxScrollFrameTemplate")
	sf:SetPoint("TOPLEFT", 10, -50)
	sf:SetWidth(380)
	sf:SetHeight(200)
	local listBg = CreateFrame("Frame", nil, t1)
	listBg:SetPoint("TOPLEFT", sf, -5, 5)
	listBg:SetPoint("BOTTOMRIGHT", sf, 25, -5)
	listBg:SetBackdrop({
		bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true,
		tileSize = 16,
		edgeSize = 16,
		insets = { left = 4, right = 4, top = 4, bottom = 4 }
	})
	listBg:SetBackdropColor(0, 0, 0, 0.5)
	sf:SetScript("OnVerticalScroll", function()
		FauxScrollFrame_OnVerticalScroll(22, function() TankMark:UpdateMobList() end)
	end)
	TankMark.scrollFrame = sf
	
	-- Mob Rows
	for i = 1, 9 do
		local row = CreateFrame("Button", "TMMobRow"..i, t1)
		row:SetWidth(380)
		row:SetHeight(22)
		row:SetPoint("TOPLEFT", 10, -50 - ((i-1)*22))
		row.icon = row:CreateTexture(nil, "ARTWORK")
		row.icon:SetWidth(18)
		row.icon:SetHeight(18)
		row.icon:SetPoint("LEFT", 0, 0)
		row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		row.text:SetPoint("LEFT", row.icon, "RIGHT", 5, 0)
		row.del = CreateFrame("Button", "TMMobRowDel"..i, row, "UIPanelButtonTemplate")
		row.del:SetWidth(20)
		row.del:SetHeight(18)
		row.del:SetPoint("RIGHT", -5, 0)
		row.del:SetText("X")
		row.edit = CreateFrame("Button", "TMMobRowEdit"..i, row, "UIPanelButtonTemplate")
		row.edit:SetWidth(20)
		row.edit:SetHeight(18)
		row.edit:SetPoint("RIGHT", row.del, "LEFT", -2, 0)
		row.edit:SetText("E")
		row:Hide()
		TankMark.mobRows[i] = row
	end
	
	-- Search Box
	local searchLabel = t1:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	searchLabel:SetPoint("TOPLEFT", listBg, "BOTTOMLEFT", 5, -8)
	searchLabel:SetText("Search:")
	local sBox = TankMark:CreateEditBox(t1, "", 150)
	sBox:SetPoint("LEFT", searchLabel, "RIGHT", 8, 0)
	sBox:SetScript("OnTextChanged", function() TankMark:UpdateMobList() end)
	TankMark.searchBox = sBox
	local sClear = CreateFrame("Button", "TMBSearchClear", sBox, "UIPanelCloseButton")
	sClear:SetWidth(20)
	sClear:SetHeight(20)
	sClear:SetPoint("LEFT", sBox, "RIGHT", 2, 0)
	sClear:SetScript("OnClick", function()
		sBox:SetText("")
		sBox:ClearFocus()
		TankMark:UpdateMobList()
	end)
	
	-- Add/Edit Form
	local addGroup = CreateFrame("Frame", nil, t1)
	addGroup:SetPoint("BOTTOMLEFT", 10, 0)
	addGroup:SetWidth(400)
	addGroup:SetHeight(90)
	local div = addGroup:CreateTexture(nil, "ARTWORK")
	div:SetHeight(1)
	div:SetWidth(380)
	div:SetPoint("TOP", 0, 0)
	div:SetTexture(1, 1, 1, 0.2)
	
	-- Mob Name Input
	local nameBox = TankMark:CreateEditBox(addGroup, "Mob Name", 200)
	nameBox:SetPoint("TOPLEFT", 0, -30)
	TankMark.editMob = nameBox
	nameBox:SetScript("OnTextChanged", function()
		local text = this:GetText()
		if text and text ~= "" then
			if TankMark.saveBtn then TankMark.saveBtn:Enable() end
		else
			if TankMark.saveBtn then TankMark.saveBtn:Disable() end
		end
	end)
	
	-- Target Button
	local targetBtn = CreateFrame("Button", "TMTargetBtn", addGroup, "UIPanelButtonTemplate")
	targetBtn:SetWidth(60)
	targetBtn:SetHeight(20)
	targetBtn:SetPoint("LEFT", nameBox, "RIGHT", 5, 0)
	targetBtn:SetText("Target")
	targetBtn:SetScript("OnClick", function()
		if UnitExists("target") then
			nameBox:SetText(UnitName("target"))
			TankMark.detectedCreatureType = UnitCreatureType("target")
			local currentIcon = GetRaidTargetIndex("target")
			if currentIcon then
				TankMark.selectedIcon = currentIcon
				if TankMark.iconBtn and TankMark.iconBtn.tex then
					TankMark:SetIconTexture(TankMark.iconBtn.tex, currentIcon)
				end
			end
			if TankMark.lockBtn then TankMark.lockBtn:Enable() end
			if TankMark.saveBtn then TankMark.saveBtn:Enable() end
		end
	end)
	
	-- Class Button
	local cBtn = CreateFrame("Button", "TMClassBtn", addGroup, "UIPanelButtonTemplate")
	cBtn:SetWidth(100)
	cBtn:SetHeight(24)
	cBtn:SetPoint("TOPLEFT", 0, -65)
	cBtn:SetText("No CC (Kill)")
	local cDrop = CreateFrame("Frame", "TMClassDropDown", cBtn, "UIDropDownMenuTemplate")
	UIDropDownMenu_Initialize(cDrop, function() TankMark:InitClassMenu() end, "MENU")
	cBtn:SetScript("OnClick", function()
		ToggleDropDownMenu(1, nil, cDrop, "cursor", 0, 0)
	end)
	TankMark.classBtn = cBtn
	
	-- Icon Selector
	local iconSel = CreateFrame("Button", nil, addGroup)
	iconSel:SetWidth(24)
	iconSel:SetHeight(24)
	iconSel:SetPoint("LEFT", cBtn, "RIGHT", 10, 0)
	local iconTex = iconSel:CreateTexture(nil, "ARTWORK")
	iconTex:SetAllPoints()
	iconSel.tex = iconTex
	iconTex:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
	TankMark:SetIconTexture(iconTex, TankMark.selectedIcon)
	local iconDrop = CreateFrame("Frame", "TMIconDropDown", iconSel, "UIDropDownMenuTemplate")
	UIDropDownMenu_Initialize(iconDrop, function() TankMark:InitIconMenu() end, "MENU")
	iconSel:SetScript("OnClick", function()
		ToggleDropDownMenu(1, nil, iconDrop, "cursor", 0, 0)
	end)
	TankMark.iconBtn = iconSel
	
	-- Priority Input
	local prioBox = TankMark:CreateEditBox(addGroup, "Prio", 25)
	prioBox:SetPoint("LEFT", iconSel, "RIGHT", 10, 0)
	prioBox:SetText("1")
	prioBox:SetNumeric(true)
	TankMark.editPrio = prioBox
	
	-- Lock Button
	local lBtn = CreateFrame("Button", "TMLockBtn", addGroup, "UIPanelButtonTemplate")
	lBtn:SetWidth(75)
	lBtn:SetHeight(24)
	lBtn:SetPoint("LEFT", prioBox, "RIGHT", 10, 0)
	lBtn:SetText("Lock Mark")
	lBtn:SetScript("OnClick", function() TankMark:ToggleLockState() end)
	lBtn:Disable()
	TankMark.lockBtn = lBtn
	
	-- Save Button
	local saveBtn = CreateFrame("Button", "TMSaveBtn", addGroup, "UIPanelButtonTemplate")
	saveBtn:SetWidth(50)
	saveBtn:SetHeight(24)
	saveBtn:SetPoint("LEFT", lBtn, "RIGHT", 5, 0)
	saveBtn:SetText("Save")
	saveBtn:SetScript("OnClick", function() TankMark:SaveFormData() end)
	saveBtn:Disable()
	TankMark.saveBtn = saveBtn
	
	-- Cancel Button
	local cancelBtn = CreateFrame("Button", "TMCancelBtn", addGroup, "UIPanelButtonTemplate")
	cancelBtn:SetWidth(20)
	cancelBtn:SetHeight(24)
	cancelBtn:SetPoint("LEFT", saveBtn, "RIGHT", 2, 0)
	cancelBtn:SetText("X")
	cancelBtn:SetScript("OnClick", function() TankMark:ResetEditor() end)
	cancelBtn:Hide()
	TankMark.cancelBtn = cancelBtn
	
	return t1
end
