local roblox = require("@lune/roblox")
local Fixture = require("./fixture")

-- Axis-aligned bounds of a Part (everything the world builder makes is unrotated).
local function bounds(part)
	local p, s = part.CFrame.Position, part.Size
	return {
		minX = p.X - s.X / 2,
		maxX = p.X + s.X / 2,
		minY = p.Y - s.Y / 2,
		maxY = p.Y + s.Y / 2,
		minZ = p.Z - s.Z / 2,
		maxZ = p.Z + s.Z / 2,
	}
end

local function overlapsXZ(a, b, margin)
	margin = margin or 0
	return a.minX < b.maxX - margin and a.maxX > b.minX + margin and a.minZ < b.maxZ - margin and a.maxZ > b.minZ + margin
end

return function(T)
	local fx = Fixture.new()
	local Config = fx:require("ReplicatedStorage.Shared.Config")
	local WorldBuilder = fx:require("ServerScriptService.Server.WorldBuilder")

	local town = WorldBuilder.build(fx.Workspace)
	local world = WorldBuilder.info(town)
	local W = Config.World
	local pitch = W.BlockSize + W.RoadWidth
	local span = W.Blocks * pitch + W.RoadWidth

	T.test("town is parented to the workspace and named Town", function()
		T.eq(town.Name, "Town")
		T.eq(town.Parent, fx.Workspace)
	end)

	T.test("every non-depot block has the expected number of houses", function()
		local expected = (W.Blocks * W.Blocks - 1) * 2 * W.HousesPerRow
		T.eq(#world.Houses, expected)
		T.eq(#town.Houses:GetChildren(), expected)
	end)

	T.test("house ids are 1..n and addresses are unique", function()
		local addresses = {}
		for index, house in world.Houses do
			T.eq(house.Id, index, "ids must be contiguous")
			T.falsy(addresses[house.Address], "duplicate address " .. house.Address)
			addresses[house.Address] = true
			T.eq(house.Address, house.Number .. " " .. house.Street)
		end
	end)

	T.test("house numbers are shown on the plaque", function()
		for _, model in town.Houses:GetChildren() do
			local plaque = model:FindFirstChild("NumberPlaque")
			T.truthy(plaque, model.Name .. " has no plaque")
			local label = plaque:FindFirstChildOfClass("SurfaceGui"):FindFirstChildOfClass("TextLabel")
			T.eq(label.Text, tostring(model:GetAttribute("Number")))
		end
	end)

	T.test("delivery markers lie on a road lane inside the town", function()
		local half = span / 2
		for _, house in world.Houses do
			local m = house.MarkerPos
			T.truthy(math.abs(m.X) < half and math.abs(m.Z) < half, house.Address .. " marker outside the town")
			-- must be inside one of the east-west road bands
			local onRoad = false
			for k = 0, W.Blocks do
				local roadZ = (k - W.Blocks / 2) * pitch
				if math.abs(m.Z - roadZ) <= W.RoadWidth / 2 then
					onRoad = true
				end
			end
			T.truthy(onRoad, house.Address .. " marker is not on a road")
		end
	end)

	T.test("each delivery marker is in the lane right in front of its own house", function()
		for _, model in town.Houses:GetChildren() do
			local marker = model:GetAttribute("MarkerPos")
			local door = model.Door.CFrame.Position
			T.near(marker.X, door.X, 1e-3, model.Name .. " marker should be straight out from the door")
			local gap = math.abs(marker.Z - door.Z)
			T.truthy(gap > 15 and gap < 40, model.Name .. " marker is " .. gap .. " studs from the door")
			-- it must be on the same side of the door as the house faces (away from the block centre)
			local blockCentre = nil
			for k = 1, W.Blocks do
				local c = (k - (W.Blocks + 1) / 2) * pitch
				if math.abs(door.Z - c) < W.BlockSize / 2 then
					blockCentre = c
				end
			end
			T.truthy(blockCentre, "door is inside a block")
			T.truthy((marker.Z - blockCentre) * (door.Z - blockCentre) > 0, model.Name .. " marker is on the far side of the block")
			T.truthy(math.abs(marker.Z - blockCentre) > math.abs(door.Z - blockCentre), model.Name .. " marker should be further out than the door")
		end
	end)

	T.test("houses stay on their lawn and never overlap each other, roads or the depot", function()
		local bodies = {}
		for _, model in town.Houses:GetChildren() do
			bodies[#bodies + 1] = { name = model.Name, b = bounds(model.Body) }
		end
		for i = 1, #bodies do
			for j = i + 1, #bodies do
				T.falsy(overlapsXZ(bodies[i].b, bodies[j].b), bodies[i].name .. " overlaps " .. bodies[j].name)
			end
		end
		-- Roofs overhang the walls by 1.2 studs; they must still clear the road.
		for _, model in town.Houses:GetChildren() do
			local roof = bounds(model.Roof)
			for _, road in town.Roads:GetChildren() do
				T.falsy(overlapsXZ(roof, bounds(road)), model.Name .. " roof overlaps " .. road.Name)
			end
		end
		local depotBlock = Config.World.BlockSize / 2
		for _, model in town.Houses:GetChildren() do
			T.falsy(
				overlapsXZ(bounds(model.Roof), { minX = -depotBlock, maxX = depotBlock, minZ = -depotBlock, maxZ = depotBlock }),
				model.Name .. " intrudes on the depot block"
			)
		end
	end)

	T.test("roads form a continuous flush surface", function()
		local roads = town.Roads:GetChildren()
		-- (N+1) east-west roads plus (N+1)*N north-south segments
		T.eq(#roads, (W.Blocks + 1) + (W.Blocks + 1) * W.Blocks)
		for _, road in roads do
			local b = bounds(road)
			T.near(b.maxY, 0.1, 1e-4, road.Name .. " top should be flush at 0.1")
		end
	end)

	T.test("nothing is positioned with NaN or leaves the ground plate", function()
		local ground = town.Ground
		local g = bounds(ground)
		for _, part in town:GetDescendants() do
			if part:IsA("BasePart") then
				local p = part.CFrame.Position
				T.truthy(p.X == p.X and p.Y == p.Y and p.Z == p.Z, part:GetFullName() .. " has NaN position")
				if part.Parent.Name ~= "Boundary" and part ~= ground then
					local b = bounds(part)
					T.truthy(b.minX >= g.minX and b.maxX <= g.maxX and b.minZ >= g.minZ and b.maxZ <= g.maxZ, part.Name .. " is outside the ground")
				end
			end
		end
	end)

	T.test("depot has a dispatch prompt, garage prompt and spawn", function()
		T.eq(world.DispatchPrompt.ClassName, "ProximityPrompt")
		T.eq(world.GaragePrompt.ClassName, "ProximityPrompt")
		T.eq(world.Spawn.ClassName, "SpawnLocation")
		T.truthy(world.DispatchPos.Magnitude > 0)
	end)

	T.test("the pickup pad is inside the dispatch prompt's reach", function()
		local pad = town.Depot.PickupPad
		local distance = (pad.CFrame.Position - world.DispatchPos).Magnitude
		T.truthy(distance < world.DispatchPrompt.MaxActivationDistance - 4, "pad centre is " .. distance .. " studs from the prompt")
	end)

	T.test("the spawn pad is clear of buildings and inside the depot yard", function()
		local s = bounds(world.Spawn)
		for _, name in { "Warehouse", "Garage", "DispatchCounter" } do
			T.falsy(overlapsXZ(s, bounds(town.Depot[name])), "spawn overlaps " .. name)
		end
		local half = W.BlockSize / 2 - W.SidewalkWidth
		T.truthy(s.minX > -half and s.maxX < half and s.minZ > -half and s.maxZ < half)
	end)

	T.test("depot buildings fit inside the yard", function()
		local half = W.BlockSize / 2 - W.SidewalkWidth
		for _, name in { "Warehouse", "WarehouseRoof", "Garage", "GarageRoof", "Awning", "DispatchCounter" } do
			local b = bounds(town.Depot[name])
			T.truthy(b.minX >= -half and b.maxX <= half and b.minZ >= -half and b.maxZ <= half, name .. " sticks out of the yard")
		end
	end)

	T.test("an open lane exists from the pickup pad to the road (no building in the way)", function()
		-- Straight line out of the yard along x = 0 towards +z must not hit the garage/warehouse.
		local pad = bounds(town.Depot.PickupPad)
		for _, name in { "Warehouse", "Garage" } do
			local b = bounds(town.Depot[name])
			local blocksLane = b.minX < pad.maxX and b.maxX > pad.minX and b.minZ > pad.maxZ
			T.falsy(blocksLane, name .. " blocks the way out from the pad")
		end
	end)

	T.test("part count is reasonable", function()
		local count = 0
		for _, d in town:GetDescendants() do
			if d:IsA("BasePart") then
				count += 1
			end
		end
		T.truthy(count > 1500 and count < 6000, "part count: " .. count)
	end)

	T.test("build is deterministic", function()
		local second = fx:require("ServerScriptService.Server.WorldBuilder").build(roblox.Instance.new("Folder"))
		local a, b = town.Houses:GetChildren(), second.Houses:GetChildren()
		T.eq(#a, #b)
		for i = 1, #a do
			T.eq(a[i]:GetAttribute("Address"), b[i]:GetAttribute("Address"))
			T.eq(a[i].Body.Color, b[i].Body.Color)
			T.eq(a[i].Body.Size, b[i].Body.Size)
		end
	end)
end
