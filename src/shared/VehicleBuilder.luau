--[[
	Builds vehicle models out of plain Parts (no asset ids needed).

	Used by the server to spawn drivable vehicles and by the garage UI to render previews.

	Layout of a built model (local space, chassis at the origin, front of the car points -Z):

	  Chassis      invisible collision hull; PrimaryPart. The only part that collides with the world.
	  Seat         VehicleSeat the driver sits in. Throttle/steer input is read from it.
	  Wheel_xx     cosmetic wheels joined to the chassis by Motor6Ds; clients spin them via Transform.
	  (everything else) cosmetic body panels, welded to the chassis, massless, non-colliding.

	Model attributes: VehicleId, MaxSpeed, Accel, Turn, Grip, WheelRadius, HullHalfHeight.
	HullHalfHeight is how far the chassis centre must sit above the ground.
]]

local Config = require(script.Parent.Config)

local VehicleBuilder = {}

-- Palette -------------------------------------------------------------------
local TYRE = Color3.fromRGB(28, 28, 32)
local SILVER = Color3.fromRGB(200, 204, 212)
local DARK = Color3.fromRGB(40, 42, 50)
local GLASS = Color3.fromRGB(150, 205, 235)
local ORANGE = Color3.fromRGB(255, 159, 28)
local HEADLIGHT = Color3.fromRGB(255, 244, 190)
local TAILLIGHT = Color3.fromRGB(255, 60, 60)

-- Designs -------------------------------------------------------------------
-- All heights ("G" suffix) are measured up from the ground.
local DESIGNS = {
	Hatchback = {
		Kind = "car",
		Width = 7,
		Length = 13,
		WheelRadius = 1.3,
		WheelWidth = 1.0,
		FloorG = 1.0,
		WaistH = 1.8,
		HoodLen = 4.5,
		RearLen = 3.2,
		Roof = true,
		Sign = "roof",
		BodyColor = Color3.fromRGB(222, 62, 62),
		AccentColor = Color3.fromRGB(245, 245, 248),
	},
	Van = {
		Kind = "car",
		Width = 8,
		Length = 16,
		WheelRadius = 1.5,
		WheelWidth = 1.1,
		FloorG = 1.2,
		WaistH = 2.0,
		HoodLen = 3.0,
		RearLen = 8.0,
		CargoHeight = 6.2,
		Roof = true,
		Sign = "roof",
		BodyColor = Color3.fromRGB(240, 242, 247),
		AccentColor = ORANGE,
	},
	Roadster = {
		Kind = "car",
		Width = 7.4,
		Length = 14.2,
		WheelRadius = 1.2,
		WheelWidth = 1.1,
		FloorG = 0.7,
		WaistH = 1.6,
		HoodLen = 5.5,
		RearLen = 2.8,
		Roof = false,
		Spoiler = true,
		Sign = "box",
		BodyColor = Color3.fromRGB(255, 196, 0),
		AccentColor = Color3.fromRGB(30, 30, 36),
	},
	Hyper = {
		Kind = "car",
		Width = 8,
		Length = 15.5,
		WheelRadius = 1.25,
		WheelWidth = 1.3,
		FloorG = 0.55,
		WaistH = 1.4,
		HoodLen = 6.2,
		RearLen = 3.0,
		Roof = false,
		Spoiler = true,
		Underglow = Color3.fromRGB(0, 230, 255),
		Sign = "box",
		BodyColor = Color3.fromRGB(26, 26, 34),
		AccentColor = Color3.fromRGB(0, 230, 255),
	},
	Scooter = {
		Kind = "scooter",
		BodyColor = ORANGE,
		AccentColor = Color3.fromRGB(245, 245, 248),
	},
}

-- Helpers -------------------------------------------------------------------

type Ctx = { Model: Model, Chassis: Part, HalfHeight: number }

local function newPart(ctx: Ctx, name: string, size: Vector3, position: Vector3, color: Color3, material: Enum.Material?): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = CFrame.new(position)
	part.Color = color
	part.Material = material or Enum.Material.SmoothPlastic
	part.Anchored = false
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.Massless = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = ctx.Model

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = ctx.Chassis
	weld.Part1 = part
	weld.Parent = part
	return part
end

local function addText(part: Part, face: Enum.NormalId, text: string, textColor: Color3, backColor: Color3?)
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0
	gui.Parent = part

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = backColor and 0 or 1
	if backColor then
		label.BackgroundColor3 = backColor
	end
	label.Text = text
	label.TextColor3 = textColor
	label.TextScaled = true
	label.FontFace = Font.fromEnum(Enum.Font.GothamBold) -- FontFace (not Font) so the label can be saved into the place file
	label.Parent = gui
end

local function addWheel(ctx: Ctx, name: string, offset: Vector3, radius: number, width: number, front: boolean)
	local wheel = Instance.new("Part")
	wheel.Name = name
	wheel.Shape = Enum.PartType.Cylinder -- cylinder axis runs along X, which is the axle direction
	wheel.Size = Vector3.new(width, radius * 2, radius * 2)
	wheel.CFrame = CFrame.new(offset)
	wheel.Color = TYRE
	wheel.Material = Enum.Material.SmoothPlastic
	wheel.Anchored = false
	wheel.CanCollide = false
	wheel.CanTouch = false
	wheel.CanQuery = false
	wheel.Massless = true
	wheel.Parent = ctx.Model

	-- Two silver spokes so you can actually see the wheel turning.
	for i, spokeSize in
		{
			Vector3.new(width + 0.12, 0.45, radius * 1.5),
			Vector3.new(width + 0.12, radius * 1.5, 0.45),
		}
	do
		local spoke = Instance.new("Part")
		spoke.Name = "Spoke" .. i
		spoke.Size = spokeSize
		spoke.CFrame = CFrame.new(offset)
		spoke.Color = SILVER
		spoke.Material = Enum.Material.Metal
		spoke.Anchored = false
		spoke.CanCollide = false
		spoke.CanTouch = false
		spoke.CanQuery = false
		spoke.Massless = true
		spoke.Parent = ctx.Model
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = wheel
		weld.Part1 = spoke
		weld.Parent = spoke
	end

	local motor = Instance.new("Motor6D")
	motor.Name = name
	motor.Part0 = ctx.Chassis
	motor.Part1 = wheel
	motor.C0 = CFrame.new(offset)
	motor.C1 = CFrame.new()
	motor:SetAttribute("Front", front)
	motor:SetAttribute("Radius", radius)
	motor.Parent = ctx.Chassis
end

local function newModel(spec, hullSize: Vector3): (Ctx, Model)
	local model = Instance.new("Model")
	model.Name = spec.Id

	local chassis = Instance.new("Part")
	chassis.Name = "Chassis"
	chassis.Size = hullSize
	chassis.CFrame = CFrame.new()
	chassis.Transparency = 1
	chassis.CanCollide = true
	chassis.CanQuery = false
	chassis.Anchored = false
	chassis.TopSurface = Enum.SurfaceType.Smooth
	chassis.BottomSurface = Enum.SurfaceType.Smooth
	-- Slippery so the arcade controller, not friction, decides how the car moves.
	chassis.CustomPhysicalProperties = PhysicalProperties.new(2.5, 0, 0, 100, 100)
	chassis.Parent = model
	model.PrimaryPart = chassis

	model:SetAttribute("VehicleId", spec.Id)
	model:SetAttribute("MaxSpeed", spec.MaxSpeed)
	model:SetAttribute("Accel", spec.Accel)
	model:SetAttribute("Turn", spec.Turn)
	model:SetAttribute("Grip", spec.Grip)
	model:SetAttribute("HullHalfHeight", hullSize.Y / 2)

	return { Model = model, Chassis = chassis, HalfHeight = hullSize.Y / 2 }, model
end

local function newSeat(ctx: Ctx, size: Vector3, position: Vector3): VehicleSeat
	local seat = Instance.new("VehicleSeat")
	seat.Name = "Seat"
	seat.Size = size
	seat.CFrame = CFrame.new(position)
	seat.Color = DARK
	seat.Material = Enum.Material.Fabric
	seat.Anchored = false
	seat.CanCollide = false
	seat.CanQuery = false
	seat.Massless = true
	seat.HeadsUpDisplay = false
	seat.MaxSpeed = 0 -- we drive the car ourselves; the built-in wheel motor logic is unused
	seat.TopSurface = Enum.SurfaceType.Smooth
	seat.BottomSurface = Enum.SurfaceType.Smooth
	seat.Parent = ctx.Model

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = ctx.Chassis
	weld.Part1 = seat
	weld.Parent = seat
	return seat
end

-- Car -----------------------------------------------------------------------

local function buildCar(spec, d)
	local width, length, wr = d.Width, d.Length, d.WheelRadius
	-- Collision hull: roughly wheel height, but always below the floor so the rider never sits inside it.
	local hullHeight = math.min(wr * 1.3, d.FloorG + 0.45)
	local ctx, model = newModel(spec, Vector3.new(width * 0.95, hullHeight, length * 0.97))
	local hh = ctx.HalfHeight

	-- Convert "height above ground" into chassis-local Y.
	local function Y(g: number): number
		return g - hh
	end

	local frontZ, rearZ = -length / 2, length / 2
	local floorTopG = d.FloorG + 0.5
	local seatTopG = floorTopG + 0.25
	local waistTopG = floorTopG + d.WaistH
	local cabinFrontZ = frontZ + d.HoodLen
	local cabinRearZ = rearZ - d.RearLen
	local cabinLen = cabinRearZ - cabinFrontZ
	local body, accent = d.BodyColor, d.AccentColor

	-- Floor, hood, and the block behind the cabin.
	newPart(ctx, "Floor", Vector3.new(width * 0.96, 0.5, length), Vector3.new(0, Y(d.FloorG + 0.25), 0), DARK)
	newPart(ctx, "Hood", Vector3.new(width, d.WaistH, d.HoodLen), Vector3.new(0, Y(floorTopG + d.WaistH / 2), frontZ + d.HoodLen / 2), body)
	newPart(ctx, "HoodStripe", Vector3.new(width * 0.3, 0.1, d.HoodLen * 0.98), Vector3.new(0, Y(waistTopG + 0.05), frontZ + d.HoodLen / 2), accent)

	local cargoHeight = d.CargoHeight
	if cargoHeight then
		newPart(ctx, "CargoBox", Vector3.new(width, cargoHeight, d.RearLen), Vector3.new(0, Y(floorTopG + cargoHeight / 2), rearZ - d.RearLen / 2), body)
		-- Orange stripe + branding on both sides and the back door.
		for _, sx in { -1, 1 } do
			local stripe = newPart(
				ctx,
				"CargoStripe",
				Vector3.new(0.12, 1.1, d.RearLen * 0.96),
				Vector3.new(sx * (width / 2 + 0.05), Y(floorTopG + cargoHeight * 0.45), rearZ - d.RearLen / 2),
				accent
			)
			addText(stripe, sx > 0 and Enum.NormalId.Right or Enum.NormalId.Left, "SWIFT DROP", Color3.new(1, 1, 1))
		end
		newPart(ctx, "CargoRearStripe", Vector3.new(width * 0.9, 1.1, 0.12), Vector3.new(0, Y(floorTopG + cargoHeight * 0.45), rearZ + 0.05), accent)
		newPart(
			ctx,
			"CargoRoofTrim",
			Vector3.new(width + 0.2, 0.3, d.RearLen + 0.2),
			Vector3.new(0, Y(floorTopG + cargoHeight + 0.1), rearZ - d.RearLen / 2),
			accent
		)
	else
		newPart(ctx, "Trunk", Vector3.new(width, d.WaistH, d.RearLen), Vector3.new(0, Y(floorTopG + d.WaistH / 2), rearZ - d.RearLen / 2), body)
	end

	-- Door panels either side of the driver.
	for _, sx in { -1, 1 } do
		newPart(
			ctx,
			"Door",
			Vector3.new(0.5, d.WaistH, cabinLen),
			Vector3.new(sx * (width / 2 - 0.25), Y(floorTopG + d.WaistH / 2), cabinFrontZ + cabinLen / 2),
			body
		)
		newPart(ctx, "DoorTrim", Vector3.new(0.55, 0.2, cabinLen), Vector3.new(sx * (width / 2 - 0.25), Y(waistTopG - 0.1), cabinFrontZ + cabinLen / 2), accent)
	end

	-- Driver seat (+ backrest).
	local seatZ = cabinFrontZ + cabinLen * 0.55
	newSeat(ctx, Vector3.new(2.6, 0.5, 2.4), Vector3.new(0, Y(seatTopG - 0.25), seatZ))
	newPart(ctx, "Backrest", Vector3.new(2.6, 2.2, 0.4), Vector3.new(0, Y(seatTopG + 1.1), seatZ + 1.4), DARK, Enum.Material.Fabric)

	-- Windscreen.
	local roofUnderG = seatTopG + 4.3
	local glassHeight = d.Roof and (roofUnderG - waistTopG) or 2.2
	local windscreen = newPart(
		ctx,
		"Windscreen",
		Vector3.new(width - 0.8, glassHeight, 0.25),
		Vector3.new(0, Y(waistTopG + glassHeight / 2), cabinFrontZ),
		GLASS,
		Enum.Material.Glass
	)
	windscreen.Transparency = 0.55

	if d.Roof then
		local roofLen = cabinLen + 0.8
		newPart(ctx, "Roof", Vector3.new(width - 0.2, 0.4, roofLen), Vector3.new(0, Y(roofUnderG + 0.2), cabinFrontZ + cabinLen / 2 + 0.2), body)
		local pillarHeight = roofUnderG - waistTopG
		for _, sx in { -1, 1 } do
			for _, pz in { cabinFrontZ + 0.2, cabinRearZ - 0.2 } do
				newPart(ctx, "Pillar", Vector3.new(0.45, pillarHeight, 0.45), Vector3.new(sx * (width / 2 - 0.4), Y(waistTopG + pillarHeight / 2), pz), accent)
			end
		end
		if d.Sign == "roof" then
			local sign = newPart(
				ctx,
				"RoofSign",
				Vector3.new(3.8, 1, 1.4),
				Vector3.new(0, Y(roofUnderG + 0.4 + 0.5), cabinFrontZ + cabinLen / 2),
				ORANGE,
				Enum.Material.Neon
			)
			addText(sign, Enum.NormalId.Front, "DELIVERY", Color3.fromRGB(30, 30, 36))
			addText(sign, Enum.NormalId.Back, "DELIVERY", Color3.fromRGB(30, 30, 36))
		end
	elseif d.Sign == "box" then
		local boxHeight = 1.7
		local box = newPart(
			ctx,
			"DeliveryBox",
			Vector3.new(3.6, boxHeight, math.min(2.4, d.RearLen - 0.4)),
			Vector3.new(0, Y(waistTopG + boxHeight / 2), rearZ - d.RearLen / 2),
			ORANGE
		)
		addText(box, Enum.NormalId.Back, "DELIVERY", Color3.fromRGB(30, 30, 36))
	end

	if d.Spoiler then
		local wingG = waistTopG + 1.9
		newPart(ctx, "Wing", Vector3.new(width - 0.6, 0.3, 1.8), Vector3.new(0, Y(wingG), rearZ - 0.4), accent)
		for _, sx in { -1, 1 } do
			newPart(
				ctx,
				"WingStrut",
				Vector3.new(0.4, wingG - waistTopG, 0.4),
				Vector3.new(sx * (width / 2 - 1.3), Y(waistTopG + (wingG - waistTopG) / 2), rearZ - 0.4),
				accent
			)
		end
	end

	if d.Underglow then
		for _, sx in { -1, 1 } do
			newPart(
				ctx,
				"Underglow",
				Vector3.new(0.25, 0.2, length * 0.55),
				Vector3.new(sx * (width / 2 + 0.05), Y(d.FloorG - 0.1), 0),
				d.Underglow,
				Enum.Material.Neon
			)
		end
	end

	-- Bumpers and lights.
	newPart(ctx, "FrontBumper", Vector3.new(width + 0.2, 0.7, 0.5), Vector3.new(0, Y(d.FloorG + 0.45), frontZ - 0.2), DARK)
	newPart(ctx, "RearBumper", Vector3.new(width + 0.2, 0.7, 0.5), Vector3.new(0, Y(d.FloorG + 0.45), rearZ + 0.2), DARK)
	for _, sx in { -1, 1 } do
		newPart(
			ctx,
			"Headlight",
			Vector3.new(1.5, 0.8, 0.3),
			Vector3.new(sx * (width / 2 - 1.6), Y(floorTopG + d.WaistH * 0.55), frontZ - 0.1),
			HEADLIGHT,
			Enum.Material.Neon
		)
		newPart(
			ctx,
			"Taillight",
			Vector3.new(1.2, 0.6, 0.3),
			Vector3.new(sx * (width / 2 - 1.2), Y(floorTopG + d.WaistH * 0.55), rearZ + 0.1),
			TAILLIGHT,
			Enum.Material.Neon
		)
	end

	-- Wheels.
	local wheelG = wr + 0.02
	local wheelX = width / 2 + 0.1
	local frontWheelZ, rearWheelZ = frontZ + 2.8, rearZ - 2.8
	addWheel(ctx, "Wheel_FL", Vector3.new(-wheelX, Y(wheelG), frontWheelZ), wr, d.WheelWidth, true)
	addWheel(ctx, "Wheel_FR", Vector3.new(wheelX, Y(wheelG), frontWheelZ), wr, d.WheelWidth, true)
	addWheel(ctx, "Wheel_RL", Vector3.new(-wheelX, Y(wheelG), rearWheelZ), wr, d.WheelWidth, false)
	addWheel(ctx, "Wheel_RR", Vector3.new(wheelX, Y(wheelG), rearWheelZ), wr, d.WheelWidth, false)

	model:SetAttribute("WheelRadius", wr)
	return model
end

-- Scooter -------------------------------------------------------------------

local function buildScooter(spec, d)
	local wr = 1.0
	local ctx, model = newModel(spec, Vector3.new(2.2, 1.0, 7.4))
	local hh = ctx.HalfHeight
	local function Y(g: number): number
		return g - hh
	end

	local body, accent = d.BodyColor, d.AccentColor

	-- Deck, fork, handlebar, light.
	newPart(ctx, "Deck", Vector3.new(2.2, 0.5, 6.0), Vector3.new(0, Y(1.15), 0), body)
	newPart(ctx, "DeckStripe", Vector3.new(0.5, 0.06, 5.8), Vector3.new(0, Y(1.43), 0), accent)
	newPart(ctx, "Column", Vector3.new(0.5, 3.6, 0.5), Vector3.new(0, Y(3.0), -2.8), DARK, Enum.Material.Metal)
	newPart(ctx, "Handlebar", Vector3.new(3.2, 0.4, 0.5), Vector3.new(0, Y(4.8), -2.7), DARK, Enum.Material.Metal)
	newPart(ctx, "Headlight", Vector3.new(0.9, 0.7, 0.3), Vector3.new(0, Y(4.0), -3.1), HEADLIGHT, Enum.Material.Neon)
	newPart(ctx, "FrontFender", Vector3.new(1.0, 0.2, 2.2), Vector3.new(0, Y(2.35), -3.4), body)

	-- Rider seat and the delivery box behind it.
	newSeat(ctx, Vector3.new(2.2, 0.4, 2.0), Vector3.new(0, Y(1.6), -0.4))
	local box = newPart(ctx, "DeliveryBox", Vector3.new(2.8, 2.6, 2.4), Vector3.new(0, Y(2.7), 2.2), ORANGE)
	addText(box, Enum.NormalId.Back, "DELIVERY", Color3.fromRGB(30, 30, 36))
	newPart(ctx, "BoxLid", Vector3.new(3.0, 0.25, 2.6), Vector3.new(0, Y(4.1), 2.2), accent)
	newPart(ctx, "Taillight", Vector3.new(1.0, 0.5, 0.3), Vector3.new(0, Y(1.9), 3.5), TAILLIGHT, Enum.Material.Neon)

	addWheel(ctx, "Wheel_F", Vector3.new(0, Y(wr + 0.02), -3.4), wr, 0.7, true)
	addWheel(ctx, "Wheel_R", Vector3.new(0, Y(wr + 0.02), 3.4), wr, 0.7, false)

	model:SetAttribute("WheelRadius", wr)
	return model
end

-- Public API ------------------------------------------------------------------

function VehicleBuilder.build(vehicleId: string): Model
	local spec = Config.VehicleById[vehicleId]
	local design = DESIGNS[vehicleId]
	assert(spec and design, "Unknown vehicle id: " .. tostring(vehicleId))
	if design.Kind == "scooter" then
		return buildScooter(spec, design)
	end
	return buildCar(spec, design)
end

-- Every vehicle in Config must have a design (and vice versa); checked by the tests.
function VehicleBuilder.hasDesign(vehicleId: string): boolean
	return DESIGNS[vehicleId] ~= nil
end

return VehicleBuilder
