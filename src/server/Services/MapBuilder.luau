--[[
	MapBuilder
	Builds the Grounds hub at server start: lighting, the asphalt plaza, the caged
	3v3 pitch with goals, stands, floodlights, surrounding buildings with graffiti,
	the Locker, the practice court, area gates and street furniture.

	Everything is generated from Config so the layout stays in sync with the
	match and ball systems. If you hand-build a map later, keep the same names
	(Workspace.Grounds.Pitches.<Id>) and attributes, and remove this service.
]]

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)

local MapBuilder = {}

local root: Folder

local COLORS = {
	Asphalt = Color3.fromRGB(240, 200, 50),
	Concrete = Color3.fromRGB(150, 150, 146),
	GrassA = Color3.fromRGB(56, 140, 60),
	GrassB = Color3.fromRGB(48, 124, 52),
	Line = Color3.fromRGB(245, 245, 240),
	Fence = Color3.fromRGB(40, 42, 46),
	Volt = Config.Teams.A.Color,
	Ember = Config.Teams.B.Color,
}

local function part(props): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	for k, v in props do
		if k ~= "Parent" then
			(p :: any)[k] = v
		end
	end
	p.Parent = props.Parent
	return p
end

local function folder(name: string, parent: Instance): Folder
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

local function collider(cf: CFrame, size: Vector3, parent: Instance, name: string?)
	return part({
		Name = name or "Collider",
		CFrame = cf,
		Size = size,
		Transparency = 1,
		CanQuery = false,
		CastShadow = false,
		Parent = parent,
	})
end

local function signText(target: BasePart, face: Enum.NormalId, text: string, color: Color3, font: Enum.Font, opts)
	opts = opts or {}
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = opts.PixelsPerStud or 20
	gui.LightInfluence = opts.LightInfluence or 0
	gui.Brightness = opts.Brightness or 1.5
	gui.Parent = target
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextScaled = true
	label.Font = font
	label.TextColor3 = color
	label.Rotation = opts.Rotation or 0
	label.Parent = gui
	if opts.Gradient then
		local g = Instance.new("UIGradient")
		g.Color = opts.Gradient
		g.Parent = label
	end
	if opts.Stroke then
		local s = Instance.new("UIStroke")
		s.Color = opts.Stroke
		s.Thickness = 3
		s.Parent = label
	end
	return gui, label
end

-------------------------------------------------------------------------------
-- Lighting
-------------------------------------------------------------------------------
local function buildLighting()
	Lighting.ClockTime = 16.2
	Lighting.Brightness = 3
	Lighting.Ambient = Color3.fromRGB(90, 88, 100)
	Lighting.OutdoorAmbient = Color3.fromRGB(150, 145, 160)
	Lighting.EnvironmentDiffuseScale = 1
	Lighting.EnvironmentSpecularScale = 0.6
	Lighting.GlobalShadows = true
	Lighting.ShadowSoftness = 0.25
	pcall(function()
		Lighting.Technology = Enum.Technology.Future
	end)

	for _, child in Lighting:GetChildren() do
		if child:IsA("PostEffect") or child:IsA("Atmosphere") or child:IsA("Sky") then
			child:Destroy()
		end
	end

	local atmosphere = Instance.new("Atmosphere")
	atmosphere.Density = 0.25
	atmosphere.Offset = 0.15
	atmosphere.Color = Color3.fromRGB(255, 196, 160)
	atmosphere.Decay = Color3.fromRGB(110, 90, 120)
	atmosphere.Glare = 0.4
	atmosphere.Haze = 1.6
	atmosphere.Parent = Lighting

	local bloom = Instance.new("BloomEffect")
	bloom.Intensity = 0.6
	bloom.Size = 30
	bloom.Threshold = 1.6
	bloom.Parent = Lighting

	local cc = Instance.new("ColorCorrectionEffect")
	cc.Contrast = 0.12
	cc.Saturation = 0.12
	cc.TintColor = Color3.fromRGB(255, 244, 236)
	cc.Parent = Lighting

	local rays = Instance.new("SunRaysEffect")
	rays.Intensity = 0.06
	rays.Spread = 0.6
	rays.Parent = Lighting
end

-------------------------------------------------------------------------------
-- Pitch
-------------------------------------------------------------------------------
local function line(parent, cf: CFrame, sizeX: number, sizeZ: number)
	return part({
		Name = "Line",
		CFrame = cf,
		Size = Vector3.new(sizeX, 0.05, sizeZ),
		Color = COLORS.Line,
		Material = Enum.Material.SmoothPlastic,
		CanCollide = false,
		CanQuery = false,
		CastShadow = false,
		Parent = parent,
	})
end

local function circle(parent, center: Vector3, radius: number, segments: number, thickness: number)
	for i = 0, segments - 1 do
		local a = (i + 0.5) / segments * math.pi * 2
		local segLength = 2 * math.pi * radius / segments + 0.15
		local pos = center + Vector3.new(math.cos(a) * radius, 0, math.sin(a) * radius)
		line(parent, CFrame.lookAt(pos, center) * CFrame.Angles(0, math.pi / 2, 0), segLength, thickness)
	end
end

local function buildGoal(parent: Instance, pitch, side: number, teamColor: Color3)
	-- side = -1 for the -X goal (Team A defends), +1 for the +X goal (Team B defends)
	local c = pitch.Center
	local y = pitch.SurfaceY
	local halfL = pitch.Length / 2
	local gw, gh, gd = pitch.GoalWidth, pitch.GoalHeight, pitch.GoalDepth
	local goalX = c.X + side * halfL
	local model = Instance.new("Model")
	model.Name = if side < 0 then "GoalA" else "GoalB"
	model.Parent = parent

	local postSize = 0.7
	for _, z in { -gw / 2, gw / 2 } do
		part({
			Name = "Post",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(gh, postSize, postSize),
			CFrame = CFrame.new(goalX, y + gh / 2, c.Z + z) * CFrame.Angles(0, 0, math.rad(90)),
			Color = Color3.new(1, 1, 1),
			Material = Enum.Material.Metal,
			Parent = model,
		})
	end
	part({
		Name = "Crossbar",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(gw + postSize, postSize, postSize),
		CFrame = CFrame.new(goalX, y + gh, c.Z) * CFrame.Angles(0, math.rad(90), 0),
		Color = Color3.new(1, 1, 1),
		Material = Enum.Material.Metal,
		Parent = model,
	})

	-- Net (visual + collision so the ball stays in)
	local netProps = {
		Color = Color3.fromRGB(230, 230, 230),
		Material = Enum.Material.Fabric,
		Transparency = 0.55,
		CastShadow = false,
		Parent = model,
	}
	local backX = goalX + side * gd
	local function net(name, cf, size)
		local p = part(netProps)
		p.Name = name
		p.CFrame = cf
		p.Size = size
		return p
	end
	net("NetBack", CFrame.new(backX + side * 0.1, y + gh / 2, c.Z), Vector3.new(0.2, gh, gw))
	net("NetTop", CFrame.new(goalX + side * gd / 2, y + gh + 0.1, c.Z), Vector3.new(gd, 0.2, gw))
	net("NetSideL", CFrame.new(goalX + side * gd / 2, y + gh / 2, c.Z - gw / 2 - 0.1), Vector3.new(gd, gh, 0.2))
	net("NetSideR", CFrame.new(goalX + side * gd / 2, y + gh / 2, c.Z + gw / 2 + 0.1), Vector3.new(gd, gh, 0.2))

	-- Coloured goal box floor so each end is readable at a glance
	part({
		Name = "GoalFloor",
		CFrame = CFrame.new(goalX + side * gd / 2, y - 0.05, c.Z),
		Size = Vector3.new(gd, 0.2, gw),
		Color = teamColor,
		Material = Enum.Material.Neon,
		Transparency = 0.6,
		CanCollide = false,
		Parent = model,
	})
	return model
end

local function buildPitch(parent: Instance, pitch)
	local model = folder(pitch.Id, parent)
	local c = pitch.Center
	local y = pitch.SurfaceY
	local L, W = pitch.Length, pitch.Width
	local halfL, halfW = L / 2, W / 2

	-- Stripes
	local stripes = 8
	for i = 0, stripes - 1 do
		local x = c.X - halfL + (i + 0.5) * (L / stripes)
		part({
			Name = "Turf",
			CFrame = CFrame.new(x, y - 0.5, c.Z),
			Size = Vector3.new(L / stripes, 1, W),
			Color = if i % 2 == 0 then COLORS.GrassA else COLORS.GrassB,
			Material = Enum.Material.Grass,
			Parent = model,
		})
	end
	-- Concrete border slab around the turf
	part({
		Name = "Border",
		CFrame = CFrame.new(c.X, y - 0.6, c.Z),
		Size = Vector3.new(L + 2 * pitch.GoalDepth + 6, 1, W + 6),
		Color = COLORS.Concrete,
		Material = Enum.Material.Concrete,
		Parent = model,
	})

	-- Markings
	local lines = folder("Lines", model)
	local ly = y + 0.03
	local t = 0.45
	line(lines, CFrame.new(c.X, ly, c.Z - halfW + t / 2), L, t)
	line(lines, CFrame.new(c.X, ly, c.Z + halfW - t / 2), L, t)
	line(lines, CFrame.new(c.X - halfL + t / 2, ly, c.Z), t, W)
	line(lines, CFrame.new(c.X + halfL - t / 2, ly, c.Z), t, W)
	line(lines, CFrame.new(c.X, ly, c.Z), t, W)
	circle(lines, Vector3.new(c.X, ly, c.Z), 9, 28, t)
	part({
		Name = "CenterSpot",
		Shape = Enum.PartType.Cylinder,
		CFrame = CFrame.new(c.X, ly, c.Z) * CFrame.Angles(0, 0, math.rad(90)),
		Size = Vector3.new(0.05, 1.2, 1.2),
		Color = COLORS.Line,
		CanCollide = false,
		CanQuery = false,
		Parent = lines,
	})
	local boxDepth, boxWidth = 14, 30
	for _, side in { -1, 1 } do
		local gx = c.X + side * halfL
		local bx = gx - side * boxDepth
		line(lines, CFrame.new(bx, ly, c.Z), t, boxWidth)
		line(lines, CFrame.new(gx - side * boxDepth / 2, ly, c.Z - boxWidth / 2), boxDepth, t)
		line(lines, CFrame.new(gx - side * boxDepth / 2, ly, c.Z + boxWidth / 2), boxDepth, t)
	end

	-- Goals
	buildGoal(model, pitch, -1, COLORS.Volt)
	buildGoal(model, pitch, 1, COLORS.Ember)

	-- Cage: visible fence + tall invisible colliders (ball and players stay inside)
	local cage = folder("Cage", model)
	local wallH = pitch.WallHeight
	local colH = pitch.ColliderHeight
	local gw = pitch.GoalWidth

	local function fenceRun(from: Vector3, to: Vector3, exact: boolean?)
		local mid = (from + to) / 2
		local length = (to - from).Magnitude
		local cf = CFrame.lookAt(mid, to)
		-- mesh panel
		part({
			Name = "FencePanel",
			CFrame = cf * CFrame.new(0, wallH / 2, 0),
			Size = Vector3.new(0.15, wallH, length),
			Color = COLORS.Fence,
			Material = Enum.Material.DiamondPlate,
			Transparency = 0.7,
			CanCollide = false,
			CastShadow = false,
			Parent = cage,
		})
		part({
			Name = "TopRail",
			CFrame = cf * CFrame.new(0, wallH, 0),
			Size = Vector3.new(0.5, 0.5, length),
			Color = COLORS.Fence,
			Material = Enum.Material.Metal,
			Parent = cage,
		})
		local posts = math.max(1, math.floor(length / 8))
		for i = 0, posts do
			local p = from:Lerp(to, i / posts)
			part({
				Name = "Post",
				CFrame = CFrame.new(p.X, p.Y + wallH / 2, p.Z),
				Size = Vector3.new(0.5, wallH, 0.5),
				Color = COLORS.Fence,
				Material = Enum.Material.Metal,
				Parent = cage,
			})
		end
		collider(cf * CFrame.new(0, colH / 2, 0), Vector3.new(2, colH, if exact then length else length + 2), cage, "CageCollider")
	end

	local base = y
	local nW = c.Z - halfW - 1
	local sW = c.Z + halfW + 1
	local eX = c.X + halfL + 1
	local wX = c.X - halfL - 1
	-- long sides
	fenceRun(Vector3.new(wX, base, nW), Vector3.new(eX, base, nW))
	fenceRun(Vector3.new(wX, base, sW), Vector3.new(eX, base, sW))
	-- goal ends, leaving a gap for each goal mouth
	for _, x in { wX, eX } do
		fenceRun(Vector3.new(x, base, nW), Vector3.new(x, base, c.Z - gw / 2 - 0.6), true)
		fenceRun(Vector3.new(x, base, c.Z + gw / 2 + 0.6), Vector3.new(x, base, sW), true)
	end
	-- Behind each goal: collider wall so a ball in the net never escapes
	for _, side in { -1, 1 } do
		local x = c.X + side * (halfL + pitch.GoalDepth + 1.5)
		collider(CFrame.new(x, base + colH / 2, c.Z), Vector3.new(2, colH, gw + 4), cage, "GoalBackCollider")
		collider(CFrame.new(c.X + side * (halfL + 1 + pitch.GoalDepth / 2), base + colH / 2 + pitch.GoalHeight + 0.4, c.Z), Vector3.new(pitch.GoalDepth + 2, colH, gw + 4), cage, "GoalTopCollider")
	end
	-- Roof
	collider(CFrame.new(c.X, base + colH, c.Z), Vector3.new(L + 20, 2, W + 6), cage, "Roof")

	-- Floodlights in each corner
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			local px = c.X + sx * (halfL + 4)
			local pz = c.Z + sz * (halfW + 4)
			part({
				Name = "LightPole",
				CFrame = CFrame.new(px, base + 16, pz),
				Size = Vector3.new(1, 32, 1),
				Color = COLORS.Fence,
				Material = Enum.Material.Metal,
				Parent = cage,
			})
			local head = part({
				Name = "LightHead",
				CFrame = CFrame.lookAt(Vector3.new(px, base + 32, pz), Vector3.new(c.X, base, c.Z)),
				Size = Vector3.new(5, 3, 1),
				Color = Color3.fromRGB(255, 250, 230),
				Material = Enum.Material.Neon,
				Parent = cage,
			})
			local spot = Instance.new("SpotLight")
			spot.Face = Enum.NormalId.Front
			spot.Angle = 70
			spot.Range = 60
			spot.Brightness = 2.2
			spot.Color = Color3.fromRGB(255, 246, 225)
			spot.Shadows = false
			spot.Parent = head
		end
	end

	-- Name board above the north fence
	local board = part({
		Name = "PitchSign",
		CFrame = CFrame.new(c.X, base + wallH + 4, nW - 0.5),
		Size = Vector3.new(30, 5, 0.6),
		Color = Color3.fromRGB(16, 16, 20),
		Parent = cage,
	})
	signText(board, Enum.NormalId.Front, pitch.DisplayName .. "  ·  3v3", Color3.fromRGB(255, 255, 255), Enum.Font.GothamBlack, { Brightness = 2 })
	signText(board, Enum.NormalId.Back, pitch.DisplayName .. "  ·  3v3", Color3.fromRGB(255, 255, 255), Enum.Font.GothamBlack, { Brightness = 2 })

	-- Spectator stands on the north side
	local stands = folder("Stands", model)
	for row = 0, 4 do
		part({
			Name = "Step",
			CFrame = CFrame.new(c.X, base + row * 1.4 + 0.7, nW - 6 - row * 3),
			Size = Vector3.new(L * 0.8, 1.4 + row * 2.8, 3),
			Color = if row % 2 == 0 then Color3.fromRGB(70, 74, 82) else Color3.fromRGB(84, 88, 96),
			Material = Enum.Material.Concrete,
			Parent = stands,
		})
	end

	-- Queue pad
	local padPos = c + pitch.QueuePad
	local pad = part({
		Name = "QueuePad",
		Shape = Enum.PartType.Cylinder,
		CFrame = CFrame.new(padPos.X, 0.25, padPos.Z) * CFrame.Angles(0, 0, math.rad(90)),
		Size = Vector3.new(0.5, 14, 14),
		Color = COLORS.Volt,
		Material = Enum.Material.Neon,
		Transparency = 0.15,
		Parent = model,
	})
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "QueuePrompt"
	prompt.ActionText = "Join Queue"
	prompt.ObjectText = pitch.DisplayName .. " 3v3"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.R
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonY
	prompt.Parent = pad

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "QueueBoard"
	billboard.Size = UDim2.fromOffset(260, 90)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, 8, 0)
	billboard.AlwaysOnTop = false
	billboard.MaxDistance = 160
	billboard.Parent = pad
	local qLabel = Instance.new("TextLabel")
	qLabel.Name = "Label"
	qLabel.Size = UDim2.fromScale(1, 1)
	qLabel.BackgroundColor3 = Color3.fromRGB(14, 14, 18)
	qLabel.BackgroundTransparency = 0.2
	qLabel.TextColor3 = Color3.new(1, 1, 1)
	qLabel.Font = Enum.Font.GothamBold
	qLabel.TextScaled = true
	qLabel.Text = pitch.DisplayName .. "\nQUEUE 0/6"
	qLabel.Parent = billboard
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = qLabel

	model:SetAttribute("PitchId", pitch.Id)
	return model
end

-------------------------------------------------------------------------------
-- Hub dressing
-------------------------------------------------------------------------------
local GRAFFITI = {
	{ Text = "CONCRETE KINGS", Color = Color3.fromRGB(205, 255, 64), Stroke = Color3.fromRGB(20, 40, 10) },
	{ Text = "NO LIMITS", Color = Color3.fromRGB(255, 110, 54), Stroke = Color3.fromRGB(60, 10, 0) },
	{ Text = "PLAY. LOSE. RUN IT BACK.", Color = Color3.fromRGB(120, 220, 255), Stroke = Color3.fromRGB(10, 30, 60) },
	{ Text = "BALL DON'T LIE", Color = Color3.fromRGB(255, 120, 220), Stroke = Color3.fromRGB(60, 0, 40) },
	{ Text = "EST. ON THE BLOCK", Color = Color3.fromRGB(255, 220, 90), Stroke = Color3.fromRGB(60, 40, 0) },
}

local function building(parent, position: Vector3, size: Vector3, color: Color3, graffitiIndex: number?, facing: Vector3)
	local cf = CFrame.lookAt(position + Vector3.new(0, size.Y / 2, 0), position + Vector3.new(0, size.Y / 2, 0) + facing)
	local body = part({
		Name = "Building",
		CFrame = cf,
		Size = size,
		Color = color,
		Material = Enum.Material.Brick,
		Parent = parent,
	})
	part({
		Name = "Roofline",
		CFrame = cf * CFrame.new(0, size.Y / 2 + 0.5, 0),
		Size = Vector3.new(size.X + 1, 1, size.Z + 1),
		Color = Color3.fromRGB(40, 40, 44),
		Material = Enum.Material.Concrete,
		Parent = parent,
	})
	-- Window strips on the front face
	local floors = math.floor(size.Y / 9)
	for f = 1, floors do
		local wy = -size.Y / 2 + f * 9 - 2
		if wy < size.Y / 2 - 3 then
			part({
				Name = "Windows",
				CFrame = cf * CFrame.new(0, wy, -size.Z / 2 - 0.05),
				Size = Vector3.new(size.X * 0.8, 3, 0.2),
				Color = if (f + math.floor(position.X)) % 3 == 0 then Color3.fromRGB(255, 214, 140) else Color3.fromRGB(40, 60, 80),
				Material = if (f + math.floor(position.X)) % 3 == 0 then Enum.Material.Neon else Enum.Material.Glass,
				CanCollide = false,
				Parent = parent,
			})
		end
	end
	if graffitiIndex then
		local g = GRAFFITI[(graffitiIndex - 1) % #GRAFFITI + 1]
		local wall = part({
			Name = "GraffitiWall",
			CFrame = cf * CFrame.new(0, -size.Y / 2 + 5, -size.Z / 2 - 0.06),
			Size = Vector3.new(size.X * 0.9, 8, 0.1),
			Transparency = 1,
			CanCollide = false,
			CanQuery = false,
			Parent = parent,
		})
		signText(wall, Enum.NormalId.Front, g.Text, g.Color, Enum.Font.PermanentMarker, {
			Stroke = g.Stroke,
			LightInfluence = 0.6,
			Brightness = 1,
			Rotation = -3,
		})
	end
	return body
end

local function bench(parent, cf: CFrame)
	part({ Name = "BenchSeat", CFrame = cf * CFrame.new(0, 1.6, 0), Size = Vector3.new(8, 0.4, 2), Color = Color3.fromRGB(150, 90, 50), Material = Enum.Material.WoodPlanks, Parent = parent })
	part({ Name = "BenchBack", CFrame = cf * CFrame.new(0, 2.8, 0.9), Size = Vector3.new(8, 2, 0.3), Color = Color3.fromRGB(150, 90, 50), Material = Enum.Material.WoodPlanks, Parent = parent })
	for _, x in { -3.4, 3.4 } do
		part({ Name = "BenchLeg", CFrame = cf * CFrame.new(x, 0.7, 0), Size = Vector3.new(0.4, 1.4, 1.8), Color = COLORS.Fence, Material = Enum.Material.Metal, Parent = parent })
	end
	local seat = Instance.new("Seat")
	seat.Name = "Seat"
	seat.Anchored = true
	seat.Transparency = 1
	seat.Size = Vector3.new(7, 0.2, 1.6)
	seat.CFrame = cf * CFrame.new(0, 1.85, 0)
	seat.Parent = parent
end

local function streetLight(parent, position: Vector3)
	part({ Name = "LampPost", CFrame = CFrame.new(position + Vector3.new(0, 7, 0)), Size = Vector3.new(0.6, 14, 0.6), Color = COLORS.Fence, Material = Enum.Material.Metal, Parent = parent })
	local lamp = part({ Name = "Lamp", CFrame = CFrame.new(position + Vector3.new(0, 14.2, 0)), Size = Vector3.new(1.6, 0.8, 1.6), Color = Color3.fromRGB(255, 220, 160), Material = Enum.Material.Neon, Parent = parent })
	local light = Instance.new("PointLight")
	light.Range = 22
	light.Brightness = 1.4
	light.Color = Color3.fromRGB(255, 214, 160)
	light.Parent = lamp
end

local function buildLocker(parent)
	local pos = Config.Hub.Locker
	local model = folder("Locker", parent)
	local cf = CFrame.lookAt(pos, pos + Vector3.new(1, 0, 0))
	part({ Name = "Floor", CFrame = cf * CFrame.new(0, 0.1, 0), Size = Vector3.new(30, 0.2, 22), Color = Color3.fromRGB(30, 30, 34), Material = Enum.Material.Marble, Parent = model })
	part({ Name = "BackWall", CFrame = cf * CFrame.new(0, 8, 11), Size = Vector3.new(30, 16, 1), Color = Color3.fromRGB(26, 26, 30), Material = Enum.Material.Concrete, Parent = model })
	part({ Name = "SideWallL", CFrame = cf * CFrame.new(-15, 8, 0), Size = Vector3.new(1, 16, 22), Color = Color3.fromRGB(26, 26, 30), Material = Enum.Material.Concrete, Parent = model })
	part({ Name = "SideWallR", CFrame = cf * CFrame.new(15, 8, 0), Size = Vector3.new(1, 16, 22), Color = Color3.fromRGB(26, 26, 30), Material = Enum.Material.Concrete, Parent = model })
	part({ Name = "Roof", CFrame = cf * CFrame.new(0, 16.5, 0), Size = Vector3.new(32, 1, 24), Color = Color3.fromRGB(20, 20, 24), Material = Enum.Material.Concrete, Parent = model })
	local sign = part({ Name = "Sign", CFrame = cf * CFrame.new(0, 13.5, -11.2), Size = Vector3.new(24, 4, 0.4), Color = Color3.fromRGB(12, 12, 14), Parent = model })
	signText(sign, Enum.NormalId.Front, "THE LOCKER", Config.Teams.A.Color, Enum.Font.GothamBlack, { Brightness = 3 })
	part({ Name = "NeonStrip", CFrame = cf * CFrame.new(0, 11.2, -11.2), Size = Vector3.new(30, 0.3, 0.3), Color = Config.Teams.A.Color, Material = Enum.Material.Neon, Parent = model })
	-- Mannequin plinths
	for _, x in { -9, 0, 9 } do
		part({ Name = "Plinth", CFrame = cf * CFrame.new(x, 1, 6), Size = Vector3.new(4, 2, 4), Color = Color3.fromRGB(240, 240, 240), Material = Enum.Material.Marble, Parent = model })
	end
	local counter = part({ Name = "Counter", CFrame = cf * CFrame.new(0, 2, -2), Size = Vector3.new(10, 4, 3), Color = Color3.fromRGB(230, 230, 230), Material = Enum.Material.Marble, Parent = model })
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Open Locker"
	prompt.ObjectText = "Customize your player"
	prompt.HoldDuration = 0
	prompt.KeyboardKeyCode = Enum.KeyCode.R
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt:SetAttribute("OpensUI", "Locker")
	prompt.Parent = counter
	local light = Instance.new("PointLight")
	light.Range = 26
	light.Brightness = 2
	light.Parent = counter
	return model
end

local function buildPractice(parent)
	local pos = Config.Hub.PracticeArea
	local model = folder("Practice", parent)
	part({ Name = "Court", CFrame = CFrame.new(pos + Vector3.new(0, 0.1, 0)), Size = Vector3.new(44, 0.2, 44), Color = Color3.fromRGB(70, 90, 160), Material = Enum.Material.Slate, Parent = model })
	-- mini goal on the east edge
	local gx = pos.X + 20
	for _, z in { -6, 6 } do
		part({ Name = "Post", CFrame = CFrame.new(gx, 3, pos.Z + z), Size = Vector3.new(0.6, 6, 0.6), Color = Color3.new(1, 1, 1), Material = Enum.Material.Metal, Parent = model })
	end
	part({ Name = "Bar", CFrame = CFrame.new(gx, 6, pos.Z), Size = Vector3.new(0.6, 0.6, 12.6), Color = Color3.new(1, 1, 1), Material = Enum.Material.Metal, Parent = model })
	part({ Name = "Net", CFrame = CFrame.new(gx + 3, 3, pos.Z), Size = Vector3.new(0.2, 6, 12), Color = Color3.new(1, 1, 1), Material = Enum.Material.Fabric, Transparency = 0.55, Parent = model })
	-- low walls so practice balls do not roll away
	for _, spec in {
		{ CFrame.new(pos.X, 1.5, pos.Z - 22), Vector3.new(44, 3, 1) },
		{ CFrame.new(pos.X, 1.5, pos.Z + 22), Vector3.new(44, 3, 1) },
		{ CFrame.new(pos.X + 24, 1.5, pos.Z), Vector3.new(1, 3, 44) },
	} do
		part({ Name = "Wall", CFrame = spec[1], Size = spec[2], Color = Color3.fromRGB(230, 230, 235), Material = Enum.Material.Concrete, Parent = model })
	end
	local sign = part({ Name = "Sign", CFrame = CFrame.new(pos.X, 6, pos.Z - 22.6), Size = Vector3.new(20, 4, 0.4), Color = Color3.fromRGB(14, 14, 18), Parent = model })
	signText(sign, Enum.NormalId.Back, "PRACTICE COURT", Color3.fromRGB(120, 220, 255), Enum.Font.GothamBlack, { Brightness = 2 })
	signText(sign, Enum.NormalId.Front, "PRACTICE COURT", Color3.fromRGB(120, 220, 255), Enum.Font.GothamBlack, { Brightness = 2 })
	return model
end

local function buildAreaGate(parent, gate)
	local model = folder("Gate_" .. gate.Area, parent)
	local pos = gate.Position
	local facing = (Vector3.new(0, pos.Y, 0) - pos).Unit
	local cf = CFrame.lookAt(pos, pos + facing)
	part({ Name = "PillarL", CFrame = cf * CFrame.new(-11, 9, 0), Size = Vector3.new(3, 18, 3), Color = Color3.fromRGB(60, 60, 66), Material = Enum.Material.Concrete, Parent = model })
	part({ Name = "PillarR", CFrame = cf * CFrame.new(11, 9, 0), Size = Vector3.new(3, 18, 3), Color = Color3.fromRGB(60, 60, 66), Material = Enum.Material.Concrete, Parent = model })
	local shutter = part({ Name = "Shutter", CFrame = cf * CFrame.new(0, 7, 0), Size = Vector3.new(19, 14, 0.6), Color = Color3.fromRGB(110, 112, 118), Material = Enum.Material.CorrodedMetal, Parent = model })
	local header = part({ Name = "Header", CFrame = cf * CFrame.new(0, 16, -0.4), Size = Vector3.new(25, 4, 1), Color = Color3.fromRGB(14, 14, 18), Parent = model })
	signText(header, Enum.NormalId.Front, gate.Name, Color3.fromRGB(255, 255, 255), Enum.Font.GothamBlack, { Brightness = 2 })
	signText(shutter, Enum.NormalId.Front, "LOCKED\nReputation: " .. gate.RequiredTier .. "\nComing soon", Color3.fromRGB(255, 220, 90), Enum.Font.GothamBold, { LightInfluence = 0.5 })
	return model
end

local function buildHub(parent)
	local hub = folder("Hub", parent)

	-- Ground plaza
	part({ Name = "Asphalt", CFrame = CFrame.new(0, -0.5, 0), Size = Vector3.new(420, 1, 340), Color = COLORS.Asphalt, Material = Enum.Material.Asphalt, Parent = hub })
	-- Walkway from spawn to pitch
	part({ Name = "Walkway", CFrame = CFrame.new(0, 0.05, 72), Size = Vector3.new(24, 0.1, 44), Color = COLORS.Concrete, Material = Enum.Material.Pavement, Parent = hub })

	-- Spawn
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "GroundsSpawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(12, 0.4, 12)
	spawn.CFrame = CFrame.new(Config.Hub.Spawn) * CFrame.Angles(0, 0, 0)
	spawn.Color = Config.Teams.A.Color
	spawn.Material = Enum.Material.Neon
	spawn.Transparency = 0.4
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Parent = hub

	-- Buildings around the edge, facing inwards
	local buildings = folder("Buildings", hub)
	local palette = {
		Color3.fromRGB(150, 70, 56),
		Color3.fromRGB(110, 100, 92),
		Color3.fromRGB(70, 82, 100),
		Color3.fromRGB(160, 120, 80),
		Color3.fromRGB(90, 60, 70),
	}
	local idx = 0
	for x = -180, 180, 45 do
		idx += 1
		local h = 30 + (idx * 13) % 28
		building(buildings, Vector3.new(x, 0, -150), Vector3.new(40, h, 18), palette[idx % #palette + 1], if idx % 2 == 0 then idx else nil, Vector3.new(0, 0, 1))
		building(buildings, Vector3.new(x, 0, 150), Vector3.new(40, h + 6, 18), palette[(idx + 2) % #palette + 1], if idx % 2 == 1 then idx else nil, Vector3.new(0, 0, -1))
	end
	for z = -110, 110, 55 do
		idx += 1
		local h = 28 + (idx * 7) % 24
		building(buildings, Vector3.new(-195, 0, z), Vector3.new(50, h, 16), palette[idx % #palette + 1], if idx % 3 == 0 then idx else nil, Vector3.new(1, 0, 0))
		building(buildings, Vector3.new(195, 0, z), Vector3.new(50, h, 16), palette[(idx + 1) % #palette + 1], if idx % 3 == 1 then idx else nil, Vector3.new(-1, 0, 0))
	end

	-- Street furniture
	local furniture = folder("Furniture", hub)
	for _, x in { -40, -20, 20, 40 } do
		bench(furniture, CFrame.lookAt(Vector3.new(x, 0, 48), Vector3.new(x, 0, 30)))
	end
	for _, x in { -25, 25 } do
		bench(furniture, CFrame.lookAt(Vector3.new(x, 0, 96), Vector3.new(0, 0, 96)))
	end
	for x = -150, 150, 50 do
		streetLight(furniture, Vector3.new(x, 0, 120))
		streetLight(furniture, Vector3.new(x, 0, -118))
	end
	for z = -80, 80, 40 do
		streetLight(furniture, Vector3.new(-165, 0, z))
		streetLight(furniture, Vector3.new(165, 0, z))
	end
	-- Cones and bins for life
	for i = 1, 10 do
		local a = i * 0.7
		part({
			Name = "Cone",
			CFrame = CFrame.new(Config.Hub.PracticeArea + Vector3.new(math.cos(a) * 12, 0.8, math.sin(a) * 12)),
			Size = Vector3.new(1, 1.6, 1),
			Color = Color3.fromRGB(255, 120, 30),
			Material = Enum.Material.Plastic,
			Parent = furniture,
		})
	end

	-- Physical leaderboard board (filled by LeaderboardService)
	part({
		Name = "Leaderboard",
		CFrame = CFrame.lookAt(Vector3.new(-56, 9, 60), Vector3.new(0, 9, 90)),
		Size = Vector3.new(18, 14, 1),
		Color = Color3.fromRGB(14, 14, 18),
		Parent = hub,
	})
	part({ Name = "LeaderboardLeg", CFrame = CFrame.new(-56, 1, 60), Size = Vector3.new(2, 2, 2), Color = COLORS.Fence, Parent = hub })

	buildLocker(hub)
	buildPractice(hub)
	for _, gate in Config.Hub.AreaGates do
		buildAreaGate(hub, gate)
	end

	return hub
end

function MapBuilder.Init()
	local existing = Workspace:FindFirstChild("Grounds")
	if existing then
		existing:Destroy()
	end
	-- Remove the default baseplate/spawn from a blank place
	for _, name in { "Baseplate", "SpawnLocation" } do
		local d = Workspace:FindFirstChild(name)
		if d then
			d:Destroy()
		end
	end

	root = folder("Grounds", Workspace)
	buildLighting()
	local pitches = folder("Pitches", root)
	for _, pitch in Config.Pitches do
		buildPitch(pitches, pitch)
	end
	buildHub(root)
	folder("Balls", root)
	folder("NPCs", root)
end

function MapBuilder.Start() end

function MapBuilder.GetRoot(): Folder
	return root
end

function MapBuilder.GetPitchModel(pitchId: string): Instance?
	return root and root.Pitches:FindFirstChild(pitchId)
end

return MapBuilder
