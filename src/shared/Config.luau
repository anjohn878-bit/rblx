--[[
	Config
	Every tunable number in Ice Skating Simulator lives here: skates, upgrades,
	rinks, trick scoring and the economy. Shared by the server and the client,
	and also read by the build script when it bakes the map into the place file.
]]

local Config = {}

Config.GameName = "Ice Skating Simulator"
Config.CurrencyName = "Snowflakes"
Config.CurrencyIcon = "❄"

Config.DataStoreName = "IceSkatingSimulator_PlayerData_v1"
Config.LeaderboardStoreName = "IceSkatingSimulator_Lifetime_v1"
Config.AutosaveInterval = 120
Config.LeaderboardRefreshInterval = 60

-- Movement on the ice. Speeds are in studs/second.
Config.Skating = {
	BaseJumpHeight = 7.2,
	GlideFriction = 0.22, -- fraction of speed bled off per second while coasting
	AirFriction = 0.02,
	BrakeDeceleration = 85, -- pushing against your direction of travel = hockey stop
	TurnRate = 3.4, -- radians/second you can carve at speed
	InstantTurnSpeed = 4, -- below this speed you turn on the spot
	OverspeedDeceleration = 40, -- how fast you slow down when above your max speed
	ForcePerMass = 10000, -- strength of the skating constraint
	MaxAirTime = 4, -- stop skating if airborne for longer than this
}

Config.Skates = {
	{
		Id = "Rental",
		Name = "Rental Skates",
		Price = 0,
		MaxSpeed = 30,
		Acceleration = 18,
		EarnMultiplier = 1,
		BladeColor = Color3.fromRGB(165, 170, 180),
		BootColor = Color3.fromRGB(90, 95, 110),
		TrailColor = Color3.fromRGB(235, 245, 255),
	},
	{
		Id = "Hockey",
		Name = "Hockey Skates",
		Price = 350,
		MaxSpeed = 38,
		Acceleration = 24,
		EarnMultiplier = 1.5,
		BladeColor = Color3.fromRGB(200, 205, 215),
		BootColor = Color3.fromRGB(30, 30, 35),
		TrailColor = Color3.fromRGB(200, 225, 255),
	},
	{
		Id = "Figure",
		Name = "Figure Skates",
		Price = 2500,
		MaxSpeed = 46,
		Acceleration = 30,
		EarnMultiplier = 2.25,
		BladeColor = Color3.fromRGB(220, 225, 235),
		BootColor = Color3.fromRGB(250, 250, 250),
		TrailColor = Color3.fromRGB(255, 190, 230),
	},
	{
		Id = "Speed",
		Name = "Speed Skates",
		Price = 20000,
		MaxSpeed = 56,
		Acceleration = 38,
		EarnMultiplier = 3.5,
		BladeColor = Color3.fromRGB(230, 235, 245),
		BootColor = Color3.fromRGB(220, 40, 50),
		TrailColor = Color3.fromRGB(255, 120, 90),
	},
	{
		Id = "Golden",
		Name = "Golden Skates",
		Price = 150000,
		MaxSpeed = 66,
		Acceleration = 46,
		EarnMultiplier = 5.5,
		BladeColor = Color3.fromRGB(255, 205, 70),
		BootColor = Color3.fromRGB(255, 225, 120),
		TrailColor = Color3.fromRGB(255, 215, 90),
		Glow = true,
	},
	{
		Id = "Diamond",
		Name = "Diamond Skates",
		Price = 1200000,
		MaxSpeed = 78,
		Acceleration = 56,
		EarnMultiplier = 9,
		BladeColor = Color3.fromRGB(160, 240, 255),
		BootColor = Color3.fromRGB(110, 210, 255),
		TrailColor = Color3.fromRGB(120, 235, 255),
		Glow = true,
	},
	{
		Id = "Aurora",
		Name = "Aurora Skates",
		Price = 10000000,
		MaxSpeed = 92,
		Acceleration = 68,
		EarnMultiplier = 15,
		BladeColor = Color3.fromRGB(140, 255, 200),
		BootColor = Color3.fromRGB(150, 90, 255),
		TrailColor = Color3.fromRGB(120, 255, 190),
		Glow = true,
	},
}

-- Cost of the next level is BaseCost * CostGrowth ^ currentLevel.
Config.Upgrades = {
	{
		Id = "Speed",
		Name = "Leg Power",
		Icon = "💨",
		Description = "+2.5% top speed and acceleration per level",
		MaxLevel = 25,
		BaseCost = 150,
		CostGrowth = 1.5,
		PerLevel = 0.025,
	},
	{
		Id = "Jump",
		Name = "Spring Jumps",
		Icon = "🦘",
		Description = "Jump higher to land more rotations",
		MaxLevel = 20,
		BaseCost = 200,
		CostGrowth = 1.55,
		PerLevel = 1.1, -- studs of jump height per level
	},
	{
		Id = "Style",
		Name = "Showmanship",
		Icon = "⭐",
		Description = "+15% snowflakes from tricks per level",
		MaxLevel = 25,
		BaseCost = 250,
		CostGrowth = 1.5,
		PerLevel = 0.15,
	},
}

Config.Lobby = {
	Center = Vector3.new(0, 0, 0),
	PlazaRadius = 55,
}

-- Each rink is laid out so its entrance faces the lobby. Size is (width, length).
Config.Rinks = {
	{
		Id = "Pond",
		Name = "Frozen Pond",
		Price = 0,
		Multiplier = 1,
		Center = Vector3.new(0, 0, -160),
		Size = Vector2.new(170, 120),
		Collectibles = 3,
		Theme = "Pond",
		IceColor = Color3.fromRGB(205, 232, 255),
		BoardColor = Color3.fromRGB(245, 248, 255),
		BoardMaterial = Enum.Material.Snow,
		BoardHeight = 3.5,
		RailColor = Color3.fromRGB(150, 105, 70),
		AccentColor = Color3.fromRGB(110, 185, 255),
	},
	{
		Id = "PineLake",
		Name = "Pine Lake",
		Price = 3000,
		Multiplier = 2,
		Center = Vector3.new(230, 0, 0),
		Size = Vector2.new(180, 230),
		Collectibles = 4,
		Theme = "Forest",
		IceColor = Color3.fromRGB(190, 225, 245),
		BoardColor = Color3.fromRGB(120, 80, 50),
		BoardMaterial = Enum.Material.WoodPlanks,
		BoardHeight = 4,
		RailColor = Color3.fromRGB(245, 248, 255),
		AccentColor = Color3.fromRGB(90, 200, 120),
	},
	{
		Id = "GlacierBay",
		Name = "Glacier Bay",
		Price = 60000,
		Multiplier = 4,
		Center = Vector3.new(-270, 0, 0),
		Size = Vector2.new(220, 280),
		Collectibles = 5,
		Theme = "Glacier",
		IceColor = Color3.fromRGB(170, 220, 250),
		BoardColor = Color3.fromRGB(150, 215, 245),
		BoardMaterial = Enum.Material.Glacier,
		BoardHeight = 4,
		RailColor = Color3.fromRGB(235, 250, 255),
		AccentColor = Color3.fromRGB(60, 220, 255),
	},
	{
		Id = "AuroraArena",
		Name = "Aurora Arena",
		Price = 1500000,
		Multiplier = 8,
		Center = Vector3.new(0, 0, 320),
		Size = Vector2.new(280, 340),
		Collectibles = 6,
		Theme = "Arena",
		IceColor = Color3.fromRGB(225, 235, 255),
		BoardColor = Color3.fromRGB(245, 245, 250),
		BoardMaterial = Enum.Material.SmoothPlastic,
		BoardHeight = 4,
		RailColor = Color3.fromRGB(170, 90, 255),
		AccentColor = Color3.fromRGB(170, 90, 255),
	},
}

Config.Tricks = {
	-- Purely cosmetic: a random jump name is picked each time you take off.
	JumpTypes = { "Axel", "Lutz", "Flip", "Salchow", "Loop", "Toe Loop" },
	Rotations = {
		{ Prefix = "Single", Points = 10 },
		{ Prefix = "Double", Points = 40 },
		{ Prefix = "Triple", Points = 120 },
		{ Prefix = "Quad", Points = 350 },
		{ Prefix = "Quint", Points = 1000 },
	},
	-- A rotation counts once you are this close to completing it (0.3 = 70% of the way round).
	RotationForgiveness = 0.3,
	BaseAirSpinRate = math.pi * 3.2, -- radians/second while airborne
	AirSpinRatePerSpeed = 0.12, -- extra radians/second for each stud/second of speed at takeoff
	MinJumpSpeed = 10, -- you need some speed to launch a real jump
	MinJumpInterval = 0.5,
	ComboWindow = 4, -- seconds to land the next trick before the combo resets
	ComboStep = 0.2,
	MaxComboMultiplier = 3,
	Spin = {
		Name = "Scratch Spin",
		Points = 15,
		Duration = 1.5,
		StartRate = math.pi * 4,
		EndRate = math.pi * 10,
		Cooldown = 0.4,
		SpeedDecay = 2.5,
	},
}

Config.Economy = {
	SnowflakesPerStud = 0.25,
	GoldenSnowflakeValue = 25,
	GoldenSnowflakeRespawn = 6,
	CollectRadius = 6,
}

Config.Rebirth = {
	BaseCost = 1000000,
	CostGrowth = 3,
	MultiplierPerRebirth = 0.5,
}

Config.Server = {
	SkateTickInterval = 0.2,
	ProfileSyncInterval = 0.25,
}

return Config
