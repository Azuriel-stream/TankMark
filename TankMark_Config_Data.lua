-- TankMark: v0.21

-- File: TankMark_Config_Data.lua

-- [v0.21] Data Management UI - Snapshot restore, default merging, and export/import

if not TankMark then return end

-- ==========================================================
-- LOCALIZATIONS
-- ==========================================================

local _pairs = pairs
local _ipairs = ipairs
local _getn = table.getn
local _insert = table.insert

-- ==========================================================
-- UI STATE
-- ==========================================================

TankMark.selectedSnapshotIndex = nil

-- ==========================================================
-- BUILD DATA MANAGEMENT TAB
-- ==========================================================

function TankMark:BuildDataManagementTab(parent)
	local tab = CreateFrame("Frame", "TMDataTab", parent)
	tab:SetPoint("TOPLEFT", 15, -40)
	tab:SetPoint("BOTTOMRIGHT", -15, 50)
	tab:Hide()

	-- Title
	local title = tab:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("TOP", 0, -20)
	title:SetText("Data Management")

	-- ==========================================================
	-- SECTION 1: SNAPSHOTS
	-- ==========================================================

	local snapshotHeader = tab:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	snapshotHeader:SetPoint("TOPLEFT", tab, "TOPLEFT", 20, -60)
	snapshotHeader:SetText("|cff00ccffSnapshots Available:|r")

	-- Snapshot Dropdown
	local snapshotDrop = CreateFrame("Frame", "TMSnapshotDropDown", tab, "UIDropDownMenuTemplate")
	snapshotDrop:SetPoint("TOPLEFT", snapshotHeader, "BOTTOMLEFT", -15, -10)
	UIDropDownMenu_SetWidth(200, snapshotDrop)

	-- Initialize dropdown
    UIDropDownMenu_Initialize(snapshotDrop, function()
        local info = {}
        for i = 1, 3 do
            local snapshot = TankMarkDB_Snapshot and TankMarkDB_Snapshot[i]
            info = {}
            info.value = i

            if snapshot then
                -- Count mobs
                local mobCount = 0
                for _, mobs in _pairs(snapshot.zones) do
                    for _ in _pairs(mobs) do
                        mobCount = mobCount + 1
                    end
                end

                -- Count zones
                local zoneCount = 0
                for _ in _pairs(snapshot.zones) do
                    zoneCount = zoneCount + 1
                end

                -- Format label
                local ageStr = TankMark:FormatTimestamp(snapshot.timestamp)
                info.text = "Slot " .. i .. ": " .. ageStr .. " (" .. zoneCount .. " zones, " .. mobCount .. " mobs)"
            else
                info.text = "Slot " .. i .. ": |cff888888Empty|r"
            end

            info.func = function()
                TankMark.selectedSnapshotIndex = this.value
                UIDropDownMenu_SetSelectedID(snapshotDrop, this.value)
            end
            info.checked = (TankMark.selectedSnapshotIndex == i)
            UIDropDownMenu_AddButton(info)
        end
    end)

	-- Set default text
	UIDropDownMenu_SetText("Select Snapshot", snapshotDrop)
	TankMark.snapshotDropdown = snapshotDrop

	-- Restore Button
	local restoreBtn = CreateFrame("Button", "TMRestoreBtn", tab, "UIPanelButtonTemplate")
	restoreBtn:SetWidth(120)
	restoreBtn:SetHeight(24)
	restoreBtn:SetPoint("TOPLEFT", snapshotDrop, "BOTTOMLEFT", 15, -10)
	restoreBtn:SetText("Restore Selected")
	restoreBtn:SetScript("OnClick", function()
		if not TankMark.selectedSnapshotIndex then
			TankMark:Print("|cffff0000Error:|r No snapshot selected.")
			return
		end

		-- Confirmation dialog
		StaticPopupDialogs["TANKMARK_RESTORE_CONFIRM"] = {
			text = "Restore snapshot? This will OVERWRITE your current database.",
			button1 = "Restore",
			button2 = "Cancel",
			OnAccept = function()
				TankMark:RestoreFromSnapshot(TankMark.selectedSnapshotIndex)
				TankMark:RefreshSnapshotList()
			end,
			timeout = 0,
			whileDead = 1,
			hideOnEscape = 1,
		}
		StaticPopup_Show("TANKMARK_RESTORE_CONFIRM")
	end)

	-- View Details Button
    local detailsBtn = CreateFrame("Button", "TMDetailsBtn", tab, "UIPanelButtonTemplate")
    detailsBtn:SetWidth(100)
    detailsBtn:SetHeight(24)
    detailsBtn:SetPoint("LEFT", restoreBtn, "RIGHT", 10, 0)
    detailsBtn:SetText("View Details")
    detailsBtn:SetScript("OnClick", function()
        if not TankMark.selectedSnapshotIndex then
            TankMark:Print("|cffff0000Error:|r No snapshot selected.")
            return
        end

        local snapshot = TankMarkDB_Snapshot[TankMark.selectedSnapshotIndex]
        if not snapshot then return end

        -- Count mobs
        local mobCount = 0
        for _, mobs in _pairs(snapshot.zones) do
            for _ in _pairs(mobs) do
                mobCount = mobCount + 1
            end
        end

        -- Count zones
        local zoneCount = 0
        for _ in _pairs(snapshot.zones) do
            zoneCount = zoneCount + 1
        end

        -- Count GUIDs
        local guidCount = 0
        for _, guids in _pairs(snapshot.guids) do
            for _ in _pairs(guids) do
                guidCount = guidCount + 1
            end
        end

        TankMark:Print("=== Snapshot " .. TankMark.selectedSnapshotIndex .. " Details ===")
        TankMark:Print("Age: " .. TankMark:FormatTimestamp(snapshot.timestamp))
        TankMark:Print("Zones: " .. zoneCount)
        TankMark:Print("Mobs: " .. mobCount)
        TankMark:Print("Locked GUIDs: " .. guidCount)
        if snapshot.profile then
            TankMark:Print("Profile: " .. snapshot.profile.zone)
        end
    end)

	-- ==========================================================
	-- SECTION 2: DEFAULT DATABASE
	-- ==========================================================

	local defaultsHeader = tab:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	defaultsHeader:SetPoint("TOPLEFT", restoreBtn, "BOTTOMLEFT", 0, -30)
	defaultsHeader:SetText("|cff00ccffDefault Database:|r")

	local defaultsInfo = tab:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	defaultsInfo:SetPoint("TOPLEFT", defaultsHeader, "BOTTOMLEFT", 0, -10)
	defaultsInfo:SetWidth(400)
	defaultsInfo:SetJustifyH("LEFT")
	defaultsInfo:SetText("Merge baseline mob priorities from curated content (raids/dungeons).\nExisting mobs will NOT be overwritten.")

	-- Merge Defaults Button
	local mergeBtn = CreateFrame("Button", "TMMergeBtn", tab, "UIPanelButtonTemplate")
	mergeBtn:SetWidth(140)
	mergeBtn:SetHeight(24)
	mergeBtn:SetPoint("TOPLEFT", defaultsInfo, "BOTTOMLEFT", 0, -10)
	mergeBtn:SetText("Merge Defaults")
	mergeBtn:SetScript("OnClick", function()
		TankMark:MergeDefaults()
	end)

	-- Replace with Defaults Button
	local replaceBtn = CreateFrame("Button", "TMReplaceBtn", tab, "UIPanelButtonTemplate")
	replaceBtn:SetWidth(140)
	replaceBtn:SetHeight(24)
	replaceBtn:SetPoint("LEFT", mergeBtn, "RIGHT", 10, 0)
	replaceBtn:SetText("Replace with Defaults")
	replaceBtn:SetScript("OnClick", function()
		StaticPopupDialogs["TANKMARK_REPLACE_CONFIRM"] = {
			text = "Replace ALL mob data with defaults? This CANNOT be undone!",
			button1 = "Replace",
			button2 = "Cancel",
			OnAccept = function()
				-- Wipe user DB
				TankMarkDB.Zones = {}
				
				-- Copy all defaults (v0.23 structure)
				for zoneName, defaultMobs in pairs(TankMarkDefaults) do
					TankMarkDB.Zones[zoneName] = {}
					for mobName, mobData in pairs(defaultMobs) do
						-- [v0.23] Deep copy marks array
						local marksCopy = {}
						if mobData.marks then
							for i, mark in ipairs(mobData.marks) do
								marksCopy[i] = mark
							end
						end
						
						TankMarkDB.Zones[zoneName][mobName] = {
							prio = mobData.prio,
							marks = marksCopy,
							type = mobData.type,
							class = mobData.class
						}
					end
				end
				
				TankMark:Print("|cff00ff00Replaced|r Database reset to defaults.")
				
				if TankMark.UpdateMobList then
					TankMark:UpdateMobList()
				end
			end,
			timeout = 0,
			whileDead = 1,
			hideOnEscape = 1,
		}
		StaticPopup_Show("TANKMARK_REPLACE_CONFIRM")
	end)

	-- ==========================================================
	-- SECTION 3: EXPORT/IMPORT
	-- ==========================================================

	local exportHeader = tab:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	exportHeader:SetPoint("TOPLEFT", mergeBtn, "BOTTOMLEFT", 0, -30)
	exportHeader:SetText("|cff00ccffAdvanced:|r")

	-- Export Current Zone Button
	local exportBtn = CreateFrame("Button", "TMExportBtn", tab, "UIPanelButtonTemplate")
	exportBtn:SetWidth(140)
	exportBtn:SetHeight(24)
	exportBtn:SetPoint("TOPLEFT", exportHeader, "BOTTOMLEFT", 0, -10)
	exportBtn:SetText("Export Current Zone")
	exportBtn:SetScript("OnClick", function()
		TankMark:ShowExportDialog()
	end)

	-- Import Zone Data Button
	local importBtn = CreateFrame("Button", "TMImportBtn", tab, "UIPanelButtonTemplate")
	importBtn:SetWidth(140)
	importBtn:SetHeight(24)
	importBtn:SetPoint("LEFT", exportBtn, "RIGHT", 10, 0)
	importBtn:SetText("Import Zone Data")
	importBtn:SetScript("OnClick", function()
		TankMark:ShowImportDialog()
	end)

	-- Manual Snapshot Button
	local manualSnapshotBtn = CreateFrame("Button", "TMManualSnapshotBtn", tab, "UIPanelButtonTemplate")
	manualSnapshotBtn:SetWidth(140)
	manualSnapshotBtn:SetHeight(24)
	manualSnapshotBtn:SetPoint("TOPLEFT", exportBtn, "BOTTOMLEFT", 0, -10)
	manualSnapshotBtn:SetText("Create Snapshot Now")
	manualSnapshotBtn:SetScript("OnClick", function()
		TankMark:CreateSnapshot()
		TankMark:RefreshSnapshotList()
	end)

	return tab
end

-- ==========================================================
-- SNAPSHOT LIST REFRESH
-- ==========================================================

function TankMark:RefreshSnapshotList()
	if not TankMark.snapshotDropdown then return end

	-- Re-initialize the dropdown to refresh the list
	UIDropDownMenu_Initialize(TankMark.snapshotDropdown, function()
		local info = {}
		for i = 1, 3 do
			local snapshot = TankMarkDB_Snapshot and TankMarkDB_Snapshot[i]
			info = {}
			info.value = i

			if snapshot then
				-- Count mobs
				local mobCount = 0
				for _, mobs in _pairs(snapshot.zones) do
					for _ in _pairs(mobs) do
						mobCount = mobCount + 1
					end
				end

				-- Count zones
				local zoneCount = 0
				for _ in _pairs(snapshot.zones) do
					zoneCount = zoneCount + 1
				end

				-- Format label
				local ageStr = TankMark:FormatTimestamp(snapshot.timestamp)
				info.text = "Slot " .. i .. ": " .. ageStr .. " (" .. zoneCount .. " zones, " .. mobCount .. " mobs)"
			else
				info.text = "Slot " .. i .. ": |cff888888Empty|r"
			end

			info.func = function()
				TankMark.selectedSnapshotIndex = this.value
				UIDropDownMenu_SetSelectedID(TankMark.snapshotDropdown, this.value)
			end
			info.checked = (TankMark.selectedSnapshotIndex == i)
			UIDropDownMenu_AddButton(info)
		end
	end)

	-- Update dropdown text if something is selected
	if TankMark.selectedSnapshotIndex then
		UIDropDownMenu_SetSelectedID(TankMark.snapshotDropdown, TankMark.selectedSnapshotIndex)
	else
		UIDropDownMenu_SetText("Select Snapshot", TankMark.snapshotDropdown)
	end
end

-- ==========================================================
-- EXPORT DIALOG
-- ==========================================================

function TankMark:ShowExportDialog()
	local zone = TankMark:GetCachedZone()
	if not TankMarkDB.Zones[zone] then
		TankMark:Print("|cffff0000Error:|r No data found for current zone (" .. zone .. ").")
		return
	end

	-- Serialize zone data (simple Lua table format)
	local exportData = "{\n"
	exportData = exportData .. '  ["' .. zone .. '"] = {\n'
	for mobName, mobData in _pairs(TankMarkDB.Zones[zone]) do
		exportData = exportData .. '    ["' .. mobName .. '"] = {prio=' .. mobData.prio .. ', mark=' .. mobData.mark .. ', type="' .. mobData.type .. '"},\n'
	end
	exportData = exportData .. "  }\n}"

	-- Show in dialog
	StaticPopupDialogs["TANKMARK_EXPORT"] = {
		text = "Zone Export: " .. zone .. "\n\nCopy this text (Ctrl+C):",
		button1 = "Close",
		hasEditBox = 1,
		maxLetters = 2048,
		OnShow = function()
			getglobal(this:GetName().."EditBox"):SetText(exportData)
			getglobal(this:GetName().."EditBox"):HighlightText()
			getglobal(this:GetName().."EditBox"):SetFocus()
		end,
		OnAccept = function() end,
		EditBoxOnEscapePressed = function() this:GetParent():Hide() end,
		timeout = 0,
		whileDead = 1,
		hideOnEscape = 1,
	}
	StaticPopup_Show("TANKMARK_EXPORT")
end

-- ==========================================================
-- IMPORT DIALOG
-- ==========================================================

function TankMark:ShowImportDialog()
	StaticPopupDialogs["TANKMARK_IMPORT"] = {
		text = "Paste zone data (Lua table format):",
		button1 = "Import",
		button2 = "Cancel",
		hasEditBox = 1,
		maxLetters = 2048,
		OnAccept = function()
			local importText = getglobal(this:GetParent():GetName().."EditBox"):GetText()
			TankMark:ImportZoneData(importText)
		end,
		OnShow = function()
			getglobal(this:GetName().."EditBox"):SetFocus()
		end,
		EditBoxOnEscapePressed = function() this:GetParent():Hide() end,
		timeout = 0,
		whileDead = 1,
		hideOnEscape = 1,
	}
	StaticPopup_Show("TANKMARK_IMPORT")
end

function TankMark:ImportZoneData(luaString)
	if not luaString or luaString == "" then
		TankMark:Print("|cffff0000Error:|r No data provided.")
		return
	end

	-- Parse Lua table (UNSAFE: eval user input - use with caution!)
	local func, err = loadstring("return " .. luaString)
	if not func then
		TankMark:Print("|cffff0000Error:|r Invalid Lua syntax: " .. (err or "unknown"))
		return
	end

	local success, importData = pcall(func)
	if not success or type(importData) ~= "table" then
		TankMark:Print("|cffff0000Error:|r Could not parse data.")
		return
	end

	-- Merge imported data
	local added = 0
	for zoneName, mobs in _pairs(importData) do
		if not TankMarkDB.Zones[zoneName] then
			TankMarkDB.Zones[zoneName] = {}
		end
		for mobName, mobData in _pairs(mobs) do
			TankMarkDB.Zones[zoneName][mobName] = {
				prio = mobData.prio or 5,
				mark = mobData.mark or 8,
				type = mobData.type or "KILL",
				class = mobData.class or nil
			}
			added = added + 1
		end
	end

	TankMark:Print("|cff00ff00Imported:|r " .. added .. " mobs.")
	if TankMark.UpdateMobList then TankMark:UpdateMobList() end
end
