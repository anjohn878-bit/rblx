--[[
	SkateController
	Turns the local character into a skater whenever they stand on a rink:
	  * momentum-based gliding with carving turns
	  * pushing against your glide does a hockey stop
	  * every jump spins you; land it to score Single/Double/Triple... jumps
	  * F / gamepad Y / the touch "Spin" button does a scratch spin

	Movement uses a LinearVelocity that only drives horizontal motion (so
	gravity and jumping still work normally) and an AlignOrientation that keeps
	the skater facing along their glide.
]]

local CollectionService = game:GetService("CollectionService")
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Formulas = require(Shared.Formulas)
local Remotes = require(Shared.Remotes)
local Signal = require(Shared.Signal)

local ClientData = require(script.Parent.ClientData)

local SKATING = Config.Skating
local TRICKS = Config.Tricks
local TAU = math.pi * 2
local SPIN_ACTION = "SkateSpin"
local OFF_ICE_GRACE = 0.12

local player = Players.LocalPlayer
local random = Random.new()

local SkateController = {}
SkateController.SkatingChanged = Signal.new() -- (isSkating)
SkateController.RinkChanged = Signal.new() -- (rinkId?) when the rink under your feet changes
SkateController.TrickStarted = Signal.new() -- ("Jump" | "Spin")
SkateController.JumpLanded = Signal.new() -- (rotations, jumpType)

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Include

local character, humanoid, root
local velocityConstraint, orientationConstraint
local characterConnections = {}

local skating = false
local velocity = Vector3.zero
local yaw = 0
local currentRinkId = nil
local offIceTime = 0
local braking = false
local brakeSide = 1
local airborne = false
local airTime = 0
local air = nil -- active jump: { spinRate, angle, time, jumpType }
local spin = nil -- active scratch spin: { elapsed }
local lastSpinEnd = -math.huge

local function flat(vector)
	return Vector3.new(vector.X, 0, vector.Z)
end

-- Yaw (rotation about Y) whose LookVector points along `direction`.
local function yawOf(direction)
	return math.atan2(-direction.X, -direction.Z)
end

local function angleDifference(from, to)
	return (to - from + math.pi) % TAU - math.pi
end

local function refreshRayFilter()
	rayParams.FilterDescendantsInstances = CollectionService:GetTagged("RinkFloor")
end

local function isUnlocked(rinkId)
	local rink = Formulas.getRink(rinkId)
	if not rink then
		return false
	end
	local profile = ClientData.get()
	if not profile then
		return rink.Price <= 0
	end
	return Formulas.isRinkUnlocked(profile, rinkId)
end

local function currentStats()
	local profile = ClientData.get()
	if profile then
		return Formulas.maxSpeed(profile), Formulas.acceleration(profile)
	end
	return Config.Skates[1].MaxSpeed, Config.Skates[1].Acceleration
end

local function rinkUnderFeet()
	local reach = humanoid.HipHeight + root.Size.Y / 2 + 1.5
	local result = workspace:Raycast(root.Position, Vector3.new(0, -reach, 0), rayParams)
	return result and result.Instance:GetAttribute("RinkId")
end

local function bindSpinAction(enabled)
	if enabled then
		ContextActionService:BindAction(SPIN_ACTION, function(_, inputState)
			if inputState == Enum.UserInputState.Begin then
				SkateController.trySpin()
			end
			return Enum.ContextActionResult.Sink
		end, true, Enum.KeyCode.F, Enum.KeyCode.ButtonY)
		ContextActionService:SetTitle(SPIN_ACTION, "Spin")
	else
		ContextActionService:UnbindAction(SPIN_ACTION)
	end
end

local function setSkating(enabled)
	if skating == enabled then
		return
	end
	skating = enabled
	braking = false
	air = nil
	spin = nil
	offIceTime = 0

	if enabled then
		velocity = flat(root.AssemblyLinearVelocity)
		yaw = yawOf(root.CFrame.LookVector)
		humanoid.AutoRotate = false
		velocityConstraint.MaxForce = root.AssemblyMass * SKATING.ForcePerMass
		velocityConstraint.PlaneVelocity = Vector2.new(velocity.X, velocity.Z)
		velocityConstraint.Enabled = true
		orientationConstraint.CFrame = CFrame.Angles(0, yaw, 0)
		orientationConstraint.Enabled = true
	else
		if velocityConstraint then
			velocityConstraint.Enabled = false
			orientationConstraint.Enabled = false
		end
		if humanoid then
			humanoid.AutoRotate = true
		end
	end

	bindSpinAction(enabled)
	Remotes.SkateState:FireServer(enabled)
	SkateController.SkatingChanged:Fire(enabled)
end

local function beginJump()
	spin = nil -- jumping out of a spin cancels it
	local speed = velocity.Magnitude
	if speed < TRICKS.MinJumpSpeed then
		air = nil
		return
	end
	air = {
		spinRate = Formulas.airSpinRate(speed),
		angle = 0,
		time = 0,
		jumpType = TRICKS.JumpTypes[random:NextInteger(1, #TRICKS.JumpTypes)],
	}
	SkateController.TrickStarted:Fire("Jump")
end

local function finishJump()
	local trick = air
	air = nil
	yaw %= TAU
	local rotations = Formulas.countRotations(trick.angle)
	if rotations >= 1 then
		Remotes.TrickLanded:FireServer({ kind = "Jump", rotations = rotations, jumpType = trick.jumpType })
	end
	SkateController.JumpLanded:Fire(rotations, trick.jumpType)
end

local function finishSpin()
	spin = nil
	yaw %= TAU
	lastSpinEnd = os.clock()
	Remotes.TrickLanded:FireServer({ kind = "Spin" })
end

function SkateController.trySpin()
	if not skating or airborne or air or spin then
		return
	end
	if os.clock() - lastSpinEnd < TRICKS.Spin.Cooldown then
		return
	end
	spin = { elapsed = 0 }
	SkateController.TrickStarted:Fire("Spin")
end

local function updateMovement(dt, grounded)
	local maxSpeed, acceleration = currentStats()

	-- If physics changed our motion (we hit a wall), go with what actually happened.
	local actual = flat(root.AssemblyLinearVelocity)
	if (actual - velocity).Magnitude > 6 then
		velocity = actual
	end

	local speed = velocity.Magnitude
	local direction = if speed > 0.01 then velocity / speed else flat(root.CFrame.LookVector).Unit
	local moveDirection = flat(humanoid.MoveDirection)
	local inputStrength = math.min(moveDirection.Magnitude, 1)
	local wasBraking = braking
	braking = false

	if spin then
		speed *= math.exp(-TRICKS.Spin.SpeedDecay * dt)
	elseif not grounded then
		speed *= math.exp(-SKATING.AirFriction * dt)
	elseif inputStrength > 0.05 then
		local wish = moveDirection.Unit
		if speed > 2 and direction:Dot(wish) < -0.5 then
			-- Pushing against your glide digs the blades in: hockey stop.
			braking = true
			speed = math.max(0, speed - SKATING.BrakeDeceleration * inputStrength * dt)
		else
			if speed < SKATING.InstantTurnSpeed then
				direction = wish
			else
				local currentYaw = yawOf(direction)
				local turn =
					math.clamp(angleDifference(currentYaw, yawOf(wish)), -SKATING.TurnRate * dt, SKATING.TurnRate * dt)
				direction = CFrame.Angles(0, currentYaw + turn, 0).LookVector
			end
			if speed < maxSpeed then
				local alignment = math.max(0, direction:Dot(wish))
				speed = math.min(maxSpeed, speed + acceleration * inputStrength * alignment * dt)
			end
		end
	else
		speed *= math.exp(-SKATING.GlideFriction * dt)
	end

	if speed > maxSpeed then
		speed = math.max(maxSpeed, speed - SKATING.OverspeedDeceleration * dt)
	end
	if speed < 0.05 then
		speed = 0
	end

	velocity = direction * speed
	velocityConstraint.PlaneVelocity = Vector2.new(velocity.X, velocity.Z)

	-- Facing: spin when doing tricks, otherwise face along the glide.
	if spin then
		local config = TRICKS.Spin
		spin.elapsed += dt
		local progress = math.min(1, spin.elapsed / config.Duration)
		yaw += (config.StartRate + (config.EndRate - config.StartRate) * math.sin(progress * math.pi / 2)) * dt
		if spin.elapsed >= config.Duration then
			finishSpin()
		end
	elseif air then
		local step = air.spinRate * dt
		air.angle += step
		yaw += step
	else
		local targetYaw = yaw
		if braking then
			local travelYaw = yawOf(direction)
			if not wasBraking then
				-- Turn sideways to whichever side is closer, like a hockey stop.
				local left = math.abs(angleDifference(yaw, travelYaw + math.pi / 2))
				local right = math.abs(angleDifference(yaw, travelYaw - math.pi / 2))
				brakeSide = if left < right then 1 else -1
			end
			targetYaw = travelYaw + brakeSide * math.pi / 2
		elseif speed > 1.5 then
			targetYaw = yawOf(direction)
		elseif inputStrength > 0.05 then
			targetYaw = yawOf(moveDirection)
		end
		yaw += angleDifference(yaw, targetYaw) * (1 - math.exp(-12 * dt))
	end
	orientationConstraint.CFrame = CFrame.Angles(0, yaw, 0)
end

local function update(dt)
	if not (character and humanoid and root and root.Parent and velocityConstraint) then
		return
	end
	if humanoid.Health <= 0 or humanoid.Sit or root.Anchored then
		setSkating(false)
		return
	end

	local grounded = humanoid.FloorMaterial ~= Enum.Material.Air
	local rinkId = rinkUnderFeet()
	if rinkId and not isUnlocked(rinkId) then
		rinkId = nil
	end

	if grounded and rinkId ~= currentRinkId then
		currentRinkId = rinkId
		SkateController.RinkChanged:Fire(rinkId)
	end

	if air then
		air.time += dt
		if grounded and air.time > 0.12 then
			finishJump()
		end
	end

	if not skating then
		if grounded and rinkId then
			setSkating(true)
		else
			return
		end
	end

	-- Stop skating once we've properly left the ice (or been in the air far too long).
	if grounded and not rinkId then
		offIceTime += dt
		if offIceTime > OFF_ICE_GRACE then
			setSkating(false)
			return
		end
	else
		offIceTime = 0
	end

	airborne = not grounded
	airTime = if airborne then airTime + dt else 0
	if airTime > SKATING.MaxAirTime then
		setSkating(false)
		return
	end

	updateMovement(dt, grounded)
end

local function onCharacterAdded(newCharacter)
	for _, connection in characterConnections do
		connection:Disconnect()
	end
	table.clear(characterConnections)
	if skating then
		setSkating(false)
	end

	character = newCharacter
	humanoid = newCharacter:WaitForChild("Humanoid")
	root = newCharacter:WaitForChild("HumanoidRootPart")
	velocity = Vector3.zero
	currentRinkId = nil
	airTime = 0

	local attachment = root:FindFirstChild("RootAttachment")
	if not attachment then
		attachment = Instance.new("Attachment")
		attachment.Name = "SkateAttachment"
		attachment.Parent = root
	end

	velocityConstraint = Instance.new("LinearVelocity")
	velocityConstraint.Name = "SkateVelocity"
	velocityConstraint.Attachment0 = attachment
	velocityConstraint.RelativeTo = Enum.ActuatorRelativeTo.World
	velocityConstraint.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane
	velocityConstraint.PrimaryTangentAxis = Vector3.xAxis
	velocityConstraint.SecondaryTangentAxis = Vector3.zAxis
	velocityConstraint.ForceLimitMode = Enum.ForceLimitMode.Magnitude
	velocityConstraint.Enabled = false
	velocityConstraint.Parent = root

	orientationConstraint = Instance.new("AlignOrientation")
	orientationConstraint.Name = "SkateOrientation"
	orientationConstraint.Mode = Enum.OrientationAlignmentMode.OneAttachment
	orientationConstraint.Attachment0 = attachment
	orientationConstraint.Responsiveness = 60
	orientationConstraint.MaxTorque = math.huge
	orientationConstraint.MaxAngularVelocity = math.huge
	orientationConstraint.Enabled = false
	orientationConstraint.Parent = root

	table.insert(
		characterConnections,
		humanoid.StateChanged:Connect(function(_, newState)
			if newState == Enum.HumanoidStateType.Jumping and skating then
				beginJump()
			end
		end)
	)
	table.insert(
		characterConnections,
		humanoid.Died:Connect(function()
			setSkating(false)
		end)
	)
end

function SkateController.isSkating()
	return skating
end

function SkateController.isBraking()
	return skating and braking
end

function SkateController.isSpinning()
	return skating and (spin ~= nil or air ~= nil)
end

function SkateController.getSpeed()
	if root and root.Parent then
		return flat(root.AssemblyLinearVelocity).Magnitude
	end
	return 0
end

function SkateController.getMaxSpeed()
	return (currentStats())
end

function SkateController.getRinkId()
	return currentRinkId
end

function SkateController.init()
	refreshRayFilter()
	CollectionService:GetInstanceAddedSignal("RinkFloor"):Connect(refreshRayFilter)
	CollectionService:GetInstanceRemovedSignal("RinkFloor"):Connect(refreshRayFilter)

	if player.Character then
		task.spawn(onCharacterAdded, player.Character)
	end
	player.CharacterAdded:Connect(onCharacterAdded)
	RunService.PreSimulation:Connect(update)
end

return SkateController
