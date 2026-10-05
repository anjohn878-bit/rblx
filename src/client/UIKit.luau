--[[
	Tiny UI toolkit: builds Instances from tables and keeps styling consistent.

	All event hookups in the UI go through UIKit.on / UIKit.onFrame so there is one seam to fake in tests.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Theme = require(script.Parent.Theme)

local UIKit = {}

-- Construction ----------------------------------------------------------------------

-- UIKit.create("Frame", { Size = ..., Parent = parent }, { child1, child2 })
function UIKit.create(className: string, props: { [string]: any }?, children: { Instance }?): any
	local instance = Instance.new(className)
	local parent = nil
	for key, value in props or {} do
		if key == "Parent" then
			parent = value
		else
			(instance :: any)[key] = value
		end
	end
	for _, child in children or {} do
		child.Parent = instance
	end
	instance.Parent = parent -- last, so the UI only renders once fully built
	return instance
end

function UIKit.corner(radius: number): UICorner
	return UIKit.create("UICorner", { CornerRadius = UDim.new(0, radius) })
end

function UIKit.stroke(color: Color3, thickness: number, transparency: number?): UIStroke
	return UIKit.create("UIStroke", {
		Color = color,
		Thickness = thickness,
		Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	})
end

function UIKit.padding(left: number, top: number?, right: number?, bottom: number?): UIPadding
	return UIKit.create("UIPadding", {
		PaddingLeft = UDim.new(0, left),
		PaddingTop = UDim.new(0, top or left),
		PaddingRight = UDim.new(0, right or left),
		PaddingBottom = UDim.new(0, bottom or top or left),
	})
end

function UIKit.list(props: { [string]: any }?): UIListLayout
	local layout = UIKit.create("UIListLayout", props)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	return layout
end

-- A rounded dark card with a subtle outline.
function UIKit.panel(props: { [string]: any }, children: { Instance }?): Frame
	local merged = {
		BackgroundColor3 = Theme.Navy,
		BackgroundTransparency = 0.12,
		BorderSizePixel = 0,
	}
	for key, value in props do
		merged[key] = value
	end
	local frame = UIKit.create("Frame", merged, children)
	UIKit.corner(14).Parent = frame
	UIKit.stroke(Theme.NavyLighter, 1.5, 0.2).Parent = frame
	return frame
end

function UIKit.label(props: { [string]: any }): TextLabel
	local merged = {
		BackgroundTransparency = 1,
		Font = Theme.FontMedium,
		TextColor3 = Theme.Text,
		TextSize = 18,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		BorderSizePixel = 0,
	}
	for key, value in props do
		merged[key] = value
	end
	return UIKit.create("TextLabel", merged)
end

-- Clickable button with hover/press feedback. props.OnClick is called on activation.
function UIKit.button(props: { [string]: any }): TextButton
	local onClick = props.OnClick
	local base = props.BackgroundColor3 or Theme.Orange
	local merged = {
		AutoButtonColor = false,
		BackgroundColor3 = base,
		BorderSizePixel = 0,
		Font = Theme.FontBold,
		TextColor3 = Theme.Navy,
		TextSize = 18,
	}
	for key, value in props do
		if key ~= "OnClick" then
			merged[key] = value
		end
	end
	local button = UIKit.create("TextButton", merged)
	UIKit.corner(10).Parent = button

	local hover = base:Lerp(Color3.new(1, 1, 1), 0.18)
	local press = base:Lerp(Color3.new(0, 0, 0), 0.18)
	UIKit.on(button, "MouseEnter", function()
		if button:GetAttribute("Disabled") ~= true then
			UIKit.tween(button, 0.1, { BackgroundColor3 = hover })
		end
	end)
	UIKit.on(button, "MouseLeave", function()
		if button:GetAttribute("Disabled") ~= true then
			UIKit.tween(button, 0.15, { BackgroundColor3 = base })
		end
	end)
	UIKit.on(button, "MouseButton1Down", function()
		if button:GetAttribute("Disabled") ~= true then
			UIKit.tween(button, 0.06, { BackgroundColor3 = press })
		end
	end)
	UIKit.on(button, "Activated", function()
		if button:GetAttribute("Disabled") ~= true and onClick then
			onClick()
		end
	end)
	return button
end

-- Greys a button out (and ignores clicks) or restores it.
function UIKit.setButtonEnabled(button: TextButton, enabled: boolean, enabledColor: Color3)
	button:SetAttribute("Disabled", not enabled)
	button.BackgroundColor3 = enabled and enabledColor or Theme.NavyLighter
	button.TextColor3 = enabled and Theme.Navy or Theme.TextDim
end

function UIKit.createGui(name: string): ScreenGui
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local existing = playerGui:FindFirstChild(name)
	if existing then
		existing:Destroy()
	end
	return UIKit.create("ScreenGui", {
		Name = name,
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		IgnoreGuiInset = false,
		Parent = playerGui,
	})
end

-- Events / animation (the testing seam) ---------------------------------------------------

function UIKit.on(instance: Instance, signalName: string, callback: (...any) -> ()): RBXScriptConnection
	return (instance :: any)[signalName]:Connect(callback)
end

-- Runs callback(dt) every rendered frame.
function UIKit.onFrame(callback: (number) -> ()): RBXScriptConnection
	return RunService.RenderStepped:Connect(callback)
end

function UIKit.tween(instance: Instance, seconds: number, goals: { [string]: any }, style: Enum.EasingStyle?, direction: Enum.EasingDirection?)
	local info = TweenInfo.new(seconds, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out)
	local tween = TweenService:Create(instance, info, goals)
	tween:Play()
	return tween
end

-- Responsive scaling ---------------------------------------------------------------------

local scales: { UIScale } = {}

local function viewportScale(): number
	local camera = workspace.CurrentCamera
	if not camera then
		return 1
	end
	local size = camera.ViewportSize
	return math.clamp(math.min(size.X / 1280, size.Y / 720), 0.62, 1.3)
end

-- Gives a widget a UIScale that follows the screen size, so layouts designed for 1280x720 work on phones and 4K.
function UIKit.autoScale(widget: GuiObject): UIScale
	local scale = Instance.new("UIScale")
	scale.Scale = viewportScale()
	scale.Parent = widget
	table.insert(scales, scale)
	return scale
end

-- Keeps every autoScale'd widget in step with the viewport. Call once from the client entry point.
function UIKit.watchViewport()
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
		local value = viewportScale()
		for _, scale in scales do
			scale.Scale = value
		end
	end)
end

return UIKit
