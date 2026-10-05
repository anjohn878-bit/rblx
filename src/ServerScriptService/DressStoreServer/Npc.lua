-- Creates shopper / cashier characters.
-- Uses a real Roblox R15 avatar when possible and falls back to a classic
-- blocky R6 rig (built from parts) if avatar loading is not available.

local Players = game:GetService("Players")

local Npc = {}

Npc.COLLISION_GROUP = "DressStoreNPC"

local ANIMATIONS = {
	R15 = { walk = "rbxassetid://507777826", idle = "rbxassetid://507766388" },
	R6 = { walk = "rbxassetid://180426354", idle = "rbxassetid://180435571" },
}

local SKIN_TONES = {
	Color3.fromRGB(255, 224, 196),
	Color3.fromRGB(241, 194, 160),
	Color3.fromRGB(224, 172, 130),
	Color3.fromRGB(198, 134, 94),
	Color3.fromRGB(141, 85, 54),
	Color3.fromRGB(97, 59, 38),
}

local OUTFITS = {
	Color3.fromRGB(255, 120, 180),
	Color3.fromRGB(170, 120, 255),
	Color3.fromRGB(110, 200, 255),
	Color3.fromRGB(255, 200, 90),
	Color3.fromRGB(120, 220, 160),
	Color3.fromRGB(255, 140, 110),
	Color3.fromRGB(250, 250, 250),
	Color3.fromRGB(60, 60, 80),
}

local HAIR = {
	Color3.fromRGB(40, 25, 15),
	Color3.fromRGB(90, 55, 30),
	Color3.fromRGB(160, 110, 60),
	Color3.fromRGB(235, 200, 120),
	Color3.fromRGB(20, 20, 20),
	Color3.fromRGB(190, 70, 50),
	Color3.fromRGB(250, 150, 200),
}

local SKIN_PARTS = {
	Head = true,
	LeftHand = true,
	RightHand = true,
	LeftLowerArm = true,
	RightLowerArm = true,
	LeftUpperArm = true,
	RightUpperArm = true,
	["Left Arm"] = true,
	["Right Arm"] = true,
}
local TOP_PARTS = { UpperTorso = true, Torso = true }
local BOTTOM_PARTS = {
	LowerTorso = true,
	LeftUpperLeg = true,
	RightUpperLeg = true,
	LeftLowerLeg = true,
	RightLowerLeg = true,
	LeftFoot = true,
	RightFoot = true,
	["Left Leg"] = true,
	["Right Leg"] = true,
}

local r15Template: Model? = nil
local templateState = "none" -- "none" | "loading" | "ready" | "failed"

local function pick<T>(list: { T }): T
	return list[math.random(1, #list)]
end

local function buildR6(): Model
	local model = Instance.new("Model")

	local function limb(name: string, size: Vector3, position: Vector3): Part
		local part = Instance.new("Part")
		part.Name = name
		part.Size = size
		part.Position = position
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		part.Material = Enum.Material.SmoothPlastic
		part.Parent = model
		return part
	end

	local root = limb("HumanoidRootPart", Vector3.new(2, 2, 1), Vector3.new(0, 3, 0))
	root.Transparency = 1
	local torso = limb("Torso", Vector3.new(2, 2, 1), Vector3.new(0, 3, 0))
	local head = limb("Head", Vector3.new(2, 1, 1), Vector3.new(0, 4.5, 0))
	local leftArm = limb("Left Arm", Vector3.new(1, 2, 1), Vector3.new(-1.5, 3, 0))
	local rightArm = limb("Right Arm", Vector3.new(1, 2, 1), Vector3.new(1.5, 3, 0))
	local leftLeg = limb("Left Leg", Vector3.new(1, 2, 1), Vector3.new(-0.5, 1, 0))
	local rightLeg = limb("Right Leg", Vector3.new(1, 2, 1), Vector3.new(0.5, 1, 0))

	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Head
	mesh.Scale = Vector3.new(1.25, 1.25, 1.25)
	mesh.Parent = head

	local face = Instance.new("Decal")
	face.Name = "face"
	face.Texture = "rbxasset://textures/face.png"
	face.Face = Enum.NormalId.Front
	face.Parent = head

	local function motor(name: string, part0: BasePart, part1: BasePart, c0: CFrame, c1: CFrame)
		local joint = Instance.new("Motor6D")
		joint.Name = name
		joint.Part0 = part0
		joint.Part1 = part1
		joint.C0 = c0
		joint.C1 = c1
		joint.Parent = part0
	end

	-- Standard R6 joint offsets
	motor("RootJoint", root, torso, CFrame.new(0, 0, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0), CFrame.new(0, 0, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0))
	motor("Neck", torso, head, CFrame.new(0, 1, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0), CFrame.new(0, -0.5, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0))
	motor("Right Shoulder", torso, rightArm, CFrame.new(1, 0.5, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0), CFrame.new(-0.5, 0.5, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0))
	motor("Left Shoulder", torso, leftArm, CFrame.new(-1, 0.5, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0), CFrame.new(0.5, 0.5, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0))
	motor("Right Hip", torso, rightLeg, CFrame.new(1, -1, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0), CFrame.new(0.5, 1, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0))
	motor("Left Hip", torso, leftLeg, CFrame.new(-1, -1, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0), CFrame.new(-0.5, 1, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0))

	local humanoid = Instance.new("Humanoid")
	humanoid.RigType = Enum.HumanoidRigType.R6
	humanoid.Parent = model

	model.PrimaryPart = root
	return model
end

local function loadR15Template(): Model?
	if templateState == "ready" or templateState == "failed" then
		return r15Template
	end
	if templateState == "loading" then
		while templateState == "loading" do
			task.wait(0.1)
		end
		return r15Template
	end

	templateState = "loading"
	local ok, result = pcall(function()
		local description = Instance.new("HumanoidDescription")
		return Players:CreateHumanoidModelFromDescription(description, Enum.HumanoidRigType.R15)
	end)
	if ok and result then
		local model = result :: Model
		for _, child in model:GetDescendants() do
			if child:IsA("BodyColors") or child:IsA("LocalScript") or child:IsA("Script") then
				child:Destroy()
			end
		end
		r15Template = model
		templateState = "ready"
	else
		warn("[DressStore] Could not load an R15 avatar for shoppers, using blocky shoppers instead:", result)
		templateState = "failed"
	end
	return r15Template
end

local function addHair(model: Model, color: Color3)
	local head = model:FindFirstChild("Head") :: BasePart?
	if not head then
		return
	end
	local size = head.Size
	local isR6 = model:FindFirstChild("Torso") ~= nil
	local headSize = if isR6 then Vector3.new(1.25, 1.25, 1.25) else size

	local function hairPiece(partSize: Vector3, offset: CFrame)
		local hair = Instance.new("Part")
		hair.Name = "Hair"
		hair.Shape = Enum.PartType.Ball
		hair.Size = partSize
		hair.Color = color
		hair.Material = Enum.Material.SmoothPlastic
		hair.CanCollide = false
		hair.CanTouch = false
		hair.CanQuery = false
		hair.Massless = true
		hair.CFrame = head.CFrame * offset
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = head
		weld.Part1 = hair
		weld.Parent = hair
		hair.Parent = model
	end

	-- A rounded cap of hair on top/back of the head
	hairPiece(
		Vector3.new(headSize.X * 1.12, headSize.Y * 0.8, headSize.Z * 1.15),
		CFrame.new(0, headSize.Y * 0.28, headSize.Z * 0.1)
	)
	local style = math.random(1, 3)
	if style == 1 then
		-- bun
		local d = headSize.X * 0.5
		hairPiece(Vector3.new(d, d, d), CFrame.new(0, headSize.Y * 0.62, headSize.Z * 0.25))
	elseif style == 2 then
		-- ponytail
		local d = headSize.X * 0.42
		hairPiece(Vector3.new(d, d * 1.8, d), CFrame.new(0, -headSize.Y * 0.05, headSize.Z * 0.62))
	end
end

local function paint(model: Model, skin: Color3, top: Color3, bottom: Color3)
	for _, part in model:GetChildren() do
		if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
			if SKIN_PARTS[part.Name] then
				part.Color = skin
			elseif TOP_PARTS[part.Name] then
				part.Color = top
			elseif BOTTOM_PARTS[part.Name] then
				part.Color = bottom
			end
		end
	end
end

local function playAnimations(humanoid: Humanoid, rig: string)
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		local newAnimator = Instance.new("Animator")
		newAnimator.Parent = humanoid
		animator = newAnimator
	end
	local ids = ANIMATIONS[rig]
	local ok, err = pcall(function()
		local walkAnim = Instance.new("Animation")
		walkAnim.AnimationId = ids.walk
		local idleAnim = Instance.new("Animation")
		idleAnim.AnimationId = ids.idle
		local walk = (animator :: Animator):LoadAnimation(walkAnim)
		local idle = (animator :: Animator):LoadAnimation(idleAnim)
		walk.Looped = true
		idle.Looped = true
		idle:Play()
		local walking = false
		humanoid.Running:Connect(function(speed)
			if speed > 0.5 and not walking then
				walking = true
				idle:Stop(0.2)
				walk:Play(0.2)
			elseif speed <= 0.5 and walking then
				walking = false
				walk:Stop(0.2)
				idle:Play(0.2)
			end
		end)
	end)
	if not ok then
		warn("[DressStore] Could not play shopper animations:", err)
	end
end

export type Character = {
	model: Model,
	humanoid: Humanoid,
	root: BasePart,
	hand: BasePart?,
	head: BasePart?,
	groundOffset: number, -- height of the root part's centre above the floor
}

-- Loads the avatar used for shoppers ahead of time (yields).
function Npc.preload()
	loadR15Template()
end

-- Creates a new character model (not parented yet). Can yield the first time.
function Npc.create(name: string, outfit: Color3?): Character
	local template = loadR15Template()
	local model: Model
	local rig: string
	if template then
		model = template:Clone()
		rig = "R15"
	else
		model = buildR6()
		rig = "R6"
	end
	model.Name = name

	local humanoid = model:FindFirstChildOfClass("Humanoid") :: Humanoid
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart
	model.PrimaryPart = root

	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid.BreakJointsOnDeath = false
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Seated, false)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Climbing, false)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Dead, false)

	local top = outfit or pick(OUTFITS)
	local bottom = if math.random() < 0.5 then top else pick(OUTFITS)
	paint(model, pick(SKIN_TONES), top, bottom)
	addHair(model, pick(HAIR))

	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.CollisionGroup = Npc.COLLISION_GROUP
		end
	end

	local groundOffset
	if rig == "R15" then
		groundOffset = humanoid.HipHeight + root.Size.Y / 2
	else
		groundOffset = 3
	end

	playAnimations(humanoid, rig)

	local hand = model:FindFirstChild("RightHand") or model:FindFirstChild("Right Arm")
	local head = model:FindFirstChild("Head")
	return {
		model = model,
		humanoid = humanoid,
		root = root,
		hand = if hand and hand:IsA("BasePart") then hand else nil,
		head = if head and head:IsA("BasePart") then head else nil,
		groundOffset = groundOffset,
	}
end

-- Gives the character a shopping bag to carry.
function Npc.giveBag(character: Character, color: Color3)
	local hand = character.hand
	if not hand then
		return
	end
	local bag = Instance.new("Part")
	bag.Name = "ShoppingBag"
	bag.Size = Vector3.new(0.5, 1.1, 1.0)
	bag.Color = color
	bag.Material = Enum.Material.SmoothPlastic
	bag.CanCollide = false
	bag.CanTouch = false
	bag.CanQuery = false
	bag.Massless = true
	local handBottom = if hand.Name == "Right Arm" then 1.0 else hand.Size.Y / 2
	bag.CFrame = hand.CFrame * CFrame.new(0, -handBottom - 0.6, 0)
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = hand
	weld.Part1 = bag
	weld.Parent = bag

	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(0.1, 0.35, 0.6)
	handle.Color = Color3.fromRGB(255, 255, 255)
	handle.CanCollide = false
	handle.CanTouch = false
	handle.CanQuery = false
	handle.Massless = true
	handle.CFrame = bag.CFrame * CFrame.new(0, 0.7, 0)
	local weld2 = Instance.new("WeldConstraint")
	weld2.Part0 = bag
	weld2.Part1 = handle
	weld2.Parent = handle

	bag.CollisionGroup = Npc.COLLISION_GROUP
	handle.CollisionGroup = Npc.COLLISION_GROUP
	bag.Parent = character.model
	handle.Parent = character.model
end

-- A speech bubble above the head with an emoji / short text.
function Npc.setBubble(character: Character, text: string?)
	local head = character.head
	if not head then
		return
	end
	local gui = head:FindFirstChild("Bubble") :: BillboardGui?
	if not text then
		if gui then
			gui.Enabled = false
		end
		return
	end
	if not gui then
		local newGui = Instance.new("BillboardGui")
		newGui.Name = "Bubble"
		newGui.Size = UDim2.new(0, 120, 0, 44)
		newGui.StudsOffsetWorldSpace = Vector3.new(0, 2.6, 0)
		newGui.MaxDistance = 70
		newGui.Adornee = head
		newGui.Parent = head

		local label = Instance.new("TextLabel")
		label.Name = "Label"
		label.AnchorPoint = Vector2.new(0.5, 0.5)
		label.Position = UDim2.fromScale(0.5, 0.5)
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		label.BackgroundTransparency = 0.05
		label.TextColor3 = Color3.fromRGB(80, 30, 70)
		label.Font = Enum.Font.FredokaOne
		label.TextScaled = true
		label.Parent = newGui

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.5, 0)
		corner.Parent = label
		local padding = Instance.new("UIPadding")
		padding.PaddingTop = UDim.new(0, 4)
		padding.PaddingBottom = UDim.new(0, 4)
		padding.PaddingLeft = UDim.new(0, 8)
		padding.PaddingRight = UDim.new(0, 8)
		padding.Parent = label
		gui = newGui
	end
	local bubble = gui :: BillboardGui
	bubble.Enabled = true
	local label = bubble:FindFirstChild("Label") :: TextLabel
	label.Text = text
end

return Npc
