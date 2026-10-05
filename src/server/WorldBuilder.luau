--[[
	Generates the town: a grid of roads and blocks full of houses, with the delivery depot in the
	middle block. Everything is built from Parts, and the layout is deterministic.

	The place file ships with the town already baked into Workspace.Town (tools/build.luau runs
	this module), so it is visible in Studio's edit view. At runtime Main only calls build() if the
	town is missing (e.g. when the scripts are synced into an empty place with Rojo).

	World coordinates: origin at the centre of the town, ground surface at y = 0.1.
	Rows (z) are east-west roads, columns (x) are north-south roads.

	WorldBuilder.info(town) reads back what the game services need (houses, prompts, spawn).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)

local WorldBuilder = {}

local SURFACE_Y = 0.1 -- top of roads, sidewalks and lawns (everything is flush so cars never bump)
local THICKNESS = 0.2

-- Palette -----------------------------------------------------------------------
local ASPHALT = Color3.fromRGB(58, 60, 66)
local LINE_YELLOW = Color3.fromRGB(255, 206, 60)
local SIDEWALK = Color3.fromRGB(190, 190, 196)
local GRASS = Color3.fromRGB(96, 150, 78)
local GRASS_OUTER = Color3.fromRGB(84, 134, 68)
local LOT = Color3.fromRGB(112, 116, 126)
local NAVY = Color3.fromRGB(26, 34, 64)
local NAVY_LIGHT = Color3.fromRGB(40, 54, 98)
local ORANGE = Color3.fromRGB(255, 159, 28)
local CREAM = Color3.fromRGB(250, 244, 228)
local GLASS = Color3.fromRGB(150, 205, 235)

local WALL_COLORS = {
	Color3.fromRGB(236, 216, 186),
	Color3.fromRGB(214, 230, 236),
	Color3.fromRGB(240, 202, 202),
	Color3.fromRGB(208, 228, 202),
	Color3.fromRGB(246, 236, 184),
	Color3.fromRGB(202, 208, 238),
	Color3.fromRGB(236, 208, 228),
	Color3.fromRGB(226, 226, 230),
}
local ROOF_COLORS = {
	Color3.fromRGB(120, 60, 54),
	Color3.fromRGB(70, 74, 88),
	Color3.fromRGB(96, 76, 60),
	Color3.fromRGB(58, 90, 110),
	Color3.fromRGB(110, 110, 118),
}
local DOOR_COLORS = {
	Color3.fromRGB(150, 60, 50),
	Color3.fromRGB(56, 96, 140),
	Color3.fromRGB(70, 120, 80),
	Color3.fromRGB(230, 170, 60),
	Color3.fromRGB(90, 70, 60),
}

-- Deterministic RNG (so the baked town and a runtime-built town are identical) -------
local function makeRng(seed: number)
	local state = seed % 4294967296
	local function nextFloat(): number
		state = (state * 1664525 + 1013904223) % 4294967296
		return state / 4294967296
	end
	return {
		float = nextFloat,
		range = function(a: number, b: number): number
			return a + (b - a) * nextFloat()
		end,
		int = function(a: number, b: number): number
			return a + math.floor(nextFloat() * (b - a + 1))
		end,
		pick = function(list)
			return list[math.floor(nextFloat() * #list) + 1]
		end,
	}
end

-- Part helpers ------------------------------------------------------------------

local function addPart(
	parent: Instance,
	name: string,
	size: Vector3,
	position: Vector3,
	color: Color3,
	material: Enum.Material?,
	extra: { [string]: any }?
): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanTouch = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Size = size
	part.CFrame = CFrame.new(position)
	part.Color = color
	part.Material = material or Enum.Material.SmoothPlastic
	if extra then
		for property, value in extra do
			(part :: any)[property] = value
		end
	end
	part.Parent = parent
	return part
end

-- Flat slab whose top face sits at SURFACE_Y.
local function addSlab(
	parent: Instance,
	name: string,
	centerX: number,
	centerZ: number,
	sizeX: number,
	sizeZ: number,
	color: Color3,
	material: Enum.Material?
): Part
	return addPart(parent, name, Vector3.new(sizeX, THICKNESS, sizeZ), Vector3.new(centerX, SURFACE_Y - THICKNESS / 2, centerZ), color, material)
end

local function addText(part: Part, face: Enum.NormalId, text: string, textColor: Color3, backColor: Color3?, pixelsPerStud: number?)
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = pixelsPerStud or 50
	gui.LightInfluence = 0
	gui.Parent = part

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = backColor and 0 or 1
	if backColor then
		label.BackgroundColor3 = backColor
	end
	label.Text = text
	label.TextColor3 = textColor
	label.TextScaled = true
	label.FontFace = Font.fromEnum(Enum.Font.GothamBold) -- FontFace (not Font) so the label can be saved into the place file
	label.Parent = gui
end

local function addFolder(parent: Instance, name: string): Folder
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	return folder
end

-- Geometry ---------------------------------------------------------------------

local function geometry()
	local w = Config.World
	local pitch = w.BlockSize + w.RoadWidth
	local span = w.Blocks * pitch + w.RoadWidth
	return {
		N = w.Blocks,
		Block = w.BlockSize,
		Road = w.RoadWidth,
		Sidewalk = w.SidewalkWidth,
		Pitch = pitch,
		Span = span,
		Ground = span + w.GroundMargin * 2,
		-- centre of block row/column i (1-based)
		BlockCenter = function(i: number): number
			return (i - (w.Blocks + 1) / 2) * pitch
		end,
		-- centre of road k (0-based, there are Blocks + 1 of them)
		RoadCenter = function(k: number): number
			return (k - w.Blocks / 2) * pitch
		end,
	}
end

-- Roads, lane markings, ground ------------------------------------------------------

local function buildGround(town: Folder, g)
	addPart(town, "Ground", Vector3.new(g.Ground, 2, g.Ground), Vector3.new(0, -1, 0), GRASS_OUTER, Enum.Material.Grass)

	-- Invisible walls so nobody can drive off the edge of the world.
	local walls = addFolder(town, "Boundary")
	local half = g.Ground / 2
	local wallHeight = 120
	local wallProps = { Transparency = 1, CanCollide = true, CanQuery = false }
	addPart(walls, "WallNorth", Vector3.new(g.Ground, wallHeight, 4), Vector3.new(0, wallHeight / 2, -half - 2), GRASS, nil, wallProps)
	addPart(walls, "WallSouth", Vector3.new(g.Ground, wallHeight, 4), Vector3.new(0, wallHeight / 2, half + 2), GRASS, nil, wallProps)
	addPart(walls, "WallWest", Vector3.new(4, wallHeight, g.Ground), Vector3.new(-half - 2, wallHeight / 2, 0), GRASS, nil, wallProps)
	addPart(walls, "WallEast", Vector3.new(4, wallHeight, g.Ground), Vector3.new(half + 2, wallHeight / 2, 0), GRASS, nil, wallProps)
end

local function addDashes(parent: Folder, centerX: number, centerZ: number, alongX: boolean)
	-- 7 dashes per block-length of road, never inside an intersection.
	for m = -3, 3 do
		local offset = m * 20
		if alongX then
			addPart(
				parent,
				"Dash",
				Vector3.new(9, 0.05, 0.7),
				Vector3.new(centerX + offset, SURFACE_Y + 0.025, centerZ),
				LINE_YELLOW,
				nil,
				{ CanCollide = false }
			)
		else
			addPart(
				parent,
				"Dash",
				Vector3.new(0.7, 0.05, 9),
				Vector3.new(centerX, SURFACE_Y + 0.025, centerZ + offset),
				LINE_YELLOW,
				nil,
				{ CanCollide = false }
			)
		end
	end
end

local function buildRoads(town: Folder, g)
	local roads = addFolder(town, "Roads")
	local markings = addFolder(town, "Markings")

	for k = 0, g.N do
		local z = g.RoadCenter(k)
		-- East-west roads run the full width of the town, intersections included.
		addSlab(roads, "RoadEW_" .. k, 0, z, g.Span, g.Road, ASPHALT, Enum.Material.Asphalt)
		for j = 1, g.N do
			addDashes(markings, g.BlockCenter(j), z, true)
		end

		-- North-south roads only cover the stretch between intersections.
		local x = g.RoadCenter(k)
		for i = 1, g.N do
			local zi = g.BlockCenter(i)
			addSlab(roads, "RoadNS_" .. k .. "_" .. i, x, zi, g.Road, g.Block, ASPHALT, Enum.Material.Asphalt)
			addDashes(markings, x, zi, false)
		end
	end
end

-- A block's sidewalk ring + inner lot (grass for housing, concrete for the depot).
local function buildBlockBase(parent: Folder, g, i: number, j: number, innerColor: Color3, innerMaterial: Enum.Material)
	local cx, cz = g.BlockCenter(j), g.BlockCenter(i)
	local s = g.Sidewalk
	local b = g.Block
	local inner = b - 2 * s
	local name = "Block_" .. i .. "_" .. j
	local model = Instance.new("Model")
	model.Name = name

	addSlab(model, "SidewalkN", cx, cz - b / 2 + s / 2, b, s, SIDEWALK, Enum.Material.Concrete)
	addSlab(model, "SidewalkS", cx, cz + b / 2 - s / 2, b, s, SIDEWALK, Enum.Material.Concrete)
	addSlab(model, "SidewalkW", cx - b / 2 + s / 2, cz, s, inner, SIDEWALK, Enum.Material.Concrete)
	addSlab(model, "SidewalkE", cx + b / 2 - s / 2, cz, s, inner, SIDEWALK, Enum.Material.Concrete)
	addSlab(model, "Lawn", cx, cz, inner, inner, innerColor, innerMaterial)

	model.Parent = parent
	return model
end

-- Street furniture ----------------------------------------------------------------

local function addTree(parent: Folder, rng, x: number, z: number)
	local trunkHeight = rng.range(5, 7)
	local leafSize = rng.range(8, 11)
	addPart(
		parent,
		"Trunk",
		Vector3.new(1.6, trunkHeight, 1.6),
		Vector3.new(x, SURFACE_Y + trunkHeight / 2, z),
		Color3.fromRGB(110, 80, 56),
		Enum.Material.Wood
	)
	local leaf = addPart(
		parent,
		"Leaves",
		Vector3.new(leafSize, leafSize, leafSize),
		Vector3.new(x, SURFACE_Y + trunkHeight + leafSize * 0.35, z),
		Color3.fromRGB(rng.int(62, 84), rng.int(128, 156), rng.int(60, 80)),
		Enum.Material.Grass,
		{ Shape = Enum.PartType.Ball }
	)
	leaf.CanCollide = false
end

local function addLamp(parent: Folder, x: number, z: number)
	addPart(parent, "LampPole", Vector3.new(0.8, 14, 0.8), Vector3.new(x, SURFACE_Y + 7, z), Color3.fromRGB(52, 54, 62), Enum.Material.Metal)
	addPart(
		parent,
		"LampHead",
		Vector3.new(2, 1.2, 2),
		Vector3.new(x, SURFACE_Y + 14.4, z),
		Color3.fromRGB(255, 240, 200),
		Enum.Material.Neon,
		{ CanCollide = false }
	)
end

local function addStreetSign(parent: Folder, x: number, z: number, streetName: string, avenueName: string)
	addPart(parent, "SignPole", Vector3.new(0.6, 12, 0.6), Vector3.new(x, SURFACE_Y + 6, z), Color3.fromRGB(70, 74, 84), Enum.Material.Metal)
	local green = Color3.fromRGB(28, 110, 70)
	local streetBoard = addPart(parent, "StreetSign", Vector3.new(9, 2, 0.3), Vector3.new(x, SURFACE_Y + 11, z), green, nil, { CanCollide = false })
	addText(streetBoard, Enum.NormalId.Front, streetName, Color3.new(1, 1, 1), green, 40)
	addText(streetBoard, Enum.NormalId.Back, streetName, Color3.new(1, 1, 1), green, 40)
	local avenueBoard = addPart(parent, "AvenueSign", Vector3.new(0.3, 2, 9), Vector3.new(x, SURFACE_Y + 8.6, z), green, nil, { CanCollide = false })
	addText(avenueBoard, Enum.NormalId.Left, avenueName, Color3.new(1, 1, 1), green, 40)
	addText(avenueBoard, Enum.NormalId.Right, avenueName, Color3.new(1, 1, 1), green, 40)
end

-- Houses ----------------------------------------------------------------------------

local DOOR_HEIGHT = 7.2

-- northSide: the house sits on the north edge of its block and faces the road to the north (-Z).
local function buildHouse(parent: Folder, g, rng, id: number, i: number, j: number, slot: number, northSide: boolean)
	local cx, cz = g.BlockCenter(j), g.BlockCenter(i)
	local dir = northSide and -1 or 1 -- direction the front of the house faces along Z
	local width = rng.range(27, 33)
	local depth = rng.range(22, 27)
	local height = rng.range(12, 15)
	local x = cx + (slot - 2) * 44
	local frontZ = cz + dir * 55
	local bodyZ = frontZ - dir * depth / 2
	local lawnEdgeZ = cz + dir * (g.Block / 2 - g.Sidewalk)
	local wall = rng.pick(WALL_COLORS)
	local roofColor = rng.pick(ROOF_COLORS)
	local doorColor = rng.pick(DOOR_COLORS)
	local face = northSide and Enum.NormalId.Front or Enum.NormalId.Back

	-- Address: north-row houses get even numbers, south-row odd, per street.
	local roadIndex = northSide and (i - 1) or i
	local street = Config.StreetNames[roadIndex + 1]
	local base = (j - 1) * Config.World.HousesPerRow + slot
	local number = base * 10 + (northSide and 2 or 1)
	local address = number .. " " .. street

	-- The delivery marker sits in the lane beside the house.
	local laneZ = cz + dir * (g.Block / 2 + g.Road / 4)
	local markerPos = Vector3.new(x, SURFACE_Y, laneZ)

	local model = Instance.new("Model")
	model.Name = "House_" .. id
	model:SetAttribute("HouseId", id)
	model:SetAttribute("Number", number)
	model:SetAttribute("Street", street)
	model:SetAttribute("Address", address)
	model:SetAttribute("MarkerPos", markerPos)

	local body = addPart(model, "Body", Vector3.new(width, height, depth), Vector3.new(x, SURFACE_Y + height / 2, bodyZ), wall, Enum.Material.Brick)
	model.PrimaryPart = body

	addPart(model, "Roof", Vector3.new(width + 2.4, 1.2, depth + 2.4), Vector3.new(x, SURFACE_Y + height + 0.6, bodyZ), roofColor, Enum.Material.Slate)
	addPart(
		model,
		"Chimney",
		Vector3.new(2.5, 4, 2.5),
		Vector3.new(x + width * 0.3, SURFACE_Y + height + 2.4, bodyZ - dir * depth * 0.2),
		Color3.fromRGB(150, 84, 70),
		Enum.Material.Brick
	)

	local out = dir * 0.2 -- features poke out of the front wall by this much
	addPart(
		model,
		"Door",
		Vector3.new(5, DOOR_HEIGHT, 0.5),
		Vector3.new(x, SURFACE_Y + DOOR_HEIGHT / 2, frontZ + out),
		doorColor,
		Enum.Material.Wood,
		{ CanCollide = false }
	)
	addPart(model, "Porch", Vector3.new(9, 0.5, 4), Vector3.new(x, SURFACE_Y + DOOR_HEIGHT + 0.9, frontZ + dir * 2), roofColor, nil, { CanCollide = false })
	for _, wx in { -9.5, 9.5 } do
		addPart(model, "WindowFrame", Vector3.new(7.4, 5.8, 0.3), Vector3.new(x + wx, SURFACE_Y + 6, frontZ + dir * 0.1), CREAM, nil, { CanCollide = false })
		local glass = addPart(
			model,
			"Window",
			Vector3.new(6.4, 4.8, 0.3),
			Vector3.new(x + wx, SURFACE_Y + 6, frontZ + dir * 0.25),
			GLASS,
			Enum.Material.Glass,
			{ CanCollide = false }
		)
		glass.Transparency = 0.35
	end

	local plaque = addPart(
		model,
		"NumberPlaque",
		Vector3.new(6.4, 2.6, 0.3),
		Vector3.new(x, SURFACE_Y + DOOR_HEIGHT + 2.4, frontZ + out),
		CREAM,
		nil,
		{ CanCollide = false }
	)
	addText(plaque, face, tostring(number), NAVY, nil, 60)

	-- Path from the front door out to the sidewalk.
	local pathLength = math.abs(frontZ - lawnEdgeZ)
	addPart(
		model,
		"Path",
		Vector3.new(5, 0.06, pathLength),
		Vector3.new(x, SURFACE_Y + 0.03, (frontZ + lawnEdgeZ) / 2),
		SIDEWALK,
		Enum.Material.Concrete,
		{ CanCollide = false }
	)

	model.Parent = parent
	return {
		Id = id,
		Number = number,
		Street = street,
		Address = address,
		MarkerPos = markerPos,
	}
end

-- Depot ---------------------------------------------------------------------------

local function addInvisibleAnchor(parent: Instance, name: string, position: Vector3): Part
	return addPart(parent, name, Vector3.new(1, 1, 1), position, Color3.new(1, 1, 1), nil, {
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
	})
end

local function buildDepot(town: Folder, g)
	local depot = Instance.new("Model")
	depot.Name = "Depot"

	-- Concrete yard inside the central block's sidewalks.
	local base = buildBlockBase(depot, g, (g.N + 1) / 2, (g.N + 1) / 2, LOT, Enum.Material.Concrete)
	base.Name = "Yard"

	-- Warehouse along the north edge of the yard; its front faces south (+Z).
	local warehouseZ = -44
	addPart(depot, "Warehouse", Vector3.new(90, 26, 38), Vector3.new(0, SURFACE_Y + 13, warehouseZ), NAVY_LIGHT, Enum.Material.Concrete)
	addPart(depot, "WarehouseRoof", Vector3.new(92, 1.5, 40), Vector3.new(0, SURFACE_Y + 26.75, warehouseZ), ORANGE)
	local frontWallZ = warehouseZ + 19 -- -25

	local sign = addPart(depot, "DepotSign", Vector3.new(60, 9, 0.6), Vector3.new(0, SURFACE_Y + 19.5, frontWallZ + 0.3), NAVY, nil, { CanCollide = false })
	addText(sign, Enum.NormalId.Back, "SWIFT DROP DEPOT", ORANGE, nil, 30)
	for _, dx in { -30, 30 } do
		addPart(
			depot,
			"RollerDoor",
			Vector3.new(16, 14, 0.4),
			Vector3.new(dx, SURFACE_Y + 7, frontWallZ + 0.2),
			Color3.fromRGB(150, 156, 168),
			Enum.Material.Metal,
			{ CanCollide = false }
		)
	end
	local office = addPart(
		depot,
		"OfficeWindow",
		Vector3.new(22, 6, 0.3),
		Vector3.new(0, SURFACE_Y + 6.5, frontWallZ + 0.15),
		GLASS,
		Enum.Material.Glass,
		{ CanCollide = false }
	)
	office.Transparency = 0.4

	-- Drive-up dispatch counter with an awning.
	addPart(depot, "DispatchCounter", Vector3.new(24, 4.4, 4), Vector3.new(0, SURFACE_Y + 2.2, -10), CREAM)
	addPart(depot, "CounterTop", Vector3.new(25, 0.4, 5), Vector3.new(0, SURFACE_Y + 4.6, -10), ORANGE)
	local counterSign = addPart(depot, "CounterSign", Vector3.new(16, 2.6, 0.2), Vector3.new(0, SURFACE_Y + 2.4, -7.9), NAVY, nil, { CanCollide = false })
	addText(counterSign, Enum.NormalId.Back, "DISPATCH", ORANGE, nil, 60)
	addPart(depot, "Awning", Vector3.new(34, 0.8, 16), Vector3.new(0, SURFACE_Y + 12, -16), ORANGE)
	for _, px in { -16, 16 } do
		addPart(depot, "AwningPost", Vector3.new(1.4, 12, 1.4), Vector3.new(px, SURFACE_Y + 6, -9), NAVY, Enum.Material.Metal)
	end

	local dispatchAnchor = addInvisibleAnchor(depot, "DispatchAnchor", Vector3.new(0, SURFACE_Y + 6, -7))
	local dispatchPrompt = Instance.new("ProximityPrompt")
	dispatchPrompt.Name = "Prompt"
	dispatchPrompt.ActionText = "Take Order"
	dispatchPrompt.ObjectText = "Dispatch"
	dispatchPrompt.KeyboardKeyCode = Enum.KeyCode.E
	dispatchPrompt.HoldDuration = 0.35
	dispatchPrompt.MaxActivationDistance = 24
	dispatchPrompt.RequiresLineOfSight = false
	dispatchPrompt.Parent = dispatchAnchor

	-- Yellow drive-up pad in front of the counter.
	local pad = addPart(
		depot,
		"PickupPad",
		Vector3.new(34, 0.1, 14),
		Vector3.new(0, SURFACE_Y + 0.05, 2),
		Color3.fromRGB(255, 200, 40),
		Enum.Material.Neon,
		{ CanCollide = false, Transparency = 0.35 }
	)
	addText(pad, Enum.NormalId.Top, "PICK UP HERE", NAVY, nil, 30)

	-- Garage on the east side of the yard; its doors face west.
	addPart(depot, "Garage", Vector3.new(34, 18, 30), Vector3.new(46, SURFACE_Y + 9, 28), Color3.fromRGB(70, 82, 118), Enum.Material.Concrete)
	addPart(depot, "GarageRoof", Vector3.new(36, 1.2, 32), Vector3.new(46, SURFACE_Y + 18.6, 28), ORANGE)
	for _, dz in { -9.5, 0, 9.5 } do
		addPart(
			depot,
			"GarageDoor",
			Vector3.new(0.5, 11, 8),
			Vector3.new(28.8, SURFACE_Y + 5.5, 28 + dz),
			Color3.fromRGB(160, 166, 178),
			Enum.Material.Metal,
			{ CanCollide = false }
		)
	end
	local garageSign = addPart(depot, "GarageSign", Vector3.new(0.6, 4, 22), Vector3.new(28.7, SURFACE_Y + 14.5, 28), NAVY, nil, { CanCollide = false })
	addText(garageSign, Enum.NormalId.Left, "GARAGE", ORANGE, nil, 40)

	local garageAnchor = addInvisibleAnchor(depot, "GarageAnchor", Vector3.new(25, SURFACE_Y + 4, 28))
	local garagePrompt = Instance.new("ProximityPrompt")
	garagePrompt.Name = "Prompt"
	garagePrompt.ActionText = "Open Garage"
	garagePrompt.ObjectText = "Vehicles"
	garagePrompt.KeyboardKeyCode = Enum.KeyCode.G
	garagePrompt.HoldDuration = 0
	garagePrompt.MaxActivationDistance = 24
	garagePrompt.RequiresLineOfSight = false
	garagePrompt.Parent = garageAnchor

	-- Where players appear.
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "Spawn"
	spawn.Anchored = true
	spawn.Neutral = true
	spawn.AllowTeamChangeOnTouch = false
	spawn.Duration = 0
	-- Thin and non-colliding so cars drive straight over it; players still appear on top of it.
	spawn.Size = Vector3.new(14, 0.2, 14)
	spawn.CFrame = CFrame.new(0, SURFACE_Y + 0.1, 34)
	spawn.CanCollide = false
	spawn.Color = ORANGE
	spawn.Material = Enum.Material.Neon
	spawn.Transparency = 0.6
	spawn.TopSurface = Enum.SurfaceType.Smooth
	spawn.BottomSurface = Enum.SurfaceType.Smooth
	spawn.Parent = depot

	-- A few trees along the yard edge.
	local props = addFolder(depot, "Trees")
	local rng = makeRng(7)
	for _, pos in { Vector3.new(-56, 0, 50), Vector3.new(-56, 0, 20), Vector3.new(56, 0, -10), Vector3.new(-56, 0, -8) } do
		addTree(props, rng, pos.X, pos.Z)
	end

	depot.Parent = town
	town:SetAttribute("DispatchPos", dispatchAnchor.CFrame.Position)
	town:SetAttribute("SpawnPos", spawn.CFrame.Position)
	return depot
end

-- Public API ------------------------------------------------------------------------

function WorldBuilder.build(parent: Instance): Folder
	local g = geometry()
	local rng = makeRng(20240229)

	local town = Instance.new("Folder")
	town.Name = "Town"

	buildGround(town, g)
	buildRoads(town, g)

	local blocks = addFolder(town, "Blocks")
	local houses = addFolder(town, "Houses")
	local props = addFolder(town, "Props")
	local center = (g.N + 1) / 2

	local nextId = 1
	for i = 1, g.N do
		for j = 1, g.N do
			if not (i == center and j == center) then
				buildBlockBase(blocks, g, i, j, GRASS, Enum.Material.Grass)
				local cx, cz = g.BlockCenter(j), g.BlockCenter(i)

				for slot = 1, Config.World.HousesPerRow do
					buildHouse(houses, g, rng, nextId, i, j, slot, true)
					nextId += 1
					buildHouse(houses, g, rng, nextId, i, j, slot, false)
					nextId += 1
				end

				-- Backyard trees between the two rows of houses.
				for tx = -2, 2 do
					for tz = -1, 1, 2 do
						if rng.float() > 0.35 then
							addTree(props, rng, cx + tx * 24 + rng.range(-4, 4), cz + tz * 14 + rng.range(-4, 4))
						end
					end
				end

				-- Street lamps at the middle of each block edge.
				local lampOffset = g.Block / 2 - g.Sidewalk / 2
				addLamp(props, cx, cz - lampOffset)
				addLamp(props, cx, cz + lampOffset)
				addLamp(props, cx - lampOffset, cz)
				addLamp(props, cx + lampOffset, cz)
			end
		end
	end

	-- Street name signs at every intersection that has a block to its south-east.
	local signs = addFolder(props, "StreetSigns")
	for k = 0, g.N - 1 do
		for m = 0, g.N - 1 do
			local x = g.RoadCenter(k) + g.Road / 2 + g.Sidewalk / 2
			local z = g.RoadCenter(m) + g.Road / 2 + g.Sidewalk / 2
			addStreetSign(signs, x, z, Config.StreetNames[m + 1], Config.AvenueNames[k + 1])
		end
	end

	buildDepot(town, g)

	town.Parent = parent
	return town
end

-- Reads a built town back into the plain data the game services use.
function WorldBuilder.info(town: Folder)
	local houses = {}
	for _, model in town.Houses:GetChildren() do
		table.insert(houses, {
			Id = model:GetAttribute("HouseId"),
			Number = model:GetAttribute("Number"),
			Street = model:GetAttribute("Street"),
			Address = model:GetAttribute("Address"),
			MarkerPos = model:GetAttribute("MarkerPos"),
		})
	end
	table.sort(houses, function(a, b)
		return a.Id < b.Id
	end)

	local depot = town.Depot
	return {
		Town = town,
		Houses = houses,
		DispatchPos = town:GetAttribute("DispatchPos"),
		SpawnPos = town:GetAttribute("SpawnPos"),
		DispatchPrompt = depot.DispatchAnchor.Prompt,
		GaragePrompt = depot.GarageAnchor.Prompt,
		Spawn = depot.Spawn,
	}
end

return WorldBuilder
