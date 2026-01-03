# TankMark (v0.12)

**TankMark** is an intelligent raid marking automation addon for Vanilla WoW (1.12.1). It automates the assignment of Raid Targets based on a priority system and includes tools for data collection and team coordination.

> **🚀 New in v0.12:** Flight Recorder, Lock Editor, and command changed to `/tmark`!

## ✨ Key Features

### 🧠 Smart Automation
* **Priority System:** Define which mobs get marked first (e.g., "Giant" = Skull).
* **Auto-Assignment:** Automatically assigns marks to available tanks or mages based on your team profile.
* **Smart Skull (SuperWoW):** Instantly promotes the next highest-priority mob to Skull when the current target dies.

### ✈️ Flight Recorder (New!)
* **Capture Mode:** Turn on the recorder to automatically build your database as you run a dungeon.
* **Usage:** `/tmark recorder start` to begin. All seen mobs are added as **Skull (Prio 1)**.
* **Refine:** Stop the recorder (`/tmark recorder stop`) and use the UI to adjust priorities later.

### 🔧 Management Tools
* **Lock Editor:** Click "E" on any GUID lock to change the icon or name instantly.
* **Zone Manager:** View, edit, or delete saved data for any zone.
* **Data Sync:** Broadcast your database to the raid with `/tmark sync`.

---

## 📥 Installation

### Turtle WoW Launcher / GitAddonsManager
1.  Open application -> **Add**.
2.  Paste url: `https://github.com/Azuriel-stream/TankMark`
3.  Download.

### Manual Installation
1.  Download the **.zip** from Releases.
2.  Extract to `\Interface\AddOns\`.
3.  Rename folder to `TankMark`.

---

## 🎮 Commands

**Note:** Command changed to `/tmark` in v0.12 to avoid conflicts.

| Command | Description |
| :--- | :--- |
| `/tmark config` | Opens the **Configuration Panel**. |
| `/tmark recorder start` | Enables **Flight Recorder** (Auto-add mobs). |
| `/tmark sync` | **Broadcasts** your Zone DB to the raid. |
| `/tmark reset` | **Wipes** all marks and assignments. |
| `/tmark assign [mark] [player]` | Manually assign a player. |
| `/tmark on` / `/tmark off` | Toggle automation. |

---

## ⚙️ Configuration Guide

### 1. The "Double-Decker" UI
* **Target Button:** Fills "Mob Name" with current target.
* **Priority:** `1` (High) to `9` (Low).
* **Lock Checkbox:** Check to lock a specific GUID (requires Target).

### 2. Zone Manager & Locks
* **Manage Zones:** Check this to browse database by zone.
* **Locks View:** Click "Locks" on a zone to see/delete specific GUIDs.
* **Edit Locks:** Click "E" to modify a lock's icon or name without re-targeting.

---

## ⚠️ Known Issues
* **Standard Client:** You must mouseover mobs to "discover" them (unless using Flight Recorder + SuperWoW).