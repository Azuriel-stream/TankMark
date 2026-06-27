-- Trust (Core/TankMark_Trust.lua) is the pure per-player trust axis for Mob DB
-- sharing (SWARM_DESIGN.md sec.7.3): one account-wide table, states
-- blocked/trusted/neutral with absent = neutral. These specs pin the pure
-- Resolve() normalizer and the thin stateful accessors over a stubbed
-- TankMarkDB.Trust, so the consumers built later (the Options UI in 6.2, the
-- share-plane gates in 6.4) stand on a frozen contract.
describe("Trust", function()
    local Trust = TankMark.Trust

    describe("Resolve (pure)", function()
        it("maps the two stored values to themselves", function()
            eq(Trust.Resolve("blocked"), "blocked", "blocked")
            eq(Trust.Resolve("trusted"), "trusted", "trusted")
        end)

        it("maps absent / unknown values to neutral", function()
            eq(Trust.Resolve(nil), "neutral", "nil -> neutral")
            eq(Trust.Resolve(""), "neutral", "empty -> neutral")
            eq(Trust.Resolve("garbage"), "neutral", "garbage -> neutral")
        end)

        it("exposes the state constants", function()
            eq(Trust.BLOCKED, "blocked", "BLOCKED")
            eq(Trust.TRUSTED, "trusted", "TRUSTED")
            eq(Trust.NEUTRAL, "neutral", "NEUTRAL")
        end)
    end)

    describe("stateful accessors", function()
        -- The accessors read/write the account-wide TankMarkDB.Trust table; stub it.
        local function freshDB() TankMarkDB = { Trust = {} } end

        it("defaults an unset player to neutral", function()
            freshDB()
            eq(Trust.StateOf("Stranger"), "neutral", "neutral default")
            eq(Trust.IsBlocked("Stranger"), false, "not blocked")
            eq(Trust.IsTrusted("Stranger"), false, "not trusted")
        end)

        it("sets and reads blocked / trusted", function()
            freshDB()
            Trust.Set("Griefer", "blocked")
            Trust.Set("Friend", "trusted")
            eq(Trust.StateOf("Griefer"), "blocked", "blocked")
            eq(Trust.IsBlocked("Griefer"), true, "IsBlocked")
            eq(Trust.StateOf("Friend"), "trusted", "trusted")
            eq(Trust.IsTrusted("Friend"), true, "IsTrusted")
        end)

        it("setting neutral clears the entry (absent = neutral)", function()
            freshDB()
            Trust.Set("Bob", "trusted")
            Trust.Set("Bob", "neutral")
            eq(Trust.StateOf("Bob"), "neutral", "back to neutral")
            eq(TankMarkDB.Trust["Bob"], nil, "entry removed")
        end)

        it("Clear removes an entry", function()
            freshDB()
            Trust.Set("Bob", "blocked")
            Trust.Clear("Bob")
            eq(TankMarkDB.Trust["Bob"], nil, "cleared")
        end)

        it("ignores an unknown state and a nil/empty name", function()
            freshDB()
            Trust.Set("Bob", "weird")
            eq(TankMarkDB.Trust["Bob"], nil, "unknown state no-op")
            Trust.Set(nil, "blocked")
            Trust.Set("", "blocked")
            eq(Trust.StateOf(nil), "neutral", "nil name -> neutral")
        end)

        it("lazily creates the store if absent", function()
            TankMarkDB = {}
            Trust.Set("Bob", "trusted")
            eq(TankMarkDB.Trust["Bob"], "trusted", "store auto-created")
        end)
    end)
end)
