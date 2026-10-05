--[[
	SkatePoser
	Procedural skating animation for R15 characters. While someone is skating
	this overrides their joints after the default Animate script has run:
	a crouched stance, alternating side pushes, arm swing, leaning into turns,
	a sideways lean during hockey stops, and a tight tuck while spinning.

	Everything is derived from how the character is moving, so it runs on every
	client for every skater and stays in sync without extra networking.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local SkateController = require(script.Parent.SkateController)

local SkatePoser = {}

local localPlayer = Players.LocalPlayer
local TAU = math.pi * 2
local BLEND_SPEED = 8

local JOINTS = {
	Root = "LowerTorso",
	Waist = "UpperTorso",
	Neck = "Head",
	LeftHip = "LeftUpperLeg",
	RightHip = "RightUpperLeg",
	LeftKnee = "LeftLowerLeg",
	RightKnee = "RightLowerLeg",
	LeftAnkle = "LeftFoot",
	RightAnkle = "RightFoot",
	LeftShoulder = "LeftUpperArm",
	RightShoulder = "RightUpperArm",
	LeftElbow = "LeftLowerArm",
	RightElbow = "RightLowerArm",
}

local rigs = {} -- [character] = rig state

local function smooth(current, target, rate, dt)
	return current + (target - current) * (1 - math.exp(-rate * dt))
end

local function findRig(character)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root or humanoid.RigType ~= Enum.HumanoidRigType.R15 then
		return nil
	end
	local motors = {}
	for jointName, partName in JOINTS do
		local limb = character:FindFirstChild(partName)
		local motor = limb and limb:FindFirstChild(jointName)
		if not (motor and motor:IsA("Motor6D")) then
			return nil
		end
		motors[jointName] = motor
	end
	return {
		character = character,
		humanoid = humanoid,
		root = root,
		motors = motors,
		weight = 0,
		phase = 0,
		lastYaw = nil,
		yawRate = 0,
		lastSpeed = 0,
		acceleration = 0,
		bank = 0,
		tuck = 0,
		brake = 0,
		brakeSign = 1,
		spinTime = 0,
		runningSound = nil,
		runningVolume = nil,
	}
end

-- Joints get rebuilt when an avatar's body parts load in, so re-find them if any went stale.
local function getRig(character)
	local rig = rigs[character]
	if rig then
		for _, motor in rig.motors do
			if not motor.Parent then
				rig = nil
				break
			end
		end
	end
	if not rig then
		rig = findRig(character)
		rigs[character] = rig
	end
	return rig
end

local function isSkating(player, character)
	if player == localPlayer then
		return SkateController.isSkating()
	end
	return character:GetAttribute("Skating") == true
end

-- Footstep sounds come from the default character sounds script; silence them on the ice.
local function muteFootsteps(rig, muted)
	if not rig.runningSound or not rig.runningSound.Parent then
		rig.runningSound = rig.root:FindFirstChild("Running")
		rig.runningVolume = rig.runningSound and rig.runningSound.Volume
	end
	if rig.runningSound then
		rig.runningSound.Volume = if muted then 0 else rig.runningVolume
	end
end

local function computePose(rig, dt, isLocal)
	local root = rig.root
	local velocity = root.AssemblyLinearVelocity
	local horizontal = Vector3.new(velocity.X, 0, velocity.Z)
	local speed = horizontal.Magnitude

	-- How fast the character is turning, from frame-to-frame facing changes.
	local look = root.CFrame.LookVector
	local currentYaw = math.atan2(-look.X, -look.Z)
	if rig.lastYaw then
		local delta = (currentYaw - rig.lastYaw + math.pi) % TAU - math.pi
		rig.yawRate = smooth(rig.yawRate, delta / math.max(dt, 1 / 240), 10, dt)
	end
	rig.lastYaw = currentYaw

	rig.acceleration = smooth(rig.acceleration, (speed - rig.lastSpeed) / math.max(dt, 1 / 240), 4, dt)
	rig.lastSpeed = speed

	-- The local skater knows exactly what it's doing; for everyone else, a sustained
	-- fast turn is a spin (a hockey stop also turns quickly, but only briefly).
	local spinning
	if isLocal then
		spinning = SkateController.isSpinning()
	else
		rig.spinTime = if math.abs(rig.yawRate) > 8 then rig.spinTime + dt else 0
		spinning = rig.spinTime > 0.2
	end
	local airborne = math.abs(velocity.Y) > 6
	rig.tuck = smooth(rig.tuck, if spinning or airborne then 1 else 0, 12, dt)

	-- Sliding sideways = hockey stop.
	local lateral = 0
	local mayBrake = if isLocal then SkateController.isBraking() else not spinning
	if speed > 5 and mayBrake then
		local facingDot = look:Dot(horizontal.Unit)
		if facingDot < 0.5 then
			lateral = root.CFrame.RightVector:Dot(horizontal.Unit)
		end
	end
	if math.abs(lateral) > 0.2 then
		rig.brakeSign = if lateral > 0 then 1 else -1
	end
	rig.brake = smooth(rig.brake, math.abs(lateral), 10, dt)

	-- Lean into turns, or away from the slide when stopping.
	local turnLean = if spinning then 0 else math.clamp(rig.yawRate * speed * 0.006, -0.35, 0.35)
	local brakeLean = 0.3 * rig.brakeSign
	local targetBank = turnLean * (1 - rig.brake) + brakeLean * rig.brake
	rig.bank = smooth(rig.bank, targetBank, 8, dt)

	-- Stride: strong pushes when speeding up, a gentle glide when coasting.
	local speedAlpha = math.clamp(speed / 40, 0, 1)
	local gliding = rig.acceleration < -0.5
	local push = math.clamp(speed / 25, 0, 1) * (if gliding then 0.3 else 1) * (1 - rig.brake)
	rig.phase = (rig.phase + dt * TAU * (0.55 + speedAlpha * 0.9)) % TAU
	local stride = math.sin(rig.phase)
	local leftPush = math.max(stride, 0) * push
	local rightPush = math.max(-stride, 0) * push

	local crouch = 1 + rig.brake * 0.5
	local lean = 0.2 + speedAlpha * 0.25 + rig.brake * 0.1
	local twist = 0.15 * stride * push

	local function leg(pushAmount, side)
		local hip = CFrame.Angles(0.35 * crouch - 0.7 * pushAmount, 0, side * 0.45 * pushAmount)
		local knee = CFrame.Angles(-0.6 * crouch + 0.45 * pushAmount, 0, 0)
		local ankle = CFrame.Angles(0.25 * crouch - 0.1 * pushAmount, 0, 0)
		return hip, knee, ankle
	end
	local leftHip, leftKnee, leftAnkle = leg(leftPush, -1)
	local rightHip, rightKnee, rightAnkle = leg(rightPush, 1)

	local skate = {
		Waist = CFrame.Angles(-lean, twist, 0),
		Neck = CFrame.Angles(lean * 0.6, -twist, 0),
		LeftHip = leftHip,
		LeftKnee = leftKnee,
		LeftAnkle = leftAnkle,
		RightHip = rightHip,
		RightKnee = rightKnee,
		RightAnkle = rightAnkle,
		LeftShoulder = CFrame.Angles(0.15 + 0.7 * stride * push, 0, -0.3 - 0.2 * rig.brake),
		RightShoulder = CFrame.Angles(0.15 - 0.7 * stride * push, 0, 0.3 + 0.2 * rig.brake),
		LeftElbow = CFrame.Angles(0.35, 0, 0),
		RightElbow = CFrame.Angles(0.35, 0, 0),
	}

	-- Arms pulled in and legs together for spins and jumps.
	local tuckPose = {
		Waist = CFrame.identity,
		Neck = CFrame.identity,
		LeftHip = CFrame.Angles(0.05, 0, 0.08),
		RightHip = CFrame.Angles(0.05, 0, -0.08),
		LeftKnee = CFrame.Angles(-0.05, 0, 0),
		RightKnee = CFrame.Angles(-0.05, 0, 0),
		LeftAnkle = CFrame.Angles(0.15, 0, 0),
		RightAnkle = CFrame.Angles(0.15, 0, 0),
		LeftShoulder = CFrame.Angles(1.1, 0, 0.55),
		RightShoulder = CFrame.Angles(1.1, 0, -0.55),
		LeftElbow = CFrame.Angles(1.5, 0, 0),
		RightElbow = CFrame.Angles(1.5, 0, 0),
	}

	local pose = {}
	for jointName, skateCFrame in skate do
		pose[jointName] = skateCFrame:Lerp(tuckPose[jointName], rig.tuck)
	end

	-- Root: drop slightly for the crouch, and bank around the feet rather than the hips.
	local rootMotor = rig.motors.Root
	local pivotHeight = rig.humanoid.HipHeight + root.Size.Y / 2 + rootMotor.C0.Position.Y
	local drop = 0.12 * crouch * (1 - rig.tuck)
	pose.Root = CFrame.new(0, -drop, 0)
		* CFrame.new(0, -pivotHeight, 0)
		* CFrame.Angles(0, 0, rig.bank)
		* CFrame.new(0, pivotHeight, 0)

	return pose
end

local function step(dt)
	for _, player in Players:GetPlayers() do
		local character = player.Character
		if not character then
			continue
		end
		local rig = getRig(character)
		if not rig or not rig.root.Parent then
			continue
		end

		local skating = isSkating(player, character) and rig.humanoid.Health > 0
		rig.weight = smooth(rig.weight, if skating then 1 else 0, BLEND_SPEED, dt)
		if not skating and rig.weight < 0.01 then
			if rig.weight > 0 then
				rig.weight = 0
				muteFootsteps(rig, false)
			end
			rig.lastYaw = nil
			continue
		end

		muteFootsteps(rig, rig.weight > 0.5)
		local pose = computePose(rig, dt, player == localPlayer)
		for jointName, motor in rig.motors do
			local target = pose[jointName]
			if target then
				motor.Transform = motor.Transform:Lerp(target, rig.weight)
			end
		end
	end
end

function SkatePoser.init()
	-- PreSimulation runs after the Animator has written this frame's joint transforms.
	RunService.PreSimulation:Connect(step)

	local function forget(character)
		rigs[character] = nil
	end
	local function watch(player)
		player.CharacterRemoving:Connect(forget)
	end
	Players.PlayerAdded:Connect(watch)
	for _, player in Players:GetPlayers() do
		watch(player)
	end
end

return SkatePoser
