--[[
	UIKit
	Tiny helpers + the Concrete Kings visual identity: charcoal glass panels,
	volt-green accent, ember-orange secondary, heavy condensed type.
]]

local TweenService = game:GetService("TweenService")

local UIKit = {}

UIKit.Theme = {
	Bg = Color3.fromRGB(14, 15, 19),
	Panel = Color3.fromRGB(22, 24, 30),
	PanelLight = Color3.fromRGB(34, 37, 46),
	Stroke = Color3.fromRGB(60, 64, 76),
	Text = Color3.fromRGB(245, 246, 250),
	Muted = Color3.fromRGB(150, 155, 170),
	Accent = Color3.fromRGB(205, 255, 64),
	AccentDark = Color3.fromRGB(26, 32, 8),
	Secondary = Color3.fromRGB(255, 110, 54),
	Danger = Color3.fromRGB(255, 72, 88),
	Gold = Color3.fromRGB(240, 196, 70),
	Heavy = Enum.Font.GothamBlack,
	Bold = Enum.Font.GothamBold,
	Medium = Enum.Font.GothamMedium,
}

local T = UIKit.Theme

function UIKit.new(className: string, props, children)
	local inst = Instance.new(className)
	if inst:IsA("GuiObject") then
		(inst :: GuiObject).BorderSizePixel = 0
	end
	for k, v in props or {} do
		if k ~= "Parent" then
			(inst :: any)[k] = v
		end
	end
	for _, child in children or {} do
		child.Parent = inst
	end
	if props and props.Parent then
		inst.Parent = props.Parent
	end
	return inst
end

function UIKit.Corner(radius: number?)
	return UIKit.new("UICorner", { CornerRadius = UDim.new(0, radius or 10) })
end

function UIKit.Stroke(color: Color3?, thickness: number?, transparency: number?)
	return UIKit.new("UIStroke", {
		Color = color or T.Stroke,
		Thickness = thickness or 1,
		Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	})
end

function UIKit.Padding(px: number)
	return UIKit.new("UIPadding", {
		PaddingTop = UDim.new(0, px),
		PaddingBottom = UDim.new(0, px),
		PaddingLeft = UDim.new(0, px),
		PaddingRight = UDim.new(0, px),
	})
end

function UIKit.List(direction: Enum.FillDirection?, padding: number?, align: Enum.HorizontalAlignment?)
	return UIKit.new("UIListLayout", {
		FillDirection = direction or Enum.FillDirection.Vertical,
		Padding = UDim.new(0, padding or 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = align or Enum.HorizontalAlignment.Left,
	})
end

function UIKit.Panel(props)
	local frame = UIKit.new("Frame", {
		BackgroundColor3 = T.Panel,
		BackgroundTransparency = 0.08,
	})
	for k, v in props do
		if k ~= "Parent" then
			(frame :: any)[k] = v
		end
	end
	UIKit.Corner(14).Parent = frame
	UIKit.Stroke(T.Stroke, 1, 0.3).Parent = frame
	frame.Parent = props.Parent
	return frame
end

function UIKit.Label(props)
	local label = UIKit.new("TextLabel", {
		BackgroundTransparency = 1,
		TextColor3 = T.Text,
		Font = T.Bold,
		TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	for k, v in props do
		if k ~= "Parent" then
			(label :: any)[k] = v
		end
	end
	label.Parent = props.Parent
	return label
end

function UIKit.Button(props, onClick: () -> ())
	local button = UIKit.new("TextButton", {
		BackgroundColor3 = T.PanelLight,
		TextColor3 = T.Text,
		Font = T.Heavy,
		TextSize = 16,
		AutoButtonColor = false,
	})
	for k, v in props do
		if k ~= "Parent" then
			(button :: any)[k] = v
		end
	end
	UIKit.Corner(10).Parent = button
	local base = button.BackgroundColor3
	button.MouseEnter:Connect(function()
		TweenService:Create(button, TweenInfo.new(0.12), { BackgroundColor3 = base:Lerp(Color3.new(1, 1, 1), 0.12) }):Play()
	end)
	button.MouseLeave:Connect(function()
		TweenService:Create(button, TweenInfo.new(0.12), { BackgroundColor3 = base }):Play()
	end)
	button.Activated:Connect(onClick)
	button.Parent = props.Parent
	return button
end

-- Horizontal progress bar. Returns container, fill.
function UIKit.Bar(props, fillColor: Color3)
	local back = UIKit.new("Frame", {
		BackgroundColor3 = Color3.fromRGB(40, 42, 52),
	})
	for k, v in props do
		if k ~= "Parent" then
			(back :: any)[k] = v
		end
	end
	UIKit.Corner(6).Parent = back
	local fill = UIKit.new("Frame", {
		Name = "Fill",
		BackgroundColor3 = fillColor,
		Size = UDim2.fromScale(0, 1),
		Parent = back,
	})
	UIKit.Corner(6).Parent = fill
	back.Parent = props.Parent
	return back, fill
end

function UIKit.Tween(inst: Instance, time: number, goal, style: Enum.EasingStyle?)
	local tween = TweenService:Create(inst, TweenInfo.new(time, style or Enum.EasingStyle.Quint, Enum.EasingDirection.Out), goal)
	tween:Play()
	return tween
end

function UIKit.FormatNumber(n: number): string
	local s = tostring(math.floor(n))
	local formatted = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if formatted:sub(1, 1) == "," then
		formatted = formatted:sub(2)
	end
	return formatted
end

return UIKit
