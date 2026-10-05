--!strict
-- Builds the whole map from parts at startup: ground, hub plaza (seed shop +
-- Birdpedia), scenery, and one fenced garden per player slot.

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Seeds = require(Shared:WaitForChild("Seeds"))

local WorldBuilder = {}

export type Garden = {
	slot: number,
	model: Model,
	origin: CFrame,
	spawnCF: CFrame,
	plots: { Part },
	lockGuis: { SurfaceGui },
	signLabels: { TextLabel },
	owner: Player?,
}

export type World = {
	gardens: { Garden },
	plantsFolder: Folder,
}

local TOP = 0.6 -- height of the walkable surface (plaza, paths, garden pads)
local GARDEN_RADIUS = 125
local PLOT_SIZE = 10
local PLOT_PITCH = 13

local GRASS = Color3.fromRGB(98, 172, 86)
local WOOD = Color3.fromRGB(150, 106, 68)
local CREAM = Color3.fromRGB(250, 240, 214)

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local function part(
	parent: Instance,
	name: string,
	size: Vector3,
	cf: CFrame,
	color: Color3,
	material: Enum.Material?,
	collide: boolean?
): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Anchored = true
	p.CanCollide = if collide == nil then true else collide
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

-- Upright cylinder centred at `cf`
local function cylinder(
	parent: Instance,
	name: string,
	height: number,
	diameter: number,
	cf: CFrame,
	color: Color3,
	material: Enum.Material?,
	collide: boolean?
): Part
	local p = part(
		parent,
		name,
		Vector3.new(height, diameter, diameter),
		cf * CFrame.Angles(0, 0, math.rad(90)),
		color,
		material,
		collide
	)
	p.Shape = Enum.PartType.Cylinder
	return p
end

local function ball(
	parent: Instance,
	name: string,
	size: Vector3,
	cf: CFrame,
	color: Color3,
	material: Enum.Material?
): Part
	local p = part(parent, name, size, cf, color, material, false)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = p
	return p
end

local function surfaceText(
	target: Part,
	face: Enum.NormalId,
	text: string,
	color: Color3?,
	pixelsPerStud: number?
): (SurfaceGui, TextLabel)
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = pixelsPerStud or 40
	gui.LightInfluence = 0
	gui.Parent = target

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextScaled = true
	label.Font = Enum.Font.FredokaOne
	label.TextColor3 = color or CREAM
	label.TextStrokeColor3 = Color3.fromRGB(60, 40, 24)
	label.TextStrokeTransparency = 0.45
	label.Parent = gui
	return gui, label
end

local function billboardText(parent: BasePart, text: string, offset: Vector3, width: number, height: number): TextLabel
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(width, height)
	gui.StudsOffsetWorldSpace = offset
	gui.MaxDistance = 140
	gui.LightInfluence = 0
	gui.Parent = parent

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextScaled = true
	label.Font = Enum.Font.FredokaOne
	label.TextColor3 = CREAM
	label.TextStrokeColor3 = Color3.fromRGB(50, 34, 20)
	label.TextStrokeTransparency = 0.3
	label.Parent = gui
	return label
end

local function prompt(parent: BasePart, name: string, action: string, object: string)
	local p = Instance.new("ProximityPrompt")
	p.Name = name
	p.ActionText = action
	p.ObjectText = object
	p.KeyboardKeyCode = Enum.KeyCode.E
	p.HoldDuration = 0
	p.MaxActivationDistance = 18
	p.RequiresLineOfSight = false
	p.Parent = parent
end

------------------------------------------------------------------------------
-- Lighting
------------------------------------------------------------------------------

function WorldBuilder.setupLighting()
	Lighting.ClockTime = 14.2
	Lighting.Brightness = 2.6
	Lighting.Ambient = rgb(104, 108, 120)
	Lighting.OutdoorAmbient = rgb(128, 134, 150)
	Lighting.EnvironmentDiffuseScale = 0.6
	Lighting.EnvironmentSpecularScale = 0.4

	for _, class in { "Atmosphere", "Sky", "ColorCorrectionEffect", "BloomEffect", "SunRaysEffect" } do
		for _, child in Lighting:GetChildren() do
			if child.ClassName == class then
				child:Destroy()
			end
		end
	end

	local sky = Instance.new("Sky")
	sky.Parent = Lighting

	local atmosphere = Instance.new("Atmosphere")
	atmosphere.Density = 0.26
	atmosphere.Offset = 0.2
	atmosphere.Color = rgb(190, 208, 230)
	atmosphere.Decay = rgb(240, 220, 190)
	atmosphere.Glare = 0.2
	atmosphere.Haze = 0.8
	atmosphere.Parent = Lighting

	local correction = Instance.new("ColorCorrectionEffect")
	correction.Saturation = 0.14
	correction.Contrast = 0.05
	correction.TintColor = rgb(255, 250, 242)
	correction.Parent = Lighting

	local bloom = Instance.new("BloomEffect")
	bloom.Intensity = 0.3
	bloom.Size = 20
	bloom.Threshold = 1.1
	bloom.Parent = Lighting

	local rays = Instance.new("SunRaysEffect")
	rays.Intensity = 0.05
	rays.Spread = 0.6
	rays.Parent = Lighting
end

------------------------------------------------------------------------------
-- Scenery
------------------------------------------------------------------------------

local function buildTree(parent: Instance, position: Vector3, scale: number, rng: Random)
	local trunkHeight = 8 * scale
	cylinder(
		parent,
		"Trunk",
		trunkHeight,
		1.6 * scale,
		CFrame.new(position + Vector3.new(0, trunkHeight / 2, 0)),
		rgb(110, 78, 54),
		Enum.Material.Wood
	)
	local greens = { rgb(70, 150, 66), rgb(84, 166, 74), rgb(62, 138, 60) }
	for i = 1, 3 do
		local offset = Vector3.new(rng:NextNumber(-2, 2), trunkHeight + rng:NextNumber(0, 3.5), rng:NextNumber(-2, 2))
			* scale
		local size = Vector3.new(8, 6.5, 8) * scale * rng:NextNumber(0.8, 1.1)
		local canopy = ball(parent, "Canopy", size, CFrame.new(position + offset), greens[i], Enum.Material.Grass)
		canopy.CanCollide = false
	end
end

local function buildScenery(world: Folder, rng: Random)
	local ground = part(world, "Ground", Vector3.new(900, 2, 900), CFrame.new(0, -1, 0), GRASS, Enum.Material.Grass)
	ground.Name = "Ground"

	-- A ring of trees around the whole map, plus a few between the gardens.
	local scenery = Instance.new("Folder")
	scenery.Name = "Trees"
	scenery.Parent = world
	for i = 1, 56 do
		local angle = i / 56 * math.pi * 2 + rng:NextNumber(-0.04, 0.04)
		local radius = rng:NextNumber(205, 245)
		buildTree(
			scenery,
			Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius),
			rng:NextNumber(1.2, 2.0),
			rng
		)
	end
	for i = 1, Config.MAX_GARDENS do
		-- between two neighbouring gardens
		local angle = (i - 0.5) / Config.MAX_GARDENS * math.pi * 2
		buildTree(scenery, Vector3.new(math.cos(angle) * 128, 0, math.sin(angle) * 128), rng:NextNumber(1.1, 1.5), rng)
	end
end

local function buildHub(world: Folder)
	local hub = Instance.new("Model")
	hub.Name = "Hub"
	hub.Parent = world

	cylinder(hub, "Plaza", TOP, 88, CFrame.new(0, TOP / 2, 0), rgb(206, 198, 182), Enum.Material.Cobblestone)
	cylinder(
		hub,
		"PlazaInner",
		TOP + 0.04,
		58,
		CFrame.new(0, (TOP + 0.04) / 2, 0),
		rgb(224, 214, 190),
		Enum.Material.Slate
	)

	-- Paths from the plaza to each garden entrance
	for slot = 1, Config.MAX_GARDENS do
		local angle = (slot - 1) / Config.MAX_GARDENS * math.pi * 2
		local dir = Vector3.new(math.cos(angle), 0, math.sin(angle))
		local from, to = 40, GARDEN_RADIUS - 29
		local center = dir * ((from + to) / 2)
		part(
			hub,
			"Path",
			Vector3.new(9, TOP, to - from),
			CFrame.lookAt(center + Vector3.new(0, TOP / 2, 0), Vector3.new(0, TOP / 2, 0)),
			rgb(214, 190, 150),
			Enum.Material.Sand
		)
	end

	-- Seed shop kiosk
	local shop = Instance.new("Model")
	shop.Name = "SeedShop"
	shop.Parent = hub
	local counter = cylinder(shop, "Counter", 4, 12, CFrame.new(0, TOP + 2, 0), WOOD, Enum.Material.Wood)
	cylinder(shop, "CounterTop", 0.5, 13.5, CFrame.new(0, TOP + 4.25, 0), rgb(240, 220, 176), Enum.Material.WoodPlanks)
	for i = 0, 3 do
		local a = i / 4 * math.pi * 2 + math.pi / 4
		part(
			shop,
			"Post",
			Vector3.new(0.8, 8, 0.8),
			CFrame.new(math.cos(a) * 5.4, TOP + 8.5, math.sin(a) * 5.4),
			rgb(220, 196, 150),
			Enum.Material.Wood
		)
	end
	cylinder(shop, "Roof", 0.8, 17, CFrame.new(0, TOP + 12.9, 0), rgb(206, 72, 62), Enum.Material.SmoothPlastic)
	cylinder(shop, "RoofTrim", 0.9, 14, CFrame.new(0, TOP + 12.9, 0), rgb(246, 240, 230), Enum.Material.SmoothPlastic)
	cylinder(shop, "RoofTop", 1.4, 6, CFrame.new(0, TOP + 14, 0), rgb(206, 72, 62), Enum.Material.SmoothPlastic)
	-- jars of every seed on the counter
	for i, seed in Seeds.list do
		local a = i / #Seeds.list * math.pi * 2
		ball(
			shop,
			"SeedJar",
			Vector3.new(1.5, 1.5, 1.5),
			CFrame.new(math.cos(a) * 4.2, TOP + 5.3, math.sin(a) * 4.2),
			seed.color,
			Enum.Material.Neon
		)
	end
	prompt(counter, "ShopPrompt", "Browse Seeds", "Seed Shop")
	billboardText(counter, "SEED SHOP", Vector3.new(0, 17, 0), 300, 70)

	-- Birdpedia board
	local boardPos = Vector3.new(24, 0, 24)
	local boardCF = CFrame.lookAt(Vector3.new(boardPos.X, TOP + 6.5, boardPos.Z), Vector3.new(0, TOP + 6.5, 0))
	local board = part(hub, "BirdpediaBoard", Vector3.new(13, 5.5, 0.6), boardCF, rgb(86, 120, 98), Enum.Material.Wood)
	for _, x in { -5.5, 5.5 } do
		part(hub, "BoardPost", Vector3.new(0.9, 7, 0.9), boardCF * CFrame.new(x, -2.2, 0.2), WOOD, Enum.Material.Wood)
	end
	surfaceText(board, Enum.NormalId.Front, "BIRDPEDIA\nSee every bird you've attracted", CREAM, 30)
	prompt(board, "BirdpediaPrompt", "Open Birdpedia", "Field Guide")

	-- Hub spawn (players are moved to their own garden once their data loads)
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "HubSpawn"
	spawn.Size = Vector3.new(10, 0.2, 10)
	spawn.CFrame = CFrame.new(0, TOP + 0.1, 32)
	spawn.Anchored = true
	spawn.Neutral = true
	spawn.CanCollide = false
	spawn.Transparency = 1
	spawn.Duration = 0
	spawn.Parent = hub
end

------------------------------------------------------------------------------
-- Gardens
------------------------------------------------------------------------------

local function buildGarden(slot: number, parent: Folder): Garden
	local angle = (slot - 1) / Config.MAX_GARDENS * math.pi * 2
	local center = Vector3.new(math.cos(angle) * GARDEN_RADIUS, 0, math.sin(angle) * GARDEN_RADIUS)
	-- local -Z points at the hub, so the entrance is on the hub side
	local origin = CFrame.lookAt(center, Vector3.zero)
	local function at(x: number, y: number, z: number): CFrame
		return origin * CFrame.new(x, y, z)
	end

	local model = Instance.new("Model")
	model.Name = "Garden_" .. slot
	model:SetAttribute("Slot", slot)
	model:SetAttribute("OwnerUserId", 0)
	model.Parent = parent

	part(model, "Pad", Vector3.new(60, TOP, 58), at(0, TOP / 2, 0), rgb(112, 184, 92), Enum.Material.Grass)

	-- soil plots, row by row from the entrance outwards
	local plots: { Part } = {}
	local lockGuis: { SurfaceGui } = {}
	for row = 1, Config.PLOT_ROWS do
		for col = 1, Config.PLOT_COLUMNS do
			local index = (row - 1) * Config.PLOT_COLUMNS + col
			local x = (col - (Config.PLOT_COLUMNS + 1) / 2) * PLOT_PITCH
			local z = -9 + (row - 1) * PLOT_PITCH
			local soil = part(
				model,
				"Plot_" .. index,
				Vector3.new(PLOT_SIZE, 0.5, PLOT_SIZE),
				at(x, TOP + 0.25, z),
				rgb(116, 118, 124),
				Enum.Material.Slate
			)
			soil:SetAttribute("Index", index)
			soil:SetAttribute("Locked", true)
			soil:SetAttribute("HasPlant", false)
			local gui, label = surfaceText(soil, Enum.NormalId.Top, "LOCKED", rgb(210, 214, 222), 24)
			label.TextTransparency = 0.25
			plots[index] = soil
			lockGuis[index] = gui
		end
	end

	-- fence with a gap at the entrance
	local rail = Vector3.new(0.6, 1.4, 58)
	part(model, "FenceL", rail, at(-30, TOP + 0.7, 0), WOOD, Enum.Material.Wood)
	part(model, "FenceR", rail, at(30, TOP + 0.7, 0), WOOD, Enum.Material.Wood)
	part(model, "FenceBack", Vector3.new(60.6, 1.4, 0.6), at(0, TOP + 0.7, 29), WOOD, Enum.Material.Wood)
	part(model, "FenceFrontL", Vector3.new(22, 1.4, 0.6), at(-19, TOP + 0.7, -29), WOOD, Enum.Material.Wood)
	part(model, "FenceFrontR", Vector3.new(22, 1.4, 0.6), at(19, TOP + 0.7, -29), WOOD, Enum.Material.Wood)

	-- entrance arch with the owner's name
	part(model, "ArchPostL", Vector3.new(0.9, 7.5, 0.9), at(-8.5, TOP + 3.75, -29), WOOD, Enum.Material.Wood)
	part(model, "ArchPostR", Vector3.new(0.9, 7.5, 0.9), at(8.5, TOP + 3.75, -29), WOOD, Enum.Material.Wood)
	part(model, "ArchBeam", Vector3.new(18.8, 1, 1), at(0, TOP + 8, -29), WOOD, Enum.Material.Wood)
	local sign =
		part(model, "Sign", Vector3.new(13, 3.4, 0.5), at(0, TOP + 10.2, -29), rgb(94, 128, 100), Enum.Material.Wood)
	part(model, "SignStrut", Vector3.new(0.5, 1.8, 0.5), at(-4, TOP + 8.9, -29), WOOD, Enum.Material.Wood)
	part(model, "SignStrut", Vector3.new(0.5, 1.8, 0.5), at(4, TOP + 8.9, -29), WOOD, Enum.Material.Wood)
	local signLabels: { TextLabel } = {}
	for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
		local _, label = surfaceText(sign, face, "Free Garden", CREAM, 40)
		table.insert(signLabels, label)
	end

	-- decorative bird bath at the back
	cylinder(model, "BathBase", 2.2, 1.8, at(0, TOP + 1.1, 25), rgb(200, 196, 188), Enum.Material.Marble)
	cylinder(model, "BathBowl", 0.9, 5, at(0, TOP + 2.6, 25), rgb(214, 210, 202), Enum.Material.Marble)
	local water =
		cylinder(model, "BathWater", 0.12, 4.2, at(0, TOP + 3.1, 25), rgb(120, 190, 255), Enum.Material.Glass, false)
	water.Transparency = 0.25

	local spawnCF = at(0, TOP + 3.5, -21) * CFrame.Angles(0, math.pi, 0)

	return {
		slot = slot,
		model = model,
		origin = origin,
		spawnCF = spawnCF,
		plots = plots,
		lockGuis = lockGuis,
		signLabels = signLabels,
		owner = nil,
	}
end

function WorldBuilder.build(): World
	WorldBuilder.setupLighting()

	local worldFolder = Instance.new("Folder")
	worldFolder.Name = "World"
	worldFolder.Parent = workspace
	local rng = Random.new(2024)
	buildScenery(worldFolder, rng)
	buildHub(worldFolder)

	local gardensFolder = Instance.new("Folder")
	gardensFolder.Name = "Gardens"
	gardensFolder.Parent = workspace
	local gardens: { Garden } = {}
	for slot = 1, Config.MAX_GARDENS do
		gardens[slot] = buildGarden(slot, gardensFolder)
	end

	local plants = Instance.new("Folder")
	plants.Name = "Plants"
	plants.Parent = workspace

	return { gardens = gardens, plantsFolder = plants }
end

return WorldBuilder
