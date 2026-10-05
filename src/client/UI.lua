-- Tiny helpers for building the interface in code.

local TweenService = game:GetService("TweenService")

local UI = {}

UI.Colors = {
	Panel = Color3.fromRGB(255, 248, 230),
	PanelDark = Color3.fromRGB(245, 232, 200),
	Wood = Color3.fromRGB(120, 85, 50),
	Header = Color3.fromRGB(90, 165, 75),
	Text = Color3.fromRGB(60, 45, 30),
	SubText = Color3.fromRGB(120, 100, 80),
	Green = Color3.fromRGB(90, 190, 80),
	Grey = Color3.fromRGB(170, 170, 170),
	Red = Color3.fromRGB(215, 75, 75),
	Gold = Color3.fromRGB(255, 205, 60),
	White = Color3.new(1, 1, 1),
}

UI.TitleFont = Enum.Font.FredokaOne
UI.BodyFont = Enum.Font.GothamBold

-- UI.new("Frame", { Size = ..., Parent = ... }, { child1, child2 })
function UI.new(className, props, children)
	local instance = Instance.new(className)
	local parent
	for key, value in pairs(props or {}) do
		if key == "Parent" then
			parent = value
		else
			instance[key] = value
		end
	end
	for _, child in ipairs(children or {}) do
		child.Parent = instance
	end
	if parent then
		instance.Parent = parent
	end
	return instance
end

function UI.corner(radius)
	return UI.new("UICorner", { CornerRadius = UDim.new(0, radius or 12) })
end

function UI.stroke(color, thickness)
	return UI.new("UIStroke", {
		Color = color or UI.Colors.Wood,
		Thickness = thickness or 3,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	})
end

function UI.padding(pixels)
	local p = UDim.new(0, pixels)
	return UI.new("UIPadding", { PaddingTop = p, PaddingBottom = p, PaddingLeft = p, PaddingRight = p })
end

function UI.label(props)
	local defaults = {
		BackgroundTransparency = 1,
		Font = UI.BodyFont,
		TextColor3 = UI.Colors.Text,
		TextScaled = true,
		Text = "",
	}
	for key, value in pairs(props) do
		defaults[key] = value
	end
	return UI.new("TextLabel", defaults)
end

-- A chunky button that squishes when pressed.
function UI.button(props, onClick)
	local defaults = {
		BackgroundColor3 = UI.Colors.Green,
		Font = UI.TitleFont,
		TextColor3 = UI.Colors.White,
		TextScaled = true,
		AutoButtonColor = true,
		Text = "",
	}
	for key, value in pairs(props) do
		defaults[key] = value
	end
	local button = UI.new("TextButton", defaults, { UI.corner(10) })
	local scale = UI.new("UIScale", { Parent = button })
	button.MouseButton1Down:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.08), { Scale = 0.92 }):Play()
	end)
	local function release()
		TweenService:Create(scale, TweenInfo.new(0.12, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	end
	button.MouseButton1Up:Connect(release)
	button.MouseLeave:Connect(release)
	if onClick then
		button.Activated:Connect(onClick)
	end
	return button
end

-- A pop animation used when numbers change.
function UI.pop(guiObject)
	local scale = guiObject:FindFirstChildOfClass("UIScale") or UI.new("UIScale", { Parent = guiObject })
	scale.Scale = 1.15
	TweenService:Create(scale, TweenInfo.new(0.25, Enum.EasingStyle.Back), { Scale = 1 }):Play()
end

-- Standard modal window with a header and a close button.
-- Returns window, body, headerRight (a label on the right of the header).
function UI.window(parent, title, onClose)
	local window = UI.new("Frame", {
		Name = title,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.92, 0.8),
		BackgroundColor3 = UI.Colors.Panel,
		Visible = false,
		Parent = parent,
	}, {
		UI.corner(16),
		UI.stroke(UI.Colors.Wood, 4),
		UI.new("UISizeConstraint", { MaxSize = Vector2.new(640, 500) }),
	})

	local header = UI.new("Frame", {
		Name = "Header",
		Size = UDim2.new(1, 0, 0, 50),
		BackgroundColor3 = UI.Colors.Header,
		Parent = window,
	}, { UI.corner(16) })
	-- square off the bottom corners of the header
	UI.new("Frame", {
		Size = UDim2.new(1, 0, 0, 16),
		Position = UDim2.new(0, 0, 1, -16),
		BackgroundColor3 = UI.Colors.Header,
		BorderSizePixel = 0,
		Parent = header,
	})

	UI.label({
		Name = "Title",
		Text = title,
		Font = UI.TitleFont,
		TextColor3 = UI.Colors.White,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.new(0, 16, 0, 8),
		Size = UDim2.new(0.5, -16, 0, 34),
		Parent = header,
	})

	local headerRight = UI.label({
		Name = "Info",
		Text = "",
		TextColor3 = UI.Colors.White,
		TextXAlignment = Enum.TextXAlignment.Right,
		Position = UDim2.new(0.5, 0, 0, 13),
		Size = UDim2.new(0.5, -66, 0, 24),
		Parent = header,
	})

	UI.button({
		Name = "Close",
		Text = "X",
		BackgroundColor3 = UI.Colors.Red,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -8, 0, 7),
		Size = UDim2.fromOffset(36, 36),
		Parent = header,
	}, onClose)

	local body = UI.new("ScrollingFrame", {
		Name = "Body",
		Position = UDim2.new(0, 10, 0, 60),
		Size = UDim2.new(1, -20, 1, -70),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 8,
		ScrollBarImageColor3 = UI.Colors.Wood,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		Parent = window,
	})

	return window, body, headerRight
end

return UI
