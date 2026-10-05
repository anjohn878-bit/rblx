--[[
	GuideController
	A glowing trail from your character to a target plus a bouncing arrow
	above it. Used by the tutorial and the "GO!" button.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local UIKit = require(script.Parent.Parent.UI.UIKit)
local Theme = UIKit.Theme

local GuideController = {}

local player = Players.LocalPlayer
local current: { Target: Instance, Cleanup: () -> () }? = nil

local function targetPart(target: Instance): BasePart?
	if target:IsA("BasePart") then
		return target
	elseif target:IsA("Model") then
		return target.PrimaryPart or target:FindFirstChild("HumanoidRootPart") :: BasePart? or target:FindFirstChildWhichIsA("BasePart")
	end
	return nil
end

function GuideController.Clear()
	if current then
		current.Cleanup()
		current = nil
	end
end

function GuideController.GetTarget(): Instance?
	return current and current.Target
end

-- Points at `target` until cleared, the target disappears, or `duration` ends.
function GuideController.PointTo(target: Instance, duration: number?)
	if current and current.Target == target then
		return
	end
	GuideController.Clear()
	local part = targetPart(target)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not part or not root then
		return
	end

	local a0 = Instance.new("Attachment")
	a0.Name = "GuideStart"
	a0.Position = Vector3.new(0, -1.5, 0)
	a0.Parent = root
	local a1 = Instance.new("Attachment")
	a1.Name = "GuideEnd"
	a1.Parent = part

	local beam = Instance.new("Beam")
	beam.Attachment0 = a0
	beam.Attachment1 = a1
	beam.Color = ColorSequence.new(Theme.Colors.Yellow)
	beam.LightEmission = 1
	beam.LightInfluence = 0
	beam.Transparency = NumberSequence.new(0.15)
	beam.Width0 = 0.9
	beam.Width1 = 0.9
	beam.FaceCamera = true
	beam.Segments = 24
	beam.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	beam.TextureMode = Enum.TextureMode.Wrap
	beam.TextureLength = 2
	beam.TextureSpeed = 2
	beam.Parent = root

	local billboard = UIKit.New("BillboardGui", {
		Name = "GuideArrow",
		Adornee = part,
		Size = UDim2.fromOffset(80, 80),
		StudsOffset = Vector3.new(0, 5, 0),
		AlwaysOnTop = true,
		LightInfluence = 0,
		Parent = player:WaitForChild("PlayerGui"),
	})
	local arrow = UIKit.Label({
		Text = "⬇️",
		TextSize = 60,
		Size = UDim2.fromScale(1, 1),
		Parent = billboard,
	})

	local bounce = RunService.RenderStepped:Connect(function()
		arrow.Position = UDim2.fromOffset(0, math.sin(os.clock() * 6) * 8)
	end)

	local connections: { RBXScriptConnection } = { bounce }
	local function cleanup()
		for _, connection in connections do
			connection:Disconnect()
		end
		beam:Destroy()
		a0:Destroy()
		a1:Destroy()
		billboard:Destroy()
	end
	local handle = { Target = target, Cleanup = cleanup }
	current = handle

	table.insert(
		connections,
		target.AncestryChanged:Connect(function(_, parent)
			if parent == nil and current == handle then
				GuideController.Clear()
			end
		end)
	)
	table.insert(
		connections,
		root.AncestryChanged:Connect(function(_, parent)
			if parent == nil and current == handle then
				GuideController.Clear()
			end
		end)
	)
	if duration then
		task.delay(duration, function()
			if current == handle then
				GuideController.Clear()
			end
		end)
	end
end

function GuideController.Init() end

return GuideController
