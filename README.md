# TankMark (v0.15)

**TankMark** is an intelligent raid marking automation addon for Vanilla WoW (1.12.1). It automates the assignment of Raid Targets based on a priority system and includes tools for data collection and team coordination.

> **🚀 New in v0.15:** Interactive HUD Toggles, Ordered Team Profiles, and Resource-Based Logic.

## ✨ Key Features

### 📋 Ordered Team Profiles (New!)
Complete control over your marking hierarchy.
* **Drag & Drop Order:** Define exactly which Mark gets assigned first.
* **Dead Tank Skipping:** If the player assigned to "Skull" dies, TankMark automatically skips to the next Mark in your list.
* **Empty Profile Warning:** The HUD now alerts you if no profile is loaded for the current zone.

### 🎛️ Interactive HUD (New!)
The HUD is now a control panel, not just a display.
* **Click to Toggle:** Left-click any row in the HUD to **Disable/Enable** that mark instantly.
* **Usage:** Useful for temporarily disabling a specific CC assignment on a per-pack basis.

### 📡 TWA Integration
TankMark listens to **BigWigs Sync** messages from the **TWAssignments** addon.
* Automatically imports Tank/Healer assignments and sorts them into your Team Profile hierarchy.

### 🧠 Smart Automation
* **Priority System:** Define which mobs get marked first (e.g., "Giant" = Skull).
* **Hybrid Driver:** Intelligent range detection (using Spellbook scanning or SuperWoW API).
* **Normal Mob Filter:** Toggle marking of non-elite mobs via `/tmark normals` (Default: OFF).

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

---

## ⚙️ Configuration Guide

### 1. Mob Database
1.  **Target** the mob you want to add.
2.  Click **"Target"** (Auto-detects Name, Icon, and Type).
3.  Choose a **Role** (e.g., "Mage" sets Moon).
4.  Click **"Save"**.

### 2. Team Profiles (Healers & Tanks)
Assign specific players to marks for any zone.
* **TWA Sync:** Happens automatically if the RL broadcasts via BigWigs.
* **Manual:** Type names into the **Tank** or **Healers** boxes and click Save.
* **Management:** Use the **Delete Profile** button to remove junk data from old zones.