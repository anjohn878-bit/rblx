-- Toast messages that slide in at the top of the screen.

local TweenService = game:GetService("TweenService")

local UI = require(script.Parent.UI)

local Notifications = {}

local KIND_COLORS = {
	Success = Color3.fromRGB(70, 165, 70),
	Error = Color3.fromRGB(200, 70, 70),
	Rare = Color3.fromRGB(145, 80, 215),
	Info = Color3.fromRGB(55, 70, 95),
}
local MAX_VISIBLE = 4
local LIFETIME = 4.5

local container
local order = 0

function Notifications.Init(screenGui)
	container = UI.new("Frame", {
		Name = "Notifications",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 8),
		Size = UDim2.new(0.6, 0, 0, 220),
		BackgroundTransparency = 1,
		ZIndex = 30, -- above windows
		Parent = screenGui,
	}, {
		UI.new("UISizeConstraint", { MaxSize = Vector2.new(460, 220) }),
		UI.new("UIListLayout", {
			Padding = UDim.new(0, 6),
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
end

function Notifications.Show(text, kind)
	if not container or type(text) ~= "string" then
		return
	end
	order += 1

	local toasts = {}
	for _, child in ipairs(container:GetChildren()) do
		if child:IsA("Frame") then
			table.insert(toasts, child)
		end
	end
	table.sort(toasts, function(a, b)
		return a.LayoutOrder < b.LayoutOrder
	end)
	for i = 1, #toasts - MAX_VISIBLE + 1 do
		toasts[i]:Destroy()
	end

	local toast = UI.new("Frame", {
		LayoutOrder = order,
		Size = UDim2.new(1, 0, 0, 44),
		BackgroundColor3 = KIND_COLORS[kind] or KIND_COLORS.Info,
		BackgroundTransparency = 1,
		Parent = container,
	}, { UI.corner(12) })
	local stroke = UI.stroke(Color3.new(1, 1, 1), 2)
	stroke.Transparency = 1
	stroke.Parent = toast
	local label = UI.label({
		Text = text,
		TextColor3 = Color3.new(1, 1, 1),
		TextTransparency = 1,
		TextWrapped = true,
		Position = UDim2.fromOffset(12, 4),
		Size = UDim2.new(1, -24, 1, -8),
		Parent = toast,
	})
	UI.new("UITextSizeConstraint", { MaxTextSize = 20, Parent = label })

	local fadeIn = TweenInfo.new(0.25)
	TweenService:Create(toast, fadeIn, { BackgroundTransparency = 0.1 }):Play()
	TweenService:Create(label, fadeIn, { TextTransparency = 0 }):Play()
	TweenService:Create(stroke, fadeIn, { Transparency = 0.4 }):Play()

	task.delay(LIFETIME, function()
		if not toast.Parent then
			return
		end
		local fadeOut = TweenInfo.new(0.4)
		TweenService:Create(toast, fadeOut, { BackgroundTransparency = 1 }):Play()
		TweenService:Create(label, fadeOut, { TextTransparency = 1 }):Play()
		TweenService:Create(stroke, fadeOut, { Transparency = 1 }):Play()
		task.wait(0.4)
		toast:Destroy()
	end)
end

return Notifications
