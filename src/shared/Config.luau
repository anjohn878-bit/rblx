--!strict
-- Every tunable number in the game lives here.

local Config = {
	GAME_NAME = "Grow a Bird Garden",

	-- Progression
	START_FEATHERS = 30,
	START_SEEDS = { sunflower = 3 } :: { [string]: number },
	START_PLOTS = 4,
	MAX_PLOTS = 12,
	-- Price of plot #5, #6, #7 ... (plots unlock in order)
	PLOT_PRICES = { 150, 450, 1200, 3500, 10000, 30000, 90000, 250000 } :: { number },

	-- Garden layout
	MAX_GARDENS = 8,
	PLOT_COLUMNS = 4,
	PLOT_ROWS = 3,

	-- Seed shop restocks on a fixed global clock so every server agrees
	RESTOCK_INTERVAL = 180,
	MAX_BUY_AMOUNT = 25,

	-- Plants
	SCALE_MIN = 0.22, -- size of a freshly planted seed relative to full size

	-- Bird visits (one independent "perch slot" per perch on a plant)
	TICK = 0.25,
	VISIT = {
		FIRST_WAIT_MIN = 3, -- delay before the first bird once a plant blooms
		FIRST_WAIT_MAX = 7,
		WAIT_MIN = 8, -- delay between birds on the same perch
		WAIT_MAX = 18,
		STAY_MIN = 10,
		STAY_MAX = 16,
		ARRIVE = 4.5, -- fly-in time; feathers are paid when the bird lands
		LEAVE = 3.5,
	},
	DISCOVERY_MULTIPLIER = 5, -- first time you see a species: value x this, once

	AUTOSAVE_INTERVAL = 60,
	DATASTORE_NAME = "GrowABirdGarden_v1",
}

Config.RARITY_ORDER = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic" }

Config.RARITY_COLORS = {
	Common = Color3.fromRGB(196, 200, 204),
	Uncommon = Color3.fromRGB(98, 214, 104),
	Rare = Color3.fromRGB(84, 160, 255),
	Epic = Color3.fromRGB(180, 104, 255),
	Legendary = Color3.fromRGB(255, 184, 48),
	Mythic = Color3.fromRGB(255, 92, 158),
} :: { [string]: Color3 }

return Config
