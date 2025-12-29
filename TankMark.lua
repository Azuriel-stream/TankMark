-- TankMark: v0.1-dev
-- File: TankMark.lua
-- Description: Core event handling and logic engine.

-- Ensure the main frame is accessible
if not TankMark then
    -- This should have been created in TankMark_Data.lua, 
    -- but we check just in case of load order issues.
    TankMark = CreateFrame("Frame", "TankMarkFrame")
end

-- ==========================================================
-- EVENT HANDLER
-- ==========================================================
TankMark:SetScript("OnEvent", function()
    if (event == "ADDON_LOADED" and arg1 == "TankMark") then
        -- Initialize the Database (defined in TankMark_Data.lua)
        if TankMark.InitializeDB then 
            TankMark:InitializeDB() 
        end
    
    elseif (event == "PLAYER_LOGIN") then
        -- Scan the roster initially
        if TankMark.UpdateRoster then 
            TankMark:UpdateRoster() 
        end
        TankMark:Print("Loaded. Type /tm for commands.")

    elseif (event == "UPDATE_MOUSEOVER_UNIT") then
        -- MODULE 2 LOGIC WILL GO HERE
        -- TankMark:HandleMouseover()

    elseif (event == "UNIT_HEALTH") then
        -- WATCHDOG LOGIC (Module 3)
        -- TankMark:HandleDeath(arg1)
    end
end)

-- ==========================================================
-- SLASH COMMAND REGISTRATION
-- ==========================================================
SLASH_TANKMARK1 = "/tm"
SLASH_TANKMARK2 = "/tankmark"
SlashCmdList["TANKMARK"] = function(msg)
    -- We will build the command parser here later
    TankMark:Print("Commands not yet implemented.")
end