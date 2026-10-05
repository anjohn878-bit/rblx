-- Global tuning values for Grow a Bird Garden.
-- Tweak these to change the pace of the game.

local Config = {
	-- Economy
	StartingCoins = 20,
	StartingSeeds = { Sunflower = 3 },

	-- Speed multiplier for all the waiting: plants growing, eggs hatching and
	-- babies growing up. 1 = normal. Set to something like 20 while testing in
	-- Studio so things happen in seconds instead of minutes.
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
	ShinyMultiplier = 5, -- shiny birds are worth this many times more
	DiscoveryBonusMultiplier = 3, -- first time you befriend a species you get its value times this in coins

	-- Pets (befriended birds)
	MaxPets = 60, -- how many birds fit in your aviary
	MaxEquippedPets = 6, -- how many can roam your garden (and give perks) at once
	WildStarWeights = { 50, 35, 15 }, -- chance of a wild bird having 1, 2 or 3 stars
	SeedFinderInterval = 60, -- seconds between seed finder rolls

	-- Breeding
	NestCount = 2,
	BredStarUpChance = 0.35, -- chance a baby gets one more star than its parents
	BredShinyChance = { 0.02, 0.15, 0.5 }, -- with 0, 1 or 2 shiny parents

	-- Trading
	TradeMaxPets = 8, -- pets each side can offer
	TradeCountdown = 3, -- seconds after both players are ready
	TradeRequestTimeout = 30,
	TradeRequestCooldown = 5,

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
