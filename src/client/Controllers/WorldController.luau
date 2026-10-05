--[[
	WorldController
	Small client-side world features:
	  * hides other players' "Diagnose" prompts (you can only treat your own)
	  * hides a hospital's roof while you are inside it so you can see in
	  * ambulances driving around the ring road with flashing lights
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")

local WorldController = {}

local player = Players.LocalPlayer

-- Prompts ---------------------------------------------------------------------------

local function filterPrompt(prompt: Instance)
	if prompt:IsA("ProximityPrompt") then
		local owner = prompt:GetAttribute("OwnerUserId")
		if owner ~= nil and owner ~= player.UserId then
			prompt.Enabled = false
		end
	end
end

local function setupPrompts()
	workspace.DescendantAdded:Connect(filterPrompt)
	for _, descendant in workspace:GetDescendants() do
		filterPrompt(descendant)
	end
end

-- Roofs -----------------------------------------------------------------------------

local hidden: { [Instance]: boolean } = {}

local function setRoofHidden(hospital: Instance, hide: boolean)
	local roofGroup = hospital:FindFirstChild("RoofGroup")
	if not roofGroup then
		return
	end
	for _, part in roofGroup:GetDescendants() do
		if part:IsA("BasePart") then
			part.LocalTransparencyModifier = if hide then 1 else 0
		end
	end
	for _, gui in roofGroup:GetDescendants() do
		if gui:IsA("SurfaceGui") then
			gui.Enabled = not hide
		end
	end
end

local function insideBounds(bounds: BasePart, point: Vector3): boolean
	local localPoint = bounds.CFrame:PointToObjectSpace(point)
	local size = bounds.Size
	return math.abs(localPoint.X) <= size.X / 2 and math.abs(localPoint.Z) <= size.Z / 2 and localPoint.Y <= size.Y / 2 + 2 and localPoint.Y >= -size.Y / 2 - 2
end

local function updateRoofs()
	local plots = workspace:FindFirstChild("Plots")
	if not plots then
		return
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local seen = {}
	for _, plot in plots:GetChildren() do
		local hospital = plot:FindFirstChild("Hospital")
		local bounds = hospital and hospital:FindFirstChild("Bounds")
		if hospital and bounds and bounds:IsA("BasePart") then
			seen[hospital] = true
			local inside = root ~= nil and insideBounds(bounds, root.Position)
			if (hidden[hospital] or false) ~= inside then
				hidden[hospital] = inside
				setRoofHidden(hospital, inside)
			end
		end
	end
	for hospital in hidden do
		if not seen[hospital] then
			hidden[hospital] = nil
		end
	end
end

-- Ambulances ----------------------------------------------------------------------------

type Vehicle = { Model: Model, Radius: number, Speed: number, Angle: number, Lights: { BasePart } }

local vehicles: { Vehicle } = {}

local function part(model: Model, size: Vector3, offset: CFrame, color: Color3, material: Enum.Material?, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Size = size
	p.CFrame = offset
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if shape then
		p.Shape = shape
	end
	p.Parent = model
	return p
end

local function buildAmbulance(): (Model, { BasePart })
	local model = Instance.new("Model")
	model.Name = "AmbientAmbulance"
	local body = part(model, Vector3.new(7, 6, 11), CFrame.new(0, 4, 1.5), Color3.fromRGB(250, 250, 250))
	model.PrimaryPart = body
	part(model, Vector3.new(7, 4, 5), CFrame.new(0, 3, -6.5), Color3.fromRGB(250, 250, 250))
	part(model, Vector3.new(6.6, 2, 0.2), CFrame.new(0, 4, -9.05), Color3.fromRGB(150, 210, 255), Enum.Material.Glass)
	part(model, Vector3.new(7.1, 0.8, 16.2), CFrame.new(0, 3, -1), Color3.fromRGB(220, 50, 50))
	part(model, Vector3.new(3, 1, 0.2), CFrame.new(0, 4.6, 7.06), Color3.fromRGB(220, 50, 50))
	part(model, Vector3.new(1, 3, 0.2), CFrame.new(0, 4.6, 7.07), Color3.fromRGB(220, 50, 50))
	local red = part(model, Vector3.new(1.5, 0.6, 1), CFrame.new(-1.6, 7.3, -2), Color3.fromRGB(255, 40, 40), Enum.Material.Neon)
	local blue = part(model, Vector3.new(1.5, 0.6, 1), CFrame.new(1.6, 7.3, -2), Color3.fromRGB(40, 120, 255), Enum.Material.Neon)
	for _, wheel in { { -3.5, -5 }, { 3.5, -5 }, { -3.5, 5 }, { 3.5, 5 } } do
		part(model, Vector3.new(1, 3, 3), CFrame.new(wheel[1], 1.5, wheel[2]), Color3.fromRGB(30, 30, 30), nil, Enum.PartType.Cylinder)
	end
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 80, 80)
	light.Range = 14
	light.Brightness = 2
	light.Parent = red
	return model, { red, blue }
end

local function setupAmbulances()
	local folder = Instance.new("Folder")
	folder.Name = "Ambient"
	folder.Parent = workspace
	for i, def in { { Radius = 138, Speed = 30 }, { Radius = 126, Speed = -24 } } do
		local model, lights = buildAmbulance()
		model.Parent = folder
		table.insert(vehicles, {
			Model = model,
			Radius = def.Radius,
			Speed = def.Speed,
			Angle = i * math.pi,
			Lights = lights,
		})
	end
	RunService.Heartbeat:Connect(function(dt)
		local blink = math.floor(os.clock() * 3) % 2 == 0
		for _, vehicle in vehicles do
			vehicle.Angle += vehicle.Speed / vehicle.Radius * dt
			local a = vehicle.Angle
			local position = Vector3.new(math.sin(a) * vehicle.Radius, 0.3, math.cos(a) * vehicle.Radius)
			local tangent = Vector3.new(math.cos(a), 0, -math.sin(a)) * math.sign(vehicle.Speed)
			vehicle.Model:PivotTo(CFrame.lookAt(position, position + tangent))
			vehicle.Lights[1].Transparency = if blink then 0 else 0.7
			vehicle.Lights[2].Transparency = if blink then 0.7 else 0
		end
	end)
end

function WorldController.Init()
	pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
	end)
end

function WorldController.Start()
	setupPrompts()
	setupAmbulances()
	task.spawn(function()
		while true do
			updateRoofs()
			task.wait(0.2)
		end
	end)
	CollectionService:GetInstanceAddedSignal("HospitalRoof"):Connect(function()
		-- A hospital was rebuilt; force the next check to re-apply visibility.
		table.clear(hidden)
	end)
end

return WorldController
