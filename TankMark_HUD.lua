-- TankMark: v0.2-dev
-- File: TankMark_HUD.lua
-- Description: The Heads-Up Display for active assignments

if not TankMark then return end

TankMark.hudFrame = nil
TankMark.hudRows = {}

-- ==========================================================
-- 1. FRAME CREATION
-- ==========================================================
function TankMark:CreateHUD()
    -- Main Container
    local f = CreateFrame("Frame", "TankMarkHUD", UIParent)
    f:SetWidth(200)
    f:SetHeight(150)
    f:SetPoint("CENTER", UIParent, "CENTER", 200, 0) 
    f:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 5, right = 5, top = 5, bottom = 5 }
    })
    f:SetBackdropColor(0, 0, 0, 0.4) 
    f:SetBackdropBorderColor(0.8, 0.8, 0.8, 0.5)
    
    -- Movable Logic
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function() this:StartMoving() end)
    f:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)
    
    -- Header 
    f.header = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.header:SetPoint("TOP", f, "TOP", 0, -5)
    f.header:SetText("TankMark HUD")

    -- Create 8 Rows (One for each icon)
    for i = 8, 1, -1 do
        local row = CreateFrame("Frame", nil, f)
        row:SetWidth(180)
        row:SetHeight(20)
        
        -- NOTE: We do NOT set points here anymore. 
        -- Anchoring is now handled dynamically in UpdateHUD.
        
        -- Icon Texture
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetWidth(16)
        row.icon:SetHeight(16)
        row.icon:SetPoint("LEFT", row, "LEFT", 0, 0)
        row.icon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
        SetRaidTargetIconTexture(row.icon, i)
        
        -- Text Label
        row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        row.text:SetPoint("LEFT", row.icon, "RIGHT", 5, 0)
        row.text:SetText("")
        
        row:Hide() 
        TankMark.hudRows[i] = row
    end
    
    TankMark.hudFrame = f
    TankMark:UpdateHUD()
end

-- ==========================================================
-- 2. UPDATE LOGIC (Fixed for Gaps)
-- ==========================================================
function TankMark:UpdateHUD()
    if not TankMark.hudFrame then
        TankMark:CreateHUD()
    end
    
    local activeRows = 0
    local lastVisibleRow = nil -- Keeps track of the previous row to anchor to
    
    -- Loop 8 -> 1
    for i = 8, 1, -1 do
        local row = TankMark.hudRows[i]
        local assignedPlayer = TankMark.sessionAssignments[i]
        local activeMob = TankMark.activeMobNames[i]
        
        local textToShow = nil
        
        if assignedPlayer then
            textToShow = "|cff00ff00" .. assignedPlayer .. "|r"
        elseif activeMob then
            textToShow = "|cffffffff" .. activeMob .. "|r"
        end
        
        if textToShow then
            row.text:SetText(textToShow)
            
            -- DYNAMIC ANCHORING:
            row:ClearAllPoints()
            if not lastVisibleRow then
                -- This is the first item in the list: Anchor to the Top of the Box
                row:SetPoint("TOPLEFT", TankMark.hudFrame, "TOPLEFT", 10, -25)
            else
                -- This is a subsequent item: Anchor to the bottom of the previous VISIBLE row
                row:SetPoint("TOPLEFT", lastVisibleRow, "BOTTOMLEFT", 0, 0)
            end
            
            row:Show()
            lastVisibleRow = row -- Update the tracker
            activeRows = activeRows + 1
        else
            row:Hide()
        end
    end
    
    -- Auto-Resize based on active rows
    if activeRows > 0 then
        TankMark.hudFrame:Show()
        TankMark.hudFrame:SetHeight((activeRows * 20) + 30)
    else
        TankMark.hudFrame:Hide()
    end
end