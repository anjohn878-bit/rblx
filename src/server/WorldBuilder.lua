-- Builds the map at runtime: garden plots, paths, the seed shop and decorations.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BirdBuilder = require(Shared.BirdBuilder)
local Birds = require(Shared.Birds)
local Config = require(Shared.Config)
local PlantBuilder = require(Shared.PlantBuilder)
local Seeds = require(Shared.Seeds)

local WorldBuilder = {}

local GRASS = Color3.fromRGB(96, 160, 68)
local PLOT_GRASS = Color3.fromRGB(125, 190, 85)
local SOIL = Color3.fromRGB(115, 78, 50)
local PATH = Color3.fromRGB(210, 195, 155)
local WOOD = Color3.fromRGB(160, 115, 70)
local DARK_WOOD = Color3.fromRGB(120, 82, 50)
local STONE = Color3.fromRGB(160, 160, 165)

-- Half-size of a plot's grass base (x, z)
local PLOT_HALF_X = 21
local PLOT_HALF_Z = 18
local PLOT_ROW_Z = 55
local PLOT_SPACING_X = 56

local function newPart(parent, name, size, cf, color, material, extra)
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cf
	part.Color = color
	part.Material = material or Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Anchored = true
	if extra then
		for key, value in pairs(extra) do
			part[key] = value
		end
	end
	part.Parent = parent
	return part
end

local function newSignText(part, face, text, textColor, background)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Sign"
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 50
	gui.LightInfluence = 0
	gui.Parent = part

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundColor3 = background or Color3.fromRGB(250, 240, 210)
	label.BackgroundTransparency = background and 0 or 1
	label.Font = Enum.Font.FredokaOne
	label.Text = text
	label.TextColor3 = textColor or Color3.fromRGB(70, 45, 25)
	label.TextScaled = true
	label.Parent = gui

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0.04, 0)
	padding.PaddingRight = UDim.new(0.04, 0)
	padding.PaddingTop = UDim.new(0.1, 0)
	padding.PaddingBottom = UDim.new(0.1, 0)
	padding.Parent = label
	return label
end

-- A wooden fence along the ground from local point a to b.
local function buildFence(parent, origin, a, b)
	local direction = b - a
	local length = direction.Magnitude
	for _, height in ipairs({ 1.3, 2.5 }) do
		local lift = Vector3.new(0, height, 0)
		local cf = origin * CFrame.lookAt((a + b) / 2 + lift, b + lift)
		newPart(parent, "Rail", Vector3.new(0.25, 0.35, length), cf, WOOD, Enum.Material.Wood)
	end
	local posts = math.max(1, math.floor(length / 6))
	for i = 0, posts do
		local point = a + direction * (i / posts)
		newPart(
			parent,
			"Post",
			Vector3.new(0.6, 3.2, 0.6),
			origin * CFrame.new(point + Vector3.new(0, 1.6, 0)),
			DARK_WOOD,
			Enum.Material.Wood
		)
	end
end

local function decorate(model)
	-- decorations should not get in the way of tile prompts
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.CanQuery = false
			descendant.CanTouch = false
		end
	end
end

-- A twiggy nest. Pets sit around it while they keep their egg warm.
local function buildNest(parent, index, cf)
	local model = Instance.new("Model")
	model.Name = "Nest" .. index
	local twig = Color3.fromRGB(125, 90, 55)
	local base = newPart(
		model,
		"NestBase",
		Vector3.new(0.5, 4.4, 4.4),
		cf * CFrame.new(0, 0.25, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Color3.fromRGB(105, 75, 45),
		Enum.Material.Wood,
		{ Shape = Enum.PartType.Cylinder, CanCollide = false }
	)
	base:SetAttribute("NestIndex", index)
	newPart(
		model,
		"Straw",
		Vector3.new(0.2, 3.2, 3.2),
		cf * CFrame.new(0, 0.55, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Color3.fromRGB(215, 185, 115),
		Enum.Material.Grass,
		{ Shape = Enum.PartType.Cylinder, CanCollide = false, CanQuery = false }
	)
	for i = 1, 10 do
		local angle = i / 10 * math.pi * 2
		local stick = newPart(
			model,
			"Twigs",
			Vector3.new(1.7, 0.65, 0.65),
			cf
				* CFrame.new(math.cos(angle) * 1.85, 0.75, math.sin(angle) * 1.85)
				* CFrame.Angles(0, -angle + math.pi / 2, 0),
			twig,
			Enum.Material.Wood,
			{ CanCollide = false, CanQuery = false }
		)
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = stick
	end

	local gui = Instance.new("BillboardGui")
	gui.Name = "NestStatus"
	gui.Size = UDim2.fromOffset(170, 40)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 4.2, 0)
	gui.MaxDistance = 40
	gui.LightInfluence = 0
	local label = Instance.new("TextLabel")
	label.Name = "Status"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.Text = "🪺 Empty nest"
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.3
	label.TextScaled = true
	label.Parent = gui
	gui.Parent = base

	model.Parent = parent
	return { Model = model, Base = base, CFrame = cf }
end

------------------------------------------------------------------------------

local function buildPlot(parent, id, cf)
	local model = Instance.new("Model")
	model.Name = "Plot" .. id
	model:SetAttribute("PlotId", id)

	newPart(
		model,
		"Ground",
		Vector3.new(PLOT_HALF_X * 2, 0.4, PLOT_HALF_Z * 2),
		cf * CFrame.new(0, 0.2, 0),
		PLOT_GRASS,
		Enum.Material.Grass
	)

	-- soil tiles
	local tiles = {}
	local columns, rows = Config.PlotColumns, Config.PlotRows
	local spacing, size = Config.TileSpacing, Config.TileSize
	for row = 1, rows do
		for column = 1, columns do
			local index = (row - 1) * columns + column
			local x = (column - (columns + 1) / 2) * spacing
			local z = (row - (rows + 1) / 2) * spacing - 3
			local tile = newPart(
				model,
				"Tile" .. index,
				Vector3.new(size, 0.6, size),
				cf * CFrame.new(x, 0.7, z),
				SOIL,
				Enum.Material.Ground
			)
			tile:SetAttribute("TileIndex", index)
			tile:SetAttribute("PlotId", id)
			tiles[index] = tile
		end
	end

	-- fence with a gate gap at the front (+Z)
	local fences = Instance.new("Folder")
	fences.Name = "Fence"
	fences.Parent = model
	local x, z = PLOT_HALF_X, PLOT_HALF_Z
	buildFence(fences, cf, Vector3.new(-x, 0, -z), Vector3.new(x, 0, -z))
	buildFence(fences, cf, Vector3.new(-x, 0, -z), Vector3.new(-x, 0, z))
	buildFence(fences, cf, Vector3.new(x, 0, -z), Vector3.new(x, 0, z))
	buildFence(fences, cf, Vector3.new(-x, 0, z), Vector3.new(-6, 0, z))
	buildFence(fences, cf, Vector3.new(6, 0, z), Vector3.new(x, 0, z))

	-- gate arch with the owner's name
	for _, side in ipairs({ -1, 1 }) do
		newPart(
			model,
			"GatePost",
			Vector3.new(0.9, 8, 0.9),
			cf * CFrame.new(side * 6, 4, z),
			DARK_WOOD,
			Enum.Material.Wood
		)
	end
	local board = newPart(
		model,
		"GateSign",
		Vector3.new(13, 2.4, 0.5),
		cf * CFrame.new(0, 7.2, z),
		WOOD,
		Enum.Material.WoodPlanks
	)
	local signLabel = newSignText(board, Enum.NormalId.Back, "Empty Garden")
	newSignText(board, Enum.NormalId.Front, "🐦 Bird Garden 🐦")

	-- nests for breeding, in the front corners
	local nests = {}
	for index = 1, Config.NestCount do
		local side = index % 2 == 1 and -1 or 1
		local row = math.floor((index - 1) / 2)
		nests[index] = buildNest(model, index, cf * CFrame.new(side * 14, 0.4, z - 4.5 - row * 5))
	end

	model.Parent = parent

	return {
		Id = id,
		Model = model,
		CFrame = cf,
		Tiles = tiles,
		SignLabel = signLabel,
		Nests = nests,
		SpawnCFrame = cf * CFrame.new(0, 3.5, z - 4),
		FrontPoint = (cf * CFrame.new(0, 0, z)).Position,
	}
end

local function buildShop(parent, cf)
	local model = Instance.new("Model")
	model.Name = "SeedShop"

	newPart(
		model,
		"Floor",
		Vector3.new(18, 0.4, 10),
		cf * CFrame.new(0, 0.2, 0),
		Color3.fromRGB(170, 130, 85),
		Enum.Material.WoodPlanks
	)
	newPart(
		model,
		"BackWall",
		Vector3.new(18, 8.6, 0.5),
		cf * CFrame.new(0, 4.5, -4.75),
		WOOD,
		Enum.Material.WoodPlanks
	)
	local counter =
		newPart(model, "Counter", Vector3.new(16, 3.2, 2), cf * CFrame.new(0, 2, 3.5), DARK_WOOD, Enum.Material.Wood)
	newPart(
		model,
		"CounterTop",
		Vector3.new(16.6, 0.3, 2.6),
		cf * CFrame.new(0, 3.75, 3.5),
		Color3.fromRGB(200, 160, 110),
		Enum.Material.Wood
	)
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			newPart(
				model,
				"Post",
				Vector3.new(0.8, 9, 0.8),
				cf * CFrame.new(sx * 8.6, 4.5, sz * 4.6),
				DARK_WOOD,
				Enum.Material.Wood
			)
		end
	end

	-- striped awning with a scalloped edge
	local stripeColors = { Color3.fromRGB(230, 75, 75), Color3.fromRGB(250, 245, 235) }
	for i = 0, 8 do
		local color = stripeColors[i % 2 + 1]
		local stripeX = -8 + i * 2
		newPart(
			model,
			"Awning",
			Vector3.new(2, 0.3, 11.2),
			cf * CFrame.new(stripeX, 9.15, 0.4),
			color,
			Enum.Material.Fabric
		)
		local scallop = newPart(
			model,
			"Scallop",
			Vector3.new(2, 0.9, 0.25),
			cf * CFrame.new(stripeX, 8.9, 6.05),
			color,
			Enum.Material.Fabric
		)
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = scallop
	end
	local sign = newPart(
		model,
		"ShopSign",
		Vector3.new(14, 2.4, 0.4),
		cf * CFrame.new(0, 10.5, 5.8),
		WOOD,
		Enum.Material.WoodPlanks
	)
	newSignText(
		sign,
		Enum.NormalId.Back,
		"🌱 SEED SHOP 🌱",
		Color3.fromRGB(255, 255, 255),
		Color3.fromRGB(70, 140, 60)
	)

	-- seed crates on the counter
	local crateSeeds = { "Sunflower", "BerryBush", "Lavender", "Hibiscus", "Lotus" }
	for i, seedId in ipairs(crateSeeds) do
		local look = Seeds.Get(seedId).Look
		local crateCf = cf * CFrame.new(-6.4 + (i - 1) * 3.2, 4.3, 3.5)
		newPart(
			model,
			"Crate",
			Vector3.new(2.2, 0.8, 1.6),
			crateCf,
			Color3.fromRGB(185, 140, 90),
			Enum.Material.WoodPlanks
		)
		local pile = newPart(
			model,
			"SeedPile",
			Vector3.new(1.9, 0.6, 1.3),
			crateCf * CFrame.new(0, 0.4, 0),
			look.PetalColor or look.BerryColor or look.FlowerColor or Color3.new(1, 1, 1),
			Enum.Material.Pebble
		)
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = pile
	end

	-- Polly the parrot runs the shop
	newPart(model, "PerchPole", Vector3.new(0.5, 4, 0.5), cf * CFrame.new(0, 2.4, 0.5), DARK_WOOD, Enum.Material.Wood)
	newPart(model, "PerchBar", Vector3.new(3, 0.4, 0.4), cf * CFrame.new(0, 4.4, 0.5), DARK_WOOD, Enum.Material.Wood)
	local polly = BirdBuilder.Build(Birds.Get("Parrot"), { Scale = 1.5 })
	polly.Name = "Polly"
	local standHeight = polly:GetAttribute("StandHeight")
	polly:PivotTo(cf * CFrame.new(0, 4.6 + standHeight, 0.5) * CFrame.Angles(0, math.pi, 0))
	polly:SetAttribute("Flying", false)
	polly:AddTag("BirdGardenBird")
	polly.Parent = model

	local nameGui = Instance.new("BillboardGui")
	nameGui.Name = "NameTag"
	nameGui.Size = UDim2.fromOffset(200, 40)
	nameGui.StudsOffsetWorldSpace = Vector3.new(0, 3.2, 0)
	nameGui.MaxDistance = 60
	nameGui.Parent = polly.PrimaryPart
	local nameLabel = Instance.new("TextLabel")
	nameLabel.Size = UDim2.fromScale(1, 1)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Font = Enum.Font.FredokaOne
	nameLabel.Text = "Polly the Shopkeeper"
	nameLabel.TextColor3 = Color3.new(1, 1, 1)
	nameLabel.TextStrokeTransparency = 0.4
	nameLabel.TextScaled = true
	nameLabel.Parent = nameGui

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "ShopPrompt"
	prompt.ActionText = "Browse Seeds"
	prompt.ObjectText = "Seed Shop"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 14
	prompt.RequiresLineOfSight = false
	prompt.Parent = counter

	decorate(model)
	model.Parent = parent
	return model, prompt
end

local function buildBirdBath(parent, cf)
	local model = Instance.new("Model")
	model.Name = "BirdBath"
	local upright = CFrame.Angles(0, 0, math.rad(90))
	newPart(
		model,
		"Base",
		Vector3.new(0.6, 4, 4),
		cf * CFrame.new(0, 0.3, 0) * upright,
		STONE,
		Enum.Material.Slate,
		{ Shape = Enum.PartType.Cylinder }
	)
	newPart(
		model,
		"Pedestal",
		Vector3.new(3.4, 1.6, 1.6),
		cf * CFrame.new(0, 2.2, 0) * upright,
		STONE,
		Enum.Material.Slate,
		{ Shape = Enum.PartType.Cylinder }
	)
	newPart(
		model,
		"Basin",
		Vector3.new(0.9, 6, 6),
		cf * CFrame.new(0, 4.2, 0) * upright,
		STONE,
		Enum.Material.Slate,
		{ Shape = Enum.PartType.Cylinder }
	)
	newPart(
		model,
		"Water",
		Vector3.new(0.1, 5.2, 5.2),
		cf * CFrame.new(0, 4.66, 0) * upright,
		Color3.fromRGB(80, 160, 220),
		Enum.Material.Glass,
		{ Shape = Enum.PartType.Cylinder, Transparency = 0.25, Reflectance = 0.2 }
	)

	-- a couple of sparrows splashing about
	for i, angle in ipairs({ 0.4, 2.6 }) do
		local bird = BirdBuilder.Build(Birds.Get(i == 1 and "Sparrow" or "Robin"))
		local rim = Vector3.new(math.cos(angle) * 2.7, 4.65, math.sin(angle) * 2.7)
		local position = cf * CFrame.new(rim + Vector3.new(0, bird:GetAttribute("StandHeight"), 0))
		bird:PivotTo(CFrame.lookAt(position.Position, cf.Position + Vector3.new(0, position.Y, 0)))
		bird:SetAttribute("Flying", false)
		bird:AddTag("BirdGardenBird")
		bird.Parent = model
	end

	decorate(model)
	model.Parent = parent
end

local function buildTitleSign(parent, cf)
	local model = Instance.new("Model")
	model.Name = "TitleSign"
	for _, side in ipairs({ -1, 1 }) do
		newPart(
			model,
			"Post",
			Vector3.new(0.8, 9, 0.8),
			cf * CFrame.new(side * 6.5, 4.5, 0),
			DARK_WOOD,
			Enum.Material.Wood
		)
	end
	local board =
		newPart(model, "Board", Vector3.new(15, 4, 0.5), cf * CFrame.new(0, 7, 0), WOOD, Enum.Material.WoodPlanks)
	newSignText(
		board,
		Enum.NormalId.Front,
		"🐦 Grow a Bird Garden 🌻",
		Color3.fromRGB(255, 255, 255),
		Color3.fromRGB(60, 130, 190)
	)
	decorate(model)
	model.Parent = parent
end

local function placeDecorPlant(parent, seedId, position, scale, yaw)
	local plant = PlantBuilder.Build(Seeds.Get(seedId), 4, scale)
	plant:PivotTo(CFrame.new(position) * CFrame.Angles(0, yaw or 0, 0))
	local trunk = plant:FindFirstChild("Trunk")
	if trunk then
		trunk.CanCollide = true
	end
	decorate(plant)
	plant.Parent = parent
end

------------------------------------------------------------------------------

function WorldBuilder.Build()
	local baseplate = workspace:FindFirstChild("Baseplate")
	if baseplate and baseplate:IsA("BasePart") then
		baseplate.Material = Enum.Material.Grass
		baseplate.Color = GRASS
		for _, child in ipairs(baseplate:GetChildren()) do
			if child:IsA("Texture") or child:IsA("Decal") then
				child:Destroy()
			end
		end
	else
		-- no baseplate in this place: make some ground to stand on
		newPart(workspace, "Baseplate", Vector3.new(512, 16, 512), CFrame.new(0, -8, 0), GRASS, Enum.Material.Grass)
	end

	local root = workspace:FindFirstChild("BirdGarden")
	if root then
		root:Destroy()
	end
	root = Instance.new("Folder")
	root.Name = "BirdGarden"
	root.Parent = workspace

	local plotsFolder = Instance.new("Folder")
	plotsFolder.Name = "Plots"
	plotsFolder.Parent = root
	local hub = Instance.new("Folder")
	hub.Name = "Hub"
	hub.Parent = root
	local birdsFolder = Instance.new("Folder")
	birdsFolder.Name = "Birds"
	birdsFolder.Parent = root

	-- Plots in two rows facing a central path
	local plots = {}
	local perRow = math.ceil(Config.PlotCount / 2)
	for id = 1, Config.PlotCount do
		local row = id <= perRow and 1 or 2
		local column = (id - 1) % perRow + 1
		local x = (column - (perRow + 1) / 2) * PLOT_SPACING_X
		local cf
		if row == 1 then
			cf = CFrame.new(x, 0, -PLOT_ROW_Z)
		else
			cf = CFrame.new(x, 0, PLOT_ROW_Z) * CFrame.Angles(0, math.pi, 0)
		end
		plots[id] = buildPlot(plotsFolder, id, cf)
	end

	-- Paths
	local pathLength = perRow * PLOT_SPACING_X + 30
	newPart(hub, "MainPath", Vector3.new(pathLength, 0.2, 12), CFrame.new(0, 0.1, 0), PATH, Enum.Material.Pebble)
	for _, plot in ipairs(plots) do
		local front = plot.FrontPoint
		local startZ = front.Z > 0 and 6 or -6
		local length = math.abs(front.Z - startZ)
		newPart(
			hub,
			"PlotPath",
			Vector3.new(8, 0.2, length),
			CFrame.new(front.X, 0.1, (front.Z + startZ) / 2),
			PATH,
			Enum.Material.Pebble
		)
	end

	-- Seed shop
	local shopCf = CFrame.new(-PLOT_SPACING_X / 2, 0, -20)
	local _, shopPrompt = buildShop(hub, shopCf)
	newPart(hub, "ShopPath", Vector3.new(10, 0.2, 9), CFrame.new(shopCf.X, 0.1, -10.5), PATH, Enum.Material.Pebble)

	-- Decorations
	buildBirdBath(hub, CFrame.new(PLOT_SPACING_X / 2, 0, -20))
	buildTitleSign(hub, CFrame.new(PLOT_SPACING_X / 2, 0, 14))
	placeDecorPlant(hub, "MangoTree", Vector3.new(-PLOT_SPACING_X / 2, 0, 20), 1.5)
	local flowerX = perRow * PLOT_SPACING_X / 2 + 6
	for _, x in ipairs({ -flowerX, -flowerX + 5, flowerX - 5, flowerX }) do
		for _, z in ipairs({ -8.5, 8.5 }) do
			placeDecorPlant(hub, "Sunflower", Vector3.new(x, 0, z), 0.9, z > 0 and math.pi or 0)
		end
	end
	for _, position in ipairs({
		Vector3.new(-12, 0, 11),
		Vector3.new(12, 0, 11),
		Vector3.new(-12, 0, -11),
		Vector3.new(12, 0, -11),
	}) do
		placeDecorPlant(hub, "BerryBush", position, 0.8)
	end

	-- a ring of trees around the edge of the map
	local edgeX = perRow * PLOT_SPACING_X / 2 + 20
	local edgeZ = PLOT_ROW_Z + PLOT_HALF_Z + 14
	local treeCount = 0
	local function tree(x, z)
		treeCount += 1
		placeDecorPlant(hub, "MangoTree", Vector3.new(x, 0, z), 1.3 + (treeCount % 3) * 0.15, treeCount * 1.7)
	end
	for i = 0, 8 do
		local x = -edgeX + i * (edgeX * 2 / 8)
		tree(x, -edgeZ)
		tree(x, edgeZ)
	end
	for _, z in ipairs({ -60, -30, 0, 30, 60 }) do
		tree(-edgeX, z)
		tree(edgeX, z)
	end

	return {
		Plots = plots,
		ShopPrompt = shopPrompt,
		ShopTeleport = CFrame.lookAt(
			(shopCf * CFrame.new(0, 3.5, 11)).Position,
			(shopCf * CFrame.new(0, 3.5, 0)).Position
		),
		BirdsFolder = birdsFolder,
	}
end

return WorldBuilder
