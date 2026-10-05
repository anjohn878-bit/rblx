--[[
	Cosmetic wheel animation for every delivery vehicle in the world (yours and other players').

	Wheels are joined to the chassis with Motor6Ds; setting Motor6D.Transform on this client spins
	and steers them without touching physics or replicating anything. Rolling speed comes from the
	chassis velocity, so it works for vehicles driven by other players too.
]]

local CollectionService = game:GetService("CollectionService")

local UIKit = require(script.Parent.UIKit)

local VehicleVisuals = {}

local MAX_WHEEL_STEER = 0.45 -- radians
local TAU = math.pi * 2
local TAG = "DeliveryVehicle"

local tracked = {} -- [Model] = { Chassis, Seat, Wheels = { { Motor, Front, Radius, Angle } } }

local function track(model: Model)
	if tracked[model] then
		return
	end
	local chassis = model:WaitForChild("Chassis", 10)
	local seat = model:WaitForChild("Seat", 10)
	if not chassis or not seat or not model.Parent then
		return
	end

	local wheels = {}
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("Motor6D") and descendant:GetAttribute("Radius") then
			table.insert(wheels, {
				Motor = descendant,
				Front = descendant:GetAttribute("Front") == true,
				Radius = descendant:GetAttribute("Radius"),
				Angle = 0,
			})
		end
	end
	tracked[model] = { Chassis = chassis, Seat = seat, Wheels = wheels }
end

-- Advances every tracked vehicle's wheels by dt seconds. Exposed for tests.
function VehicleVisuals.update(dt: number)
	for model, info in tracked do
		if not model.Parent then
			tracked[model] = nil
		else
			local chassis = info.Chassis
			local forwardSpeed = chassis.AssemblyLinearVelocity:Dot(chassis.CFrame.LookVector)
			local steerYaw = -info.Seat.SteerFloat * MAX_WHEEL_STEER
			for _, wheel in info.Wheels do
				-- Rolling forward turns the wheel's top toward -Z, which is a negative rotation about X.
				wheel.Angle = (wheel.Angle - forwardSpeed * dt / wheel.Radius) % TAU
				local roll = CFrame.Angles(wheel.Angle, 0, 0)
				if wheel.Front then
					wheel.Motor.Transform = CFrame.Angles(0, steerYaw, 0) * roll
				else
					wheel.Motor.Transform = roll
				end
			end
		end
	end
end

function VehicleVisuals.start()
	CollectionService:GetInstanceAddedSignal(TAG):Connect(function(model)
		task.spawn(track, model)
	end)
	for _, model in CollectionService:GetTagged(TAG) do
		task.spawn(track, model)
	end
	UIKit.onFrame(VehicleVisuals.update)
end

-- Exposed for tests.
VehicleVisuals.track = track

return VehicleVisuals
