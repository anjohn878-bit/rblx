--!strict
-- Builds a bird from primitive parts and exposes a small "rig" so a renderer can
-- pose it every frame (flapping wings) without welds or physics.
-- Local space: the bird faces -Z, up is +Y, and its feet are at the origin.

local Birds = require(script.Parent.Birds)
local Types = require(script.Parent.Types)
type BirdDef = Types.BirdDef

local BirdModel = {}

export type Wing = { index: number, shoulder: CFrame, offset: CFrame, side: number }

export type Rig = {
	model: Model,
	parts: { BasePart },
	rest: { CFrame }, -- local CFrame of each part when wings are folded
	static: { number }, -- indices of parts that never move relative to the body
	wings: { Wing },
	flapRate: number, -- radians/second of the wing beat
	height: number, -- studs from feet to the top of the head
	def: BirdDef,
}

local PLASTIC = Enum.Material.SmoothPlastic
local SILHOUETTE = Color3.fromRGB(16, 16, 22)
local EYE = Color3.fromRGB(20, 20, 26)
local WHITE = Color3.fromRGB(245, 246, 252)

function BirdModel.build(def: BirdDef, silhouette: boolean?): Rig
	local s = def.scale
	local model = Instance.new("Model")
	model.Name = def.id

	local parts: { BasePart } = {}
	local rest: { CFrame } = {}
	local static: { number } = {}
	local wings: { Wing } = {}
	local glow = Birds.hasTrait(def, "Glow")

	local function add(
		name: string,
		size: Vector3,
		cf: CFrame,
		color: Color3,
		material: Enum.Material?,
		round: boolean
	): Part
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size * s
		p.Color = if silhouette then SILHOUETTE else color
		p.Material = if silhouette then PLASTIC else (material or PLASTIC)
		p.Anchored = true
		p.CanCollide = false
		p.CanTouch = false
		p.CanQuery = false
		p.CastShadow = false
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		-- positions are authored at scale 1 and scaled here
		local scaled = cf.Rotation + cf.Position * s
		p.CFrame = scaled
		if round then
			local mesh = Instance.new("SpecialMesh")
			mesh.MeshType = Enum.MeshType.Sphere
			mesh.Parent = p
		end
		p.Parent = model
		table.insert(parts, p)
		table.insert(rest, scaled)
		return p
	end
	local function addStatic(
		name: string,
		size: Vector3,
		cf: CFrame,
		color: Color3,
		material: Enum.Material?,
		round: boolean
	): Part
		local p = add(name, size, cf, color, material, round)
		table.insert(static, #parts)
		return p
	end

	-- invisible root so the model has a pivot at the feet
	local root = addStatic("Root", Vector3.new(0.2, 0.2, 0.2) / s, CFrame.new(), WHITE, PLASTIC, false)
	root.Transparency = 1
	model.PrimaryPart = root

	local wingMaterial = if glow then Enum.Material.Neon else PLASTIC
	local bellyMaterial = if glow then Enum.Material.Neon else PLASTIC

	-- legs
	for _, x in { -0.17, 0.17 } do
		addStatic("Leg", Vector3.new(0.09, 0.42, 0.09), CFrame.new(x, 0.21, 0), def.beak, PLASTIC, false)
	end

	-- body, belly, head
	local body = addStatic("Body", Vector3.new(0.95, 0.85, 1.4), CFrame.new(0, 0.8, 0.05), def.body, PLASTIC, true)
	addStatic("Belly", Vector3.new(0.8, 0.55, 1.05), CFrame.new(0, 0.64, -0.12), def.belly, bellyMaterial, true)
	addStatic("Head", Vector3.new(0.66, 0.66, 0.66), CFrame.new(0, 1.4, -0.5), def.body, PLASTIC, true)

	local owl = Birds.hasTrait(def, "OwlFace")

	-- beak
	if Birds.hasTrait(def, "BigBeak") then
		addStatic("Beak", Vector3.new(0.26, 0.24, 0.8), CFrame.new(0, 1.34, -1.0), def.beak, PLASTIC, false)
		addStatic(
			"BeakTip",
			Vector3.new(0.24, 0.22, 0.18),
			CFrame.new(0, 1.34, -1.36),
			Color3.fromRGB(30, 30, 34),
			PLASTIC,
			false
		)
	elseif Birds.hasTrait(def, "LongBeak") then
		addStatic("Beak", Vector3.new(0.07, 0.07, 0.95), CFrame.new(0, 1.37, -1.15), def.beak, PLASTIC, false)
	elseif owl then
		addStatic("Beak", Vector3.new(0.1, 0.16, 0.18), CFrame.new(0, 1.3, -0.84), def.beak, PLASTIC, false)
	else
		addStatic("Beak", Vector3.new(0.16, 0.14, 0.36), CFrame.new(0, 1.35, -0.88), def.beak, PLASTIC, false)
	end

	-- eyes
	if owl then
		for _, x in { -0.17, 0.17 } do
			addStatic("EyeDisc", Vector3.new(0.34, 0.34, 0.1), CFrame.new(x, 1.44, -0.79), WHITE, PLASTIC, true)
			addStatic(
				"Eye",
				Vector3.new(0.18, 0.18, 0.1),
				CFrame.new(x, 1.44, -0.84),
				def.accent,
				Enum.Material.Neon,
				true
			)
		end
		for _, side in { -1, 1 } do
			addStatic(
				"Tuft",
				Vector3.new(0.1, 0.3, 0.1),
				CFrame.new(side * 0.22, 1.78, -0.5) * CFrame.Angles(0, 0, side * -0.35),
				def.wing,
				PLASTIC,
				false
			)
		end
	else
		for _, x in { -0.2, 0.2 } do
			addStatic("Eye", Vector3.new(0.12, 0.12, 0.12), CFrame.new(x, 1.47, -0.78), EYE, PLASTIC, true)
		end
	end

	-- head decorations
	if Birds.hasTrait(def, "Crest") then
		addStatic(
			"Crest",
			Vector3.new(0.14, 0.5, 0.36),
			CFrame.new(0, 1.78, -0.42) * CFrame.Angles(math.rad(-28), 0, 0),
			def.accent,
			PLASTIC,
			true
		)
	end
	if Birds.hasTrait(def, "Cap") then
		addStatic("Cap", Vector3.new(0.52, 0.3, 0.52), CFrame.new(0, 1.58, -0.5), def.accent, PLASTIC, true)
	end

	-- tail
	local tailTilt = CFrame.Angles(math.rad(20), 0, 0)
	if Birds.hasTrait(def, "LongTail") then
		addStatic("Tail", Vector3.new(0.3, 0.07, 1.8), CFrame.new(0, 0.82, 1.5) * tailTilt, def.wing, PLASTIC, false)
		addStatic(
			"TailTip",
			Vector3.new(0.34, 0.075, 0.5),
			CFrame.new(0, 0.5, 2.28) * tailTilt,
			def.accent,
			PLASTIC,
			false
		)
	else
		addStatic("Tail", Vector3.new(0.34, 0.08, 0.7), CFrame.new(0, 0.9, 0.98) * tailTilt, def.wing, PLASTIC, false)
	end
	if Birds.hasTrait(def, "FanTail") then
		local base = CFrame.new(0, 0.9, 0.95) * CFrame.Angles(math.rad(22), 0, 0)
		for i = 0, 8 do
			local phi = math.rad(-72 + i * 18)
			local feather = base * CFrame.Angles(0, 0, phi) * CFrame.new(0, 1.35, 0)
			local color = if i % 2 == 0 then def.wing else def.belly
			addStatic("Feather", Vector3.new(0.36, 2.6, 0.06), feather, color, PLASTIC, true)
			addStatic(
				"FeatherEye",
				Vector3.new(0.3, 0.34, 0.07),
				feather * CFrame.new(0, 0.95, 0.02),
				Color3.fromRGB(40, 90, 200),
				PLASTIC,
				true
			)
		end
	end

	-- wings: each hangs from a shoulder and rotates about the body's forward axis
	for _, side in { -1, 1 } do
		local shoulder = CFrame.new(side * 0.46, 1.15, 0)
		local offset = CFrame.new(side * 0.03, -0.4, 0.05)
		local wing = add("Wing", Vector3.new(0.1, 0.85, 0.95), shoulder * offset, def.wing, wingMaterial, true)
		table.insert(wings, {
			index = #parts,
			shoulder = CFrame.new(shoulder.Position * s),
			offset = CFrame.new(offset.Position * s),
			side = side,
		})
		wing.Name = if side < 0 then "WingL" else "WingR"
	end

	-- effects
	if not silhouette then
		if glow then
			local light = Instance.new("PointLight")
			light.Color = def.accent
			light.Range = 10 + 4 * s
			light.Brightness = 0.9
			light.Parent = body
		end
		if Birds.hasTrait(def, "Fire") then
			local fire = Instance.new("ParticleEmitter")
			fire.Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 240, 150)),
				ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 130, 30)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(200, 30, 10)),
			})
			fire.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.9 * s), NumberSequenceKeypoint.new(1, 0) })
			fire.Transparency =
				NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
			fire.Lifetime = NumberRange.new(0.5, 0.9)
			fire.Rate = 40
			fire.Speed = NumberRange.new(1, 3)
			fire.SpreadAngle = Vector2.new(35, 35)
			fire.EmissionDirection = Enum.NormalId.Top
			fire.LightEmission = 1
			fire.Parent = body
		end
	end

	local flapRate = (if Birds.hasTrait(def, "Hover") then 58 else 26) / math.sqrt(s)

	return {
		model = model,
		parts = parts,
		rest = rest,
		static = static,
		wings = wings,
		flapRate = flapRate,
		height = 1.8 * s,
		def = def,
	}
end

-- Moves the whole bird: `rootCF` is where its feet go, `wingAngle` is the wing
-- spread in radians (0 = folded against the body, ~2 = raised high).
function BirdModel.pose(rig: Rig, rootCF: CFrame, wingAngle: number)
	local parts, rest = rig.parts, rig.rest
	for _, i in rig.static do
		parts[i].CFrame = rootCF * rest[i]
	end
	for _, wing in rig.wings do
		parts[wing.index].CFrame = rootCF * wing.shoulder * CFrame.Angles(0, 0, wing.side * wingAngle) * wing.offset
	end
end

return BirdModel
