-- CanAutomate gate (Core/TankMark_Permissions.lua) -- the slice-C reconciliation.
--
-- CanAutomate is the single hard gate for automation. Slice C replaces the raw
-- `if not IsSuperWoW then return false` with a capability-gated check: SuperWoW is
-- required UNLESS the platform declares requiresSuperWoW=false (Ascension marks via
-- the two-sweep live-token path, not SuperWoW). Every OTHER gate (active, permissions,
-- zone profile) is unchanged and must still hold. These tests drive CanAutomate
-- directly (its public contract), stubbing only the WoW-state reads it makes --
-- GetCachedZone (defined in the entry point, absent from the harness) and the solo
-- HasPermissions counters -- and vary IsSuperWoW x requiresSuperWoW.

describe("CanAutomate gate (requiresSuperWoW reconciliation)", function()
    -- All-pass baseline: solo (so HasPermissions is true), active, non-empty profile,
    -- Vanilla caps (requiresSuperWoW true), no SuperWoW. Each test tweaks one axis.
    local function baseline()
        TankMark.GetCachedZone = function() return "TestZone" end
        TankMarkProfileDB = { TestZone = { { mark = 8 } } }
        TankMark.Locals._GetNumRaidMembers  = function() return 0 end
        TankMark.Locals._GetNumPartyMembers = function() return 0 end
        TankMark.IsActive = true
        TankMark.Platform.Caps = { hasScanner = true, requiresSuperWoW = true }
        TankMark.IsSuperWoW = false
    end

    it("blocks a SuperWoW-less Vanilla client (requiresSuperWoW true, no SuperWoW)", function()
        baseline()
        eq(TankMark:CanAutomate(), false, "Vanilla-no-SuperWoW stays inert")
    end)

    it("passes a Vanilla client once SuperWoW is present", function()
        baseline()
        TankMark.IsSuperWoW = true
        eq(TankMark:CanAutomate(), true, "Vanilla+SuperWoW automates")
    end)

    it("passes Ascension (requiresSuperWoW false) with no SuperWoW", function()
        baseline()
        TankMark.Platform.Caps.requiresSuperWoW = false
        eq(TankMark:CanAutomate(), true, "Ascension automates without SuperWoW")
    end)

    it("requiresSuperWoW=false does NOT bypass the other gates (IsActive)", function()
        baseline()
        TankMark.Platform.Caps.requiresSuperWoW = false
        TankMark.IsActive = false
        eq(TankMark:CanAutomate(), false, "still blocked when inactive")
    end)

    it("requiresSuperWoW=false does NOT bypass the zone-profile gate", function()
        baseline()
        TankMark.Platform.Caps.requiresSuperWoW = false
        TankMarkProfileDB = { TestZone = {} }   -- empty profile
        eq(TankMark:CanAutomate(), false, "still blocked with no zone profile")
    end)
end)

-- Driver_GetGUID must route through Platform.GUID so Ascension's native-UnitGUID
-- override takes effect (and the batch collector + recorder inherit it). A future
-- revert to a raw UnitExists read would silently re-break Ascension -- this locks it.
describe("Driver_GetGUID delegates to the platform identity primitive", function()
    it("returns whatever Platform.GUID returns", function()
        local saved = TankMark.Platform.GUID
        TankMark.Platform.GUID = function(unit) return "0xDEAD:" .. tostring(unit) end
        eq(TankMark:Driver_GetGUID("mouseover"), "0xDEAD:mouseover", "delegates to Platform.GUID")
        TankMark.Platform.GUID = saved
    end)
end)
