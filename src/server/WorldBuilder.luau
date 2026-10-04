-- Procedurally builds the town: ground, roads, restaurant, houses.
local Workspace = game:GetService("Workspace")

local WorldBuilder = {}

local GRID = 4 -- blocks per side
local BLOCK = 120
local ROAD = 30
local STRIDE = BLOCK + ROAD

local function part(parent: Instance, name: string, size: Vector3, pos: Vector3, color: Color3, material: Enum.Material?)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Position = pos
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function makeHouse(parent: Folder, pos: Vector3, index: number, rng: Random)
	local model = Instance.new("Model")
	model.Name = "House" .. index
	local wallColor = Color3.fromHSV(rng:NextNumber(), 0.25, 0.95)
	local w, d = rng:NextInteger(18, 26), rng:NextInteger(18, 26)
	part(model, "Walls", Vector3.new(w, 12, d), pos + Vector3.new(0, 6, 0), wallColor)
	local roof = part(model, "Roof", Vector3.new(w + 3, 2, d + 3), pos + Vector3.new(0, 13, 0), Color3.fromRGB(120, 50, 40), Enum.Material.Slate)
	roof.Name = "Roof"
	local door = part(model, "Door", Vector3.new(5, 8, 1), pos + Vector3.new(0, 4, d / 2 + 0.5), Color3.fromRGB(90, 60, 40), Enum.Material.Wood)
	model.PrimaryPart = model:FindFirstChild("Walls") :: BasePart

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "DeliverPrompt"
	prompt.ActionText = "Deliver Package"
	prompt.ObjectText = "House " .. index
	prompt.HoldDuration = 0.4
	prompt.MaxActivationDistance = 14
	prompt.Enabled = false
	prompt.RequiresLineOfSight = false
	prompt.Parent = door
	model.Parent = parent
	return model, door, prompt
end

function WorldBuilder.build()
	local world = Instance.new("Folder")
	world.Name = "World"
	world.Parent = Workspace

	for _, c in Workspace:GetChildren() do
		if c.Name == "Baseplate" then
			c:Destroy()
		end
	end

	local total = GRID * STRIDE + ROAD
	local center = Vector3.new(0, 0, 0)
	part(world, "Ground", Vector3.new(total + 400, 2, total + 400), center + Vector3.new(0, -1, 0), Color3.fromRGB(88, 140, 70), Enum.Material.Grass)

	local origin = -total / 2
	-- roads
	for i = 0, GRID do
		local offset = origin + ROAD / 2 + i * STRIDE
		part(world, "RoadX", Vector3.new(total, 0.4, ROAD), Vector3.new(0, 0.2, offset), Color3.fromRGB(45, 45, 50), Enum.Material.Asphalt)
		part(world, "RoadZ", Vector3.new(ROAD, 0.4, total), Vector3.new(offset, 0.25, 0), Color3.fromRGB(45, 45, 50), Enum.Material.Asphalt)
		part(world, "LineX", Vector3.new(total, 0.1, 0.8), Vector3.new(0, 0.5, offset), Color3.fromRGB(240, 220, 90))
		part(world, "LineZ", Vector3.new(0.8, 0.1, total), Vector3.new(offset, 0.55, 0), Color3.fromRGB(240, 220, 90))
	end

	-- city blocks: sidewalks + houses (block 1,1 is the restaurant block)
	local houses = Instance.new("Folder")
	houses.Name = "Houses"
	houses.Parent = world
	local rng = Random.new(1337)
	local count = 0
	local restaurantPos
	for gx = 1, GRID do
		for gz = 1, GRID do
			local cx = origin + ROAD + (gx - 1) * STRIDE + BLOCK / 2
			local cz = origin + ROAD + (gz - 1) * STRIDE + BLOCK / 2
			part(world, "Sidewalk", Vector3.new(BLOCK, 0.8, BLOCK), Vector3.new(cx, 0.4, cz), Color3.fromRGB(190, 190, 190), Enum.Material.Concrete)
			if gx == 1 and gz == 1 then
				restaurantPos = Vector3.new(cx, 0.8, cz)
			else
				-- four houses facing +Z, arranged in a 2x2 inside the block
				for hx = -1, 1, 2 do
					for hz = -1, 1, 2 do
						count += 1
						local pos = Vector3.new(cx + hx * 28, 0.8, cz + hz * 28)
						makeHouse(houses, pos, count, rng)
					end
				end
			end
		end
	end

	-- restaurant
	local rest = Instance.new("Model")
	rest.Name = "Restaurant"
	part(rest, "Building", Vector3.new(60, 18, 50), restaurantPos + Vector3.new(0, 9, 0), Color3.fromRGB(220, 60, 50))
	part(rest, "Awning", Vector3.new(62, 2, 12), restaurantPos + Vector3.new(0, 14, 30), Color3.fromRGB(255, 255, 255))
	local counter = part(rest, "PickupCounter", Vector3.new(12, 4, 4), restaurantPos + Vector3.new(0, 2, 28), Color3.fromRGB(255, 200, 80), Enum.Material.Wood)
	local sign = part(rest, "Sign", Vector3.new(36, 6, 1), restaurantPos + Vector3.new(0, 21, 25), Color3.fromRGB(30, 30, 30))
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.Parent = sign
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = "BURGER BARN"
	label.TextScaled = true
	label.Font = Enum.Font.FredokaOne
	label.TextColor3 = Color3.fromRGB(255, 220, 60)
	label.Parent = gui

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "PickupPrompt"
	prompt.ActionText = "Pick Up Order"
	prompt.ObjectText = "Burger Barn"
	prompt.HoldDuration = 0.5
	prompt.MaxActivationDistance = 14
	prompt.RequiresLineOfSight = false
	prompt.Parent = counter
	rest.PrimaryPart = rest:FindFirstChild("Building") :: BasePart
	rest.Parent = world

	-- spawn + car dealer
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "Spawn"
	spawn.Size = Vector3.new(14, 1, 14)
	spawn.Position = restaurantPos + Vector3.new(0, 0.5, 55)
	spawn.Anchored = true
	spawn.Neutral = true
	spawn.Material = Enum.Material.Neon
	spawn.Color = Color3.fromRGB(255, 200, 60)
	spawn.Parent = world

	local garage = part(world, "GarageStand", Vector3.new(10, 1, 10), restaurantPos + Vector3.new(30, 1.3, 55), Color3.fromRGB(50, 120, 255), Enum.Material.Neon)
	local shopPrompt = Instance.new("ProximityPrompt")
	shopPrompt.Name = "ShopPrompt"
	shopPrompt.ActionText = "Open Car Shop"
	shopPrompt.ObjectText = "Garage"
	shopPrompt.HoldDuration = 0
	shopPrompt.MaxActivationDistance = 12
	shopPrompt.Parent = garage

	return {
		Houses = houses,
		Restaurant = rest,
		PickupPrompt = prompt,
		ShopPrompt = shopPrompt,
		Spawn = spawn,
		CarSpawn = restaurantPos + Vector3.new(15, 3, 70),
	}
end

return WorldBuilder
