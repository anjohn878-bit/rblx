--!strict
local Types = require(script.Parent.Types)
type BirdDef = Types.BirdDef

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

-- Ordered by rarity so the Birdpedia reads like a field guide.
local list: { BirdDef } = {
	-- Common (Sunflower)
	{
		id = "sparrow",
		name = "House Sparrow",
		rarity = "Common",
		value = 3,
		scale = 0.9,
		blurb = "A cheerful little brown bird that can't resist sunflower seeds.",
		body = rgb(150, 111, 78),
		belly = rgb(214, 196, 170),
		wing = rgb(112, 80, 55),
		beak = rgb(120, 100, 80),
		accent = rgb(60, 45, 35),
		traits = { "Cap" },
	},
	{
		id = "goldfinch",
		name = "Goldfinch",
		rarity = "Common",
		value = 5,
		scale = 0.85,
		blurb = "Bright as a buttercup, and just as sweet.",
		body = rgb(255, 214, 52),
		belly = rgb(255, 236, 120),
		wing = rgb(40, 36, 34),
		beak = rgb(255, 150, 60),
		accent = rgb(30, 28, 28),
		traits = { "Cap" },
	},
	{
		id = "dove",
		name = "Mourning Dove",
		rarity = "Common",
		value = 8,
		scale = 1.1,
		blurb = "Soft, gentle and always a little sleepy.",
		body = rgb(176, 168, 170),
		belly = rgb(222, 206, 200),
		wing = rgb(140, 132, 136),
		beak = rgb(70, 70, 70),
		accent = rgb(60, 60, 70),
		traits = { "LongTail" },
	},

	-- Uncommon (Berry Bush)
	{
		id = "robin",
		name = "Robin",
		rarity = "Uncommon",
		value = 18,
		scale = 1.0,
		blurb = "The first bird of spring, with a warm orange chest.",
		body = rgb(110, 102, 98),
		belly = rgb(232, 120, 60),
		wing = rgb(84, 78, 76),
		beak = rgb(255, 200, 60),
		accent = rgb(40, 40, 40),
		traits = {},
	},
	{
		id = "chickadee",
		name = "Chickadee",
		rarity = "Uncommon",
		value = 26,
		scale = 0.8,
		blurb = "Tiny, fearless, and wearing a little black cap.",
		body = rgb(150, 160, 170),
		belly = rgb(240, 235, 225),
		wing = rgb(110, 120, 130),
		beak = rgb(30, 30, 30),
		accent = rgb(20, 20, 20),
		traits = { "Cap" },
	},
	{
		id = "bluebird",
		name = "Eastern Bluebird",
		rarity = "Uncommon",
		value = 36,
		scale = 1.0,
		blurb = "A flash of sky-blue that loves ripe berries.",
		body = rgb(70, 120, 220),
		belly = rgb(235, 150, 90),
		wing = rgb(50, 90, 200),
		beak = rgb(30, 30, 30),
		accent = rgb(255, 255, 255),
		traits = {},
	},

	-- Rare (Cherry Blossom)
	{
		id = "bluejay",
		name = "Blue Jay",
		rarity = "Rare",
		value = 110,
		scale = 1.25,
		blurb = "Loud, proud and crested. Rules the blossom tree.",
		body = rgb(70, 130, 230),
		belly = rgb(235, 240, 250),
		wing = rgb(40, 90, 200),
		beak = rgb(30, 30, 35),
		accent = rgb(30, 40, 90),
		traits = { "Crest" },
	},
	{
		id = "cardinal",
		name = "Cardinal",
		rarity = "Rare",
		value = 150,
		scale = 1.2,
		blurb = "A crimson jewel against the pink petals.",
		body = rgb(215, 40, 50),
		belly = rgb(225, 70, 70),
		wing = rgb(170, 25, 35),
		beak = rgb(255, 150, 60),
		accent = rgb(30, 20, 20),
		traits = { "Crest" },
	},
	{
		id = "oriole",
		name = "Baltimore Oriole",
		rarity = "Rare",
		value = 210,
		scale = 1.1,
		blurb = "Blazing orange, with a song like a flute.",
		body = rgb(255, 140, 20),
		belly = rgb(255, 170, 50),
		wing = rgb(30, 30, 30),
		beak = rgb(120, 120, 130),
		accent = rgb(20, 20, 20),
		traits = { "Cap" },
	},

	-- Epic (Hibiscus)
	{
		id = "hummingbird",
		name = "Ruby Hummingbird",
		rarity = "Epic",
		value = 520,
		scale = 0.7,
		blurb = "Wings too fast to see. Drawn to the biggest blooms.",
		body = rgb(40, 170, 110),
		belly = rgb(230, 230, 225),
		wing = rgb(200, 220, 230),
		beak = rgb(30, 30, 30),
		accent = rgb(240, 40, 80),
		traits = { "LongBeak", "Hover" },
	},
	{
		id = "parakeet",
		name = "Sunny Parakeet",
		rarity = "Epic",
		value = 720,
		scale = 1.0,
		blurb = "Chatters constantly about how nice the garden is.",
		body = rgb(110, 220, 70),
		belly = rgb(255, 235, 70),
		wing = rgb(60, 170, 60),
		beak = rgb(255, 170, 120),
		accent = rgb(60, 130, 240),
		traits = { "LongTail" },
	},
	{
		id = "kingfisher",
		name = "Kingfisher",
		rarity = "Epic",
		value = 1050,
		scale = 1.2,
		blurb = "A sharp-eyed jewel that arrives like a blue lightning bolt.",
		body = rgb(30, 140, 200),
		belly = rgb(255, 160, 60),
		wing = rgb(20, 100, 170),
		beak = rgb(30, 30, 40),
		accent = rgb(255, 255, 255),
		traits = { "Crest", "BigBeak" },
	},

	-- Legendary (Golden Apple Tree)
	{
		id = "toucan",
		name = "Toucan",
		rarity = "Legendary",
		value = 3000,
		scale = 1.7,
		blurb = "That beak is a lot, but it's also the point.",
		body = rgb(30, 30, 35),
		belly = rgb(255, 255, 255),
		wing = rgb(20, 20, 25),
		beak = rgb(255, 150, 20),
		accent = rgb(60, 180, 230),
		traits = { "BigBeak" },
	},
	{
		id = "macaw",
		name = "Scarlet Macaw",
		rarity = "Legendary",
		value = 4200,
		scale = 1.8,
		blurb = "A living rainbow with a tail like a comet.",
		body = rgb(230, 30, 30),
		belly = rgb(240, 60, 50),
		wing = rgb(50, 100, 230),
		beak = rgb(240, 235, 225),
		accent = rgb(255, 210, 40),
		traits = { "LongTail" },
	},
	{
		id = "peacock",
		name = "Peacock",
		rarity = "Legendary",
		value = 6400,
		scale = 1.9,
		blurb = "Only the golden tree is grand enough to deserve this display.",
		body = rgb(20, 110, 190),
		belly = rgb(30, 150, 170),
		wing = rgb(30, 140, 120),
		beak = rgb(200, 190, 150),
		accent = rgb(30, 170, 100),
		traits = { "FanTail", "Crest" },
	},

	-- Mythic (Starbloom)
	{
		id = "owl",
		name = "Aurora Owl",
		rarity = "Mythic",
		value = 22000,
		scale = 2.2,
		blurb = "Wakes only for starlight. Its feathers shimmer like the northern sky.",
		body = rgb(210, 225, 255),
		belly = rgb(245, 250, 255),
		wing = rgb(170, 190, 240),
		beak = rgb(255, 220, 120),
		accent = rgb(120, 255, 230),
		traits = { "OwlFace", "Glow" },
	},
	{
		id = "quetzal",
		name = "Celestial Quetzal",
		rarity = "Mythic",
		value = 31000,
		scale = 2.1,
		blurb = "The legendary spirit bird, trailing a tail of living emerald.",
		body = rgb(60, 230, 150),
		belly = rgb(255, 60, 90),
		wing = rgb(30, 180, 130),
		beak = rgb(255, 220, 60),
		accent = rgb(255, 255, 255),
		traits = { "Crest", "LongTail", "Glow" },
	},
	{
		id = "phoenix",
		name = "Phoenix",
		rarity = "Mythic",
		value = 48000,
		scale = 2.4,
		blurb = "Reborn in fire. Only the rarest bloom in the world calls it home.",
		body = rgb(255, 110, 20),
		belly = rgb(255, 200, 40),
		wing = rgb(255, 60, 20),
		beak = rgb(255, 230, 120),
		accent = rgb(255, 255, 180),
		traits = { "Crest", "LongTail", "Glow", "Fire" },
	},
}

local byId: { [string]: BirdDef } = {}
for _, bird in list do
	byId[bird.id] = bird
end

local Birds = {
	list = list,
}

function Birds.get(id: string): BirdDef?
	return byId[id]
end

function Birds.hasTrait(bird: BirdDef, trait: string): boolean
	return table.find(bird.traits, trait) ~= nil
end

return Birds
