-- Builds a simple drivable car from parts + a VehicleSeat.
local Config = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Config"))

local CarSpawner = {}

local function weld(a: BasePart, b: BasePart)
	local w = Instance.new("WeldConstraint")
	w.Part0, w.Part1 = a, b
	w.Parent = a
end

function CarSpawner.spawn(carId: string, cframe: CFrame, owner: Player)
	local def
	for _, c in Config.Cars do
		if c.id == carId then
			def = c
		end
	end
	def = def or Config.Cars[1]

	local model = Instance.new("Model")
	model.Name = owner.Name .. "_Car"

	local seat = Instance.new("VehicleSeat")
	seat.Size = Vector3.new(6, 1.2, 12)
	seat.MaxSpeed = def.speed
	seat.Torque = def.torque * 1000
	seat.TurnSpeed = 1.5
	seat.HeadsUpDisplay = false
	seat.Color = def.color
	seat.CFrame = cframe
	seat.Parent = model
	model.PrimaryPart = seat

	local top = Instance.new("Part")
	top.Name = "Cabin"
	top.Size = Vector3.new(5.6, 3, 6)
	top.Color = def.color
	top.Material = Enum.Material.SmoothPlastic
	top.CFrame = cframe * CFrame.new(0, 2.1, 1.5)
	top.Parent = model
	weld(seat, top)

	local glass = Instance.new("Part")
	glass.Name = "Windshield"
	glass.Size = Vector3.new(5.2, 2, 0.4)
	glass.Color = Color3.fromRGB(150, 200, 255)
	glass.Transparency = 0.4
	glass.CFrame = cframe * CFrame.new(0, 2.3, -1.6)
	glass.CanCollide = false
	glass.Parent = model
	weld(seat, glass)

	-- wheels (slippery cylinders, don't collide with ground much: seat does the driving)
	for _, off in { Vector3.new(-3.2, -0.6, -4), Vector3.new(3.2, -0.6, -4), Vector3.new(-3.2, -0.6, 4), Vector3.new(3.2, -0.6, 4) } do
		local wheel = Instance.new("Part")
		wheel.Name = "Wheel"
		wheel.Shape = Enum.PartType.Cylinder
		wheel.Size = Vector3.new(1.2, 3, 3)
		wheel.Color = Color3.fromRGB(25, 25, 25)
		wheel.CustomPhysicalProperties = PhysicalProperties.new(0.5, 0.05, 0, 1, 1)
		wheel.CFrame = cframe * CFrame.new(off) * CFrame.Angles(0, 0, math.rad(90))
		wheel.Parent = model
		weld(seat, wheel)
	end

	model:SetAttribute("Owner", owner.UserId)
	model.Parent = workspace
	pcall(function()
		seat:SetNetworkOwner(owner)
	end)
	return model, seat
end

return CarSpawner
