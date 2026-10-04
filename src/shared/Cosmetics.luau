--[[
	Cosmetics
	Applies an "equipped" table to a character model. Used by the server for real
	characters and by the client for the locker preview, so both always match.
]]

local Catalog = require(script.Parent.Catalog)

local Cosmetics = {}

local COSMETIC_TAG = "CK_Cosmetic"

-- Which body parts each slot colours (R15 and R6 names)
local SLOT_PARTS = {
	Shirt = { "UpperTorso", "LeftUpperArm", "RightUpperArm", "Torso" },
	Shorts = { "LowerTorso", "LeftUpperLeg", "RightUpperLeg", "Left Leg", "Right Leg" },
	Socks = { "LeftLowerLeg", "RightLowerLeg" },
	Boots = { "LeftFoot", "RightFoot" },
}

local function clearOld(character: Model)
	for _, d in character:GetDescendants() do
		if d:GetAttribute(COSMETIC_TAG) then
			d:Destroy()
		end
	end
end

local function weldTo(part: BasePart, to: BasePart, offset: CFrame)
	part.Anchored = false
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
	part.CFrame = to.CFrame * offset
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = to
	weld.Part1 = part
	weld.Parent = part
	part:SetAttribute(COSMETIC_TAG, true)
	part.Parent = to.Parent
end

local function newPart(name: string, size: Vector3, color: Color3, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = Enum.Material.Fabric
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if shape then
		p.Shape = shape
	end
	return p
end

local function buildHeadwear(character: Model, item)
	local head = character:FindFirstChild("Head") :: BasePart?
	if not head or item.Style == "None" then
		return
	end
	local hs = head.Size
	if item.Style == "Headband" then
		local band = newPart("CK_Headband", Vector3.new(0.35, hs.X * 1.08, hs.X * 1.08), item.Color, Enum.PartType.Cylinder)
		weldTo(band, head, CFrame.new(0, hs.Y * 0.18, 0) * CFrame.Angles(0, 0, math.rad(90)))
	elseif item.Style == "Cap" then
		local crown = newPart("CK_CapTop", Vector3.new(hs.X * 1.05, hs.Y * 0.45, hs.Z * 1.05), item.Color)
		weldTo(crown, head, CFrame.new(0, hs.Y * 0.42, 0))
		local brim = newPart("CK_CapBrim", Vector3.new(hs.X * 0.9, 0.12, hs.Z * 0.6), item.Color)
		weldTo(brim, head, CFrame.new(0, hs.Y * 0.22, -hs.Z * 0.72))
	elseif item.Style == "Beanie" then
		local beanie = newPart("CK_Beanie", Vector3.new(hs.X * 1.12, hs.X * 1.12, hs.X * 1.12), item.Color, Enum.PartType.Ball)
		weldTo(beanie, head, CFrame.new(0, hs.Y * 0.3, 0.02))
		local pom = newPart("CK_Pom", Vector3.new(0.45, 0.45, 0.45), Color3.new(1, 1, 1), Enum.PartType.Ball)
		weldTo(pom, head, CFrame.new(0, hs.Y * 0.95, 0))
	elseif item.Style == "Crown" then
		local ring = newPart("CK_Crown", Vector3.new(0.5, hs.X * 1.05, hs.X * 1.05), item.Color, Enum.PartType.Cylinder)
		ring.Material = Enum.Material.Metal
		weldTo(ring, head, CFrame.new(0, hs.Y * 0.62, 0) * CFrame.Angles(0, 0, math.rad(90)))
		for i = 0, 4 do
			local spike = newPart("CK_CrownSpike", Vector3.new(0.25, 0.45, 0.25), item.Color)
			spike.Material = Enum.Material.Metal
			local a = (i / 5) * math.pi * 2
			weldTo(spike, head, CFrame.new(math.cos(a) * hs.X * 0.45, hs.Y * 0.9, math.sin(a) * hs.X * 0.45))
		end
	end
end

local function buildTrail(character: Model, item)
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root or item.Style == "None" then
		return
	end
	local a0 = Instance.new("Attachment")
	a0.Name = "CK_TrailTop"
	a0.Position = Vector3.new(0, 0.6, 0.4)
	a0:SetAttribute(COSMETIC_TAG, true)
	a0.Parent = root
	local a1 = Instance.new("Attachment")
	a1.Name = "CK_TrailBottom"
	a1.Position = Vector3.new(0, -2.4, 0.4)
	a1:SetAttribute(COSMETIC_TAG, true)
	a1.Parent = root
	local trail = Instance.new("Trail")
	trail.Name = "CK_Trail"
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Lifetime = 0.35
	trail.MinLength = 0.2
	trail.LightEmission = 0.6
	trail.FaceCamera = true
	trail.Color = ColorSequence.new(item.Color, item.Secondary or item.Color)
	trail.Transparency = NumberSequence.new(0.35, 1)
	trail:SetAttribute(COSMETIC_TAG, true)
	trail.Parent = root
end

--[[
	equipped: { Shirt = id, Shorts = id, ... }
	shirtOverride: optional Color3 (team bib colour during matches)
]]
function Cosmetics.Apply(character: Model, equipped: { [string]: string }, shirtOverride: Color3?)
	if not character then
		return
	end
	clearOld(character)

	-- Remove avatar clothing so kit colours show. Hair/face accessories are kept.
	for _, child in character:GetChildren() do
		if child:IsA("Shirt") or child:IsA("Pants") or child:IsA("ShirtGraphic") then
			child:Destroy()
		end
	end

	for slot, partNames in SLOT_PARTS do
		local item = Catalog.Get(equipped[slot] or "")
		local color = item and item.Color
		if slot == "Shirt" and shirtOverride then
			color = shirtOverride
		end
		if color then
			for _, partName in partNames do
				local part = character:FindFirstChild(partName)
				if part and part:IsA("BasePart") then
					part.Color = color
				end
			end
		end
	end

	-- BodyColors would overwrite our part colours on respawn/refresh, so drop it.
	local bodyColors = character:FindFirstChildOfClass("BodyColors")
	if bodyColors then
		bodyColors:Destroy()
	end

	local headwear = Catalog.Get(equipped.Headwear or "")
	if headwear and headwear.Style ~= "None" then
		-- Hide hats from the Roblox avatar so they do not clip with our headwear.
		for _, child in character:GetChildren() do
			if child:IsA("Accessory") and child.AccessoryType == Enum.AccessoryType.Hat then
				child:Destroy()
			end
		end
		buildHeadwear(character, headwear)
	end

	local trail = Catalog.Get(equipped.Trail or "")
	if trail then
		buildTrail(character, trail)
	end
end

return Cosmetics
