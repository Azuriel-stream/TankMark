-- Swarm election core (Core/TankMark_Swarm.lua) is the PURE consensus logic for
-- slice 2 (SWARM_DESIGN.md sec.5.8): deterministic election, the claimant-count
-- rule that unifies election / stickiness / split-brain, the two-filter presence
-- set, and the derived role label. These specs pin the hard consensus behavior
-- off-client, before any of it touches a real raid -- the whole point of building
-- the tracer's keystone test-first.
describe("Swarm election", function()
    local Swarm = TankMark.Swarm

    local function has(arr, name)
        for _, v in ipairs(arr) do if v == name then return true end end
        return false
    end
    local count = table.getn

    describe("DeterministicMax", function()
        it("picks the highest roster rank", function()
            eq(Swarm.DeterministicMax({ "Bob", "Alice" }, { Alice = 2, Bob = 1 }), "Alice", "rank")
        end)
        it("breaks an equal-rank tie by lowest name", function()
            eq(Swarm.DeterministicMax({ "Cara", "Bob" }, { Cara = 1, Bob = 1 }), "Bob", "name")
        end)
        it("returns the lone candidate", function()
            eq(Swarm.DeterministicMax({ "Solo" }, { Solo = 1 }), "Solo", "solo")
        end)
        it("returns nil for an empty set", function()
            eq(Swarm.DeterministicMax({}, {}), nil, "empty")
        end)
    end)

    describe("ElectQueen (claimant-count rule)", function()
        local roster = { Alice = 2, Bob = 1, Cara = 1 }

        it("0 claimants -> fresh election over present candidates", function()
            eq(Swarm.ElectQueen({ "Bob", "Alice" }, {}, roster), "Alice", "fresh")
        end)

        it("1 claimant -> stickiness, even against a higher-rank non-claimant", function()
            -- Bob (assist) is the sitting queen; Alice (leader) is present but not
            -- claiming. Stickiness keeps Bob -- a later higher rank does not depose.
            eq(Swarm.ElectQueen({ "Bob", "Alice" }, { "Bob" }, roster), "Bob", "sticky")
        end)

        it(">=2 claimants -> split-brain tiebreak by rank (overrides stickiness)", function()
            eq(Swarm.ElectQueen({ "Alice", "Bob" }, { "Alice", "Bob" }, roster), "Alice", "rank")
        end)

        it(">=2 claimants -> split-brain tiebreak by name on equal rank", function()
            eq(Swarm.ElectQueen({ "Bob", "Cara" }, { "Cara", "Bob" }, roster), "Bob", "name")
        end)

        it("no present candidates -> nil (no queen)", function()
            eq(Swarm.ElectQueen({}, {}, roster), nil, "none")
        end)
    end)

    describe("ComputePresence (two filters)", function()
        local W = 15
        local NOW = 100

        it("self present from the gate, not heartbeats; claims iff selfAmQueen", function()
            local p, c = Swarm.ComputePresence("Me", true, false, {}, {}, { Me = 1 }, NOW, W)
            eq(count(p), 1, "present count"); eq(has(p, "Me"), true, "self present")
            eq(count(c), 0, "no claim")
            local _, c2 = Swarm.ComputePresence("Me", true, true, {}, {}, { Me = 1 }, NOW, W)
            eq(has(c2, "Me"), true, "self claims")
        end)

        it("a non-candidate self is absent", function()
            local p = Swarm.ComputePresence("Me", false, false, {}, {}, { Me = 1 }, NOW, W)
            eq(count(p), 0, "absent")
        end)

        it("another candidate is present iff heard-in-window AND rank>=1", function()
            local p, c = Swarm.ComputePresence("Me", false, false,
                { Bob = 90 }, { Bob = true }, { Me = 1, Bob = 1 }, NOW, W)
            eq(has(p, "Bob"), true, "Bob present"); eq(has(c, "Bob"), true, "Bob claims")
        end)

        it("eligibility filter: a demoted (rank 0) candidate is dropped even if freshly heard", function()
            local p = Swarm.ComputePresence("Me", false, false,
                { Bob = 99 }, {}, { Me = 1, Bob = 0 }, NOW, W)
            eq(has(p, "Bob"), false, "demote dropped instantly")
        end)

        it("presence filter: a stale (unheard past window) candidate is dropped despite rank", function()
            local p = Swarm.ComputePresence("Me", false, false,
                { Bob = 80 }, {}, { Me = 1, Bob = 1 }, NOW, W) -- 100-80=20 >= 15
            eq(has(p, "Bob"), false, "stale dropped")
        end)

        it("a candidate no longer in the roster is dropped", function()
            local p = Swarm.ComputePresence("Me", false, false,
                { Bob = 99 }, {}, { Me = 1 }, NOW, W) -- Bob left the roster
            eq(has(p, "Bob"), false, "left dropped")
        end)
    end)

    describe("DeriveRole (role is derived, not stored)", function()
        it("bootstrapping wins regardless of any tentative queen", function()
            eq(Swarm.DeriveRole("Me", "Me", true), "BOOTSTRAP", "boot")
        end)
        it("queen == self -> QUEEN", function()
            eq(Swarm.DeriveRole("Me", "Me", false), "QUEEN", "queen")
        end)
        it("queen == other -> DRONE", function()
            eq(Swarm.DeriveRole("Me", "Bob", false), "DRONE", "drone")
        end)
        it("no queen -> NONE", function()
            eq(Swarm.DeriveRole("Me", nil, false), "NONE", "none")
        end)
    end)

    describe("end-to-end (presence -> election)", function()
        it("stickiness holds when a higher-rank candidate joins mid-incumbency", function()
            -- Me(assist) not claiming; Bob(assist) is the incumbent queen; Alice
            -- (leader) just joined and beats amQueen=false (bootstrapping). The
            -- lone claimant Bob must keep the crown.
            local roster = { Me = 1, Bob = 1, Alice = 2 }
            local p, c = Swarm.ComputePresence("Me", true, false,
                { Bob = 98, Alice = 99 }, { Bob = true, Alice = false }, roster, 100, 15)
            eq(Swarm.ElectQueen(p, c, roster), "Bob", "incumbent kept")
        end)

        it("split-brain of two self-declared queens converges to the higher rank", function()
            local roster = { Me = 1, Bob = 1, Alice = 2 }
            local p, c = Swarm.ComputePresence("Me", true, true, -- self also claims
                { Bob = 98, Alice = 99 }, { Bob = false, Alice = true }, roster, 100, 15)
            -- claimants = { Me, Alice }; Alice (leader) wins, Me must yield.
            eq(Swarm.ElectQueen(p, c, roster), "Alice", "higher rank wins")
        end)
    end)

    describe("tunables", function()
        it("presence window is interval * miss (15s)", function()
            eq(Swarm.PRESENCE_WINDOW, 15, "window")
        end)
    end)
end)
