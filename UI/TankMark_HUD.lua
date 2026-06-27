if not TankMark then return end

-- ==========================================================
-- LOCALIZATIONS
-- ==========================================================

-- Import shared localizations
local L = TankMark.Locals

-- UI State
TankMark.hudFrame = nil
TankMark.hudRows = {}
TankMark.menuFrame = nil
TankMark.clickedIconID = nil -- Tracks which row was right-clicked

-- ==========================================================
-- 1. MENUS (Global & Context)
-- ==========================================================
function TankMark:InitGlobalMenu()
	local info = {}
	
	-- Header
	info = { text = "TankMark Actions", isTitle = 1, notCheckable = 1 }
	UIDropDownMenu_AddButton(info)
	
	-- Master Toggle
	info = {
		text = "Enable Auto-Marking",
		checked = TankMark.IsActive,
		func = function()
			TankMark.IsActive = not TankMark.IsActive
			CloseDropDownMenus()
			TankMark:Print("Auto-Marking is now: " .. (TankMark.IsActive and "|cff00ff00ON|r" or "|cffff0000OFF|r"))
		end
	}
	UIDropDownMenu_AddButton(info)
	
	-- Actions
	info = { text = "Enable All Marks", notCheckable = 1, func = function() TankMark.disabledMarks = {}; TankMark:UpdateHUD() end }
	UIDropDownMenu_AddButton(info)
	
	info = { text = "Announce Assignments", notCheckable = 1, func = function() TankMark:AnnounceAssignments() end }
	UIDropDownMenu_AddButton(info)
	
	info = { text = "Share Zone Mob DB", notCheckable = 1, func = function() TankMark:PostShareLink() end }
	UIDropDownMenu_AddButton(info)
	
	info = { text = "Open Configuration", notCheckable = 1, func = function() TankMark:ShowOptions() end }
	UIDropDownMenu_AddButton(info)
	
	-- Reset
	info = { text = "|cffff0000Reset Session|r", notCheckable = 1, func = function() TankMark:ResetSession() end }
	UIDropDownMenu_AddButton(info)
	
	info = { text = "Close", notCheckable = 1, func = function() CloseDropDownMenus() end }
	UIDropDownMenu_AddButton(info)
end

function TankMark:InitRowMenu()
	local iconID = TankMark.clickedIconID
	if not iconID then return end
	
	local markName = TankMark.MarkInfo[iconID].color .. TankMark.MarkInfo[iconID].name .. "|r"
	
	local info = { text = markName .. " Options", isTitle = 1, notCheckable = 1 }
	UIDropDownMenu_AddButton(info)
	
	-- 1. Assign Target
	local targetName = L._UnitName("target")
    local canAssign = (targetName and L._UnitIsPlayer("target"))
	local assignText = "Assign Target"
	if canAssign then assignText = assignText .. " |cff00ff00(" .. targetName .. ")|r" end
	
	info = {
		text = assignText,
		notCheckable = 1,
		disabled = not canAssign,
		func = function()
			TankMark:SetProfileAssignment(iconID, targetName)
			CloseDropDownMenus()
		end
	}
	UIDropDownMenu_AddButton(info)
	
	-- 2. Clear Assignment
	info = {
		text = "Clear Assignment (Free)",
		notCheckable = 1,
		func = function()
			TankMark:SetProfileAssignment(iconID, "")
			CloseDropDownMenus()
		end
	}
	UIDropDownMenu_AddButton(info)
	
	-- 3. Disable Toggle
	local isDisabled = TankMark.disabledMarks[iconID]
	info = {
		text = isDisabled and "Enable Mark" or "Disable Mark",
		notCheckable = 1,
		func = function()
			TankMark:ToggleMarkState(iconID)
			CloseDropDownMenus() -- Close to show update
		end
	}
	UIDropDownMenu_AddButton(info)
	
	info = { text = "Cancel", notCheckable = 1, func = function() CloseDropDownMenus() end }
	UIDropDownMenu_AddButton(info)
end

-- Helper to write directly to DB from HUD
function TankMark:SetProfileAssignment(iconID, playerName)
	local zone = TankMark:GetCachedZone()  -- [PHASE 2] Use cached zone
	if not TankMarkProfileDB[zone] then TankMarkProfileDB[zone] = {} end
	local list = TankMarkProfileDB[zone]
	
	-- 1. Find existing entry or create new
	local found = false
	for _, entry in L._ipairs(list) do
		if entry.mark == iconID then
			entry.tank = playerName
			found = true
			break
		end
	end
	
	if not found then
		L._tinsert(list, { mark = iconID, tank = playerName, healers = "" })
		-- Sort new list by ID desc (Skull first)
		L._tsort(list, function(a,b) return a.mark > b.mark end)
	end
	
	-- 2. Update Live Session
	if playerName and playerName ~= "" then
		TankMark.sessionAssignments[iconID] = playerName
		TankMark.usedIcons[iconID] = true
		TankMark:Print("Assigned " .. playerName .. " to " .. TankMark:GetMarkString(iconID))
	else
		-- If clearing, we remove the name but keep the 'used' status if it's currently on a mob
		TankMark.sessionAssignments[iconID] = nil
		TankMark:Print("Cleared assignment for " .. TankMark:GetMarkString(iconID))
	end
	
	-- 3. Refresh UI
	TankMark:UpdateHUD()
	
	-- Refresh Config Tab 2 if it's open
	if TankMark.UpdateProfileList then TankMark:LoadProfileToCache(); TankMark:UpdateProfileList() end
end

-- ==========================================================
-- 2. FRAME CREATION
-- ==========================================================
function TankMark:CreateHUD()
    -- Single Menu Frame used for both contexts (re-initialized on click)
    TankMark.menuFrame = CreateFrame("Frame", "TankMarkHUDMenu", UIParent, "UIDropDownMenuTemplate")
    
    local f = CreateFrame("Frame", "TankMarkHUD", UIParent)
    f:SetWidth(200); f:SetHeight(150)
    
    -- [v0.22] Restore saved position or use default
    if TankMarkCharConfig and TankMarkCharConfig.HUD and TankMarkCharConfig.HUD.point then
        local pos = TankMarkCharConfig.HUD
        f:SetPoint(pos.point, pos.relativeTo or UIParent, pos.relativePoint, pos.xOffset, pos.yOffset)
    else
        -- Default position (first-time user)
        f:SetPoint("CENTER", UIParent, "CENTER", 200, 0)
    end
    
    f:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 5, right = 5, top = 5, bottom = 5 }
    })
    f:SetBackdropColor(0, 0, 0, 0.4)
    f:SetBackdropBorderColor(0.8, 0.8, 0.8, 0.5)
    f:SetMovable(true); f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function() this:StartMoving() end)
    f:SetScript("OnDragStop", function()
        this:StopMovingOrSizing()
        -- [v0.22] Save HUD position
        TankMark:SaveHUDPosition()
    end)
    
    -- Right-Click on Background -> Global Menu
    f:SetScript("OnMouseUp", function()
        if arg1 == "RightButton" then
            UIDropDownMenu_Initialize(TankMark.menuFrame, function() TankMark:InitGlobalMenu() end, "MENU")
            ToggleDropDownMenu(1, nil, TankMark.menuFrame, "cursor", 0, 0)
        end
    end)
    
    f.header = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.header:SetPoint("TOP", f, "TOP", 0, -5)
    f.header:SetText("TankMark HUD")

    -- [v0.29] slice 2 tracer: bottom-anchored swarm status line, created once
    -- here and (re)painted by RenderSwarmLine. DISPLAY-ONLY -- never marks.
    f.swarmStatus = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.swarmStatus:SetPoint("BOTTOM", f, "BOTTOM", 0, 6)
    f.swarmStatus:Hide()

    -- [v0.29] slice 5b.3: transparent click overlay on the swarm status line. Shown
    -- by RenderSwarmLine ONLY for a QUEEN with >=1 eligible candidate; clicking opens
    -- the handoff candidate menu. Hidden otherwise so it neither intercepts HUD drag
    -- nor offers a dead click to drones. Spans the text PLUS the arrow cue to its
    -- right, so a click on the arrow counts too.
    local hb = CreateFrame("Button", nil, f)
    hb:SetPoint("TOPLEFT",     f.swarmStatus, "TOPLEFT",     0, 0)
    hb:SetPoint("BOTTOMRIGHT", f.swarmStatus, "BOTTOMRIGHT", 16, 0)
    hb:EnableMouse(true)
    hb:RegisterForClicks("LeftButtonUp")
    hb:SetScript("OnClick", function()
        UIDropDownMenu_Initialize(TankMark.swarmHandoffDrop, function()
            TankMark:InitHandoffMenu()
        end, "MENU")
        ToggleDropDownMenu(1, nil, TankMark.swarmHandoffDrop, "cursor", 0, 0)
    end)
    hb:SetScript("OnEnter", function()
        GameTooltip:SetOwner(this, "ANCHOR_TOP")
        GameTooltip:AddLine("Pass the Queen role")
        GameTooltip:AddLine("Click to hand marking off to another player.", 1, 1, 1)
        GameTooltip:Show()
    end)
    hb:SetScript("OnLeave", function() GameTooltip:Hide() end)
    hb:Hide()
    f.swarmHandoffBtn = hb

    -- [v0.29] slice 5b.3: the "clickable" cue. 1.12 has NO Unicode (chevron glyphs
    -- render blank) and FontStrings do NOT parse |T inline textures (they print
    -- literally) -- so the cue must be a real Texture region. This path is the down
    -- arrow that FauxScrollFrameTemplate already renders in the addon's own list
    -- scrollbars, so it is guaranteed present on the client.
    local arrow = f:CreateTexture(nil, "OVERLAY")
    arrow:SetTexture("Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Up")
    arrow:SetWidth(14); arrow:SetHeight(14)
    arrow:SetPoint("LEFT", f.swarmStatus, "RIGHT", 1, 0)
    arrow:Hide()
    f.swarmHandoffArrow = arrow

    TankMark.swarmHandoffDrop = CreateFrame("Frame", "TMSwarmHandoffMenu", f, "UIDropDownMenuTemplate")

    -- Create 8 rows (Skull to Star)
    for i = 8, 1, -1 do
        local row = CreateFrame("Button", nil, f)
        row:SetWidth(180); row:SetHeight(20)
        row:SetID(i)
        
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetWidth(16); row.icon:SetHeight(16)
        row.icon:SetPoint("LEFT", row, "LEFT", 0, 0)
        row.icon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
        L._SetRaidTargetIconTexture(row.icon, i)
        
        row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        row.text:SetPoint("LEFT", row.icon, "RIGHT", 5, 0)
        row.text:SetText("")
        
        row:EnableMouse(true)
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        row:SetScript("OnClick", function()
            if arg1 == "LeftButton" then
                TankMark:ToggleMarkState(this:GetID())
            elseif arg1 == "RightButton" then
                -- Open Row Context Menu
                TankMark.clickedIconID = this:GetID()
                UIDropDownMenu_Initialize(TankMark.menuFrame, function() TankMark:InitRowMenu() end, "MENU")
                ToggleDropDownMenu(1, nil, TankMark.menuFrame, "cursor", 0, 0)
            end
        end)
        
        row:Hide()
        TankMark.hudRows[i] = row
    end
    
    TankMark.hudFrame = f
    TankMark:UpdateHUD()
end

-- ==========================================================
-- [v0.24] CLASS COLOR HELPER
-- ==========================================================

function TankMark:GetClassColor(class)
    -- Vanilla WoW class colors
    if class == "Warrior" then return "|cffC79C6E" end      -- Tan
    if class == "Paladin" then return "|cffF58CBA" end      -- Pink
    if class == "Hunter" then return "|cffABD473" end       -- Green
    if class == "Rogue" then return "|cffFFF569" end        -- Yellow
    if class == "Priest" then return "|cffFFFFFF" end       -- White
    if class == "Shaman" then return "|cff0070DE" end       -- Blue
    if class == "Mage" then return "|cff69CCF0" end         -- Light Blue
    if class == "Warlock" then return "|cff9482C9" end      -- Purple
    if class == "Druid" then return "|cffFF7D0A" end        -- Orange
    return "|cff00ff00"  -- Default green if class unknown
end

-- ==========================================================
-- [v0.24] HUD ROW RENDERING HELPER
-- ==========================================================

function TankMark:RenderHUDRow(row, markID, isProfileMark)
    local assignedPlayer = TankMark.sessionAssignments[markID]
    local activeMob = TankMark.Ledger.NameFor(markID)
    local textToShow = nil
    
    if assignedPlayer then
        -- [v0.24] Apply class-colored names
        local unit = TankMark:FindUnitByName(assignedPlayer)
        local isInRaid = TankMark:IsPlayerInRaid(assignedPlayer)
        
        if unit and isInRaid then
            -- Get class color
            local class = L._UnitClass(unit)
            local classColor = TankMark:GetClassColor(class)
            textToShow = classColor .. assignedPlayer .. "|r"
        elseif isInRaid then
            -- In raid but unit not found (shouldn't happen, but fallback to green)
            textToShow = "|cff00ff00" .. assignedPlayer .. "|r"
        else
            -- Not in raid (red)
            textToShow = "|cffff0000" .. assignedPlayer .. "|r"
        end
    elseif activeMob then
        textToShow = "|cffffffff" .. activeMob .. "|r"
    end
    
    local isDisabled = TankMark.disabledMarks[markID]
    
    -- Apply Visual Disable (Dimming)
    if isDisabled then
        row.icon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
        L._SetRaidTargetIconTexture(row.icon, markID)
        row.icon:SetVertexColor(0.3, 0.3, 0.3)
        if textToShow then
            local plainText = L._gsub(textToShow, "|c%x%x%x%x%x%x%x%x", "")
            plainText = L._gsub(plainText, "|r", "")
            textToShow = "|cff888888" .. plainText .. " (OFF)|r"
        else
            textToShow = "|cff888888(Disabled)|r"
        end
    else
        row.icon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
        L._SetRaidTargetIconTexture(row.icon, markID)
        row.icon:SetVertexColor(1, 1, 1)
    end
    
    -- Default text for empty marks
    if not textToShow then
        textToShow = "|cff888888(Free)|r"
    end
    
    row.text:SetText(textToShow)
end

-- ==========================================================
-- [v0.29] SWARM STATUS LINE (slice 2 tracer)
-- ==========================================================

-- Paint the one-line swarm status at the HUD bottom: who the marking queen is and
-- our derived role. DISPLAY-ONLY -- it reads the live Swarm election state and
-- never marks. Shown in BOTH HUD render paths (profiled and NO PROFILE LOADED) so
-- a drone with an empty profile still sees who the queen is. Returns true when the
-- line is visible, so UpdateHUD can reserve room for it.
function TankMark:RenderSwarmLine()
    local f = TankMark.hudFrame
    if not f or not f.swarmStatus then return false end

    local Swarm = TankMark.Swarm
    -- Only trace once the swarm is actually running (SuperWoW + InitSwarm built
    -- the beat frame). Otherwise the line stays hidden and reserves no height.
    if not (TankMark.IsSuperWoW and Swarm and Swarm.frame) then
        f.swarmStatus:Hide()
        if f.swarmHandoffBtn   then f.swarmHandoffBtn:Hide()   end
        if f.swarmHandoffArrow then f.swarmHandoffArrow:Hide() end
        return false
    end

    local role  = Swarm.lastRole
    local queen = Swarm.currentQueen
    local text
    -- [v0.29] slice 5b.3: the line is a handoff trigger only for a QUEEN who has at
    -- least one eligible candidate to pass to; the down-arrow cue (a separate Texture,
    -- toggled below) advertises it. The button's click re-validates via
    -- InitiateHandoff, so a slightly stale gate is harmless.
    local clickable = false
    if role == "QUEEN" then
        text = "|cff00ff00Queen: " .. (queen or "?") .. " (you)|r"
        if Swarm.HandoffCandidates and L._tgetn(Swarm.HandoffCandidates()) > 0 then
            clickable = true
        end
    elseif role == "DRONE" then
        text = "|cffffd100Queen:|r |cffffffff" .. (queen or "?") .. "|r"
    elseif role == "BOOTSTRAP" then
        text = "|cffffd100Queen: electing...|r"
    else -- NONE / nil
        text = "|cff888888Queen: --|r"
    end

    f.swarmStatus:SetText(text)
    f.swarmStatus:Show()

    if f.swarmHandoffBtn then
        if clickable then
            f.swarmHandoffBtn:Show()
            if f.swarmHandoffArrow then f.swarmHandoffArrow:Show() end
        else
            f.swarmHandoffBtn:Hide()
            if f.swarmHandoffArrow then f.swarmHandoffArrow:Hide() end
            -- Close our own menu if it lingers after a demotion (don't stomp others).
            local open = UIDROPDOWNMENU_OPEN_MENU
            if open and (open == TankMark.swarmHandoffDrop or open == "TMSwarmHandoffMenu") then
                CloseDropDownMenus()
            end
        end
    end
    return true
end

-- ==========================================================
-- [v0.29] slice 5b.2: RECORDER-ON-PROMOTION PROMPT
-- ==========================================================
-- Safety interlock for the dead-queen trap: a Flight Recorder left running makes
-- ProcessUnit record-and-return, so a freshly-promoted Queen would silently never
-- mark. On promotion (rising edge) while recording, Swarm.Recompute calls
-- PromptRecorderOnPromotion. Stop is the ONLY outcome that suppresses the warning;
-- Keep, Escape, and the X all leave the recorder running and warn loudly via OnHide
-- (1.12 Escape hides WITHOUT firing OnCancel, so the flag-in-OnHide is what makes
-- a silent dismiss still warn).

function TankMark:WarnRecordingQueen()
    TankMark:Print("|cffff0000WARNING:|r You are the Queen but the Flight Recorder is ON "
        .. "-- mobs are being recorded, NOT marked. Use |cffffffff/tmark recorder stop|r to mark.")
end

StaticPopupDialogs["TANKMARK_RECORDER_ON_PROMOTE"] = {
    text = "",  -- set per-show in PromptRecorderOnPromotion (sole-candidate notice)
    button1 = "Stop Recording",
    button2 = "Keep Recording",
    OnShow = function()
        TankMark.recorderPromoteStopped = false
    end,
    OnAccept = function()
        TankMark.recorderPromoteStopped = true
        TankMark.IsRecorderActive = false
        TankMark:Print("Flight Recorder: |cffff0000DISABLED|r -- you are the Queen; marking is live.")
    end,
    OnHide = function()
        -- Fires for every dismissal (button or Escape). Warn unless Stop was chosen.
        if not TankMark.recorderPromoteStopped then
            TankMark:WarnRecordingQueen()
        end
    end,
    timeout = 0,
    whileDead = 1,
    hideOnEscape = 1,
}

function TankMark:PromptRecorderOnPromotion(soleCandidate)
    local text = "You are now the marking Queen, but the Flight Recorder is running -- "
        .. "while it is on you record mobs instead of marking them. Stop recording so you can mark?"
    if soleCandidate then
        text = text .. "\n\n|cffff8000You are the only eligible marker -- "
            .. "if you keep recording, no one will mark.|r"
    end
    StaticPopupDialogs["TANKMARK_RECORDER_ON_PROMOTE"].text = text
    StaticPopup_Show("TANKMARK_RECORDER_ON_PROMOTE")
end

-- ==========================================================
-- [v0.29] slice 5b.3: HANDOFF TRIGGER (queen clicks the status line)
-- ==========================================================
-- The dropdown is just a launcher: it lists the live candidates and routes the
-- pick through InitiateHandoff, which re-validates queen-only + eligibility + non-
-- self at click time -- so a stale list or a mid-menu demotion just prints a
-- rejection, never corrupts state (the slash command stays authoritative).

function TankMark:InitHandoffMenu()
    local Swarm = TankMark.Swarm
    if not (Swarm and Swarm.HandoffCandidates) then return end
    local candidates = Swarm.HandoffCandidates()
    local n = L._tgetn(candidates)
    if n == 0 then
        local info = {}
        info.text     = "(no eligible players)"
        info.disabled = 1
        UIDropDownMenu_AddButton(info)
        return
    end
    for i = 1, n do
        local name = candidates[i]
        local info = {}
        info.text = name
        info.func = function() TankMark:ConfirmHandoff(name) end
        UIDropDownMenu_AddButton(info)
    end
end

function TankMark:ConfirmHandoff(name)
    if not name then return end
    TankMark.pendingHandoffTargetUI = name
    StaticPopupDialogs["TANKMARK_HANDOFF_CONFIRM"].text =
        "Pass the marking Queen role to |cffffd100" .. name .. "|r?"
    StaticPopup_Show("TANKMARK_HANDOFF_CONFIRM")
end

StaticPopupDialogs["TANKMARK_HANDOFF_CONFIRM"] = {
    text = "",  -- set per-show in ConfirmHandoff
    button1 = "Pass Role",
    button2 = "Cancel",
    OnAccept = function()
        local name = TankMark.pendingHandoffTargetUI
        if name and TankMark.Swarm and TankMark.Swarm.InitiateHandoff then
            TankMark.Swarm.InitiateHandoff(name)  -- re-validates; prints on reject
        end
    end,
    timeout = 0,
    whileDead = 1,
    hideOnEscape = 1,
}

-- ==========================================================
-- 3. TOGGLE & UPDATE LOGIC
-- ==========================================================
function TankMark:ToggleMarkState(iconID)
	TankMark.disabledMarks[iconID] = not TankMark.disabledMarks[iconID]
	TankMark:UpdateHUD()
end

function TankMark:UpdateHUD()
    if not TankMark.hudFrame then TankMark:CreateHUD() end
    
    local zone = TankMark:GetCachedZone()
    local tankMarks = {}
    local ccMarks = {}
    local added = {}
    
    -- 1. Build Lists from Profile (separate tank/CC)
    if TankMarkProfileDB and TankMarkProfileDB[zone] then
        -- Ensure all entries have a role field before we read it.
        -- MigrateProfileRoles is a no-op for entries that already have a role.
        TankMark:MigrateProfileRoles(zone)

        for _, entry in L._ipairs(TankMarkProfileDB[zone]) do
            if entry.mark then
                added[entry.mark] = true

                -- [v0.28] Read stored role directly instead of doing a live
                -- class lookup. This respects manual CC checkbox overrides
                -- (e.g. a Druid ticked as CC, or a Warrior ticked as CC)
                -- and removes the dependency on IsPlayerCCClass from the
                -- HUD render path entirely.
                if entry.role == "CC" then
                    L._tinsert(ccMarks, entry.mark)
                else
                    L._tinsert(tankMarks, entry.mark)
                end
            end
        end
    end
    
    -- 2. Empty Profile Warning
	if L._tgetn(tankMarks) == 0 and L._tgetn(ccMarks) == 0 then
		local warningRow = TankMark.hudRows[8]
		warningRow.icon:SetTexture(nil)
		warningRow.text:SetText("|cffff0000NO PROFILE LOADED|r")
		warningRow:ClearAllPoints()
		warningRow:SetPoint("TOPLEFT", TankMark.hudFrame, "TOPLEFT", 10, -25)
		warningRow:Show()
		
		-- Hide all mark rows
		for i = 7, 1, -1 do TankMark.hudRows[i]:Hide() end
		
		-- [v0.24] Hide section headers
		if TankMark.hudFrame.tankHeader then TankMark.hudFrame.tankHeader:Hide() end
		if TankMark.hudFrame.ccHeader then TankMark.hudFrame.ccHeader:Hide() end
		
		-- [v0.29] slice 2 tracer: still show the swarm status line with no profile,
		-- so a drone with an empty profile can see who the queen is.
		local swarmShown = TankMark:RenderSwarmLine()
		TankMark.hudFrame:Show()
		TankMark.hudFrame:SetHeight(50 + (swarmShown and 16 or 0))
		return
	end
    
    -- 3. Add Leftovers (marks not in profile)
    -- (Removed leftover marks - HUD only displays assigned marks)
    
    -- 4. Render Sections
    local lastVisibleRow = nil
    local activeRows = 0
    
    -- 4A. Render TANK Section
    if L._tgetn(tankMarks) > 0 then
        -- Create tank header if it doesn't exist
        if not TankMark.hudFrame.tankHeader then
            TankMark.hudFrame.tankHeader = TankMark.hudFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            TankMark.hudFrame.tankHeader:SetTextColor(1.0, 0.82, 0)
        end
        
        TankMark.hudFrame.tankHeader:SetText("TANKS")
        TankMark.hudFrame.tankHeader:ClearAllPoints()
        if not lastVisibleRow then
            TankMark.hudFrame.tankHeader:SetPoint("TOPLEFT", TankMark.hudFrame, "TOPLEFT", 10, -25)
        else
            TankMark.hudFrame.tankHeader:SetPoint("TOPLEFT", lastVisibleRow, "BOTTOMLEFT", 0, -5)
        end
        TankMark.hudFrame.tankHeader:Show()
        lastVisibleRow = TankMark.hudFrame.tankHeader
        activeRows = activeRows + 1
        
        -- Render tank marks
        for _, i in L._ipairs(tankMarks) do
            local row = TankMark.hudRows[i]
            TankMark:RenderHUDRow(row, i, added[i])
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", lastVisibleRow, "BOTTOMLEFT", 0, lastVisibleRow == TankMark.hudFrame.tankHeader and -2 or 0)
            row:Show()
            lastVisibleRow = row
            activeRows = activeRows + 1
        end
    else
        if TankMark.hudFrame.tankHeader then TankMark.hudFrame.tankHeader:Hide() end
    end
    
    -- 4B. Render CC Section
    if L._tgetn(ccMarks) > 0 then
        -- Create CC header if it doesn't exist
        if not TankMark.hudFrame.ccHeader then
            TankMark.hudFrame.ccHeader = TankMark.hudFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            TankMark.hudFrame.ccHeader:SetTextColor(1.0, 0.82, 0)
        end
        
        TankMark.hudFrame.ccHeader:SetText("CROWD CONTROL")
        TankMark.hudFrame.ccHeader:ClearAllPoints()
        if not lastVisibleRow then
            TankMark.hudFrame.ccHeader:SetPoint("TOPLEFT", TankMark.hudFrame, "TOPLEFT", 10, -25)
        else
            TankMark.hudFrame.ccHeader:SetPoint("TOPLEFT", lastVisibleRow, "BOTTOMLEFT", 0, -8)
        end
        TankMark.hudFrame.ccHeader:Show()
        lastVisibleRow = TankMark.hudFrame.ccHeader
        activeRows = activeRows + 1
        
        -- Render CC marks
        for _, i in L._ipairs(ccMarks) do
            local row = TankMark.hudRows[i]
            TankMark:RenderHUDRow(row, i, added[i])
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", lastVisibleRow, "BOTTOMLEFT", 0, lastVisibleRow == TankMark.hudFrame.ccHeader and -2 or 0)
            row:Show()
            lastVisibleRow = row
            activeRows = activeRows + 1
        end
    else
        if TankMark.hudFrame.ccHeader then TankMark.hudFrame.ccHeader:Hide() end
    end
    
    -- [v0.24] Hide all rows not rendered above (safety cleanup)
	for i = 1, 8 do
		if not added[i] then
			TankMark.hudRows[i]:Hide()
		end
	end
    
    -- [v0.29] slice 2 tracer: bottom-anchored swarm status line (queen + role).
    local swarmShown = TankMark:RenderSwarmLine()
    if activeRows > 0 or swarmShown then
        TankMark.hudFrame:Show()
        TankMark.hudFrame:SetHeight((activeRows * 20) + 30 + (swarmShown and 16 or 0))
    else
        TankMark.hudFrame:Hide()
    end
end

-- ==========================================================
-- [v0.22] HUD POSITION PERSISTENCE
-- ==========================================================

function TankMark:SaveHUDPosition()
    if not TankMark.hudFrame then return end
    
    local point, relativeTo, relativePoint, xOffset, yOffset = TankMark.hudFrame:GetPoint()
    
    -- Initialize if needed
    if not TankMarkCharConfig then TankMarkCharConfig = {} end
    if not TankMarkCharConfig.HUD then TankMarkCharConfig.HUD = {} end
    
    -- Save position (always anchor to UIParent for stability)
    TankMarkCharConfig.HUD.point = point
    TankMarkCharConfig.HUD.relativeTo = "UIParent"
    TankMarkCharConfig.HUD.relativePoint = relativePoint
    TankMarkCharConfig.HUD.xOffset = xOffset
    TankMarkCharConfig.HUD.yOffset = yOffset
end

-- ==========================================================
-- [v0.29] SLICE 6.4a: MOB DB SHARING -- RECEIVER UI
-- ==========================================================
-- The SetItemRef click hook (fires the pull) and the import-confirm dialog. The
-- receive LOGIC + the DB-apply edge live in Core/TankMark_Sync.lua; this is the
-- UI half (Core has no UI). 1.12 StaticPopup supports only TWO buttons, but the
-- consent needs three (Import / Always trust / Cancel), so the confirm is a small
-- custom frame -- which also sidesteps Turtle's Escape-skips-OnCancel quirk.

-- Build (once) and return the import-confirm frame.
local function GetShareConfirmFrame()
    if TankMark.shareConfirmFrame then return TankMark.shareConfirmFrame end

    local f = CreateFrame("Frame", "TankMarkShareConfirm", UIParent)
    f:SetWidth(380); f:SetHeight(150)
    f:SetPoint("CENTER", 0, 120)
    f:SetFrameStrata("DIALOG")
    f:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })
    f:EnableMouse(true)
    f:Hide()

    local msg = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    msg:SetPoint("TOP", 0, -22)
    msg:SetWidth(344); msg:SetJustifyH("CENTER")
    f.msg = msg

    local importBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    importBtn:SetWidth(90); importBtn:SetHeight(22)
    importBtn:SetPoint("BOTTOMLEFT", 18, 16)
    importBtn:SetText("Import")
    importBtn:SetScript("OnClick", function()
        local p = TankMark.pendingShareConfirm
        f:Hide(); TankMark.pendingShareConfirm = nil
        if p then TankMark:ApplyShare(p.sender, p.buf) end
    end)

    local trustBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    trustBtn:SetWidth(112); trustBtn:SetHeight(22)
    trustBtn:SetPoint("BOTTOM", 0, 16)
    trustBtn:SetText("Always trust")
    trustBtn:SetScript("OnClick", function()
        local p = TankMark.pendingShareConfirm
        f:Hide(); TankMark.pendingShareConfirm = nil
        if p then
            TankMark.Trust.Set(p.sender, TankMark.Trust.TRUSTED)
            if TankMark.RefreshTrustList then TankMark:RefreshTrustList() end
            TankMark:ApplyShare(p.sender, p.buf)
        end
    end)

    local cancelBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    cancelBtn:SetWidth(90); cancelBtn:SetHeight(22)
    cancelBtn:SetPoint("BOTTOMRIGHT", -18, 16)
    cancelBtn:SetText("Cancel")
    cancelBtn:SetScript("OnClick", function()
        f:Hide(); TankMark.pendingShareConfirm = nil
    end)

    TankMark.shareConfirmFrame = f
    return f
end

-- Neutral-sender confirm: show the overwrite warning with concrete counts.
function TankMark:ShowShareConfirm(sender, buf)
    if not sender or not buf then return end
    local mine = 0
    if TankMarkDB.Zones[buf.zone] then
        for _ in L._pairs(TankMarkDB.Zones[buf.zone]) do mine = mine + 1 end
    end
    TankMark.pendingShareConfirm = { sender = sender, buf = buf }
    local f = GetShareConfirmFrame()
    f.msg:SetText("Import |cffffd200" .. sender .. "|r's " .. buf.zone ..
        " Mob DB?\n\n|cffffaa00" .. buf.count .. "|r mobs will REPLACE your |cffffaa00" ..
        mine .. "|r.\nA snapshot will be saved.")
    f:Show()
end

-- [v0.29] slice 6.4a: intercept clicks on our "tankmark:" share links. Defensive
-- -- only OUR links are handled; everything else (and any unparsable link) falls
-- straight through to the original SetItemRef, so normal chat links never break.
local origSetItemRef = SetItemRef
function SetItemRef(link, text, button)
    if link then
        local parsed = TankMark.SyncCodec.DecodeShareLink(link)
        if parsed then
            TankMark:OnShareLinkClick(parsed.poster, parsed.zone)
            return
        end
    end
    return origSetItemRef(link, text, button)
end
