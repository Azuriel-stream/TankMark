-- TankMark: v0.20
-- File: TankMark_Defaults.lua
-- [v0.20] Default Mob Database - Curated baseline priorities for top-tier content

-- ==========================================================
-- DEFAULT MOB DATABASE
-- ==========================================================
-- This database serves as a fallback and starting point for new users.
-- User customizations in TankMarkDB always take priority.
-- Format: [zone][mobName] = {prio, mark, type, class}

TankMarkDefaults = {}

-- ==========================================================
-- MOLTEN CORE
-- ==========================================================
TankMarkDefaults["Molten Core"] = {
	-- Bosses
	["Lucifron"] = {prio=1, mark=8, type="KILL", class=nil},
	["Magmadar"] = {prio=1, mark=8, type="KILL", class=nil},
	["Gehennas"] = {prio=1, mark=8, type="KILL", class=nil},
	["Garr"] = {prio=1, mark=8, type="KILL", class=nil},
	["Shazzrah"] = {prio=1, mark=8, type="KILL", class=nil},
	["Baron Geddon"] = {prio=1, mark=8, type="KILL", class=nil},
	["Sulfuron Harbinger"] = {prio=1, mark=8, type="KILL", class=nil},
	["Golemagg the Incinerator"] = {prio=1, mark=8, type="KILL", class=nil},
	["Majordomo Executus"] = {prio=1, mark=8, type="KILL", class=nil},
	["Ragnaros"] = {prio=1, mark=8, type="KILL", class=nil},
	
	-- High Priority Adds
	["Flamewaker Healer"] = {prio=1, mark=8, type="KILL", class=nil},
	["Flamewaker Elite"] = {prio=2, mark=8, type="KILL", class=nil},
	["Flamewaker Priest"] = {prio=1, mark=8, type="KILL", class=nil},
	["Core Hound"] = {prio=3, mark=8, type="KILL", class=nil},
	["Lava Surger"] = {prio=3, mark=8, type="KILL", class=nil},
	["Firesworn"] = {prio=4, mark=8, type="KILL", class=nil},
	
	-- CC Targets
	["Ancient Core Hound"] = {prio=5, mark=8, type="KILL", class=nil},
	["Lava Spawn"] = {prio=6, mark=8, type="KILL", class=nil},
}

-- ==========================================================
-- BLACKWING LAIR
-- ==========================================================
TankMarkDefaults["Blackwing Lair"] = {
	-- Bosses
	["Razorgore the Untamed"] = {prio=1, mark=8, type="KILL", class=nil},
	["Vaelastrasz the Corrupt"] = {prio=1, mark=8, type="KILL", class=nil},
	["Broodlord Lashlayer"] = {prio=1, mark=8, type="KILL", class=nil},
	["Firemaw"] = {prio=1, mark=8, type="KILL", class=nil},
	["Ebonroc"] = {prio=1, mark=8, type="KILL", class=nil},
	["Flamegor"] = {prio=1, mark=8, type="KILL", class=nil},
	["Chromaggus"] = {prio=1, mark=8, type="KILL", class=nil},
	["Nefarian"] = {prio=1, mark=8, type="KILL", class=nil},
	
	-- High Priority Adds
	["Blackwing Mage"] = {prio=1, mark=8, type="KILL", class=nil},
	["Blackwing Warlock"] = {prio=1, mark=8, type="KILL", class=nil},
	["Death Talon Dragonspawn"] = {prio=2, mark=8, type="KILL", class=nil},
	["Blackwing Technician"] = {prio=3, mark=8, type="KILL", class=nil},
	["Blackwing Legionnaire"] = {prio=4, mark=8, type="KILL", class=nil},
}

-- ==========================================================
-- ONYXIA'S LAIR
-- ==========================================================
TankMarkDefaults["Onyxia's Lair"] = {
	["Onyxia"] = {prio=1, mark=8, type="KILL", class=nil},
	["Onyxian Whelp"] = {prio=7, mark=1, type="KILL", class=nil},
	["Onyxian Warder"] = {prio=3, mark=8, type="KILL", class=nil},
}

-- ==========================================================
-- ZULGURUB
-- ==========================================================
TankMarkDefaults["Zul'Gurub"] = {
	-- Bosses
	["High Priestess Jeklik"] = {prio=1, mark=8, type="KILL", class=nil},
	["High Priest Venoxis"] = {prio=1, mark=8, type="KILL", class=nil},
	["High Priestess Mar'li"] = {prio=1, mark=8, type="KILL", class=nil},
	["Bloodlord Mandokir"] = {prio=1, mark=8, type="KILL", class=nil},
	["High Priest Thekal"] = {prio=1, mark=8, type="KILL", class=nil},
	["High Priestess Arlokk"] = {prio=1, mark=8, type="KILL", class=nil},
	["Hakkar"] = {prio=1, mark=8, type="KILL", class=nil},
	
	-- High Priority
	["Zealot Lor'Khan"] = {prio=1, mark=8, type="KILL", class=nil},
	["Zealot Zath"] = {prio=1, mark=8, type="KILL", class=nil},
	["Zulian Tiger"] = {prio=2, mark=8, type="KILL", class=nil},
	["Razzashi Venombrood"] = {prio=3, mark=8, type="KILL", class=nil},
}

-- ==========================================================
-- AHN'QIRAJ (40)
-- ==========================================================
TankMarkDefaults["Ahn'Qiraj"] = {
	-- Bosses
	["The Prophet Skeram"] = {prio=1, mark=8, type="KILL", class=nil},
	["Vem"] = {prio=1, mark=8, type="KILL", class=nil},
	["Lord Kri"] = {prio=1, mark=8, type="KILL", class=nil},
	["Princess Yauj"] = {prio=1, mark=8, type="KILL", class=nil},
	["Battleguard Sartura"] = {prio=1, mark=8, type="KILL", class=nil},
	["Fankriss the Unyielding"] = {prio=1, mark=8, type="KILL", class=nil},
	["Viscidus"] = {prio=1, mark=8, type="KILL", class=nil},
	["Princess Huhuran"] = {prio=1, mark=8, type="KILL", class=nil},
	["Emperor Vek'lor"] = {prio=1, mark=8, type="KILL", class=nil},
	["Emperor Vek'nilash"] = {prio=1, mark=8, type="KILL", class=nil},
	["Ouro"] = {prio=1, mark=8, type="KILL", class=nil},
	["C'Thun"] = {prio=1, mark=8, type="KILL", class=nil},
	
	-- High Priority
	["Anubisath Defender"] = {prio=2, mark=8, type="KILL", class=nil},
	["Qiraji Mindslayer"] = {prio=1, mark=8, type="KILL", class=nil},
	["Vekniss Warrior"] = {prio=3, mark=8, type="KILL", class=nil},
}

-- ==========================================================
-- NAXXRAMAS
-- ==========================================================
TankMarkDefaults["Naxxramas"] = {
	-- Spider Wing
	["Anub'Rekhan"] = {prio=1, mark=8, type="KILL", class=nil},
	["Grand Widow Faerlina"] = {prio=1, mark=8, type="KILL", class=nil},
	["Maexxna"] = {prio=1, mark=8, type="KILL", class=nil},
	["Naxxramas Worshipper"] = {prio=1, mark=8, type="KILL", class=nil},
	["Naxxramas Follower"] = {prio=2, mark=8, type="KILL", class=nil},
	
	-- Plague Wing
	["Noth the Plaguebringer"] = {prio=1, mark=8, type="KILL", class=nil},
	["Heigan the Unclean"] = {prio=1, mark=8, type="KILL", class=nil},
	["Loatheb"] = {prio=1, mark=8, type="KILL", class=nil},
	["Plagued Warrior"] = {prio=3, mark=8, type="KILL", class=nil},
	
	-- Military Wing
	["Instructor Razuvious"] = {prio=1, mark=8, type="KILL", class=nil},
	["Gothik the Harvester"] = {prio=1, mark=8, type="KILL", class=nil},
	["Highlord Mograine"] = {prio=1, mark=8, type="KILL", class=nil},
	["Thane Korth'azz"] = {prio=1, mark=8, type="KILL", class=nil},
	["Lady Blaumeux"] = {prio=1, mark=8, type="KILL", class=nil},
	["Sir Zeliek"] = {prio=1, mark=8, type="KILL", class=nil},
	["Death Knight Captain"] = {prio=2, mark=8, type="KILL", class=nil},
	
	-- Construct Wing
	["Patchwerk"] = {prio=1, mark=8, type="KILL", class=nil},
	["Grobbulus"] = {prio=1, mark=8, type="KILL", class=nil},
	["Gluth"] = {prio=1, mark=8, type="KILL", class=nil},
	["Thaddius"] = {prio=1, mark=8, type="KILL", class=nil},
	
	-- Frostwyrm Lair
	["Sapphiron"] = {prio=1, mark=8, type="KILL", class=nil},
	["Kel'Thuzad"] = {prio=1, mark=8, type="KILL", class=nil},
}

-- ==========================================================
-- STRATHOLME
-- ==========================================================
TankMarkDefaults["Stratholme"] = {
	["Baron Rivendare"] = {prio=1, mark=8, type="KILL", class=nil},
	["Magistrate Barthilas"] = {prio=1, mark=8, type="KILL", class=nil},
	["Ramstein the Gorger"] = {prio=1, mark=8, type="KILL", class=nil},
	["Risen Protector"] = {prio=2, mark=8, type="KILL", class=nil},
	["Risen Priest"] = {prio=1, mark=8, type="KILL", class=nil},
	["Risen Wizard"] = {prio=2, mark=8, type="KILL", class=nil},
	["Skeletal Guardian"] = {prio=3, mark=8, type="KILL", class=nil},
}

-- ==========================================================
-- SCHOLOMANCE
-- ==========================================================
TankMarkDefaults["Scholomance"] = {
	["Darkmaster Gandling"] = {prio=1, mark=8, type="KILL", class=nil},
	["Instructor Malicia"] = {prio=1, mark=8, type="KILL", class=nil},
	["Ras Frostwhisper"] = {prio=1, mark=8, type="KILL", class=nil},
	["Scholomance Dark Summoner"] = {prio=1, mark=8, type="KILL", class=nil},
	["Scholomance Necromancer"] = {prio=2, mark=8, type="KILL", class=nil},
	["Risen Aberration"] = {prio=3, mark=8, type="KILL", class=nil},
}

-- ==========================================================
-- UPPER BLACKROCK SPIRE
-- ==========================================================
TankMarkDefaults["Blackrock Spire"] = {
	["General Drakkisath"] = {prio=1, mark=8, type="KILL", class=nil},
	["Pyroguard Emberseer"] = {prio=1, mark=8, type="KILL", class=nil},
	["Solakar Flamewreath"] = {prio=1, mark=8, type="KILL", class=nil},
	["Warchief Rend Blackhand"] = {prio=1, mark=8, type="KILL", class=nil},
	["Blackhand Assassin"] = {prio=2, mark=8, type="KILL", class=nil},
	["Blackhand Elite"] = {prio=3, mark=8, type="KILL", class=nil},
	["Blackhand Summoner"] = {prio=1, mark=8, type="KILL", class=nil},
}

-- ==========================================================
-- DIRE MAUL
-- ==========================================================
TankMarkDefaults["Dire Maul"] = {
	-- North
	["King Gordok"] = {prio=1, mark=8, type="KILL", class=nil},
	["Cho'Rush the Observer"] = {prio=1, mark=8, type="KILL", class=nil},
	["Guard Mol'dar"] = {prio=2, mark=8, type="KILL", class=nil},
	
	-- East
	["Alzzin the Wildshaper"] = {prio=1, mark=8, type="KILL", class=nil},
	["Lethtendris"] = {prio=1, mark=8, type="KILL", class=nil},
	["Hydrospawn"] = {prio=1, mark=8, type="KILL", class=nil},
	["Zevrim Thornhoof"] = {prio=1, mark=8, type="KILL", class=nil},
	
	-- West
	["Prince Tortheldrin"] = {prio=1, mark=8, type="KILL", class=nil},
	["Immol'thar"] = {prio=1, mark=8, type="KILL", class=nil},
	["Tendris Warpwood"] = {prio=1, mark=8, type="KILL", class=nil},
	["Magister Kalendris"] = {prio=1, mark=8, type="KILL", class=nil},
}

-- ==========================================================
-- HELPER: Check if zone has defaults
-- ==========================================================
function TankMark:HasDefaultsForZone(zoneName)
	return (TankMarkDefaults[zoneName] ~= nil)
end

function TankMark:GetDefaultMobCount(zoneName)
	if not TankMarkDefaults[zoneName] then return 0 end
	
	local count = 0
	for _ in pairs(TankMarkDefaults[zoneName]) do
		count = count + 1
	end
	return count
end
