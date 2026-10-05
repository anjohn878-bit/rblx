-- Builds plant models out of simple parts from a seed definition (see Seeds.lua).
--
-- Stages: 1 = seed mound, 2 = sprout, 3 = young plant, 4 = full bloom.
-- The model's pivot ("Root") sits on the ground at the centre of the plant and
-- the plant faces +Z. A "Perch" attachment marks where visiting birds land.

local PlantBuilder = {}

local DIRT = Color3.fromRGB(100, 70, 45)
local SPROUT_GREEN = Color3.fromRGB(90, 170, 70)
local GOLDEN_ANGLE = math.rad(137.5)

local function newPart(model, name, size, cf, color, material, shape)
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cf
	part.Color = color
	part.Material = material or Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	if shape then
		part.Shape = shape
	end
	part.Parent = model
	return part
end

local function newEllipsoid(model, name, size, cf, color, material)
	local part = newPart(model, name, size, cf, color, material)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = part
	return part
end

local function newBall(model, name, diameter, position, color, material)
	return newPart(model, name, Vector3.one * diameter, CFrame.new(position), color, material, Enum.PartType.Ball)
end

-- A cylinder running from point a to point b.
local function newStem(model, name, a, b, width, color, material)
	local direction = b - a
	local length = direction.Magnitude
	local cf
	if math.abs(direction.Unit.Y) > 0.999 then
		-- straight up: lookAt is unreliable here, so just stand the cylinder up
		cf = CFrame.new((a + b) / 2) * CFrame.Angles(0, 0, math.rad(90))
	else
		cf = CFrame.lookAt((a + b) / 2, b) * CFrame.Angles(0, math.rad(90), 0)
	end
	return newPart(model, name, Vector3.new(length, width, width), cf, color, material, Enum.PartType.Cylinder)
end

-- A flat disc lying on the ground plane at the given height.
local function newDisc(model, name, diameter, thickness, position, color, material)
	local cf = CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90))
	return newPart(model, name, Vector3.new(thickness, diameter, diameter), cf, color, material, Enum.PartType.Cylinder)
end

local function newLeaf(model, position, yaw, tilt, size, color)
	local cf = CFrame.new(position) * CFrame.Angles(0, yaw, 0) * CFrame.Angles(0, 0, math.rad(tilt))
	-- offset so the leaf grows outward from the stem
	cf = cf * CFrame.new(size.X / 2 - 0.1, 0, 0)
	return newEllipsoid(model, "Leaf", size, cf, color)
end

local function addEffects(anchorPart, look)
	if look.Glow then
		local light = Instance.new("PointLight")
		light.Color = look.Glow
		light.Range = 14
		light.Brightness = 1.5
		light.Parent = anchorPart
	end
	if look.Fire then
		local fire = Instance.new("Fire")
		fire.Size = 4
		fire.Heat = 6
		fire.Color = Color3.fromRGB(255, 120, 30)
		fire.SecondaryColor = Color3.fromRGB(255, 220, 80)
		fire.Parent = anchorPart
	end
	if look.Sparkle then
		local sparkles = Instance.new("Sparkles")
		sparkles.SparkleColor = Color3.fromRGB(255, 230, 140)
		sparkles.Parent = anchorPart
	end
end

------------------------------------------------------------------------------
-- Styles. Each returns the local position birds should perch on.

local function buildFlower(model, look, s, bloom)
	local stemHeight = look.StemHeight * s
	local stemWidth = 0.28 * (look.StemWidth or 1) * s
	local heads = look.Heads or 1
	local tilt = math.rad(look.HeadTilt or 30)
	local perch = Vector3.new(0, stemHeight, 0)
	local highestHead = -math.huge

	-- leaves along the base / stem
	local leafCount = look.Leaves or 2
	for i = 1, leafCount do
		local height = (heads == 1) and stemHeight * (0.2 + 0.5 * (i - 1) / math.max(leafCount, 2)) or 0.3 * s
		local size = Vector3.new(1.6, 0.14, 0.7) * s
		newLeaf(model, Vector3.new(0, height, 0), i * GOLDEN_ANGLE, 25, size, look.LeafColor)
	end

	for i = 1, heads do
		local headPos, yaw
		if heads == 1 then
			headPos = Vector3.new(0, stemHeight, 0)
			yaw = 0
		else
			local angle = (i - 1) / heads * math.pi * 2 + 0.6
			local radius = (look.HeadSpread or 1.4) * s
			local height = stemHeight * ((i % 2 == 0) and 1 or 0.82)
			headPos = Vector3.new(math.cos(angle) * radius, height, math.sin(angle) * radius)
			yaw = math.pi / 2 - angle
		end
		newStem(model, "Stem", Vector3.zero, headPos, stemWidth, look.StemColor)
		if heads > 1 then
			-- a leaf halfway up each stem, pointing outward
			local outward = math.atan2(headPos.Z, headPos.X)
			newLeaf(model, headPos * 0.5, -outward, 20, Vector3.new(1.3, 0.14, 0.6) * s, look.LeafColor)
		end

		local face = CFrame.new(headPos) * CFrame.Angles(0, yaw, 0) * CFrame.Angles(-tilt, 0, 0)
		if bloom then
			local centerSize = (look.CenterSize or 0.6) * s
			local petalLength = (look.PetalLength or 1) * s
			local petalWidth = (look.PetalWidth or 0.5) * s
			local count = look.PetalCount or 8
			for p = 1, count do
				local petalCf = face
					* CFrame.Angles(0, 0, p / count * math.pi * 2)
					* CFrame.new(0, centerSize / 2 + petalLength / 2 - 0.15 * s, 0)
				newEllipsoid(
					model,
					"Petal",
					Vector3.new(petalWidth, petalLength, 0.12 * s),
					petalCf,
					look.PetalColor,
					look.PetalMaterial
				)
			end
			if look.InnerPetalColor then
				for p = 1, count do
					local petalCf = face
						* CFrame.Angles(0, 0, (p + 0.5) / count * math.pi * 2)
						* CFrame.new(0, centerSize / 2 + petalLength * 0.3 - 0.1 * s, 0.08 * s)
					newEllipsoid(
						model,
						"InnerPetal",
						Vector3.new(petalWidth * 0.7, petalLength * 0.6, 0.12 * s),
						petalCf,
						look.InnerPetalColor,
						look.PetalMaterial
					)
				end
			end
			local center = newEllipsoid(
				model,
				"FlowerCenter",
				Vector3.new(centerSize, centerSize, 0.35 * s),
				face * CFrame.new(0, 0, 0.1 * s),
				look.CenterColor,
				look.CenterMaterial
			)
			if i == 1 then
				addEffects(center, look)
			end
		else
			newEllipsoid(model, "Bud", Vector3.new(0.5, 0.75, 0.5) * s, CFrame.new(headPos), look.LeafColor)
		end

		if heads == 1 then
			-- stand on the upper petals
			local petalReach = ((look.CenterSize or 0.6) / 2 + (look.PetalLength or 1) * 0.35) * s
			perch = (face * CFrame.new(0, petalReach, 0.1 * s)).Position
		elseif headPos.Y > highestHead then
			-- stand in the middle of the tallest flower
			highestHead = headPos.Y
			perch = (face * CFrame.new(0, 0, 0.2 * s)).Position
		end
	end
	return perch
end

local function buildSpike(model, look, s, bloom)
	local stemHeight = look.StemHeight * s
	local stems = look.Stems or 7

	-- grassy clump of leaves
	for i = 1, 8 do
		local yaw = i * GOLDEN_ANGLE
		local cf = CFrame.Angles(0, yaw, 0) * CFrame.new(0.35 * s, 0.6 * s, 0) * CFrame.Angles(0, 0, math.rad(-18))
		newEllipsoid(model, "Leaf", Vector3.new(0.22, 1.5, 0.1) * s, cf, look.LeafColor)
	end

	local top = 0
	for i = 1, stems do
		local angle = i * GOLDEN_ANGLE
		local radius = (0.4 + 0.5 * ((i % 3) / 2)) * s
		local height = stemHeight * (0.82 + 0.18 * ((i * 7) % 5) / 4)
		local base = Vector3.new(math.cos(angle) * 0.2 * s, 0, math.sin(angle) * 0.2 * s)
		local tip = Vector3.new(math.cos(angle) * radius, height, math.sin(angle) * radius)
		newStem(model, "Stem", base, tip, 0.12 * s, look.StemColor)
		local dir = (tip - base).Unit
		if bloom then
			for b = 0, 5 do
				local position = tip - dir * (b * 0.26 * s)
				newBall(model, "Blossom", (0.42 - b * 0.02) * s, position, look.FlowerColor)
			end
		else
			newEllipsoid(
				model,
				"Bud",
				Vector3.new(0.2, 0.7, 0.2) * s,
				CFrame.lookAt(tip, tip + dir) * CFrame.Angles(math.rad(90), 0, 0),
				look.LeafColor
			)
		end
		top = math.max(top, tip.Y)
	end
	return Vector3.new(0, top + 0.2 * s, 0)
end

local function buildBush(model, look, s, bloom)
	local center = Vector3.new(0, 1.4 * s, 0)
	newEllipsoid(
		model,
		"Leaves",
		Vector3.new(3.4, 2.7, 3.4) * s,
		CFrame.new(center),
		look.LeafColor,
		Enum.Material.Grass
	)
	for i = 1, 4 do
		local angle = i * math.pi / 2 + math.pi / 4
		local position = Vector3.new(math.cos(angle) * 1.15 * s, 1.0 * s, math.sin(angle) * 1.15 * s)
		newEllipsoid(
			model,
			"Leaves",
			Vector3.new(2.2, 1.9, 2.2) * s,
			CFrame.new(position),
			look.LeafColor,
			Enum.Material.Grass
		)
	end
	newEllipsoid(
		model,
		"Leaves",
		Vector3.new(2.2, 1.8, 2.2) * s,
		CFrame.new(0, 2.5 * s, 0),
		look.LeafColor,
		Enum.Material.Grass
	)

	if bloom then
		for i = 1, 16 do
			local theta = i * GOLDEN_ANGLE
			local phi = math.rad(10 + (i * 37) % 60)
			local dir = Vector3.new(math.cos(theta) * math.cos(phi), math.sin(phi), math.sin(theta) * math.cos(phi))
			local position = center + Vector3.new(dir.X * 1.75, dir.Y * 1.45, dir.Z * 1.75) * s
			newBall(model, "Berry", 0.42 * s, position, look.BerryColor)
		end
	end
	return Vector3.new(0, 3.35 * s, 0)
end

local function buildTree(model, look, s, bloom)
	local trunkHeight = look.TrunkHeight * s
	newStem(
		model,
		"Trunk",
		Vector3.zero,
		Vector3.new(0, trunkHeight + 0.5 * s, 0),
		0.9 * s,
		look.TrunkColor,
		Enum.Material.Wood
	)
	for _, side in ipairs({ -1, 1 }) do
		newStem(
			model,
			"Branch",
			Vector3.new(0, trunkHeight * 0.55, 0),
			Vector3.new(side * 1.4 * s, trunkHeight * 0.95, side * 0.4 * s),
			0.4 * s,
			look.TrunkColor,
			Enum.Material.Wood
		)
	end

	local canopyBase = trunkHeight + 0.6 * s
	local leafMaterial = Enum.Material.Grass
	local canopy = {
		{ Vector3.new(0, canopyBase, 0), Vector3.new(4.6, 3.2, 4.6) },
		{ Vector3.new(1.6, canopyBase - 0.3, 0.9), Vector3.new(2.8, 2.4, 2.8) },
		{ Vector3.new(-1.6, canopyBase - 0.3, -0.9), Vector3.new(2.8, 2.4, 2.8) },
		{ Vector3.new(-1.1, canopyBase - 0.2, 1.4), Vector3.new(2.6, 2.2, 2.6) },
		{ Vector3.new(1.1, canopyBase - 0.2, -1.4), Vector3.new(2.6, 2.2, 2.6) },
		{ Vector3.new(0, canopyBase + 1.5 * s, 0), Vector3.new(2.8, 2.2, 2.8) },
	}
	local top
	for index, entry in ipairs(canopy) do
		local position = Vector3.new(entry[1].X * s, entry[1].Y, entry[1].Z * s)
		local part = newEllipsoid(model, "Canopy", entry[2] * s, CFrame.new(position), look.LeafColor, leafMaterial)
		part.Reflectance = look.LeafReflectance or 0
		if index == #canopy then
			top = part
		end
	end

	if bloom then
		for i = 1, 8 do
			local angle = i * math.pi * 2 / 8 + 0.3
			local radius = (1.7 + 0.4 * (i % 2)) * s
			local position =
				Vector3.new(math.cos(angle) * radius, canopyBase - (1.1 + 0.25 * (i % 3)) * s, math.sin(angle) * radius)
			newEllipsoid(
				model,
				"Fruit",
				Vector3.new(0.85, 1, 0.85) * (look.FruitSize or 0.6) * s,
				CFrame.new(position),
				look.FruitColor,
				look.FruitMaterial
			)
		end
		addEffects(top, look)
	end
	return Vector3.new(0, canopyBase + 2.55 * s, 0)
end

local function buildLotus(model, look, s, bloom)
	local stone = Color3.fromRGB(150, 145, 140)
	local water = Color3.fromRGB(80, 160, 220)
	newDisc(model, "PondRim", 6.4 * s, 0.5 * s, Vector3.new(0, 0.25 * s, 0), stone, Enum.Material.Slate)
	local pool = newDisc(model, "Water", 5.6 * s, 0.1 * s, Vector3.new(0, 0.5 * s, 0), water, Enum.Material.Glass)
	pool.Transparency = 0.25
	pool.Reflectance = 0.2

	local pads = {
		Vector3.new(1.4, 0, 0.9),
		Vector3.new(-1.5, 0, 0.6),
		Vector3.new(0.3, 0, -1.6),
		Vector3.new(0, 0, 0),
	}
	for _, offset in ipairs(pads) do
		newDisc(
			model,
			"LilyPad",
			1.7 * s,
			0.08 * s,
			Vector3.new(offset.X * s, 0.58 * s, offset.Z * s),
			look.PadColor,
			Enum.Material.SmoothPlastic
		)
	end

	local flowerBase = Vector3.new(0, 0.62 * s, 0)
	if bloom then
		for layer = 1, 2 do
			local count = layer == 1 and 8 or 6
			local outward = layer == 1 and 62 or 30
			local length = layer == 1 and 1.4 or 1.1
			local color = layer == 1 and look.PetalColor or look.InnerPetalColor
			for p = 1, count do
				local cf = CFrame.new(flowerBase)
					* CFrame.Angles(0, (p + layer * 0.5) / count * math.pi * 2, 0)
					* CFrame.Angles(math.rad(outward), 0, 0)
					* CFrame.new(0, length * s / 2, 0)
				newEllipsoid(
					model,
					"Petal",
					Vector3.new(0.7 * s, length * s, 0.14 * s),
					cf,
					color,
					Enum.Material.SmoothPlastic
				)
			end
		end
		local center = newBall(
			model,
			"FlowerCenter",
			0.55 * s,
			flowerBase + Vector3.new(0, 0.3 * s, 0),
			look.CenterColor,
			Enum.Material.Neon
		)
		local light = Instance.new("PointLight")
		light.Color = look.PetalColor
		light.Range = 10
		light.Brightness = 1
		light.Parent = center
	else
		newEllipsoid(
			model,
			"Bud",
			Vector3.new(0.7, 1.1, 0.7) * s,
			CFrame.new(flowerBase + Vector3.new(0, 0.5 * s, 0)),
			look.PetalColor
		)
	end

	-- birds stand on the stone rim of the pond
	return Vector3.new(2.95 * s, 0.5 * s, 0.5 * s)
end

local STYLES = {
	Flower = buildFlower,
	Spike = buildSpike,
	Bush = buildBush,
	Tree = buildTree,
	Lotus = buildLotus,
}

local function buildSeedling(model, look, stage)
	newEllipsoid(model, "Mound", Vector3.new(2.4, 0.7, 2.4), CFrame.new(0, 0.05, 0), DIRT, Enum.Material.Ground)
	local green = SPROUT_GREEN
	if stage == 1 then
		newStem(model, "Sprout", Vector3.new(0, 0.2, 0), Vector3.new(0, 0.75, 0), 0.16, green)
		return Vector3.new(0, 0.8, 0)
	end
	newStem(model, "Stem", Vector3.new(0, 0.2, 0), Vector3.new(0, 1.5, 0), 0.2, look.StemColor or green)
	newLeaf(model, Vector3.new(0, 1.4, 0), 0, 25, Vector3.new(1.0, 0.12, 0.5), look.LeafColor or green)
	newLeaf(model, Vector3.new(0, 1.4, 0), math.pi, 25, Vector3.new(1.0, 0.12, 0.5), look.LeafColor or green)
	newLeaf(model, Vector3.new(0, 0.9, 0), math.pi / 2, 30, Vector3.new(0.8, 0.12, 0.4), look.LeafColor or green)
	return Vector3.new(0, 1.6, 0)
end

-- Returns a Model for the given seed at the given growth stage (1-4).
function PlantBuilder.Build(seed, stage, scaleOverride)
	local model = Instance.new("Model")
	model.Name = seed.Id

	local root = Instance.new("Part")
	root.Name = "Root"
	root.Size = Vector3.new(0.2, 0.2, 0.2)
	root.CFrame = CFrame.identity
	root.Transparency = 1
	root.Anchored = true
	root.CanCollide = false
	root.CanTouch = false
	root.CanQuery = false
	root.Parent = model
	model.PrimaryPart = root

	local perch
	if stage <= 2 then
		perch = buildSeedling(model, seed.Look, stage)
	else
		local scale = scaleOverride or (stage == 3 and 0.6 or 1)
		perch = STYLES[seed.Look.Style](model, seed.Look, scale, stage >= 4)
	end

	local perchAttachment = Instance.new("Attachment")
	perchAttachment.Name = "Perch"
	perchAttachment.Position = perch
	perchAttachment.Parent = root

	local boxCf, size = model:GetBoundingBox()
	model:SetAttribute("TopY", boxCf.Position.Y + size.Y / 2)
	return model
end

return PlantBuilder
