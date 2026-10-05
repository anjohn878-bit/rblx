--[[
	EffectsController
	Juice: floating "+$45" popups, sparkle bursts, confetti and camera shake.
	Triggered by the server's Effect remote and by other controllers.
]]

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Rarities = require(Shared:WaitForChild("Config"):WaitForChild("Rarities"))
local Format = require(Shared:WaitForChild("Util"):WaitForChild("Format"))
local UIKit = require(script.Parent.Parent.UI.UIKit)
local Theme = UIKit.Theme

local EffectsController = {}

local controllers: any = nil
local player = Players.LocalPlayer
local confettiGui: ScreenGui

local CONFETTI_COLORS = {
	Color3.fromRGB(255, 90, 90),
	Color3.fromRGB(255, 205, 60),
	Color3.fromRGB(90, 210, 110),
	Color3.fromRGB(80, 160, 255),
	Color3.fromRGB(190, 110, 255),
	Color3.fromRGB(255, 150, 210),
}

function EffectsController.Init(all: any)
	controllers = all
	confettiGui = UIKit.New("ScreenGui", {
		Name = "Confetti",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 30,
		Parent = player:WaitForChild("PlayerGui"),
	})
end

-- Floating text in the world that rises and fades.
function EffectsController.WorldPopup(position: Vector3, text: string, color: Color3?, size: number?)
	local attachment = Instance.new("Attachment")
	attachment.WorldPosition = position
	attachment.Parent = workspace.Terrain

	local billboard = UIKit.New("BillboardGui", {
		Adornee = attachment,
		Size = UDim2.fromOffset(260, 70),
		AlwaysOnTop = true,
		LightInfluence = 0,
		MaxDistance = 250,
		StudsOffsetWorldSpace = Vector3.zero,
		Parent = player:WaitForChild("PlayerGui"),
	})
	local label = UIKit.Label({
		Text = text,
		TextSize = size or 40,
		TextColor3 = color or Theme.Colors.Money,
		Size = UDim2.fromScale(1, 1),
		Parent = billboard,
	})
	UIKit.TextStroke(3).Parent = label
	UIKit.PopIn(label, 0.3)
	UIKit.Tween(billboard, 1.6, { StudsOffsetWorldSpace = Vector3.new(0, 6, 0) }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	task.delay(1, function()
		UIKit.Tween(label, 0.6, { TextTransparency = 1 })
		local stroke = label:FindFirstChildOfClass("UIStroke")
		if stroke then
			UIKit.Tween(stroke, 0.6, { Transparency = 1 })
		end
	end)
	Debris:AddItem(billboard, 1.8)
	Debris:AddItem(attachment, 1.8)
end

-- Particle burst at a world position.
function EffectsController.Burst(position: Vector3, color: Color3?, amount: number?)
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Transparency = 1
	part.Size = Vector3.new(1, 1, 1)
	part.CFrame = CFrame.new(position)
	part.Parent = workspace

	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = ColorSequence.new(color or Theme.Colors.Yellow)
	emitter.LightEmission = 0.8
	emitter.Rate = 0
	emitter.Lifetime = NumberRange.new(0.6, 1.2)
	emitter.Speed = NumberRange.new(12, 24)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Acceleration = Vector3.new(0, -25, 0)
	emitter.Drag = 2
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.8),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Parent = part
	emitter:Emit(amount or 40)
	Debris:AddItem(part, 2)
end

-- Screen confetti rain.
function EffectsController.Confetti(count: number?)
	local camera = workspace.CurrentCamera
	local width = if camera then camera.ViewportSize.X else 1280
	for _ = 1, count or 70 do
		local piece = UIKit.New("Frame", {
			Size = UDim2.fromOffset(math.random(8, 16), math.random(12, 22)),
			Position = UDim2.new(math.random(), 0, 0, -30 - math.random(0, 200)),
			Rotation = math.random(0, 360),
			BackgroundColor3 = CONFETTI_COLORS[math.random(1, #CONFETTI_COLORS)],
			BorderSizePixel = 0,
			Parent = confettiGui,
		})
		local duration = 1.6 + math.random() * 1.4
		local drift = (math.random() - 0.5) * width * 0.2
		UIKit.Tween(piece, duration, {
			Position = UDim2.new(piece.Position.X.Scale, drift, 1, 40),
			Rotation = piece.Rotation + math.random(-400, 400),
		}, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		Debris:AddItem(piece, duration + 0.1)
	end
end

function EffectsController.Shake(intensity: number?, duration: number?)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	local strength = intensity or 0.4
	local endsAt = os.clock() + (duration or 0.4)
	local connection
	connection = RunService.RenderStepped:Connect(function()
		if os.clock() > endsAt or not humanoid.Parent then
			humanoid.CameraOffset = Vector3.zero
			connection:Disconnect()
			return
		end
		humanoid.CameraOffset = Vector3.new((math.random() - 0.5) * strength, (math.random() - 0.5) * strength, 0)
	end)
end

local function onEffect(effect: any)
	if type(effect) ~= "table" then
		return
	end
	local kind = effect.Type
	local position = effect.Position
	if kind == "Treated" then
		local rarity = Rarities.ById[effect.Rarity or "Common"]
		local big = effect.Manual or (rarity and rarity.Stars >= 2)
		local color = if rarity and rarity.Stars >= 2 then rarity.Color else Theme.Colors.Money
		if typeof(position) == "Vector3" then
			EffectsController.WorldPopup(position, "+" .. Format.Money(effect.Amount), color, if big then 46 else 34)
			if effect.Pharmacy and effect.Pharmacy > 0 then
				task.delay(0.35, function()
					EffectsController.WorldPopup(position + Vector3.new(1.5, -1, 0), "+" .. Format.Money(effect.Pharmacy) .. " 💊", Theme.Colors.Teal, 28)
				end)
			end
			if big then
				EffectsController.Burst(position, color, 25)
			end
		end
		controllers.SoundController.Play("Cash", 0.9 + math.random() * 0.25)
		controllers.HUDController.FlashMoney((effect.Amount or 0) + (effect.Pharmacy or 0))
	elseif kind == "HospitalUpgraded" then
		EffectsController.Confetti(110)
		EffectsController.Shake(0.6, 0.5)
		if typeof(position) == "Vector3" then
			EffectsController.Burst(position + Vector3.new(0, 12, 0), Theme.Colors.Yellow, 120)
		end
		controllers.SoundController.Play("Upgrade")
	elseif kind == "RoomUnlocked" then
		if typeof(position) == "Vector3" then
			EffectsController.Burst(position, Theme.Colors.Teal, 80)
			EffectsController.WorldPopup(position + Vector3.new(0, 4, 0), "✨ UNLOCKED! ✨", Theme.Colors.Yellow, 40)
		end
		EffectsController.Confetti(50)
		controllers.SoundController.Play("Upgrade")
	elseif kind == "DoctorHired" then
		if typeof(position) == "Vector3" then
			EffectsController.Burst(position, Theme.Colors.Blue, 60)
			EffectsController.WorldPopup(position + Vector3.new(0, 4, 0), "🤖 NEW DOCTOR!", Theme.Colors.Blue, 36)
		end
		controllers.SoundController.Play("Purchase")
	elseif kind == "DoctorLevelUp" then
		EffectsController.Confetti(80)
		controllers.SoundController.Play("LevelUp")
	elseif kind == "Improvement" then
		controllers.SoundController.Play("Purchase", 1.2)
	end
end

function EffectsController.Start()
	Remotes.Event("Effect").OnClientEvent:Connect(onEffect)
end

return EffectsController
