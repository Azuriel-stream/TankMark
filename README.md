# TankMark (v0.17)

**TankMark** is an intelligent raid marking automation addon for Vanilla WoW (1.12.1). It automates the assignment of Raid Targets based on a priority system and includes tools for data collection and team coordination.

> **🚀 New in v0.17:** Performance Optimization, Enhanced Stability, and Sync Data Validation.

## ✨ Key Features

### ⚡ Performance Improvements (New!)
Significant optimization for high-density combat scenarios.
* **Zone Caching System:** Reduces API overhead by ~50+ calls per combat pull.
* **Automatic UI Refresh:** Config panels now auto-update zone dropdowns after teleports.
* **Configurable Scanner Throttle:** Fine-tune nameplate scan intervals for performance tuning.

### 🛡️ Enhanced Stability (New!)
Bulletproof data integrity and error handling.
* **Sync Data Validation:** Incoming sync messages are now validated to prevent database corruption.
* **Wildcard Safety:** Fixed edge-case nil errors with empty tank assignments in profiles.
* **State Synchronization:** Profile cache pre-loads before tab switches to eliminate stale data display.

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

### 2. Team Profiles (Healers & Tanks)
Assign specific players to marks for any zone.
* **Wildcards:** Leave the Name field blank to let the addon use the mark freely.
* **TWA Sync:** Assignments are imported automatically if the RL broadcasts via BigWigs/TWAssignments.
* **Manual:** Type names into the **Tank** or **Healers** boxes and click Save.
* **Management:** Use the **Right-Click Context Menu** on the HUD to manage these on the fly.

---

## 🔄 Version History

* **v0.17** - Performance optimization, sync validation, zone caching
* **v0.16** - Modular architecture, HUD context menus, wildcard profiles
* **v0.15** - Ordered profile lists, TWA integration
* **v0.14** - Team profile system, sticky skull logic
