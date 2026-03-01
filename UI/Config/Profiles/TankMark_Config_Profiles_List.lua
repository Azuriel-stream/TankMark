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
-- MAIN LIST RENDERER
-- ==========================================================

function TankMark:UpdateProfileList()
	if not TankMark.profileScroll then return end

	local list     = TankMark.profileCache
	local numItems = L._tgetn(list)
	local MAX_ROWS = 6

	FauxScrollFrame_Update(TankMark.profileScroll, numItems, MAX_ROWS, 44)
	local offset = FauxScrollFrame_GetOffset(TankMark.profileScroll)

	for i = 1, MAX_ROWS do
		local index = offset + i
		local row   = TankMark.profileRows[i]

		if index <= numItems then
			local data  = list[index]
			row.index   = index

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

	-- Update the visual text on the dropdown button.
	-- LoadProfileToCache() reads this text via UIDropDownMenu_GetText,
	-- so the text must be set before that call.
	UIDropDownMenu_SetText(zone, TankMark.profileZoneDropdown)

	if TankMark.LoadProfileToCache then
		TankMark:LoadProfileToCache()
	end

	if TankMark.UpdateProfileList then
		TankMark:UpdateProfileList()
	end
end