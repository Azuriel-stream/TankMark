# TankMark Developer Guide (v0.26)

## Project Structure

### Entry Point
- **TankMark.lua**: Event handlers, slash commands, `TankMark.Locals` localization table, key-binding handlers, and startup initialization. All WoW API references are cached here into `TankMark.Locals` so other files never call globals directly.

### Core/
Contains business logic (marking algorithms, death handling, scanner, etc.)

- **TankMark_Session.lua**: Centralized runtime state variables (`usedIcons`, `activeGUIDs`, `activeMobNames`, `disabledMarks`, `sessionAssignments`, `MarkNormals`, etc.) and the `MarkInfo` constants table. Loaded first among Core modules.
- **TankMark_Permissions.lua**: `CanAutomate()`, `HasPermissions()`, `Driver_GetGUID()`, and `Driver_ApplyMark()`. The latter wraps `SetRaidTarget` with debug logging (guarded by `TankMark.DebugEnabled`).
- **TankMark_Assignment.lua**: Mark assignment algorithms and player detection:
  - `GetFreeTankIcon()` — iterates Team Profile entries, uses `IsMarkBusy()` to check availability.
  - `FindCCPlayerForClass()` — matches CC-capable players by English class token.
  - `GetBlockingMarkInfo()` — [v0.26] finds the highest-priority non-skull mark holder (liveness-checked via SuperWoW `mark` unit tokens). Used by the Governor Check.
  - `FindEmergencyCandidate()` — [v0.26] scans `visibleTargets` for the best skull candidate. Rejects mobs whose DB mark is explicitly not skull.
  - `GetUnitIDForName()` — resolves a player name to a unit ID.
  - `IsPlayerAliveAndInRaid()`, `IsPlayerCCClass()`, `GetAssigneeForMark()`, `AssignCC()`.
- **TankMark_Processor.lua**: Core marking decision logic:
  - `ProcessUnit()` — main entry point. Validates unit, checks current mark with server-side ownership verification (SuperWoW), handles stale `activeGUIDs` invalidation, routes to `ProcessKnownMob()` or `ProcessUnknownMob()`.
  - `IsMarkBusy(iconID)` — [v0.26] checks `MarkMemory`, SuperWoW `mark` units, and `usedIcons`. Debug logging guarded by `TankMark.DebugEnabled`.
  - `GetMarkOwnerPriority(iconID)` — [v0.26] resolves the priority of the current mark holder.
  - `ProcessKnownMob()` — handles CC assignment, aggressive skull theft logic, Governor Check (incumbency rule), and `MarkMemory` state cleanup on theft.
  - `ProcessUnknownMob()` — assigns free marks to unknown mobs with Governor Check for skull.
  - `RegisterMarkUsage()`, `RecordUnit()`.  
- **TankMark_Death.lua**: Death detection, mark cleanup, and skull priority management:
  - `HandleCombatLog()` / `HandleDeath()` — resolve dead mob GUID before eviction.
  - `EvictMarkOwner(iconID, deadGUID)` — [v0.26] GUID-aware eviction. Preserves state when `MarkMemory` already points to a new assignment.
  - `ReviewSkullState(callerID)` — [v0.26] complete rewrite. Uses SuperWoW `mark8` for liveness check, duplicate-event guard via `MarkMemory[8]`, sequential marking guard, Governor/Incumbency rule via `GetBlockingMarkInfo()` + `FindEmergencyCandidate()`.
  - `VerifyMarkExistence()` — uses SuperWoW `mark` units for server-side tracking.
  - `ResetSession()` — wipes all state including `MarkMemory`.
- **TankMark_Batch.lua**: Shift+mouseover batch marking system with delayed queue execution.
- **TankMark_Scanner.lua**: SuperWoW nameplate scanner with snapshot batching:
  - Initializes `TankMark.MarkMemory` table.
  - `StartSuperScanner()` — OnUpdate loop with 4 phases: Reset → Snapshot (capture nameplates, reinforce `MarkMemory` for known marks, buffer candidates) → Decision (priority-sort candidates, execute `ProcessUnit`) → Cleanup (`ReviewSkullState`).
  - `IsGUIDInCombat()`, `IsNameplate()`, `ScanForRangeSpell()`, `Driver_IsDistanceValid()`.
- **TankMark_Sync.lua**: Raid data synchronization and TWA integration via addon messages.

### Data/
Database management and persistence

- **TankMark_Data.lua**: DB initialization (`InitializeDB`), corruption detection (`ValidateDB`), snapshot system (`CreateSnapshot`/`RestoreFromSnapshot`), lazy-load zone data (`LoadZoneData`/`RefreshActiveDB`), roster management (`UpdateRoster`/`GetFirstAvailableBackup`), and the **Debug Logging System**:
  - `DebugLog(category, message, data)` — circular buffer (500 entries max), stored in `TankMarkDB.DebugLog`. Early-returns if `TankMark.DebugEnabled == false`.
  - `DumpDebugLog(filterCategory)` — prints to chat with color-coded categories.
  - `ClearDebugLog()` — wipes the buffer.
  - `UpdateZoneDropdowns()` — syncs Mob DB and Profile dropdowns on zone change.
- **TankMark_Defaults.lua**: Default mob database (shipped data).

### UI/
All visual components

- **TankMark_HUD.lua**: In-game heads-up display (8-row mark tracker).
- **TankMark_Options.lua**: Config panel entry point and tab management.
- **TankMark_UI_Widgets.lua**: Reusable UI components (dropdowns, buttons, etc.)
- **Config/**: Config panel tabs:
  - `TankMark_Config_Mobs.lua` — Mob Database tab container.
  - `TankMark_Config_Mobs_UI.lua` — Mob editor UI widgets, zone controls, `UpdateMobZoneUI()`.
  - `TankMark_Config_Mobs_List.lua` — Mob list rendering and scrolling.
  - `TankMark_Config_Mobs_Logic.lua` — Save/load/delete mob data, smart defaults.
  - `TankMark_Config_Mobs_Sequential.lua` — Sequential mark configuration UI.
  - `TankMark_Config_Mobs_Menus.lua` — Context menus for mob entries.
  - `TankMark_Config_Profiles.lua` — Team Profile management, `UpdateProfileZoneUI()`, healer assignment.
  - `TankMark_Config_Data.lua` — Data management tab (import/export/snapshots).

### Other
- **Bindings.xml**: Key binding definitions.
- **TankMark.toc**: Addon manifest and load order.

## Key Systems (v0.26)

### MarkMemory
A table (`TankMark.MarkMemory`) mapping `iconID → GUID` that tracks which mob currently holds each raid mark. Initialized in `TankMark_Scanner.lua`. Reinforced every scanner tick for visible marks. Flushed on combat end (`PLAYER_REGEN_ENABLED`) and session reset.

**Used by:** `IsMarkBusy()`, `GetMarkOwnerPriority()`, `EvictMarkOwner()`, `ReviewSkullState()`, `ProcessUnit()` (stale GUID cleanup), `GetBlockingMarkInfo()`, `GetFreeTankIcon()`.

### Governor Check (Skull Incumbency)
Prevents skull from being assigned to a mob when existing marked mobs have equal or higher priority. Implemented in both `ProcessKnownMob()` and `ReviewSkullState()` via `GetBlockingMarkInfo()`.

### Debug Logging
Toggle with `/tm debug on|off`. Dump with `/tm debug dump`. Filter by category: `/tm debug apply`, `/tm debug busy`. Clear with `/tm debug clear`.

**Performance rule:** All `DebugLog()` call sites MUST be wrapped in `if TankMark.DebugEnabled then ... end` to prevent argument construction when debug is off. See `Core/TankMark_Permissions.lua` `Driver_ApplyMark()` for the canonical pattern.

### Ownership Verification
In `ProcessUnit()`, when SuperWoW is available, `GetRaidTargetIndex(guid)` results are cross-checked against `UnitExists("mark"..icon)` to detect stale marks from theft scenarios.

## Adding New Features

### Adding a New Mark Assignment Rule
1. Open `Core/TankMark_Assignment.lua`
2. Add your logic to `GetFreeTankIcon()` or create a new function
3. Call it from `Core/TankMark_Processor.lua` in `ProcessKnownMob()`
4. If the rule affects skull assignment, also update the Governor Check in `ProcessKnownMob()` and `ReviewSkullState()` in `Core/TankMark_Death.lua`

### Adding a New Debug Log Category
1. Add `DebugLog()` calls with your category string (e.g., "MYFEATURE")
2. **Always** wrap in `if TankMark.DebugEnabled then ... end`
3. Optionally add a `/tm debug myfeature` filter in `TankMark.lua` `SlashHandler`

### Adding a New Config Tab
1. Create `UI/Config/TankMark_Config_NewTab.lua`
2. Add UI creation logic
3. Register tab in `UI/TankMark_Options.lua`
4. Update `TankMark.toc` load order

### Adding a New Localized API Call
1. Add the reference to `TankMark.Locals` in `TankMark.lua` (e.g., `_NewFunction = NewFunction`)
2. Use `L._NewFunction(...)` in your code
3. Never call WoW API globals directly outside of `TankMark.lua`

## Coding Standards
- **Localization:** Always use `TankMark.Locals` for WoW API functions (no direct global calls). Use `local L = TankMark.Locals` at the top of each file.
- **Nil safety:** Validate all inputs — check for nil before indexing tables.
- **Table length:** Use `L._tgetn()` (aliased `table.getn()`) for array length. Never use `#table` (not available in Lua 5.0).
- **Version tags:** Comment complex algorithms with `-- [v0.XX]` version tags.
- **Debug guards:** Wrap all `TankMark:DebugLog()` calls in `if TankMark.DebugEnabled then ... end` to avoid argument construction overhead on the hot path.
- **String functions:** Use `L._gfind()` (not `string.find` or `sgfind`) for pattern iteration. Use `L._strfind()` for single match.
- **Type checks:** Use `L._type()` instead of bare `type()`.
- **Global function references:** Use `L._SendChatMessage()`, `L._SetRaidTarget()`, `L._PlaySound()`, `L._CreateFrame()`, etc. — all WoW API calls must go through the Locals table.

## SavedVariables

| Variable | Scope | Description |
|---|---|---|
| `TankMarkDB` | Account-wide | Mob database (`Zones`, `StaticGUIDs`), debug log (`DebugLog`) |
| `TankMarkProfileDB` | Per-character | Team profiles (mark → tank → healers assignments per zone) |
| `TankMarkDB_Snapshot` | Per-character | Up to 3 database snapshots for corruption recovery |
| `TankMarkCharConfig` | Per-character | Character-specific UI settings (HUD position, etc.) |

## Event Flow (Simplified)

```
ADDON_LOADED → InitializeDB() → InitCombatLogParser()
PLAYER_LOGIN → LoadZoneData() → InitDriver() → ScanForRangeSpell() → Mark Wipe → HUD Update
ZONE_CHANGED_NEW_AREA → LoadZoneData() → UpdateZoneDropdowns()
UPDATE_MOUSEOVER_UNIT → HandleMouseover() → ProcessUnit("PASSIVE")
Scanner OnUpdate (0.5s) → Snapshot → Sort → ProcessUnit("SCANNER") → ReviewSkullState()
UNIT_HEALTH (0 HP) → HandleDeath() → EvictMarkOwner() → ReviewSkullState()
CHAT_MSG_COMBAT_HOSTILE_DEATH → HandleCombatLog() → EvictMarkOwner() → ReviewSkullState()
PLAYER_REGEN_ENABLED → Flush MarkMemory
```