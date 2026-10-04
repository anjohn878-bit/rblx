--[[
	MovementController (client)
	Sprint with stamina, sprint acceleration ramp, dribble slowdown and the short
	slow after a failed tackle. Speeds scale gently with Pace/Stamina attributes.
	Also performs the local dash used by skill moves and tackles.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)

local ClientState = require(script.Parent.Parent.ClientState)

local MovementController = {}

local player = Players.LocalPlayer
local sprintHeld = false
local sprintBlend = 0
local lastSprintTime = 0
local slowUntil = 0

function MovementController.SetSprinting(held: boolean)
	sprintHeld = held
end

local function getCharacterParts()
	local character = player.Character
	if not character then
		return nil, nil
	end
	return character:FindFirstChildOfClass("Humanoid"), character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

-- Short burst of velocity (skill-move sidestep / tackle lunge).
function MovementController.Dash(direction: Vector3, speed: number, duration: number)
	local _, root = getCharacterParts()
	if not root then
		return
	end
	local flat = Vector3.new(direction.X, 0, direction.Z)
	if flat.Magnitude < 1e-3 then
		return
	end
	local attachment = Instance.new("Attachment")
	attachment.Parent = root
	local lv = Instance.new("LinearVelocity")
	lv.Attachment0 = attachment
	lv.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane
	lv.PrimaryTangentAxis = Vector3.xAxis
	lv.SecondaryTangentAxis = Vector3.zAxis
	lv.PlaneVelocity = Vector2.new(flat.Unit.X * speed, flat.Unit.Z * speed)
	lv.MaxForce = 60000
	lv.RelativeTo = Enum.ActuatorRelativeTo.World
	lv.Parent = root
	task.delay(duration, function()
		lv:Destroy()
		attachment:Destroy()
	end)
end

local function step(dt: number)
	local humanoid, root = getCharacterParts()
	if not humanoid or not root then
		return
	end
	local m = Config.Movement
	local paceAlpha = math.clamp(ClientState.GetAttribute("Pace") / Config.Attributes.Max, 0, 1)
	local staminaAlpha = math.clamp(ClientState.GetAttribute("Stamina") / Config.Attributes.Max, 0, 1)
	local now = os.clock()

	local moving = humanoid.MoveDirection.Magnitude > 0.1
	local canSprint = sprintHeld and moving and ClientState.Stamina > 0 and not root.Anchored
	if canSprint then
		sprintBlend = math.min(1, sprintBlend + dt / m.SprintRampTime)
		local drain = m.StaminaDrainPerSecond * (1 - staminaAlpha * m.StaminaAttributeBonus)
		ClientState.Stamina = math.max(0, ClientState.Stamina - drain * dt)
		lastSprintTime = now
	else
		sprintBlend = math.max(0, sprintBlend - dt / (m.SprintRampTime * 0.6))
		if now - lastSprintTime > m.StaminaRegenDelay then
			ClientState.Stamina = math.min(m.StaminaMax, ClientState.Stamina + m.StaminaRegenPerSecond * dt)
		end
	end

	local walk = m.BaseWalkSpeed + paceAlpha * m.PaceWalkBonus
	local sprint = m.BaseSprintSpeed + paceAlpha * m.PaceSprintBonus
	local speed = walk + (sprint - walk) * sprintBlend
	if player:GetAttribute("HasBall") then
		speed *= m.DribbleSpeedMultiplier
	end
	if now < slowUntil then
		speed *= 0.45
	end
	humanoid.WalkSpeed = speed
end

function MovementController.Init() end

function MovementController.Start()
	RunService.Heartbeat:Connect(step)
	Remotes.Get("BallEvent").OnClientEvent:Connect(function(kind, payload)
		if kind == "TackleFailed" then
			slowUntil = os.clock() + (payload and payload.Duration or 0.6)
		end
	end)
	player.CharacterAdded:Connect(function()
		ClientState.Stamina = Config.Movement.StaminaMax
		sprintBlend = 0
	end)
end

return MovementController
