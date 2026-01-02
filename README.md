# TankMark (v0.11)

**TankMark** is an intelligent raid marking automation addon for Vanilla WoW (1.12.1). It automates the assignment of Raid Targets (Skull, Cross, Square, etc.) to enemy mobs based on a priority system, ensuring your tank team is always coordinated.

> **🚀 New in v0.11:** Major UI overhaul, Zone Manager, GUID Locks, and Data Syncing!

## ✨ Key Features

### 🧠 Smart Automation
* **Priority System:** Define which mobs get marked first (e.g., "Giant" = Skull, "Hound" = Cross).
* **Auto-Assignment:** Automatically assigns marks to available tanks or mages (for CC) based on your team profile.
* **Smart Skull (SuperWoW Only):** When the current **Skull** target dies, the addon instantly promotes the next highest-priority mob to Skull.

### 🛡️ Hybrid Driver
* **SuperWoW Users:** Uses high-speed Nameplate Scanning (40y range) to detect and mark enemies instantly without mouseover.
* **Standard Clients:** Falls back to a "Passive Mouseover" collector that builds the database as you play.

### 🔧 Management Tools (v0.11)
* **Zone Manager:** View, edit, or delete saved data for any zone in the game.
* **GUID Locking:** Lock a specific mark to a specific mob instance (GUID). Great for static boss fights or multi-mob pulls where positioning is key.
* **Data Sync:** Share your marking priorities and zone database with your fellow tanks or raid leader instantly.

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

| Command | Alias | Description |
| :--- | :--- | :--- |
| `/tm config` | `/tm c` | Opens the **Configuration Panel**. |
| `/tm sync` | `/tm share` | **Broadcasts** your current Zone Database to the raid/party. |
| `/tm reset` | `/tm r` | **Wipes** all current marks and resets session assignments. |
| `/tm assign` | | Manually assign a player: `/tm assign skull PlayerName` |
| `/tm on` | | Enables automation. |
| `/tm off` | | Disables automation. |

---

## ⚙️ Configuration Guide

### 1. The "Double-Decker" UI
The main panel allows you to add or edit mobs.
* **Target Button:** Fills the "Mob Name" box with your current target.
* **Priority:** `1` is highest (Skull/Cross), `2+` are lower priority.
* **Lock Checkbox:** Check this **while targeting a mob** to permanently assign that specific creature instance (GUID) to a mark.

### 2. Zone Manager
Click the **"Manage Zones"** checkbox at the top of the window.
* **View:** See all zones where you have saved data.
* **Locks:** Click the **"Locks"** button on a zone to view and delete specific GUID locks.
* **Delete:** Remove old or corrupt zone data to keep your database clean.

### 3. Team Profiles (Tab 2)
Assign specific players to specific marks.
* *Example:* Assign "MainTank" to **Skull** and "OffTank" to **Cross**.
* If a player is assigned to a mark, TankMark will whisper them when their target appears.

---

## 📡 Data Syncing
To share your configuration with other TankMark users:
1.  Open the **Configuration Panel** (`/tm config`).
2.  Ensure you are in a Party or Raid.
3.  Type `/tm sync`.
4.  Other users with **Assistant/Leader** privileges will automatically receive and merge your data for the current zone.

---

## ⚠️ Known Issues
* **Standard Client:** You must mouseover mobs to "discover" them before they can be marked. (SuperWoW users do not have this limitation).