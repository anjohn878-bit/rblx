--[[
	WorldBuilder
	Builds the shared map at server start: grass, the ring road, the central
	plaza (fountain, title, leaderboards, spawn) and the decorative trees.
	Plots are arranged in a ring around the plaza, all facing the centre.
]]

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("GameConfig"))
local Build = require(script.Parent.Parent.Util.Build)

local WorldBuilder = {}

local ROAD_OUTER = 145
local PLAZA_RADIUS = 118

export type Board = {
	Rows: Frame,
	Title: TextLabel,
}

local function disk(parent: Instance, radius: number, topY: number, thickness: number, color: Color3, material: Enum.Material, name: string): Part
	return Build.Part(parent, {
		Name = name,
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(thickness, radius * 2, radius * 2),
		CFrame = CFrame.new(0, topY - thickness / 2, 0) * CFrame.Angles(0, 0, math.pi / 2),
		Color = color,
		Material = material,
	})
end

local function tree(parent: Instance, position: Vector3, scale: number)
	local base = CFrame.new(position)
	Build.Cylinder(parent, base, 7 * scale, 1.6 * scale, { Color = Color3.fromRGB(120, 80, 50), Material = Enum.Material.Wood })
	Build.Ball(parent, base * CFrame.new(0, 8.5 * scale, 0), 8 * scale, { Color = Color3.fromRGB(60, 160, 70), Material = Enum.Material.Grass, CanCollide = false })
	Build.Ball(parent, base * CFrame.new(1.5 * scale, 11 * scale, 0.5 * scale), 5.5 * scale, { Color = Color3.fromRGB(85, 185, 85), Material = Enum.Material.Grass, CanCollide = false })
end

local function lamp(parent: Instance, position: Vector3)
	local base = CFrame.new(position)
	Build.Cylinder(parent, base, 12, 0.6, { Color = Color3.fromRGB(50, 55, 65), Material = Enum.Material.Metal })
	local bulb = Build.Ball(parent, base * CFrame.new(0, 12.6, 0), 1.6, { Color = Color3.fromRGB(255, 240, 200), Material = Enum.Material.Neon, CanCollide = false })
	local light = Instance.new("PointLight")
	light.Range = 24
	light.Brightness = 1.4
	light.Color = Color3.fromRGB(255, 230, 180)
	light.Parent = bulb
end

local function bench(parent: Instance, cf: CFrame)
	Build.Part(parent, { Size = Vector3.new(6, 0.4, 1.8), CFrame = cf * CFrame.new(0, 1.6, 0), Color = Color3.fromRGB(150, 100, 60), Material = Enum.Material.Wood })
	Build.Part(parent, { Size = Vector3.new(6, 1.6, 0.3), CFrame = cf * CFrame.new(0, 2.6, 0.8), Color = Color3.fromRGB(150, 100, 60), Material = Enum.Material.Wood })
	for _, x in { -2.5, 2.5 } do
		Build.Part(parent, { Size = Vector3.new(0.4, 1.4, 1.6), CFrame = cf * CFrame.new(x, 0.7, 0), Color = Color3.fromRGB(50, 50, 55), Material = Enum.Material.Metal })
	end
end

local function makeBoard(parent: Instance, cf: CFrame, title: string, color: Color3): Board
	for _, x in { -7.5, 7.5 } do
		Build.Part(parent, { Size = Vector3.new(1, 22, 1), CFrame = cf * CFrame.new(x, 11, 0.6), Color = Color3.fromRGB(60, 60, 70), Material = Enum.Material.Metal })
	end
	local board = Build.Part(parent, {
		Name = "Leaderboard",
		Size = Vector3.new(16, 20, 0.8),
		CFrame = cf * CFrame.new(0, 12, 0),
		Color = Color3.fromRGB(25, 30, 45),
	})
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 25
	gui.LightInfluence = 0
	gui.Parent = board

	local titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "Title"
	titleLabel.Size = UDim2.new(1, 0, 0.13, 0)
	titleLabel.BackgroundColor3 = color
	titleLabel.Text = title
	titleLabel.TextScaled = true
	titleLabel.Font = Enum.Font.FredokaOne
	titleLabel.TextColor3 = Color3.new(1, 1, 1)
	titleLabel.Parent = gui
	local titleStroke = Instance.new("UIStroke")
	titleStroke.Thickness = 3
	titleStroke.Color = Color3.fromRGB(20, 20, 30)
	titleStroke.Parent = titleLabel

	local rows = Instance.new("Frame")
	rows.Name = "Rows"
	rows.BackgroundTransparency = 1
	rows.Position = UDim2.new(0.03, 0, 0.15, 0)
	rows.Size = UDim2.new(0.94, 0, 0.83, 0)
	rows.Parent = gui
	local list = Instance.new("UIListLayout")
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0.01, 0)
	list.Parent = rows

	for i = 1, GameConfig.LeaderboardSize do
		local row = Instance.new("Frame")
		row.Name = "Row" .. i
		row.LayoutOrder = i
		row.Size = UDim2.new(1, 0, 1 / GameConfig.LeaderboardSize - 0.01, 0)
		row.BackgroundColor3 = if i % 2 == 0 then Color3.fromRGB(40, 46, 66) else Color3.fromRGB(34, 40, 58)
		row.Parent = rows
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.2, 0)
		corner.Parent = row

		local rank = Instance.new("TextLabel")
		rank.Name = "Rank"
		rank.BackgroundTransparency = 1
		rank.Size = UDim2.new(0.14, 0, 1, 0)
		rank.Text = if i == 1 then "🥇" elseif i == 2 then "🥈" elseif i == 3 then "🥉" else "#" .. i
		rank.TextScaled = true
		rank.Font = Enum.Font.FredokaOne
		rank.TextColor3 = Color3.fromRGB(255, 220, 120)
		rank.Parent = row

		local name = Instance.new("TextLabel")
		name.Name = "PlayerName"
		name.BackgroundTransparency = 1
		name.Position = UDim2.new(0.15, 0, 0.1, 0)
		name.Size = UDim2.new(0.53, 0, 0.8, 0)
		name.Text = "---"
		name.TextScaled = true
		name.TextXAlignment = Enum.TextXAlignment.Left
		name.Font = Enum.Font.FredokaOne
		name.TextColor3 = Color3.new(1, 1, 1)
		name.Parent = row

		local value = Instance.new("TextLabel")
		value.Name = "Value"
		value.BackgroundTransparency = 1
		value.Position = UDim2.new(0.68, 0, 0.1, 0)
		value.Size = UDim2.new(0.3, 0, 0.8, 0)
		value.Text = ""
		value.TextScaled = true
		value.TextXAlignment = Enum.TextXAlignment.Right
		value.Font = Enum.Font.FredokaOne
		value.TextColor3 = Color3.fromRGB(120, 255, 140)
		value.Parent = row
	end

	return { Rows = rows, Title = titleLabel }
end

local function setupLighting()
	Lighting.ClockTime = 14.5
	Lighting.Brightness = 2.2
	Lighting.Ambient = Color3.fromRGB(95, 95, 105)
	Lighting.OutdoorAmbient = Color3.fromRGB(140, 140, 150)
	Lighting.EnvironmentDiffuseScale = 0.6
	Lighting.EnvironmentSpecularScale = 0.4
	Lighting.GlobalShadows = true
	if not Lighting:FindFirstChildOfClass("Atmosphere") then
		local atmosphere = Instance.new("Atmosphere")
		atmosphere.Density = 0.25
		atmosphere.Haze = 1
		atmosphere.Color = Color3.fromRGB(200, 220, 255)
		atmosphere.Decay = Color3.fromRGB(110, 140, 190)
		atmosphere.Parent = Lighting
	end
	if not Lighting:FindFirstChild("WAADColor") then
		local cc = Instance.new("ColorCorrectionEffect")
		cc.Name = "WAADColor"
		cc.Saturation = 0.15
		cc.Contrast = 0.05
		cc.Brightness = 0.02
		cc.Parent = Lighting
	end
end

-- Returns the CFrame of every plot's front-centre, facing the map centre.
function WorldBuilder.GetPlotCFrames(): { CFrame }
	local result = {}
	for i = 1, GameConfig.PlotCount do
		local angle = (i - 1) * (2 * math.pi / GameConfig.PlotCount)
		local position = Vector3.new(math.sin(angle) * GameConfig.PlotFrontRadius, 0, math.cos(angle) * GameConfig.PlotFrontRadius)
		table.insert(result, CFrame.lookAt(position, Vector3.new(0, 0, 0)))
	end
	return result
end

export type World = {
	Map: Folder,
	Boards: { [string]: Board },
	SpawnCFrame: CFrame,
}

function WorldBuilder.Build(): World
	-- Remove the default template baseplate/spawn if this place still has them.
	for _, name in { "Baseplate", "SpawnLocation" } do
		local existing = workspace:FindFirstChild(name)
		if existing and existing:IsA("BasePart") then
			existing:Destroy()
		end
	end
	setupLighting()

	local map = Build.Folder(workspace, "Map")

	-- Ground + invisible border walls
	Build.Part(map, {
		Name = "Ground",
		Size = Vector3.new(900, 4, 900),
		CFrame = CFrame.new(0, -2, 0),
		Color = Color3.fromRGB(104, 178, 76),
		Material = Enum.Material.Grass,
	})
	for _, wall in { { 0, 450, 900, 2 }, { 0, -450, 900, 2 }, { 450, 0, 2, 900 }, { -450, 0, 2, 900 } } do
		Build.Part(map, {
			Name = "Border",
			Size = Vector3.new(wall[3], 60, wall[4]),
			CFrame = CFrame.new(wall[1], 30, wall[2]),
			Transparency = 1,
			CastShadow = false,
		})
	end

	-- Ring road + plaza
	disk(map, ROAD_OUTER, 0.3, 1, Color3.fromRGB(62, 64, 70), Enum.Material.Asphalt, "Road")
	disk(map, PLAZA_RADIUS + 2, 0.36, 1, Color3.fromRGB(190, 190, 185), Enum.Material.Concrete, "Curb")
	disk(map, PLAZA_RADIUS, 0.42, 1, Color3.fromRGB(222, 214, 196), Enum.Material.Pavement, "Plaza")
	local dashRadius = (ROAD_OUTER + PLAZA_RADIUS + 2) / 2
	local dashes = 48
	for i = 1, dashes do
		local angle = i / dashes * math.pi * 2
		local position = Vector3.new(math.sin(angle) * dashRadius, 0.32, math.cos(angle) * dashRadius)
		local tangent = Vector3.new(math.cos(angle), 0, -math.sin(angle))
		Build.Part(map, {
			Name = "Dash",
			Size = Vector3.new(0.7, 0.05, 6),
			CFrame = CFrame.lookAt(position, position + tangent),
			Color = Color3.fromRGB(250, 220, 90),
			CanCollide = false,
			CastShadow = false,
		})
	end

	-- Fountain with a giant medical cross
	local plazaTop = 0.42
	local fountain = Build.Model(map, "Fountain")
	Build.Cylinder(fountain, CFrame.new(0, plazaTop, 0), 2.2, 34, { Color = Color3.fromRGB(200, 205, 215), Material = Enum.Material.Marble })
	Build.Cylinder(fountain, CFrame.new(0, plazaTop + 2.2, 0), 0.1, 30, { Color = Color3.fromRGB(80, 170, 255), Material = Enum.Material.Glass, Transparency = 0.25, CanCollide = false })
	local pillar = Build.Cylinder(fountain, CFrame.new(0, plazaTop, 0), 16, 4, { Color = Color3.fromRGB(235, 235, 240), Material = Enum.Material.Marble })
	local spray = Instance.new("ParticleEmitter")
	spray.Color = ColorSequence.new(Color3.fromRGB(170, 220, 255))
	spray.Rate = 40
	spray.Lifetime = NumberRange.new(1.2, 1.8)
	spray.Speed = NumberRange.new(14, 18)
	spray.SpreadAngle = Vector2.new(18, 18)
	spray.Acceleration = Vector3.new(0, -30, 0)
	spray.EmissionDirection = Enum.NormalId.Right
	spray.Size = NumberSequence.new(0.5, 0.1)
	spray.Transparency = NumberSequence.new(0.2, 1)
	spray.Parent = pillar
	local crossColor = Color3.fromRGB(235, 50, 60)
	Build.Part(fountain, { Size = Vector3.new(3, 12, 3), CFrame = CFrame.new(0, plazaTop + 22, 0), Color = crossColor, Material = Enum.Material.Neon })
	Build.Part(fountain, { Size = Vector3.new(12, 3, 3), CFrame = CFrame.new(0, plazaTop + 23, 0), Color = crossColor, Material = Enum.Material.Neon })
	Build.Part(fountain, { Size = Vector3.new(3, 12, 12), CFrame = CFrame.new(0, plazaTop + 22, 0), Color = crossColor, Material = Enum.Material.Neon, Transparency = 1, CanCollide = false })
	local crossLight = Instance.new("PointLight")
	crossLight.Color = crossColor
	crossLight.Range = 30
	crossLight.Brightness = 2
	crossLight.Parent = pillar

	-- Floating title visible from every hospital
	local titleAnchor = Build.Part(map, {
		Name = "TitleAnchor",
		Size = Vector3.new(1, 1, 1),
		CFrame = CFrame.new(0, plazaTop + 34, 0),
		Transparency = 1,
		CanCollide = false,
		CastShadow = false,
	})
	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.new(60, 0, 12, 0)
	billboard.LightInfluence = 0
	billboard.MaxDistance = 1000
	billboard.Parent = titleAnchor
	local title = Instance.new("TextLabel")
	title.Size = UDim2.fromScale(1, 1)
	title.BackgroundTransparency = 1
	title.Text = "🏥 WORK AS A DOCTOR 🩺"
	title.TextScaled = true
	title.Font = Enum.Font.FredokaOne
	title.TextColor3 = Color3.new(1, 1, 1)
	title.Parent = billboard
	local titleStroke = Instance.new("UIStroke")
	titleStroke.Thickness = 4
	titleStroke.Color = Color3.fromRGB(200, 40, 60)
	titleStroke.Parent = title

	-- Leaderboards facing outwards towards the hospitals
	local boards: { [string]: Board } = {}
	local boardDefs = {
		{ Key = "Richest", Title = "🏆 Richest Doctor", Color = Color3.fromRGB(60, 180, 90), Angle = math.rad(30) },
		{ Key = "Treated", Title = "🏆 Most Patients Treated", Color = Color3.fromRGB(60, 140, 230), Angle = math.rad(150) },
		{ Key = "Level", Title = "🏆 Highest Hospital Level", Color = Color3.fromRGB(230, 140, 40), Angle = math.rad(270) },
	}
	for _, def in boardDefs do
		local direction = Vector3.new(math.sin(def.Angle), 0, math.cos(def.Angle))
		local position = direction * 48 + Vector3.new(0, plazaTop, 0)
		boards[def.Key] = makeBoard(map, CFrame.lookAt(position, position + direction), def.Title, def.Color)
	end

	-- Lamps, benches and trees around the plaza
	for i = 1, 12 do
		local angle = (i + 0.5) / 12 * math.pi * 2
		lamp(map, Vector3.new(math.sin(angle) * (PLAZA_RADIUS - 4), plazaTop, math.cos(angle) * (PLAZA_RADIUS - 4)))
	end
	for i = 1, 6 do
		local angle = i / 6 * math.pi * 2 + math.rad(30)
		local position = Vector3.new(math.sin(angle) * 26, plazaTop, math.cos(angle) * 26)
		bench(map, CFrame.lookAt(position, Vector3.new(0, plazaTop, 0)) * CFrame.Angles(0, math.pi, 0))
	end
	for i = 1, GameConfig.PlotCount do
		local angle = (i - 0.5) / GameConfig.PlotCount * math.pi * 2
		for _, radius in { 85, 175, 230, 290, 350 } do
			if radius < PLAZA_RADIUS or radius > ROAD_OUTER + 20 then
				local wiggle = (radius % 7) * 0.02
				local position = Vector3.new(math.sin(angle + wiggle) * radius, if radius < PLAZA_RADIUS then plazaTop else 0, math.cos(angle + wiggle) * radius)
				tree(map, position, if radius < PLAZA_RADIUS then 0.8 else 1 + (radius % 3) * 0.15)
			end
		end
	end
	for i = 1, 36 do
		local angle = i / 36 * math.pi * 2
		tree(map, Vector3.new(math.sin(angle) * 400, 0, math.cos(angle) * 400), 1.2)
	end

	-- Spawn pad (players are teleported to their own hospital right away)
	local spawnPosition = Vector3.new(math.sin(math.rad(90)) * 70, plazaTop + 0.2, math.cos(math.rad(90)) * 70)
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "PlazaSpawn"
	spawn.Anchored = true
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Size = Vector3.new(10, 0.4, 10)
	spawn.CFrame = CFrame.new(spawnPosition)
	spawn.Color = Color3.fromRGB(255, 255, 255)
	spawn.Material = Enum.Material.SmoothPlastic
	spawn.TopSurface = Enum.SurfaceType.Smooth
	spawn.Parent = map

	return {
		Map = map,
		Boards = boards,
		SpawnCFrame = CFrame.new(spawnPosition + Vector3.new(0, 4, 0)),
	}
end

return WorldBuilder
