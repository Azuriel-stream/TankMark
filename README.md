# TankMark (v0.23)

**TankMark** is an intelligent raid marking automation addon for Vanilla WoW (1.12.1), specifically optimized for Turtle WoW. It automates Raid Target assignment based on priority and includes tools for data collection and team coordination.

---

## ✨ Core Features

### 🎯 Intelligent Marking
- **Auto-Assignment:** Marks mobs based on priority (1-8) and Team Profile assignments.
- **Sequential Marking:** Assign up to 8 marks to a single mob for coordinated multi-target kills (v0.23).
- **Batch Marking:** Hold Shift + Mouseover to queue up to 8 mobs for sequential marking.
- **Combat Gating:** Scanner only marks mobs actively targeting raid members (Requires SuperWoW).
- **GUID Locking:** Lock specific mob spawns to always receive an assigned mark.
- **Ctrl+Mouseover:** Quickly unmark any mob.

### 👥 Team Management
- **Profile Templates:** 4 pre-built templates (8-Tank, 5-Tank, 3-Tank, CC Heavy).
- **Roster Validation:** Real-time highlighting when tanks/healers are offline.
- **Smart Fallback:** Auto-assigns roles based on class if no profile exists.
- **Healer Death Alerts:** Automatic whispers to tanks when their healer dies.
- **Copy Between Zones:** Duplicate profiles instantly.

### 📼 Data Collection
- **Flight Recorder:** Auto-record mobs by mousing over them (`/tmark recorder start`).
- **Mob Database:** Assign priorities and icons via config panel.
- **Zone Management:** Add, delete, and browse zones with GUID lock viewer.
- **Duplicate Detection:** Warns before overwriting existing mob entries (v0.23).

### 🖱️ Interactive HUD
- **Right-Click Menus:** Assign/clear/disable marks directly from HUD rows.
- **Position Memory:** HUD remembers position per-character.
- **Auto-Hide:** HUD hides when leaving party/raid.

---

## Installation

### Turtle WoW Launcher / GitAddonsManager
1. Open either application
2. Click **Add** button
3. Paste URL: `https://github.com/Azuriel-stream/TankMark`
4. Download and keep up to date

### Manual Installation
1. Download latest **.zip** from Releases page
2. Extract contents
3. Ensure folder is named `TankMark` (remove `-main` or version numbers)
4. Move to `\World of Warcraft\Interface\AddOns\` directory

---

## 🎮 Quick Start

### Basic Usage
1. `/tmark config` - Open configuration panel.
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

---

## ⚙️ Configuration Tips

### Quick Setup with Flight Recorder
1. `/tmark recorder start` in your target zone.
2. Fight mobs normally - all new encounters auto-added.
3. Recorder auto-disables when you leave zone.
4. Edit priorities in **Mob Database** tab later.

### Team Profile Setup
1. **Load Template:** Choose closest match to your raid comp.
2. **Assign Tanks:** Type names or click "T" button with target selected.
3. **Add Healers:** Click "T" button in healer field (space-delimited list).
4. **Save Profile:** Changes apply immediately.

---

## 🔄 Recent Updates

**v0.23** - Sequential marking (up to 8 marks per mob), two-column UI redesign, modular code refactor.
**v0.22** - HUD position persistence, unknown mob auto-marking, auto-reset on group leave.
**v0.21** - Batch marking system, combat gating, Ctrl+mouseover unmark.

---

## 🤝 Contributing

Contributions, bug reports, and feature requests welcome!  
**GitHub:** https://github.com/Azuriel-stream/TankMark

---

## 📜 License

MIT License