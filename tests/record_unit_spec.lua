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
end)
