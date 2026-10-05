--[[
	Effects
	Client-side polish: falling snow, speed-based field of view, snow spray on
	hockey stops, sparkles for landed tricks and pickups, and bobbing golden
	snowflakes.
]]

local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)

local SkateController = require(script.Parent.SkateController)

local Effects = {}

local player = Players.LocalPlayer
local BASE_FOV = 70
local MAX_FOV = 92
local GOLD = Color3.fromRGB(255, 205, 60)

local snowEmitterPart
local sprayEmitter
local sprayAttachment
local flakes = {}

local function emitterPart(name)
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Transparency = 1
	part.Size = Vector3.new(1, 1, 1)
	return part
end

-- A one-shot burst of particles at a point in the world.
local function burst(position, color, count, speed)
	local part = emitterPart("Burst")
	part.CFrame = CFrame.new(position)
	part.Parent = workspace.CurrentCamera

	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = ColorSequence.new(color)
	emitter.LightEmission = 1
	emitter.Lifetime = NumberRange.new(0.5, 1)
	emitter.Speed = NumberRange.new(speed * 0.5, speed)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.5),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Drag = 3
	emitter.Enabled = false
	emitter.Parent = part
	emitter:Emit(count)

	Debris:AddItem(part, 1.5)
end

local function createSnowfall()
	snowEmitterPart = emitterPart("Snowfall")
	snowEmitterPart.Size = Vector3.new(160, 1, 160)
	snowEmitterPart.Parent = workspace.CurrentCamera

	local snow = Instance.new("ParticleEmitter")
	snow.Name = "Snow"
	snow.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255))
	snow.LightEmission = 0.3
	snow.Rate = 140
	snow.Lifetime = NumberRange.new(7, 10)
	snow.Speed = NumberRange.new(5, 9)
	snow.EmissionDirection = Enum.NormalId.Bottom
	snow.SpreadAngle = Vector2.new(15, 15)
	snow.Acceleration = Vector3.new(1.5, 0, 0.6)
	snow.RotSpeed = NumberRange.new(-60, 60)
	snow.Rotation = NumberRange.new(0, 360)
	snow.Size = NumberSequence.new(0.22)
	snow.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.1, 0.1),
		NumberSequenceKeypoint.new(0.85, 0.2),
		NumberSequenceKeypoint.new(1, 1),
	})
	snow.Parent = snowEmitterPart
end

local function attachSpray(character)
	local root = character:WaitForChild("HumanoidRootPart")
	local humanoid = character:WaitForChild("Humanoid")

	sprayAttachment = Instance.new("Attachment")
	sprayAttachment.Name = "SnowSpray"
	sprayAttachment.Position = Vector3.new(0, -(humanoid.HipHeight + root.Size.Y / 2) + 0.4, 0)
	sprayAttachment.Parent = root

	sprayEmitter = Instance.new("ParticleEmitter")
	sprayEmitter.Color = ColorSequence.new(Color3.fromRGB(240, 248, 255))
	sprayEmitter.LightEmission = 0.2
	sprayEmitter.Lifetime = NumberRange.new(0.3, 0.6)
	sprayEmitter.Speed = NumberRange.new(8, 16)
	sprayEmitter.SpreadAngle = Vector2.new(35, 25)
	sprayEmitter.Acceleration = Vector3.new(0, -30, 0)
	sprayEmitter.Drag = 2
	sprayEmitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.35),
		NumberSequenceKeypoint.new(1, 0.1),
	})
	sprayEmitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.1),
		NumberSequenceKeypoint.new(1, 1),
	})
	sprayEmitter.EmissionDirection = Enum.NormalId.Front
	sprayEmitter.Rate = 0
	sprayEmitter.Parent = sprayAttachment
end

local function trackFlake(part)
	local billboard = part:WaitForChild("Icon", 5)
	local flake = billboard and billboard:WaitForChild("Flake", 5)
	if flake and part.Parent then
		flakes[part] = { billboard = billboard, label = flake, phase = math.random() * math.pi * 2 }
	end
end

local function onRenderStep(dt)
	local camera = workspace.CurrentCamera
	local now = os.clock()

	if snowEmitterPart then
		snowEmitterPart.CFrame = CFrame.new(camera.CFrame.Position + Vector3.new(0, 40, 0))
	end

	-- Widen the view as you pick up speed.
	local targetFov = BASE_FOV
	if SkateController.isSkating() then
		local speedAlpha = math.clamp((SkateController.getSpeed() - 20) / 80, 0, 1)
		targetFov = BASE_FOV + (MAX_FOV - BASE_FOV) * speedAlpha
	end
	camera.FieldOfView += (targetFov - camera.FieldOfView) * (1 - math.exp(-4 * dt))

	-- Kick up snow during hockey stops.
	if sprayEmitter and sprayEmitter.Parent then
		local speed = SkateController.getSpeed()
		sprayEmitter.Rate = if SkateController.isBraking() and speed > 4 then math.min(200, speed * 5) else 0
		local root = sprayAttachment.Parent
		local velocity = root.AssemblyLinearVelocity
		if velocity.Magnitude > 1 then
			-- Spray forwards, the way the skater is sliding.
			local localDirection = root.CFrame:VectorToObjectSpace(Vector3.new(velocity.X, 2, velocity.Z).Unit)
			local origin = sprayAttachment.Position
			sprayAttachment.CFrame = CFrame.lookAt(origin, origin + localDirection)
		end
	end

	-- Bob and spin the golden snowflakes.
	for part, flake in flakes do
		if not part.Parent then
			flakes[part] = nil
			continue
		end
		flake.billboard.StudsOffset = Vector3.new(0, math.sin(now * 2.5 + flake.phase) * 0.6, 0)
		flake.label.Rotation = (now * 90 + flake.phase * 57) % 360
	end
end

function Effects.init()
	createSnowfall()

	if player.Character then
		task.spawn(attachSpray, player.Character)
	end
	player.CharacterAdded:Connect(attachSpray)

	for _, part in CollectionService:GetTagged("GoldenSnowflake") do
		task.spawn(trackFlake, part)
	end
	CollectionService:GetInstanceAddedSignal("GoldenSnowflake"):Connect(trackFlake)

	Remotes.CollectiblePicked.OnClientEvent:Connect(function(position)
		burst(position, GOLD, 30, 18)
	end)

	Remotes.TrickResult.OnClientEvent:Connect(function()
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root then
			burst(root.Position - Vector3.new(0, 2.5, 0), Color3.fromRGB(170, 225, 255), 18, 12)
		end
	end)

	Remotes.Rebirthed.OnClientEvent:Connect(function()
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root then
			burst(root.Position, Color3.fromRGB(190, 130, 255), 80, 30)
		end
	end)

	RunService.RenderStepped:Connect(onRenderStep)
end

return Effects
