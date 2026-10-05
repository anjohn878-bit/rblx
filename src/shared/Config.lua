-- Global tuning values for Grow a Bird Garden.
-- Tweak these to change the pace of the game.

local Config = {
	-- Economy
	StartingCoins = 20,
	StartingSeeds = { Sunflower = 3 },

	-- Growth speed multiplier. 1 = normal. Set to something like 20 while
	-- testing in Studio so plants bloom in seconds instead of minutes.
	GrowthSpeed = 1,

	-- Growth stages are reached at these fractions of the total grow time.
	SproutAt = 0.25,
	YoungPlantAt = 0.6,

	-- Seed shop
	RestockInterval = 300, -- seconds between shop restocks

	-- Birds
	BirdStayTime = 45, -- seconds a perched bird waits before flying off
	BirdFlightSpeed = 28, -- studs per second
	ShinyChance = 0.02, -- chance a visiting bird is a sparkly shiny
	ShinyMultiplier = 5, -- coin multiplier for befriending a shiny bird
	DiscoveryBonusMultiplier = 3, -- first time you befriend a species you get this many times the reward

	-- Saving
	DataStoreName = "BirdGarden_v1",
	AutosaveInterval = 120,

	-- Garden plots
	PlotCount = 6,
	PlotColumns = 4,
	PlotRows = 3,
	TileSize = 7,
	TileSpacing = 9,
}

return Config
