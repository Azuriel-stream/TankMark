# TankMark (v0.21)

**TankMark** is an intelligent raid marking automation addon for Vanilla WoW (1.12.1). It automates the assignment of Raid Targets based on a priority system and includes tools for data collection and team coordination.

> **🚀 New in v0.19:** Batch Marking System!

## ✨ Key Features

### ⚡ Batch Marking System (New!)
Queue multiple mobs for intelligent sequential marking.
* **Hold Shift + Mouseover:** Queue up to 8 mobs for batch processing.
* **Priority Sorting:** Marks are assigned based on mob priority (1-8), then mouseover order.
* **Smart Assignment:** Respects Team Profile assignments and mark availability.
* **Combat Gating:** Scanner only marks mobs actively targeting raid members.
* **Ctrl+Mouseover:** Quickly unmark any mob without opening menus.

### 🎯 Profile Templates
Quick-start your team configuration with pre-built templates.
* **4 Templates:** Standard 8-Tank, Priority 5-Tank, Minimal 3-Tank, CC Heavy (4 Tank + 4 CC)
* **One-Click Setup:** Load any template, add player names, save.
* **Copy From...:** Duplicate existing profiles between zones instantly.

### 👥 Roster Validation
Real-time feedback on team readiness.
* **Red Name Highlighting:** Tank/Healer names turn red when offline or not in raid.
* **Warning Icons:** Yellow alert icons appear when assigned healers are offline.
* **Status Tooltips:** Hover over warning icon to see detailed healer status.
* **Auto-Updates:** Refreshes when players join/leave raid.

### 💔 Healer Death Alerts
Automatic notifications keep tanks informed.
* **Instant Whispers:** Tank receives alert when their healer dies.
* **Smart Filtering:** Only alerts for healers currently in raid.
* **Multi-Healer Support:** Handles space-delimited healer lists.

### 🗺️ Zone Management Tools
Complete zone lifecycle control.
* **Add Zone Button:** Add current zone to database with confirmation.
* **Delete Zone:** Remove entire zone with all data (with safety prompt).
* **Lock Viewer:** Browse and edit GUID-locked mobs per zone.
* **Manage Zones Browser:** View all saved zones with lock counts.

### 📼 Enhanced Flight Recorder
Smarter mob recording workflow.
* **Zone Pre-Creation:** Automatically creates zone entry on recorder start.
* **Duplicate Prevention:** Skips mobs already in database (no spam).
* **Auto-Disable:** Turns off when you leave the zone with notification.
* **Immediate Use:** Recorded mobs available for marking instantly.

### ⚡ Performance Improvements
Significant optimization for high-density combat scenarios.
* **Zone Caching System:** Reduces API overhead by ~50+ calls per combat pull.
* **Automatic UI Refresh:** Config panels now auto-update zone dropdowns after teleports.
* **Configurable Scanner Throttle:** Fine-tune nameplate scan intervals for performance tuning.

### 🖱️ HUD Context Menus
The HUD is now a fully interactive Command Center.
* **Right-Click Any Row:** Instantly access management options for that specific mark.
    * **Assign Target:** Links the mark to your current target immediately.
    * **Clear:** Frees the mark for auto-assignment.
    * **Disable/Enable:** Toggles the mark's usage status.

### 💀 Sticky Skull Logic
Smarter combat tracking prevents the "disco ball" effect during AoE pulls.
* **10% HP Threshold:** The Skull mark will no longer jitter rapidly between mobs with similar health. It only swaps if a new target is significantly lower (10% difference) or the current Skull dies.
* **SuperWoW Integration:** Uses `RAW_COMBATLOG` events (if available) for precise death tracking, ensuring the mark only moves when the specific GUID dies.

### 🃏 Wildcard Profiles
More flexible team assignments.
* **Empty Slots = Wildcards:** If you leave the "Assigned Tank" field **blank** in your Team Profile, TankMark treats that mark as a "Wildcard."
* **Auto-Fill:** The engine will use these Wildcard marks to auto-mark mobs even if no specific player is defined for them.

### 🏗️ Modular Core
* **Refactored Engine:** The addon has been split into specialized modules (`Engine`, `Scanner`, `UI`) for better performance and stability.
* **Relaxed Automation:** You can now force-mark mobs (Shift+Mouseover) even if you haven't built a database for the current zone yet.

---

## Installation

### Turtle WoW Launcher / GitAddonsManager
1.  Open either application.
2.  Click the **Add** button.
3.  Paste the url: `https://github.com/Azuriel-stream/TankMark`
4.  Download and keep up to date.

### Manual Installation
1.  Download the latest **.zip** file from the Releases page.
2.  Extract the contents.
3.  Ensure the folder is named `TankMark` (remove `-main` or version numbers if present).
4.  Move the folder to your `\World of Warcraft\Interface\AddOns\` directory.

---

## 🎮 Commands

| Command | Description |
| :--- | :--- |
| `/tmark config` | Opens the **Configuration Panel**. |
| `/tmark announce` | **Announce** current assignments to Raid/Party chat. |
| `/tmark normals` | Toggle marking of **Normal/Non-Elite** mobs. |
| `/tmark sync` | **Broadcasts** priorities AND locks to the raid. |
| `/tmark recorder start` | Enables **Flight Recorder** (Auto-add mobs). |
| `/tmark recorder stop` | Disables **Flight Recorder**. |
| `/tmark reset` | **Wipes** all marks and assignments (HUD & In-Game). |
| `/tmark on` / `/tmark off` | Toggle automation. |
| `/tmark assign [mark] [player]` | Manually assign a player to a mark via command line. |
| `/tmark zone` | Displays current zone and driver mode (debug). |

---

## ⚙️ Configuration Guide

### 1. Mob Database
1.  **Target** the mob you want to add.
2.  Click **"Target"** (Auto-detects Name, Icon, and Type).
3.  Choose a **Role** (e.g., "Mage" sets Moon).
4.  Click **"Save"**.

#### Quick Setup with Flight Recorder:
1.  `/tmark recorder start` in the zone you want to record.
2.  Fight mobs normally - all new mobs auto-added to database.
3.  Recorder auto-disables when you leave the zone.
4.  Edit priorities/icons in Mob Database tab later.

### 2. Team Profiles

#### Quick Setup with Templates:
1.  Open **Team Profiles** tab.
2.  Click **"Load Template"** → Select template.
3.  Add player names to **Tank** fields.
4.  (Optional) Add **Healers** (space-delimited list).
5.  Click **"Save Profile"**.

#### Copy Between Zones:
1.  Select target zone in dropdown.
2.  Click **"Copy From..."** button.
3.  Select source zone from list.
4.  Edit as needed and **Save**.

#### Manual Assignment:
* **Tank Field:** Type player name or click "T" button to use current target.
* **Healer Field:** Click "T" button to add current target to healer list (auto-appends, checks duplicates).
* **Warning Icon:** Yellow icon appears when any assigned healer is offline.
* **Roster Validation:** Names turn red when players are not in raid/party.

---

## 🔄 Version History

* **v0.21** - Batch marking system, combat gating, activeDB auto-refresh, Ctrl+mouseover unmark
* **v0.20** - Merged zone cache, snapshot system, corruption detection
* **v0.19** - Profile templates, zone cloning, healer death alerts, roster validation
* **v0.18** - Zone management tools, flight recorder improvements
* **v0.17** - Performance optimization, sync validation, zone caching
* **v0.16** - Modular architecture, HUD context menus, wildcard profiles
* **v0.15** - Ordered profile lists, TWA integration
* **v0.14** - Team profile system, sticky skull logic

---

## 🤝 Contributing

Contributions, bug reports, and feature requests are welcome!
- **GitHub:** https://github.com/Azuriel-stream/TankMark

---

## 📜 License

This project is licensed under the MIT License.
