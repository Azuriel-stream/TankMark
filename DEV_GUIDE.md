# TankMark Developer Guide

## Project Structure

### Core/
Contains business logic (marking algorithms, death handling, etc.)
- **TankMark_State.lua**: Centralized state variables and constants
- **TankMark_Permissions.lua**: Permission checks and validation
- **TankMark_Assignment.lua**: Mark assignment algorithms
- **TankMark_Processor.lua**: Core marking decision logic
- **TankMark_Death.lua**: Death detection and skull management
- **TankMark_Batch.lua**: Batch marking system
- **TankMark_Scanner.lua**: SuperWoW nameplate scanning
- **TankMark_Sync.lua**: Raid data synchronization

### Data/
Database management and persistence
- **TankMark_Data.lua**: DB initialization, zone caching, roster sync
- **TankMark_Defaults.lua**: Default mob database

### UI/
All visual components
- **TankMark_HUD.lua**: In-game heads-up display
- **TankMark_Options.lua**: Config panel entry point
- **TankMark_UI_Widgets.lua**: Reusable UI components
- **Config/**: Config panel tabs (Mob Database, Team Profiles, Data Management)

## Adding New Features

### Adding a New Mark Assignment Rule
1. Open `Core/TankMark_Assignment.lua`
2. Add your logic to `GetFreeTankIcon()` or create a new function
3. Call it from `Core/TankMark_Processor.lua` in `ProcessKnownMob()`

### Adding a New Config Tab
1. Create `UI/Config/TankMark_Config_NewTab.lua`
2. Add UI creation logic
3. Register tab in `UI/TankMark_Options.lua`
4. Update `TankMark.toc` load order

## Coding Standards
- Always use `TankMark.Locals` for API functions (no global calls)
- Use `local L = TankMark.Locals` at the top of each file
- Validate all user inputs (check for nil before indexing)
- Use `table.getn()` for array length (NOT `#table`)
- Comment complex algorithms with `-- [v0.XX]` version tags
