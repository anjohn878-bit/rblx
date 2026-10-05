--[[
	UI
	Small helpers for building interfaces in code, plus the shared colour palette.
]]

local TweenService = game:GetService("TweenService")

local UI = {}

UI.Colors = {
	Panel = Color3.fromRGB(18, 28, 52),
	PanelLight = Color3.fromRGB(32, 46, 82),
	PanelLighter = Color3.fromRGB(45, 62, 105),
	Accent = Color3.fromRGB(110, 195, 255),
	Gold = Color3.fromRGB(255, 210, 90),
	Success = Color3.fromRGB(85, 205, 125),
	Danger = Color3.fromRGB(235, 85, 95),
	Purple = Color3.fromRGB(170, 110, 255),
	Disabled = Color3.fromRGB(70, 80, 105),
	Text = Color3.fromRGB(255, 255, 255),
	SubText = Color3.fromRGB(175, 195, 230),
	Outline = Color3.fromRGB(10, 18, 40),
}

UI.TitleFont = Enum.Font.FredokaOne
UI.BodyFont = Enum.Font.GothamBold

function UI.create(className, props, children)
	local instance = Instance.new(className)
	for key, value in props do
		if key ~= "Parent" then
			instance[key] = value
		end
	end
	if children then
		for _, child in children do
			child.Parent = instance
		end
	end
	if props.Parent then
		instance.Parent = props.Parent
	end
	return instance
end

function UI.corner(radius)
	return UI.create("UICorner", { CornerRadius = UDim.new(0, radius or 12) })
end

function UI.stroke(color, thickness, transparency)
	return UI.create("UIStroke", {
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Color = color or UI.Colors.Accent,
		Thickness = thickness or 2,
		Transparency = transparency or 0,
	})
end

function UI.textStroke(thickness)
	return UI.create("UIStroke", {
		ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
		Color = UI.Colors.Outline,
		Thickness = thickness or 2,
	})
end

function UI.padding(pixels)
	local amount = UDim.new(0, pixels)
	return UI.create(
		"UIPadding",
		{ PaddingTop = amount, PaddingBottom = amount, PaddingLeft = amount, PaddingRight = amount }
	)
end

function UI.maxText(size)
	return UI.create("UITextSizeConstraint", { MaxTextSize = size })
end

function UI.label(props, children)
	local defaults = {
		BackgroundTransparency = 1,
		Font = UI.TitleFont,
		TextColor3 = UI.Colors.Text,
		TextScaled = true,
	}
	for key, value in props do
		defaults[key] = value
	end
	return UI.create("TextLabel", defaults, children)
end

function UI.button(props, children)
	local defaults = {
		AutoButtonColor = true,
		BackgroundColor3 = UI.Colors.Accent,
		Font = UI.TitleFont,
		TextColor3 = UI.Colors.Text,
		TextScaled = true,
	}
	for key, value in props do
		defaults[key] = value
	end
	local button = UI.create("TextButton", defaults, children)
	if not button:FindFirstChildOfClass("UICorner") then
		UI.corner(10).Parent = button
	end

	-- A little squish when pressed.
	local scale = UI.create("UIScale", { Parent = button })
	button.MouseButton1Down:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.08), { Scale = 0.93 }):Play()
	end)
	local function release()
		TweenService:Create(scale, TweenInfo.new(0.15, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	end
	button.MouseButton1Up:Connect(release)
	button.MouseLeave:Connect(release)
	return button
end

function UI.tween(instance, duration, goals, style, direction)
	local tween = TweenService:Create(
		instance,
		TweenInfo.new(duration, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out),
		goals
	)
	tween:Play()
	return tween
end

return UI
