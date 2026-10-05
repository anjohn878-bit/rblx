--!strict
-- Transient feedback: toast messages, the "new bird discovered" banner, and the
-- floating "+feathers" popup that appears over a bird when it lands.

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BirdModel = require(Shared:WaitForChild("BirdModel"))
local Birds = require(Shared:WaitForChild("Birds"))
local Config = require(Shared:WaitForChild("Config"))
local Format = require(Shared:WaitForChild("Format"))
local Types = require(Shared:WaitForChild("Types"))

local Ui = require(script.Parent.Ui)
local Viewport = require(script.Parent.Viewport)

local Toasts = {}

local container: Frame
local banner: Frame
local bannerStroke: UIStroke
local fxFolder: Folder

local MAX_TOASTS = 4

function Toasts.init(gui: ScreenGui)
	container = Ui.new("Frame", {
		Name = "Toasts",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 108),
		Size = UDim2.new(0.9, 0, 0, 220),
		BackgroundTransparency = 1,
		Parent = gui,
	}, {
		Ui.new("UIListLayout", {
			Padding = UDim.new(0, 6),
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})

	banner = Ui.new("Frame", {
		Name = "DiscoveryBanner",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, -220),
		Size = UDim2.fromOffset(400, 130),
		BackgroundColor3 = Ui.COLORS.bg,
		Visible = false,
		ZIndex = 20,
		Parent = gui,
	}, { Ui.corner(18) })
	bannerStroke = Ui.stroke(Ui.COLORS.gold, 3)
	bannerStroke.Parent = banner

	fxFolder = Ui.new("Folder", { Name = "ClientFX", Parent = workspace })
end

local order = 0

function Toasts.show(text: string, color: Color3?)
	order += 1
	local toast = Ui.new("TextLabel", {
		Name = "Toast",
		LayoutOrder = order,
		AutomaticSize = Enum.AutomaticSize.XY,
		BackgroundColor3 = Ui.COLORS.bg,
		BackgroundTransparency = 0.1,
		Font = Ui.FONT_BOLD,
		Text = text,
		TextColor3 = color or Ui.COLORS.text,
		TextSize = 16,
		TextWrapped = true,
		Parent = container,
	}, {
		Ui.corner(12),
		Ui.padding(10),
		Ui.stroke(color or Ui.COLORS.panelLight, 2, 0.3),
		Ui.new("UISizeConstraint", { MaxSize = Vector2.new(460, 120) }),
	})

	-- keep the stack short
	local toasts = {}
	for _, child in container:GetChildren() do
		if child.Name == "Toast" then
			table.insert(toasts, child)
		end
	end
	if #toasts > MAX_TOASTS then
		toasts[1]:Destroy()
	end

	task.delay(3.6, function()
		if not toast.Parent then
			return
		end
		local info = TweenInfo.new(0.4)
		TweenService:Create(toast, info, { TextTransparency = 1, BackgroundTransparency = 1 }):Play()
		local stroke = toast:FindFirstChildOfClass("UIStroke")
		if stroke then
			TweenService:Create(stroke, info, { Transparency = 1 }):Play()
		end
		task.wait(0.45)
		toast:Destroy()
	end)
end

function Toasts.result(result: any)
	if type(result) ~= "table" then
		return
	end
	Toasts.show(tostring(result.message), if result.ok then Ui.COLORS.good else Ui.COLORS.bad)
end

------------------------------------------------------------------------------
-- Discovery banner
------------------------------------------------------------------------------

local queue: { { birdId: string, bonus: number } } = {}
local pumping = false

local function playBanner(birdId: string, bonus: number)
	local def = Birds.get(birdId)
	if not def then
		return
	end
	local rarityColor = Config.RARITY_COLORS[def.rarity]

	for _, child in banner:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	bannerStroke.Color = rarityColor

	local preview = Ui.new("ViewportFrame", {
		Position = UDim2.fromOffset(12, 10),
		Size = UDim2.fromOffset(110, 110),
		Parent = banner,
	})
	Viewport.mount(preview, BirdModel.build(def).model)

	Ui.label({
		Position = UDim2.fromOffset(134, 12),
		Size = UDim2.new(1, -146, 0, 18),
		Text = "NEW BIRD DISCOVERED!",
		Font = Ui.FONT_BOLD,
		TextSize = 14,
		TextColor3 = Ui.COLORS.gold,
		Parent = banner,
	})
	Ui.label({
		Position = UDim2.fromOffset(134, 34),
		Size = UDim2.new(1, -146, 0, 34),
		Text = def.name,
		Font = Ui.FONT,
		TextSize = 28,
		TextColor3 = rarityColor,
		TextScaled = true,
		Parent = banner,
	})
	Ui.label({
		Position = UDim2.fromOffset(134, 72),
		Size = UDim2.new(1, -146, 0, 18),
		Text = def.rarity,
		Font = Ui.FONT_BOLD,
		TextSize = 15,
		TextColor3 = rarityColor,
		Parent = banner,
	})
	Ui.label({
		Position = UDim2.fromOffset(134, 94),
		Size = UDim2.new(1, -146, 0, 22),
		Text = `Discovery bonus: +{Format.feathers(bonus)} feathers`,
		Font = Ui.FONT_BOLD,
		TextSize = 15,
		TextColor3 = Ui.COLORS.good,
		Parent = banner,
	})

	banner.Visible = true
	banner.Position = UDim2.new(0.5, 0, 0, -220)
	TweenService:Create(
		banner,
		TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Position = UDim2.new(0.5, 0, 0, 130) }
	):Play()
	task.wait(4.2)
	local out = TweenService:Create(
		banner,
		TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ Position = UDim2.new(0.5, 0, 0, -220) }
	)
	out:Play()
	out.Completed:Wait()
	banner.Visible = false
end

function Toasts.discovery(birdId: string, bonus: number)
	table.insert(queue, { birdId = birdId, bonus = bonus })
	if pumping then
		return
	end
	pumping = true
	task.spawn(function()
		while #queue > 0 do
			local item = table.remove(queue, 1)
			if item then
				playBanner(item.birdId, item.bonus)
			end
		end
		pumping = false
	end)
end

------------------------------------------------------------------------------
-- "+feathers" popup over the bird
------------------------------------------------------------------------------

function Toasts.reward(position: Vector3, amount: number, birdId: string)
	local def = Birds.get(birdId)
	local anchor = Ui.new("Part", {
		Name = "RewardAnchor",
		Anchored = true,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		Transparency = 1,
		Size = Vector3.new(0.2, 0.2, 0.2),
		Position = position,
		Parent = fxFolder,
	})
	local gui = Ui.new("BillboardGui", {
		Size = UDim2.fromOffset(200, 64),
		AlwaysOnTop = true,
		MaxDistance = 140,
		LightInfluence = 0,
		StudsOffsetWorldSpace = Vector3.zero,
		Parent = anchor,
	})
	local amountLabel = Ui.label({
		Size = UDim2.new(1, 0, 0.62, 0),
		Text = "+" .. Format.feathers(amount),
		Font = Ui.FONT,
		TextScaled = true,
		TextColor3 = Ui.COLORS.gold,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextStrokeTransparency = 0.2,
		Parent = gui,
	})
	local nameLabel = Ui.label({
		Position = UDim2.fromScale(0, 0.62),
		Size = UDim2.new(1, 0, 0.34, 0),
		Text = if def then def.name else "",
		Font = Ui.FONT_BOLD,
		TextScaled = true,
		TextColor3 = if def then Config.RARITY_COLORS[def.rarity] else Ui.COLORS.text,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextStrokeTransparency = 0.3,
		Parent = gui,
	})

	TweenService:Create(
		gui,
		TweenInfo.new(2.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ StudsOffsetWorldSpace = Vector3.new(0, 4.5, 0) }
	):Play()
	local fade = TweenInfo.new(0.9, Enum.EasingStyle.Linear, Enum.EasingDirection.In, 0, false, 1.3)
	TweenService:Create(amountLabel, fade, { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	TweenService:Create(nameLabel, fade, { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	Debris:AddItem(anchor, 2.6)
end

-- Routes a server Notice to the right effect.
function Toasts.handle(notice: Types.Notice)
	if notice.kind == "toast" and notice.text then
		Toasts.show(notice.text, notice.color)
	elseif notice.kind == "reward" and notice.position and notice.amount and notice.birdId then
		Toasts.reward(notice.position, notice.amount, notice.birdId)
	elseif notice.kind == "discovery" and notice.birdId and notice.bonus then
		Toasts.discovery(notice.birdId, notice.bonus)
	end
end

return Toasts
