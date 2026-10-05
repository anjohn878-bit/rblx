--[[
	Shows where to go:
	  * an arrow at the top of the screen that always points at the target, with the distance
	  * for a delivery, a glowing ring + light beam + address label at the destination (client-side
	    only, so each player sees just their own)
	  * a particle burst when a delivery completes
]]

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Theme = require(script.Parent.Theme)
local UIKit = require(script.Parent.UIKit)

local Waypoint = {}

local player = Players.LocalPlayer

local function markerPart(parent: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3, transparency: number, shape: Enum.PartType?): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	part.Color = color
	part.Transparency = transparency
	part.Shape = shape or Enum.PartType.Block
	part.Size = size
	part.CFrame = cframe
	part.Parent = parent
	return part
end

-- The glowing ring/beam at a delivery address. Returns the folder and the ring (for pulsing).
local function buildMarker(position: Vector3, address: string)
	local folder = Instance.new("Folder")
	folder.Name = "OrderMarker"

	local diameter = Config.DeliveryRadius * 2
	-- A cylinder's axis is X, so turn it 90 degrees to lie flat on the road.
	local flat = CFrame.new(position + Vector3.new(0, 0.4, 0)) * CFrame.Angles(0, 0, math.rad(90))
	local ring = markerPart(folder, "Ring", Vector3.new(0.4, diameter, diameter), flat, Theme.Orange, 0.5, Enum.PartType.Cylinder)
	markerPart(folder, "Core", Vector3.new(0.45, diameter * 0.55, diameter * 0.55), flat, Theme.Yellow, 0.6, Enum.PartType.Cylinder)
	markerPart(folder, "Beacon", Vector3.new(3, 140, 3), CFrame.new(position + Vector3.new(0, 70, 0)), Theme.Orange, 0.72)

	local anchor = markerPart(folder, "LabelAnchor", Vector3.new(1, 1, 1), CFrame.new(position + Vector3.new(0, 26, 0)), Theme.Orange, 1)
	local billboard = Instance.new("BillboardGui")
	billboard.Adornee = anchor
	billboard.Size = UDim2.fromOffset(260, 64)
	billboard.AlwaysOnTop = true
	billboard.LightInfluence = 0
	billboard.Parent = anchor
	UIKit.panel({
		Size = UDim2.fromScale(1, 1),
		Parent = billboard,
	}, {
		UIKit.label({
			Size = UDim2.fromScale(1, 1),
			Font = Theme.FontBold,
			TextSize = 24,
			TextXAlignment = Enum.TextXAlignment.Center,
			Text = address,
		}),
	})

	folder.Parent = Workspace
	return folder, ring
end

function Waypoint.build(gui: ScreenGui)
	local widget = UIKit.create("Frame", {
		Name = "Waypoint",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 58),
		Size = UDim2.fromOffset(300, 100),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = gui,
	})
	UIKit.autoScale(widget)

	-- The arrow: a rotated square for the head plus a bar for the shaft; the frame rotates as a whole.
	local arrow = UIKit.create("Frame", {
		Name = "Arrow",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0, 34),
		Size = UDim2.fromOffset(56, 56),
		BackgroundTransparency = 1,
		Parent = widget,
	})
	UIKit.create("Frame", {
		Name = "Shaft",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.42),
		Size = UDim2.fromOffset(12, 28),
		BackgroundColor3 = Theme.Orange,
		BorderSizePixel = 0,
		Parent = arrow,
	}, { UIKit.corner(4) })
	UIKit.create("Frame", {
		Name = "Head",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.3),
		Size = UDim2.fromOffset(26, 26),
		Rotation = 45,
		BackgroundColor3 = Theme.Orange,
		BorderSizePixel = 0,
		Parent = arrow,
	}, { UIKit.corner(4) })

	local caption = UIKit.label({
		Name = "Caption",
		Position = UDim2.new(0, 0, 0, 70),
		Size = UDim2.new(1, 0, 0, 24),
		Font = Theme.FontBold,
		TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextStrokeTransparency = 0.5,
		Text = "",
		Parent = widget,
	})

	local target = nil -- { Position, Label, HideWithin }
	local markerFolder, markerRing = nil, nil

	local function removeMarker()
		if markerFolder then
			markerFolder:Destroy()
			markerFolder, markerRing = nil, nil
		end
	end

	local waypoint = {}

	-- target: { Position: Vector3, Label: string, HideWithin: number } or nil. withMarker draws the 3D ring.
	function waypoint.setTarget(newTarget, withMarker: boolean?)
		removeMarker()
		target = newTarget
		if target and withMarker then
			markerFolder, markerRing = buildMarker(target.Position, target.Label)
		end
		if not target then
			widget.Visible = false
		end
	end

	-- Points the arrow; split out so it can be tested. Returns the rotation in degrees.
	function waypoint.update()
		if not target then
			return nil
		end
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local camera = Workspace.CurrentCamera
		if not root or not camera then
			return nil
		end

		local delta = target.Position - root.Position
		local flatDelta = Vector3.new(delta.X, 0, delta.Z)
		local distance = flatDelta.Magnitude
		widget.Visible = distance > (target.HideWithin or 0)

		local look = camera.CFrame.LookVector
		local flatLook = Vector3.new(look.X, 0, look.Z)
		flatLook = flatLook.Magnitude > 1e-3 and flatLook.Unit or Vector3.new(0, 0, -1)
		local right = flatLook:Cross(Vector3.yAxis)
		local degrees = math.deg(math.atan2(flatDelta:Dot(right), flatDelta:Dot(flatLook)))
		arrow.Rotation = degrees
		caption.Text = string.format("%s  -  %d studs", target.Label, math.floor(distance + 0.5))

		if markerRing then
			markerRing.Transparency = 0.5 + 0.15 * math.sin(os.clock() * 4)
		end
		return degrees
	end

	UIKit.onFrame(waypoint.update)

	-- Confetti-style burst at a position.
	function waypoint.celebrate(position: Vector3)
		local anchor = Instance.new("Part")
		anchor.Anchored = true
		anchor.CanCollide = false
		anchor.CanQuery = false
		anchor.CanTouch = false
		anchor.Transparency = 1
		anchor.Size = Vector3.new(1, 1, 1)
		anchor.CFrame = CFrame.new(position + Vector3.new(0, 3, 0))
		anchor.Parent = Workspace

		local emitter = Instance.new("ParticleEmitter")
		emitter.Rate = 0
		emitter.Lifetime = NumberRange.new(0.9, 1.6)
		emitter.Speed = NumberRange.new(24, 48)
		emitter.SpreadAngle = Vector2.new(180, 180)
		emitter.Acceleration = Vector3.new(0, -60, 0)
		emitter.Color = ColorSequence.new(Theme.Orange, Theme.Green)
		emitter.Size = NumberSequence.new(1.4, 0)
		emitter.LightEmission = 0.6
		emitter.Parent = anchor
		emitter:Emit(60)
		Debris:AddItem(anchor, 3)
	end

	-- Exposed for tests.
	waypoint.Widget = widget
	waypoint.Arrow = arrow
	waypoint.Caption = caption
	waypoint.hasMarker = function()
		return markerFolder ~= nil
	end
	return waypoint
end

return Waypoint
