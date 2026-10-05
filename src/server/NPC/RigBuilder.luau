--[[
	RigBuilder
	Builds classic R6 characters entirely from parts (no assets required).
	A single template is built once and cloned for every NPC, then coloured
	and decorated (hair, hats, lab coats, robot parts...).
]]

local Collision = require(script.Parent.Parent.Util.Collision)

export type Appearance = {
	Skin: Color3,
	Shirt: Color3,
	Pants: Color3,
	Hair: Color3?,
	HairStyle: string?, -- "Short" | "Long" | "Spiky" | "Bun" | "Cap" | "Bald" | "TopHat"
	HatColor: Color3?,
	Sleeves: boolean?, -- arms use shirt colour instead of skin
	Scale: number?,
}

local RigBuilder = {}

local template: Model? = nil

local function motor(name: string, part0: BasePart, part1: BasePart, c0: CFrame, c1: CFrame, parent: Instance)
	local m = Instance.new("Motor6D")
	m.Name = name
	m.Part0 = part0
	m.Part1 = part1
	m.C0 = c0
	m.C1 = c1
	m.Parent = parent
end

local function newPart(name: string, size: Vector3, canCollide: boolean): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CanCollide = canCollide
	part.CanTouch = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Material = Enum.Material.SmoothPlastic
	return part
end

local function buildTemplate(): Model
	local model = Instance.new("Model")
	model.Name = "NPC"

	local root = newPart("HumanoidRootPart", Vector3.new(2, 2, 1), false)
	root.Transparency = 1
	local torso = newPart("Torso", Vector3.new(2, 2, 1), true)
	local head = newPart("Head", Vector3.new(2, 1, 1), true)
	local leftArm = newPart("Left Arm", Vector3.new(1, 2, 1), false)
	local rightArm = newPart("Right Arm", Vector3.new(1, 2, 1), false)
	local leftLeg = newPart("Left Leg", Vector3.new(1, 2, 1), false)
	local rightLeg = newPart("Right Leg", Vector3.new(1, 2, 1), false)

	-- Lay the parts out in their standing pose (motors then hold them).
	root.CFrame = CFrame.new(0, 3, 0)
	torso.CFrame = CFrame.new(0, 3, 0)
	head.CFrame = CFrame.new(0, 4.5, 0)
	leftArm.CFrame = CFrame.new(-1.5, 3, 0)
	rightArm.CFrame = CFrame.new(1.5, 3, 0)
	leftLeg.CFrame = CFrame.new(-0.5, 1, 0)
	rightLeg.CFrame = CFrame.new(0.5, 1, 0)

	local headMesh = Instance.new("SpecialMesh")
	headMesh.MeshType = Enum.MeshType.Head
	headMesh.Scale = Vector3.new(1.25, 1.25, 1.25)
	headMesh.Parent = head

	local face = Instance.new("Decal")
	face.Name = "face"
	face.Texture = "rbxasset://textures/face.png"
	face.Face = Enum.NormalId.Front
	face.Parent = head

	for _, part in { root, torso, head, leftArm, rightArm, leftLeg, rightLeg } do
		part.Parent = model
	end

	local rootJointCF = CFrame.new(0, 0, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0)
	motor("RootJoint", root, torso, rootJointCF, rootJointCF, root)
	motor("Neck", torso, head, CFrame.new(0, 1, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0), CFrame.new(0, -0.5, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0), torso)
	motor("Right Shoulder", torso, rightArm, CFrame.new(1, 0.5, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0), CFrame.new(-0.5, 0.5, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0), torso)
	motor("Left Shoulder", torso, leftArm, CFrame.new(-1, 0.5, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0), CFrame.new(0.5, 0.5, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0), torso)
	motor("Right Hip", torso, rightLeg, CFrame.new(1, -1, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0), CFrame.new(0.5, 1, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0), torso)
	motor("Left Hip", torso, leftLeg, CFrame.new(-1, -1, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0), CFrame.new(-0.5, 1, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0), torso)

	local humanoid = Instance.new("Humanoid")
	humanoid.RigType = Enum.HumanoidRigType.R6
	humanoid.HipHeight = 0
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid.BreakJointsOnDeath = false
	humanoid.RequiresNeck = false
	humanoid.WalkSpeed = 12
	humanoid.Parent = model

	local animator = Instance.new("Animator")
	animator.Parent = humanoid

	model.PrimaryPart = root
	Collision.SetModelGroup(model, Collision.NPC)
	return model
end

local function weldTo(part: BasePart, target: BasePart, offset: CFrame)
	part.Massless = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CFrame = target.CFrame * offset
	part.CollisionGroup = Collision.NPC
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = target
	weld.Part1 = part
	weld.Parent = part
end

local function accessory(model: Model, attachTo: BasePart, name: string, size: Vector3, offset: CFrame, color: Color3, material: Enum.Material?, shape: Enum.PartType?): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Color = color
	part.Material = material or Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	if shape then
		part.Shape = shape
	end
	weldTo(part, attachTo, offset)
	part.Parent = model
	return part
end

local function addHair(model: Model, head: BasePart, style: string, color: Color3, hatColor: Color3?)
	if style == "Bald" then
		return
	elseif style == "Short" then
		accessory(model, head, "Hair", Vector3.new(1.3, 0.35, 1.3), CFrame.new(0, 0.62, 0.05), color)
	elseif style == "Long" then
		accessory(model, head, "Hair", Vector3.new(1.3, 0.35, 1.3), CFrame.new(0, 0.62, 0.05), color)
		accessory(model, head, "HairBack", Vector3.new(1.3, 1.3, 0.3), CFrame.new(0, 0.05, 0.6), color)
	elseif style == "Spiky" then
		accessory(model, head, "Hair", Vector3.new(1.3, 0.3, 1.3), CFrame.new(0, 0.6, 0.05), color)
		for i = -1, 1 do
			accessory(model, head, "Spike", Vector3.new(0.35, 0.45, 0.35), CFrame.new(i * 0.4, 0.9, 0) * CFrame.Angles(0, 0, -i * 0.35), color)
		end
	elseif style == "Bun" then
		accessory(model, head, "Hair", Vector3.new(1.3, 0.35, 1.3), CFrame.new(0, 0.62, 0.05), color)
		accessory(model, head, "Bun", Vector3.new(0.7, 0.7, 0.7), CFrame.new(0, 0.95, 0.35), color, nil, Enum.PartType.Ball)
	elseif style == "Cap" then
		local capColor = hatColor or color
		accessory(model, head, "Cap", Vector3.new(1.35, 0.4, 1.35), CFrame.new(0, 0.66, 0), capColor)
		accessory(model, head, "Brim", Vector3.new(1.2, 0.12, 0.6), CFrame.new(0, 0.5, -0.85), capColor)
	elseif style == "TopHat" then
		local hat = hatColor or Color3.fromRGB(30, 30, 30)
		accessory(model, head, "HatBrim", Vector3.new(1.7, 0.12, 1.7), CFrame.new(0, 0.62, 0), hat)
		accessory(model, head, "HatTop", Vector3.new(1.1, 1, 1.1), CFrame.new(0, 1.15, 0), hat)
		accessory(model, head, "HatBand", Vector3.new(1.15, 0.2, 1.15), CFrame.new(0, 0.78, 0), Color3.fromRGB(255, 200, 40))
	end
end

function RigBuilder.Init()
	if not template then
		template = buildTemplate()
	end
end

local function cloneTemplate(): Model
	RigBuilder.Init()
	return (template :: Model):Clone()
end

local function color(model: Model, appearance: Appearance)
	local skin = appearance.Skin
	local head = model:FindFirstChild("Head") :: BasePart
	head.Color = skin
	local torso = model:FindFirstChild("Torso") :: BasePart
	torso.Color = appearance.Shirt
	for _, name in { "Left Arm", "Right Arm" } do
		local arm = model:FindFirstChild(name) :: BasePart
		arm.Color = if appearance.Sleeves then appearance.Shirt else skin
	end
	for _, name in { "Left Leg", "Right Leg" } do
		local leg = model:FindFirstChild(name) :: BasePart
		leg.Color = appearance.Pants
	end
end

function RigBuilder.CreateCharacter(name: string, appearance: Appearance): Model
	local model = cloneTemplate()
	model.Name = name
	color(model, appearance)
	local head = model:FindFirstChild("Head") :: BasePart
	addHair(model, head, appearance.HairStyle or "Short", appearance.Hair or Color3.fromRGB(60, 40, 30), appearance.HatColor)
	if appearance.Scale and appearance.Scale ~= 1 then
		model:ScaleTo(appearance.Scale)
	end
	return model
end

export type DoctorLook = {
	Coat: Color3,
	Scrubs: Color3,
	Accent: Color3,
	Robot: boolean,
	Glasses: boolean,
}

function RigBuilder.CreateDoctor(name: string, look: DoctorLook, skin: Color3): Model
	local model = cloneTemplate()
	model.Name = name
	local head = model:FindFirstChild("Head") :: BasePart
	local torso = model:FindFirstChild("Torso") :: BasePart

	if look.Robot then
		color(model, { Skin = look.Coat, Shirt = look.Coat, Pants = look.Scrubs, Sleeves = true })
		for _, part in model:GetChildren() do
			if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
				part.Material = Enum.Material.Metal
			end
		end
		local face = head:FindFirstChild("face")
		if face then
			face:Destroy()
		end
		accessory(model, head, "Visor", Vector3.new(1.1, 0.3, 0.1), CFrame.new(0, 0.1, -0.62), look.Accent, Enum.Material.Neon)
		accessory(model, head, "Antenna", Vector3.new(0.12, 0.7, 0.12), CFrame.new(0, 0.95, 0), Color3.fromRGB(90, 90, 100))
		accessory(model, head, "AntennaTip", Vector3.new(0.35, 0.35, 0.35), CFrame.new(0, 1.35, 0), look.Accent, Enum.Material.Neon, Enum.PartType.Ball)
		accessory(model, torso, "ChestLight", Vector3.new(0.6, 0.6, 0.1), CFrame.new(0, 0.3, -0.52), look.Accent, Enum.Material.Neon)
	else
		color(model, { Skin = skin, Shirt = look.Coat, Pants = look.Scrubs, Sleeves = true })
		-- Lab coat tail hanging below the torso
		accessory(model, torso, "CoatTail", Vector3.new(2.05, 0.9, 1.05), CFrame.new(0, -1.4, 0), look.Coat)
		-- Scrub shirt showing at the collar + surgical cap
		accessory(model, torso, "Collar", Vector3.new(0.8, 0.6, 0.1), CFrame.new(0, 0.7, -0.52), look.Scrubs)
		accessory(model, head, "SurgicalCap", Vector3.new(1.32, 0.38, 1.32), CFrame.new(0, 0.62, 0.02), look.Scrubs)
		-- Stethoscope
		accessory(model, torso, "Stethoscope", Vector3.new(0.12, 0.9, 0.12), CFrame.new(-0.35, 0.2, -0.55), Color3.fromRGB(40, 40, 50))
		accessory(model, torso, "StethoscopeEnd", Vector3.new(0.3, 0.3, 0.12), CFrame.new(-0.35, -0.3, -0.56), Color3.fromRGB(180, 180, 190), Enum.Material.Metal)
		-- Name badge in the doctor's accent colour
		accessory(model, torso, "Badge", Vector3.new(0.45, 0.3, 0.08), CFrame.new(0.5, 0.45, -0.54), look.Accent, Enum.Material.Neon)
		if look.Glasses then
			accessory(model, head, "Glasses", Vector3.new(1.0, 0.22, 0.08), CFrame.new(0, 0.12, -0.62), Color3.fromRGB(30, 30, 40))
		end
	end
	return model
end

-- Static decorative staff (receptionist / pharmacist).
function RigBuilder.CreateStaff(name: string, uniform: Color3, skin: Color3, hair: Color3): Model
	local model = RigBuilder.CreateCharacter(name, {
		Skin = skin,
		Shirt = uniform,
		Pants = Color3.fromRGB(50, 60, 80),
		Hair = hair,
		HairStyle = "Bun",
		Sleeves = true,
	})
	return model
end

return RigBuilder
