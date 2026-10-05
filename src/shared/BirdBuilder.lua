-- Builds bird models out of simple parts from a bird definition (see Birds.lua).
--
-- The model faces -Z (its LookVector). "Body" is the anchored PrimaryPart;
-- every other part is welded to it, so moving Body moves the whole bird.
-- Wings and head use named Welds ("Hinge", "Neck") that the client animates.

local BirdBuilder = {}

local DEFAULT_LEGS = Color3.fromRGB(90, 70, 60)
local DEFAULT_EYE = Color3.fromRGB(20, 20, 20)

local function newPart(name, size, color, material, shape)
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Color = color
	part.Material = material or Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.Massless = true
	part.Anchored = false
	if shape then
		part.Shape = shape
	end
	return part
end

local function newEllipsoid(name, size, color, material)
	local part = newPart(name, size, color, material)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = part
	return part
end

-- Welds `part` to `parent` so that part.CFrame == parent.CFrame * c0 * c1:Inverse().
local function weldTo(model, part, parent, c0, c1, jointName)
	c1 = c1 or CFrame.identity
	part.CFrame = parent.CFrame * c0 * c1:Inverse()
	local weld = Instance.new("Weld")
	weld.Name = jointName or "Joint"
	weld.Part0 = parent
	weld.Part1 = part
	weld.C0 = c0
	weld.C1 = c1
	weld.Parent = part
	part.Parent = model
	return weld
end

local function buildTail(model, body, look, s, material)
	local style = look.TailStyle or "Short"
	local color = look.Tail or look.Body
	local length = look.TailLength or 0.9

	if style == "Fan" then
		-- Peacock: a big upright fan of feathers with eye spots.
		local pivot = CFrame.new(0, 0.3 * s, 0.85 * s) * CFrame.Angles(math.rad(12), 0, 0)
		local count = 11
		for i = 1, count do
			local angle = math.rad(-80 + (i - 1) * (160 / (count - 1)))
			local feather = newEllipsoid("TailFeather", Vector3.new(0.7, 3.4, 0.12) * s, color, material)
			local featherCf = pivot * CFrame.Angles(0, 0, angle) * CFrame.new(0, 1.7 * s, 0)
			weldTo(model, feather, body, featherCf)
			local ring =
				newEllipsoid("TailRing", Vector3.new(0.55, 0.65, 0.14) * s, look.TailSpotRing or color, material)
			weldTo(model, ring, body, featherCf * CFrame.new(0, 1.1 * s, -0.02 * s))
			local spot = newEllipsoid("TailSpot", Vector3.new(0.3, 0.38, 0.16) * s, look.TailSpot or color, material)
			weldTo(model, spot, body, featherCf * CFrame.new(0, 1.1 * s, -0.04 * s))
		end
	elseif style == "Flame" then
		-- Phoenix: several long glowing streamers.
		for i, spread in ipairs({ -14, 0, 14 }) do
			local streamerLength = length * (i == 2 and 1 or 0.8)
			local streamer = newEllipsoid("TailFeather", Vector3.new(0.35, 0.12, streamerLength) * s, color, material)
			local cf = CFrame.new(0, 0.1 * s, 0.8 * s)
				* CFrame.Angles(math.rad(-12), math.rad(spread), 0)
				* CFrame.new(0, 0, streamerLength * s / 2)
			weldTo(model, streamer, body, cf)
		end
	else
		local angle = look.TailAngle or -20
		local tail = newEllipsoid("Tail", Vector3.new(0.75, 0.15, length) * s, color, material)
		local cf = CFrame.new(0, 0.15 * s, 0.8 * s)
			* CFrame.Angles(math.rad(angle), 0, 0)
			* CFrame.new(0, 0, length * s / 2)
		weldTo(model, tail, body, cf)
	end
end

function BirdBuilder.Build(def, options)
	options = options or {}
	local look = def.Look
	local s = (look.Size or 1) * (options.Scale or 1)
	local material = look.Material or Enum.Material.SmoothPlastic
	local shape = look.BodyShape or Vector3.one

	local model = Instance.new("Model")
	model.Name = def.Id

	-- Body
	local body = newEllipsoid("Body", Vector3.new(1.4 * shape.X, 1.25 * shape.Y, 2 * shape.Z) * s, look.Body, material)
	body.Anchored = true
	body.CFrame = CFrame.identity
	body.Reflectance = look.Reflectance or 0
	body.Parent = model
	model.PrimaryPart = body

	if look.Belly then
		local belly =
			newEllipsoid("Belly", Vector3.new(1.15 * shape.X, 1.0 * shape.Y, 1.5 * shape.Z) * s, look.Belly, material)
		weldTo(model, belly, body, CFrame.new(0, -0.2 * s, -0.3 * shape.Z * s))
	end

	-- Neck (only for long-necked birds) and head
	local neckLength = look.NeckLength or 0
	local headOffset = look.HeadOffset or Vector3.new(0, 0.7, -0.8)
	local headPosition = Vector3.new(headOffset.X, headOffset.Y + neckLength, headOffset.Z) * s
	if neckLength > 0 then
		local neck = newEllipsoid("NeckFeathers", Vector3.new(0.34, neckLength + 0.8, 0.34) * s, look.Body, material)
		weldTo(model, neck, body, CFrame.new(0, (0.35 + neckLength / 2) * s, -0.75 * s))
	end

	local hs = look.HeadSize or 1
	local head = newEllipsoid("Head", Vector3.new(0.95, 0.95, 0.95) * hs * s, look.Head or look.Body, material)
	head.Reflectance = look.Reflectance or 0
	weldTo(model, head, body, CFrame.new(headPosition), nil, "Neck")

	-- Beak
	local beakLength = look.BeakLength or 0.45
	local beakWidth = look.BeakWidth or 0.3
	local beak = newEllipsoid("Beak", Vector3.new(beakWidth, beakWidth * 0.75, beakLength) * s, look.Beak, material)
	weldTo(
		model,
		beak,
		head,
		CFrame.new(0, -0.06 * s, -(0.42 * hs + beakLength / 2 - 0.08) * s) * CFrame.Angles(math.rad(-8), 0, 0)
	)

	-- Eyes
	local eyeColor = look.Eye or DEFAULT_EYE
	for _, side in ipairs({ -1, 1 }) do
		if look.BigEyes then
			local eye = newPart("Eye", Vector3.one * 0.3 * hs * s, eyeColor, Enum.Material.Neon, Enum.PartType.Ball)
			weldTo(model, eye, head, CFrame.new(side * 0.2 * hs * s, 0.08 * hs * s, -0.37 * hs * s))
			local pupil = newPart(
				"Pupil",
				Vector3.one * 0.15 * hs * s,
				DEFAULT_EYE,
				Enum.Material.SmoothPlastic,
				Enum.PartType.Ball
			)
			weldTo(model, pupil, head, CFrame.new(side * 0.2 * hs * s, 0.08 * hs * s, -0.47 * hs * s))
		else
			local eye =
				newPart("Eye", Vector3.one * 0.17 * hs * s, eyeColor, Enum.Material.SmoothPlastic, Enum.PartType.Ball)
			weldTo(model, eye, head, CFrame.new(side * 0.33 * hs * s, 0.12 * hs * s, -0.3 * hs * s))
		end
	end

	-- Head decorations
	if look.Crest then
		local crest = newEllipsoid("Crest", Vector3.new(0.18, 0.6, 0.45) * hs * s, look.Crest, material)
		weldTo(model, crest, head, CFrame.new(0, 0.5 * hs * s, 0.12 * hs * s) * CFrame.Angles(math.rad(28), 0, 0))
	end
	if look.Cap then
		local cap = newEllipsoid("Cap", Vector3.new(0.8, 0.45, 0.75) * hs * s, look.Cap, material)
		weldTo(model, cap, head, CFrame.new(0, 0.3 * hs * s, -0.08 * hs * s))
	end
	if look.Mask then
		local mask = newEllipsoid("Mask", Vector3.new(0.7, 0.5, 0.35) * hs * s, look.Mask, material)
		weldTo(model, mask, head, CFrame.new(0, -0.05 * hs * s, -0.33 * hs * s))
	end

	-- Wings (hinged so the client can flap them)
	local wingColor = look.Wing or look.Body
	for _, side in ipairs({ -1, 1 }) do
		local wing =
			newEllipsoid(side < 0 and "LeftWing" or "RightWing", Vector3.new(0.18, 0.85, 1.55) * s, wingColor, material)
		wing.Reflectance = look.Reflectance or 0
		local hinge = CFrame.new(side * 0.62 * shape.X * s, 0.3 * s, -0.15 * s)
		local offset = CFrame.new(side * 0.08 * s, -0.32 * s, 0.25 * s)
		weldTo(model, wing, body, hinge, offset:Inverse(), "Hinge")
		if look.WingTip then
			local tip = newEllipsoid("WingTip", Vector3.new(0.2, 0.5, 0.8) * s, look.WingTip, material)
			weldTo(model, tip, wing, CFrame.new(0, -0.15 * s, 0.45 * s))
		end
	end

	buildTail(model, body, look, s, material)

	-- Legs and feet
	local legLength = look.LegLength or 0.5
	local legColor = look.Legs or DEFAULT_LEGS
	for _, side in ipairs({ -1, 1 }) do
		local leg = newPart("Leg", Vector3.new(0.13, legLength, 0.13) * s, legColor, Enum.Material.SmoothPlastic)
		weldTo(model, leg, body, CFrame.new(side * 0.25 * s, -(0.45 + legLength / 2) * s, 0.05 * s))
		local foot = newPart("Foot", Vector3.new(0.3, 0.08, 0.4) * s, legColor, Enum.Material.SmoothPlastic)
		weldTo(model, foot, body, CFrame.new(side * 0.25 * s, -(0.45 + legLength) * s, -0.08 * s))
	end

	-- Effects
	if look.Fire then
		local fire = Instance.new("Fire")
		fire.Size = 3 * s
		fire.Heat = 4
		fire.Color = Color3.fromRGB(255, 120, 30)
		fire.SecondaryColor = Color3.fromRGB(255, 220, 80)
		fire.Parent = body
	end
	if look.Glow then
		local light = Instance.new("PointLight")
		light.Color = look.Glow
		light.Range = 12
		light.Brightness = 2
		light.Parent = body
	end
	if options.Shiny then
		local sparkles = Instance.new("Sparkles")
		sparkles.SparkleColor = Color3.fromRGB(255, 230, 120)
		sparkles.Parent = body
		local light = Instance.new("PointLight")
		light.Color = Color3.fromRGB(255, 225, 120)
		light.Range = 8
		light.Brightness = 1.5
		light.Parent = body
	end

	-- Distance from the body's centre down to the bottom of the feet, and
	-- how far a hovering bird floats above its perch.
	local hover = look.Hover and 1.6 or 0
	model:SetAttribute("StandHeight", (0.45 + legLength + 0.04) * s + hover)
	model:SetAttribute("Hover", look.Hover == true)

	return model
end

return BirdBuilder
