# TankMark Developer Guide (v0.29)

## Project Structure

### Entry Point
- **TankMark.lua**: Event handlers, slash commands, `TankMark.Locals` localization table, key-binding handlers, and startup initialization. All WoW API references are cached here into `TankMark.Locals` so other files never call globals directly.

### Core/
Contains business logic (marking algorithms, death handling, scanner, etc.)

- **TankMark_Session.lua**: Centralized runtime state variables (`usedIcons`, `activeGUIDs`, `activeMobNames`, `disabledMarks`, `sessionAssignments`, `MarkNormals`, etc.), the `MarkInfo` constants table, and **[v0.28]** `CCAuraSet` — the flattened set of parked-CC aura IDs (built at load from the grouped `CC_SOURCE` table) that `IsMarkCCd` reads. Loaded first among Core modules.
- **TankMark_Permissions.lua**: `CanAutomate()`, `HasPermissions()`, `ShouldDriveMarks()`, `Driver_GetGUID()`, and `Driver_ApplyMark()`. The last wraps `SetRaidTarget` with debug logging (guarded by `TankMark.DebugEnabled`). **[v0.29, swarm slice 3, PR #72]** `ShouldDriveMarks()` is the **marking** gate, deliberately distinct from `CanAutomate()` the **candidacy** gate: `CanAutomate() and (not Swarm.IsRunning() or Swarm.selfAmQueen)`, **fail-open** when the election shell isn't running. Every world-mark path reads it; `CanAutomate` is left unchanged so the swarm election/failover pool is preserved. See **Single-Marker Enforcement** under Key Systems.
- **TankMark_Assignment.lua**: Mark assignment algorithms and player detection:
  - `GetFreeTankIcon()` — iterates Team Profile entries, uses `IsMarkBusy()` to check availability.
  - `FindCCPlayerForClass()` — matches CC-capable players by English class token.
  - `GetBlockingMarkInfo()` — [v0.26] finds the highest-priority non-skull mark holder (liveness-checked via SuperWoW `mark` unit tokens). Used by the Governor Check. **[v0.28]** its private `UpdateBest` chokepoint excludes parked/CC'd holders via `IsMarkCCd()`, so a sheeped incumbent no longer blocks skull (roadmap #3 sheep-edge, PR #47).
  - `FindEmergencyCandidate()` — [v0.26] scans `visibleTargets` for the best skull candidate. Rejects mobs whose DB mark is explicitly not skull.
  - `IncumbencyBlocks(myPrio, blockIcon, blockPrio)` — [v0.28] the single source of the skull incumbency comparison (`blockIcon and myPrio >= blockPrio`). Pure — callers fetch `GetBlockingMarkInfo()` and pass the blocker in. Shared by the decide-path governor (`GovernorBlocks`) and the death-path review (`ReviewSkullState`) so the `>=` operator can't drift between them (roadmap #3).
  - `IsMarkCCd(icon)` — [v0.28] true when the mob holding `icon` wears a parked-CC debuff (Polymorph/Sap/Shackle/Banish/Hibernate/Freezing-Trap/Wyvern-Sting/Seduction). Polls `UnitDebuff` on the SuperWoW `mark` token — the aura id is the **4th** return — against `Session.lua`'s `CCAuraSet`. Used by the `UpdateBest` early-out in `GetBlockingMarkInfo` so a parked incumbent is not a skull-blocker (roadmap #3 sheep-edge, PR #47). Fail-safe: an unrecognized/stale debuff → not-CC → blocks as before.
  - `GetUnitIDForName()` — resolves a player name to a unit ID.
  - `IsPlayerAliveAndInRaid()`, `IsPlayerCCClass()`, `GetAssigneeForMark()`, `AssignCC()`.
- **TankMark_Processor.lua**: Core marking decision logic. **[v0.28] split into decide / apply** (roadmap #2):
  - `LiveBoard` — **[v0.28, Tier 2]** the **ports board**: the one seam the pure decision layer (`DecideMark` and below) reads the world through — a table of closures over the live `TankMark` methods (`playerInCombat`, `guidInCombat`, `isMarkBusy`, `markOwnerPriority`, `getFreeTankIcon`, `getBlockingMarkInfo`, `findCCPlayer`, `isDisabled`) plus one side-effect **sink**, `logDecision` (the guarded `DECIDE` log; a no-op under test). Built once at load; closures resolve at **call time**, so Ledger reads stay **live across a scanner tick** (candidate #1's `Assign` is visible to candidate #2's `getFreeTankIcon` — a frozen snapshot could not). Production wires `TankMark.LiveBoard`; the off-client tests inject a mock, so the decide functions touch **no** WoW/Ledger/session global directly (zero-global apart from the pure-language `L._tgetn`). Pure predicates (`IncumbencyBlocks()`) are NOT ports — they read no state and stay direct calls. See **Decision Layer** under Key Systems and the **Testing** section.
  - `ProcessUnit()` — main entry point. Validates unit, checks current mark with server-side ownership verification (SuperWoW), handles stale `activeGUIDs` invalidation, then calls `DecideMark()` + `ApplyMarkIntent()`.
  - `DecideMark(mobData, guid, mode, board)` — [v0.28] single decision entry point. Routes by `mobData` (`nil` → unknown path), emits the one `DECIDE` debug log through `board.logDecision`, and returns an inspectable intent `{ icon, reason, wasBusy?, override? }`. Applies NOTHING. `board` is the injected ports table — `TankMark.LiveBoard` in production, a mock under test.
  - `DecideKnownMark(mobData, guid, mode, board)` — [v0.28] known-mob decision: sequential/zero bails → SCANNER combat gate → `ResolveCC` → primary-mark selection (with selection-time skull theft) → free-icon fallback → governor. Returns an intent.
  - `DecideUnknownMark(guid, mode, board)` — [v0.28] unknown-mob decision (prio 5): highest free tank icon, skull only when genuinely free, never steals. Returns an intent. (No `mobData` — the unknown path has none.)
  - `ResolveCC(mobData, board)` — [v0.28] CC resolver seam; returns the CC mark icon or nil (owns the `type=="CC"` guard). The decide-once+notify CC model is future work behind this seam.
  - `GovernorBlocks(icon, myPrio, mode, allowSteal, board)` — [v0.28] shared skull-governor gate. `allowSteal` freezes the prio-5 asymmetry (known=true may steal an occupied skull; unknown=false never does). The skull-free incumbency check routes through the shared `IncumbencyBlocks()` predicate (roadmap #3). Returns a block-reason string or nil.
  - `ApplyMarkIntent(guid, name, intent, skipProfileLookup)` — [v0.28] sole decide-path apply edge: `RegisterMarkUsage` (Ledger record) then `Driver_ApplyMark`. (Batch's within-sequence `marks>1` cursor still applies directly; bodies *beyond* the sequence route through this edge via `DecideUnknownMark` — the cursor clamps instead of wrapping, PR #45.)
  - `IsMarkBusy(iconID)` — [v0.26] checks `MarkMemory`, SuperWoW `mark` units, and `usedIcons`. Debug logging guarded by `TankMark.DebugEnabled`.
  - `GetMarkOwnerPriority(iconID)` — [v0.26] resolves the priority of the current mark holder.
  - `RegisterMarkUsage()`, `RecordUnit()`.
- **TankMark_Death.lua**: Death detection, mark cleanup, and skull priority management:
  - `HandleCombatLog()` / `HandleDeath()` — resolve dead mob GUID before eviction.
  - `EvictMarkOwner(iconID, deadGUID)` — [v0.26] GUID-aware eviction. Preserves state when `MarkMemory` already points to a new assignment.
  - `ReviewSkullState(callerID)` — [v0.26] complete rewrite. Uses SuperWoW `mark8` for liveness check, duplicate-event guard via `MarkMemory[8]`, sequential marking guard, Governor/Incumbency rule via `GetBlockingMarkInfo()` + `FindEmergencyCandidate()`. **[v0.28]** the incumbency comparison now routes through the shared `IncumbencyBlocks()` predicate (`shouldAssign = not IncumbencyBlocks(...)`), single-sourced with `GovernorBlocks` (roadmap #3). **[v0.29, swarm slice 3, PR #72]** its own gate is now `ShouldDriveMarks()` (was `HasPermissions`): `ReviewSkullState` records skull ownership (`RegisterMarkUsage`) **before** `Driver_ApplyMark`, so a non-queen must not even reach the Ledger write — all callers are already queen-gated, this tightens the path itself (defense-in-depth, the third `HasPermissions→ShouldDriveMarks` site alongside pull-end clear and the `ResetSession` strip). **[v0.28, PR #55]** a steady-state short-circuit at the **top** of the function returns **before** the entry log when a skull is alive and `MemoryOwner(8)` already equals that exact live GUID (the no-op confirm), emitting one `confirm - mark8 alive (owned)` breadcrumb per *distinct* holder (tracked via a runtime-only `lastAliveSkullLogged`) instead of ~2 SKULL_REVIEW lines/tick the whole time a skull is up. Log-only — adoption (`MemoryOwner(8)` nil → the `registered pre-existing skull holder` wedge tell) and theft/mismatch (owner ≠ live GUID) still fall through to the full logic, and the mark8 reads already ran every tick so there's no added hot-path cost (roadmap candidate 0).
  - `VerifyMarkExistence()` — uses SuperWoW `mark` units for server-side tracking.
  - `ClearMarksForPullEnd()` — **[v0.28, PR #52]** at true pull-end, physically strips every **hostile-worn** mark (`mark1-8`, guarded by `not UnitIsPlayer` so manually-placed player marks survive) and calls `Ledger.Clear()`, so Turtle never retains a raid icon onto a respawn. **[v0.29, swarm slice 3, PR #72]** `ShouldDriveMarks`-gated (was `HasPermissions`) — it fires automatically on pull-end, so un-gated every drone would race to strip the queen's marks. Preserves the plan (`sessionAssignments` / profile DB / `disabledMarks` / sequential cursor / recorder). NOT `ResetSession`. See **Pull-End Mark Clear** under Key Systems.
  - `ResetSession()` — wipes all state including `MarkMemory`. **[v0.29, swarm slice 3, PR #72]** split-gated: the local-state reset is unconditional, but the physical `mark1-8` strip is `ShouldDriveMarks`-gated, so `/tmark reset` on a drone clears its own state without stripping the group's (queen's) world marks.
- **TankMark_Batch.lua**: Shift+mouseover batch marking system with delayed queue execution. **[v0.29, swarm slice 3, PR #72]** both guards (entry + mid-batch re-check) are `ShouldDriveMarks`-gated, so manual marking is queen-only; a drone gets a swarm-aware "X is the active marker" notice instead of placing marks.
- **TankMark_Scanner.lua**: SuperWoW nameplate scanner with snapshot batching:
  - Initializes `TankMark.MarkMemory` table.
  - `StartSuperScanner()` — OnUpdate loop with 4 phases: Reset → Snapshot (capture nameplates, reinforce `MarkMemory` for known marks, buffer candidates) → Decision (priority-sort candidates, execute `ProcessUnit`) → Cleanup (`ReviewSkullState`). **[v0.28, PR #53]** the Cleanup call is gated: `ReviewSkullState("SCANNER_TICK")` runs only when `batchIndex > 0 or UnitExists("mark8")` (an unmarked in-combat candidate exists, or a skull token needs review); when neither holds it has nothing to do, so the idle tick skips it (and stops spamming the SKULL_REVIEW debug log). Death-driven skull reassignment is unaffected — it runs via the `COMBAT_LOG`/`UNIT_DEATH` callers in `Death.lua`, not the scanner tick. **[v0.28, PR #55]** for the complementary *in-combat* case (a skull stays up, so this gate keeps calling every tick), `ReviewSkullState`'s own steady-state confirm short-circuit keeps the per-tick SKULL_REVIEW noise down — see its entry above.
  - `IsGUIDInCombat()`, `IsNameplate()`, `ScanForRangeSpell()`, `Driver_IsDistanceValid()`.
- **TankMark_SyncCodec.lua**: **[v0.29, swarm slice 1, PR #66]** Pure, definition-only wire codec for addon-message sync — the single source of truth for the `M` mob-record format. `EncodeMob(zone, mob, data)` → wire string; `Decode(msg)` → typed record `{ kind="M", zone, mob, prio, mark, type, class }` or nil. Owns the field order, `;` separator, `M` tag, defaults (first-mark-only / `KILL` / `NIL`-class sentinel), and all validation (numeric prio/mark, 0–8 range). No WoW/Ledger/session state and no top-level execution, so the off-client harness loads it directly (unlike `Sync.lua`, which builds a frame at load). Loaded before `Sync.lua`. **[v0.29, swarm slice 4, PR #75]** now also owns two profile-sync types — `EncodeProfile`/`Decode`→`{kind="P"}` (the HUD-minimal `mark+tank+role` snapshot, role as 1-char `T`/`C`, one bad entry rejects the whole message) and `EncodePull`/`Decode`→`{kind="PR"}` — plus the `planVersion` field on the `Q` heartbeat. `Decode` now splits the tag on the first `;` (so the multi-char `PR` tag parses) instead of taking one char. See **Sync Wire Codec** under Key Systems.
- **TankMark_Sync.lua**: Raid data synchronization via `TM_SYNC` addon messages. **[v0.29, swarm slice 0, PR #64]** the TWA/BigWigs inbound integration (`HandleTWABW`, `TWA_MarkMap`) is **removed** — one TM-native dialect now. `HandleSync` decodes via `SyncCodec.Decode` then performs the `TankMarkDB.Zones` write — the lone stateful apply edge (mirrors Ledger / `ApplyMarkIntent`); `BroadcastZone` encodes via `SyncCodec.EncodeMob`. Trust-gated by `IsTrustedSender` (raid Assist/Leader or party leader). **[v0.29, swarm slice 2, PR #69]** a decoded `Q` heartbeat routes to `Swarm.OnHeartbeat` (same trust gate); `TankMark.SyncPrefix` is exposed so the swarm beats on the one transport. **[v0.29, swarm slice 4, PR #75]** a decoded `P` routes to `Swarm.OnProfile` and a `PR` to `Swarm.OnPullRequest` — both behind the same rank≥1 `IsTrustedSender` gate, and `OnProfile` *additionally* requires `sender == Swarm.currentQueen` before it overwrites the local plan (so a rank≥1 non-queen can pollute comms but never rewrite a drone's HUD). Receiver-side consent hardening (offer/accept + per-player trust axis) for the *Mob DB* is a later swarm slice (`SWARM_DESIGN.md` §7); the profile is queen-authoritative and deliberately carved out of that consent rule (§6.1).
- **TankMark_Swarm.lua**: **[v0.29, swarm slice 2, PR #69]** Queen/drone control plane that computes & displays who the marking queen is. **[v0.29, swarm slice 3, PR #72]** it is no longer display-only: `Permissions.ShouldDriveMarks()` now reads `Swarm.selfAmQueen` (the stored election output) and `Swarm.IsRunning()` (the `Swarm.frame ~= nil` liveness predicate) to gate every marking path — so a non-queen yields. The election core itself is unchanged and still touches no marking path. Mirrors the SyncCodec/Sync split: a **pure election core** (`DeterministicMax`, `ElectQueen` — the claimant-count rule unifying election / stickiness / split-brain, `ComputePresence` — two-filter present set, `DeriveRole`) with no WoW state / no frame / no top-level execution, so the off-client harness loads it directly; plus a **runtime shell** (`InitSwarm` deferred + SuperWoW-gated builds the 5s beat frame, `Recompute` orchestrates roster build → bootstrap entry/exit → election → live HUD repaint, `UpdateNotice` is the ≥1-cycle debounced chat announcer, `OnHeartbeat`/`OnRosterChange`/`Tick` are the triggers). Loaded after `Sync.lua`. **[v0.29, swarm slice 4, PR #75]** it also carries the profile-sync data plane: the queen-side `OnProfileSaved`/`OnPromoted` (bump the global `planVersion` + `PushProfile` the zone snapshot) and `OnPullRequest`/`FlushSync` (coalesced PR-response, one broadcast per zone per tick), the drone-side `OnProfile` (queen-gated apply, empty-keeps), `EvaluatePull` (the `(queen,version,zone)`-triple refetch predicate), and `SendPull`; runtime state `planVersion`/`appliedKey`/`needPull`/`versionHeard`/`pendingPush`. Loaded after `Sync.lua`. See **Swarm Control Plane** and **Profile Sync** under Key Systems.

### Data/
Database management and persistence

- **TankMark_Data.lua**: DB initialization (`InitializeDB`), corruption detection (`ValidateDB`), snapshot system (`CreateSnapshot`/`RestoreFromSnapshot`), lazy-load zone data (`LoadZoneData`/`RefreshActiveDB`), roster management (`UpdateRoster`/`GetFirstAvailableBackup`), and the **Debug Logging System**:
  - `DebugLog(category, message, data)` — circular buffer (500 entries max), stored in `TankMarkDB.DebugLog`. Early-returns if `TankMark.DebugEnabled == false`, then **[v0.28, PR #49]** drops any category not in the optional `TankMark.DebugCategories` capture-time allow-list (`nil` = log every category).
  - `DumpDebugLog(filterCategory)` — prints to chat with color-coded categories.
  - `ClearDebugLog()` — wipes the buffer.
  - `UpdateZoneDropdowns()` — syncs Mob DB and Profile dropdowns on zone change.
- **TankMark_Defaults.lua**: Default mob database (shipped data).

### UI/
All visual components

- **TankMark_HUD.lua**: In-game heads-up display (8-row mark tracker). **[v0.29, swarm slice 2, PR #69]** `RenderSwarmLine()` paints a bottom-anchored swarm status line (queen name + derived role) in **both** render paths (profiled and `NO PROFILE LOADED`); display-only, reads live `Swarm` state, reserves 16px when shown.
- **TankMark_Options.lua**: Config panel entry point and tab management.
- **TankMark_UI_Widgets.lua**: Reusable UI components (dropdowns, buttons, etc.)
- **Config/**: Config panel tabs, split into two subdirectories:

#### Config/Database/ — Mob Database tab
- `TankMark_Config_Mobs.lua` — State registry: `mobRows`, `selectedIcon`, accordion state flags (`isAddMobExpanded`, `isSequentialExpanded`, `isSequentialActive`), and all Mob tab widget references.
- `TankMark_Config_Mobs_UI.lua` — [v0.27] **UI construction only.** All layout is expressed as private `local function` section builders (`CreateZoneControls`, `CreateMobList`, `CreateSearchBox`, etc.) called from the `CreateMobTab(parent)` entry point. Container frame uses `TOPLEFT 0,0 / BOTTOMRIGHT 0,0`. Zone dropdown anchored at `TOPLEFT 44,-43`. List background left edge at x=31 from the window. Exposes `UpdateMobZoneUI()`.
- `TankMark_Config_Mobs_List.lua` — Mob list rendering and `UpdateMobList()` scroll logic.
- `TankMark_Config_Mobs_Logic.lua` — Save/load/delete mob data, smart defaults, `ResetEditorState()`.
- `TankMark_Config_Mobs_Sequential.lua` — Sequential mark configuration: `RefreshSequentialRows()`, `OnAddMoreMarksClicked()`, `RemoveSequentialRow()`, `ActivateSequentialAccordion()`.
- `TankMark_Config_Mobs_Menus.lua` — Context menus: `InitIconMenu()`, `InitClassMenu()`, `InitSequentialIconMenu()`, `InitSequentialClassMenu()`.

#### Config/Profiles/ — Team Profiles tab
- `TankMark_Config_Profiles.lua` — State registry and data logic: `profileRows`, `profileCache`, `profileZoneDropdown`, `profileScroll`, profile templates (`TankMarkProfileTemplates`), `LoadProfileToCache()`, `SaveProfileCache()`, **[v0.29, swarm slice 4, PR #75]** `ApplyProfileToSession(zone)` (the shared seam factored out of `SaveProfileCache` — rebuild `sessionAssignments` + `UpdateHUD` only, no Print/dropdown-read/list-refresh/marking — used by both the queen's Save and the drone's `Swarm.OnProfile` apply edge; `SaveProfileCache` now also calls `Swarm.OnProfileSaved` so a queen push-on-Saves), `UpdateProfileList()`, `ProfileAddRow()`, `ProfileDeleteRow()`, `ToggleProfileZoneBrowser()`, `InferRoleFromClass()`, `InitProfileIconMenu()`, `AddHealerToRow()`, `UpdateProfileZoneUI()`, `ShowTemplateMenu()`, `ShowCopyProfileDialog()`, `RequestResetProfile()`.
- `TankMark_Config_Profiles_UI.lua` — [v0.27] **UI construction only.** Layout is expressed as five private `local function` section builders, each receiving `parent` (the tab container frame) and returning nothing except `CreateListArea` which returns `psf` for internal use:
  - `CreateTopRow(parent)` — Zone dropdown (`TMProfileZoneDropDown`, `TOPLEFT 44,-43`, matching Mobs tab), Manage Profiles checkbox (`TMManageProfilesCheck`, `TOPLEFT 243,-45`), Save Profile button (`TMProfileSaveBtn`, `TOPLEFT 372,-45`).
  - `CreateColumnHeaders(parent)` — Four `GameFontNormalSmall` labels at y=-85.
  - `CreateListArea(parent)` — `FauxScrollFrame` `TankMarkProfileScroll` at `TOPLEFT 37,-100`; backdrop `plistBg` anchored to the scroll frame. Left edge aligns with Mobs tab list background (both at 31px from the window).
  - `CreateRowPool(parent)` — Pool of 8 reusable `Frame` rows at x=40, y=-100-(i-1)*30. Each row contains: `row.zoneLabel` (hidden FontString for zone browser mode), icon button, tank edit box + T button, healer edit box + T button, offline-healer warning icon with tooltip, CC checkbox, Delete button. All references stored in `TankMark.profileRows[i]`.
  - `CreateBottomBar(parent)` — Add Mark / Use Template / Copy From / Reset buttons.
  - `CreateProfileTab(parent)` — Entry point. Container `t2` uses `TOPLEFT 0,0 / BOTTOMRIGHT 0,0` (same coordinate origin as Mobs tab `t1`).

#### Config/TankMark_Config_Data.lua — Data Management tab
Standalone file (not in a subdirectory). Snapshot restore, default merging, export/import UI. `BuildDataManagementTab(parent)`.

### Layout Alignment Convention (v0.27)
Both tab container frames (`t1` for Mobs, `t2` for Profiles) use `TOPLEFT 0,0 / BOTTOMRIGHT 0,0`. All pixel offsets inside both tabs are therefore in the same coordinate space. Key shared landmarks:

| Element | x offset from window | Anchor in code |
|---|---|---|
| Zone dropdown | 44px | `TOPLEFT 44, -43` |
| Manage checkbox | 243px | `TOPLEFT 243, -45` |
| List/scroll bg left edge | 31px | Mobs: `listBg TOPLEFT 31,-79`; Profiles: `psf TOPLEFT 37,-100` (bg inset adds 6px) |

Maintaining these shared anchors ensures no element "jumps" when switching tabs.

### Other
- **Bindings.xml**: Key binding definitions.
- **TankMark.toc**: Addon manifest and load order.

## Key Systems (v0.26)

### MarkMemory
A table (`TankMark.MarkMemory`) mapping `iconID → GUID` that tracks which mob currently holds each raid mark. Initialized in `TankMark_Scanner.lua`. Reinforced every scanner tick for visible marks. Flushed on combat end (`PLAYER_REGEN_ENABLED`, **partial** — `MarkMemory` only, so marks survive the addon-holder's own death) and session reset. **[v0.28, PR #52]** at pull-end *when alive*, `ClearMarksForPullEnd()` additionally does a full `Ledger.Clear()` (all four indices) plus a physical `mark1-8` strip — see **Pull-End Mark Clear**.

**Used by:** `IsMarkBusy()`, `GetMarkOwnerPriority()`, `EvictMarkOwner()`, `ReviewSkullState()`, `ProcessUnit()` (stale GUID cleanup), `GetBlockingMarkInfo()`, `GetFreeTankIcon()`.

### Decision Layer (decide / apply split + ports board)
**[v0.28, roadmap #2]** `ProcessUnit()` no longer decides *and* marks in one pass — the two concerns are split so the decision is inspectable and testable in isolation.

**Tier 1 (decide / apply, PR #41).** `DecideMark()` is the single decision seam: it returns an **intent** (`{ icon, reason, wasBusy?, override? }`) and applies **nothing**. `ProcessUnit()` then hands that intent to `ApplyMarkIntent()` — the **sole** decide-path apply edge (`RegisterMarkUsage` Ledger record → `Driver_ApplyMark`). So every automatic mark flows decide → intent → apply, and a decision can be exercised without touching the game.

**Tier 2 (ports board, PR #58).** The decide functions are **dependency-injected**: their only window onto the world is a `board` parameter — a table of closures over the live `TankMark` methods (state **reads**: combat/busy/priority/free-icon/blocker/CC/disabled) plus one side-effect **sink** (`logDecision`). Production passes `TankMark.LiveBoard` (`Core/TankMark_Processor.lua`); the off-client suite passes a mock. The closures resolve at **call time**, not build time, so within a single scanner tick a `board.getFreeTankIcon()` for candidate #2 already sees candidate #1's just-recorded `Assign` — a frozen snapshot would not. The board carries only state reads and the one sink; **pure** predicates such as `IncumbencyBlocks()` are not ports (they read no state) and stay direct calls. The result is a `DecideMark` that is **zero-global** apart from the pure-language `L._tgetn`, which is what lets the decision tree run under `lua5.1` with no WoW client — see **Testing**.

### Governor Check (Skull Incumbency)
Prevents skull from being assigned to a mob when existing marked mobs have equal or higher priority. **[v0.28]** The decide-path gate is `GovernorBlocks()` (shared by `DecideKnownMark`/`DecideUnknownMark` via the `allowSteal` flag); the death-path gate is `ReviewSkullState()`. **Both share one incumbency comparison** — `IncumbencyBlocks(myPrio, blockIcon, blockPrio)` in `TankMark_Assignment.lua` (roadmap #3, PR #43) — so the `>=` operator is single-sourced and can't drift. The PR #43 consolidation deliberately left the *policy* questions frozen; **[v0.28, PR #47]** the equal-prio **sheep-edge is now fixed** — a parked/CC'd incumbent is excluded from blocking via `IsMarkCCd()` (in `GetBlockingMarkInfo`/`UpdateBest`), while the `>=` operator itself is unchanged (a *non*-CC'd equal-prio incumbent still blocks). **[v0.28]** the unknown-path `allowSteal` asymmetry is now **resolved** (roadmap #3's last loose end): it is a *deliberate* split, not a deferred question — `known=true` honors the mob's DB designation (asserts the plan over a phantom/foreign holder), while `unknown=false` has nothing to assert and stays hands-off an occupied skull. No behavior change: unknown never stealing was already the shipped Tier-1 state.

### Pull-End Mark Clear
**[v0.28, PR #52]** Turtle WoW retains raid-target icons on mobs through death AND respawn, so a respawn wearing a retained skull could be adopted by `ReviewSkullState` into `MarkMemory[8]` and wedge skull reassignment for the rest of the run. `ClearMarksForPullEnd()` (`Core/TankMark_Death.lua`) fixes this at the source: on `PLAYER_REGEN_ENABLED`, when the addon-holder is **alive** (`not UnitIsDeadOrGhost("player")` — a tank's only alive combat-exit is the pull resolving), it physically strips every **hostile-worn** mark (`mark1-8`, guarded by `not UnitIsPlayer` so manually-placed player marks survive) and calls `Ledger.Clear()`. The raid leader's plan survives (`sessionAssignments`, profile DB, `disabledMarks`, sequential cursor, recorder are not Ledger indices) — this is **not** `ResetSession`. The dead/ghost path is deliberately skipped so marks survive the addon-holder's own death (same rationale as `FlushMemory`'s partial wipe). **Cut 1 ships the primary trigger only**; a scanner-tick fallback for the die→raid-finishes-pull→late-rez gap (no post-rez `REGEN`) and `RAW_COMBATLOG` engaged-set tracking are deferred to phase 2.

### Debug Logging
Toggle with `/tmark debug on|off`. Dump with `/tmark debug dump`, optionally filtered by category: `/tmark debug dump APPLY`, `/tmark debug dump DECIDE`, `/tmark debug dump BUSY` (any category, case-insensitive). Clear with `/tmark debug clear`. **[v0.28, PR #49]** Filter at *capture time* with `/tmark debug only <cats...>` (e.g. `/tmark debug only PROCESS DECIDE APPLY` — the ring then stores ONLY those categories, so a spammy category like `SKULL_REVIEW` ~2-4 entries/tick can't evict the decision entries before you read them); `/tmark debug all` clears the filter; `/tmark debug only` with no args prints it. Runtime-only (resets on `/reload`, like `DebugEnabled`). **[v0.28]** `/tmark debug ccscan` dumps the current target's debuffs with their aura IDs (the 4th `UnitDebuff` return) for gathering parked-CC IDs into `CCAuraSet` — a dev helper retained until the CC list is validated against Turtle.

**Performance rule:** All `DebugLog()` call sites MUST be wrapped in `if TankMark.DebugEnabled then ... end` to prevent argument construction when debug is off. See `Core/TankMark_Permissions.lua` `Driver_ApplyMark()` for the canonical pattern.

### Ownership Verification
In `ProcessUnit()`, when SuperWoW is available, `GetRaidTargetIndex(guid)` results are cross-checked against `UnitExists("mark"..icon)` to detect stale marks from theft scenarios.

### Sync Wire Codec
**[v0.29, swarm slice 1, PR #66]** The `M` mob-record wire format is single-sourced in the pure `Core/TankMark_SyncCodec.lua` (`EncodeMob` / `Decode`), replacing two hand-rolled copies that previously lived apart in `Sync.lua` — the encoder in `BroadcastZone`, the decoder in `HandleSync` (the original roadmap #4 defect). Same shape as the Decision Layer: a **pure** core (decode → validate → reject malformed → typed record; no WoW/Ledger/session state) plus a **single guarded apply edge** — `HandleSync`'s `TankMarkDB.Zones` write — that owns the stateful effect. This is what makes the codec unit-testable off-client (see **Testing**), and it is the intended substrate for the swarm's wider message set (heartbeat, profile, handoff — `SWARM_DESIGN.md` §8). **[v0.29, swarm slice 0, PR #64]** the second dialect (TWA/BigWigs inbound) is removed, so the codec is purely TM-native. Receiver-side consent (offer/accept + trust axis) is designed but deferred to a later slice (§7).

### Zone Cache & Cold-Login HUD Refresh
**[v0.29, PR #65]** `TankMark.currentZone` caches the current zone; `GetCachedZone()` is the read accessor. On a *cold* login `GetRealZoneText()` can return `""` before the zone APIs are ready, and `""` is truthy in Lua — so a naive cache sticks on the empty string and every `TankMarkProfileDB[zone]` lookup (and the HUD) misses, showing **"NO PROFILE LOADED"**. Fixed three ways: `GetCachedZone()` treats `""` like nil; a new **`PLAYER_ENTERING_WORLD`** handler (the first reliable zone moment on login, and it fires after every loading screen) re-reads the zone, runs `LoadZoneData`, and repaints the HUD when grouped; and `ZONE_CHANGED_NEW_AREA` now repaints too. Vanilla gotcha to remember: zone APIs are unreliable until `PLAYER_ENTERING_WORLD` / `ZONE_CHANGED_NEW_AREA` — `PLAYER_LOGIN` is too early.

### Swarm Control Plane
**[v0.29, swarm slice 2, PR #69]** `Core/TankMark_Swarm.lua` is the queen/drone consensus — **display-only** at this slice (it computes & shows who the single authorized marker *would* be; it changes **no** marking behavior, and only ever *reads* `CanAutomate`). Same pure-core + thin-shell shape as the Decision Layer and the Sync Wire Codec: the **election is a set of pure functions** the shell feeds plain tables, so it is unit-tested off-client (see **Testing**) before it ever touches a real raid.
- **Candidacy = `CanAutomate()`** (the existing automation gate, read-only). The two-filter **present set** (`ComputePresence`): *self* is present iff it is a candidate (from the gate, not heartbeats — we don't hear our own beats); any *other* is present iff heard within the 15s window **and** currently holds roster rank ≥ 1, so a **demote** drops it instantly (eligibility filter via `RAID_ROSTER_UPDATE`) while an **unclean DC** drops it at the window timeout (presence filter).
- **Election is deterministic** (`ElectQueen`), driven by the **claimant-count rule** that unifies three behaviors: **≥2** self-declared claimants → split-brain tiebreak `DeterministicMax(claimants)` (highest roster rank, then lowest name — *overrides* stickiness); **1** claimant → stickiness (the lone incumbent is kept, even against a higher-rank non-claimant that appeared later); **0** → fresh election over all present candidates (bootstrap-resolve or failover). Rank is read from the roster, never trusted from a payload.
- **Role is derived, not stored** (`DeriveRole` → `QUEEN`/`DRONE`/`NONE`/`BOOTSTRAP`). A fresh candidate opens a **15s bootstrap listen-window** (= `INTERVAL*MISS`), beating `amQueen=false` and deferring to any heard incumbent, before it may assert the crown.
- **Transport:** candidate-only `Q` heartbeat (5s interval / 3-miss = 15s) on the shared `TM_SYNC` prefix + 0.3s throttle; the wire carries `amQueen` plus **[v0.29, slice 4]** `planVersion` (the queen's profile counter, 0 for a non-queen — see **Profile Sync**) (`SWARM_DESIGN.md` §8). `HandleSync` routes `Q` to `Swarm.OnHeartbeat` behind the same `IsTrustedSender` gate as `M`.
- **Display:** the HUD bottom line (`RenderSwarmLine`) follows the election live; the chat notice (`UpdateNotice`) is **debounced ≥ 1 heartbeat cycle**, so the ~1s `NONE` flicker on a leader handover never reaches chat (BOOTSTRAP and solo commit silently). The `SWARM` debug category (`/tmark debug dump SWARM`) is the acceptance instrument.

### Single-Marker Enforcement
**[v0.29, swarm slice 3, PR #72]** The one slice that makes a non-queen actually *yield* — acting on the election above. It splits the two concepts slice 2 had conflated (`Swarm.SelfIsCandidate()` reads `CanAutomate()`):
- **`CanAutomate()` — UNCHANGED, the *candidacy* gate.** `SelfIsCandidate` keeps reading it, so the election candidate set and **failover pool are preserved**. Folding the queen-check into `CanAutomate` would have dropped every non-queen out of the candidate set and broken failover — the trap this split avoids.
- **`ShouldDriveMarks()` — the *marking* gate** (`Core/TankMark_Permissions.lua`): `CanAutomate() and (not Swarm.IsRunning() or Swarm.selfAmQueen)`. **Fail-open** — if the election shell isn't running, degrade to today's eligible-clients-mark rather than going silent (the server rank-gate is the real backstop). No circular dependency: it reads the **stored** `selfAmQueen` field, never `CanAutomate`'s queen-status.
- **Every world-mark `SetRaidTarget` path reads it** — not just the `CanAutomate` sites. Ten gates migrated: the scanner top (a drone does **zero** scan work — no snapshot/Reaffirm/decision; recorder bypass preserved), `HandleCombatLog`/`HandleDeath`/`UnmarkUnit`, both Batch guards, the `Driver_ApplyMark` backstop (the sole edge = authoritative enforcement point), **and three former `HasPermissions` paths** the audit surfaced: `ClearMarksForPullEnd` (automatic — un-gated every drone raced to strip the queen's marks at pull-end), the `ResetSession` physical strip (split from its local-state reset), and `ReviewSkullState` (a record-before-apply path). Untouched: `BroadcastZone` (sync eligibility), `SelfIsCandidate` (candidacy), the load-time NUCLEAR wipe (pre-election, self-healing), HUD texture calls.

In-game 2-box verified (queen marks / drone silent / drone DRONE-deference / failover reclaim with no gap). `SWARM_DESIGN.md` §5.9 + §12 row 3.

### Profile Sync
**[v0.29, swarm slice 4, PR #75]** The drone-visibility payoff: the queen pushes its **Team Profile** so drones render the plan, filling the 8-row HUD mark grid slice 3 left blank for non-queens. **Display == enactment** — a drone overwrites its own `TankMarkProfileDB[zone]` slot, so a promoted ex-drone marks off *exactly* the plan it was showing. `SWARM_DESIGN.md` §6.1.
- **Storage — single-slot overwrite, queen-authoritative.** `Swarm.OnProfile` overwrites `TankMarkProfileDB[<zone>]` directly (no separate drone cache, no backup) and re-renders via the shared `ApplyProfileToSession` seam. The profile is **carved out of §7's consent rule** (the queen is an elected, rank-gated authority you already delegated marking to; team profiles are operational and rebuilt per run) — unlike the curated Mob DB, which keeps offer/accept. Healers are deliberately **omitted from the wire** (never rendered; would overflow one message) until the chunked-transport slice.
- **Versioning — global runtime `planVersion`.** A single monotonic counter, bumped on every queen-side Save (`OnProfileSaved`) and on promotion (`OnPromoted`), advertised on the `Q` heartbeat. Each drone records the `(queenName, planVersion, zone)` triple it last applied (`appliedKey`).
- **Refresh — three triggers.** (1) **Push-on-Save** — `SaveProfileCache` → `OnProfileSaved` bumps + `PushProfile` (the fast path). (2) **Push-on-promotion** — `Recompute` detects the `selfAmQueen` rising edge → `OnPromoted` bumps + pushes the current zone, so a handoff converges even when the new queen's plan changed without a Save (e.g. a pre-promotion drone-side edit). (3) **Pull-on-mismatch** — `EvaluatePull` arms `needPull` whenever the live `(currentQueen, heardVersion, currentZone)` ≠ `appliedKey` (inequality, so a queen reload's counter reset still refetches; unknown cold-login zone defers); `FlushSync` fires one coalesced `PR` per tick, and the queen coalesces all `PR`s into one broadcast per zone per tick.
- **Trust + empty semantics.** `OnProfile` auto-applies **only** from the drone's own `Swarm.currentQueen` (stronger than the rank≥1 baseline; split-brain-safe). An **empty** snapshot → **keep** the current plan (a failover to an unprepared queen must not blank drones mid-run while the old queen's marks are still on the mobs) but still record the version. **Known limitation:** an intentional full-zone clear therefore does not propagate (a real re-plan is a non-empty Save, which does).
- **Wire surface:** `P` (profile snapshot, queen→drones) + `PR` (pull-request, drone→queen) message types + the `planVersion` heartbeat field, all in the pure codec (see **Sync Wire Codec**). The decode path is the untrusted parse edge; a focused `/security-review` of PR #75 found no actionable findings (the queen-gated apply + the server-rank `SetRaidTarget` backstop bound it). Off-client specs in `tests/profile_sync_spec.lua` (queen-gating, empty-keeps, the pull predicate, push-on-promotion) + the codec round-trips/rejections in `sync_codec_spec.lua`.

## Adding New Features

### Adding a New Mark Assignment Rule
1. Open `Core/TankMark_Assignment.lua`
2. Add your logic to `GetFreeTankIcon()` or create a new function
3. Call it from `DecideKnownMark()` in `Core/TankMark_Processor.lua` (return an intent — do not apply directly)
4. If the rule affects skull assignment, also update `GovernorBlocks()` and `ReviewSkullState()` in `Core/TankMark_Death.lua`

### Adding a New Debug Log Category
1. Add `DebugLog()` calls with your category string (e.g., "MYFEATURE")
2. **Always** wrap in `if TankMark.DebugEnabled then ... end`
3. Optionally add a `/tmark debug myfeature` filter in `TankMark.lua` `SlashHandler`

### Adding a New Config Tab
1. Create a subdirectory under `UI/Config/` matching the tab's domain (e.g., `UI/Config/NewFeature/`)
2. Create `TankMark_Config_NewFeature.lua` (state + logic) and `TankMark_Config_NewFeature_UI.lua` (UI construction)
3. In the UI file, use private `local function` section builders for each visual region; keep the public entry point to a single `TankMark:CreateNewFeatureTab(parent)` function
4. Set the container frame to `TOPLEFT 0,0 / BOTTOMRIGHT 0,0` to share the coordinate space with existing tabs
5. Register the tab in `UI/TankMark_Options.lua`
6. Update `TankMark.toc` load order

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
- **UI file structure:** Config tab UI files must use private `local function` section builders. No UI construction code inside the public entry point beyond calling section builders and returning the container frame. See `UI/Config/Database/TankMark_Config_Mobs_UI.lua` and `UI/Config/Profiles/TankMark_Config_Profiles_UI.lua` as the canonical patterns.

## Testing (v0.28)

TankMark has an **off-client unit-test suite** for the decision layer. It runs
outside the WoW client — no `/reload` needed — because the decision layer
(`DecideMark` and its helpers in `Core/TankMark_Processor.lua`) reads the world
only through an injected **board** of ports (roadmap #2 Tier 2). Production wires
`TankMark.LiveBoard` (closures over the live methods); tests inject a mock board.

**Run it** (from the repo root):
```
lua5.1 tests/run.lua
```
Exits non-zero if any assertion fails. The harness needs only Lua itself — no WoW
client, and no mock of the `Locals` table: the system under test is zero-global
apart from a few pure-language utilities the harness shims to their stock Lua
versions — `L._tgetn` (→ `table.getn`) for the decide layer, and **[v0.29]**
`L._sub` / `L._strfind` / `L._tonumber` / `L._tinsert` / `L._pairs` / `L._ipairs`
and **[slice 4]** `L._gfind` (→ `string.gmatch`, Vanilla's `string.gfind`) for the
SyncCodec and the swarm.

**Runtime:** production code stays Lua **5.0**-idiomatic (Vanilla WoW); the harness
runs on Lua **5.1** (closest widely-available interpreter — it still has
`table.getn`, removed in 5.2+). Do not introduce 5.1-only idioms into shipped code.

**Layout** (`tests/`, dev-only — never shipped to the AddOns folder; the deploy
script excludes the whole tree by path prefix):
- `run.lua` — entry point; lists the spec files and prints a pass/fail summary.
- `support/harness.lua` — stubs the minimum, loads the SUT (`Assignment.lua`,
  `Processor.lua`, and **[v0.29]** `SyncCodec.lua` + `Swarm.lua` — all
  definition-only), and provides a tiny `describe`/`it`/`eq`/`eq_intent` runner.
- `support/board.lua` — `make_board(overrides)`, a mock ports board with safe
  defaults (in combat, nothing busy/disabled/free, no CC, no blocker).
- `*_spec.lua` — `incumbency_spec` (the pure `IncumbencyBlocks` predicate),
  `decide_mark_spec` (combat gate, selection, fallback, bails), `governor_spec`
  (skull governor, CC, the `allowSteal` asymmetry), **[v0.29]** `sync_codec_spec`
  (the pure `SyncCodec` encode/decode round-trip + every rejection rule, incl. the
  slice-4 `P`/`PR`/`planVersion` types), `swarm_election_spec` (the pure election
  core — `DeterministicMax`/`ElectQueen`/`ComputePresence`/`DeriveRole`), and
  **[slice 4]** `profile_sync_spec` (queen-gated apply, empty-keeps, the
  `EvaluatePull` triple predicate, push-on-promotion).

**Adding a spec:** create `tests/<name>_spec.lua` using `describe`/`it`/`eq`/
`eq_intent` and `make_board{...}`, then add it to the `SPECS` list in `run.lua`.

## SavedVariables

| Variable | Scope | Description |
|---|---|---|
| `TankMarkDB` | Account-wide | Mob database (`Zones`), debug log (`DebugLog`) |
| `TankMarkProfileDB` | Per-character | Team profiles (mark → tank → healers assignments per zone) |
| `TankMarkDB_Snapshot` | Per-character | Up to 3 database snapshots for corruption recovery |
| `TankMarkCharConfig` | Per-character | Character-specific UI settings (HUD position, etc.) |

## Event Flow (Simplified)