-- SyncCodec (Core/TankMark_SyncCodec.lua) is the pure wire codec for the "M"
-- mob record -- string <-> typed record, no client state. These specs pin the
-- round-trip and the rejection rules so the encoder and decoder can never drift
-- apart again (the defect slice 1 exists to fix), and so the validation that
-- HandleSync used to do inline stays enforced.
describe("SyncCodec", function()
    local Codec = TankMark.SyncCodec

    describe("EncodeMob", function()
        it("emits the canonical M wire string for a full entry", function()
            local s = Codec.EncodeMob("Blackrock Depths", "Lord Roccor",
                { prio = 3, marks = { 8 }, type = "KILL", class = "WARRIOR" })
            eq(s, "M;Blackrock Depths;Lord Roccor;3;8;KILL;WARRIOR", "wire")
        end)

        -- [v0.29] slice 6: the mark field now carries the FULL array as a dot-list
        -- (sequential marks transfer losslessly), not just marks[1].
        it("syncs the FULL marks array as a dot-list", function()
            local s = Codec.EncodeMob("Z", "M", { prio = 1, marks = { 5, 6, 7 } })
            eq(s, "M;Z;M;1;5.6.7;KILL;NIL", "full array")
        end)

        it("encodes a single-mark mob byte-identical to the legacy wire", function()
            local s = Codec.EncodeMob("Z", "M", { prio = 1, marks = { 5 } })
            eq(s, "M;Z;M;1;5;KILL;NIL", "single mark = legacy form")
        end)

        it("defaults mark=8, type=KILL, class=NIL when absent", function()
            local s = Codec.EncodeMob("Z", "M", { prio = 2 })
            eq(s, "M;Z;M;2;8;KILL;NIL", "defaults")
        end)

        it("returns nil when zone, mob, data, or prio is missing", function()
            eq(Codec.EncodeMob(nil, "M", { prio = 1 }), nil, "no zone")
            eq(Codec.EncodeMob("Z", nil, { prio = 1 }), nil, "no mob")
            eq(Codec.EncodeMob("Z", "M", nil), nil, "no data")
            eq(Codec.EncodeMob("Z", "M", { marks = { 8 } }), nil, "no prio")
        end)
    end)

    describe("Decode", function()
        it("parses a well-formed M record into a typed table", function()
            local r = Codec.Decode("M;Blackrock Depths;Lord Roccor;3;8;KILL;WARRIOR")
            eq(r.kind, "M", "kind")
            eq(r.zone, "Blackrock Depths", "zone")
            eq(r.mob, "Lord Roccor", "mob")
            eq(r.prio, 3, "prio")
            eq(r.mark, 8, "mark")
            eq(r.type, "KILL", "type")
            eq(r.class, "WARRIOR", "class")
        end)

        it("returns prio and mark as numbers, not strings", function()
            local r = Codec.Decode("M;Z;M;3;8;KILL;NIL")
            eq(type(r.prio), "number", "prio type")
            eq(type(r.mark), "number", "mark type")
        end)

        it("decodes the NIL class sentinel back to nil", function()
            local r = Codec.Decode("M;Z;M;3;8;KILL;NIL")
            eq(r.class, nil, "class nil")
        end)

        -- [v0.29] slice 6: the widened mark field is a '.'-joined list.
        it("decodes a multi-mark dot-list into a marks array", function()
            local r = Codec.Decode("M;Z;M;1;5.6.7;KILL;NIL")
            eq(table.getn(r.marks), 3, "marks count")
            eq(r.marks[1], 5, "marks[1]")
            eq(r.marks[2], 6, "marks[2]")
            eq(r.marks[3], 7, "marks[3]")
            eq(r.mark, 5, "mark stays = marks[1]")
        end)

        it("decodes a legacy single-mark wire into a one-element marks array", function()
            local r = Codec.Decode("M;Z;M;3;8;KILL;NIL")
            eq(table.getn(r.marks), 1, "one element")
            eq(r.marks[1], 8, "marks[1]")
            eq(r.mark, 8, "mark")
        end)

        it("rejects the whole record if any mark element is out of range", function()
            eq(Codec.Decode("M;Z;M;1;5.9.7;KILL;NIL"), nil, "9 out of range")
            eq(Codec.Decode("M;Z;M;1;5.x.7;KILL;NIL"), nil, "non-numeric element")
        end)

        it("rejects an unknown type tag", function()
            eq(Codec.Decode("X;Z;M;3;8;KILL;NIL"), nil, "X tag")
        end)

        it("rejects non-numeric prio or mark", function()
            eq(Codec.Decode("M;Z;M;x;8;KILL;NIL"), nil, "bad prio")
            eq(Codec.Decode("M;Z;M;3;y;KILL;NIL"), nil, "bad mark")
        end)

        it("rejects a mark outside the 0-8 icon range", function()
            eq(Codec.Decode("M;Z;M;3;9;KILL;NIL"), nil, "mark 9")
        end)

        it("rejects nil and structurally malformed input", function()
            eq(Codec.Decode(nil), nil, "nil msg")
            eq(Codec.Decode("M;Z;M;3"), nil, "too few fields")
            eq(Codec.Decode(""), nil, "empty")
        end)
    end)

    describe("round-trip", function()
        it("EncodeMob -> Decode preserves every field", function()
            local s = Codec.EncodeMob("Dire Maul", "Pusillin",
                { prio = 4, marks = { 7 }, type = "CC", class = "MAGE" })
            local r = Codec.Decode(s)
            eq(r.zone, "Dire Maul", "zone")
            eq(r.mob, "Pusillin", "mob")
            eq(r.prio, 4, "prio")
            eq(r.mark, 7, "mark")
            eq(r.type, "CC", "type")
            eq(r.class, "MAGE", "class")
        end)

        it("round-trips a classless entry through the NIL sentinel", function()
            local s = Codec.EncodeMob("Z", "Trash", { prio = 5, marks = { 6 }, type = "KILL" })
            local r = Codec.Decode(s)
            eq(r.class, nil, "class stays nil")
            eq(r.mark, 6, "mark")
        end)

        -- [v0.29] slice 6: a sequential-mark mob survives Encode -> Decode intact.
        it("round-trips the full marks array losslessly", function()
            local r = Codec.Decode(Codec.EncodeMob("Dire Maul", "Pusillin",
                { prio = 4, marks = { 8, 1, 2, 3 }, type = "KILL" }))
            eq(table.getn(r.marks), 4, "count")
            eq(r.marks[1], 8, "m1")
            eq(r.marks[4], 3, "m4")
        end)
    end)

    -- [v0.29] slice 2/4: the "Q" control heartbeat shares the codec's typed
    -- dispatch. Slice 4 made planVersion a live second field on the wire.
    describe("Q heartbeat", function()
        it("encodes amQueen + planVersion to the Q wire", function()
            eq(Codec.EncodeHeartbeat(true, 7), "Q;1;7", "amQueen true, v7")
            eq(Codec.EncodeHeartbeat(false, 0), "Q;0;0", "amQueen false, v0")
        end)

        it("defaults planVersion to 0 when omitted", function()
            eq(Codec.EncodeHeartbeat(true), "Q;1;0", "no version arg")
        end)

        it("decodes a heartbeat into a typed record with planVersion", function()
            local r = Codec.Decode("Q;1;42")
            eq(r.kind, "Q", "kind")
            eq(r.amQueen, true, "amQueen true")
            eq(r.planVersion, 42, "planVersion")
            eq(Codec.Decode("Q;0;3").amQueen, false, "amQueen false")
        end)

        it("round-trips amQueen + planVersion through Encode -> Decode", function()
            local r = Codec.Decode(Codec.EncodeHeartbeat(true, 9))
            eq(r.amQueen, true, "amQueen")
            eq(r.planVersion, 9, "planVersion")
            eq(Codec.Decode(Codec.EncodeHeartbeat(false, 0)).amQueen, false, "false")
        end)

        it("treats a legacy versionless 'Q;1' as planVersion 0 (slice-2 peer)", function()
            local r = Codec.Decode("Q;1")
            eq(r.kind, "Q", "kind")
            eq(r.amQueen, true, "amQueen")
            eq(r.planVersion, 0, "missing version -> 0")
        end)

        it("rejects a heartbeat with a missing/malformed amQueen flag", function()
            eq(Codec.Decode("Q;"), nil, "empty flag")
            eq(Codec.Decode("Q;2;0"), nil, "out-of-range flag")
            eq(Codec.Decode("Q;x;0"), nil, "non-numeric flag")
        end)
    end)

    -- [v0.29] slice 4: the "P" profile snapshot (queen->drones). HUD-minimal
    -- (mark+tank+role), one atomic message, healers deliberately omitted.
    describe("P profile snapshot", function()
        it("emits the canonical P wire with T/C roles", function()
            local s = Codec.EncodeProfile("Blackrock Depths", 3, {
                { mark = 8, tank = "Bob",  role = "TANK" },
                { mark = 6, tank = "Sue",  role = "CC"   },
            })
            eq(s, "P;Blackrock Depths;3;8,Bob,T;6,Sue,C", "wire")
        end)

        it("emits a header-only string for an empty profile", function()
            eq(Codec.EncodeProfile("Z", 5, {}), "P;Z;5", "empty")
            eq(Codec.EncodeProfile("Z", 5, nil), "P;Z;5", "nil entries")
        end)

        it("defaults planVersion to 0 and skips a markless entry", function()
            local s = Codec.EncodeProfile("Z", nil, { { tank = "X", role = "TANK" } })
            eq(s, "P;Z;0", "no version, markless entry dropped")
        end)

        it("decodes a P snapshot into typed entries (C -> CC, T -> TANK)", function()
            local r = Codec.Decode("P;Blackrock Depths;3;8,Bob,T;6,Sue,C")
            eq(r.kind, "P", "kind")
            eq(r.zone, "Blackrock Depths", "zone")
            eq(r.planVersion, 3, "planVersion")
            eq(table.getn(r.entries), 2, "entry count")
            eq(r.entries[1].mark, 8, "e1.mark")
            eq(r.entries[1].tank, "Bob", "e1.tank")
            eq(r.entries[1].role, "TANK", "e1.role")
            eq(r.entries[2].role, "CC", "e2.role")
        end)

        it("decodes an empty snapshot to a zero-length entry list", function()
            local r = Codec.Decode("P;Z;5")
            eq(r.kind, "P", "kind")
            eq(r.zone, "Z", "zone")
            eq(table.getn(r.entries), 0, "no entries")
        end)

        it("preserves an empty tank field", function()
            local r = Codec.Decode("P;Z;1;8,,T")
            eq(r.entries[1].tank, "", "empty tank")
            eq(r.entries[1].mark, 8, "mark")
        end)

        it("rejects the WHOLE message on a single malformed entry", function()
            eq(Codec.Decode("P;Z;1;8,Bob,T;9,Sue,C"), nil, "mark 9 out of range")
            eq(Codec.Decode("P;Z;1;x,Bob,T"), nil, "non-numeric mark")
            eq(Codec.Decode("P;Z;1;8,Bob,X"), nil, "bad role char")
            eq(Codec.Decode("P;Z;1;8,Bob"), nil, "missing role field")
        end)

        it("rejects a P with an empty zone or non-numeric version", function()
            eq(Codec.Decode("P;;3"), nil, "empty zone")
            eq(Codec.Decode("P;Z;x"), nil, "bad version")
        end)

        it("round-trips a full profile through Encode -> Decode", function()
            local entries = {
                { mark = 1, tank = "Tankadin", role = "TANK" },
                { mark = 7, tank = "Sheepmage", role = "CC" },
            }
            local r = Codec.Decode(Codec.EncodeProfile("Dire Maul", 12, entries))
            eq(r.planVersion, 12, "version")
            eq(r.entries[1].tank, "Tankadin", "tank")
            eq(r.entries[2].role, "CC", "role")
        end)
    end)

    -- [v0.29] slice 4: the "PR" pull-request (drone->queen).
    describe("PR pull-request", function()
        it("encodes and decodes a bare zone request", function()
            eq(Codec.EncodePull("Blackrock Depths"), "PR;Blackrock Depths", "wire")
            local r = Codec.Decode("PR;Blackrock Depths")
            eq(r.kind, "PR", "kind")
            eq(r.zone, "Blackrock Depths", "zone")
        end)

        it("does not collide with the single-char P tag", function()
            eq(Codec.Decode("P;Z;5").kind, "P", "P stays P")
            eq(Codec.Decode("PR;Z").kind, "PR", "PR stays PR")
        end)

        it("rejects an empty zone", function()
            eq(Codec.Decode("PR;"), nil, "empty zone")
        end)
    end)

    -- [v0.29] slice 5a.1: the "H" handoff offer (queen->target). A directed
    -- crown-pass, broadcast; one field, the target name. Pure codec only -- no
    -- election/runtime behavior rides on it at this checkpoint (SWARM_DESIGN.md
    -- sec.5.10). These specs pin the wire so 5a.2/5a.3 build on a frozen format.
    describe("H handoff offer", function()
        it("encodes and decodes a directed offer", function()
            eq(Codec.EncodeHandoff("Bob"), "H;Bob", "wire")
            local r = Codec.Decode("H;Bob")
            eq(r.kind, "H", "kind")
            eq(r.target, "Bob", "target")
        end)

        it("round-trips the target through Encode -> Decode", function()
            local r = Codec.Decode(Codec.EncodeHandoff("Frostkeg"))
            eq(r.kind, "H", "kind")
            eq(r.target, "Frostkeg", "target")
        end)

        it("returns nil from EncodeHandoff when target is missing", function()
            eq(Codec.EncodeHandoff(nil), nil, "nil target")
        end)

        it("rejects an empty or absent target on decode", function()
            eq(Codec.Decode("H;"), nil, "empty target")
            eq(Codec.Decode("H"), nil, "no separator")
        end)

        it("does not collide with other tags", function()
            eq(Codec.Decode("H;Bob").kind, "H", "H stays H")
            eq(Codec.Decode("M;Z;M;3;8;KILL;NIL").kind, "M", "M unaffected")
            eq(Codec.Decode("Q;1;0").kind, "Q", "Q unaffected")
        end)
    end)

    -- [v0.29] slice 6: "SB"/"SE" frame a broadcast-once Mob DB share (sec.7.2).
    -- SB opens with the M-record count (validated at SE -> all-or-nothing apply);
    -- both key the frame on poster+zone. Pure codec only at this checkpoint.
    describe("SB/SE share frame", function()
        it("encodes and decodes a share-begin with poster, zone, count", function()
            eq(Codec.EncodeShareBegin("Borgrim", "Blackwing Lair", 11),
                "SB;Borgrim;Blackwing Lair;11", "SB wire")
            local r = Codec.Decode("SB;Borgrim;Blackwing Lair;11")
            eq(r.kind, "SB", "kind")
            eq(r.poster, "Borgrim", "poster")
            eq(r.zone, "Blackwing Lair", "zone")
            eq(r.count, 11, "count")
        end)

        it("encodes and decodes a share-end with poster and zone", function()
            eq(Codec.EncodeShareEnd("Borgrim", "Blackwing Lair"),
                "SE;Borgrim;Blackwing Lair", "SE wire")
            local r = Codec.Decode("SE;Borgrim;Blackwing Lair")
            eq(r.kind, "SE", "kind")
            eq(r.poster, "Borgrim", "poster")
            eq(r.zone, "Blackwing Lair", "zone")
        end)

        it("returns the count as a number, not a string", function()
            eq(type(Codec.Decode("SB;P;Z;3").count), "number", "count type")
        end)

        it("returns nil from encoders when poster or zone is missing", function()
            eq(Codec.EncodeShareBegin(nil, "Z", 1), nil, "SB no poster")
            eq(Codec.EncodeShareBegin("P", nil, 1), nil, "SB no zone")
            eq(Codec.EncodeShareEnd("P", nil), nil, "SE no zone")
        end)

        it("rejects malformed SB/SE on decode", function()
            eq(Codec.Decode("SB;P;Z"), nil, "SB missing count")
            eq(Codec.Decode("SB;P;Z;x"), nil, "SB non-numeric count")
            eq(Codec.Decode("SB;;Z;1"), nil, "SB empty poster")
            eq(Codec.Decode("SE;P;"), nil, "SE empty zone")
            eq(Codec.Decode("SE;;Z"), nil, "SE empty poster")
        end)

        it("does not collide with other tags", function()
            eq(Codec.Decode("SB;P;Z;1").kind, "SB", "SB stays SB")
            eq(Codec.Decode("SE;P;Z").kind, "SE", "SE stays SE")
            eq(Codec.Decode("M;Z;M;3;8;KILL;NIL").kind, "M", "M unaffected")
        end)
    end)

    -- [v0.29] slice 6: the clickable chat-link data grammar
    -- "tankmark:<poster>:<zone>" (a |H..|h hyperlink body, not an addon message).
    describe("share link", function()
        it("encodes and decodes the link data", function()
            eq(Codec.EncodeShareLink("Borgrim", "Blackwing Lair"),
                "tankmark:Borgrim:Blackwing Lair", "link data")
            local r = Codec.DecodeShareLink("tankmark:Borgrim:Blackwing Lair")
            eq(r.poster, "Borgrim", "poster")
            eq(r.zone, "Blackwing Lair", "zone")
        end)

        it("round-trips poster and zone", function()
            local r = Codec.DecodeShareLink(Codec.EncodeShareLink("Frostkeg", "Zul'Gurub"))
            eq(r.poster, "Frostkeg", "poster")
            eq(r.zone, "Zul'Gurub", "zone")
        end)

        it("treats everything after the 2nd colon as the zone", function()
            local r = Codec.DecodeShareLink("tankmark:P:Weird:Zone")
            eq(r.zone, "Weird:Zone", "greedy zone")
        end)

        it("ignores a non-tankmark link (other addons / item links pass through)", function()
            eq(Codec.DecodeShareLink("item:12345:0:0:0"), nil, "item link")
            eq(Codec.DecodeShareLink("quest:42:30"), nil, "pfquest link")
            eq(Codec.DecodeShareLink(nil), nil, "nil")
        end)

        it("returns nil from EncodeShareLink when poster or zone is missing", function()
            eq(Codec.EncodeShareLink(nil, "Z"), nil, "no poster")
            eq(Codec.EncodeShareLink("P", nil), nil, "no zone")
        end)
    end)
end)
