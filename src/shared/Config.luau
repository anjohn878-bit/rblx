--[[
	Config
	Central tuning for the whole game. Server and client both read this module.
	Change numbers here instead of hunting through systems.
]]

local Config = {}

Config.GameName = "CONCRETE KINGS"
Config.CurrencyName = "Kicks"
Config.DataStoreName = "ConcreteKings_PlayerData_v1"

-------------------------------------------------------------------------------
-- Controls (single place to rebind everything)
-- Each action lists keyboard/mouse inputs, gamepad inputs and whether a touch
-- button should be created on mobile.
-------------------------------------------------------------------------------
Config.Controls = {
	Sprint = {
		Keyboard = { Enum.KeyCode.LeftShift },
		Gamepad = { Enum.KeyCode.ButtonR2 },
		Touch = true,
		TouchTitle = "Sprint",
	},
	Pass = {
		Keyboard = { Enum.UserInputType.MouseButton1 },
		Gamepad = { Enum.KeyCode.ButtonA },
		Touch = true,
		TouchTitle = "Pass",
	},
	Shoot = {
		-- Hold to charge, release to shoot
		Keyboard = { Enum.UserInputType.MouseButton2 },
		Gamepad = { Enum.KeyCode.ButtonB },
		Touch = true,
		TouchTitle = "Shoot",
	},
	ThroughBall = {
		Keyboard = { Enum.KeyCode.F },
		Gamepad = { Enum.KeyCode.ButtonY },
		Touch = true,
		TouchTitle = "Through",
	},
	Lob = {
		-- Space lobs when you have the ball, otherwise it is a normal jump
		Keyboard = { Enum.KeyCode.Space },
		Gamepad = { Enum.KeyCode.ButtonX },
		Touch = true,
		TouchTitle = "Lob",
	},
	Tackle = {
		Keyboard = { Enum.KeyCode.E },
		Gamepad = { Enum.KeyCode.ButtonL2 },
		Touch = true,
		TouchTitle = "Tackle",
	},
	SkillMove = {
		Keyboard = { Enum.KeyCode.Q },
		Gamepad = { Enum.KeyCode.ButtonL1 },
		Touch = true,
		TouchTitle = "Skill",
	},
	CameraMode = {
		Keyboard = { Enum.KeyCode.C },
		Gamepad = { Enum.KeyCode.ButtonR3 },
		Touch = false,
	},
	Menu = {
		Keyboard = { Enum.KeyCode.M },
		Gamepad = { Enum.KeyCode.ButtonSelect },
		Touch = false,
	},
}

-------------------------------------------------------------------------------
-- Movement
-------------------------------------------------------------------------------
Config.Movement = {
	BaseWalkSpeed = 16,
	BaseSprintSpeed = 23,
	PaceWalkBonus = 2, -- extra walk speed at 99 pace
	PaceSprintBonus = 3, -- extra sprint speed at 99 pace
	DribbleSpeedMultiplier = 0.92,
	SprintRampTime = 0.35, -- seconds to reach full sprint speed
	StaminaMax = 100,
	StaminaDrainPerSecond = 16,
	StaminaRegenPerSecond = 12,
	StaminaRegenDelay = 0.8,
	StaminaAttributeBonus = 0.5, -- up to +50% drain efficiency at 99 stamina
}

-------------------------------------------------------------------------------
-- Ball
-------------------------------------------------------------------------------
Config.Ball = {
	Size = 2.2,
	Density = 0.35,
	Friction = 0.35,
	Elasticity = 0.55,
	GravityScale = 0.5, -- custom ball gravity, lower feels floatier
	GroundDrag = 0.9, -- horizontal velocity decay per second while rolling
	AirDrag = 0.12,
	ControlRadius = 3.4, -- horizontal distance from root part to take the ball
	ControlHeight = 5, -- max height above the pitch to take the ball
	KickerCooldown = 0.45, -- seconds before a kicker can retake their own kick
	TackledCooldown = 0.9,
	DribbleDistance = 2.7, -- studs in front of the player
	DribbleStiffness = 14,
	MaxDribbleLeash = 9, -- server resets possession if the ball is further than this
	HardTouchSpeed = 70, -- above this, first touch can fail and deflect
}

Config.Kick = {
	PassMinSpeed = 42,
	PassMaxSpeed = 85,
	PassLift = 3,
	PassAssistAngle = 40, -- degrees; teammates inside this cone get targeted
	ThroughLeadTime = 0.9,
	LobFlightTime = 1.05,
	LobMaxRange = 80,
	ShotMinSpeed = 68,
	ShotMaxSpeed = 118,
	ShotMinLift = 12,
	ShotMaxLift = 40,
	ShotAssistAngle = 45,
	ShotMaxErrorDegrees = 7, -- at 0 shooting, scales down with attribute
	MaxChargeTime = 0.9,
	RateLimit = 0.2,
	ReachRadius = 4.5, -- one-touch kicks allowed on a free ball this close
}

Config.Tackle = {
	Range = 6.5,
	Cooldown = 1.2,
	BaseSuccess = 0.62,
	AttributeSwing = 0.35, -- (defending - dribbling)/99 * swing
	FailSlowTime = 0.6,
	EvadeWindow = 0.5, -- seconds of tackle immunity after a skill move
}

Config.SkillMove = {
	Cooldown = 0.9,
	DashSpeed = 34,
	DashTime = 0.18,
}

-------------------------------------------------------------------------------
-- Matches
-------------------------------------------------------------------------------
Config.Match = {
	TeamSize = 3,
	DurationSeconds = 240,
	MatchFoundSeconds = 4, -- "MATCH FOUND" then "TEAM A vs TEAM B"
	KickoffCountdown = 3,
	GoalCelebrationSeconds = 4,
	ResultsSeconds = 9,
	MinHumansToStart = 1,
	FillWithBots = true, -- empty slots are filled by Ground Regulars (bots)
	BotFillDelay = 8, -- seconds the queue waits for humans before adding bots
	MercyGoalDifference = 7,
}

-- Pitch layout. Length runs along X. Team A defends the -X goal and attacks +X.
-- SurfaceY is the height of the playing surface.
Config.Pitches = {
	{
		Id = "Pitch1",
		DisplayName = "THE CAGE",
		Area = "CommunityCourt",
		Center = Vector3.new(0, 0, 0),
		SurfaceY = 0.4,
		Length = 112,
		Width = 64,
		GoalWidth = 16,
		GoalHeight = 8,
		GoalDepth = 5,
		WallHeight = 12,
		ColliderHeight = 60,
		QueuePad = Vector3.new(0, 0, 52), -- relative to Center
	},
}

Config.Hub = {
	Spawn = Vector3.new(0, 1, 92),
	PracticeArea = Vector3.new(118, 0, 10),
	Locker = Vector3.new(-110, 0, 60),
	-- Locked teaser gates for the next areas (world progression)
	AreaGates = {
		{ Area = "StreetCourt", Name = "STREET COURT", RequiredTier = "Local", Position = Vector3.new(0, 0, -120) },
		{ Area = "UrbanArena", Name = "URBAN ARENA", RequiredTier = "Skilled", Position = Vector3.new(-150, 0, -40) },
	},
}

Config.Teams = {
	A = { Name = "VOLT", Color = Color3.fromRGB(205, 255, 64), Dark = Color3.fromRGB(40, 52, 12) },
	B = { Name = "EMBER", Color = Color3.fromRGB(255, 110, 54), Dark = Color3.fromRGB(58, 22, 10) },
}

-- Reward formula inputs (server only uses these, client shows them)
Config.Rewards = {
	XP = { Played = 60, Win = 80, Draw = 35, Goal = 30, Assist = 20, Pass = 3, Tackle = 8, SkillMove = 2, CapPerMatch = 600 },
	Kicks = { Played = 25, Win = 40, Draw = 15, Goal = 10, Assist = 6, CapPerMatch = 200 },
	Reputation = { Played = 2, Win = 10, Draw = 5, Goal = 2, Assist = 1 },
	LevelUpKicks = 50,
}

Config.Attributes = {
	List = { "Pace", "Shooting", "Passing", "Dribbling", "BallControl", "Defending", "Physicality", "Stamina" },
	Start = 50,
	Max = 99,
	PointsPerLevel = 2,
}

Config.DataStore = {
	AutosaveInterval = 90,
	SessionLockTimeout = 600, -- seconds before a lock from a dead server is considered stale
	LoadRetries = 6,
	SaveRetries = 4,
}

return Config
