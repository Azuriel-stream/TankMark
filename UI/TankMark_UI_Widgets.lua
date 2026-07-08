if not TankMark then return end

-- ==========================================================
-- UI HELPERS
-- ==========================================================

function TankMark:SetIconTexture(texture, iconID)
    if not texture then return end
    if iconID == 0 then
        -- "Pass" icon for Disabled/Ignore
        texture:SetTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Up")
        texture:SetTexCoord(0, 1, 0, 1)
    else
        texture:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
        SetRaidTargetIconTexture(texture, iconID)
    end
end

-- [v0.32] Button:SetTextColor is a 1.12 widget method that is nil on 3.3.5 (Ascension) ->
-- coloring a templated button's text directly throws there. Route through the button's
-- font string, which colors identically on both clients (GetFontString exists on 1.12
-- and 3.3.5). Vanilla-behavior-equivalent.
function TankMark:SetButtonTextColor(btn, r, g, b)
    if not btn then return end
    local fs = btn:GetFontString()
    if fs then
        fs:SetTextColor(r, g, b)
    end
end

function TankMark:CreateEditBox(parent, title, w)
    local eb = CreateFrame("EditBox", nil, parent)
    eb:SetWidth(w); eb:SetHeight(20)
    eb:SetFontObject(GameFontHighlightSmall)
    eb:SetAutoFocus(false) 
    eb:SetTextInsets(5, 5, 0, 0)
    
    local left = eb:CreateTexture(nil, "BACKGROUND")
    left:SetTexture("Interface\\Common\\Common-Input-Border")
    left:SetTexCoord(0, 0.0625, 0, 0.625)
    left:SetWidth(8); left:SetHeight(20)
    left:SetPoint("LEFT", 0, 0)
    
    local right = eb:CreateTexture(nil, "BACKGROUND")
    right:SetTexture("Interface\\Common\\Common-Input-Border")
    right:SetTexCoord(0.9375, 1, 0, 0.625)
    right:SetWidth(8); right:SetHeight(20)
    right:SetPoint("RIGHT", 0, 0)
    
    local mid = eb:CreateTexture(nil, "BACKGROUND")
    mid:SetTexture("Interface\\Common\\Common-Input-Border")
    mid:SetTexCoord(0.0625, 0.9375, 0, 0.625)
    mid:SetHeight(20)
    mid:SetPoint("LEFT", left, "RIGHT", 0, 0)
    mid:SetPoint("RIGHT", right, "LEFT", 0, 0)
    
    local label = eb:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    label:SetPoint("BOTTOMLEFT", eb, "TOPLEFT", -5, 2)
    label:SetText(title or "") 
    
    eb:SetScript("OnEscapePressed", function() eb:ClearFocus() end)
    eb:SetScript("OnEnterPressed", function() eb:ClearFocus() end)
    return eb
end
