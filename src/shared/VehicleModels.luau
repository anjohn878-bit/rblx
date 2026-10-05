-- Builds the delivery vehicles out of plain parts. Shared so the server can spawn them and the
-- client can show the same model in the garage preview.
--
-- Local space for every design: origin on the ground under the middle of the vehicle, -Z is
-- forward, +Y is up. The invisible "Chassis" part is the PrimaryPart; its PivotOffset puts the
-- model's pivot back on the ground, so `model:PivotTo(groundCFrame)` parks it correctly.

local Config = require(script.Parent.Config)

local VehicleModels = {}

local PAINT = Config.Colors.Brand
local WHITE = Color3.fromRGB(240, 240, 240)
local DARK = Color3.fromRGB(45, 45, 52)
local BLACK = Color3.fromRGB(25, 25, 28)
local TIRE = Color3.fromRGB(28, 28, 30)
local HUB = Color3.fromRGB(190, 190, 196)
local GLASS = Color3.fromRGB(120, 170, 210)
local HEADLIGHT = Color3.fromRGB(255, 247, 210)
local TAILLIGHT = Color3.fromRGB(230, 40, 40)

type PartSpec = {
	Name: string,
	Size: Vector3,
	CFrame: CFrame,
	Color: Color3,
	Material: Enum.Material?,
	Shape: Enum.PartType?,
	Transparency: number?,
	Label: string?,
	Hidden: boolean?, -- invisible collision helper
}

type Design = {
	ChassisSize: Vector3,
	ChassisY: number,
	SeatSize: Vector3,
	SeatPosition: Vector3,
	Parts: { PartSpec },
}

local function box(name: string, size: Vector3, position: Vector3, color: Color3, material: Enum.Material?): PartSpec
	return { Name = name, Size = size, CFrame = CFrame.new(position), Color = color, Material = material }
end

-- A thin rod running from `a` to `b`.
local function tube(name: string, a: Vector3, b: Vector3, thickness: number, color: Color3): PartSpec
	return {
		Name = name,
		Size = Vector3.new(thickness, thickness, (b - a).Magnitude),
		CFrame = CFrame.lookAt((a + b) / 2, b),
		Color = color,
		Material = Enum.Material.Metal,
	}
end

local function glass(name: string, size: Vector3, position: Vector3): PartSpec
	local spec = box(name, size, position, GLASS, Enum.Material.Glass)
	spec.Transparency = 0.45
	return spec
end

local function neon(name: string, size: Vector3, position: Vector3, color: Color3): PartSpec
	return box(name, size, position, color, Enum.Material.Neon)
end

-- Cylinders point along X, which is exactly the axle direction, so no rotation is needed.
local function addWheel(parts: { PartSpec }, position: Vector3, radius: number, width: number)
	table.insert(parts, {
		Name = "Wheel",
		Size = Vector3.new(width, radius * 2, radius * 2),
		CFrame = CFrame.new(position),
		Color = TIRE,
		Material = Enum.Material.SmoothPlastic,
		Shape = Enum.PartType.Cylinder,
	})
	table.insert(parts, {
		Name = "Hub",
		Size = Vector3.new(width + 0.06, radius, radius),
		CFrame = CFrame.new(position),
		Color = HUB,
		Material = Enum.Material.Metal,
		Shape = Enum.PartType.Cylinder,
	})
end

-- Two-wheelers rest on a pair of invisible side wheels so they never tip over while parked.
local function addOutriggers(parts: { PartSpec }, halfWidth: number, radius: number)
	for _, side in { -1, 1 } do
		table.insert(parts, {
			Name = "Outrigger",
			Size = Vector3.new(0.4, radius * 2, radius * 2),
			CFrame = CFrame.new(side * halfWidth, radius, 0),
			Color = BLACK,
			Shape = Enum.PartType.Cylinder,
			Transparency = 1,
			Hidden = true,
		})
	end
end

local DESIGNS: { [string]: Design } = {}

do -- Delivery Bike
	local parts: { PartSpec } = {}
	addWheel(parts, Vector3.new(0, 1.3, -2.2), 1.3, 0.35)
	addWheel(parts, Vector3.new(0, 1.3, 2.2), 1.3, 0.35)
	local crank = Vector3.new(0, 1.5, 0.2)
	local head = Vector3.new(0, 3.0, -1.8)
	table.insert(parts, tube("TopTube", Vector3.new(0, 3.0, 0.7), head, 0.3, PAINT))
	table.insert(parts, tube("DownTube", crank, head, 0.3, PAINT))
	table.insert(parts, tube("SeatTube", crank, Vector3.new(0, 3.0, 0.7), 0.3, PAINT))
	table.insert(parts, tube("ChainStay", crank, Vector3.new(0, 1.3, 2.2), 0.25, PAINT))
	table.insert(parts, tube("SeatStay", Vector3.new(0, 3.0, 0.7), Vector3.new(0, 1.3, 2.2), 0.25, PAINT))
	table.insert(parts, tube("Fork", Vector3.new(0, 3.4, -1.85), Vector3.new(0, 1.3, -2.2), 0.3, DARK))
	table.insert(parts, tube("Stem", Vector3.new(0, 3.4, -1.85), Vector3.new(0, 3.9, -1.9), 0.25, DARK))
	table.insert(parts, box("Handlebar", Vector3.new(2.2, 0.25, 0.25), Vector3.new(0, 3.9, -1.9), BLACK))
	table.insert(parts, box("Rack", Vector3.new(1.4, 0.2, 2.2), Vector3.new(0, 2.6, 2.3), DARK, Enum.Material.Metal))
	table.insert(parts, box("CargoBox", Vector3.new(2, 1.8, 2), Vector3.new(0, 3.6, 2.4), PAINT))
	table.insert(parts, box("CargoLid", Vector3.new(2.06, 0.3, 2.06), Vector3.new(0, 4.4, 2.4), WHITE))
	table.insert(parts, neon("Headlight", Vector3.new(0.5, 0.5, 0.3), Vector3.new(0, 3.5, -2.1), HEADLIGHT))
	addOutriggers(parts, 1.5, 0.7)
	DESIGNS.Bike = {
		ChassisSize = Vector3.new(1.5, 1, 5),
		ChassisY = 1.6,
		SeatSize = Vector3.new(1, 0.4, 1.4),
		SeatPosition = Vector3.new(0, 3.0, 0.6),
		Parts = parts,
	}
end

do -- City Moped
	local parts: { PartSpec } = {}
	addWheel(parts, Vector3.new(0, 1.1, -2.3), 1.1, 0.55)
	addWheel(parts, Vector3.new(0, 1.1, 2.3), 1.1, 0.55)
	table.insert(parts, box("Floor", Vector3.new(1.4, 0.4, 3.0), Vector3.new(0, 1.3, 0.2), WHITE))
	table.insert(parts, box("Cowl", Vector3.new(1.6, 1.4, 2.2), Vector3.new(0, 2.1, 1.6), PAINT))
	table.insert(parts, box("LegShield", Vector3.new(1.4, 2.4, 0.4), Vector3.new(0, 2.3, -1.4), PAINT))
	table.insert(parts, tube("Fork", Vector3.new(0, 3.6, -1.7), Vector3.new(0, 1.1, -2.3), 0.35, DARK))
	table.insert(parts, box("Handlebar", Vector3.new(2.2, 0.3, 0.3), Vector3.new(0, 3.7, -1.7), BLACK))
	table.insert(parts, neon("Headlight", Vector3.new(0.8, 0.6, 0.3), Vector3.new(0, 3.35, -1.95), HEADLIGHT))
	table.insert(parts, box("Rack", Vector3.new(1.6, 0.2, 2.2), Vector3.new(0, 3.1, 3.2), DARK, Enum.Material.Metal))
	table.insert(parts, box("CargoBox", Vector3.new(2.2, 2, 2.2), Vector3.new(0, 4.2, 3.2), PAINT))
	table.insert(parts, box("CargoLid", Vector3.new(2.26, 0.3, 2.26), Vector3.new(0, 5.1, 3.2), WHITE))
	table.insert(parts, neon("Taillight", Vector3.new(0.8, 0.3, 0.2), Vector3.new(0, 2.4, 2.75), TAILLIGHT))
	addOutriggers(parts, 1.5, 0.7)
	DESIGNS.Moped = {
		ChassisSize = Vector3.new(1.5, 1, 5),
		ChassisY = 1.5,
		SeatSize = Vector3.new(1.3, 0.5, 2),
		SeatPosition = Vector3.new(0, 3.05, 1.0),
		Parts = parts,
	}
end

do -- Compact Car
	local parts: { PartSpec } = {}
	for _, x in { -2.7, 2.7 } do
		for _, z in { -3.6, 3.6 } do
			addWheel(parts, Vector3.new(x, 1.25, z), 1.25, 0.8)
		end
	end
	table.insert(parts, box("Body", Vector3.new(6, 1.8, 11), Vector3.new(0, 2.0, 0), PAINT))
	table.insert(parts, box("Stripe", Vector3.new(6.06, 0.4, 9), Vector3.new(0, 2.4, 0), WHITE))
	table.insert(parts, glass("Cabin", Vector3.new(5.6, 3.0, 5.6), Vector3.new(0, 4.4, 0.6)))
	table.insert(parts, box("Roof", Vector3.new(5.8, 0.4, 5.8), Vector3.new(0, 6.1, 0.6), WHITE))
	table.insert(parts, box("FrontBumper", Vector3.new(6.2, 0.7, 0.6), Vector3.new(0, 1.4, -5.6), DARK))
	table.insert(parts, box("RearBumper", Vector3.new(6.2, 0.7, 0.6), Vector3.new(0, 1.4, 5.6), DARK))
	for _, x in { -2.0, 2.0 } do
		table.insert(parts, neon("Headlight", Vector3.new(1.2, 0.5, 0.2), Vector3.new(x, 2.4, -5.55), HEADLIGHT))
		table.insert(parts, neon("Taillight", Vector3.new(1.2, 0.5, 0.2), Vector3.new(x, 2.4, 5.55), TAILLIGHT))
	end
	DESIGNS.Hatchback = {
		ChassisSize = Vector3.new(5, 1, 10),
		ChassisY = 1.6,
		SeatSize = Vector3.new(2, 0.4, 2),
		SeatPosition = Vector3.new(-1.3, 2.0, 0.8),
		Parts = parts,
	}
end

do -- Delivery Van
	local parts: { PartSpec } = {}
	for _, x in { -2.9, 2.9 } do
		for _, z in { -4.8, 4.6 } do
			addWheel(parts, Vector3.new(x, 1.4, z), 1.4, 0.9)
		end
	end
	table.insert(parts, box("Body", Vector3.new(6.6, 6.0, 11), Vector3.new(0, 4.3, 1.8), WHITE))
	table.insert(parts, box("Nose", Vector3.new(6.6, 3.6, 3.6), Vector3.new(0, 3.1, -5.5), WHITE))
	table.insert(parts, glass("Windshield", Vector3.new(6.2, 2.3, 0.3), Vector3.new(0, 6.1, -3.85)))
	table.insert(parts, glass("SideWindows", Vector3.new(6.66, 1.8, 2.6), Vector3.new(0, 6.0, -2.3)))
	local stripe = box("Stripe", Vector3.new(6.66, 1.6, 9.6), Vector3.new(0, 3.8, 2.3), PAINT)
	stripe.Label = string.upper(Config.CompanyName)
	table.insert(parts, stripe)
	table.insert(parts, box("NoseStripe", Vector3.new(6.66, 0.6, 3.6), Vector3.new(0, 3.8, -5.5), PAINT))
	table.insert(parts, box("RearDoorSeam", Vector3.new(0.15, 5.4, 0.1), Vector3.new(0, 4.3, 7.32), DARK))
	table.insert(parts, box("FrontBumper", Vector3.new(6.8, 0.8, 0.6), Vector3.new(0, 1.6, -7.5), DARK))
	table.insert(parts, box("RearBumper", Vector3.new(6.8, 0.8, 0.5), Vector3.new(0, 1.6, 7.45), DARK))
	for _, x in { -2.4, 2.4 } do
		table.insert(parts, neon("Headlight", Vector3.new(1.2, 0.6, 0.2), Vector3.new(x, 3.6, -7.35), HEADLIGHT))
	end
	for _, x in { -2.9, 2.9 } do
		table.insert(parts, neon("Taillight", Vector3.new(0.6, 1.2, 0.2), Vector3.new(x, 3.0, 7.35), TAILLIGHT))
	end
	DESIGNS.Van = {
		ChassisSize = Vector3.new(5.5, 1, 13),
		ChassisY = 1.8,
		SeatSize = Vector3.new(2, 0.4, 2),
		SeatPosition = Vector3.new(-1.5, 2.6, -2.8),
		Parts = parts,
	}
end

do -- Box Truck
	local parts: { PartSpec } = {}
	for _, x in { -3.1, 3.1 } do
		for _, z in { -6.5, 4.6, 7.8 } do
			addWheel(parts, Vector3.new(x, 1.6, z), 1.6, 1.0)
		end
	end
	table.insert(parts, box("Frame", Vector3.new(6, 0.8, 19), Vector3.new(0, 1.9, 0.3), DARK))
	table.insert(parts, box("Cab", Vector3.new(7, 6.4, 5.5), Vector3.new(0, 4.8, -6.6), PAINT))
	table.insert(parts, glass("Windshield", Vector3.new(6.4, 2.4, 0.3), Vector3.new(0, 6.4, -9.4)))
	table.insert(parts, glass("SideWindows", Vector3.new(7.06, 2.2, 2.6), Vector3.new(0, 6.4, -7.0)))
	table.insert(parts, box("CargoBox", Vector3.new(7.4, 9, 13.5), Vector3.new(0, 6.8, 3.25), WHITE))
	local stripe = box("Stripe", Vector3.new(7.46, 1.6, 13.5), Vector3.new(0, 4.2, 3.25), PAINT)
	stripe.Label = string.upper(Config.CompanyName)
	table.insert(parts, stripe)
	table.insert(parts, box("FrontBumper", Vector3.new(7.4, 1, 0.6), Vector3.new(0, 2.0, -9.6), DARK))
	for _, x in { -2.6, 2.6 } do
		table.insert(parts, neon("Headlight", Vector3.new(1.2, 0.7, 0.2), Vector3.new(x, 3.4, -9.4), HEADLIGHT))
	end
	for _, x in { -3.2, 3.2 } do
		table.insert(parts, neon("Taillight", Vector3.new(0.6, 1.2, 0.2), Vector3.new(x, 3.2, 10.05), TAILLIGHT))
	end
	DESIGNS.Truck = {
		ChassisSize = Vector3.new(6, 1, 18),
		ChassisY = 2.0,
		SeatSize = Vector3.new(2, 0.4, 2),
		SeatPosition = Vector3.new(-1.6, 3.4, -6.4),
		Parts = parts,
	}
end

do -- Express Supercar
	local parts: { PartSpec } = {}
	for _, x in { -2.9, 2.9 } do
		for _, z in { -4.3, 4.1 } do
			addWheel(parts, Vector3.new(x, 1.2, z), 1.2, 1.0)
		end
	end
	table.insert(parts, box("Body", Vector3.new(6.4, 1.4, 13), Vector3.new(0, 1.6, 0), PAINT))
	table.insert(parts, box("Splitter", Vector3.new(6.6, 0.3, 1), Vector3.new(0, 1.0, -6.6), BLACK))
	table.insert(parts, box("SidePods", Vector3.new(6.6, 0.9, 6), Vector3.new(0, 2.6, 1.0), PAINT))
	local cockpit = glass("Cockpit", Vector3.new(5.2, 2.0, 4.6), Vector3.new(0, 3.8, 0.2))
	cockpit.Color = Color3.fromRGB(40, 50, 70)
	cockpit.Transparency = 0.3
	table.insert(parts, cockpit)
	table.insert(parts, box("Roof", Vector3.new(5.0, 0.3, 3.2), Vector3.new(0, 4.95, 0.4), BLACK))
	for _, x in { -0.7, 0.7 } do
		table.insert(parts, box("RacingStripe", Vector3.new(0.6, 1.46, 13.06), Vector3.new(x, 1.6, 0), WHITE))
	end
	table.insert(parts, box("Wing", Vector3.new(6.4, 0.25, 1.4), Vector3.new(0, 3.9, 6.0), BLACK))
	for _, x in { -2, 2 } do
		table.insert(parts, box("WingStrut", Vector3.new(0.3, 1.4, 0.4), Vector3.new(x, 3.1, 6.0), BLACK))
	end
	for _, x in { -2.2, 2.2 } do
		table.insert(parts, neon("Headlight", Vector3.new(1.4, 0.3, 0.2), Vector3.new(x, 1.9, -6.52), HEADLIGHT))
		table.insert(parts, neon("Taillight", Vector3.new(1.6, 0.3, 0.2), Vector3.new(x, 2.0, 6.52), TAILLIGHT))
	end
	DESIGNS.Supercar = {
		ChassisSize = Vector3.new(5.5, 1, 12),
		ChassisY = 1.4,
		SeatSize = Vector3.new(2, 0.4, 2),
		SeatPosition = Vector3.new(-1.2, 1.0, 0.5),
		Parts = parts,
	}
end

local function addLabel(part: BasePart, text: string)
	for _, face in { Enum.NormalId.Left, Enum.NormalId.Right } do
		local gui = Instance.new("SurfaceGui")
		gui.Face = face
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 40
		gui.LightInfluence = 0.5
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(1, 1)
		label.Font = Enum.Font.FredokaOne
		label.TextScaled = true
		label.TextColor3 = WHITE
		label.Text = text
		label.Parent = gui
		gui.Parent = part
	end
end

function VehicleModels.has(id: string): boolean
	return DESIGNS[id] ~= nil
end

-- Returns an anchored model in local space. The server welds and unanchors it when spawning.
function VehicleModels.build(id: string): Model
	local design = DESIGNS[id]
	assert(design, "Unknown vehicle design " .. tostring(id))

	local model = Instance.new("Model")
	model.Name = id

	local chassis = Instance.new("Part")
	chassis.Name = "Chassis"
	chassis.Size = design.ChassisSize
	chassis.CFrame = CFrame.new(0, design.ChassisY, 0)
	chassis.PivotOffset = CFrame.new(0, -design.ChassisY, 0)
	chassis.Transparency = 1
	chassis.CanCollide = false
	chassis.CanTouch = false
	chassis.CanQuery = false
	chassis.Anchored = true
	chassis.Parent = model
	model.PrimaryPart = chassis

	local seat = Instance.new("VehicleSeat")
	seat.Name = "DriverSeat"
	seat.Size = design.SeatSize
	seat.CFrame = CFrame.new(design.SeatPosition)
	seat.Color = BLACK
	seat.Material = Enum.Material.Fabric
	seat.TopSurface = Enum.SurfaceType.Smooth
	seat.BottomSurface = Enum.SurfaceType.Smooth
	seat.CanCollide = false
	seat.HeadsUpDisplay = false
	seat.Anchored = true
	seat.Parent = model

	for _, spec in design.Parts do
		local part = Instance.new("Part")
		part.Name = spec.Name
		part.Size = spec.Size
		part.CFrame = spec.CFrame
		part.Color = spec.Color
		part.Material = spec.Material or Enum.Material.SmoothPlastic
		part.Shape = spec.Shape or Enum.PartType.Block
		part.Transparency = spec.Transparency or 0
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		part.CastShadow = not spec.Hidden
		part.Anchored = true
		if spec.Label then
			addLabel(part, spec.Label)
		end
		part.Parent = model
	end

	return model
end

return VehicleModels
