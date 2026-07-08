-- RecordUnit Tier-A metadata stamping (marking-redesign Phase 1).
--
-- RecordUnit reads WoW state through the Locals directly (not the injected
-- board), so this spec stubs the minimum game Locals + TankMark state the record
-- path touches, then asserts the written entry carries creatureType + tier.
-- The harness already loaded Core/TankMark_Processor.lua, and L is the same
-- TankMark.Locals table the SUT captured at load, so post-load stubs are visible.

local L = TankMark.Locals

-- Install the minimal game-state stubs for one record, return the GUID to record.
local function setup(cType, classification, name)
    TankMarkDB = { Zones = {} }
    TankMark.recordedGUIDs = {}
    TankMark.activeDB = {}
    TankMark.IsRecorderActive = true
    -- Vanilla baseline (a GUID is an addressable handle). The Ascension case below
    -- flips this to false to prove reads route through the live token instead.
    TankMark.Platform.Caps.hasScanner = true
    L._UnitIsPlayer       = function() return false end
    L._UnitIsFriend       = function() return false end
    L._UnitCreatureType   = function() return cType end
    L._UnitClassification = function() return classification end
    L._UnitName           = function() return name end
    TankMark.GetCachedZone = function() return "Test Zone" end
    TankMark.Print         = function() end
end

describe("RecordUnit Tier-A metadata", function()
    it("stamps creatureType and tier on a new entry, keeping the defaults", function()
        setup("Humanoid", "elite", "Test Bandit")
        TankMark:RecordUnit("guid-1")
        local e = TankMarkDB.Zones["Test Zone"]["Test Bandit"]
        eq(e ~= nil, true, "entry created")
        eq(e.creatureType, "Humanoid", "creatureType")
        eq(e.tier, "elite", "tier")
        eq(e.prio, 5, "prio default unchanged")
        eq(e.marks[1], 8, "marks default unchanged")
        eq(e.type, "KILL", "type default unchanged")
    end)

    it("captures the worldboss classification", function()
        setup("Elemental", "worldboss", "Test Boss")
        TankMark:RecordUnit("guid-2")
        local e = TankMarkDB.Zones["Test Zone"]["Test Boss"]
        eq(e.creatureType, "Elemental", "creatureType")
        eq(e.tier, "worldboss", "tier")
    end)

    it("skips critters entirely (no entry, no fields)", function()
        setup("Critter", "normal", "Small Frog")
        TankMark:RecordUnit("guid-3")
        eq(TankMarkDB.Zones["Test Zone"], nil, "no zone entry created for a critter")
    end)

    it("reads mob attributes off the live token on a scanner-less platform (Ascension)", function()
        -- On Ascension a GUID is not a re-readable handle -- the game Locals only
        -- answer for a live unit token. Stub them to return data ONLY for the token,
        -- so a correct RecordUnit must route every read through the passed unit; the
        -- GUID stays the dedup/identity key.
        setup("Humanoid", "elite", "Token Bandit")
        local TOKEN, GUID = "mouseover", "0xF1300ABCDE"
        local function tokenOnly(ret)
            return function(u) if u == TOKEN then return ret end end
        end
        L._UnitIsPlayer       = function(u) return false end
        L._UnitIsFriend       = function(u) return false end
        L._UnitCreatureType   = tokenOnly("Humanoid")
        L._UnitClassification = tokenOnly("elite")
        L._UnitName           = tokenOnly("Token Bandit")
        TankMark.Platform.Caps.hasScanner = false

        TankMark:RecordUnit(GUID, TOKEN)

        local e = TankMarkDB.Zones["Test Zone"]["Token Bandit"]
        eq(e ~= nil, true, "entry created from token reads")
        eq(e.creatureType, "Humanoid", "creatureType off token")
        eq(e.tier, "elite", "tier off token")
        eq(TankMark.recordedGUIDs[GUID], true, "dedup keyed on GUID, not token")

        TankMark.Platform.Caps.hasScanner = true -- restore for later specs
    end)

    it("still reads off the GUID on a scanner platform when no token is passed (Vanilla)", function()
        -- The scanner caller passes RecordUnit(guid) with no unit arg. With a scanner
        -- the GUID is addressable, so reads must land on the GUID -- byte-identical to
        -- the pre-seam behavior.
        setup("Beast", "normal", "Vanilla Wolf")
        local GUID = "guid-vanilla"
        local function guidOnly(ret)
            return function(u) if u == GUID then return ret end end
        end
        L._UnitIsPlayer       = function(u) return false end
        L._UnitIsFriend       = function(u) return false end
        L._UnitCreatureType   = guidOnly("Beast")
        L._UnitClassification = guidOnly("normal")
        L._UnitName           = guidOnly("Vanilla Wolf")

        TankMark:RecordUnit(GUID) -- no unit arg, exactly like the scanner path

        local e = TankMarkDB.Zones["Test Zone"]["Vanilla Wolf"]
        eq(e ~= nil, true, "entry created from GUID reads")
        eq(e.creatureType, "Beast", "creatureType off GUID")
        eq(e.tier, "normal", "tier off GUID")
    end)
end)
