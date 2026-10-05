--[[
	SkateGear
	Straps a pair of skates (boot sole, blade and an ice-carving trail) onto a
	character's feet in the colours of the player's current skate tier. The
	character is raised by the blade height so the blades sit on the ice.
]]

local SkateGear = {}

local BLADE_HEIGHT = 0.2
local SOLE_THICKNESS = 0.14
-- How far the character is lifted so the blades rest on top of the ice.
local RAISE = 0.32
local FEET = {
	{ "LeftFoot", "Left Leg" },
	{ "RightFoot", "Right Leg" },
}

local function findFoot(character, names)
	for _, name in names do
		local foot = character:FindFirstChild(name)
		if foot and foot:IsA("BasePart") then
			return foot
		end
	end
	return nil
end

local function gearPart(name, size, color, material)
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Color = color
	part.Material = material
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	return part
end

local function weldTo(foot, part, offset)
	part.CFrame = foot.CFrame * offset
	local weld = Instance.new("Weld")
	weld.Part0 = foot
	weld.Part1 = part
	weld.C0 = offset
	weld.Parent = part
end

local raisedHumanoids = setmetatable({}, { __mode = "k" })

local function raiseCharacter(character)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or raisedHumanoids[humanoid] then
		return
	end
	raisedHumanoids[humanoid] = true

	local baseHipHeight = humanoid.HipHeight
	humanoid.HipHeight = baseHipHeight + RAISE

	-- Avatar scaling can recompute HipHeight after we've set it; keep the skates on top of the ice.
	humanoid:GetPropertyChangedSignal("HipHeight"):Connect(function()
		if math.abs(humanoid.HipHeight - (baseHipHeight + RAISE)) > 0.001 then
			baseHipHeight = humanoid.HipHeight
			humanoid.HipHeight = baseHipHeight + RAISE
		end
	end)
end

function SkateGear.equip(character, skate)
	local existing = character:FindFirstChild("SkateGear")
	if existing then
		existing:Destroy()
	end

	local gear = Instance.new("Folder")
	gear.Name = "SkateGear"
	local enabled = character:GetAttribute("Skating") == true

	for _, names in FEET do
		local foot = findFoot(character, names)
		if not foot then
			continue
		end

		local bottom = -foot.Size.Y / 2
		local length = math.max(foot.Size.Z, 0.8)

		local soleBottom = bottom - SOLE_THICKNESS + 0.03
		local sole = gearPart(
			"Sole",
			Vector3.new(foot.Size.X * 1.12, SOLE_THICKNESS, length * 1.1),
			skate.BootColor,
			Enum.Material.SmoothPlastic
		)
		weldTo(foot, sole, CFrame.new(0, soleBottom + SOLE_THICKNESS / 2, 0))
		sole.Parent = gear

		local blade = gearPart(
			"Blade",
			Vector3.new(0.12, BLADE_HEIGHT, length * 1.35),
			skate.BladeColor,
			if skate.Glow then Enum.Material.Neon else Enum.Material.Metal
		)
		weldTo(foot, blade, CFrame.new(0, soleBottom - BLADE_HEIGHT / 2, -0.05))
		blade.Parent = gear

		-- The trail is a flat ribbon across the bottom of the blade, so it reads as a groove in the ice.
		local halfBlade = blade.Size.Y / 2
		local left = Instance.new("Attachment")
		left.Name = "TrailLeft"
		left.Position = Vector3.new(-0.16, -halfBlade + 0.05, 0)
		left.Parent = blade
		local right = Instance.new("Attachment")
		right.Name = "TrailRight"
		right.Position = Vector3.new(0.16, -halfBlade + 0.05, 0)
		right.Parent = blade

		local trail = Instance.new("Trail")
		trail.Name = "IceTrail"
		trail.Attachment0 = left
		trail.Attachment1 = right
		trail.FaceCamera = false
		trail.Lifetime = 1.4
		trail.MinLength = 0.15
		trail.LightEmission = 0.35
		trail.Color = ColorSequence.new(skate.TrailColor)
		trail.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.25),
			NumberSequenceKeypoint.new(1, 1),
		})
		trail.Enabled = enabled
		trail.Parent = blade
	end

	gear.Parent = character
	raiseCharacter(character)
end

function SkateGear.setTrails(character, enabled)
	local gear = character:FindFirstChild("SkateGear")
	if not gear then
		return
	end
	for _, descendant in gear:GetDescendants() do
		if descendant:IsA("Trail") then
			descendant.Enabled = enabled
		end
	end
end

return SkateGear
