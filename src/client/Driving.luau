-- Drives the local player's vehicle. The driver's client owns the vehicle's physics, so setting
-- the chassis constraints here every frame gives instant, lag-free steering. Input comes from
-- VehicleSeat.ThrottleFloat / SteerFloat, which Roblox fills in for keyboard, gamepad and the
-- mobile thumbstick.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Driving = {}

local MAX_SPEED_LAG = 12 -- how far the commanded speed may run ahead of the real speed
local UPRIGHT_STRENGTH = 8

local player = Players.LocalPlayer
local connection: RBXScriptConnection? = nil
local currentSeat: VehicleSeat? = nil
local currentChassis: BasePart? = nil
local drive: LinearVelocity? = nil
local steer: AngularVelocity? = nil
local speed = 0

local function moveToward(value: number, target: number, step: number): number
	if value < target then
		return math.min(value + step, target)
	end
	return math.max(value - step, target)
end

local function stop()
	if connection then
		connection:Disconnect()
		connection = nil
	end
	if drive then
		drive.PlaneVelocity = Vector2.zero
	end
	if steer then
		steer.AngularVelocity = Vector3.zero
	end
	currentSeat, currentChassis, drive, steer = nil, nil, nil, nil
	speed = 0
end

local function start(seat: VehicleSeat)
	stop()
	local model = seat.Parent
	local chassis = model and (model :: Model).PrimaryPart
	if not chassis then
		return
	end
	local driveConstraint = chassis:FindFirstChild("Drive") :: LinearVelocity?
	local steerConstraint = chassis:FindFirstChild("Steer") :: AngularVelocity?
	if not driveConstraint or not steerConstraint then
		return
	end
	currentSeat, currentChassis, drive, steer = seat, chassis, driveConstraint, steerConstraint

	local topSpeed = seat:GetAttribute("TopSpeed") or 40
	local acceleration = seat:GetAttribute("Acceleration") or 30
	local turnRate = seat:GetAttribute("TurnRate") or 2
	speed = chassis.CFrame.LookVector:Dot(chassis.AssemblyLinearVelocity)

	connection = RunService.Heartbeat:Connect(function(dt)
		if not seat.Parent or not chassis.Parent then
			stop()
			return
		end
		local throttle = seat.ThrottleFloat
		local steering = seat.SteerFloat

		local target = if throttle >= 0 then throttle * topSpeed else throttle * topSpeed * 0.4
		local rate = acceleration
		if throttle == 0 then
			rate = acceleration * 0.6 -- coasting
		elseif speed * throttle < 0 then
			rate = acceleration * 2.2 -- braking
		end
		speed = moveToward(speed, target, rate * dt)

		-- Don't keep pushing at full speed into a wall: stay close to how fast we really move.
		local actual = chassis.CFrame.LookVector:Dot(chassis.AssemblyLinearVelocity)
		speed = math.clamp(speed, actual - MAX_SPEED_LAG, actual + MAX_SPEED_LAG)

		driveConstraint.PlaneVelocity = Vector2.new(speed, 0)

		-- Steering needs some speed, and flips when reversing like a real car.
		local grip = math.clamp(speed / 18, -1, 1)
		local yaw = -steering * turnRate * grip
		local upright = chassis.CFrame.UpVector:Cross(Vector3.yAxis) * UPRIGHT_STRENGTH
		steerConstraint.AngularVelocity = Vector3.new(0, yaw, 0) + upright
	end)
end

local function onCharacter(character: Model)
	stop()
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	humanoid.Seated:Connect(function(active, seatPart)
		if active and seatPart and seatPart:IsA("VehicleSeat") and seatPart:GetAttribute("DeliveryVehicle") then
			start(seatPart)
		else
			stop()
		end
	end)
end

function Driving.isDriving(): boolean
	return currentSeat ~= nil
end

function Driving.getSpeed(): number
	if currentChassis then
		return currentChassis.AssemblyLinearVelocity.Magnitude
	end
	return 0
end

function Driving.init()
	player.CharacterAdded:Connect(onCharacter)
	if player.Character then
		task.spawn(onCharacter, player.Character)
	end
end

return Driving
