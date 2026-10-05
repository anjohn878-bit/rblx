--!strict
-- Procedural plant models built from primitive parts (no uploaded assets needed).
-- Every plant is authored at full size with its root at the soil surface.
--   * parts tagged "Bud"   are visible while the plant is growing
--   * parts tagged "Bloom" are visible once it is fully grown
--   * effects tagged "BloomFX" (particles, lights) switch on at full growth

local PlantModels = {}

local Builder = {}
Builder.__index = Builder

type BuilderData = { model: Model, origin: CFrame }
type Builder = typeof(setmetatable({} :: BuilderData, Builder))

local PLASTIC = Enum.Material.SmoothPlastic

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local function newPart(
	self: Builder,
	name: string,
	size: Vector3,
	cf: CFrame,
	color: Color3,
	material: Enum.Material?,
	kind: string?
): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = material or PLASTIC
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CFrame = self.origin * cf
	if kind then
		p:SetAttribute(kind, true)
	end
	p.Parent = self.model
	return p
end

-- Squashed sphere (ellipsoid)
function Builder.blob(
	self: Builder,
	name: string,
	size: Vector3,
	cf: CFrame,
	color: Color3,
	material: Enum.Material?,
	kind: string?
): Part
	local p = newPart(self, name, size, cf, color, material, kind)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = p
	return p
end

function Builder.block(
	self: Builder,
	name: string,
	size: Vector3,
	cf: CFrame,
	color: Color3,
	material: Enum.Material?,
	kind: string?
): Part
	return newPart(self, name, size, cf, color, material, kind)
end

-- Upright cylinder; `cf` is the centre (rotate it to lean the stem).
function Builder.stem(
	self: Builder,
	name: string,
	height: number,
	diameter: number,
	cf: CFrame,
	color: Color3,
	material: Enum.Material?,
	kind: string?
): Part
	local p = newPart(
		self,
		name,
		Vector3.new(height, diameter, diameter),
		cf * CFrame.Angles(0, 0, math.rad(90)),
		color,
		material,
		kind
	)
	p.Shape = Enum.PartType.Cylinder
	return p
end

-- Flat disc whose face looks along `cf`'s look vector (-Z).
function Builder.disc(
	self: Builder,
	name: string,
	thickness: number,
	diameter: number,
	cf: CFrame,
	color: Color3,
	material: Enum.Material?,
	kind: string?
): Part
	local p = newPart(
		self,
		name,
		Vector3.new(thickness, diameter, diameter),
		cf * CFrame.Angles(0, math.rad(90), 0),
		color,
		material,
		kind
	)
	p.Shape = Enum.PartType.Cylinder
	return p
end

function Builder.fx(self: Builder, parent: BasePart, emitter: ParticleEmitter)
	emitter.Name = "BloomFX"
	emitter:SetAttribute("BloomFX", true)
	emitter.Enabled = false
	emitter.Parent = parent
end

function Builder.light(self: Builder, parent: BasePart, color: Color3, range: number, brightness: number)
	local light = Instance.new("PointLight")
	light.Name = "BloomFX"
	light:SetAttribute("BloomFX", true)
	light.Color = color
	light.Range = range
	light.Brightness = brightness
	light.Enabled = false
	light.Parent = parent
end

-- A small invisible anchor part that particle emitters can be parented to.
function Builder.anchor(self: Builder, name: string, size: Vector3, cf: CFrame): Part
	local p = newPart(self, name, size, cf, rgb(255, 255, 255), PLASTIC, nil)
	p.Transparency = 1
	return p
end

local function sparkle(color: Color3, rate: number, lifetime: number, size: number, speed: number): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Color = ColorSequence.new(color)
	e.Rate = rate
	e.Lifetime = NumberRange.new(lifetime * 0.7, lifetime)
	e.Speed = NumberRange.new(speed * 0.5, speed)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.3, size),
		NumberSequenceKeypoint.new(1, 0),
	})
	e.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.2, 0.1),
		NumberSequenceKeypoint.new(1, 1),
	})
	e.LightEmission = 0.8
	e.Drag = 1
	e.Acceleration = Vector3.new(0, 0.5, 0)
	e.Rotation = NumberRange.new(0, 360)
	e.RotSpeed = NumberRange.new(-40, 40)
	return e
end

local function petalFall(color: Color3): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Color = ColorSequence.new(color)
	e.Rate = 6
	e.Lifetime = NumberRange.new(3, 4.5)
	e.Speed = NumberRange.new(0.5, 1.5)
	e.EmissionDirection = Enum.NormalId.Bottom
	e.SpreadAngle = Vector2.new(60, 60)
	e.Size = NumberSequence.new(0.35)
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
	e.Acceleration = Vector3.new(0, -1.5, 0)
	e.Rotation = NumberRange.new(0, 360)
	e.RotSpeed = NumberRange.new(-120, 120)
	return e
end

local BARK = rgb(112, 78, 54)

------------------------------------------------------------------------------
-- Individual plants
------------------------------------------------------------------------------

local builders: { [string]: (b: Builder) -> () } = {}

function builders.sunflower(b)
	local stemColor = rgb(70, 140, 60)
	b:stem("Stem", 4.2, 0.36, CFrame.new(0, 2.1, 0), stemColor, nil, nil)
	b:blob(
		"Leaf",
		Vector3.new(1.6, 0.12, 0.8),
		CFrame.new(0.9, 1.4, 0) * CFrame.Angles(0, 0, math.rad(22)),
		rgb(84, 168, 70),
		nil,
		nil
	)
	b:blob(
		"Leaf",
		Vector3.new(1.6, 0.12, 0.8),
		CFrame.new(-0.9, 2.0, 0) * CFrame.Angles(0, 0, math.rad(-22)),
		rgb(84, 168, 70),
		nil,
		nil
	)

	-- The flower head looks up and out so birds can perch right on the seeds.
	local head = CFrame.new(0, 4.65, 0) * CFrame.Angles(math.rad(45), 0, 0)
	b:blob("Bud", Vector3.new(1.4, 1.4, 1.4), CFrame.new(0, 4.5, 0), rgb(92, 172, 72), nil, "Bud")
	b:disc("HeadDisc", 0.3, 3.0, head, rgb(255, 205, 40), nil, "Bloom")
	for i = 0, 9 do
		local a = i / 10 * math.pi * 2
		local color = if i % 2 == 0 then rgb(255, 196, 24) else rgb(255, 170, 20)
		b:blob(
			"Petal",
			Vector3.new(1.1, 0.55, 0.14),
			head * CFrame.Angles(0, 0, a) * CFrame.new(1.75, 0, 0.02),
			color,
			nil,
			"Bloom"
		)
	end
	b:disc("Seeds", 0.5, 1.8, head * CFrame.new(0, 0, -0.1), rgb(88, 58, 36), nil, "Bloom")
	local glow = b:anchor("FXAnchor", Vector3.new(2, 0.2, 2), CFrame.new(0, 5.2, 0))
	b:fx(glow, sparkle(rgb(255, 228, 120), 3, 2, 0.35, 2))
end

function builders.berrybush(b)
	local greens = { rgb(66, 140, 62), rgb(76, 154, 68), rgb(58, 126, 56), rgb(72, 148, 64), rgb(62, 134, 60) }
	local blobs = {
		{ Vector3.new(3.4, 2.4, 3.2), Vector3.new(0, 1.2, 0) },
		{ Vector3.new(2.4, 2.0, 2.2), Vector3.new(1.3, 1.0, 0.6) },
		{ Vector3.new(2.4, 2.1, 2.3), Vector3.new(-1.2, 1.1, -0.5) },
		{ Vector3.new(2.6, 2.1, 2.4), Vector3.new(0.3, 2.1, -0.4) },
		{ Vector3.new(2.0, 1.7, 2.0), Vector3.new(-0.6, 1.8, 0.8) },
	}
	for i, spec in blobs do
		b:blob("Foliage", spec[1], CFrame.new(spec[2]), greens[i], Enum.Material.Grass, nil)
	end
	-- Berries sit on the surface of the main mass of leaves.
	for i = 1, 18 do
		local a = i * 2.39996
		local e = 0.15 + (i % 5) * 0.22
		local pos =
			Vector3.new(1.75 * math.cos(e) * math.cos(a), 1.2 + 1.5 * math.sin(e), 1.65 * math.cos(e) * math.sin(a))
		local color = if i % 3 == 0 then rgb(86, 64, 176) else rgb(196, 30, 76)
		b:blob("Berry", Vector3.new(0.5, 0.5, 0.5), CFrame.new(pos), color, nil, "Bloom")
	end
	local flowerGlow = b:anchor("FXAnchor", Vector3.new(3, 0.2, 3), CFrame.new(0, 3, 0))
	b:fx(flowerGlow, sparkle(rgb(255, 150, 190), 3, 2, 0.3, 1.5))
end

function builders.cherry(b)
	b:stem("Trunk", 5.6, 1.1, CFrame.new(0, 2.8, 0), BARK, Enum.Material.Wood, nil)
	b:stem(
		"Branch",
		3.4,
		0.6,
		CFrame.new(1.3, 6.1, 0) * CFrame.Angles(0, 0, math.rad(-35)),
		BARK,
		Enum.Material.Wood,
		nil
	)
	b:stem(
		"Branch",
		3.4,
		0.6,
		CFrame.new(-1.4, 5.9, 0) * CFrame.Angles(0, 0, math.rad(38)),
		BARK,
		Enum.Material.Wood,
		nil
	)

	local canopy = {
		{ Vector3.new(5.6, 4.2, 5.3), Vector3.new(0, 8.3, 0) },
		{ Vector3.new(4.2, 3.4, 4.0), Vector3.new(2.8, 7.9, 0.4) },
		{ Vector3.new(4.2, 3.2, 4.0), Vector3.new(-2.9, 7.5, 0.4) },
		{ Vector3.new(3.8, 2.8, 3.6), Vector3.new(0.2, 9.2, -0.5) },
		{ Vector3.new(3.6, 2.8, 3.6), Vector3.new(0.2, 7.4, 2.3) },
	}
	for _, spec in canopy do
		b:blob("Leaves", spec[1], CFrame.new(spec[2]), rgb(92, 170, 80), Enum.Material.Grass, "Bud")
		b:blob(
			"Blossoms",
			spec[1] * 1.03,
			CFrame.new(spec[2]),
			rgb(255, 172, 202),
			Enum.Material.SmoothPlastic,
			"Bloom"
		)
	end
	for i = 1, 8 do
		local a = i * 2.4
		local pos = Vector3.new(2.6 * math.cos(a), 8.6 + (i % 3) * 0.8, 2.5 * math.sin(a))
		b:blob("Blossom", Vector3.new(0.8, 0.8, 0.8), CFrame.new(pos), rgb(255, 214, 230), nil, "Bloom")
	end
	local petals = b:anchor("FXAnchor", Vector3.new(7, 0.2, 7), CFrame.new(0, 9, 0))
	b:fx(petals, petalFall(rgb(255, 190, 215)))
end

local function hibiscusFlower(b: Builder, pos: Vector3, outward: Vector3)
	local base = CFrame.lookAt(pos, pos + outward)
	for i = 0, 4 do
		local a = i / 5 * math.pi * 2
		local color = if i % 2 == 0 then rgb(255, 64, 90) else rgb(255, 92, 110)
		b:blob(
			"Petal",
			Vector3.new(1.4, 1.1, 0.2),
			base * CFrame.Angles(0, 0, a) * CFrame.new(0.7, 0, 0),
			color,
			nil,
			"Bloom"
		)
	end
	b:disc("Heart", 0.25, 0.8, base * CFrame.new(0, 0, -0.1), rgb(255, 150, 40), nil, "Bloom")
	b:blob("Stamen", Vector3.new(0.22, 0.22, 0.9), base * CFrame.new(0, 0, -0.5), rgb(255, 224, 80), nil, "Bloom")
	b:blob("FlowerBud", Vector3.new(0.7, 1.1, 0.7), CFrame.new(pos), rgb(214, 70, 80), nil, "Bud")
end

function builders.hibiscus(b)
	local dark = rgb(44, 128, 62)
	b:stem("Stem", 3.4, 0.6, CFrame.new(0, 1.7, 0), rgb(96, 84, 52), Enum.Material.Wood, nil)
	b:stem(
		"Stem",
		3.0,
		0.45,
		CFrame.new(1.1, 1.6, 0) * CFrame.Angles(0, 0, math.rad(-24)),
		rgb(96, 84, 52),
		Enum.Material.Wood,
		nil
	)
	b:stem(
		"Stem",
		3.0,
		0.45,
		CFrame.new(-1.1, 1.6, 0) * CFrame.Angles(0, 0, math.rad(24)),
		rgb(96, 84, 52),
		Enum.Material.Wood,
		nil
	)
	b:blob("Foliage", Vector3.new(4.8, 3.4, 4.6), CFrame.new(0, 3.6, 0), dark, Enum.Material.Grass, nil)
	b:blob("Foliage", Vector3.new(3.4, 2.6, 3.2), CFrame.new(2.3, 3.1, 0.2), rgb(52, 140, 66), Enum.Material.Grass, nil)
	b:blob(
		"Foliage",
		Vector3.new(3.4, 2.6, 3.2),
		CFrame.new(-2.3, 3.3, -0.3),
		rgb(40, 120, 58),
		Enum.Material.Grass,
		nil
	)
	b:blob("Foliage", Vector3.new(3.4, 2.7, 3.2), CFrame.new(0.4, 5.0, 0.1), rgb(50, 136, 64), Enum.Material.Grass, nil)

	hibiscusFlower(b, Vector3.new(1.0, 3.6, 2.35), Vector3.new(0.2, 0.2, 1))
	hibiscusFlower(b, Vector3.new(-1.5, 3.9, -2.2), Vector3.new(-0.2, 0.3, -1))
	hibiscusFlower(b, Vector3.new(3.6, 3.6, 0.3), Vector3.new(1, 0.3, 0.1))
	hibiscusFlower(b, Vector3.new(-3.9, 3.2, 0.3), Vector3.new(-1, 0.2, 0.1))
	hibiscusFlower(b, Vector3.new(2.0, 5.5, 1.5), Vector3.new(0.5, 0.6, 0.8))
	local glow = b:anchor("FXAnchor", Vector3.new(4, 0.2, 4), CFrame.new(0, 5.5, 0))
	b:fx(glow, sparkle(rgb(255, 120, 150), 4, 2, 0.35, 2))
end

function builders.goldenapple(b)
	b:blob("RootFlare", Vector3.new(3.4, 1.4, 3.4), CFrame.new(0, 0.5, 0), BARK, Enum.Material.Wood, nil)
	b:stem("Trunk", 8, 2.0, CFrame.new(0, 4, 0), BARK, Enum.Material.Wood, nil)
	b:stem(
		"Branch",
		4.4,
		0.9,
		CFrame.new(2, 8.2, 0.3) * CFrame.Angles(0, 0, math.rad(-45)),
		BARK,
		Enum.Material.Wood,
		nil
	)
	b:stem(
		"Branch",
		4.4,
		0.9,
		CFrame.new(-2, 8, -0.3) * CFrame.Angles(0, 0, math.rad(45)),
		BARK,
		Enum.Material.Wood,
		nil
	)

	local mainCenter, mainRadii = Vector3.new(0, 11.5, 0), Vector3.new(4.5, 3.25, 4.25)
	b:blob("Canopy", mainRadii * 2, CFrame.new(mainCenter), rgb(66, 148, 58), Enum.Material.Grass, nil)
	b:blob("Canopy", Vector3.new(5, 4.6, 5), CFrame.new(3.6, 10.4, 0.8), rgb(74, 158, 64), Enum.Material.Grass, nil)
	b:blob("Canopy", Vector3.new(5, 4.6, 5), CFrame.new(-3.7, 10, -0.6), rgb(60, 140, 54), Enum.Material.Grass, nil)

	-- Fruit hangs on the surface of the main canopy: unripe green, then gold.
	for i = 1, 16 do
		local a = i * 2.39996
		local e = -0.55 + (i % 5) * 0.27
		local pos = mainCenter
			+ Vector3.new(
				mainRadii.X * math.cos(e) * math.cos(a),
				mainRadii.Y * math.sin(e),
				mainRadii.Z * math.cos(e) * math.sin(a)
			)
		b:blob("UnripeApple", Vector3.new(0.6, 0.6, 0.6), CFrame.new(pos), rgb(150, 190, 70), nil, "Bud")
		local apple = b:blob(
			"GoldenApple",
			Vector3.new(1, 1, 1),
			CFrame.new(pos),
			rgb(255, 196, 40),
			Enum.Material.Metal,
			"Bloom"
		)
		apple.Reflectance = 0.15
	end
	local glow = b:anchor("FXAnchor", Vector3.new(9, 0.2, 9), CFrame.new(0, 11, 0))
	b:fx(glow, sparkle(rgb(255, 214, 90), 8, 3, 0.5, 2.5))
	b:light(glow, rgb(255, 200, 90), 22, 0.8)
end

function builders.starbloom(b)
	local deep = rgb(58, 40, 112)
	b:stem("Trunk", 9, 1.6, CFrame.new(0, 4.5, 0), deep, Enum.Material.SmoothPlastic, nil)
	b:stem("Vein", 8.6, 0.26, CFrame.new(0.55, 4.4, 0.3), rgb(120, 255, 240), Enum.Material.Neon, "Bloom")
	b:stem("Vein", 8.6, 0.26, CFrame.new(-0.5, 4.4, -0.35), rgb(255, 150, 240), Enum.Material.Neon, "Bloom")
	b:stem(
		"Branch",
		4.6,
		0.8,
		CFrame.new(2.4, 8.6, 0) * CFrame.Angles(0, 0, math.rad(-48)),
		deep,
		Enum.Material.SmoothPlastic,
		nil
	)
	b:stem(
		"Branch",
		4.6,
		0.8,
		CFrame.new(-2.4, 8.6, 0) * CFrame.Angles(0, 0, math.rad(48)),
		deep,
		Enum.Material.SmoothPlastic,
		nil
	)

	local canopy = {
		{ size = Vector3.new(7, 5, 7), pos = Vector3.new(0, 13, 0), color = rgb(150, 110, 255) },
		{ size = Vector3.new(4.6, 4, 4.6), pos = Vector3.new(3.8, 10.6, 0), color = rgb(100, 200, 255) },
		{ size = Vector3.new(4.6, 4, 4.6), pos = Vector3.new(-3.8, 10.6, 0), color = rgb(255, 130, 224) },
		{ size = Vector3.new(4.2, 3.6, 4.2), pos = Vector3.new(0, 10.4, 3.6), color = rgb(130, 255, 205) },
		{ size = Vector3.new(4.2, 3.6, 4.2), pos = Vector3.new(0, 10.4, -3.6), color = rgb(255, 214, 120) },
	}
	for _, spec in canopy do
		b:blob("NightLeaves", spec.size, CFrame.new(spec.pos), rgb(52, 46, 128), Enum.Material.SmoothPlastic, "Bud")
		b:blob("StarLeaves", spec.size * 1.03, CFrame.new(spec.pos), spec.color, Enum.Material.Neon, "Bloom")
	end
	-- Floating star shards orbiting the crown.
	for i = 1, 10 do
		local a = i * 2.39996
		local pos = Vector3.new(math.cos(a) * (7.5 + (i % 3)), 8.5 + (i % 5) * 1.7, math.sin(a) * (7.5 + (i % 3)))
		local color = if i % 2 == 0 then rgb(255, 250, 190) else rgb(190, 235, 255)
		b:block(
			"Shard",
			Vector3.new(0.6, 0.6, 0.6),
			CFrame.new(pos) * CFrame.Angles(math.rad(45), math.rad(45), 0),
			color,
			Enum.Material.Neon,
			"Bloom"
		)
	end
	local glow = b:anchor("FXAnchor", Vector3.new(10, 0.2, 10), CFrame.new(0, 12, 0))
	local e = sparkle(rgb(255, 255, 255), 14, 3.5, 0.55, 3)
	e.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, rgb(120, 255, 240)),
		ColorSequenceKeypoint.new(0.5, rgb(190, 130, 255)),
		ColorSequenceKeypoint.new(1, rgb(255, 130, 224)),
	})
	b:fx(glow, e)
	b:light(glow, rgb(170, 130, 255), 30, 1.4)
end

------------------------------------------------------------------------------
-- Public API
------------------------------------------------------------------------------

-- Shows the right half of a plant: growing look vs blooming look.
function PlantModels.setMature(model: Model, mature: boolean)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			if d:GetAttribute("Bloom") then
				d.Transparency = if mature then 0 else 1
			elseif d:GetAttribute("Bud") then
				d.Transparency = if mature then 1 else 0
			end
		elseif d:GetAttribute("BloomFX") then
			(d :: any).Enabled = mature
		end
	end
	model:SetAttribute("Mature", mature)
end

function PlantModels.build(seedId: string, origin: CFrame, mature: boolean): Model?
	local builder = builders[seedId]
	if not builder then
		return nil
	end
	local model = Instance.new("Model")
	model.Name = "Plant"

	local root = Instance.new("Part")
	root.Name = "Root"
	root.Size = Vector3.new(1, 0.2, 1)
	root.Transparency = 1
	root.Anchored = true
	root.CanCollide = false
	root.CanTouch = false
	root.CanQuery = false
	root.CFrame = origin
	root.Parent = model
	model.PrimaryPart = root

	builder(setmetatable({ model = model, origin = origin }, Builder))
	PlantModels.setMature(model, mature)
	return model
end

return PlantModels
