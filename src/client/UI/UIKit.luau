--[[
	UIKit
	Tiny declarative helpers for building the UI from code, plus shared
	animations (pop-in, button bounce) and resolution scaling.
]]

local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Theme = require(script.Parent.Theme)

local UIKit = {}
UIKit.Theme = Theme

local scales: { UIScale } = {}
local currentScale = 1
local clickSound: (() -> ())? = nil

-- Creates an instance, assigns properties and parents children.
-- Properties are a plain table; `Children` is an optional array.
function UIKit.New(className: string, props: { [string]: any }?, children: { Instance }?): any
	local instance = Instance.new(className :: any)
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
	if parent then
		instance.Parent = parent
	end
	return instance
end

function UIKit.Corner(radius: number?): UICorner
	return UIKit.New("UICorner", { CornerRadius = UDim.new(0, radius or 12) })
end

function UIKit.Stroke(thickness: number?, color: Color3?, mode: Enum.ApplyStrokeMode?): UIStroke
	return UIKit.New("UIStroke", {
		Thickness = thickness or 3,
		Color = color or Theme.Colors.Stroke,
		ApplyStrokeMode = mode or Enum.ApplyStrokeMode.Border,
	})
end

function UIKit.TextStroke(thickness: number?, color: Color3?): UIStroke
	return UIKit.New("UIStroke", {
		Thickness = thickness or 2,
		Color = color or Theme.Colors.Stroke,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
	})
end

function UIKit.Padding(all: number, horizontal: number?): UIPadding
	local h = horizontal or all
	return UIKit.New("UIPadding", {
		PaddingTop = UDim.new(0, all),
		PaddingBottom = UDim.new(0, all),
		PaddingLeft = UDim.new(0, h),
		PaddingRight = UDim.new(0, h),
	})
end

function UIKit.Gradient(top: Color3, bottom: Color3, rotation: number?): UIGradient
	return UIKit.New("UIGradient", {
		Color = ColorSequence.new(top, bottom),
		Rotation = rotation or 90,
	})
end

function UIKit.List(direction: Enum.FillDirection?, padding: number?, hAlign: Enum.HorizontalAlignment?, vAlign: Enum.VerticalAlignment?): UIListLayout
	return UIKit.New("UIListLayout", {
		FillDirection = direction or Enum.FillDirection.Vertical,
		Padding = UDim.new(0, padding or 8),
		HorizontalAlignment = hAlign or Enum.HorizontalAlignment.Center,
		VerticalAlignment = vAlign or Enum.VerticalAlignment.Top,
		SortOrder = Enum.SortOrder.LayoutOrder,
	})
end

function UIKit.Label(props: { [string]: any }): TextLabel
	local defaults = {
		BackgroundTransparency = 1,
		Font = Theme.Font,
		TextColor3 = Theme.Colors.White,
		TextSize = 22,
		Text = "",
	}
	for key, value in props do
		defaults[key] = value
	end
	return UIKit.New("TextLabel", defaults)
end

function UIKit.Tween(instance: Instance, duration: number, goal: { [string]: any }, style: Enum.EasingStyle?, direction: Enum.EasingDirection?): Tween
	local tween = TweenService:Create(instance, TweenInfo.new(duration, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out), goal)
	tween:Play()
	return tween
end

-- Pops a GuiObject in with a bouncy scale animation.
function UIKit.PopIn(object: GuiObject, duration: number?)
	local scale = object:FindFirstChild("PopScale") :: UIScale?
	if not scale then
		scale = UIKit.New("UIScale", { Name = "PopScale", Parent = object })
	end
	local popScale = scale :: UIScale
	popScale.Scale = 0.6
	UIKit.Tween(popScale, duration or 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
end

function UIKit.Bounce(object: GuiObject, amount: number?)
	local scale = object:FindFirstChild("PopScale") :: UIScale?
	if not scale then
		scale = UIKit.New("UIScale", { Name = "PopScale", Parent = object })
	end
	local popScale = scale :: UIScale
	popScale.Scale = amount or 1.15
	UIKit.Tween(popScale, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)
end

function UIKit.Shake(object: GuiObject)
	local origin = object.Position
	task.spawn(function()
		for i = 1, 6 do
			local offset = if i % 2 == 0 then -8 else 8
			object.Position = origin + UDim2.fromOffset(offset * (1 - i / 7), 0)
			task.wait(0.04)
		end
		object.Position = origin
	end)
end

function UIKit.SetClickSound(callback: () -> ())
	clickSound = callback
end

export type ButtonProps = {
	Text: string,
	Color: Color3?,
	DarkColor: Color3?,
	Size: UDim2?,
	Position: UDim2?,
	AnchorPoint: Vector2?,
	TextSize: number?,
	LayoutOrder: number?,
	Parent: Instance?,
	Name: string?,
	RichText: boolean?,
	OnClick: (() -> ())?,
}

-- Chunky cartoon button with hover + press feedback.
-- The gradient lives on a child "Fill" frame so it never tints the text.
function UIKit.Button(props: ButtonProps): TextButton
	local color = props.Color or Theme.Colors.Green
	local dark = props.DarkColor or color:Lerp(Color3.new(0, 0, 0), 0.3)
	local button = UIKit.New("TextButton", {
		Name = props.Name or "Button",
		Size = props.Size or UDim2.fromOffset(160, 50),
		Position = props.Position or UDim2.new(),
		AnchorPoint = props.AnchorPoint or Vector2.zero,
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		Text = "",
		LayoutOrder = props.LayoutOrder or 0,
	})
	UIKit.New("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		ZIndex = 1,
		Parent = button,
	}, {
		UIKit.Corner(12),
		UIKit.Stroke(3, Theme.Colors.Stroke),
		UIKit.New("UIGradient", { Name = "Gradient", Color = ColorSequence.new(color, dark), Rotation = 90 }),
	})
	UIKit.New("TextLabel", {
		Name = "Label",
		Size = UDim2.new(1, -8, 1, 0),
		Position = UDim2.fromOffset(4, 0),
		BackgroundTransparency = 1,
		Text = props.Text,
		RichText = props.RichText or false,
		Font = Theme.Font,
		TextSize = props.TextSize or 22,
		TextColor3 = Theme.Colors.White,
		TextWrapped = true,
		ZIndex = 2,
		Parent = button,
	}, {
		UIKit.New("UIStroke", {
			Name = "TextOutline",
			Thickness = 2,
			Color = dark:Lerp(Color3.new(0, 0, 0), 0.4),
			ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
		}),
	})
	local scale = UIKit.New("UIScale", { Name = "PopScale", Parent = button })
	button.MouseEnter:Connect(function()
		UIKit.Tween(scale, 0.12, { Scale = 1.06 })
	end)
	button.MouseLeave:Connect(function()
		UIKit.Tween(scale, 0.12, { Scale = 1 })
	end)
	button.MouseButton1Down:Connect(function()
		UIKit.Tween(scale, 0.08, { Scale = 0.93 })
	end)
	button.MouseButton1Up:Connect(function()
		UIKit.Tween(scale, 0.15, { Scale = 1 }, Enum.EasingStyle.Back)
	end)
	if props.OnClick then
		local callback = props.OnClick
		button.Activated:Connect(function()
			if clickSound then
				clickSound()
			end
			callback()
		end)
	end
	if props.Parent then
		button.Parent = props.Parent
	end
	return button
end

function UIKit.SetButtonColor(button: GuiObject, color: Color3, dark: Color3?)
	local darkColor = dark or color:Lerp(Color3.new(0, 0, 0), 0.3)
	local fill = button:FindFirstChild("Fill")
	local gradient = fill and fill:FindFirstChild("Gradient") :: UIGradient?
	if gradient then
		gradient.Color = ColorSequence.new(color, darkColor)
	end
	local label = button:FindFirstChild("Label")
	local outline = label and label:FindFirstChild("TextOutline") :: UIStroke?
	if outline then
		outline.Color = darkColor:Lerp(Color3.new(0, 0, 0), 0.4)
	end
end

function UIKit.SetButtonText(button: GuiObject, text: string)
	local label = button:FindFirstChild("Label") :: TextLabel?
	if label then
		label.Text = text
	end
end

-- Registers a container so it scales with the screen size (designed at 1280x760).
function UIKit.Scaled(object: GuiObject): UIScale
	local scale = UIKit.New("UIScale", { Name = "ScreenScale", Scale = currentScale, Parent = object })
	table.insert(scales, scale)
	return scale
end

function UIKit.GetScale(): number
	return currentScale
end

local function updateScale()
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	local viewport = camera.ViewportSize
	currentScale = math.clamp(math.min(viewport.X / 1280, viewport.Y / 760), 0.5, 1.2)
	for i = #scales, 1, -1 do
		local scale = scales[i]
		if scale.Parent then
			scale.Scale = currentScale
		else
			table.remove(scales, i)
		end
	end
end

function UIKit.Init()
	local function hook()
		local camera = Workspace.CurrentCamera
		if camera then
			camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale)
		end
		updateScale()
	end
	Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(hook)
	hook()
end

-- Modal panel with a coloured header and a close button.
export type PanelProps = {
	Name: string,
	Title: string,
	Size: Vector2,
	Color: Color3?,
	Parent: Instance,
	OnClose: (() -> ())?,
}

function UIKit.Panel(props: PanelProps): (Frame, Frame, TextLabel)
	local color = props.Color or Theme.Colors.Blue
	local panel = UIKit.New("Frame", {
		Name = props.Name,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(props.Size.X, props.Size.Y),
		BackgroundColor3 = Theme.Colors.Panel,
		Visible = false,
		Parent = props.Parent,
	}, {
		UIKit.Corner(20),
		UIKit.Stroke(4, Theme.Colors.Stroke),
	})
	UIKit.Scaled(panel)

	local header = UIKit.New("Frame", {
		Name = "Header",
		Size = UDim2.new(1, 0, 0, 64),
		BackgroundColor3 = Color3.new(1, 1, 1),
		Parent = panel,
	}, {
		UIKit.Corner(20),
		UIKit.Gradient(color, color:Lerp(Color3.new(0, 0, 0), 0.25)),
	})
	-- Square off the header's bottom corners
	UIKit.New("Frame", {
		Size = UDim2.new(1, 0, 0, 20),
		Position = UDim2.new(0, 0, 1, -20),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		Parent = header,
	}, {
		UIKit.Gradient(color:Lerp(Color3.new(0, 0, 0), 0.18), color:Lerp(Color3.new(0, 0, 0), 0.25)),
	})
	local title = UIKit.Label({
		Name = "Title",
		Text = props.Title,
		TextSize = 34,
		Size = UDim2.new(1, -140, 1, 0),
		Position = UDim2.fromOffset(24, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 2,
		Parent = header,
	})
	UIKit.TextStroke(3).Parent = title

	UIKit.Button({
		Name = "Close",
		Text = "✖",
		Color = Theme.Colors.Red,
		Size = UDim2.fromOffset(48, 48),
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -10, 0.5, 0),
		TextSize = 26,
		Parent = header,
		OnClick = function()
			if props.OnClose then
				props.OnClose()
			end
		end,
	})

	local content = UIKit.New("Frame", {
		Name = "Content",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 64),
		Size = UDim2.new(1, 0, 1, -64),
		Parent = panel,
	})
	return panel, content, title
end

return UIKit
