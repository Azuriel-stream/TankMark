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

        it("syncs only the FIRST mark of the marks array", function()
            local s = Codec.EncodeMob("Z", "M", { prio = 1, marks = { 5, 6, 7 } })
            eq(s, "M;Z;M;1;5;KILL;NIL", "first-mark only")
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

        it("rejects an unknown type tag", function()
            eq(Codec.Decode("Q;Z;M;3;8;KILL;NIL"), nil, "Q tag")
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
    end)
end)
