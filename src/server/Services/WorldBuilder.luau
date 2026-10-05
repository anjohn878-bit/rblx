--[[
	WorldBuilder
	Builds the whole map out of plain parts: the lobby plaza, the skate shop,
	the rebirth crystal, the leaderboard, four themed rinks with their gates,
	paths, lamps, trees and the mountain backdrop.

	The build script (.lune/build.luau) runs this under Lune to bake the map
	into Place1.rbxl / Place1.rbxlx, so the map can be edited in Studio. If the
	Map folder is ever missing (for example in a fresh Rojo-synced place) the
	server runs it on startup instead. Only plain instance creation is used
	here so the same code works in both environments.
]]

local WorldBuilder = {}

local CYLINDER_UP = CFrame.Angles(0, 0, math.pi / 2)
local WHITE = Color3.fromRGB(255, 255, 255)
local SNOW = Color3.fromRGB(240, 245, 252)
local DARK_METAL = Color3.fromRGB(45, 50, 62)
local LAMP_GLOW = Color3.fromRGB(255, 222, 160)
local ENTRANCE_WIDTH = 24
local BOARD_THICKNESS = 1.5
local LOCK_OUTSET = 4

-- Deterministic random numbers, so every build produces the same map.
local function newRandom(seed)
	local state = seed
	return function(min, max)
		state = (state * 16807) % 2147483647
		return min + (max - min) * (state / 2147483647)
	end
end

local function commas(number)
	local text = tostring(math.floor(number))
	local formatted = string.reverse((string.gsub(string.reverse(text), "(%d%d%d)", "%1,")))
	return (string.gsub(formatted, "^,", ""))
end

local function multiplierText(value)
	return "x" .. tostring(value)
end

local function folder(name, parent)
	local instance = Instance.new("Folder")
	instance.Name = name
	instance.Parent = parent
	return instance
end

local function part(parent, props, className)
	local instance = Instance.new(className or "Part")
	instance.Anchored = true
	instance.TopSurface = Enum.SurfaceType.Smooth
	instance.BottomSurface = Enum.SurfaceType.Smooth
	-- Shape has to be set before Size or Roblox resizes the part to fit the shape.
	if props.Shape then
		instance.Shape = props.Shape
	end
	for key, value in props do
		if key ~= "Shape" then
			instance[key] = value
		end
	end
	instance.Parent = parent
	return instance
end

-- Purely visual part: no collisions, no raycasts, no touch events.
local function decor(parent, props, className)
	local instance = part(parent, props, className)
	instance.CanCollide = false
	instance.CanQuery = false
	instance.CanTouch = false
	return instance
end

local function cylinder(parent, position, height, diameter, props)
	props.Shape = Enum.PartType.Cylinder
	props.Size = Vector3.new(height, diameter, diameter)
	props.CFrame = CFrame.new(position) * CYLINDER_UP
	return part(parent, props)
end

local function ball(parent, position, diameter, props)
	props.Shape = Enum.PartType.Ball
	props.Size = Vector3.new(diameter, diameter, diameter)
	props.CFrame = CFrame.new(position)
	return part(parent, props)
end

-- A CFrame at `position` whose front (-Z) faces `target` on the horizontal plane.
local function facing(position, target)
	local delta = target - position
	return CFrame.new(position) * CFrame.Angles(0, math.atan2(-delta.X, -delta.Z), 0)
end

local function light(parent, className, props)
	local instance = Instance.new(className)
	instance.Shadows = false
	for key, value in props do
		instance[key] = value
	end
	instance.Parent = parent
	return instance
end

-- lines = { { Text, Weight, Color? }, ... } stacked top to bottom.
local function addText(target, face, lines, options)
	options = options or {}
	local gui = Instance.new("SurfaceGui")
	gui.Name = options.Name or "Sign"
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = options.PixelsPerStud or 25
	gui.LightInfluence = 0
	gui.Parent = target

	local totalWeight = 0
	for _, line in lines do
		totalWeight += line[2]
	end

	local offset = 0
	for index, line in lines do
		local label = Instance.new("TextLabel")
		label.Name = "Line" .. index
		label.BackgroundTransparency = 1
		label.Position = UDim2.fromScale(0.04, offset / totalWeight)
		label.Size = UDim2.fromScale(0.92, line[2] / totalWeight)
		label.FontFace = Font.fromEnum(Enum.Font.FredokaOne)
		label.Text = line[1]
		label.TextScaled = true
		label.TextColor3 = line[3] or WHITE
		label.Parent = gui

		local stroke = Instance.new("UIStroke")
		stroke.Thickness = options.StrokeThickness or 3
		stroke.Color = options.StrokeColor or Color3.fromRGB(20, 30, 55)
		stroke.Parent = label

		offset += line[2]
	end

	return gui
end

local function addPrompt(target, props, attributes)
	local prompt = Instance.new("ProximityPrompt")
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	for key, value in props do
		prompt[key] = value
	end
	for key, value in attributes do
		prompt:SetAttribute(key, value)
	end
	prompt.Parent = target
	return prompt
end

-- Four walls around a width x length rectangle in the local frame `cf`,
-- optionally leaving a gap centred on the +Z side for an entrance.
local function ring(parent, cf, width, length, options)
	local thickness = options.Thickness
	local height = options.Height
	local y = (options.Bottom or 0) + height / 2
	local halfWidth = width / 2 + (options.Outset or 0)
	local halfLength = length / 2 + (options.Outset or 0)
	local gap = options.Gap or 0

	local segments = {
		{
			Vector3.new(0, y, -halfLength - thickness / 2),
			Vector3.new(halfWidth * 2 + thickness * 2, height, thickness),
		},
		{ Vector3.new(-halfWidth - thickness / 2, y, 0), Vector3.new(thickness, height, halfLength * 2) },
		{ Vector3.new(halfWidth + thickness / 2, y, 0), Vector3.new(thickness, height, halfLength * 2) },
	}
	if gap > 0 then
		local segmentLength = (halfWidth * 2 - gap) / 2 + thickness
		local x = gap / 2 + segmentLength / 2
		table.insert(
			segments,
			{ Vector3.new(-x, y, halfLength + thickness / 2), Vector3.new(segmentLength, height, thickness) }
		)
		table.insert(
			segments,
			{ Vector3.new(x, y, halfLength + thickness / 2), Vector3.new(segmentLength, height, thickness) }
		)
	else
		table.insert(segments, {
			Vector3.new(0, y, halfLength + thickness / 2),
			Vector3.new(halfWidth * 2 + thickness * 2, height, thickness),
		})
	end

	for _, segment in segments do
		local wall = part(parent, {
			Name = options.Name or "Wall",
			Size = segment[2],
			CFrame = cf * CFrame.new(segment[1]),
			Material = options.Material or Enum.Material.SmoothPlastic,
			Color = options.Color or WHITE,
			Transparency = options.Transparency or 0,
		})
		if options.Invisible then
			wall.CanQuery = false
			wall.CanTouch = false
			wall.CastShadow = false
		end
	end
end

local function distanceToSegment(point, a, b)
	local ab = b - a
	local t = math.clamp((point - a):Dot(ab) / ab:Dot(ab), 0, 1)
	return (point - (a + ab * t)).Magnitude
end

-- Geometry -----------------------------------------------------------------

function WorldBuilder.rinkCFrame(rink, lobbyCenter)
	local toLobby = lobbyCenter - rink.Center
	local yaw = math.atan2(toLobby.X, toLobby.Z)
	-- Local +Z points at the lobby, which is where the entrance goes.
	return CFrame.new(rink.Center) * CFrame.Angles(0, yaw, 0)
end

-- Props ---------------------------------------------------------------------

local function lamp(parent, position, glow)
	local lampFolder = folder("Lamp", parent)
	cylinder(lampFolder, position + Vector3.new(0, 6, 0), 12, 0.7, {
		Name = "Post",
		Material = Enum.Material.Metal,
		Color = DARK_METAL,
	})
	decor(lampFolder, {
		Name = "Cap",
		Size = Vector3.new(2, 0.4, 2),
		CFrame = CFrame.new(position + Vector3.new(0, 12.2, 0)),
		Material = Enum.Material.Metal,
		Color = DARK_METAL,
	})
	decor(lampFolder, {
		Name = "SnowCap",
		Size = Vector3.new(2.2, 0.35, 2.2),
		CFrame = CFrame.new(position + Vector3.new(0, 12.55, 0)),
		Material = Enum.Material.Snow,
		Color = SNOW,
	})
	local bulb = ball(lampFolder, position + Vector3.new(0, 11.2, 0), 1.6, {
		Name = "Bulb",
		Material = Enum.Material.Neon,
		Color = glow or LAMP_GLOW,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		CastShadow = false,
	})
	light(bulb, "PointLight", { Range = 22, Brightness = 1.3, Color = glow or LAMP_GLOW })
	return lampFolder
end

local function tree(parent, position, scale, random)
	local treeFolder = folder("PineTree", parent)
	local trunkHeight = 4 * scale
	cylinder(treeFolder, position + Vector3.new(0, trunkHeight / 2, 0), trunkHeight, 1.6 * scale, {
		Name = "Trunk",
		Material = Enum.Material.Wood,
		Color = Color3.fromRGB(95, 65, 45),
	})

	local green = Color3.fromRGB(40, 95 + math.floor(random(0, 30)), 60)
	local y = trunkHeight
	for tier = 1, 3 do
		local diameter = (11 - tier * 2.6) * scale
		local height = 3.2 * scale
		cylinder(treeFolder, position + Vector3.new(0, y + height / 2, 0), height, diameter, {
			Name = "Leaves",
			Material = Enum.Material.Grass,
			Color = green,
		})
		local cap = cylinder(
			treeFolder,
			position + Vector3.new(0, y + height + 0.25 * scale, 0),
			0.5 * scale,
			diameter * 0.82,
			{
				Name = "Snow",
				Material = Enum.Material.Snow,
				Color = SNOW,
			}
		)
		cap.CanCollide = false
		cap.CanQuery = false
		y += height * 0.82
	end
	return treeFolder
end

local function snowman(parent, position, lookAt, scale)
	local cf = facing(position, lookAt)
	local model = folder("Snowman", parent)
	local function at(x, y, z)
		return (cf * CFrame.new(x * scale, y * scale, z * scale)).Position
	end

	ball(model, at(0, 2, 0), 5 * scale, { Name = "Base", Material = Enum.Material.Snow, Color = SNOW })
	ball(model, at(0, 5.3, 0), 3.8 * scale, { Name = "Body", Material = Enum.Material.Snow, Color = SNOW })
	ball(model, at(0, 7.9, 0), 2.8 * scale, { Name = "Head", Material = Enum.Material.Snow, Color = SNOW })

	for _, x in { -0.45, 0.45 } do
		decor(model, {
			Shape = Enum.PartType.Ball,
			Name = "Eye",
			Size = Vector3.one * 0.35 * scale,
			CFrame = CFrame.new(at(x, 8.25, -1.22)),
			Color = Color3.fromRGB(20, 20, 25),
		})
	end
	for index = 1, 3 do
		decor(model, {
			Shape = Enum.PartType.Ball,
			Name = "Button",
			Size = Vector3.one * 0.4 * scale,
			CFrame = CFrame.new(at(0, 4.5 + index * 0.55, -1.75 + math.abs(index - 2) * 0.12)),
			Color = Color3.fromRGB(20, 20, 25),
		})
	end
	decor(model, {
		Shape = Enum.PartType.Cylinder,
		Name = "Nose",
		Size = Vector3.new(1.2, 0.35, 0.35) * scale,
		CFrame = CFrame.new(at(0, 7.9, -1.6)) * (cf - cf.Position) * CFrame.Angles(0, math.pi / 2, 0),
		Color = Color3.fromRGB(255, 140, 40),
	})
	decor(model, {
		Shape = Enum.PartType.Cylinder,
		Name = "Scarf",
		Size = Vector3.new(0.6, 3.1, 3.1) * scale,
		CFrame = CFrame.new(at(0, 6.65, 0)) * CYLINDER_UP,
		Material = Enum.Material.Fabric,
		Color = Color3.fromRGB(210, 50, 60),
	})
	decor(model, {
		Shape = Enum.PartType.Cylinder,
		Name = "HatBrim",
		Size = Vector3.new(0.25, 3, 3) * scale,
		CFrame = CFrame.new(at(0, 9.15, 0)) * CYLINDER_UP,
		Color = Color3.fromRGB(25, 25, 30),
	})
	decor(model, {
		Shape = Enum.PartType.Cylinder,
		Name = "Hat",
		Size = Vector3.new(1.8, 2, 2) * scale,
		CFrame = CFrame.new(at(0, 10.1, 0)) * CYLINDER_UP,
		Color = Color3.fromRGB(25, 25, 30),
	})
	return model
end

local function iceCrystals(parent, position, scale, random)
	local cluster = folder("IceCrystals", parent)
	for _ = 1, 3 do
		local width = random(1.5, 3) * scale
		local height = random(6, 16) * scale
		local offset = Vector3.new(random(-3, 3), 0, random(-3, 3)) * scale
		local tilt = CFrame.Angles(math.rad(random(-25, 25)), math.rad(random(0, 90)), math.rad(random(-25, 25)))
		part(cluster, {
			Name = "Crystal",
			Size = Vector3.new(width, height, width),
			CFrame = CFrame.new(position + offset) * tilt * CFrame.new(0, height * 0.35, 0),
			Material = Enum.Material.Glacier,
			Color = Color3.fromRGB(150, 220, 255),
			Transparency = 0.15,
			Reflectance = 0.1,
		})
	end
	return cluster
end

local function mountain(parent, position, size, yaw, color, material)
	-- A cube balanced on its corner reads as a jagged peak from far away.
	local cornerUp = CFrame.Angles(0, yaw, 0)
		* CFrame.Angles(0, 0, math.rad(54.7356))
		* CFrame.Angles(0, math.rad(45), 0)
	decor(parent, {
		Name = "Mountain",
		Size = Vector3.new(size, size, size),
		CFrame = CFrame.new(position + Vector3.new(0, -size * 0.35, 0)) * cornerUp,
		Material = material,
		Color = color,
		CastShadow = false,
	})
end

-- Lighting & baseplate ---------------------------------------------------------

local function configureLighting()
	local lighting = game:GetService("Lighting")
	lighting.ClockTime = 15.2
	lighting.Brightness = 2.4
	lighting.Ambient = Color3.fromRGB(105, 120, 150)
	lighting.OutdoorAmbient = Color3.fromRGB(150, 165, 200)
	lighting.ColorShift_Top = Color3.fromRGB(215, 230, 255)
	lighting.ColorShift_Bottom = Color3.fromRGB(180, 200, 235)
	lighting.EnvironmentDiffuseScale = 0.7
	lighting.EnvironmentSpecularScale = 1
	lighting.GeographicLatitude = 55
	-- Technology can only be changed in Studio, not by a running game.
	pcall(function()
		lighting.Technology = Enum.Technology.Future
	end)

	local atmosphere = lighting:FindFirstChildOfClass("Atmosphere")
	if not atmosphere then
		atmosphere = Instance.new("Atmosphere")
		atmosphere.Parent = lighting
	end
	atmosphere.Density = 0.32
	atmosphere.Offset = 0.1
	atmosphere.Color = Color3.fromRGB(205, 225, 250)
	atmosphere.Decay = Color3.fromRGB(120, 150, 195)
	atmosphere.Glare = 0.15
	atmosphere.Haze = 1.6

	local bloom = lighting:FindFirstChildOfClass("BloomEffect")
	if bloom then
		bloom.Intensity = 0.6
		bloom.Size = 30
		bloom.Threshold = 1.6
	end
end

local function restyleWorkspace()
	local baseplate = workspace:FindFirstChild("Baseplate")
	if baseplate and baseplate:IsA("BasePart") then
		baseplate.Material = Enum.Material.Snow
		baseplate.Color = Color3.fromRGB(236, 242, 250)
		local texture = baseplate:FindFirstChildOfClass("Texture")
		if texture then
			texture:Destroy()
		end
	end

	-- The template's default spawn is replaced by the one in the lobby.
	local defaultSpawn = workspace:FindFirstChild("SpawnLocation")
	if defaultSpawn then
		defaultSpawn:Destroy()
	end
end

-- Lobby -----------------------------------------------------------------------------

local function buildSkateShop(parent, cf, Config)
	local shop = folder("SkateShop", parent)
	local function at(x, y, z)
		return cf * CFrame.new(x, y, z)
	end
	local wood = Color3.fromRGB(150, 100, 65)

	part(shop, {
		Name = "Floor",
		Size = Vector3.new(20, 0.8, 12),
		CFrame = at(0, 0.4, 0),
		Material = Enum.Material.WoodPlanks,
		Color = wood,
	})
	part(shop, {
		Name = "BackWall",
		Size = Vector3.new(20, 11, 1),
		CFrame = at(0, 6.3, 5.5),
		Material = Enum.Material.WoodPlanks,
		Color = Color3.fromRGB(125, 85, 55),
	})
	for _, x in { -9.5, 9.5 } do
		part(shop, {
			Name = "SideWall",
			Size = Vector3.new(1, 11, 12),
			CFrame = at(x, 6.3, 0),
			Material = Enum.Material.WoodPlanks,
			Color = Color3.fromRGB(125, 85, 55),
		})
	end
	part(shop, {
		Name = "Counter",
		Size = Vector3.new(16, 3.4, 2.4),
		CFrame = at(0, 2.5, -3.5),
		Material = Enum.Material.SmoothPlastic,
		Color = Color3.fromRGB(70, 150, 230),
	})
	part(shop, {
		Name = "CounterTop",
		Size = Vector3.new(16.6, 0.4, 3),
		CFrame = at(0, 4.4, -3.5),
		Material = Enum.Material.Wood,
		Color = wood,
	})

	-- Striped roof with snow on top.
	for index = 0, 4 do
		part(shop, {
			Name = "Roof",
			Size = Vector3.new(4.4, 1, 14),
			CFrame = at(-8.8 + index * 4.4, 12.3, -0.5),
			Color = if index % 2 == 0 then Color3.fromRGB(220, 60, 70) else WHITE,
		})
	end
	decor(shop, {
		Name = "RoofSnow",
		Size = Vector3.new(22.4, 0.7, 14.4),
		CFrame = at(0, 13.1, -0.5),
		Material = Enum.Material.Snow,
		Color = SNOW,
	})

	local sign = part(
		shop,
		{ Name = "Sign", Size = Vector3.new(18, 4, 0.6), CFrame = at(0, 15.5, 1), Color = Color3.fromRGB(30, 45, 80) }
	)
	addText(sign, Enum.NormalId.Front, { { "⛸ SKATE SHOP", 1 } }, { PixelsPerStud = 30 })
	addText(sign, Enum.NormalId.Back, { { "⛸ SKATE SHOP", 1 } }, { PixelsPerStud = 30 })

	-- A shelf of display skates in each tier's colours.
	part(shop, {
		Name = "Shelf",
		Size = Vector3.new(18, 0.4, 1.6),
		CFrame = at(0, 6.5, 4.4),
		Material = Enum.Material.Wood,
		Color = wood,
	})
	for index = 1, math.min(5, #Config.Skates) do
		local skate = Config.Skates[index]
		local x = -7.2 + (index - 1) * 3.6
		decor(shop, {
			Name = "DisplayBoot",
			Size = Vector3.new(1.2, 1.3, 2),
			CFrame = at(x, 7.55, 4.2),
			Color = skate.BootColor,
		})
		decor(shop, {
			Name = "DisplayBlade",
			Size = Vector3.new(0.2, 0.3, 2.4),
			CFrame = at(x, 6.85, 4.2),
			Material = Enum.Material.Metal,
			Color = skate.BladeColor,
		})
	end

	local lantern = decor(shop, {
		Name = "Lantern",
		Size = Vector3.new(1, 1, 1),
		CFrame = at(0, 11.3, 0),
		Material = Enum.Material.Neon,
		Color = LAMP_GLOW,
	})
	light(lantern, "PointLight", { Range = 18, Brightness = 1.2, Color = LAMP_GLOW })

	local promptPart =
		decor(shop, { Name = "PromptAnchor", Size = Vector3.new(4, 4, 1), CFrame = at(0, 3, -5.2), Transparency = 1 })
	addPrompt(promptPart, { ActionText = "Open Shop", ObjectText = "Skate Shop" }, { Action = "OpenShop" })
end

local function buildRebirthCrystal(parent, cf)
	local altar = folder("RebirthCrystal", parent)
	local position = cf.Position
	local purple = Color3.fromRGB(170, 110, 255)

	cylinder(
		altar,
		position + Vector3.new(0, 0.5, 0),
		1,
		18,
		{ Name = "Base", Material = Enum.Material.Marble, Color = Color3.fromRGB(235, 235, 245) }
	)
	cylinder(
		altar,
		position + Vector3.new(0, 1.5, 0),
		1,
		12,
		{ Name = "Step", Material = Enum.Material.Glacier, Color = Color3.fromRGB(200, 180, 255) }
	)

	local crystal = part(altar, {
		Name = "Crystal",
		Size = Vector3.new(4, 10, 4),
		CFrame = CFrame.new(position + Vector3.new(0, 8, 0)) * CFrame.Angles(0, math.pi / 4, 0),
		Material = Enum.Material.Glass,
		Color = purple,
		Transparency = 0.2,
	})
	decor(altar, {
		Name = "Core",
		Size = Vector3.new(1.8, 7, 1.8),
		CFrame = crystal.CFrame,
		Material = Enum.Material.Neon,
		Color = Color3.fromRGB(215, 170, 255),
	})
	for side = -1, 1, 2 do
		part(altar, {
			Name = "Shard",
			Size = Vector3.new(1.6, 5, 1.6),
			CFrame = CFrame.new(position + Vector3.new(side * 3.2, 4.5, 0))
				* CFrame.Angles(0, math.pi / 4, math.rad(side * -20)),
			Material = Enum.Material.Glass,
			Color = purple,
			Transparency = 0.25,
		})
	end
	for index = 0, 7 do
		local angle = index / 8 * math.pi * 2
		ball(altar, position + Vector3.new(math.cos(angle) * 5.5, 7, math.sin(angle) * 5.5), 0.8, {
			Name = "Orb",
			Material = Enum.Material.Neon,
			Color = Color3.fromRGB(230, 200, 255),
			CanCollide = false,
			CanQuery = false,
			CanTouch = false,
		})
	end
	light(crystal, "PointLight", { Range = 22, Brightness = 2, Color = purple })

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "Title"
	billboard.Size = UDim2.fromScale(14, 3.5)
	billboard.StudsOffset = Vector3.new(0, 8, 0)
	billboard.LightInfluence = 0
	billboard.MaxDistance = 160
	billboard.Parent = crystal
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.FontFace = Font.fromEnum(Enum.Font.FredokaOne)
	label.Text = "🔄 REBIRTH"
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(235, 215, 255)
	label.Parent = billboard
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Color = Color3.fromRGB(60, 25, 110)
	stroke.Parent = label

	local promptPart = decor(altar, {
		Name = "PromptAnchor",
		Size = Vector3.new(4, 4, 4),
		CFrame = CFrame.new(position + Vector3.new(0, 4, 0)),
		Transparency = 1,
	})
	addPrompt(promptPart, { ActionText = "Rebirth", ObjectText = "Rebirth Crystal" }, { Action = "OpenRebirth" })
end

local function buildLeaderboard(parent, cf)
	local board = folder("Leaderboard", parent)
	local function at(x, y, z)
		return cf * CFrame.new(x, y, z)
	end
	for _, x in { -13, 13 } do
		part(board, {
			Name = "Post",
			Size = Vector3.new(1.2, 22, 1.2),
			CFrame = at(x, 11, 0.6),
			Material = Enum.Material.Metal,
			Color = DARK_METAL,
		})
	end
	decor(board, {
		Name = "Frame",
		Size = Vector3.new(28.8, 18.8, 0.6),
		CFrame = at(0, 13, 0.4),
		Material = Enum.Material.Neon,
		Color = Color3.fromRGB(255, 200, 80),
	})
	local panel = part(board, {
		Name = "LeaderboardBoard",
		Size = Vector3.new(28, 18, 1),
		CFrame = at(0, 13, 0),
		Color = Color3.fromRGB(22, 32, 58),
	})

	local gui = Instance.new("SurfaceGui")
	gui.Name = "Leaderboard"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 25
	gui.LightInfluence = 0
	gui.Parent = panel

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.Position = UDim2.fromScale(0.05, 0.02)
	title.Size = UDim2.fromScale(0.9, 0.15)
	title.FontFace = Font.fromEnum(Enum.Font.FredokaOne)
	title.Text = "🏆 TOP SKATERS"
	title.TextScaled = true
	title.TextColor3 = Color3.fromRGB(255, 215, 100)
	title.Parent = gui

	local subtitle = Instance.new("TextLabel")
	subtitle.Name = "Subtitle"
	subtitle.BackgroundTransparency = 1
	subtitle.Position = UDim2.fromScale(0.05, 0.17)
	subtitle.Size = UDim2.fromScale(0.9, 0.07)
	subtitle.FontFace = Font.fromEnum(Enum.Font.GothamMedium)
	subtitle.Text = "Lifetime snowflakes earned"
	subtitle.TextScaled = true
	subtitle.TextColor3 = Color3.fromRGB(180, 200, 235)
	subtitle.Parent = gui

	local list = Instance.new("Frame")
	list.Name = "List"
	list.BackgroundTransparency = 1
	list.Position = UDim2.fromScale(0.05, 0.26)
	list.Size = UDim2.fromScale(0.9, 0.72)
	list.Parent = gui

	for rank = 1, 10 do
		local row = Instance.new("Frame")
		row.Name = "Row" .. rank
		row.BackgroundColor3 = WHITE
		row.BackgroundTransparency = if rank % 2 == 0 then 0.94 else 1
		row.BorderSizePixel = 0
		row.Position = UDim2.fromScale(0, (rank - 1) / 10)
		row.Size = UDim2.fromScale(1, 0.1)
		row.Parent = list

		local columns = {
			{ "Rank", "#" .. rank, 0, 0.12, Enum.TextXAlignment.Left },
			{ "PlayerName", "—", 0.12, 0.56, Enum.TextXAlignment.Left },
			{ "Value", "", 0.68, 0.32, Enum.TextXAlignment.Right },
		}
		for _, column in columns do
			local label = Instance.new("TextLabel")
			label.Name = column[1]
			label.BackgroundTransparency = 1
			label.Position = UDim2.fromScale(column[3], 0.1)
			label.Size = UDim2.fromScale(column[4], 0.8)
			label.FontFace = Font.fromEnum(Enum.Font.GothamBold)
			label.Text = column[2]
			label.TextScaled = true
			label.TextXAlignment = column[5]
			label.TextColor3 = if rank <= 3 then Color3.fromRGB(255, 225, 140) else WHITE
			label.Parent = row
		end
	end
end

local function buildTitleArch(parent, center, radius, accent)
	local arch = folder("TitleArch", parent)
	local z = center.Z - radius - 6
	for _, x in { -13, 13 } do
		part(arch, {
			Name = "Pillar",
			Size = Vector3.new(4, 24, 4),
			CFrame = CFrame.new(center.X + x, 12, z),
			Material = Enum.Material.Glacier,
			Color = Color3.fromRGB(175, 220, 250),
		})
		ball(
			arch,
			Vector3.new(center.X + x, 24.5, z),
			3.2,
			{ Name = "Orb", Material = Enum.Material.Neon, Color = accent, CanCollide = false }
		)
	end
	local beam = part(arch, {
		Name = "Beam",
		Size = Vector3.new(34, 7, 3),
		CFrame = CFrame.new(center.X, 27.5, z),
		Color = Color3.fromRGB(30, 50, 95),
	})
	decor(arch, {
		Name = "Trim",
		Size = Vector3.new(34.4, 0.5, 3.2),
		CFrame = CFrame.new(center.X, 24.1, z),
		Material = Enum.Material.Neon,
		Color = accent,
	})
	decor(arch, {
		Name = "Snow",
		Size = Vector3.new(34.6, 0.8, 3.6),
		CFrame = CFrame.new(center.X, 31.4, z),
		Material = Enum.Material.Snow,
		Color = SNOW,
	})
	local lines = {
		{ "ICE SKATING SIMULATOR", 0.66 },
		{ "❄ skate • spin • collect ❄", 0.34, Color3.fromRGB(190, 225, 255) },
	}
	addText(beam, Enum.NormalId.Back, lines, { PixelsPerStud = 30 })
	addText(beam, Enum.NormalId.Front, lines, { PixelsPerStud = 30 })
end

local function buildLobby(map, Config)
	local lobby = folder("Lobby", map)
	local center = Config.Lobby.Center
	local radius = Config.Lobby.PlazaRadius
	local accent = Color3.fromRGB(110, 190, 255)

	cylinder(
		lobby,
		center + Vector3.new(0, -0.05, 0),
		0.6,
		(radius + 3) * 2,
		{ Name = "PlazaRim", Material = Enum.Material.Slate, Color = Color3.fromRGB(150, 160, 182) }
	)
	cylinder(
		lobby,
		center,
		0.6,
		radius * 2,
		{ Name = "Plaza", Material = Enum.Material.Cobblestone, Color = Color3.fromRGB(200, 207, 220) }
	)
	cylinder(
		lobby,
		center + Vector3.new(0, 0.02, 0),
		0.6,
		34,
		{ Name = "Medallion", Material = Enum.Material.Marble, Color = Color3.fromRGB(185, 220, 250) }
	)
	for index = 0, 2 do
		decor(lobby, {
			Name = "SnowflakeArm",
			Size = Vector3.new(30, 0.06, 1.4),
			CFrame = CFrame.new(center + Vector3.new(0, 0.34, 0)) * CFrame.Angles(0, index * math.pi / 3, 0),
			Material = Enum.Material.Neon,
			Color = accent,
		})
	end

	local spawn = part(lobby, {
		Name = "Spawn",
		Size = Vector3.new(10, 0.6, 10),
		CFrame = CFrame.new(center + Vector3.new(0, 0.62, 0)),
		Material = Enum.Material.Glass,
		Color = Color3.fromRGB(160, 215, 255),
		Transparency = 0.15,
	}, "SpawnLocation")
	spawn.Duration = 0
	spawn.Neutral = true

	buildTitleArch(lobby, center, radius, accent)
	buildSkateShop(lobby, facing(center + Vector3.new(-34, 0.0, 22), center), Config)
	buildRebirthCrystal(lobby, facing(center + Vector3.new(34, 0, 22), center))
	buildLeaderboard(lobby, facing(center + Vector3.new(0, 0, radius - 6), center))

	-- Lamps around the plaza, leaving the path openings clear.
	local pathAngles = {}
	for _, rink in Config.Rinks do
		local toRink = rink.Center - center
		table.insert(pathAngles, math.atan2(toRink.Z, toRink.X))
	end
	local lamps = folder("Lamps", lobby)
	for index = 0, 15 do
		local angle = index / 16 * math.pi * 2 + math.pi / 16
		local blocked = false
		for _, pathAngle in pathAngles do
			local difference = math.abs((angle - pathAngle + math.pi) % (math.pi * 2) - math.pi)
			if difference < math.rad(16) then
				blocked = true
			end
		end
		if not blocked then
			lamp(lamps, center + Vector3.new(math.cos(angle) * (radius - 2.5), 0.3, math.sin(angle) * (radius - 2.5)))
		end
	end

	-- A couple of benches facing the spawn.
	for _, x in { -18, 18 } do
		local bench = folder("Bench", lobby)
		local cf = facing(center + Vector3.new(x, 0.3, -20), center)
		part(bench, {
			Name = "Seat",
			Size = Vector3.new(7, 0.5, 2),
			CFrame = cf * CFrame.new(0, 1.6, 0),
			Material = Enum.Material.WoodPlanks,
			Color = Color3.fromRGB(150, 100, 65),
		})
		part(bench, {
			Name = "Back",
			Size = Vector3.new(7, 2, 0.4),
			CFrame = cf * CFrame.new(0, 2.8, 0.9),
			Material = Enum.Material.WoodPlanks,
			Color = Color3.fromRGB(150, 100, 65),
		})
		for _, legX in { -3, 3 } do
			part(bench, {
				Name = "Leg",
				Size = Vector3.new(0.4, 1.4, 1.6),
				CFrame = cf * CFrame.new(legX, 0.7, 0),
				Material = Enum.Material.Metal,
				Color = DARK_METAL,
			})
		end
	end

	return lobby
end

-- Rinks ------------------------------------------------------------------------------

local function buildRinkDecor(model, rink, cf, random)
	local width, length = rink.Size.X, rink.Size.Y
	local decorFolder = folder("Decor", model)

	if rink.Theme == "Pond" then
		for index, x in { -1, 1, -1 } do
			local position = (cf * CFrame.new(x * (width / 2 + 16), 0, length / 2 - 20 - index * 25)).Position
			snowman(decorFolder, position, cf.Position, 1 + index * 0.1)
		end
	elseif rink.Theme == "Forest" then
		for _ = 1, 34 do
			local side = math.floor(random(0, 4))
			local outset = random(14, 40)
			local x, z
			if side == 0 then
				x, z = -width / 2 - outset, random(-length / 2, length / 2)
			elseif side == 1 then
				x, z = width / 2 + outset, random(-length / 2, length / 2)
			else
				x, z = random(-width / 2, width / 2), -length / 2 - outset
			end
			tree(decorFolder, (cf * CFrame.new(x, 0, z)).Position, random(0.9, 1.5), random)
		end
	elseif rink.Theme == "Glacier" then
		for _ = 1, 26 do
			local side = math.floor(random(0, 3))
			local outset = random(10, 36)
			local x, z
			if side == 0 then
				x, z = -width / 2 - outset, random(-length / 2, length / 2)
			elseif side == 1 then
				x, z = width / 2 + outset, random(-length / 2, length / 2)
			else
				x, z = random(-width / 2, width / 2), -length / 2 - outset
			end
			iceCrystals(decorFolder, (cf * CFrame.new(x, 0, z)).Position, random(0.8, 1.8), random)
		end
	elseif rink.Theme == "Arena" then
		-- Bleachers along both long sides.
		local purple = Color3.fromRGB(70, 45, 120)
		for side = -1, 1, 2 do
			for row = 1, 6 do
				part(decorFolder, {
					Name = "Bleacher",
					Size = Vector3.new(3, 1.4 * row, length * 0.85),
					CFrame = cf * CFrame.new(side * (width / 2 + 5 + 3 * (row - 1)), 0.7 * row, 0),
					Color = if row % 2 == 0 then purple else Color3.fromRGB(100, 70, 160),
				})
			end
		end

		-- Floodlight towers in each corner.
		for _, corner in { { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } } do
			local base = (cf * CFrame.new(corner[1] * (width / 2 + 26), 0, corner[2] * (length / 2 + 10))).Position
			cylinder(
				decorFolder,
				base + Vector3.new(0, 20, 0),
				40,
				1.6,
				{ Name = "Tower", Material = Enum.Material.Metal, Color = DARK_METAL }
			)
			local lampHead = part(decorFolder, {
				Name = "Floodlight",
				Size = Vector3.new(8, 4, 1),
				CFrame = facing(base + Vector3.new(0, 40, 0), cf.Position) * CFrame.Angles(math.rad(-30), 0, 0),
				Material = Enum.Material.Neon,
				Color = Color3.fromRGB(240, 240, 255),
				CanCollide = false,
			})
			light(lampHead, "SpotLight", {
				Face = Enum.NormalId.Front,
				Range = 60,
				Angle = 70,
				Brightness = 2,
				Color = Color3.fromRGB(230, 225, 255),
			})
		end

		-- Floating jumbotron over centre ice.
		local screen = decor(decorFolder, {
			Name = "Jumbotron",
			Size = Vector3.new(26, 12, 26),
			CFrame = cf * CFrame.new(0, 55, 0),
			Color = Color3.fromRGB(28, 28, 40),
		})
		for _, y in { -6.2, 6.2 } do
			decor(decorFolder, {
				Name = "JumbotronTrim",
				Size = Vector3.new(26.6, 0.6, 26.6),
				CFrame = cf * CFrame.new(0, 55 + y, 0),
				Material = Enum.Material.Neon,
				Color = rink.AccentColor,
			})
		end
		for _, face in { Enum.NormalId.Front, Enum.NormalId.Back, Enum.NormalId.Left, Enum.NormalId.Right } do
			addText(screen, face, {
				{ string.upper(rink.Name), 0.6 },
				{ multiplierText(rink.Multiplier) .. " ❄", 0.4, Color3.fromRGB(210, 180, 255) },
			}, { PixelsPerStud = 20 })
		end

		-- Aurora ribbons in the sky.
		for band = 0, 1 do
			for index = 0, 39 do
				local t = index / 39
				local x = -220 + t * 440
				local wave = math.sin(t * math.pi * 3 + band * 1.7)
				local colour = Color3.fromRGB(90, 255, 170)
					:Lerp(Color3.fromRGB(170, 100, 255), (math.sin(t * math.pi * 2 + band) + 1) / 2)
				decor(decorFolder, {
					Name = "Aurora",
					Size = Vector3.new(12, 40 + wave * 12, 0.4),
					CFrame = cf
						* CFrame.new(x, 150 + band * 30 + wave * 8, -60 + band * 90 + wave * 30)
						* CFrame.Angles(0, wave * 0.4, 0),
					Material = Enum.Material.Neon,
					Color = colour,
					Transparency = 0.6,
					CastShadow = false,
				})
			end
		end
	end
end

local function buildRink(parent, rink, Config, random)
	local width, length = rink.Size.X, rink.Size.Y
	local cf = WorldBuilder.rinkCFrame(rink, Config.Lobby.Center)
	local model = Instance.new("Model")
	model.Name = rink.Id
	model:SetAttribute("RinkId", rink.Id)
	model:SetAttribute("Multiplier", rink.Multiplier)
	model:SetAttribute("Price", rink.Price)

	local ice = part(model, {
		Name = "Ice",
		Size = Vector3.new(width, 0.4, length),
		CFrame = cf,
		Material = Enum.Material.Ice,
		Color = rink.IceColor,
		Reflectance = 0.15,
	})
	ice:SetAttribute("RinkId", rink.Id)
	ice:AddTag("RinkFloor")
	model.PrimaryPart = ice

	-- Centre circle and lines on the ice.
	local markings = folder("Markings", model)
	decor(markings, {
		Shape = Enum.PartType.Cylinder,
		Name = "CircleOuter",
		Size = Vector3.new(0.04, 32, 32),
		CFrame = cf * CFrame.new(0, 0.22, 0) * CYLINDER_UP,
		Color = rink.AccentColor,
		Transparency = 0.35,
	})
	decor(markings, {
		Shape = Enum.PartType.Cylinder,
		Name = "CircleInner",
		Size = Vector3.new(0.04, 29, 29),
		CFrame = cf * CFrame.new(0, 0.25, 0) * CYLINDER_UP,
		Material = Enum.Material.Ice,
		Color = rink.IceColor,
	})
	if rink.Theme == "Arena" or rink.Theme == "Forest" then
		decor(markings, {
			Name = "CentreLine",
			Size = Vector3.new(width, 0.04, 1.2),
			CFrame = cf * CFrame.new(0, 0.22, 0),
			Color = Color3.fromRGB(220, 60, 70),
			Transparency = 0.3,
		})
		for _, z in { -length / 6, length / 6 } do
			decor(markings, {
				Name = "BlueLine",
				Size = Vector3.new(width, 0.04, 1.2),
				CFrame = cf * CFrame.new(0, 0.22, z),
				Color = Color3.fromRGB(50, 110, 220),
				Transparency = 0.3,
			})
		end
	end

	-- Boards around the edge, with an entrance on the lobby side.
	local boards = folder("Boards", model)
	local boardHeight = rink.BoardHeight
	ring(boards, cf, width, length, {
		Name = "Board",
		Height = boardHeight,
		Thickness = BOARD_THICKNESS,
		Gap = ENTRANCE_WIDTH,
		Material = rink.BoardMaterial,
		Color = rink.BoardColor,
	})
	ring(boards, cf, width, length, {
		Name = "Rail",
		Height = 0.5,
		Bottom = boardHeight,
		Thickness = BOARD_THICKNESS + 0.4,
		Outset = -0.2,
		Gap = ENTRANCE_WIDTH,
		Color = rink.RailColor,
	})
	if rink.Theme == "Arena" then
		ring(boards, cf, width, length, {
			Name = "Glass",
			Height = 6,
			Bottom = boardHeight + 0.5,
			Thickness = 0.4,
			Outset = 0.55,
			Gap = ENTRANCE_WIDTH,
			Material = Enum.Material.Glass,
			Color = Color3.fromRGB(200, 230, 255),
			Transparency = 0.65,
		})
	end

	-- Entrance arch with the rink's name.
	local arch = folder("Arch", model)
	local archZ = length / 2 + BOARD_THICKNESS / 2
	for side = -1, 1, 2 do
		local x = side * (ENTRANCE_WIDTH / 2 + 2.5)
		part(arch, {
			Name = "Pillar",
			Size = Vector3.new(3.5, 18, 3.5),
			CFrame = cf * CFrame.new(x, 9, archZ),
			Material = rink.BoardMaterial,
			Color = rink.BoardColor,
		})
		ball(
			arch,
			(cf * CFrame.new(x, 18.4, archZ)).Position,
			2.6,
			{ Name = "Orb", Material = Enum.Material.Neon, Color = rink.AccentColor, CanCollide = false }
		)
	end
	local beam = part(arch, {
		Name = "Beam",
		Size = Vector3.new(ENTRANCE_WIDTH + 9, 5, 2.5),
		CFrame = cf * CFrame.new(0, 20.5, archZ),
		Color = Color3.fromRGB(30, 45, 80),
	})
	decor(arch, {
		Name = "Trim",
		Size = Vector3.new(ENTRANCE_WIDTH + 9.4, 0.4, 2.7),
		CFrame = cf * CFrame.new(0, 18.2, archZ),
		Material = Enum.Material.Neon,
		Color = rink.AccentColor,
	})
	decor(arch, {
		Name = "Snow",
		Size = Vector3.new(ENTRANCE_WIDTH + 9.4, 0.8, 2.9),
		CFrame = cf * CFrame.new(0, 23.4, archZ),
		Material = Enum.Material.Snow,
		Color = SNOW,
	})
	local archLines = {
		{ string.upper(rink.Name), 0.62 },
		{ multiplierText(rink.Multiplier) .. " Snowflakes", 0.38, Color3.fromRGB(200, 230, 255) },
	}
	addText(beam, Enum.NormalId.Back, archLines, { PixelsPerStud = 30 })
	addText(beam, Enum.NormalId.Front, archLines, { PixelsPerStud = 30 })

	-- Lamps around the outside.
	local lamps = folder("Lamps", model)
	local lampOutset = BOARD_THICKNESS + LOCK_OUTSET + 3
	local sideCount = math.max(2, math.floor(length / 45))
	for index = 0, sideCount do
		local z = -length / 2 + index * (length / sideCount)
		for side = -1, 1, 2 do
			if rink.Theme ~= "Arena" then
				lamp(
					lamps,
					(cf * CFrame.new(side * (width / 2 + lampOutset), 0, z)).Position,
					rink.Theme == "Glacier" and Color3.fromRGB(170, 230, 255) or nil
				)
			end
		end
	end
	local backCount = math.max(2, math.floor(width / 45))
	for index = 1, backCount - 1 do
		local x = -width / 2 + index * (width / backCount)
		lamp(
			lamps,
			(cf * CFrame.new(x, 0, -length / 2 - lampOutset)).Position,
			rink.Theme == "Glacier" and Color3.fromRGB(170, 230, 255) or nil
		)
	end

	-- Locked rinks are sealed by invisible walls and a shimmering gate until bought.
	-- The client opens them for players who own them; the server double-checks.
	if rink.Price > 0 then
		local lock = folder("Lock", model)
		ring(lock, cf, width, length, {
			Name = "LockWall",
			Height = 90,
			Thickness = 1,
			Outset = LOCK_OUTSET,
			Transparency = 1,
			Invisible = true,
		})
		local gateZ = length / 2 + LOCK_OUTSET + 1.5
		local gate = decor(lock, {
			Name = "Gate",
			Size = Vector3.new(ENTRANCE_WIDTH + 14, 24, 0.4),
			CFrame = cf * CFrame.new(0, 12, gateZ),
			Material = Enum.Material.ForceField,
			Color = rink.AccentColor,
			CastShadow = false,
		})
		addText(gate, Enum.NormalId.Back, {
			{ "🔒 LOCKED", 0.4 },
			{ commas(rink.Price) .. " ❄", 0.35, Color3.fromRGB(200, 235, 255) },
			{ "to unlock " .. rink.Name, 0.25, Color3.fromRGB(200, 215, 240) },
		}, { PixelsPerStud = 20 })
		local promptPart = decor(lock, {
			Name = "PromptAnchor",
			Size = Vector3.new(4, 4, 1),
			CFrame = cf * CFrame.new(0, 4, gateZ + 1.5),
			Transparency = 1,
		})
		addPrompt(promptPart, {
			ActionText = "Unlock",
			ObjectText = rink.Name .. " (" .. commas(rink.Price) .. " ❄)",
			HoldDuration = 0.4,
			MaxActivationDistance = 16,
		}, { Action = "UnlockRink", RinkId = rink.Id })
	end

	buildRinkDecor(model, rink, cf, random)
	model.Parent = parent
	return model, cf
end

local function buildPath(parent, Config, rink, cf)
	local center = Config.Lobby.Center
	local radius = Config.Lobby.PlazaRadius
	local entrance = (cf * CFrame.new(0, 0, rink.Size.Y / 2 + BOARD_THICKNESS)).Position
	local direction = Vector3.new(entrance.X - center.X, 0, entrance.Z - center.Z).Unit
	local start = center + direction * (radius - 1)
	local pathLength = (entrance - start).Magnitude
	local pathCFrame = facing((start + entrance) / 2, entrance)

	local path = folder(rink.Id .. "Path", parent)
	part(path, {
		Name = "Path",
		Size = Vector3.new(18, 0.3, pathLength),
		CFrame = pathCFrame,
		Material = Enum.Material.Slate,
		Color = Color3.fromRGB(175, 185, 205),
	})
	for side = -1, 1, 2 do
		decor(path, {
			Name = "SnowBank",
			Size = Vector3.new(2.4, 1.4, pathLength),
			CFrame = pathCFrame * CFrame.new(side * 10.2, 0, 0),
			Material = Enum.Material.Snow,
			Color = SNOW,
		})
	end

	local lampCount = math.max(1, math.floor(pathLength / 40))
	for index = 1, lampCount do
		local z = -pathLength / 2 + (index - 0.5) * (pathLength / lampCount)
		for side = -1, 1, 2 do
			lamp(path, (pathCFrame * CFrame.new(side * 13, 0, z)).Position)
		end
	end

	-- Signpost at the plaza end of the path.
	local signBase = start + direction * 4 + direction:Cross(Vector3.yAxis) * 12
	cylinder(
		path,
		signBase + Vector3.new(0, 4, 0),
		8,
		0.6,
		{ Name = "SignPost", Material = Enum.Material.Wood, Color = Color3.fromRGB(110, 75, 50) }
	)
	local board = part(path, {
		Name = "SignBoard",
		Size = Vector3.new(9, 3.4, 0.4),
		CFrame = facing(signBase + Vector3.new(0, 7.4, 0), center),
		Material = Enum.Material.WoodPlanks,
		Color = Color3.fromRGB(150, 100, 65),
	})
	local signLines = {
		{ rink.Name, 0.6 },
		{ multiplierText(rink.Multiplier) .. " ❄", 0.4, Color3.fromRGB(200, 235, 255) },
	}
	addText(board, Enum.NormalId.Front, signLines, { PixelsPerStud = 30, StrokeThickness = 2 })
	addText(board, Enum.NormalId.Back, signLines, { PixelsPerStud = 30, StrokeThickness = 2 })

	return start, entrance
end

-- Scenery ----------------------------------------------------------------------------

local function buildScenery(map, Config, random, rinkFrames, paths)
	local scenery = folder("Scenery", map)
	local center = Config.Lobby.Center
	local radius = Config.Lobby.PlazaRadius

	local function isClear(point, margin)
		if (point - center).Magnitude < radius + 15 + margin then
			return false
		end
		for _, entry in rinkFrames do
			local localPoint = entry.CFrame:PointToObjectSpace(point)
			if
				math.abs(localPoint.X) < entry.Rink.Size.X / 2 + 32 + margin
				and math.abs(localPoint.Z) < entry.Rink.Size.Y / 2 + 32 + margin
			then
				return false
			end
		end
		for _, segment in paths do
			if distanceToSegment(point, segment[1], segment[2]) < 20 + margin then
				return false
			end
		end
		return true
	end

	local trees = folder("Trees", scenery)
	local placed = 0
	local attempts = 0
	while placed < 140 and attempts < 4000 do
		attempts += 1
		local point = Vector3.new(random(-560, 560), 0, random(-420, 620))
		if isClear(point, 0) then
			tree(trees, point, random(0.9, 1.7), random)
			placed += 1
		end
	end

	local drifts = folder("SnowDrifts", scenery)
	placed = 0
	attempts = 0
	while placed < 40 and attempts < 2000 do
		attempts += 1
		local point = Vector3.new(random(-560, 560), 0, random(-420, 620))
		if isClear(point, 10) then
			local diameter = random(10, 26)
			ball(
				drifts,
				point + Vector3.new(0, -diameter * 0.3, 0),
				diameter,
				{ Name = "Drift", Material = Enum.Material.Snow, Color = SNOW }
			)
			placed += 1
		end
	end

	local mountains = folder("Mountains", scenery)
	local mountainCentre = center + Vector3.new(0, 0, 100)
	for index = 0, 17 do
		local angle = index / 18 * math.pi * 2 + random(-0.1, 0.1)
		local distance = random(850, 980)
		local position = mountainCentre + Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)
		local glacier = index % 3 == 0
		mountain(
			mountains,
			position,
			random(260, 420),
			random(0, math.pi * 2),
			if glacier then Color3.fromRGB(185, 215, 240) else Color3.fromRGB(235, 240, 248),
			if glacier then Enum.Material.Glacier else Enum.Material.Snow
		)
	end
end

-- Entry point --------------------------------------------------------------------

function WorldBuilder.build(Config)
	local random = newRandom(20261004)

	configureLighting()
	restyleWorkspace()

	local map = Instance.new("Folder")
	map.Name = "Map"

	buildLobby(map, Config)

	local rinksFolder = folder("Rinks", map)
	local pathsFolder = folder("Paths", map)
	local rinkFrames = {}
	local paths = {}
	for _, rink in Config.Rinks do
		local _, cf = buildRink(rinksFolder, rink, Config, random)
		table.insert(rinkFrames, { Rink = rink, CFrame = cf })
		local start, finish = buildPath(pathsFolder, Config, rink, cf)
		table.insert(paths, { start, finish })
	end

	buildScenery(map, Config, random, rinkFrames, paths)

	map.Parent = workspace
	return map
end

return WorldBuilder
