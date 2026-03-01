-- TankMark: v0.27
-- File: TankMark_Config_Profiles_List.lua
-- List rendering and UI sync for Team Profiles tab

if not TankMark then return end

-- ==========================================================
-- LOCALIZATIONS
-- ==========================================================

local L = TankMark.Locals

-- ==========================================================
-- ICON DROPDOWN MENU
-- ==========================================================

function TankMark:InitProfileIconMenu(parentFrame, dataIndex)
	if not dataIndex or not TankMark.profileCache[dataIndex] then return end
	local info
	local iconNames = {
		[8] = "Skull",
		[7] = "Cross",
		[6] = "Square",
		[5] = "Moon",
		[4] = "Triangle",
		[3] = "Diamond",
		[2] = "Circle",
		[1] = "Star"
	}

	for i = 8, 1, -1 do
		local capturedIcon = i
		info = {}
		info.text = iconNames[capturedIcon]
		info.func = function()
			if TankMark.profileCache[dataIndex] then
				TankMark.profileCache[dataIndex].mark = capturedIcon
				TankMark:UpdateProfileList()
			end
		end
		if TankMark.profileCache[dataIndex].mark == capturedIcon then
			info.checked = 1
		end
		UIDropDownMenu_AddButton(info)
	end
end

-- ==========================================================
-- [v0.27] ZONE BROWSER ROW RENDERER
-- ==========================================================

-- Renders a single row in zone browser mode.
-- Shows zone name + mark count on the left and a Delete button on the right.
-- All normal-mode edit widgets are hidden for the duration.
local function RenderZoneBrowserRow(row, zoneName, markCount)
	-- Hide ALL normal-mode widgets
	if row.iconTex  then row.iconTex:SetTexture("")  end
	if row.tankEdit then row.tankEdit:Hide()          end
	if row.tankBtn  then row.tankBtn:Hide()           end
	if row.healEdit then row.healEdit:Hide()          end
	if row.healBtn  then row.healBtn:Hide()           end
	if row.warnIcon then row.warnIcon:Hide()          end
	if row.ccCheck  then row.ccCheck:Hide()           end

	-- Zone label
	local countStr = " |cff888888(" .. markCount .. " marks)|r"
	row.zoneLabel:SetText("|cffffd200" .. zoneName .. "|r" .. countStr)
	row.zoneLabel:Show()

	-- Wire Delete button to zone deletion.
	-- Width and text are identical to normal mode — no resizing needed.
	local capturedZone = zoneName
	row.del:SetScript("OnClick", function()
		TankMark:RequestDeleteProfileZone(capturedZone)
	end)
	row.del:Show()
end

-- Restore all normal-mode widgets after leaving zone browser mode.
local function ShowNormalRowWidgets(row)
	if row.tankEdit then row.tankEdit:Show() end
	if row.tankBtn  then row.tankBtn:Show()  end
	if row.healEdit then row.healEdit:Show() end
	if row.healBtn  then row.healBtn:Show()  end
	if row.ccCheck  then row.ccCheck:Show()  end
	-- warnIcon visibility is managed by UpdateProfileList based on data
	row.zoneLabel:Hide()
	-- Restore delete button OnClick to normal-mode behaviour.
	-- No size or text change needed — button is permanently width 55 / text "X".
	row.del:SetScript("OnClick", function()
		TankMark:ProfileDeleteRow(row.index)
	end)
end

-- ==========================================================
-- MAIN LIST RENDERER
-- ==========================================================

function TankMark:UpdateProfileList()
	if not TankMark.profileScroll then return end

	local MAX_ROWS = 6

	-- -------------------------------------------------------
	-- ZONE BROWSER MODE
	-- -------------------------------------------------------
	if TankMark.isProfileZoneListMode then
		-- Build sorted zone list from TankMarkProfileDB
		local zoneList = {}
		for zoneName, profile in L._pairs(TankMarkProfileDB) do
			if L._type(profile) == "table" then
				L._tinsert(zoneList, {
					name      = zoneName,
					markCount = L._tgetn(profile),
				})
			end
		end
		L._tsort(zoneList, function(a, b) return a.name < b.name end)

		local numZones = L._tgetn(zoneList)
		FauxScrollFrame_Update(TankMark.profileScroll, numZones, MAX_ROWS, 44)
		local offset = FauxScrollFrame_GetOffset(TankMark.profileScroll)

		for i = 1, MAX_ROWS do
			local dataIndex = offset + i
			local row       = TankMark.profileRows[i]
			if not row then break end

			if dataIndex <= numZones then
				local entry = zoneList[dataIndex]
				row.index   = nil
				RenderZoneBrowserRow(row, entry.name, entry.markCount)
				row:Show()
			else
				row:Hide()
			end
		end

		-- Hide overflow rows
		for i = MAX_ROWS + 1, 8 do
			if TankMark.profileRows[i] then
				TankMark.profileRows[i]:Hide()
			end
		end

		-- Disable Add Mark while in zone browser mode
		if TankMark.profileAddBtn then
			TankMark.profileAddBtn:Disable()
		end

		return
	end

	-- -------------------------------------------------------
	-- NORMAL MODE
	-- -------------------------------------------------------
	local list     = TankMark.profileCache
	local numItems = L._tgetn(list)

	FauxScrollFrame_Update(TankMark.profileScroll, numItems, MAX_ROWS, 44)
	local offset = FauxScrollFrame_GetOffset(TankMark.profileScroll)

	for i = 1, MAX_ROWS do
		local index = offset + i
		local row   = TankMark.profileRows[i]

		if index <= numItems then
			local data  = list[index]
			row.index   = index

			-- Restore normal-mode widgets (guards against returning from zone browser)
			ShowNormalRowWidgets(row)

			TankMark:SetIconTexture(row.iconTex, data.mark)
			row.tankEdit:SetText(data.tank or "")
			row.healEdit:SetText(data.healers or "")

			-- CC checkbox state
			if row.ccCheck then
				if data.role == "CC" then
					row.ccCheck:SetChecked(true)
				else
					row.ccCheck:SetChecked(false)
				end
			end

			-- Roster validation color on tank name
			if data.tank and data.tank ~= "" then
				if TankMark:IsPlayerInRaid(data.tank) then
					row.tankEdit:SetTextColor(1, 1, 1)       -- white  (in raid)
				else
					row.tankEdit:SetTextColor(1, 0, 0)       -- red    (not in raid)
				end
			else
				row.tankEdit:SetTextColor(0.7, 0.7, 0.7)    -- gray   (empty)
			end

			-- Warning icon for offline healers
			if row.warnIcon then
				local showWarning = false
				if data.healers and data.healers ~= "" then
					for healerName in L._gfind(data.healers, "[^ ]+") do
						if not TankMark:IsPlayerInRaid(healerName) then
							showWarning = true
							break
						end
					end
				end
				if showWarning then
					row.warnIcon:Show()
				else
					row.warnIcon:Hide()
				end
			end

			row.del:Show()
			row:Show()
		else
			row.index = nil
			row:Hide()
		end
	end

	-- Hide any rows beyond MAX_ROWS (safety for pool size 8)
	for i = MAX_ROWS + 1, 8 do
		if TankMark.profileRows[i] then
			TankMark.profileRows[i]:Hide()
		end
	end

	-- "Add Mark" button state (hard cap: 8 marks)
	if TankMark.profileAddBtn then
		if numItems >= 8 then
			TankMark.profileAddBtn:Disable()
		else
			TankMark.profileAddBtn:Enable()
		end
	end
end

-- ==========================================================
-- ZONE DROPDOWN SYNC
-- ==========================================================

function TankMark:UpdateProfileZoneUI(zone)
	if not TankMark.profileZoneDropdown then return end

	UIDropDownMenu_SetText(zone, TankMark.profileZoneDropdown)

	if TankMark.LoadProfileToCache then
		TankMark:LoadProfileToCache()
	end

	if TankMark.UpdateProfileList then
		TankMark:UpdateProfileList()
	end
end