--[[
	Central tuning for "Become a Delivery Driver".

	Everything a designer would want to tweak - ranks, vehicles, payouts, timers,
	town size - lives here so balance changes never need code changes elsewhere.
]]

local Config = {}

Config.GameName = "Become a Delivery Driver"
Config.DataStoreName = "BecomeADeliveryDriver_v1"
Config.AutosaveInterval = 60

-- Town layout (studs). WorldBuilder derives everything else from these. --------
Config.World = {
	Blocks = 5, -- blocks per side (odd, so the depot can sit in the middle)
	BlockSize = 150,
	RoadWidth = 36,
	SidewalkWidth = 8,
	GroundMargin = 120, -- grass beyond the outer roads
	HousesPerRow = 3,
}

-- Late-afternoon lighting (applied by the server at startup and baked into the place).
Config.Lighting = {
	ClockTime = 16.2,
	Brightness = 2.6,
	GeographicLatitude = 35,
}

-- Gameplay rules ------------------------------------------------------------
Config.DeliveryRadius = 14 -- how close to the marker counts as "arrived"
Config.DeliveryMaxSpeed = 38 -- must be slower than this to hand over the package
Config.OrderFailGrace = 45 -- seconds past the deadline before the customer cancels
Config.SummonCooldown = 2.5
Config.MaxPlausibleSpeed = 170 -- anti-cheat: nobody legitimately beats this (studs/s)
Config.StartingCash = 0

-- Economy -------------------------------------------------------------------
Config.Economy = {
	BasePay = 18,
	PayPerStud = 0.11,
	TimeBase = 20, -- seconds of slack on every order
	TimeSpeedFactor = 0.62, -- fraction of top speed we assume the driver averages
	TimeBonusMax = 0.35, -- up to +35% for a fast run
	StreakStep = 0.05, -- +5% per consecutive on-time delivery
	StreakMax = 0.5,
	XPBase = 12,
	XPPerStud = 0.02,
	XPPerStar = 4,
	LateXPMult = 0.5,
	TipByStars = { [1] = 0, [2] = 0, [3] = 0.08, [4] = 0.15, [5] = 0.25 },
	-- stars from (time used / time limit)
	StarThresholds = { 0.55, 0.75, 1.0, 1.35 }, -- <= each of these gives 5,4,3,2 stars; above gives 1
}

-- Ranks: more XP unlocks longer, better-paying orders ---------------------------
Config.Ranks = {
	{ Name = "Rookie", XP = 0, PayMult = 1.00, MinDist = 140, MaxDist = 420 },
	{ Name = "Courier", XP = 120, PayMult = 1.10, MinDist = 160, MaxDist = 560 },
	{ Name = "Driver", XP = 350, PayMult = 1.22, MinDist = 200, MaxDist = 720 },
	{ Name = "Pro Driver", XP = 800, PayMult = 1.38, MinDist = 260, MaxDist = 900 },
	{ Name = "Elite Courier", XP = 1600, PayMult = 1.55, MinDist = 320, MaxDist = 1100 },
	{ Name = "Road Legend", XP = 3000, PayMult = 1.80, MinDist = 380, MaxDist = 1300 },
	{ Name = "Delivery Master", XP = 5500, PayMult = 2.10, MinDist = 450, MaxDist = 1500 },
}

-- What's in the box. Fragile/hot stuff gets less time but pays more. ---------------
Config.Packages = {
	{ Name = "Pizza", TimeMult = 0.85, PayMult = 1.15 },
	{ Name = "Groceries", TimeMult = 1.00, PayMult = 1.00 },
	{ Name = "Parcel", TimeMult = 1.10, PayMult = 0.95 },
	{ Name = "Flowers", TimeMult = 0.90, PayMult = 1.10 },
	{ Name = "Birthday Cake", TimeMult = 0.85, PayMult = 1.20 },
	{ Name = "Electronics", TimeMult = 1.00, PayMult = 1.25 },
	{ Name = "Hot Takeout", TimeMult = 0.80, PayMult = 1.15 },
	{ Name = "Medicine", TimeMult = 0.90, PayMult = 1.10 },
}

-- Vehicles ------------------------------------------------------------------
-- MaxSpeed: studs/s. Accel: studs/s^2. Turn: rad/s at low speed. Grip: how quickly
-- sideways slide is killed (higher = more planted, lower = driftier).
-- The 3D model for each Id is designed in VehicleBuilder.
Config.Vehicles = {
	{
		Id = "Scooter",
		Name = "Delivery Scooter",
		Description = "Zippy and free. Every legend starts here.",
		Price = 0,
		RankRequired = 1,
		MaxSpeed = 46,
		Accel = 32,
		Turn = 2.9,
		Grip = 7,
		PayBonus = 0,
	},
	{
		Id = "Hatchback",
		Name = "City Hatch",
		Description = "A proper little car. Quicker and sturdier than the scooter.",
		Price = 450,
		RankRequired = 1,
		MaxSpeed = 62,
		Accel = 40,
		Turn = 2.5,
		Grip = 5.5,
		PayBonus = 0,
	},
	{
		Id = "Van",
		Name = "Cargo Van",
		Description = "Room for more parcels: +10% on every payout.",
		Price = 1400,
		RankRequired = 2,
		MaxSpeed = 70,
		Accel = 36,
		Turn = 2.1,
		Grip = 4.8,
		PayBonus = 0.10,
	},
	{
		Id = "Roadster",
		Name = "Street Roadster",
		Description = "Open-top speed machine. Hold on tight.",
		Price = 3800,
		RankRequired = 4,
		MaxSpeed = 92,
		Accel = 55,
		Turn = 2.6,
		Grip = 4.2,
		PayBonus = 0,
	},
	{
		Id = "Hyper",
		Name = "Hyper Courier",
		Description = "The fastest thing on four wheels. Barely legal.",
		Price = 11000,
		RankRequired = 6,
		MaxSpeed = 118,
		Accel = 70,
		Turn = 2.4,
		Grip = 3.8,
		PayBonus = 0.05,
	},
}

Config.VehicleById = {}
for _, vehicle in Config.Vehicles do
	Config.VehicleById[vehicle.Id] = vehicle
end
Config.DefaultVehicle = Config.Vehicles[1].Id

-- Street names. Rows run east-west, columns run north-south. ---------------------
Config.StreetNames = { "Maple St", "Oak St", "Pine St", "Cedar St", "Elm St", "Birch St" }
Config.AvenueNames = { "1st Ave", "2nd Ave", "3rd Ave", "4th Ave", "5th Ave", "6th Ave" }

return Config
