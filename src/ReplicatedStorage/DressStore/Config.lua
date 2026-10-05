-- Build a Dress Store: game settings shared by the server and the client.
-- Tweak prices, dresses and upgrades here.

local Config = {}

Config.GAME_NAME = "Build a Dress Store"

Config.STARTING_CASH = 100
Config.REBIRTH_BONUS = 0.5 -- every rebirth adds +50% to all money earned

Config.DATASTORE_NAME = "BuildADressStore_v1"
Config.AUTOSAVE_INTERVAL = 90

Config.PLOT_COUNT = 6
Config.FLOOR_Y = 0.6 -- height of the store floor surface above the ground

Config.Customer = {
	BASE_SPAWN_INTERVAL = 5, -- seconds between customers before any upgrades
	BASE_CAPACITY = 4, -- customers allowed in the store at once
	RACK_APPEAL = 0.15, -- every dress rack makes the store a bit more popular
	WALK_SPEED = 14,
	BROWSE_TIME_MIN = 1.5,
	BROWSE_TIME_MAX = 3,
	PATIENCE = 40, -- seconds a customer waits at the register before leaving
	CASHIER_SPEED = 1.5, -- seconds the hired cashier needs per customer
}

Config.Sewing = {
	HAND_HOLD_TIME = 0.6, -- seconds to hold E at the sewing table
	RACK_SLOTS = 4, -- dresses per rack
	NEW_RACK_STOCK = 2, -- dresses a rack comes with when it is built
}

-- Dresses are drawn from stacked cylinders ("tiers"): {height, diameter}
Config.Dresses = {
	{
		id = "Sundress",
		name = "Sundress",
		price = 20,
		color = Color3.fromRGB(255, 214, 79),
		accent = Color3.fromRGB(255, 255, 255),
		material = Enum.Material.Fabric,
		tiers = { { 0.55, 1.0 }, { 0.6, 1.3 } },
	},
	{
		id = "Floral",
		name = "Floral Dress",
		price = 50,
		color = Color3.fromRGB(255, 158, 196),
		accent = Color3.fromRGB(140, 220, 120),
		material = Enum.Material.Fabric,
		tiers = { { 0.55, 1.0 }, { 0.6, 1.25 }, { 0.6, 1.5 } },
	},
	{
		id = "Party",
		name = "Party Dress",
		price = 125,
		color = Color3.fromRGB(255, 60, 160),
		accent = Color3.fromRGB(30, 30, 30),
		material = Enum.Material.Foil,
		tiers = { { 0.5, 1.05 }, { 0.55, 1.45 } },
	},
	{
		id = "Evening",
		name = "Evening Gown",
		price = 300,
		color = Color3.fromRGB(112, 44, 175),
		accent = Color3.fromRGB(220, 220, 235),
		material = Enum.Material.Fabric,
		tiers = { { 0.7, 0.95 }, { 0.7, 1.05 }, { 0.7, 1.15 }, { 0.7, 1.3 } },
	},
	{
		id = "Ball",
		name = "Ball Gown",
		price = 750,
		color = Color3.fromRGB(120, 190, 255),
		accent = Color3.fromRGB(255, 255, 255),
		material = Enum.Material.Fabric,
		tiers = { { 0.6, 1.1 }, { 0.6, 1.4 }, { 0.6, 1.65 }, { 0.6, 1.85 } },
		sparkles = Color3.fromRGB(200, 230, 255),
	},
	{
		id = "Wedding",
		name = "Wedding Dress",
		price = 2000,
		color = Color3.fromRGB(252, 250, 245),
		accent = Color3.fromRGB(235, 215, 170),
		material = Enum.Material.Fabric,
		tiers = { { 0.6, 1.1 }, { 0.65, 1.45 }, { 0.65, 1.7 }, { 0.7, 1.9 } },
		sparkles = Color3.fromRGB(255, 255, 255),
	},
}

Config.DressById = {}
for _, dress in Config.Dresses do
	Config.DressById[dress.id] = dress
end

-- Everything the player can build, in unlock order.
-- requires: items that must be owned before this button shows up
-- appeal:   more customers (shorter time between customers)
-- capacity: more customers allowed inside at once
-- priceBonus: customers pay more for every dress
-- rack:     a dress rack (side -1 = left wall, 1 = right wall; z = position along the wall)
-- machine:  an automatic sewing machine (interval = seconds per dress)
Config.Items = {
	{ id = "starter", name = "Open Your Store", price = 0, requires = {}, info = "Floor + Sewing Table" },
	{ id = "register", name = "Cash Register", price = 25, requires = { "starter" }, info = "Customers can pay!" },
	{
		id = "rack1",
		name = "Sundress Rack",
		price = 40,
		requires = { "starter" },
		builder = "rack",
		rack = { dress = "Sundress", side = -1, z = -9 },
	},
	{
		id = "machine1",
		name = "Sewing Machine",
		price = 100,
		requires = { "rack1" },
		builder = "machine",
		machine = { interval = 5, x = -19.5 },
		info = "Sews a dress every 5s",
	},
	{
		id = "walls",
		name = "Walls & Windows",
		price = 200,
		requires = { "starter" },
		appeal = 0.2,
		capacity = 1,
		info = "+Customers",
	},
	{ id = "sign", name = "Shop Sign", price = 350, requires = { "walls" }, appeal = 0.4, info = "+Customers" },
	{
		id = "rack2",
		name = "Floral Dress Rack",
		price = 500,
		requires = { "machine1" },
		builder = "rack",
		rack = { dress = "Floral", side = 1, z = -9 },
	},
	{ id = "window", name = "Window Display", price = 750, requires = { "walls" }, appeal = 0.3, info = "+Customers" },
	{
		id = "fitting",
		name = "Fitting Rooms",
		price = 1000,
		requires = { "walls" },
		appeal = 0.3,
		capacity = 1,
		info = "+Customers",
	},
	{
		id = "cashier",
		name = "Hire a Cashier",
		price = 1400,
		requires = { "register", "rack2" },
		info = "Auto checkout!",
	},
	{
		id = "rack3",
		name = "Party Dress Rack",
		price = 2000,
		requires = { "rack2" },
		builder = "rack",
		rack = { dress = "Party", side = -1, z = 0 },
	},
	{ id = "roof", name = "Roof & Lights", price = 2500, requires = { "sign" }, appeal = 0.1, info = "+Customers" },
	{
		id = "machine2",
		name = "Sewing Machine 2",
		price = 3200,
		requires = { "rack3" },
		builder = "machine",
		machine = { interval = 4, x = -14 },
		info = "Sews a dress every 4s",
	},
	{
		id = "lights",
		name = "Sparkly Chandeliers",
		price = 4200,
		requires = { "roof" },
		appeal = 0.4,
		info = "+Customers",
	},
	{
		id = "sofas",
		name = "Comfy Sofas",
		price = 5000,
		requires = { "fitting" },
		appeal = 0.2,
		capacity = 1,
		info = "+Customers",
	},
	{
		id = "rack4",
		name = "Evening Gown Rack",
		price = 6500,
		requires = { "rack3" },
		builder = "rack",
		rack = { dress = "Evening", side = 1, z = 0 },
	},
	{
		id = "handbags",
		name = "Designer Handbags",
		price = 9000,
		requires = { "rack4" },
		priceBonus = 0.25,
		info = "+25% dress prices",
	},
	{
		id = "runway",
		name = "Fashion Runway",
		price = 12000,
		requires = { "sofas" },
		appeal = 0.6,
		capacity = 1,
		info = "++Customers",
	},
	{
		id = "machine3",
		name = "Sewing Machine 3",
		price = 16000,
		requires = { "machine2", "rack4" },
		builder = "machine",
		machine = { interval = 3, x = -8.5 },
		info = "Sews a dress every 3s",
	},
	{
		id = "rack5",
		name = "Ball Gown Rack",
		price = 22000,
		requires = { "rack4" },
		builder = "rack",
		rack = { dress = "Ball", side = -1, z = 9 },
	},
	{
		id = "fountain",
		name = "Garden Fountain",
		price = 30000,
		requires = { "runway" },
		appeal = 0.5,
		capacity = 1,
		info = "++Customers",
	},
	{
		id = "rack6",
		name = "Wedding Dress Rack",
		price = 42000,
		requires = { "rack5" },
		builder = "rack",
		rack = { dress = "Wedding", side = 1, z = 9 },
	},
	{
		id = "statue",
		name = "Golden Dress Statue",
		price = 65000,
		requires = { "rack6" },
		appeal = 0.5,
		priceBonus = 0.5,
		info = "+50% dress prices",
	},
}

Config.ItemById = {}
for index, item in Config.Items do
	item.order = index
	Config.ItemById[item.id] = item
	if item.rack then
		-- "Sells Sundresses ($20 each)"
		local dress = Config.DressById[item.rack.dress]
		local plural = if string.sub(dress.name, -1) == "s" then dress.name .. "es" else dress.name .. "s"
		item.info = "Sells " .. plural .. " ($" .. dress.price .. " each)"
	end
end

return Config
