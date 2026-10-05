--[[
	Drives the vehicle the local player is sitting in.

	The server hands physics ownership of your own vehicle to you, so this script (running on your
	client) sets its velocity every physics step from the VehicleSeat's throttle/steer input.
	Roblox's PlayerModule already feeds the seat from keyboard, gamepad and mobile thumbstick.
	See DriveModel for what the numbers mean.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local DriveModel = require(script.Parent.DriveModel)

local VehicleController = {}

local player = Players.LocalPlayer

-- The vehicle model we're currently driving, or nil.
function VehicleController.currentVehicle(): (Model?, VehicleSeat?)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local seat = humanoid and humanoid.SeatPart
	if not seat or not seat:IsA("VehicleSeat") then
		return nil, nil
	end
	local model = seat.Parent
	if not model or model:GetAttribute("OwnerUserId") ~= player.UserId then
		return nil, nil
	end
	return model, seat
end

local function step(dt: number)
	local model, seat = VehicleController.currentVehicle()
	if not model or not seat then
		return
	end
	local chassis = model.PrimaryPart
	if not chassis or chassis.Anchored then
		return -- parked, or the server hasn't released it yet
	end

	local cframe = chassis.CFrame
	if DriveModel.needsRecovery(cframe.UpVector) then
		chassis.AssemblyLinearVelocity = Vector3.zero
		chassis.AssemblyAngularVelocity = Vector3.zero
		chassis.CFrame = DriveModel.recoveryCFrame(cframe.Position, cframe.LookVector)
		return
	end

	local stats = {
		MaxSpeed = model:GetAttribute("MaxSpeed"),
		Accel = model:GetAttribute("Accel"),
		Turn = model:GetAttribute("Turn"),
		Grip = model:GetAttribute("Grip"),
	}
	if not (stats.MaxSpeed and stats.Accel and stats.Turn and stats.Grip) then
		return
	end

	local velocity, angular =
		DriveModel.step(chassis.AssemblyLinearVelocity, cframe.LookVector, cframe.UpVector, seat.ThrottleFloat, seat.SteerFloat, stats, dt)
	chassis.AssemblyLinearVelocity = velocity
	chassis.AssemblyAngularVelocity = angular
end

function VehicleController.start()
	-- PreSimulation runs just before each physics step, so our velocity is what the step uses.
	RunService.PreSimulation:Connect(step)
end

-- Exposed for tests.
VehicleController.step = step

return VehicleController
