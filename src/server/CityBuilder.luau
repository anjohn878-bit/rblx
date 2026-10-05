-- Generates the town of Parcelton at server start: a grid of roads, the parcel depot in the
-- middle, downtown offices around it and houses everywhere else. A fixed random seed means the
-- streets look the same in every server, so players can learn their routes.
--
-- Returns a registry the gameplay code uses: every deliverable address and the depot's
-- interactive bits.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)

local CityBuilder = {}

export type Address = {
	Id: number,
	Name: string?, -- business name, nil for houses
	Address: string, -- "312 Maple St"
	Kind: string, -- "House" | "Business"
	Position: Vector3, -- where the parcel is handed over
	Facing: Vector3, -- direction the front door faces
	DepotDistance: number,
}

export type Registry = {
	Addresses: { Address },
	Depot: {
		Counter: Vector3,
		LoadPrompt: ProximityPrompt,
		ShopPrompt: ProximityPrompt,
		SpawnPrompt: ProximityPrompt,
		ParkingSpots: { CFrame },
		Bounds: { Min: Vector3, Max: Vector3 },
	},
	StreetLights: { BasePart },
}

local CITY = Config.City
local ROAD_TOP = 0.05
local CURB_TOP = 0.45
local LAWN_TOP = 0.5

local STREET_NAMES = { "Maple", "Oak", "Cedar", "Pine", "Elm", "Birch", "Willow", "Aspen" }

local BUSINESSES = {
	"Bean Brew Cafe",
	"Pixel Pizza",
	"Blocky Burgers",
	"Starlight Cinema",
	"Brick Bakery",
	"Neon Arcade",
	"Stud Fitness",
	"Builder's Hardware",
	"Happy Paws Vet",
	"Sunny Side Books",
	"Glow Gadgets",
	"Fresh Mart",
	"Cozy Furniture",
	"Turbo Toys",
	"Rocket Realty",
	"Sushi Spin",
	"Taco Tower",
	"Spark Electric",
	"Green Leaf Florist",
	"Gold Coin Jewelers",
	"Moonlight Hotel",
	"Cloud Nine Offices",
	"Igloo Ice Cream",
	"Paint Splash Studio",
	"Bright Smile Dental",
	"Quick Fix Repairs",
	"City Library",
	"Parcelton Times",
	"Lucky Noodle",
	"Pebble Pharmacy",
	"Orbit Software",
	"Velvet Theater",
}

local HOUSE_COLORS = {
	Color3.fromRGB(240, 222, 180),
	Color3.fromRGB(182, 210, 232),
	Color3.fromRGB(232, 190, 190),
	Color3.fromRGB(200, 226, 190),
	Color3.fromRGB(248, 244, 236),
	Color3.fromRGB(214, 184, 152),
	Color3.fromRGB(196, 192, 220),
	Color3.fromRGB(244, 208, 140),
}
local ROOF_COLORS = {
	Color3.fromRGB(128, 62, 52),
	Color3.fromRGB(72, 72, 82),
	Color3.fromRGB(96, 64, 44),
	Color3.fromRGB(62, 92, 116),
}
local DOOR_COLORS = {
	Color3.fromRGB(112, 72, 42),
	Color3.fromRGB(42, 72, 112),
	Color3.fromRGB(142, 42, 42),
	Color3.fromRGB(42, 102, 62),
}
local OFFICE_COLORS = {
	Color3.fromRGB(200, 200, 205),
	Color3.fromRGB(222, 212, 190),
	Color3.fromRGB(160, 170, 185),
	Color3.fromRGB(190, 160, 140),
	Color3.fromRGB(120, 130, 150),
}

local rng = Random.new(2026)

local function pick<T>(list: { T }): T
	return list[rng:NextInteger(1, #list)]
end

local function newPart(parent: Instance, props: { [string]: any }): Part
	local part = Instance.new("Part")
	part.Anchored = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Material = Enum.Material.SmoothPlastic
	for key, value in props do
		(part :: any)[key] = value
	end
	part.Parent = parent
	return part
end

local function addSign(part: BasePart, face: Enum.NormalId, text: string, textColor: Color3, maxDistance: number?)
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 30
	gui.LightInfluence = 0.3
	gui.MaxDistance = maxDistance or 0
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = textColor
	label.Text = text
	label.Parent = gui
	gui.Parent = part
end

local function addPrompt(part: BasePart, name: string, action: string, object: string, hold: number): ProximityPrompt
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = name
	prompt.ActionText = action
	prompt.ObjectText = object
	prompt.HoldDuration = hold
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Parent = part
	return prompt
end

-- Grid helpers -------------------------------------------------------------------------------

-- Centre of block (bx, bz), indices 0 .. BlocksPerSide-1.
local function blockCenter(bx: number, bz: number): Vector3
	local offset = (CITY.BlocksPerSide - 1) / 2
	return Vector3.new((bx - offset) * CITY.CellSize, 0, (bz - offset) * CITY.CellSize)
end

-- Centre line of road k (0 .. BlocksPerSide) along either axis.
local function roadLine(k: number): number
	return -CITY.Extent + k * CITY.CellSize
end

-- Scenery ------------------------------------------------------------------------------------

local function buildTree(parent: Instance, position: Vector3, scale: number)
	local trunkHeight = 6 * scale
	newPart(parent, {
		Name = "Trunk",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(trunkHeight, 1.4 * scale, 1.4 * scale),
		CFrame = CFrame.new(position + Vector3.new(0, trunkHeight / 2, 0)) * CFrame.Angles(0, 0, math.pi / 2),
		Color = Color3.fromRGB(110, 76, 50),
		Material = Enum.Material.Wood,
	})
	local leaves = Color3.fromRGB(rng:NextInteger(60, 90), rng:NextInteger(130, 165), rng:NextInteger(55, 80))
	newPart(parent, {
		Name = "Leaves",
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * 8 * scale,
		Position = position + Vector3.new(0, trunkHeight + 2 * scale, 0),
		Color = leaves,
		Material = Enum.Material.Grass,
	})
	newPart(parent, {
		Name = "Leaves",
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * 5.5 * scale,
		Position = position + Vector3.new(1.5 * scale, trunkHeight + 5 * scale, 0.8 * scale),
		Color = leaves:Lerp(Color3.new(1, 1, 1), 0.08),
		Material = Enum.Material.Grass,
	})
end

local function buildStreetLight(parent: Instance, position: Vector3, toward: Vector3, lights: { BasePart })
	local model = Instance.new("Model")
	model.Name = "StreetLight"
	local poleTop = position + Vector3.new(0, 14, 0)
	newPart(model, {
		Name = "Pole",
		Size = Vector3.new(0.6, 14, 0.6),
		Position = position + Vector3.new(0, 7, 0),
		Color = Color3.fromRGB(60, 62, 70),
		Material = Enum.Material.Metal,
	})
	local direction = Vector3.new(toward.X - position.X, 0, toward.Z - position.Z).Unit
	local lampPosition = poleTop + direction * 3.5
	newPart(model, {
		Name = "Arm",
		Size = Vector3.new(0.4, 0.4, 3.6),
		CFrame = CFrame.lookAt((poleTop + lampPosition) / 2, lampPosition),
		Color = Color3.fromRGB(60, 62, 70),
		Material = Enum.Material.Metal,
	})
	local bulb = newPart(model, {
		Name = "Bulb",
		Size = Vector3.new(1.6, 0.6, 1.6),
		Position = lampPosition - Vector3.new(0, 0.4, 0),
		Color = Color3.fromRGB(255, 236, 190),
		CastShadow = false,
	})
	local light = Instance.new("PointLight")
	light.Range = 32
	light.Brightness = 1.6
	light.Color = Color3.fromRGB(255, 220, 170)
	light.Enabled = false
	light.Parent = bulb
	table.insert(lights, bulb)
	model.Parent = parent
end

-- Roads --------------------------------------------------------------------------------------

local function buildRoads(parent: Instance)
	local folder = Instance.new("Folder")
	folder.Name = "Roads"
	local size = CITY.Extent * 2 + CITY.RoadWidth
	newPart(folder, {
		Name = "Asphalt",
		Size = Vector3.new(size, 1, size),
		Position = Vector3.new(0, ROAD_TOP - 0.5, 0),
		Color = Color3.fromRGB(58, 60, 66),
		Material = Enum.Material.Asphalt,
	})

	-- A yellow centre line on every stretch of road between two intersections.
	local yellow = Color3.fromRGB(245, 200, 60)
	local segment = CITY.BlockSize
	for k = 0, CITY.BlocksPerSide do
		local line = roadLine(k)
		for b = 0, CITY.BlocksPerSide - 1 do
			local mid = blockCenter(b, b).X
			newPart(folder, {
				Name = "CenterLine",
				Size = Vector3.new(0.6, 0.2, segment - 4),
				Position = Vector3.new(line, ROAD_TOP - 0.05, mid),
				Color = yellow,
				CanCollide = false,
				CastShadow = false,
			})
			newPart(folder, {
				Name = "CenterLine",
				Size = Vector3.new(segment - 4, 0.2, 0.6),
				Position = Vector3.new(mid, ROAD_TOP - 0.05, line),
				Color = yellow,
				CanCollide = false,
				CastShadow = false,
			})
		end
	end
	folder.Parent = parent
end

-- Blocks -------------------------------------------------------------------------------------

local function buildBlockBase(parent: Instance, center: Vector3, topColor: Color3?, topMaterial: Enum.Material?)
	newPart(parent, {
		Name = "Sidewalk",
		Size = Vector3.new(CITY.BlockSize, 1, CITY.BlockSize),
		Position = Vector3.new(center.X, CURB_TOP - 0.5, center.Z),
		Color = Color3.fromRGB(196, 196, 200),
		Material = Enum.Material.Concrete,
	})
	if topColor then
		local inner = CITY.BlockSize - CITY.SidewalkWidth * 2
		newPart(parent, {
			Name = "Ground",
			Size = Vector3.new(inner, 1, inner),
			Position = Vector3.new(center.X, LAWN_TOP - 0.5, center.Z),
			Color = topColor,
			Material = topMaterial or Enum.Material.Grass,
		})
	end
end

local function streetFor(bz: number, facingNorth: boolean): string
	-- A building on the north edge of block bz faces road bz; on the south edge, road bz + 1.
	local roadIndex = if facingNorth then bz else bz + 1
	return STREET_NAMES[roadIndex + 1] .. " St"
end

local function houseNumber(bx: number, slot: number, facingNorth: boolean): number
	-- Even numbers on the south side of a street, odd numbers on the north side.
	return (bx + 1) * 100 + 10 + slot * 20 + (if facingNorth then 0 else 1)
end

local function buildHouse(parent: Instance, cf: CFrame, number: number, street: string): Vector3
	local model = Instance.new("Model")
	model.Name = number .. " " .. street

	local width, depth, height = 24, 18, 11
	local wallColor = pick(HOUSE_COLORS)
	local function at(x: number, y: number, z: number): CFrame
		return cf * CFrame.new(x, y, z)
	end

	newPart(model, {
		Name = "Walls",
		Size = Vector3.new(width, height, depth),
		CFrame = at(0, height / 2, 0),
		Color = wallColor,
		Material = if rng:NextNumber() < 0.3 then Enum.Material.Brick else Enum.Material.SmoothPlastic,
	})
	-- A square beam rolled 45 degrees: the top half pokes out as a gable roof, the bottom half
	-- hides inside the walls. Works without relying on wedge orientation.
	local roofSide = (depth / 2 + 1) * math.sqrt(2)
	newPart(model, {
		Name = "Roof",
		Size = Vector3.new(width - 0.2, roofSide, roofSide),
		CFrame = at(0, height, 0) * CFrame.Angles(math.rad(45), 0, 0),
		Color = pick(ROOF_COLORS),
	})
	if rng:NextNumber() < 0.5 then
		newPart(model, {
			Name = "Chimney",
			Size = Vector3.new(2, 7, 2),
			CFrame = at(width / 2 - 4, height + 5, 4),
			Color = Color3.fromRGB(150, 80, 64),
			Material = Enum.Material.Brick,
		})
	end

	local front = -depth / 2
	newPart(model, {
		Name = "Door",
		Size = Vector3.new(4.5, 7.5, 0.4),
		CFrame = at(0, 3.75, front - 0.1),
		Color = pick(DOOR_COLORS),
		Material = Enum.Material.Wood,
	})
	for _, x in { -7, 7 } do
		newPart(model, {
			Name = "Window",
			Size = Vector3.new(5, 4, 0.3),
			CFrame = at(x, 6, front - 0.1),
			Color = Color3.fromRGB(170, 210, 235),
			Material = Enum.Material.Glass,
			Reflectance = 0.15,
		})
	end
	local plaque = newPart(model, {
		Name = "NumberPlaque",
		Size = Vector3.new(2.6, 1.2, 0.2),
		CFrame = at(3.8, 8.6, front - 0.15),
		Color = Color3.fromRGB(40, 40, 46),
	})
	addSign(plaque, Enum.NormalId.Front, tostring(number), Color3.new(1, 1, 1), 150)

	newPart(model, {
		Name = "Porch",
		Size = Vector3.new(9, 0.5, 4),
		CFrame = at(0, 0.25, front - 2),
		Color = Color3.fromRGB(176, 172, 166),
		Material = Enum.Material.Concrete,
	})
	local yard = 14 -- distance from the front wall to the sidewalk
	newPart(model, {
		Name = "Path",
		Size = Vector3.new(3, 0.2, yard - 4),
		CFrame = at(0, 0.05, front - 4 - (yard - 4) / 2),
		Color = Color3.fromRGB(176, 172, 166),
		Material = Enum.Material.Concrete,
		CanCollide = false,
	})
	newPart(model, {
		Name = "MailboxPost",
		Size = Vector3.new(0.4, 3.4, 0.4),
		CFrame = at(3.6, 1.7, front - yard + 1.2),
		Color = Color3.fromRGB(110, 76, 50),
		Material = Enum.Material.Wood,
	})
	newPart(model, {
		Name = "Mailbox",
		Size = Vector3.new(1.1, 1.1, 1.8),
		CFrame = at(3.6, 3.7, front - yard + 1.2),
		Color = Color3.fromRGB(50, 90, 160),
		Material = Enum.Material.Metal,
	})

	model.Parent = parent
	-- Hand-over spot on the path just in front of the porch.
	return (cf * CFrame.new(0, 3, front - 6.5)).Position
end

local function buildOffice(parent: Instance, cf: CFrame, name: string): Vector3
	local model = Instance.new("Model")
	model.Name = name

	local width, depth = 46, 40
	local height = pick({ 36, 48, 60, 72, 84 })
	local function at(x: number, y: number, z: number): CFrame
		return cf * CFrame.new(x, y, z)
	end

	newPart(model, {
		Name = "Tower",
		Size = Vector3.new(width, height, depth),
		CFrame = at(0, height / 2, 0),
		Color = pick(OFFICE_COLORS),
		Material = Enum.Material.Concrete,
	})
	local windowColor = Color3.fromRGB(70, 110, 150):Lerp(Color3.fromRGB(120, 170, 200), rng:NextNumber())
	local floors = math.floor((height - 14) / 12)
	for floor = 0, floors - 1 do
		newPart(model, {
			Name = "Windows",
			Size = Vector3.new(width + 0.3, 5, depth + 0.3),
			CFrame = at(0, 17 + floor * 12, 0),
			Color = windowColor,
			Material = Enum.Material.Glass,
			Reflectance = 0.2,
		})
	end
	newPart(model, {
		Name = "Cornice",
		Size = Vector3.new(width + 1.5, 1.5, depth + 1.5),
		CFrame = at(0, height + 0.75, 0),
		Color = Color3.fromRGB(80, 82, 90),
	})
	newPart(model, {
		Name = "RoofUnit",
		Size = Vector3.new(8, 3, 6),
		CFrame = at(rng:NextNumber(-12, 12), height + 3, rng:NextNumber(-10, 10)),
		Color = Color3.fromRGB(150, 152, 158),
		Material = Enum.Material.Metal,
	})

	local front = -depth / 2
	newPart(model, {
		Name = "Entrance",
		Size = Vector3.new(8, 9, 0.4),
		CFrame = at(0, 4.5, front - 0.15),
		Color = Color3.fromRGB(40, 60, 80),
		Material = Enum.Material.Glass,
		Reflectance = 0.25,
	})
	newPart(model, {
		Name = "Awning",
		Size = Vector3.new(14, 0.6, 5),
		CFrame = at(0, 10.5, front - 2.5),
		Color = Color3.fromHSV(rng:NextNumber(), 0.6, 0.85),
	})
	local sign = newPart(model, {
		Name = "Sign",
		Size = Vector3.new(26, 3.2, 0.4),
		CFrame = at(0, 13.4, front - 0.3),
		Color = Color3.fromRGB(30, 32, 40),
	})
	addSign(sign, Enum.NormalId.Front, name, Color3.fromRGB(255, 236, 200), 400)

	model.Parent = parent
	return (cf * CFrame.new(0, 3, front - 4)).Position
end

local function buildResidentialBlock(parent: Instance, bx: number, bz: number, addresses: { Address })
	local center = blockCenter(bx, bz)
	local folder = Instance.new("Folder")
	folder.Name = string.format("Block_%d_%d", bx, bz)
	buildBlockBase(folder, center, Color3.fromRGB(100, 160, 80))

	local inner = CITY.BlockSize / 2 - CITY.SidewalkWidth -- lawn half-size (59)
	local frontYard = 14
	local depth = 18
	for _, facingNorth in { true, false } do
		local sign = if facingNorth then -1 else 1
		local z = center.Z + sign * (inner - frontYard - depth / 2)
		local street = streetFor(bz, facingNorth)
		for slot = 0, 2 do
			local x = center.X + (slot - 1) * 40
			local position = Vector3.new(x, LAWN_TOP, z)
			local cf = CFrame.lookAt(position, position + Vector3.new(0, 0, sign))
			local number = houseNumber(bx, slot, facingNorth)
			local drop = buildHouse(folder, cf, number, street)
			table.insert(addresses, {
				Id = #addresses + 1,
				Address = number .. " " .. street,
				Kind = "House",
				Position = drop,
				Facing = Vector3.new(0, 0, sign),
				DepotDistance = 0,
			})
		end
	end

	-- Backyard trees.
	for _ = 1, rng:NextInteger(2, 4) do
		local offset = Vector3.new(rng:NextNumber(-50, 50), 0, rng:NextNumber(-14, 14))
		buildTree(folder, Vector3.new(center.X, LAWN_TOP, center.Z) + offset, rng:NextNumber(0.8, 1.2))
	end

	folder.Parent = parent
end

local businessIndex = 0
local function buildDowntownBlock(parent: Instance, bx: number, bz: number, addresses: { Address })
	local center = blockCenter(bx, bz)
	local folder = Instance.new("Folder")
	folder.Name = string.format("Block_%d_%d", bx, bz)
	buildBlockBase(folder, center, Color3.fromRGB(176, 170, 162), Enum.Material.Pavement)

	local inner = CITY.BlockSize / 2 - CITY.SidewalkWidth
	for _, facingNorth in { true, false } do
		local sign = if facingNorth then -1 else 1
		local z = center.Z + sign * (inner - 6 - 20)
		local street = streetFor(bz, facingNorth)
		for slot, xOffset in { -31, 31 } do
			businessIndex += 1
			local name = BUSINESSES[(businessIndex - 1) % #BUSINESSES + 1]
			local position = Vector3.new(center.X + xOffset, LAWN_TOP, z)
			local cf = CFrame.lookAt(position, position + Vector3.new(0, 0, sign))
			local drop = buildOffice(folder, cf, name)
			local number = (bx + 1) * 100 + slot * 40 - 20 + (if facingNorth then 0 else 1)
			table.insert(addresses, {
				Id = #addresses + 1,
				Name = name,
				Address = number .. " " .. street,
				Kind = "Business",
				Position = drop,
				Facing = Vector3.new(0, 0, sign),
				DepotDistance = 0,
			})
		end
	end

	folder.Parent = parent
end

local function buildPark(parent: Instance, bx: number, bz: number)
	local center = blockCenter(bx, bz)
	local folder = Instance.new("Folder")
	folder.Name = string.format("Park_%d_%d", bx, bz)
	buildBlockBase(folder, center, Color3.fromRGB(92, 168, 84))

	newPart(folder, {
		Name = "Pond",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.4, 44, 44),
		CFrame = CFrame.new(center.X + 14, LAWN_TOP + 0.02, center.Z - 10) * CFrame.Angles(0, 0, math.pi / 2),
		Color = Color3.fromRGB(70, 140, 200),
		Material = Enum.Material.Glass,
		Transparency = 0.15,
		Reflectance = 0.2,
		CanCollide = false,
	})
	local pathColor = Color3.fromRGB(196, 180, 150)
	newPart(folder, {
		Name = "Path",
		Size = Vector3.new(4, 0.2, 118),
		Position = Vector3.new(center.X - 22, LAWN_TOP, center.Z),
		Color = pathColor,
		Material = Enum.Material.Sand,
		CanCollide = false,
	})
	newPart(folder, {
		Name = "Path",
		Size = Vector3.new(118, 0.2, 4),
		Position = Vector3.new(center.X, LAWN_TOP, center.Z + 24),
		Color = pathColor,
		Material = Enum.Material.Sand,
		CanCollide = false,
	})
	for _, offset in { Vector3.new(-30, 0, 32), Vector3.new(-14, 0, 32), Vector3.new(-36, 0, -10) } do
		local seat = Instance.new("Seat")
		seat.Name = "Bench"
		seat.Size = Vector3.new(6, 1, 2)
		seat.Anchored = true
		seat.Color = Color3.fromRGB(130, 90, 60)
		seat.Material = Enum.Material.Wood
		seat.TopSurface = Enum.SurfaceType.Smooth
		seat.Position = Vector3.new(center.X, LAWN_TOP + 1.5, center.Z) + offset
		seat.Parent = folder
	end
	for _ = 1, 9 do
		local spot = Vector3.new(rng:NextNumber(-52, 52), 0, rng:NextNumber(-52, 52))
		if (spot - Vector3.new(14, 0, -10)).Magnitude > 28 then
			buildTree(folder, Vector3.new(center.X, LAWN_TOP, center.Z) + spot, rng:NextNumber(0.9, 1.4))
		end
	end
	folder.Parent = parent
end

-- Depot --------------------------------------------------------------------------------------

local function buildDepot(parent: Instance)
	local folder = Instance.new("Folder")
	folder.Name = "Depot"
	local base = LAWN_TOP -- top of the parking lot surface
	local brand = Config.Colors.Brand

	buildBlockBase(folder, Vector3.zero, Color3.fromRGB(72, 74, 80), Enum.Material.Asphalt)

	-- Warehouse with its open loading bay facing south, towards the spawn.
	newPart(folder, {
		Name = "Warehouse",
		Size = Vector3.new(96, 24, 40),
		Position = Vector3.new(0, base + 12, -38),
		Color = Color3.fromRGB(226, 228, 232),
		Material = Enum.Material.Concrete,
	})
	newPart(folder, {
		Name = "WarehouseStripe",
		Size = Vector3.new(96.3, 3, 40.3),
		Position = Vector3.new(0, base + 19, -38),
		Color = brand,
	})
	newPart(folder, {
		Name = "WarehouseRoof",
		Size = Vector3.new(98, 1.5, 42),
		Position = Vector3.new(0, base + 24.75, -38),
		Color = Color3.fromRGB(70, 72, 80),
	})
	for _, x in { -34, 34 } do
		newPart(folder, {
			Name = "RollerDoor",
			Size = Vector3.new(16, 14, 0.4),
			Position = Vector3.new(x, base + 7, -17.9),
			Color = Color3.fromRGB(96, 100, 110),
			Material = Enum.Material.CorrodedMetal,
		})
	end
	local roofSign = newPart(folder, {
		Name = "CompanySign",
		Size = Vector3.new(56, 8, 1),
		Position = Vector3.new(0, base + 29.5, -19),
		Color = brand,
	})
	addSign(roofSign, Enum.NormalId.Back, string.upper(Config.CompanyName), Color3.new(1, 1, 1))
	addSign(roofSign, Enum.NormalId.Front, string.upper(Config.CompanyName), Color3.new(1, 1, 1))

	-- Loading canopy and package counter.
	newPart(folder, {
		Name = "Canopy",
		Size = Vector3.new(36, 1, 14),
		Position = Vector3.new(0, base + 13, -11),
		Color = brand,
	})
	for _, x in { -17.5, 17.5 } do
		newPart(folder, {
			Name = "CanopyPillar",
			Size = Vector3.new(1, 13, 1),
			Position = Vector3.new(x, base + 6.5, -4.5),
			Color = Color3.fromRGB(70, 72, 80),
			Material = Enum.Material.Metal,
		})
	end
	local counter = newPart(folder, {
		Name = "Counter",
		Size = Vector3.new(16, 3.6, 3),
		Position = Vector3.new(0, base + 1.8, -12),
		Color = Color3.fromRGB(240, 240, 240),
	})
	newPart(folder, {
		Name = "CounterTop",
		Size = Vector3.new(16.4, 0.4, 3.4),
		Position = Vector3.new(0, base + 3.8, -12),
		Color = brand,
	})
	local counterSign = newPart(folder, {
		Name = "CounterSign",
		Size = Vector3.new(16, 2.6, 0.4),
		Position = Vector3.new(0, base + 10.8, -5),
		Color = Color3.fromRGB(30, 32, 40),
	})
	addSign(counterSign, Enum.NormalId.Back, "PICK UP PACKAGES HERE", Color3.fromRGB(255, 220, 160))

	local boxColor = Color3.fromRGB(205, 160, 110)
	for _ = 1, 14 do
		local size = Vector3.new(rng:NextNumber(1.6, 3), rng:NextNumber(1.4, 2.6), rng:NextNumber(1.6, 3))
		newPart(folder, {
			Name = "Parcel",
			Size = size,
			CFrame = CFrame.new(rng:NextNumber(-14, 14), base + size.Y / 2, rng:NextNumber(-17, -14.5))
				* CFrame.Angles(0, rng:NextNumber(-0.4, 0.4), 0),
			Color = boxColor:Lerp(Color3.new(0, 0, 0), rng:NextNumber(0, 0.2)),
			Material = Enum.Material.Cardboard,
		})
	end
	for _, x in { -5, -1.5, 2.5, 5.5 } do
		newPart(folder, {
			Name = "Parcel",
			Size = Vector3.new(2, 1.6, 2),
			CFrame = CFrame.new(x, base + 4.8, -12) * CFrame.Angles(0, rng:NextNumber(-0.3, 0.3), 0),
			Color = boxColor,
			Material = Enum.Material.Cardboard,
		})
	end
	local loadPrompt = addPrompt(counter, "LoadPrompt", "Load Packages", "Package Counter", 0.5)
	loadPrompt.KeyboardKeyCode = Enum.KeyCode.E

	-- Garage kiosk (opens the vehicle shop) and vehicle pick-up post.
	local kiosk = newPart(folder, {
		Name = "GarageKiosk",
		Size = Vector3.new(7, 7, 4),
		Position = Vector3.new(-30, base + 3.5, -8),
		Color = Color3.fromRGB(38, 48, 74),
	})
	local kioskSign = newPart(folder, {
		Name = "GarageSign",
		Size = Vector3.new(7, 1.8, 0.3),
		Position = Vector3.new(-30, base + 8, -6.2),
		Color = brand,
	})
	addSign(kioskSign, Enum.NormalId.Back, "VEHICLE SHOP", Color3.new(1, 1, 1))
	local shopPrompt = addPrompt(kiosk, "ShopPrompt", "Open Garage", "Vehicle Shop", 0)

	local post = newPart(folder, {
		Name = "PickupPost",
		Size = Vector3.new(7, 7, 4),
		Position = Vector3.new(30, base + 3.5, -8),
		Color = Color3.fromRGB(38, 48, 74),
	})
	local postSign = newPart(folder, {
		Name = "PickupSign",
		Size = Vector3.new(7, 1.8, 0.3),
		Position = Vector3.new(30, base + 8, -6.2),
		Color = brand,
	})
	addSign(postSign, Enum.NormalId.Back, "GET YOUR VEHICLE", Color3.new(1, 1, 1))
	local spawnPrompt = addPrompt(post, "SpawnPrompt", "Get Vehicle", "Vehicle Pick-up", 0)

	-- Parking bays along the south edge, facing the street so you can drive straight out.
	local spots = {}
	local white = Color3.fromRGB(235, 235, 235)
	for _, x in { -56, -40, -24, -8, 8, 24, 40, 56 } do
		newPart(folder, {
			Name = "BayLine",
			Size = Vector3.new(0.5, 0.1, 18),
			Position = Vector3.new(x, base + 0.03, 44),
			Color = white,
			CanCollide = false,
			CastShadow = false,
		})
	end
	for _, x in { -48, -32, -16, 16, 32, 48 } do
		table.insert(spots, CFrame.lookAt(Vector3.new(x, base, 44), Vector3.new(x, base, 50)))
	end

	-- Flagpole and some cones for a bit of life.
	newPart(folder, {
		Name = "Flagpole",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(30, 0.6, 0.6),
		CFrame = CFrame.new(-56, base + 15, 20) * CFrame.Angles(0, 0, math.pi / 2),
		Color = Color3.fromRGB(200, 200, 205),
		Material = Enum.Material.Metal,
	})
	newPart(folder, {
		Name = "Flag",
		Size = Vector3.new(0.2, 4, 7),
		Position = Vector3.new(-56, base + 27.5, 23.6),
		Color = brand,
		Material = Enum.Material.Fabric,
	})
	for i = 0, 5 do
		newPart(folder, {
			Name = "Cone",
			Size = Vector3.new(1, 1.6, 1),
			Position = Vector3.new(-6 + i * 2.4, base + 0.8, 30),
			Color = Color3.fromRGB(255, 120, 30),
		})
	end

	-- Reuse the place's SpawnLocation so players appear facing the counter.
	local spawn = Workspace:FindFirstChildOfClass("SpawnLocation") or Instance.new("SpawnLocation")
	spawn.Name = "DepotSpawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(12, 1, 12)
	spawn.CFrame = CFrame.new(0, base + 0.5, 14)
	spawn.Color = brand
	spawn.Material = Enum.Material.SmoothPlastic
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Parent = Workspace

	folder.Parent = parent

	local half = CITY.BlockSize / 2
	return {
		Counter = Vector3.new(0, base + 3, -9), -- standing spot in front of the counter
		LoadPrompt = loadPrompt,
		ShopPrompt = shopPrompt,
		SpawnPrompt = spawnPrompt,
		ParkingSpots = spots,
		Bounds = { Min = Vector3.new(-half, -10, -half), Max = Vector3.new(half, 50, half) },
	}
end

-- Entry point --------------------------------------------------------------------------------

function CityBuilder.build(): Registry
	local existing = Workspace:FindFirstChild("City")
	if existing then
		existing:Destroy()
	end
	local city = Instance.new("Folder")
	city.Name = "City"

	-- Turn the default grid baseplate into countryside around the town.
	local baseplate = Workspace:FindFirstChild("Baseplate")
	if baseplate and baseplate:IsA("BasePart") then
		baseplate.Color = Color3.fromRGB(96, 150, 76)
		baseplate.Material = Enum.Material.Grass
		for _, child in baseplate:GetChildren() do
			if child:IsA("Texture") or child:IsA("Decal") then
				child:Destroy()
			end
		end
	end

	buildRoads(city)

	local addresses: { Address } = {}
	local lights: { BasePart } = {}
	local depot
	local middle = (CITY.BlocksPerSide - 1) / 2
	local parks = { [string.format("%d,%d", middle - 2, middle + 2)] = true, [string.format("%d,%d", middle + 2, middle - 2)] = true }

	local blocks = Instance.new("Folder")
	blocks.Name = "Blocks"
	for bx = 0, CITY.BlocksPerSide - 1 do
		for bz = 0, CITY.BlocksPerSide - 1 do
			local ring = math.max(math.abs(bx - middle), math.abs(bz - middle))
			if ring == 0 then
				depot = buildDepot(city)
			elseif parks[bx .. "," .. bz] then
				buildPark(blocks, bx, bz)
			elseif ring == 1 then
				buildDowntownBlock(blocks, bx, bz, addresses)
			else
				buildResidentialBlock(blocks, bx, bz, addresses)
			end

			-- Street lights on two opposite corners of every block.
			local center = blockCenter(bx, bz)
			local corner = CITY.BlockSize / 2 - 2
			for _, dir in { Vector3.new(1, 0, -1), Vector3.new(-1, 0, 1) } do
				local position = Vector3.new(center.X + dir.X * corner, CURB_TOP, center.Z + dir.Z * corner)
				buildStreetLight(blocks, position, position + dir * 10, lights)
			end
		end
	end
	blocks.Parent = city

	-- A ring of trees around the town.
	local outskirts = Instance.new("Folder")
	outskirts.Name = "Outskirts"
	local edge = CITY.Extent + CITY.RoadWidth
	for _ = 1, 90 do
		local angle = rng:NextNumber(0, math.pi * 2)
		local radius = rng:NextNumber(edge + 20, edge + 260)
		local position = Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
		if math.max(math.abs(position.X), math.abs(position.Z)) > edge + 10 then
			buildTree(outskirts, position, rng:NextNumber(1, 1.8))
		end
	end
	outskirts.Parent = city

	for _, address in addresses do
		address.DepotDistance = Config.roadDistance(depot.Counter, address.Position)
	end

	city.Parent = Workspace

	return {
		Addresses = addresses,
		Depot = depot,
		StreetLights = lights,
	}
end

-- Exposed for vehicle spawning: lane centre lines are the same grid the builder used.
CityBuilder.roadLine = roadLine

return CityBuilder
