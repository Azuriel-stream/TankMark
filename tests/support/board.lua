-- make_board(overrides) -> a mock ports board for DecideMark and friends.
--
-- Safe defaults model "nothing going on": in combat, no mark busy or disabled,
-- no free icon, no CC player, no skull blocker, logDecision a no-op. A test
-- overrides only what it needs:
--   busy      = {[8]=true}        -- IsMarkBusy(icon)
--   ownerPrio = {[8]=5}           -- GetMarkOwnerPriority(icon) (default 99 = untracked)
--   free        = 4               -- GetFreeTankIcon() return
--   disabled    = {[4]=true}      -- disabledMarks[icon]
--   creatureType = "Humanoid"     -- UnitCreatureType(guid) live read (default nil).
--                                 -- May also be a guid->type table for multi-mob
--                                 -- pull specs that need per-mob reads.
--   tier        = "elite"         -- UnitClassification(guid); single value or a
--                                 -- guid->tier table (Phase 4 DecidePull).
--   ccSlots     = { {mark=6, class="MAGE", race="Orc", alive=true, used=false, disabled=false} }
--                                 -- GetCCSlots() snapshot (default {})
--   tankRoster  = { {mark=8, player="T", alive=true} }  -- GetTankRoster() (default {})
--   blocker     = {icon=4, prio=2}-- GetBlockingMarkInfo() best blocker
--   playerInCombat / guidInCombat = false
function make_board(o)
    o = o or {}
    local function flag(v, default)
        if v == nil then return default end
        return v
    end
    local function lookup(t, i) return (t or {})[i] end
    -- creatureType/tier may be a single value (legacy specs) or a guid->value
    -- table (pull specs, which need per-mob reads).
    local function perGuid(v, g)
        if type(v) == "table" then return v[g] end
        return v
    end
    return {
        playerInCombat      = function()  return flag(o.playerInCombat, true) end,
        guidInCombat        = function()  return flag(o.guidInCombat, true) end,
        isMarkBusy          = function(i) return lookup(o.busy, i) or false end,
        markOwnerPriority   = function(i) return lookup(o.ownerPrio, i) or 99 end,
        getFreeTankIcon     = function()  return o.free end,
        isDisabled          = function(i) return lookup(o.disabled, i) or false end,
        creatureType        = function(g) return perGuid(o.creatureType, g) end,
        tier                = function(g) return perGuid(o.tier, g) end,
        getCCSlots          = function()  return o.ccSlots or {} end,
        getTankRoster       = function()  return o.tankRoster or {} end,
        getBlockingMarkInfo = function()
            if o.blocker then
                return o.blocker.icon, o.blocker.guid or "blocker-guid", o.blocker.prio, o.blocker.hp or 100
            end
            return nil, nil, 99, 999999
        end,
        logDecision         = function() end,
    }
end
