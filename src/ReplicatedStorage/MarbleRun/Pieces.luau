-- Track piece definitions plus the geometry builder shared by the server (real pieces)
-- and the client (ghost previews).
--
-- Conventions (piece local space):
--   * A piece fills one grid cell, centred on the origin, spanning x/z in [-CELL/2, CELL/2].
--   * Marbles enter through the +Z edge travelling toward -Z.
--   * y = 0 is the floor height at the exit; the entry floor is `drop` levels higher.
--   * A piece placed at `level` therefore has its exit floor at level * LEVEL_HEIGHT, and the
--     piece feeding into it must exit at (level + drop).

local Config = require(script.Parent.Config)

local CELL = Config.CELL
local LH = Config.LEVEL_HEIGHT
local HALF = CELL / 2
local W = Config.TRACK_WIDTH
local FT = Config.FLOOR_THICKNESS
local RH = Config.RAIL_HEIGHT
local RT = Config.RAIL_THICKNESS

export type PieceDef = {
	id: string,
	name: string,
	description: string,
	price: number,
	drop: number,
	exit: string?, -- "straight" | "left" | "right" | nil (no exit)
	color: Color3,
	spanBelow: number, -- studs below the exit floor the geometry reaches
	spanAbove: number, -- studs above the entry floor the geometry reaches
	maxPerPlot: number?,
}

local Pieces = {}

Pieces.Defs = {
	Straight = {
		id = "Straight",
		name = "Ramp",
		description = "A gentle downhill ramp.",
		price = 5,
		drop = 1,
		exit = "straight",
		color = Color3.fromRGB(80, 160, 255),
		spanBelow = FT,
		spanAbove = RH,
	},
	CurveLeft = {
		id = "CurveLeft",
		name = "Curve L",
		description = "Turns the marble left.",
		price = 8,
		drop = 1,
		exit = "left",
		color = Color3.fromRGB(255, 170, 60),
		spanBelow = FT,
		spanAbove = RH,
	},
	CurveRight = {
		id = "CurveRight",
		name = "Curve R",
		description = "Turns the marble right.",
		price = 8,
		drop = 1,
		exit = "right",
		color = Color3.fromRGB(255, 120, 60),
		spanBelow = FT,
		spanAbove = RH,
	},
	Steep = {
		id = "Steep",
		name = "Steep",
		description = "A steep drop of 4 levels. Fast!",
		price = 10,
		drop = 4,
		exit = "straight",
		color = Color3.fromRGB(230, 70, 90),
		spanBelow = FT,
		spanAbove = RH,
	},
	Flat = {
		id = "Flat",
		name = "Flat",
		description = "Level track. Keeps the marble at the same height.",
		price = 4,
		drop = 0,
		exit = "straight",
		color = Color3.fromRGB(150, 150, 165),
		spanBelow = FT,
		spanAbove = RH,
	},
	Booster = {
		id = "Booster",
		name = "Booster",
		description = "Flat track that launches the marble forward.",
		price = 25,
		drop = 0,
		exit = "straight",
		color = Color3.fromRGB(60, 220, 120),
		spanBelow = FT,
		spanAbove = RH,
	},
	Chime = {
		id = "Chime",
		name = "Chime",
		description = "Rings a bell and earns bonus coins.",
		price = 15,
		drop = 1,
		exit = "straight",
		color = Color3.fromRGB(190, 110, 255),
		spanBelow = FT,
		spanAbove = 5.5,
	},
	Goal = {
		id = "Goal",
		name = "Goal",
		description = "The finish cup. Marbles that land here pay out!",
		price = 0,
		drop = 1,
		exit = nil,
		color = Color3.fromRGB(255, 215, 0),
		spanBelow = 2.6,
		spanAbove = 6,
		maxPerPlot = 1,
	},
} :: { [string]: PieceDef }

-- Display order for the hotbar.
Pieces.Order = { "Straight", "CurveLeft", "CurveRight", "Steep", "Flat", "Booster", "Chime", "Goal" }

---------------------------------------------------------------------------
-- Grid math
---------------------------------------------------------------------------

function Pieces.rotationCFrame(rot: number): CFrame
	return CFrame.Angles(0, rot * math.pi / 2, 0)
end

-- Rotates a local direction into (axis aligned) plot space and snaps it to integers.
function Pieces.rotateDir(dir: Vector3, rot: number): Vector2
	local v = Pieces.rotationCFrame(rot):VectorToWorldSpace(dir)
	return Vector2.new(math.round(v.X), math.round(v.Z))
end

function Pieces.cellCenter(origin: Vector3, cx: number, cz: number): Vector3
	return origin + Vector3.new((cx + 0.5) * CELL, 0, (cz + 0.5) * CELL)
end

function Pieces.pieceCFrame(origin: Vector3, cx: number, cz: number, level: number, rot: number): CFrame
	local c = Pieces.cellCenter(origin, cx, cz)
	return CFrame.new(c.X, origin.Y + level * LH, c.Z) * Pieces.rotationCFrame(rot)
end

-- Direction of travel (in cell steps) when a marble enters a piece with this rotation.
function Pieces.entryDir(rot: number): Vector2
	return Pieces.rotateDir(Vector3.new(0, 0, -1), rot)
end

local EXIT_LOCAL = {
	straight = Vector3.new(0, 0, -1),
	left = Vector3.new(-1, 0, 0),
	right = Vector3.new(1, 0, 0),
}

-- Returns the direction the marble leaves the piece (in cell steps) and the level of the exit floor.
function Pieces.exitInfo(pieceType: string, rot: number, level: number): (Vector2?, number)
	local def = Pieces.Defs[pieceType]
	if not def or not def.exit then
		return nil, level
	end
	return Pieces.rotateDir(EXIT_LOCAL[def.exit], rot), level
end

-- Vertical extent in studs relative to the plot floor.
function Pieces.verticalSpan(pieceType: string, level: number): (number, number)
	local def = Pieces.Defs[pieceType]
	return level * LH - def.spanBelow, (level + def.drop) * LH + def.spanAbove
end

---------------------------------------------------------------------------
-- Geometry
---------------------------------------------------------------------------

local function newPart(model: Model, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = model
	return p
end

local function newSensor(model: Model, name: string, size: Vector3, cf: CFrame): Part
	local p = newPart(model, name, size, cf, Color3.new(1, 1, 1), Enum.Material.SmoothPlastic)
	p.Transparency = 1
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = true
	return p
end

-- Builds a floor plank whose top surface runs from a to b (local space).
local function plank(model: Model, a: Vector3, b: Vector3, width: number, extra: number, color: Color3)
	local mid = (a + b) / 2
	local len = (b - a).Magnitude + extra
	local cf = CFrame.lookAt(mid, b)
	cf = cf * CFrame.new(0, -FT / 2, 0)
	local p = newPart(model, "Floor", Vector3.new(width, FT, len), cf, color, Enum.Material.SmoothPlastic)
	p.CustomPhysicalProperties = PhysicalProperties.new(1, 0.25, 0.1, 1, 1)
end

-- Builds a rail whose bottom runs from a to b (local space, floor height).
local function rail(model: Model, a: Vector3, b: Vector3, extra: number)
	local mid = (a + b) / 2
	local len = (b - a).Magnitude + extra
	local cf = CFrame.lookAt(mid, b) * CFrame.new(0, RH / 2 - FT, 0)
	local p = newPart(model, "Rail", Vector3.new(RT, RH + FT, len), cf, Color3.fromRGB(220, 240, 255), Enum.Material.Glass)
	p.Transparency = 0.45
	p.CustomPhysicalProperties = PhysicalProperties.new(1, 0.1, 0.2, 1, 1)
end

-- Builds a railed track along a polyline of floor points.
local function track(model: Model, path: { Vector3 }, color: Color3, extra: number)
	local n = #path
	local offset = W / 2 + RT / 2
	local left, right = {}, {}
	for i = 1, n do
		local prev = path[math.max(i - 1, 1)]
		local nxt = path[math.min(i + 1, n)]
		local t = Vector3.new(nxt.X - prev.X, 0, nxt.Z - prev.Z).Unit
		local r = Vector3.new(-t.Z, 0, t.X)
		left[i] = path[i] - r * offset
		right[i] = path[i] + r * offset
	end
	for i = 1, n - 1 do
		plank(model, path[i], path[i + 1], W + RT * 2, extra, color)
		rail(model, left[i], left[i + 1], extra)
		rail(model, right[i], right[i + 1], extra)
	end
end

local function straightPath(drop: number, zStart: number?, zEnd: number?): { Vector3 }
	return { Vector3.new(0, drop * LH, zStart or HALF), Vector3.new(0, 0, zEnd or -HALF) }
end

local function curvePath(drop: number, side: number): { Vector3 }
	local segments = 8
	local path = {}
	for i = 0, segments do
		local a = (i / segments) * math.pi / 2
		local x = side * (HALF - HALF * math.cos(a))
		local z = HALF - HALF * math.sin(a)
		local y = drop * LH * (1 - i / segments)
		table.insert(path, Vector3.new(x, y, z))
	end
	return path
end

local function arrow(model: Model, z: number, color: Color3)
	for _, side in { -1, 1 } do
		local cf = CFrame.new(side * 0.55, 0.01, z) * CFrame.Angles(0, side * math.rad(40), 0)
		local p = newPart(model, "Arrow", Vector3.new(0.35, 0.05, 1.6), cf, color, Enum.Material.Neon)
		p.CanCollide = false
		p.CanQuery = false
	end
end

local builders: { [string]: (Model, PieceDef) -> () } = {}

builders.Straight = function(model, def)
	track(model, straightPath(def.drop), def.color, 0.15)
end

builders.Flat = builders.Straight
builders.Steep = builders.Straight

builders.CurveLeft = function(model, def)
	track(model, curvePath(def.drop, -1), def.color, 0.5)
end

builders.CurveRight = function(model, def)
	track(model, curvePath(def.drop, 1), def.color, 0.5)
end

builders.Booster = function(model, def)
	track(model, straightPath(0), Color3.fromRGB(40, 45, 55), 0.15)
	for _, z in { 2, -0.5, -3 } do
		arrow(model, z, def.color)
	end
	newSensor(model, "BoostPad", Vector3.new(W, 2, CELL - 1), CFrame.new(0, 1, 0))
end

builders.Chime = function(model, def)
	track(model, straightPath(def.drop), def.color, 0.15)
	local archColor = Color3.fromRGB(240, 230, 255)
	local top = def.drop * LH + 5
	for _, side in { -1, 1 } do
		newPart(model, "Arch", Vector3.new(0.4, top, 0.4), CFrame.new(side * (W / 2 + 0.8), top / 2 - FT, 0), archColor, Enum.Material.Metal)
	end
	newPart(model, "Arch", Vector3.new(W + 2, 0.4, 0.4), CFrame.new(0, top - FT, 0), archColor, Enum.Material.Metal)
	local bell = newPart(model, "Bell", Vector3.new(1.4, 1.4, 1.4), CFrame.new(0, top - FT - 0.9, 0), Color3.fromRGB(255, 205, 60), Enum.Material.Metal)
	bell.Shape = Enum.PartType.Ball
	bell.CanCollide = false
	newSensor(model, "Chime", Vector3.new(W, 2, 2), CFrame.new(0, def.drop * LH / 2 + 1, 0))
end

builders.Goal = function(model, def)
	-- Short lead-in ramp that tips the marble into the cup.
	track(model, straightPath(def.drop, HALF, 1.5), def.color, 0.1)
	local cupColor = Color3.fromRGB(255, 225, 90)
	local glass = Color3.fromRGB(255, 245, 200)
	local cupZ = -1.25
	newPart(model, "CupFloor", Vector3.new(7.6, 0.4, 6), CFrame.new(0, -2.4, cupZ), cupColor, Enum.Material.SmoothPlastic)
	local back = newPart(model, "CupWall", Vector3.new(7.6, 4.2, 0.3), CFrame.new(0, -0.4, -HALF + 0.15), glass, Enum.Material.Glass)
	back.Transparency = 0.4
	for _, side in { -1, 1 } do
		local wall = newPart(model, "CupWall", Vector3.new(0.3, 4.2, 6), CFrame.new(side * 3.65, -0.4, cupZ), glass, Enum.Material.Glass)
		wall.Transparency = 0.4
	end
	newPart(model, "CupLip", Vector3.new(7.6, 2.2, 0.3), CFrame.new(0, -1.5, 1.6), cupColor, Enum.Material.SmoothPlastic)
	-- Flag
	newPart(model, "FlagPole", Vector3.new(0.3, 7, 0.3), CFrame.new(3.4, 1.3, -3.6), Color3.fromRGB(230, 230, 230), Enum.Material.Metal)
	newPart(model, "Flag", Vector3.new(0.1, 1.6, 2.4), CFrame.new(3.4, 4, -2.3), Color3.fromRGB(255, 60, 60), Enum.Material.SmoothPlastic).CanCollide = false
	local sensor = newSensor(model, "GoalSensor", Vector3.new(6.8, 1.6, 5.2), CFrame.new(0, -1.4, cupZ))
	local confetti = Instance.new("ParticleEmitter")
	confetti.Name = "Confetti"
	confetti.Enabled = false
	confetti.Rate = 0
	confetti.Lifetime = NumberRange.new(1, 2)
	confetti.Speed = NumberRange.new(25, 40)
	confetti.SpreadAngle = Vector2.new(35, 35)
	confetti.Acceleration = Vector3.new(0, -40, 0)
	confetti.Size = NumberSequence.new(0.4)
	confetti.Rotation = NumberRange.new(0, 360)
	confetti.RotSpeed = NumberRange.new(-200, 200)
	confetti.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 80, 80)),
		ColorSequenceKeypoint.new(0.33, Color3.fromRGB(255, 220, 60)),
		ColorSequenceKeypoint.new(0.66, Color3.fromRGB(80, 200, 255)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(150, 255, 120)),
	})
	confetti.EmissionDirection = Enum.NormalId.Top
	confetti.Parent = sensor
end

-- Builds a piece model (unparented) positioned at `cf` (see pieceCFrame).
function Pieces.Build(pieceType: string, cf: CFrame): Model
	local def = Pieces.Defs[pieceType]
	assert(def, "Unknown piece type " .. tostring(pieceType))
	local model = Instance.new("Model")
	model.Name = pieceType
	builders[pieceType](model, def)
	-- Parts were built in local space around the origin; move them into place.
	model.WorldPivot = CFrame.new()
	model:PivotTo(cf)
	return model
end

-- Builds the start tower that lives in START_CELL. Returns the model and the CFrame
-- where new marbles should spawn.
function Pieces.BuildStartTower(origin: Vector3): (Model, CFrame)
	local level = Config.START_LEVEL
	local cx, cz = Config.START_CELL.X, Config.START_CELL.Y
	local model = Instance.new("Model")
	model.Name = "StartTower"
	local chuteCf = Pieces.pieceCFrame(origin, cx, cz, level, Config.START_ROT)
	local chute = Instance.new("Model")
	chute.Name = "Chute"
	track(chute, straightPath(2), Color3.fromRGB(255, 255, 255), 0.15)
	-- Back stop so marbles can't roll out of the hopper.
	newPart(chute, "BackStop", Vector3.new(W + 1, RH + 3, 0.4), CFrame.new(0, 2 * LH + 1, HALF), Color3.fromRGB(255, 255, 255), Enum.Material.SmoothPlastic)
	chute.WorldPivot = CFrame.new()
	chute:PivotTo(chuteCf)
	chute.Parent = model

	local base = Pieces.cellCenter(origin, cx, cz)
	local height = level * LH
	newPart(model, "Column", Vector3.new(3, height, 3), CFrame.new(base.X, origin.Y + height / 2, base.Z), Color3.fromRGB(70, 75, 90), Enum.Material.Concrete)
	local stripe = newPart(model, "Stripe", Vector3.new(3.2, 1, 3.2), CFrame.new(base.X, origin.Y + height - 1.5, base.Z), Color3.fromRGB(255, 200, 0), Enum.Material.Neon)
	stripe.CanCollide = false

	local spawnCf = chuteCf * CFrame.new(0, 2 * LH + Config.MARBLE_SIZE / 2 + 0.3, HALF - 1.5)
	return model, spawnCf
end

return Pieces
