-- Shared tuning values for Become a Delivery Driver
local Config = {}

Config.BasePay = 25
Config.PayPerStud = 0.35
Config.SpeedBonusMax = 40 -- extra cash for fast deliveries
Config.TimeLimitBase = 45 -- seconds
Config.TimePerStud = 0.12
Config.StartCash = 0

Config.Ranks = {
	{ name = "Rookie", deliveries = 0 },
	{ name = "Courier", deliveries = 5 },
	{ name = "Driver", deliveries = 20 },
	{ name = "Pro Driver", deliveries = 50 },
	{ name = "Road Warrior", deliveries = 100 },
	{ name = "Delivery Legend", deliveries = 250 },
}

-- Each tier of a car stat costs more. Index = tier (0 = stock).
Config.Cars = {
	{ id = "Scooter", name = "Delivery Scooter", price = 0, speed = 40, torque = 6, color = Color3.fromRGB(255, 170, 0) },
	{ id = "Hatchback", name = "Hatchback", price = 500, speed = 60, torque = 9, color = Color3.fromRGB(80, 170, 255) },
	{ id = "Van", name = "Delivery Van", price = 2000, speed = 75, torque = 12, color = Color3.fromRGB(240, 240, 240) },
	{ id = "Sports", name = "Sports Car", price = 7500, speed = 105, torque = 16, color = Color3.fromRGB(230, 40, 40) },
	{ id = "Hyper", name = "Hyper Car", price = 25000, speed = 140, torque = 22, color = Color3.fromRGB(170, 60, 255) },
}

function Config.getRank(deliveries: number): string
	local rank = Config.Ranks[1].name
	for _, r in Config.Ranks do
		if deliveries >= r.deliveries then
			rank = r.name
		end
	end
	return rank
end

return Config
