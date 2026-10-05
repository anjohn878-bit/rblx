-- Game-wide tuning. Everything a designer is likely to tweak lives here.

local Config = {}

Config.GameName = "Become a Delivery Driver"
Config.CompanyName = "Speedy Parcel Co."
Config.CityName = "Parcelton"

Config.Colors = {
	Brand = Color3.fromRGB(255, 140, 26),
	BrandDark = Color3.fromRGB(204, 98, 0),
	Navy = Color3.fromRGB(22, 28, 45),
	NavyLight = Color3.fromRGB(38, 48, 74),
	White = Color3.fromRGB(245, 245, 245),
	Money = Color3.fromRGB(92, 220, 120),
	Danger = Color3.fromRGB(235, 80, 80),
	Muted = Color3.fromRGB(150, 160, 185),
}

-- The city is a square grid of blocks with roads between them. Keep BlocksPerSide odd so the
-- depot block sits exactly at the origin, where the place's SpawnLocation already is.
Config.City = {
	BlocksPerSide = 7,
	BlockSize = 130,
	RoadWidth = 32,
	SidewalkWidth = 6,
	LaneOffset = 8, -- distance from the road centre line to the middle of a lane
}
Config.City.CellSize = Config.City.BlockSize + Config.City.RoadWidth
-- Centre line of the outermost road, measured from the origin.
Config.City.Extent = (Config.City.BlocksPerSide / 2) * Config.City.CellSize

-- Ranks are earned by completed deliveries and boost every payout.
Config.Ranks = {
	{ Name = "Trainee", Deliveries = 0, PayMultiplier = 1.0, Color = Color3.fromRGB(190, 196, 210) },
	{ Name = "Delivery Driver", Deliveries = 5, PayMultiplier = 1.1, Color = Color3.fromRGB(255, 160, 60) },
	{ Name = "Senior Driver", Deliveries = 25, PayMultiplier = 1.25, Color = Color3.fromRGB(90, 170, 255) },
	{ Name = "Route Master", Deliveries = 75, PayMultiplier = 1.4, Color = Color3.fromRGB(100, 220, 130) },
	{ Name = "Express Expert", Deliveries = 150, PayMultiplier = 1.6, Color = Color3.fromRGB(190, 120, 255) },
	{ Name = "Logistics Legend", Deliveries = 300, PayMultiplier = 2.0, Color = Color3.fromRGB(255, 215, 70) },
}

export type VehicleInfo = {
	Id: string,
	Name: string,
	Description: string,
	Price: number,
	Rank: number, -- index into Config.Ranks needed to buy it
	TopSpeed: number, -- studs per second
	Acceleration: number, -- studs per second squared
	TurnRate: number, -- radians per second at full lock
	Capacity: number, -- packages per trip
}

Config.Vehicles = {
	{
		Id = "Bike",
		Name = "Delivery Bike",
		Description = "Every courier starts somewhere.",
		Price = 0,
		Rank = 1,
		TopSpeed = 34,
		Acceleration = 30,
		TurnRate = 2.6,
		Capacity = 1,
	},
	{
		Id = "Moped",
		Name = "City Moped",
		Description = "Zippy, cheap and fits two parcels.",
		Price = 400,
		Rank = 1,
		TopSpeed = 50,
		Acceleration = 34,
		TurnRate = 2.4,
		Capacity = 2,
	},
	{
		Id = "Hatchback",
		Name = "Compact Car",
		Description = "A proper car with a roomy boot.",
		Price = 1500,
		Rank = 2,
		TopSpeed = 62,
		Acceleration = 36,
		TurnRate = 2.1,
		Capacity = 3,
	},
	{
		Id = "Van",
		Name = "Delivery Van",
		Description = "The classic. Five parcels at a time.",
		Price = 5000,
		Rank = 3,
		TopSpeed = 68,
		Acceleration = 32,
		TurnRate = 1.9,
		Capacity = 5,
	},
	{
		Id = "Truck",
		Name = "Box Truck",
		Description = "Slow to turn, but carries a whole route.",
		Price = 15000,
		Rank = 4,
		TopSpeed = 62,
		Acceleration = 26,
		TurnRate = 1.6,
		Capacity = 8,
	},
	{
		Id = "Supercar",
		Name = "Express Supercar",
		Description = "Absolutely not company policy.",
		Price = 40000,
		Rank = 5,
		TopSpeed = 115,
		Acceleration = 60,
		TurnRate = 2.3,
		Capacity = 3,
	},
} :: { VehicleInfo }

export type PackageKind = {
	Id: string,
	Name: string,
	Weight: number, -- relative chance of being picked
	PayMultiplier: number,
	TimeMultiplier: number,
	Color: Color3,
}

Config.PackageKinds = {
	{
		Id = "Standard",
		Name = "Standard",
		Weight = 75,
		PayMultiplier = 1,
		TimeMultiplier = 1,
		Color = Color3.fromRGB(205, 160, 110),
	},
	{
		Id = "Express",
		Name = "Express",
		Weight = 20,
		PayMultiplier = 1.75,
		TimeMultiplier = 0.65,
		Color = Color3.fromRGB(255, 110, 70),
	},
	{
		Id = "VIP",
		Name = "VIP",
		Weight = 5,
		PayMultiplier = 3,
		TimeMultiplier = 0.85,
		Color = Color3.fromRGB(255, 210, 60),
	},
} :: { PackageKind }

Config.Economy = {
	StartingCash = 0,
	BasePay = 20,
	PayPerStud = 0.15, -- per stud of road distance from the depot
	FastBonus = 0.3, -- +30% when delivered before the timer runs out
	ParBaseSeconds = 30,
	ParSpeedFactor = 0.5, -- the timer assumes you average half your top speed
	ParPerExtraPackage = 20, -- extra seconds for each parcel already ahead of it in the load
	NewDriverDeliveries = 3, -- the first few jobs are short, standard ones
	NewDriverMaxDistance = 380,
	DeliverRadius = 14,
	-- Anti-teleport: nobody legitimately covers road distance faster than this (studs/second).
	MaxTravelSpeed = 160,
}

Config.VehicleSpawnCooldown = 4
Config.CollisionGroups = {
	-- Vehicles don't collide with characters: no ramming other players, and no getting flung
	-- when you hop out of a car.
	Vehicles = "DeliveryVehicles",
	Characters = "DeliveryCharacters",
}
Config.DayLengthMinutes = 12 -- real minutes for a full day/night cycle
Config.DataStoreName = "DeliveryDriver_v1"
Config.AutosaveSeconds = 90

function Config.getVehicle(id: string): VehicleInfo?
	for _, info in Config.Vehicles do
		if info.Id == id then
			return info
		end
	end
	return nil
end

function Config.getRankIndex(deliveries: number): number
	local index = 1
	for i, rank in Config.Ranks do
		if deliveries >= rank.Deliveries then
			index = i
		end
	end
	return index
end

-- Road distance between two points on the grid (roads only run north-south and east-west).
function Config.roadDistance(a: Vector3, b: Vector3): number
	return math.abs(a.X - b.X) + math.abs(a.Z - b.Z)
end

return Config
