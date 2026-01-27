-- TankMark: v0.23
-- File: TankMark_Config_Mobs_List.lua
-- Mob list rendering and data management

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

-- ==========================================================
-- MOB LIST DATA BUILDER
-- ==========================================================

-- Build the list data based on current mode (zone list, lock view, or normal mob list)
local function BuildListData(db, zone, filter)
	local listData = {}

	-- Lock view for specific zone
	if TankMark.isZoneListMode and TankMark.lockViewZone then
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

	-- Zone list mode
	elseif TankMark.isZoneListMode then
		for zoneName, _ in _pairs(db.Zones) do
			if filter == "" or _strfind(_lower(zoneName), filter, 1, true) then
				local locks = 0
				if db.StaticGUIDs[zoneName] then
					for k,v in _pairs(db.StaticGUIDs[zoneName]) do
						locks = locks + 1
					end
				end
				_insert(listData, { label = zoneName, type = "ZONE", lockCount = locks })
			end
		end

		_sort(listData, function(a,b) return a.label < b.label end)

	-- Normal mob list for selected zone
	else
		local mobsData = db.Zones[zone] or {}
		for name, info in _pairs(mobsData) do
			if filter == "" or _strfind(_lower(name), filter, 1, true) then
				-- [v0.23] Extract first mark from array for display
				local displayMark = info.marks and info.marks[1] or 8
				local isSequential = info.marks and _getn(info.marks) > 1

				_insert(listData, {
					name=name,
					prio=info.prio,
					mark=displayMark,
					marks=info.marks, -- Keep full array for editing
					type=info.type,
					class=info.class,
					isSequential=isSequential
				})
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

	return listData
end

-- ==========================================================
-- ROW RENDERING HELPERS
-- ==========================================================

-- Render "Back to Zones" button
local function RenderBackButton(row, data)
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
end

-- Render GUID lock row
local function RenderLockRow(row, data)
	TankMark:SetIconTexture(row.icon, data.mark)
	row.icon:Show()
	row.text:SetText(data.name .. " |cff888888(" .. string.sub(data.guid, -6) .. ")|r")

	row.del:Show()
	row.del:SetText("X")
	row.del:SetWidth(20)
	row.del:SetScript("OnClick", function()
		TankMark:RequestDeleteLock(data.guid, data.name)
	end)

	row.edit:Show()
	row.edit:SetText("E")
	row.edit:SetWidth(20)
	row.edit:SetScript("OnClick", function()
		TankMark.editMob:SetText(data.name or "Unknown")
		TankMark.selectedIcon = data.mark
		TankMark.editingLockGUID = data.guid
		TankMark.selectedClass = nil
		TankMark:UpdateClassButton()

		if TankMark.iconBtn then
			TankMark:SetIconTexture(TankMark.iconBtn.tex, data.mark)
		end

		TankMark.saveBtn:SetText("Update")
		TankMark.saveBtn:Enable()
		TankMark.cancelBtn:Show()
		TankMark.lockBtn:Disable()
		TankMark.lockBtn:SetText("Locked")

		-- Ensure accordion is expanded when editing
		if not TankMark.isAddMobExpanded then
			if TankMark.addMobHeader then
				TankMark.addMobInterface:Show()
				TankMark.addMobHeader.arrow:SetTexture("Interface\\Buttons\\UI-MinusButton-Up")
				TankMark.isAddMobExpanded = true
			end
		end
	end)
end

-- Render zone row (in zone browser mode)
local function RenderZoneRow(row, data)
	local info = (data.lockCount > 0) and (" |cff00ff00(" .. data.lockCount .. " locks)|r") or ""
	row.text:SetText("|cffffd200" .. data.label .. "|r" .. info)

	row.del:Show()
	row.del:SetText("|cffff0000Delete|r")
	row.del:SetWidth(60)
	row.del:SetScript("OnClick", function()
		TankMark:RequestDeleteZone(data.label)
	end)

	row.edit:Show()
	row.edit:SetText("Locks")
	row.edit:SetWidth(50)
	row.edit:SetScript("OnClick", function()
		TankMark:ViewLocksForZone(data.label)
	end)
end

-- Render normal mob row
local function RenderMobRow(row, data, zone)
	TankMark:SetIconTexture(row.icon, data.mark)
	row.icon:Show()

	local c = (data.type=="CC") and "|cff00ccff" or "|cffffffff"

	-- [v0.23] Check if first mark is IGNORE (0)
	local firstMark = data.marks and data.marks[1] or 8
	if firstMark == 0 then
		c = "|cff888888"
	end

	-- [v0.23] Show indicator for sequential mobs
	local seqIndicator = data.isSequential and " |cffffaa00[SEQ]|r" or ""
	row.text:SetText("|cff888888[" .. data.prio .. "]|r " .. c .. data.name .. "|r" .. seqIndicator)

	row.del:Show()
	row.del:SetText("X")
	row.del:SetWidth(20)
	row.del:SetScript("OnClick", function()
		TankMark:RequestDeleteMob(zone, data.name)
	end)

	row.edit:Show()
	row.edit:SetText("E")
	row.edit:SetWidth(20)
	row.edit:SetScript("OnClick", function()
		-- Populate main row
		TankMark.editMob:SetText(data.name)
		TankMark.editPrio:SetText(data.prio)
		TankMark.selectedIcon = data.mark
		TankMark.selectedClass = data.class
		TankMark:UpdateClassButton()

		if TankMark.iconBtn then
			TankMark:SetIconTexture(TankMark.iconBtn.tex, data.mark)
		end

		-- [v0.23] Populate sequential marks (skip first mark as it's the main row)
		TankMark.editingSequentialMarks = {}
		if data.marks and _getn(data.marks) > 1 then
			for i = 2, _getn(data.marks) do
				_insert(TankMark.editingSequentialMarks, {
					icon = data.marks[i],
					class = data.class, -- Share class (can be changed per row)
					type = data.type
				})
			end

			TankMark:RefreshSequentialRows()

			-- Show '+ Add More Marks' text
			if TankMark.addMoreMarksText then
				TankMark.addMoreMarksText:Show()
			end

			-- Disable Lock button when sequential marks exist
			if TankMark.lockBtn then
				TankMark.lockBtn:Disable()
				TankMark.lockBtn:SetText("|cff888888Lock Mark|r")
			end
		else
			TankMark:RefreshSequentialRows()
		end

		-- Update UI state
		TankMark.saveBtn:SetText("Update")
		TankMark.saveBtn:Enable()
		TankMark.cancelBtn:Show()

		-- Check GUID lock conflict
		if TankMark:HasGUIDLockForMobName(data.name) then
			if TankMark.addMoreMarksText then
				TankMark.addMoreMarksText:SetTextColor(0.5, 0.5, 0.5)
			end

			-- Disable the button
			if TankMark.addMoreMarksText.clickFrame then
				TankMark.addMoreMarksText.clickFrame:Disable()
			end
		else
			if TankMark.addMoreMarksText then
				TankMark.addMoreMarksText:SetTextColor(0, 0.8, 1)
			end

			-- Enable the button
			if TankMark.addMoreMarksText.clickFrame then
				TankMark.addMoreMarksText.clickFrame:Enable()
			end
		end

		if not TankMark.editingLockGUID and TankMark.lockBtn then
			TankMark.lockBtn:Enable()
		end

		-- Ensure accordion is expanded when editing
		if not TankMark.isAddMobExpanded then
			if TankMark.addMobHeader and TankMark.addMobInterface then
				TankMark.addMobInterface:Show()
				TankMark.addMobHeader.arrow:SetTexture("Interface\\Buttons\\UI-MinusButton-Up")
				TankMark.isAddMobExpanded = true
			end
		end
	end)
end

-- ==========================================================
-- MAIN UPDATE FUNCTION
-- ==========================================================

-- Update the mob list display (called on filter change, zone change, etc.)
function TankMark:UpdateMobList()
	if not TankMark.optionsFrame or not TankMark.optionsFrame:IsVisible() then return end
	if not TankMarkDB then TankMarkDB = {} end

	local db = TankMarkDB
	local zone = UIDropDownMenu_GetText(TankMark.zoneDropDown) or GetRealZoneText()
	local filter = ""

	if TankMark.searchBox then
		local searchText = TankMark.searchBox:GetText()
        -- Ignore placeholder text
        if searchText ~= "Search Mob Database" then
            filter = _lower(searchText)
        end
	end

	-- Build list data
	local listData = BuildListData(db, zone, filter)

	-- Render list (6 rows)
	local numItems = _getn(listData)
	local MAX_ROWS = 6

	FauxScrollFrame_Update(TankMark.scrollFrame, numItems, MAX_ROWS, 22)
	local offset = FauxScrollFrame_GetOffset(TankMark.scrollFrame)

	for i = 1, MAX_ROWS do
		local index = offset + i
		local row = TankMark.mobRows[i]

		if row then
			if index <= numItems then
				local data = listData[index]

				-- Reset row
				row.icon:Hide()
				row.del:Hide()
				row.edit:Hide()
				row.text:SetTextColor(1, 1, 1)
				row:SetScript("OnClick", nil)

				-- Render based on type
				if data.type == "BACK" then
					RenderBackButton(row, data)
				elseif data.type == "LOCK" then
					RenderLockRow(row, data)
				elseif data.type == "ZONE" then
					RenderZoneRow(row, data)
				else
					RenderMobRow(row, data, zone)
				end

				row:Show()
			else
				row:Hide()
			end
		end
	end
end
