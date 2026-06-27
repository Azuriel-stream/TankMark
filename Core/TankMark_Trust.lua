-- Per-player trust axis for Mob DB sharing (SWARM_DESIGN.md sec.7.3). ONE
-- account-wide table, three states with precedence Blocked > Trusted > Neutral:
--
--   TankMarkDB.Trust[playerName] = "blocked" | "trusted"   (absent = neutral)
--
-- A name can only ever hold one value, so the precedence is really a resolution
-- rule: any unrecognized/absent value reads as Neutral (the safe default).
--
-- [v0.29] slice 6.1: the pure model + thin stateful accessors. Definition-only
-- (no top-level WoW calls, no WoW API at all -- pure Lua string comparison), so
-- the off-client tests/ harness can dofile it directly. Resolve() is the pure
-- core (harness-tested); the accessors bind it to the account-wide
-- TankMarkDB.Trust table. Consumers come later: the Options-tab management UI
-- (6.2) and the share-plane gates -- inert click / dropped frames / ignored
-- pull-requests (6.4). Nothing reads or writes this table at runtime yet.

if not TankMark then return end

TankMark.Trust = {}
local Trust = TankMark.Trust

local BLOCKED = "blocked"
local TRUSTED = "trusted"
local NEUTRAL = "neutral"

-- Pure: normalize a raw stored value to one of blocked/trusted/neutral. Any
-- unrecognized value (nil, "", garbage) resolves to neutral.
function Trust.Resolve(stored)
    if stored == BLOCKED then return BLOCKED end
    if stored == TRUSTED then return TRUSTED end
    return NEUTRAL
end

-- The account-wide store, lazily created (defensive -- InitializeDB also seeds it).
local function store()
    TankMarkDB.Trust = TankMarkDB.Trust or {}
    return TankMarkDB.Trust
end

-- Stateful: the effective state for a player name (Resolve over the store).
function Trust.StateOf(name)
    if not name then return NEUTRAL end
    return Trust.Resolve(store()[name])
end

function Trust.IsBlocked(name) return Trust.StateOf(name) == BLOCKED end
function Trust.IsTrusted(name) return Trust.StateOf(name) == TRUSTED end

-- Stateful: set a player's state. NEUTRAL clears the entry (absent = neutral), so
-- the table only ever holds non-default players. An unknown state is a no-op.
function Trust.Set(name, state)
    if not name or name == "" then return end
    local s = store()
    if state == BLOCKED or state == TRUSTED then
        s[name] = state
    elseif state == NEUTRAL then
        s[name] = nil
    end
end

function Trust.Clear(name)
    if not name then return end
    store()[name] = nil
end

-- Exposed so callers (UI, gates) reference the states without hardcoding strings.
Trust.BLOCKED = BLOCKED
Trust.TRUSTED = TRUSTED
Trust.NEUTRAL = NEUTRAL
