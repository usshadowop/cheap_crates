--[[
	Cheap Crates - crate database (World of Warcraft: Forever, patch 1.60.1)

	Every Waylaid Crate, the bundles that fill it, and the Merchant's Favor a sealed crate pays.
	A crate is filled with ANY ONE bundle from its list (the whole quantity in one stack); the
	filled crate becomes a bind-on-pickup "Sealed ... Crate" that is handed in at the Azeroth
	Commerce Authority (Marcy Baker, Three Corners, Redridge) or Durotar Supply and Logistics
	(Dokimi, west of the Crossroads, the Barrens) for Merchant's Favor (currency 3402).

	Sources (WoW Forever pages only): crate item IDs and bundles from Method's Forever crate guide,
	cross-checked by name on wowhead.com/forever; bundles also match ForeverChanges and
	The Forever Guides; Favor amounts from outof.games, wowforever.gg and ForeverChanges.

	Unconfirmed at the time of writing, so they can be overridden in game (/crates favor ...):
	  * Artisan Favor (20 raw / 40 crafted is the expected value, nobody has reported it yet).
	  * Journeyman Textiles: one guide saw the crate take 40 Medium Leather, not 20.
	  * Journeyman Parts: "45 Gold Power Core" is how every source lists it.
	The addon reads each fill item's stack size from the game and flags bundles that cannot fit
	in one stack (a reported crate quirk), so those never end up in a plan by accident.
]]

local _, ns = ...

ns.CURRENCY_ID = 3402 -- Merchant's Favor

ns.TIER_ORDER = { Apprentice = 1, Journeyman = 2, Expert = 3, Artisan = 4 }

-- Herbs, Ore, Textiles and Curiosities are raw ("gathered") goods; Fabrics, Ingots and Parts are crafted.
ns.CRAFTED = { Fabrics = true, Ingots = true, Parts = true }

-- Merchant's Favor per sealed crate. [tier] = { gathered, crafted }
ns.DEFAULT_FAVOR = {
	Apprentice = { gathered = 5, crafted = 10 },
	Journeyman = { gathered = 10, crafted = 20 },
	Expert = { gathered = 15, crafted = 30 },
	Artisan = { gathered = 20, crafted = 40 },
}
-- tiers whose Favor has not been reported by players yet (shown as "est." in the UI)
ns.FAVOR_ESTIMATED = { Artisan = true }

-- Fallback names (the game's own name is used once the item is cached).
ns.ITEM_NAMES = {
	-- ore
	[2770] = "Copper Ore", [2771] = "Tin Ore", [2775] = "Silver Ore", [2772] = "Iron Ore",
	[2776] = "Gold Ore", [3858] = "Mithril Ore", [7911] = "Truesilver Ore", [10620] = "Thorium Ore",
	[11099] = "Dark Iron Ore",
	-- bars
	[2840] = "Copper Bar", [3576] = "Tin Bar", [2841] = "Bronze Bar", [2842] = "Silver Bar",
	[3575] = "Iron Bar", [3860] = "Mithril Bar", [3859] = "Steel Bar", [3577] = "Gold Bar",
	[11371] = "Dark Iron Bar", [6037] = "Truesilver Bar", [12359] = "Thorium Bar",
	-- herbs
	[2447] = "Peacebloom", [765] = "Silverleaf", [2449] = "Earthroot", [785] = "Mageroyal",
	[2450] = "Briarthorn", [3820] = "Stranglekelp", [2453] = "Bruiseweed", [3355] = "Wild Steelbloom",
	[3369] = "Grave Moss", [3356] = "Kingsblood", [3357] = "Liferoot", [3818] = "Fadeleaf",
	[3821] = "Goldthorn", [3358] = "Khadgar's Whisker", [3819] = "Wintersbite", [4625] = "Firebloom",
	[8831] = "Purple Lotus", [8836] = "Arthas' Tears", [13464] = "Golden Sansam", [8838] = "Sungrass",
	[8839] = "Blindweed", [8845] = "Ghost Mushroom", [8846] = "Gromsblood", [13463] = "Dreamfoil",
	[13465] = "Mountain Silversage", [13466] = "Plaguebloom", [13467] = "Icecap",
	-- engineering parts
	[4359] = "Handful of Copper Bolts", [4361] = "Copper Tube", [4363] = "Copper Modulator",
	[4371] = "Bronze Tube", [4375] = "Whirring Bronze Gizmo", [4382] = "Bronze Framework",
	[10558] = "Gold Power Core", [4387] = "Iron Strut", [10559] = "Mithril Tube",
	[10560] = "Unstable Trigger", [10561] = "Mithril Casing", [15994] = "Thorium Widget",
	[18631] = "Truesilver Transformer", [16000] = "Thorium Tube",
	-- cloth and leather
	[2589] = "Linen Cloth", [2318] = "Light Leather", [2592] = "Wool Cloth", [4306] = "Silk Cloth",
	[2319] = "Medium Leather", [4338] = "Mageweave Cloth", [4234] = "Heavy Leather",
	[14047] = "Runecloth", [4304] = "Thick Leather", [8170] = "Rugged Leather",
	-- bolts and cured hides
	[2996] = "Bolt of Linen Cloth", [4231] = "Cured Light Hide", [2997] = "Bolt of Woolen Cloth",
	[4305] = "Bolt of Silk Cloth", [4233] = "Cured Medium Hide", [4339] = "Bolt of Mageweave",
	[4236] = "Cured Heavy Hide", [14048] = "Bolt of Runecloth", [8172] = "Cured Thick Hide",
	-- enchanting
	[10940] = "Strange Dust", [10939] = "Greater Magic Essence", [10978] = "Small Glimmering Shard",
	[11084] = "Large Glimmering Shard", [11083] = "Soul Dust", [11082] = "Greater Astral Essence",
	[11138] = "Small Glowing Shard", [11139] = "Large Glowing Shard", [11137] = "Vision Dust",
	[11135] = "Greater Mystic Essence", [11177] = "Small Radiant Shard", [11178] = "Large Radiant Shard",
	[11176] = "Dream Dust", [11175] = "Greater Nether Essence", [14343] = "Small Brilliant Shard",
	[14344] = "Large Brilliant Shard",
}

-- fills = { { itemID, quantity }, ... }  (any ONE of them fills the crate)
ns.CRATES = {
	-- Herbs (raw)
	{ id = 248682, name = "Waylaid Crate: Apprentice Herbs", tier = "Apprentice", cat = "Herbs", level = 10,
		fills = { { 2447, 20 }, { 765, 20 }, { 2449, 10 }, { 785, 10 }, { 2450, 10 } } },
	{ id = 248686, name = "Waylaid Crate: Journeyman Herbs", tier = "Journeyman", cat = "Herbs", level = 10,
		fills = { { 3820, 10 }, { 2453, 10 }, { 3355, 10 }, { 3369, 10 }, { 3356, 10 } } },
	{ id = 248690, name = "Waylaid Crate: Earthly Expert Herbs", tier = "Expert", cat = "Herbs", level = 20,
		fills = { { 3357, 20 }, { 3818, 10 }, { 3821, 10 }, { 3358, 10 } } },
	{ id = 248691, name = "Waylaid Crate: Flowering Expert Herbs", tier = "Expert", cat = "Herbs", level = 20,
		fills = { { 3819, 10 }, { 4625, 10 }, { 8831, 20 }, { 8836, 10 } } },
	{ id = 248695, name = "Waylaid Crate: Earthly Artisan Herbs", tier = "Artisan", cat = "Herbs", level = 35,
		fills = { { 13464, 10 }, { 8838, 20 }, { 8839, 10 }, { 8845, 10 }, { 8846, 10 } } },
	{ id = 248696, name = "Waylaid Crate: Flowering Artisan Herbs", tier = "Artisan", cat = "Herbs", level = 35,
		fills = { { 13463, 20 }, { 13465, 20 }, { 13466, 20 }, { 13467, 20 } } },

	-- Ore (raw)
	{ id = 248683, name = "Waylaid Crate: Apprentice Ore", tier = "Apprentice", cat = "Ore", level = 10,
		fills = { { 2770, 20 }, { 2771, 20 } } },
	{ id = 248687, name = "Waylaid Crate: Journeyman Ore", tier = "Journeyman", cat = "Ore", level = 10,
		fills = { { 2775, 10 }, { 2772, 20 } } },
	{ id = 248692, name = "Waylaid Crate: Expert Ore", tier = "Expert", cat = "Ore", level = 20,
		fills = { { 2776, 10 }, { 3858, 20 } } },
	{ id = 248697, name = "Waylaid Crate: Artisan Ore", tier = "Artisan", cat = "Ore", level = 35,
		fills = { { 7911, 10 }, { 10620, 20 }, { 11099, 20 } } },

	-- Textiles (raw)
	{ id = 248684, name = "Waylaid Crate: Apprentice Textiles", tier = "Apprentice", cat = "Textiles", level = 10,
		fills = { { 2589, 40 }, { 2318, 20 } } },
	{ id = 248688, name = "Waylaid Crate: Journeyman Textiles", tier = "Journeyman", cat = "Textiles", level = 10,
		fills = { { 2592, 20 }, { 4306, 40 }, { 2319, 20 } } },
	{ id = 248693, name = "Waylaid Crate: Expert Textiles", tier = "Expert", cat = "Textiles", level = 20,
		fills = { { 4338, 40 }, { 4234, 20 } } },
	{ id = 248698, name = "Waylaid Crate: Artisan Textiles", tier = "Artisan", cat = "Textiles", level = 35,
		fills = { { 14047, 40 }, { 4304, 20 }, { 8170, 20 } } },

	-- Curiosities (raw)
	{ id = 248685, name = "Waylaid Crate: Apprentice Curiosities", tier = "Apprentice", cat = "Curiosities", level = 10,
		fills = { { 10940, 20 }, { 10939, 4 }, { 10978, 6 }, { 11084, 2 } } },
	{ id = 248689, name = "Waylaid Crate: Journeyman Curiosities", tier = "Journeyman", cat = "Curiosities", level = 10,
		fills = { { 11083, 20 }, { 11082, 4 }, { 11138, 6 }, { 11139, 2 } } },
	{ id = 248694, name = "Waylaid Crate: Expert Curiosities", tier = "Expert", cat = "Curiosities", level = 20,
		fills = { { 11137, 20 }, { 11135, 4 }, { 11177, 6 }, { 11178, 2 } } },
	{ id = 248699, name = "Waylaid Crate: Artisan Curiosities", tier = "Artisan", cat = "Curiosities", level = 35,
		fills = { { 11176, 20 }, { 11175, 4 }, { 14343, 6 }, { 14344, 2 } } },

	-- Fabrics (crafted)
	{ id = 248702, name = "Waylaid Crate: Apprentice Fabrics", tier = "Apprentice", cat = "Fabrics", level = 10,
		fills = { { 4231, 2 }, { 2996, 20 } } },
	{ id = 248705, name = "Waylaid Crate: Journeyman Fabrics", tier = "Journeyman", cat = "Fabrics", level = 10,
		fills = { { 2997, 6 }, { 4305, 10 }, { 4233, 2 } } },
	{ id = 248708, name = "Waylaid Crate: Expert Fabrics", tier = "Expert", cat = "Fabrics", level = 20,
		fills = { { 4339, 8 }, { 4236, 2 } } },
	{ id = 248711, name = "Waylaid Crate: Artisan Fabrics", tier = "Artisan", cat = "Fabrics", level = 35,
		fills = { { 14048, 8 }, { 8172, 2 } } },

	-- Ingots (crafted)
	{ id = 248703, name = "Waylaid Crate: Apprentice Ingots", tier = "Apprentice", cat = "Ingots", level = 10,
		fills = { { 2840, 20 }, { 3576, 20 }, { 2841, 10 } } },
	{ id = 248706, name = "Waylaid Crate: Journeyman Ingots", tier = "Journeyman", cat = "Ingots", level = 10,
		fills = { { 2842, 10 }, { 3575, 20 } } },
	{ id = 248709, name = "Waylaid Crate: Expert Ingots", tier = "Expert", cat = "Ingots", level = 20,
		fills = { { 3860, 20 }, { 3859, 15 }, { 3577, 10 } } },
	{ id = 248712, name = "Waylaid Crate: Artisan Ingots", tier = "Artisan", cat = "Ingots", level = 35,
		fills = { { 11371, 2 }, { 6037, 10 }, { 12359, 20 } } },

	-- Parts (crafted)
	{ id = 248704, name = "Waylaid Crate: Apprentice Parts", tier = "Apprentice", cat = "Parts", level = 10,
		fills = { { 4359, 16 }, { 4361, 16 }, { 4363, 4 } } },
	{ id = 248707, name = "Waylaid Crate: Journeyman Parts", tier = "Journeyman", cat = "Parts", level = 10,
		fills = { { 4371, 8 }, { 4375, 7 }, { 4382, 4 }, { 10558, 45 } } },
	{ id = 248710, name = "Waylaid Crate: Expert Parts", tier = "Expert", cat = "Parts", level = 20,
		fills = { { 4387, 8 }, { 10559, 5 }, { 10560, 12 }, { 10561, 5 } } },
	{ id = 248713, name = "Waylaid Crate: Artisan Parts", tier = "Artisan", cat = "Parts", level = 35,
		fills = { { 15994, 5 }, { 18631, 5 }, { 16000, 2 } } },
}

-- lookups built once
ns.CRATE_BY_ID = {}
ns.FILL_OWNER = {}    -- fill itemID -> list of crates that take it
ns.ALL_ITEMS = {}     -- every itemID the scan prices: crates first, then fill items
for _, c in ipairs(ns.CRATES) do
	c.kind = ns.CRAFTED[c.cat] and "crafted" or "gathered"
	c.short = c.name:gsub("^Waylaid Crate: ", "")
	ns.CRATE_BY_ID[c.id] = c
	ns.ITEM_NAMES[c.id] = c.name
	ns.ALL_ITEMS[#ns.ALL_ITEMS + 1] = c.id
end
local seen = {}
for _, c in ipairs(ns.CRATES) do
	for i, f in ipairs(c.fills) do
		local id = f[1]
		c.fills[i] = { item = id, qty = f[2] }
		ns.FILL_OWNER[id] = ns.FILL_OWNER[id] or {}
		table.insert(ns.FILL_OWNER[id], c)
		if not seen[id] then
			seen[id] = true
			ns.ALL_ITEMS[#ns.ALL_ITEMS + 1] = id
		end
	end
end
