-- TankMark off-client test entry point.  Run from the repo root:
--   lua5.1 tests/run.lua
--
-- Loads the harness (stubs + SUT + runner), then every spec, and exits non-zero
-- if any assertion failed (CI-ready, though the project has no CI yet).

dofile("tests/support/harness.lua")
dofile("tests/support/board.lua")

-- Specs run in listed order. Missing files are skipped, so the list can grow
-- ahead of the specs themselves across commits.
local SPECS = {
    "tests/incumbency_spec.lua",
    "tests/decide_mark_spec.lua",
    "tests/governor_spec.lua",
    "tests/sync_codec_spec.lua",
    "tests/trust_spec.lua",
    "tests/swarm_election_spec.lua",
    "tests/profile_sync_spec.lua",
    "tests/record_unit_spec.lua",
    "tests/legal_cc_spec.lua",
    "tests/role_prio_spec.lua",
    "tests/cc_worthiness_spec.lua",
    "tests/pull_assignment_spec.lua",
    "tests/mark_normals_spec.lua",
    "tests/decide_skull_successor_spec.lua",
    "tests/reservation_spec.lua",
    "tests/zone_merge_spec.lua",
}
for _, spec in ipairs(SPECS) do
    local fh = io.open(spec, "r")
    if fh then fh:close(); dofile(spec) end
end

local r = TM_TEST_RESULTS
print("")
print(string.format("%d passed, %d failed", r.pass, r.fail))
if r.fail > 0 then
    print("")
    print("FAILURES:")
    for _, f in ipairs(r.failures) do print("  - " .. f) end
    os.exit(1)
end
print("OK")
os.exit(0)
