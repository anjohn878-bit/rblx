--!strict
local Types = require(script.Parent.Types)
type SeedDef = Types.SeedDef

-- Better seeds take longer to grow, cost more, and attract rarer birds.
-- Each seed mostly draws birds of its own tier, with a ~3% chance of a bird
-- from the tier above (a "lucky visit").
local list: { SeedDef } = {
	{
		id = "sunflower",
		name = "Sunflower",
		rarity = "Common",
		tier = 1,
		price = 15,
		growTime = 20,
		blurb = "Quick to grow. Perfect for finches and sparrows.",
		color = Color3.fromRGB(255, 205, 40),
		labelHeight = 6.6,
		perches = { { 0, 5.1, -0.15 } },
		birds = {
			{ id = "sparrow", weight = 60 },
			{ id = "goldfinch", weight = 29 },
			{ id = "dove", weight = 10 },
			{ id = "robin", weight = 1 },
		},
		stock = { chance = 1, min = 6, max = 12 },
	},
	{
		id = "berrybush",
		name = "Berry Bush",
		rarity = "Uncommon",
		tier = 2,
		price = 140,
		growTime = 90,
		blurb = "Juicy berries bring the songbirds.",
		color = Color3.fromRGB(190, 40, 80),
		labelHeight = 3.4,
		perches = { { 0.3, 3.2, -0.4 } },
		birds = {
			{ id = "robin", weight = 55 },
			{ id = "chickadee", weight = 30 },
			{ id = "bluebird", weight = 12 },
			{ id = "bluejay", weight = 3 },
		},
		stock = { chance = 0.8, min = 2, max = 5 },
	},
	{
		id = "cherry",
		name = "Cherry Blossom",
		rarity = "Rare",
		tier = 3,
		price = 2100,
		growTime = 300,
		blurb = "A tree in full bloom. Two perches for two proud visitors.",
		color = Color3.fromRGB(255, 160, 190),
		labelHeight = 10.6,
		perches = { { 2.6, 9.55, 0.4 }, { -2.8, 9.05, 0.4 } },
		birds = {
			{ id = "bluejay", weight = 55 },
			{ id = "cardinal", weight = 30 },
			{ id = "oriole", weight = 12 },
			{ id = "hummingbird", weight = 3 },
		},
		stock = { chance = 0.5, min = 1, max = 3 },
	},
	{
		id = "hibiscus",
		name = "Hibiscus",
		rarity = "Epic",
		tier = 4,
		price = 13000,
		growTime = 900,
		blurb = "Enormous tropical flowers that hummingbirds dream about.",
		color = Color3.fromRGB(255, 70, 90),
		labelHeight = 7,
		perches = { { 0.4, 6.35, 0.1 }, { -2.3, 4.65, -0.3 } },
		birds = {
			{ id = "hummingbird", weight = 50 },
			{ id = "parakeet", weight = 30 },
			{ id = "kingfisher", weight = 17 },
			{ id = "toucan", weight = 3 },
		},
		stock = { chance = 0.25, min = 1, max = 2 },
	},
	{
		id = "goldenapple",
		name = "Golden Apple Tree",
		rarity = "Legendary",
		tier = 5,
		price = 140000,
		growTime = 2400,
		blurb = "A magnificent tree of golden fruit. Three perches for the grandest birds.",
		color = Color3.fromRGB(255, 200, 50),
		labelHeight = 15,
		perches = { { 0, 14.8, 0 }, { 3.4, 12.7, 0.8 }, { -3.5, 12.3, -0.6 } },
		birds = {
			{ id = "toucan", weight = 50 },
			{ id = "macaw", weight = 32 },
			{ id = "peacock", weight = 15 },
			{ id = "owl", weight = 3 },
		},
		stock = { chance = 0.1, min = 1, max = 1 },
	},
	{
		id = "starbloom",
		name = "Starbloom",
		rarity = "Mythic",
		tier = 6,
		price = 1050000,
		growTime = 7200,
		blurb = "A celestial tree that blooms with starlight. Mythic birds only.",
		color = Color3.fromRGB(180, 120, 255),
		labelHeight = 16.6,
		perches = { { 0, 15.55, 0 }, { 3.8, 12.65, 0 }, { -3.8, 12.65, 0 } },
		birds = {
			{ id = "owl", weight = 52 },
			{ id = "quetzal", weight = 32 },
			{ id = "phoenix", weight = 16 },
		},
		stock = { chance = 0.05, min = 1, max = 1 },
	},
}

local byId: { [string]: SeedDef } = {}
for _, seed in list do
	byId[seed.id] = seed
end

local Seeds = {
	list = list,
}

function Seeds.get(id: string): SeedDef?
	return byId[id]
end

function Seeds.isValid(id: any): boolean
	return typeof(id) == "string" and byId[id] ~= nil
end

return Seeds
