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

    -- [v0.29] slice 5a.2: AdvertisedClaim splits the wire/claim bit from the election
    -- output (selfAmQueen). These pin the truth table; the handoff block below proves
    -- it moves the crown through the existing claimant-count rule.
    describe("AdvertisedClaim (claim-override split)", function()
        local AC = Swarm.AdvertisedClaim
        it("a real queen advertises a claim", function()
            eq(AC(true, false, false), true, "selfAmQueen")
        end)
        it("a handoff target claims via pendingClaim alone (no selfAmQueen write)", function()
            eq(AC(false, true, false), true, "pendingClaim")
        end)
        it("a relinquishing queen drops its own claim", function()
            eq(AC(true, false, true), false, "relinquish overrides queen")
        end)
        it("an idle non-queen non-target advertises nothing", function()
            eq(AC(false, false, false), false, "idle")
        end)
        it("is behavior-identical to selfAmQueen while dormant (both flags false)", function()
            eq(AC(true, false, false), true, "queen == selfAmQueen")
            eq(AC(false, false, false), false, "drone == selfAmQueen")
        end)
        it("always returns a strict boolean", function()
            eq(AC(true, false, false), true, "true not truthy obj")
            eq(AC(false, false, false), false, "false not nil")
        end)
    end)

    -- [v0.29] slice 5a.2: the §5.10 happy-path crown-pass, proven purely. Queen
    -- Alice(rank2) hands to Bob(rank1). The crown moves ONLY by changing the claimant
    -- set (pendingClaim/relinquish fed through AdvertisedClaim), never by writing
    -- selfAmQueen -- so the deterministic election stays the sole marking authority and
    -- the single-queen invariant holds at each step. Dormant at runtime; activated in 5a.3.
    describe("handoff via claim-set (sec.5.10, dormant override cases)", function()
        local roster = { Alice = 2, Bob = 1, Cara = 1 }
        local AC = Swarm.AdvertisedClaim

        it("step 2 (drone view): target claims -> 2 claimants -> higher-rank queen keeps the crown, zero gap", function()
            -- Cara hears Alice still queen (amQueen=1) and Bob now pendingClaim (amQueen=1).
            local p, c = Swarm.ComputePresence("Cara", true, false,
                { Alice = 99, Bob = 99 },
                { Alice = AC(true, false, false), Bob = AC(false, true, false) },
                roster, 100, 15)
            eq(count(c), 2, "two claimants")
            eq(Swarm.ElectQueen(p, c, roster), "Alice", "queen retained (rank tiebreak)")
        end)

        it("step 3 (drone view): queen relinquishes -> 1 claimant -> crown moves to the lower-rank target", function()
            -- Cara now hears Alice amQueen=0 (relinquish) and Bob amQueen=1.
            local p, c = Swarm.ComputePresence("Cara", true, false,
                { Alice = 99, Bob = 99 },
                { Alice = AC(true, false, true), Bob = AC(false, true, false) },
                roster, 100, 15)
            eq(count(c), 1, "lone claimant")
            eq(Swarm.ElectQueen(p, c, roster), "Bob", "crown moved to target via stickiness")
        end)

        it("the relinquishing queen excludes ITSELF from its own claimant set", function()
            -- Alice's own client: selfAmQueen=true but relinquish=true -> claim=false.
            local claim = AC(true, false, true)
            local p, c = Swarm.ComputePresence("Alice", true, claim,
                { Bob = 99 }, { Bob = true }, roster, 100, 15)
            eq(has(c, "Alice"), false, "self not claiming")
            eq(Swarm.ElectQueen(p, c, roster), "Bob", "yields to target")
        end)

        it("the target's own client claims via pendingClaim and wins once the queen yields", function()
            -- Bob's own client: not yet queen, pendingClaim=true; Alice already amQueen=0.
            local claim = AC(false, true, false)
            local p, c = Swarm.ComputePresence("Bob", true, claim,
                { Alice = 99 }, { Alice = false }, roster, 100, 15)
            eq(has(c, "Bob"), true, "self claims via pendingClaim")
            eq(Swarm.ElectQueen(p, c, roster), "Bob", "target elected")
        end)
    end)
end)
