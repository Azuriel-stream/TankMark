# TankMark (v0.13)

**TankMark** is an intelligent raid marking automation addon for Vanilla WoW (1.12.1). It automates the assignment of Raid Targets based on a priority system and includes tools for data collection and team coordination.

> **🚀 New in v0.13:** Smart Assignment UI, "Ignore" Logic, Auto-Icon Selection, and Full Lock Syncing!

## ✨ Key Features

### 🧠 Smart Automation
* **Priority System:** Define which mobs get marked first (e.g., "Giant" = Skull).
* **Auto-Assignment:** Automatically assigns marks to available tanks or mages based on your team profile.
* **Smart Skull (SuperWoW):** Instantly promotes the next highest-priority mob to Skull when the current target dies.
* **Hybrid Driver:** Intelligent range detection (using Spellbook scanning or SuperWoW API) to prevent marking distant mobs.

### 🎯 Smart Entry System (New!)
The configuration panel now adapts to what you target:
* **One-Click Setup:** Target a mob and click **"Target"**. TankMark detects if it is a Humanoid, Beast, or Elemental.
* **Auto-Configuration:**
    * Select **"Mage"** -> Icon becomes **Moon**, Priority becomes **3**.
    * Select **"Warlock"** -> Icon becomes **Diamond**, Priority becomes **3**.
    * Select **"No CC (Kill)"** -> Icon becomes **Skull**, Priority becomes **1**.

### 🚫 Ignore System
Have a mob you never want marked?
* Select **"IGNORE"** in the Class dropdown, or **"Disabled"** in the Icon dropdown.
* The mob remains in the database (so the Recorder won't re-add it) but will never be auto-marked.

### 🔧 Management Tools
* **Lock Mark:** Permanently bind a specific mark to a specific mob GUID (e.g., "Keep this specific add as Cross forever").
* **Zone Manager:** View, edit, or delete saved data for any zone.
* **Data Sync:** Broadcast your entire database (including Locked Marks!) to the raid with `/tmark sync`.

---

## 🎮 Commands

| Command | Description |
| :--- | :--- |
| `/tmark config` | Opens the **Configuration Panel**. |
| `/tmark recorder start` | Enables **Flight Recorder** (Auto-add mobs). |
| `/tmark sync` | **Broadcasts** priorities AND locks to the raid. |
| `/tmark reset` | **Wipes** all marks and assignments. |
| `/tmark assign [mark] [player]` | Manually assign a player. |
| `/tmark on` / `/tmark off` | Toggle automation. |

---

## ⚙️ Configuration Guide

### 1. The "Smart Row" (Bottom of Config)
1.  **Target** the mob you want to add.
2.  Click the **"Target"** button (Fills name & detects type).
3.  Choose a **Role** from the dropdown (e.g., "Mage").
    * *The Icon and Priority will auto-set for you.*
4.  (Optional) Click **"Lock Mark"** if you want this specific spawn to always keep this mark.
5.  Click **"Save"**.

### 2. Team Profiles
Assign specific players to marks for the current zone.
* *Example:* "MainTank" is always **Skull** (8). "OffTank" is always **Cross** (7).
* If a player dies, TankMark attempts to reassign their mark to a class-appropriate backup.

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