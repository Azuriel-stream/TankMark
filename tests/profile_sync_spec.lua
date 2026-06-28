-- Profile-sync drone logic (Core/TankMark_Swarm.lua, slice 4 / SWARM_DESIGN.md
-- sec.6.1): the security-sensitive receive edge (OnProfile -- queen-gated apply,
-- empty-keeps) and the pull predicate (EvaluatePull -- the (queen,version,zone)
-- triple that drives convergence). Pinned off-client so the trust gate and the
-- convergence rule cannot silently regress.
describe("Profile sync", function()
    local Swarm = TankMark.Swarm
    local L = TankMark.Locals

    -- Swarm reads the live zone through Locals; this mutable stub stands in.
    local zone = "Blackrock Depths"
    L._GetRealZoneText = function() return zone end

    local function reset()
        zone = "Blackrock Depths"
        Swarm.currentQueen = "Queenie"
        Swarm.selfAmQueen  = false
        Swarm.versionHeard = {}
        Swarm.appliedKey   = nil
        Swarm.needPull     = false
        TankMarkProfileDB  = {}
        TankMark.ApplyProfileToSession = nil -- skip the render path in these specs
    end

    local function rec(z, ver, entries)
        return { kind = "P", zone = z, planVersion = ver, entries = entries }
    end

    describe("OnProfile (queen-gated apply)", function()
        it("ignores a snapshot from anyone but our elected queen", function()
            reset()
            Swarm.OnProfile("Impostor", rec("Blackrock Depths", 5, {
                { mark = 8, tank = "Bob", role = "TANK" },
            }))
            eq(TankMarkProfileDB["Blackrock Depths"], nil, "no overwrite")
            eq(Swarm.appliedKey, nil, "no key recorded")
        end)

        it("overwrites the local slot with a non-empty snapshot from the queen", function()
            reset()
            Swarm.OnProfile("Queenie", rec("Blackrock Depths", 5, {
                { mark = 8, tank = "Bob", role = "TANK" },
                { mark = 6, tank = "Sue", role = "CC" },
            }))
            local slot = TankMarkProfileDB["Blackrock Depths"]
            eq(table.getn(slot), 2, "two entries")
            eq(slot[1].tank, "Bob", "tank")
            eq(slot[2].role, "CC", "role")
            eq(slot[1].healers, "", "healers blanked")
            eq(Swarm.appliedKey.queen, "Queenie", "key.queen")
            eq(Swarm.appliedKey.version, 5, "key.version")
            eq(Swarm.appliedKey.zone, "Blackrock Depths", "key.zone")
        end)

        it("KEEPS the current plan on an empty snapshot but records the version", function()
            reset()
            TankMarkProfileDB["Blackrock Depths"] =
                { { mark = 8, tank = "Old", role = "TANK", healers = "" } }
            Swarm.needPull = true
            Swarm.OnProfile("Queenie", rec("Blackrock Depths", 9, {}))
            local slot = TankMarkProfileDB["Blackrock Depths"]
            eq(table.getn(slot), 1, "old plan kept")
            eq(slot[1].tank, "Old", "old tank kept")
            eq(Swarm.appliedKey.version, 9, "version still recorded")
            eq(Swarm.needPull, false, "pull disarmed")
        end)
    end)

    describe("EvaluatePull (pull predicate)", function()
        it("never pulls when not a drone", function()
            reset()
            Swarm.EvaluatePull("Queenie", "QUEEN")
            eq(Swarm.needPull, false, "queen renders its own DB")
            Swarm.EvaluatePull(nil, "NONE")
            eq(Swarm.needPull, false, "no queen")
        end)

        it("arms a pull when the queen's heard version differs from applied", function()
            reset()
            Swarm.versionHeard["Queenie"] = 5
            Swarm.appliedKey = { queen = "Queenie", version = 4, zone = "Blackrock Depths" }
            Swarm.EvaluatePull("Queenie", "DRONE")
            eq(Swarm.needPull, true, "version mismatch")
        end)

        it("stays quiet when the applied triple matches", function()
            reset()
            Swarm.versionHeard["Queenie"] = 5
            Swarm.appliedKey = { queen = "Queenie", version = 5, zone = "Blackrock Depths" }
            Swarm.EvaluatePull("Queenie", "DRONE")
            eq(Swarm.needPull, false, "up to date")
        end)

        it("arms a pull on a queen change (failover)", function()
            reset()
            Swarm.versionHeard["NewQueen"] = 2
            Swarm.appliedKey = { queen = "OldQueen", version = 2, zone = "Blackrock Depths" }
            Swarm.EvaluatePull("NewQueen", "DRONE")
            eq(Swarm.needPull, true, "queen differs")
        end)

        it("arms a pull on a zone change", function()
            reset()
            zone = "Dire Maul"
            Swarm.versionHeard["Queenie"] = 5
            Swarm.appliedKey = { queen = "Queenie", version = 5, zone = "Blackrock Depths" }
            Swarm.EvaluatePull("Queenie", "DRONE")
            eq(Swarm.needPull, true, "zone differs")
        end)

        it("defers (does not arm) when the zone is unknown", function()
            reset()
            zone = ""
            Swarm.versionHeard["Queenie"] = 5
            Swarm.EvaluatePull("Queenie", "DRONE")
            eq(Swarm.needPull, false, "cold-login zone deferred")
        end)
    end)

    -- Push-on-promotion (slice 4): becoming queen propagates the current plan even
    -- when it changed without a version bump (e.g. a pre-promotion drone-side edit),
    -- so drones converge on a handoff with no pull latency.
    describe("OnPromoted (push-on-promotion)", function()
        local captured
        L._GetNumRaidMembers  = function() return 0 end
        L._GetNumPartyMembers = function() return 1 end
        TankMark.SyncPrefix   = "TM_SYNC"
        function TankMark:QueueMessage(prefix, text, channel)
            captured = { prefix = prefix, text = text, channel = channel }
        end

        it("bumps the version and pushes the current zone's plan", function()
            reset()
            captured = nil
            zone = "Blackrock Depths"
            Swarm.planVersion = 4
            TankMarkProfileDB["Blackrock Depths"] = { { mark = 8, tank = "Bob", role = "TANK" } }
            Swarm.OnPromoted()
            eq(Swarm.planVersion, 5, "version bumped")
            eq(captured ~= nil, true, "a message was queued")
            eq(captured.text, "P;Blackrock Depths;5;8,Bob,T", "pushed snapshot at bumped version")
        end)

        it("bumps but does not push when the zone is unknown (cold login)", function()
            reset()
            captured = nil
            zone = ""
            Swarm.planVersion = 4
            Swarm.OnPromoted()
            eq(Swarm.planVersion, 5, "version still bumped")
            eq(captured, nil, "no push with unknown zone")
        end)
    end)

    -- [v0.29] slice 7.2: PushProfile appends one HR healer record per entry that HAS
    -- healers, right after the P, at the SAME planVersion. Dormant on the wire until
    -- 7.3 (drones drop the unknown HR), but the queen-side EMISSION is pinned here.
    describe("PushProfile (slice 7.2 healer records)", function()
        local sent
        L._GetNumRaidMembers  = function() return 0 end
        L._GetNumPartyMembers = function() return 1 end
        TankMark.SyncPrefix   = "TM_SYNC"
        function TankMark:QueueMessage(prefix, text, channel)
            table.insert(sent, text)
        end

        it("sends the P first, then one HR per healer-bearing entry (same version)", function()
            reset()
            sent = {}
            zone = "Blackrock Depths"
            Swarm.planVersion = 7
            TankMarkProfileDB["Blackrock Depths"] = {
                { mark = 8, tank = "Bob", role = "TANK", healers = "Aine Boldo" },
                { mark = 6, tank = "Sue", role = "CC",   healers = "" },
                { mark = 1, tank = "Tim", role = "TANK", healers = "Cara" },
            }
            Swarm.PushProfile("Blackrock Depths")
            eq(table.getn(sent), 3, "P + 2 HRs (healer-less entry skipped)")
            eq(sent[1], "P;Blackrock Depths;7;8,Bob,T;6,Sue,C;1,Tim,T", "P first")
            eq(sent[2], "HR;Blackrock Depths;7;8;Aine Boldo", "HR for mark 8")
            eq(sent[3], "HR;Blackrock Depths;7;1;Cara", "HR for mark 1")
        end)

        it("sends no HR when no entry has healers", function()
            reset()
            sent = {}
            zone = "Z"
            Swarm.planVersion = 2
            TankMarkProfileDB["Z"] = { { mark = 8, tank = "Bob", role = "TANK", healers = "" } }
            Swarm.PushProfile("Z")
            eq(table.getn(sent), 1, "only the P")
            eq(sent[1], "P;Z;2;8,Bob,T", "P only")
        end)
    end)

    -- [v0.29] slice 7.3: OnHealerRecord layers healers onto the entry the matching P
    -- already applied -- queen-only + version-gated, no-op (no error) on a miss.
    describe("OnHealerRecord (slice 7.3 apply)", function()
        local function hrec(z, ver, m, h)
            return { kind = "HR", zone = z, planVersion = ver, mark = m, healers = h }
        end
        local function seedProfile(z, ver)
            TankMarkProfileDB[z] = {
                { mark = 8, tank = "Bob", role = "TANK", healers = "" },
                { mark = 6, tank = "Sue", role = "CC",   healers = "" },
            }
            Swarm.versionHeard["Queenie"] = ver
        end

        it("sets healers on the entry whose mark matches, leaving others untouched", function()
            reset()
            seedProfile("Blackrock Depths", 5)
            Swarm.OnHealerRecord("Queenie", hrec("Blackrock Depths", 5, 8, "Aine Boldo"))
            eq(TankMarkProfileDB["Blackrock Depths"][1].healers, "Aine Boldo", "mark 8 set")
            eq(TankMarkProfileDB["Blackrock Depths"][2].healers, "", "mark 6 untouched")
        end)

        it("ignores an HR from anyone but our elected queen", function()
            reset()
            seedProfile("Blackrock Depths", 5)
            Swarm.OnHealerRecord("Impostor", hrec("Blackrock Depths", 5, 8, "Evil"))
            eq(TankMarkProfileDB["Blackrock Depths"][1].healers, "", "not applied")
        end)

        it("drops a stale HR whose version != the version last heard", function()
            reset()
            seedProfile("Blackrock Depths", 5)
            Swarm.OnHealerRecord("Queenie", hrec("Blackrock Depths", 4, 8, "Stale"))
            eq(TankMarkProfileDB["Blackrock Depths"][1].healers, "", "stale dropped")
        end)

        it("is a no-op when the zone has no applied profile", function()
            reset()
            Swarm.versionHeard["Queenie"] = 5
            Swarm.OnHealerRecord("Queenie", hrec("Unseen Zone", 5, 8, "Aine"))
            eq(TankMarkProfileDB["Unseen Zone"], nil, "nothing created")
        end)

        it("is a no-op when no entry has the record's mark", function()
            reset()
            seedProfile("Blackrock Depths", 5)
            Swarm.OnHealerRecord("Queenie", hrec("Blackrock Depths", 5, 1, "Nobody"))
            eq(TankMarkProfileDB["Blackrock Depths"][1].healers, "", "mark 8 untouched")
            eq(TankMarkProfileDB["Blackrock Depths"][2].healers, "", "mark 6 untouched")
        end)
    end)
end)
