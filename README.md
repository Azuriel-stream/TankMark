# TankMark

**TankMark** is an intelligent raid marking automation addon for Vanilla WoW (1.12.1), specifically optimized for Turtle WoW. It automates Raid Target assignment based on priority and includes tools for data collection and team coordination.

---

## ✨ Core Features

### 🎯 Intelligent Marking
- **Auto-Assignment:** Marks mobs based on priority (1–8) and Team Profile assignments.
- **Sequential Marking:** Assign up to 8 marks to a single mob for coordinated multi-target kills.
- **Batch Marking:** Hold Shift + Mouseover to queue up to 8 mobs for sequential marking.
- **Combat Gating:** Scanner only marks mobs actively targeting raid members (requires SuperWoW).
- **GUID Locking:** Lock specific mob spawns to always receive an assigned mark.
- **Ctrl+Mouseover:** Quickly unmark any mob (combat-gated to prevent accidental removals).
- **MarkMemory:** Persistent mark-to-GUID tracking prevents redundant re-marks and enables intelligent mark theft.
- **Governor Check:** Skull assignment respects incumbency — existing marked mobs with equal or higher priority block skull theft.
- **Ownership Verification:** Server-side mark validation via SuperWoW `mark` unit tokens detects stale marks and external theft.

### 👥 Team Management
- **Profile Templates:** 4 pre-built templates (8-Tank, 5-Tank, 3-Tank, CC Heavy).
- **Roster Validation:** Real-time highlighting when tanks or healers are offline.
- **Smart Fallback:** Auto-assigns roles based on class when no profile exists.
- **Healer Death Alerts:** Automatic whispers to tanks when their assigned healer dies.
- **Copy Between Zones:** Duplicate profiles across zones instantly.

### 📼 Data Collection
- **Flight Recorder:** Auto-record mobs by mousing over them (`/tmark recorder start`).
- **Mob Database:** Assign priorities and icons via the config panel.
- **Zone Management:** Add, delete, and browse zones with a GUID lock viewer.
- **Duplicate Detection:** Warns before overwriting existing mob entries.

### 🖱️ Interactive HUD
- **Right-Click Menus:** Assign, clear, or disable marks directly from HUD rows.
- **Position Memory:** HUD position is saved per-character.
- **Auto-Hide:** HUD hides automatically when leaving party or raid.
- **Auto-Show:** HUD appears on login when already in a group.

### 🐛 Debug Logging
- **Circular Buffer:** Up to 500 debug entries stored in SavedVariables.
- **Category Filtering:** Dump only the log categories you care about (e.g., `apply`, `busy`, `skull`).
- **Performance-Safe:** All logging is gated behind `TankMark.DebugEnabled` — zero overhead when disabled.

---

## Installation

### Turtle WoW Launcher / GitAddonsManager
1. Open either application.
2. Click **Add** button.
3. Paste URL: `https://github.com/Azuriel-stream/TankMark`
4. Download and keep up to date.

### Manual Installation
1. Download the latest **.zip** from the Releases page.
2. Extract contents.
3. Ensure the folder is named `TankMark` (remove `-main` or version suffixes).
4. Move to `\World of Warcraft\Interface\AddOns\` directory.

---

## 🎮 Quick Start

### Basic Usage
1. `/tmark config` — Open configuration panel.
2. **Team Profiles tab:** Load a template, add player names, save.
3. **Mob Database tab:** Use Flight Recorder or manually add mobs.
4. Marks apply automatically during combat.

### Essential Commands
| Command | Description |
|---------|-------------|
| `/tmark config` | Open configuration panel |
| `/tmark recorder start/stop` | Toggle mob auto-recording |
| `/tmark announce` | Announce assignments to raid/party chat |
| `/tmark reset` | Clear all marks and reset session |
| `/tmark normals` | Toggle marking normal/non-elite mobs |
| `/tmark debug on` | Enable debug logging |
| `/tmark debug off` | Disable debug logging |
| `/tmark debug dump [category]` | Print debug log to chat (optionally filtered) |
| `/tmark debug clear` | Clear the debug log buffer |

---

## ⚙️ Configuration Tips

### Quick Setup with Flight Recorder
1. `/tmark recorder start` in your target zone.
2. Fight mobs normally — all new encounters are auto-added.
3. Recorder auto-disables when you leave the zone.
4. Edit priorities in the **Mob Database** tab later.

### Team Profile Setup
1. **Load Template:** Choose the closest match to your raid composition.
2. **Assign Tanks:** Type names or click the "T" button with your target selected.
3. **Add Healers:** Click the "T" button in the healer field (space-delimited list).
4. **Save Profile:** Changes apply immediately.

---

## 🤝 Contributing

Contributions, bug reports, and feature requests welcome!  
**GitHub:** https://github.com/Azuriel-stream/TankMark

---

## 📜 License

MIT License
