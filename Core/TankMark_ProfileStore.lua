-- The ProfileStore seam: the sole writer of the Team Profile store
-- (TankMarkProfileDB) and the sole constructor of profile entries.
--
-- The Team Profile store is the persistent, per-zone roster binding each mark to a
-- player (its tank) + healers + profile role. Before this module its ~8 write sites
-- each re-spelled the entry shape {mark, tank, healers, role} and its defaults, and
-- each assigned TankMarkProfileDB[zone] raw -- so a new field (the Phase-1
-- creatureType/tier preserve landmine) or a default could drift between them. This is
-- now the one writer: every structural write (create/replace/delete a zone's entry
-- list) and every entry construction routes through here, across all three write
-- tiers -- authored (UI/HUD), sync-receive (a drone applying the queen's push), and
-- recovery (snapshot restore + bootstrap).
--
-- Scope is deliberately the STORE only. Reads stay with their callers (the decision
-- layer's Get* accessors and CanAutomate's hard-gate check). In-place single-field
-- edits on an already-existing entry stay raw too: Swarm.OnHealerRecord's healers=
-- (sync layering) and MigrateProfileRoles' role= (a non-pure, reader-side lazy
-- migration). And the runtime session projection (sessionAssignments /
-- ApplyProfileToSession) is a SEPARATE concern -- a future "session-assignment
-- owner", not this module.
--
-- Pure: no WoW API, no UI. `zone` is passed in; callers resolve it. NewEntry
-- normalizes shape + defaults but does NOT validate/drop (unlike ZoneView) -- profile
-- entries are player names, free-form by nature, and the untrusted sync path is gated
-- upstream (SyncCodec + the queen/version guards, which stay in Swarm).

if not TankMark then return end

local L = TankMark.Locals

TankMark.ProfileStore = {}
local ProfileStore = TankMark.ProfileStore

-- [v0.31] Ensure the top-level store table exists. Called at load-time bootstrap and
-- internally by every writer, so no caller assigns `TankMarkProfileDB = {}` raw.
function ProfileStore.EnsureDB()
    if not TankMarkProfileDB then TankMarkProfileDB = {} end
    return TankMarkProfileDB
end

-- [v0.31] The canonical profile-entry constructor: the single source of the entry
-- shape {mark, tank, healers, role} and its defaults. `tank`/`healers` default to "";
-- `role` is preserved AS PASSED (nil stays nil) -- it must NOT hard-default to "TANK",
-- or the HUD's nil-role-then-class-infer path (MigrateProfileRoles) would break (a
-- quick-assigned Mage would become TANK instead of class-inferred CC). `mark` is
-- coerced to a number so downstream readers need no defensive tonumber.
function ProfileStore.NewEntry(mark, tank, healers, role)
    return {
        mark    = L._tonumber(mark),
        tank    = tank or "",
        healers = healers or "",
        role    = role,
    }
end

-- [v0.31] Replace a zone's entire entry list, normalizing each entry through NewEntry
-- (so the stored tables are always fresh + uniform -- snapshot restore needs no
-- separate deep copy). `entries` nil or {} clears the zone to an empty list (the
-- reset-profile behavior). The whole-zone replace for all three tiers: SaveProfileCache
-- commit, Swarm.OnProfile, Data snapshot restore, and reset.
function ProfileStore.SetZone(zone, entries)
    if not zone then return end
    ProfileStore.EnsureDB()
    local list = {}
    if entries then
        for _, e in L._ipairs(entries) do
            L._tinsert(list, ProfileStore.NewEntry(e.mark, e.tank, e.healers, e.role))
        end
    end
    TankMarkProfileDB[zone] = list
    return list
end

-- [v0.31] Upsert a player onto a mark in a zone's roster: update the existing entry's
-- tank if the mark is present, else insert a fresh entry and re-sort skull-first (mark
-- descending). The one write with real logic -- lifted out of the HUD
-- (SetProfileAssignment), where it was business logic living in the UI. The inserted
-- entry's role is left nil so the class-inference backfill (MigrateProfileRoles) still
-- fires, exactly as the old HUD path did.
function ProfileStore.Upsert(zone, mark, player)
    if not zone or not mark then return end
    ProfileStore.EnsureDB()
    if not TankMarkProfileDB[zone] then TankMarkProfileDB[zone] = {} end
    local list = TankMarkProfileDB[zone]
    for _, entry in L._ipairs(list) do
        if entry.mark == mark then
            entry.tank = player or ""
            return list
        end
    end
    L._tinsert(list, ProfileStore.NewEntry(mark, player, "", nil))
    L._tsort(list, function(a, b) return a.mark > b.mark end)
    return list
end

-- [v0.31] Remove a zone's profile entirely (the key goes away) -- distinct from
-- SetZone(zone, {}), which keeps an empty zone. The delete-profile-zone action.
function ProfileStore.DeleteZone(zone)
    if not zone or not TankMarkProfileDB then return end
    TankMarkProfileDB[zone] = nil
end

-- [v0.31] Reset the entire store to empty -- every zone gone (the "wipe database"
-- recovery action). The whole-store counterpart to DeleteZone; keeps the invariant
-- that no raw TankMarkProfileDB structural write remains outside this module.
function ProfileStore.Wipe()
    TankMarkProfileDB = {}
end
