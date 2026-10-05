-- Build a Dress Store - player's screen
-- Cash counter, store stats, tips, notifications, floating "+$" popups,
-- and colouring the buy buttons green (can afford) or red (too expensive).

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local shared = ReplicatedStorage:WaitForChild("DressStore")
local Config = require(shared:WaitForChild("Config"))
local Util = require(shared:WaitForChild("Util"))
local remotes = shared:WaitForChild("Remotes")
local notifyEvent = remotes:WaitForChild("Notify") :: RemoteEvent
local popupEvent = remotes:WaitForChild("Popup") :: RemoteEvent
local rebirthEvent = remotes:WaitForChild("Rebirth") :: RemoteEvent
local goHomeEvent = remotes:WaitForChild("GoHome") :: RemoteEvent

local PAD_TAG = "DressStorePad"

local COLORS = {
	pink = Color3.fromRGB(255, 105, 180),
	hotPink = Color3.fromRGB(240, 60, 150),
	light = Color3.fromRGB(255, 240, 248),
	dark = Color3.fromRGB(90, 30, 75),
	white = Color3.fromRGB(255, 255, 255),
	green = Color3.fromRGB(80, 210, 120),
	red = Color3.fromRGB(240, 80, 100),
	gold = Color3.fromRGB(255, 200, 70),
	lilac = Color3.fromRGB(190, 150, 255),
	gray = Color3.fromRGB(170, 160, 175),
}

local NOTIFY_COLORS = {
	info = COLORS.lilac,
	success = COLORS.green,
	error = COLORS.red,
	money = COLORS.gold,
}

----------------------------------------------------------------------------
-- Sounds
----------------------------------------------------------------------------

local function makeSound(id: string, volume: number): Sound
	local sound = Instance.new("Sound")
	sound.SoundId = id
	sound.Volume = volume
	sound.Parent = SoundService
	return sound
end

local sounds = {
	money = makeSound("rbxasset://sounds/electronicpingshort.wav", 0.35),
	click = makeSound("rbxasset://sounds/button.wav", 0.5),
}

local function play(sound: Sound, pitch: number?)
	sound.PlaybackSpeed = pitch or 1
	SoundService:PlayLocalSound(sound)
end

----------------------------------------------------------------------------
-- UI helpers
----------------------------------------------------------------------------

local function new(className: string, props: { [string]: any }, children: { Instance }?): any
	local instance = Instance.new(className)
	for key, value in props do
		if key ~= "Parent" then
			(instance :: any)[key] = value
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

local function corner(radius: number): UICorner
	return new("UICorner", { CornerRadius = UDim.new(0, radius) })
end

local function stroke(color: Color3, thickness: number): UIStroke
	return new("UIStroke", { Color = color, Thickness = thickness, ApplyStrokeMode = Enum.ApplyStrokeMode.Border })
end

local function padding(px: number): UIPadding
	return new("UIPadding", {
		PaddingTop = UDim.new(0, px),
		PaddingBottom = UDim.new(0, px),
		PaddingLeft = UDim.new(0, px),
		PaddingRight = UDim.new(0, px),
	})
end

local function label(props: { [string]: any }): TextLabel
	local defaults = {
		BackgroundTransparency = 1,
		Font = Enum.Font.FredokaOne,
		TextColor3 = COLORS.white,
		TextScaled = true,
	}
	for key, value in props do
		defaults[key] = value
	end
	return new("TextLabel", defaults)
end

-- Everything scales down on small screens (phones) and up on big ones.
local scales: { UIScale } = {}
local uiScale = 1
local function scaled(frame: GuiObject): GuiObject
	local scale = new("UIScale", { Parent = frame })
	table.insert(scales, scale)
	return frame
end

local function updateScales()
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local viewport = camera.ViewportSize
	uiScale = math.clamp(math.min(viewport.X / 1280, viewport.Y / 760), 0.6, 1.25)
	for _, scale in scales do
		scale.Scale = uiScale
	end
end

----------------------------------------------------------------------------
-- Build the HUD
----------------------------------------------------------------------------

local screen = new("ScreenGui", {
	Name = "DressStoreHUD",
	ResetOnSpawn = false,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	Parent = player:WaitForChild("PlayerGui"),
})

-- Cash (top middle)
local cashPanel = scaled(new("Frame", {
	Name = "Cash",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 6),
	Size = UDim2.new(0, 280, 0, 58),
	BackgroundColor3 = COLORS.white,
	Parent = screen,
}, {
	corner(29),
	stroke(COLORS.pink, 4),
	new("UIGradient", {
		Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(255, 225, 240)),
		Rotation = 90,
	}),
}))
label({
	Name = "Icon",
	Text = "💰",
	Position = UDim2.new(0, 10, 0, 6),
	Size = UDim2.new(0, 46, 0, 46),
	Parent = cashPanel,
})
local cashLabel = label({
	Name = "Amount",
	Text = "$0",
	Position = UDim2.new(0, 60, 0, 6),
	Size = UDim2.new(1, -72, 0, 46),
	TextColor3 = COLORS.hotPink,
	TextXAlignment = Enum.TextXAlignment.Left,
	Parent = cashPanel,
})
local multiplierBadge = new("Frame", {
	Name = "Multiplier",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.new(1, -6, 0, 6),
	Size = UDim2.new(0, 62, 0, 28),
	BackgroundColor3 = COLORS.gold,
	Visible = false,
	Parent = cashPanel,
}, { corner(14), stroke(COLORS.white, 2) })
local multiplierLabel = label({
	Text = "x1.5",
	Size = UDim2.fromScale(1, 1),
	TextColor3 = COLORS.dark,
	Parent = multiplierBadge,
})

-- Store stats (under the cash)
local statsPanel = scaled(new("Frame", {
	Name = "Stats",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 70),
	Size = UDim2.new(0, 420, 0, 30),
	BackgroundColor3 = COLORS.dark,
	BackgroundTransparency = 0.25,
	Parent = screen,
}, { corner(15), padding(4) }))
local statsLabel = label({
	Text = "",
	Size = UDim2.fromScale(1, 1),
	Font = Enum.Font.GothamBold,
	Parent = statsPanel,
})

-- Tip + next goal (left side)
local goalPanel = scaled(new("Frame", {
	Name = "Goal",
	AnchorPoint = Vector2.new(0, 0.5),
	Position = UDim2.new(0, 12, 0.56, 0),
	Size = UDim2.new(0, 270, 0, 190),
	BackgroundColor3 = COLORS.white,
	BackgroundTransparency = 0.05,
	Parent = screen,
}, { corner(18), stroke(COLORS.pink, 3), padding(12) }))
label({
	Text = "💡 TIP",
	Size = UDim2.new(1, 0, 0, 22),
	TextColor3 = COLORS.hotPink,
	TextXAlignment = Enum.TextXAlignment.Left,
	Parent = goalPanel,
})
local tipLabel = label({
	Text = "",
	Position = UDim2.new(0, 0, 0, 24),
	Size = UDim2.new(1, 0, 0, 64),
	Font = Enum.Font.GothamBold,
	TextColor3 = COLORS.dark,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextYAlignment = Enum.TextYAlignment.Top,
	TextWrapped = true,
	Parent = goalPanel,
})
local goalTitle = label({
	Text = "🎯 NEXT UPGRADE",
	Position = UDim2.new(0, 0, 0, 94),
	Size = UDim2.new(1, 0, 0, 20),
	TextColor3 = COLORS.hotPink,
	TextXAlignment = Enum.TextXAlignment.Left,
	Parent = goalPanel,
})
local goalName = label({
	Text = "",
	Position = UDim2.new(0, 0, 0, 116),
	Size = UDim2.new(1, 0, 0, 22),
	TextColor3 = COLORS.dark,
	TextXAlignment = Enum.TextXAlignment.Left,
	Parent = goalPanel,
})
local goalBar = new("Frame", {
	Name = "Bar",
	Position = UDim2.new(0, 0, 0, 144),
	Size = UDim2.new(1, 0, 0, 22),
	BackgroundColor3 = Color3.fromRGB(255, 220, 236),
	Parent = goalPanel,
}, { corner(11) })
local goalFill = new("Frame", {
	Name = "Fill",
	Size = UDim2.fromScale(0, 1),
	BackgroundColor3 = COLORS.pink,
	Parent = goalBar,
}, { corner(11) })
local goalText = label({
	Text = "",
	Size = UDim2.fromScale(1, 1),
	TextColor3 = COLORS.white,
	TextStrokeTransparency = 0.4,
	TextStrokeColor3 = COLORS.dark,
	ZIndex = 2,
	Parent = goalBar,
})

-- Buttons (right side)
local buttonColumn = scaled(new("Frame", {
	Name = "Buttons",
	AnchorPoint = Vector2.new(1, 0.5),
	Position = UDim2.new(1, -12, 0.5, 0),
	Size = UDim2.new(0, 170, 0, 130),
	BackgroundTransparency = 1,
	Parent = screen,
}, {
	new("UIListLayout", {
		Padding = UDim.new(0, 10),
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		SortOrder = Enum.SortOrder.LayoutOrder,
	}),
}))

local function bigButton(text: string, color: Color3, order: number): TextButton
	local button = new("TextButton", {
		Text = text,
		Size = UDim2.new(1, 0, 0, 52),
		BackgroundColor3 = color,
		Font = Enum.Font.FredokaOne,
		TextColor3 = COLORS.white,
		TextScaled = true,
		AutoButtonColor = true,
		LayoutOrder = order,
		Parent = buttonColumn,
	}, { corner(16), stroke(COLORS.white, 3), padding(8) })
	return button
end

local homeButton = bigButton("🏠 My Store", COLORS.pink, 1)
local rebirthButton = bigButton("⭐ Rebirth", COLORS.gold, 2)
rebirthButton.TextColor3 = COLORS.dark
rebirthButton.Visible = false

-- Notifications (top middle, under the stats)
local toastList = new("Frame", {
	Name = "Toasts",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 108),
	Size = UDim2.new(0, 460, 0, 200),
	BackgroundTransparency = 1,
	Parent = screen,
}, {
	new("UIListLayout", {
		Padding = UDim.new(0, 6),
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
	}),
})
scaled(toastList)

-- Rebirth confirmation
local confirm = new("Frame", {
	Name = "RebirthConfirm",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.new(0, 420, 0, 220),
	BackgroundColor3 = COLORS.white,
	Visible = false,
	ZIndex = 10,
	Parent = screen,
}, { corner(22), stroke(COLORS.gold, 4), padding(16) })
scaled(confirm)
label({
	Text = "⭐ Rebirth? ⭐",
	Size = UDim2.new(1, 0, 0, 40),
	TextColor3 = COLORS.hotPink,
	ZIndex = 10,
	Parent = confirm,
})
local confirmText = label({
	Text = "",
	Position = UDim2.new(0, 0, 0, 46),
	Size = UDim2.new(1, 0, 0, 80),
	Font = Enum.Font.GothamBold,
	TextColor3 = COLORS.dark,
	TextWrapped = true,
	ZIndex = 10,
	Parent = confirm,
})
local yesButton = new("TextButton", {
	Text = "Rebirth!",
	AnchorPoint = Vector2.new(0, 1),
	Position = UDim2.new(0, 0, 1, 0),
	Size = UDim2.new(0.48, 0, 0, 50),
	BackgroundColor3 = COLORS.gold,
	Font = Enum.Font.FredokaOne,
	TextColor3 = COLORS.dark,
	TextScaled = true,
	ZIndex = 10,
	Parent = confirm,
}, { corner(14), padding(8) })
local noButton = new("TextButton", {
	Text = "Not yet",
	AnchorPoint = Vector2.new(1, 1),
	Position = UDim2.new(1, 0, 1, 0),
	Size = UDim2.new(0.48, 0, 0, 50),
	BackgroundColor3 = COLORS.gray,
	Font = Enum.Font.FredokaOne,
	TextColor3 = COLORS.white,
	TextScaled = true,
	ZIndex = 10,
	Parent = confirm,
}, { corner(14), padding(8) })

updateScales()
local function watchCamera()
	local camera = workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScales)
	end
	updateScales()
end
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(watchCamera)
watchCamera()

----------------------------------------------------------------------------
-- Notifications
----------------------------------------------------------------------------

local toastCount = 0
local function toast(text: string, kind: string?)
	toastCount += 1
	local color = NOTIFY_COLORS[kind or "info"] or COLORS.lilac
	local frame = new("Frame", {
		Size = UDim2.new(1, 0, 0, 40),
		BackgroundColor3 = color,
		BackgroundTransparency = 0.05,
		LayoutOrder = toastCount,
		Parent = toastList,
	}, { corner(14), stroke(COLORS.white, 2), padding(6) })
	local text_ = label({
		Text = text,
		Size = UDim2.fromScale(1, 1),
		Font = Enum.Font.GothamBold,
		TextColor3 = COLORS.white,
		TextStrokeTransparency = 0.6,
		TextStrokeColor3 = COLORS.dark,
		Parent = frame,
	})
	-- keep at most 4 messages on screen
	local toasts = {}
	for _, child in toastList:GetChildren() do
		if child:IsA("Frame") then
			table.insert(toasts, child)
		end
	end
	table.sort(toasts, function(a, b)
		return a.LayoutOrder < b.LayoutOrder
	end)
	for i = 1, #toasts - 4 do
		toasts[i]:Destroy()
	end

	task.delay(4, function()
		if frame.Parent then
			local info = TweenInfo.new(0.4)
			TweenService:Create(frame, info, { BackgroundTransparency = 1 }):Play()
			TweenService:Create(text_, info, { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
			local outline = frame:FindFirstChildOfClass("UIStroke")
			if outline then
				TweenService:Create(outline, info, { Transparency = 1 }):Play()
			end
			task.wait(0.45)
			frame:Destroy()
		end
	end)
	if kind == "error" then
		play(sounds.click, 0.7)
	end
end

notifyEvent.OnClientEvent:Connect(function(text: string, kind: string?)
	toast(text, kind)
end)

----------------------------------------------------------------------------
-- Floating popups in the world ("+$20", "+1 👗", "✨ Built!")
----------------------------------------------------------------------------

local POPUP_COLORS = {
	money = Color3.fromRGB(120, 255, 140),
	dress = Color3.fromRGB(255, 170, 220),
	build = Color3.fromRGB(255, 225, 120),
}

popupEvent.OnClientEvent:Connect(function(position: Vector3, text: string, kind: string?, ownerUserId: number?)
	local camera = workspace.CurrentCamera
	if not camera or (camera.CFrame.Position - position).Magnitude > 140 then
		return
	end
	local anchor = Instance.new("Part")
	anchor.Name = "Popup"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.Position = position
	anchor.Parent = workspace

	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.new(0, 220, 0, 56)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.Adornee = anchor
	gui.Parent = anchor
	local text_ = label({
		Text = text,
		Size = UDim2.fromScale(1, 1),
		TextColor3 = POPUP_COLORS[kind or "money"] or COLORS.white,
		TextStrokeTransparency = 0,
		TextStrokeColor3 = COLORS.dark,
		Parent = gui,
	})

	local info = TweenInfo.new(1.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(gui, info, { StudsOffsetWorldSpace = Vector3.new(0, 3.5, 0) }):Play()
	TweenService:Create(text_, TweenInfo.new(1.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		TextTransparency = 1,
		TextStrokeTransparency = 1,
	}):Play()
	task.delay(1.3, function()
		anchor:Destroy()
	end)

	if ownerUserId == player.UserId and kind == "money" then
		play(sounds.money, 1 + math.random() * 0.2)
	elseif ownerUserId == player.UserId and kind == "build" then
		play(sounds.money, 0.8)
	end
end)

----------------------------------------------------------------------------
-- Buy buttons: green when you can afford them, red when you can't,
-- grey when they belong to someone else's store.
----------------------------------------------------------------------------

local cashValue: IntValue? = nil

local function currentCash(): number
	return if cashValue then cashValue.Value else 0
end

local function tintPad(pad: Instance)
	local button = pad:FindFirstChild("Button")
	if not button or not button:IsA("BasePart") then
		return
	end
	local info = button:FindFirstChild("Info")
	local priceLabel = if info then info:FindFirstChild("Price") else nil
	local price = pad:GetAttribute("Price") or 0
	local mine = pad:GetAttribute("OwnerUserId") == player.UserId
	local color, textColor
	if not mine then
		color, textColor = COLORS.gray, COLORS.gray
	elseif currentCash() >= price then
		color, textColor = COLORS.green, Color3.fromRGB(140, 255, 160)
	else
		color, textColor = COLORS.red, Color3.fromRGB(255, 150, 160)
	end
	button.Color = color
	if priceLabel and priceLabel:IsA("TextLabel") then
		priceLabel.TextColor3 = textColor
	end
end

local function tintAllPads()
	for _, pad in CollectionService:GetTagged(PAD_TAG) do
		tintPad(pad)
	end
end

CollectionService:GetInstanceAddedSignal(PAD_TAG):Connect(function(pad)
	tintPad(pad)
	-- with streaming the button part can arrive a moment after the model
	pad.DescendantAdded:Connect(function()
		tintPad(pad)
	end)
end)
for _, pad in CollectionService:GetTagged(PAD_TAG) do
	pad.DescendantAdded:Connect(function()
		tintPad(pad)
	end)
end

----------------------------------------------------------------------------
-- Cash counter
----------------------------------------------------------------------------

local shownCash = 0
local targetCash = 0

local function onCashChanged()
	local value = currentCash()
	if value > targetCash and targetCash > 0 then
		-- little bounce when money comes in
		local scale = cashPanel:FindFirstChildOfClass("UIScale")
		if scale then
			scale.Scale = uiScale * 1.08
			TweenService:Create(scale, TweenInfo.new(0.25, Enum.EasingStyle.Back), { Scale = uiScale }):Play()
		end
	end
	targetCash = value
	tintAllPads()
end

task.spawn(function()
	local leaderstats = player:WaitForChild("leaderstats")
	local value = leaderstats:WaitForChild("Cash") :: IntValue
	cashValue = value
	shownCash = value.Value
	targetCash = value.Value
	value.Changed:Connect(onCashChanged)
	onCashChanged()
end)

RunService.RenderStepped:Connect(function(dt)
	if shownCash ~= targetCash then
		local step = (targetCash - shownCash) * math.min(1, dt * 8)
		if math.abs(targetCash - shownCash) < 1 then
			shownCash = targetCash
		else
			shownCash += step
		end
	end
	cashLabel.Text = Util.formatMoney(math.floor(shownCash + 0.5))
end)

----------------------------------------------------------------------------
-- Stats, tips and next goal
----------------------------------------------------------------------------

local function attr(name: string, default: any): any
	local value = player:GetAttribute(name)
	if value == nil then
		return default
	end
	return value
end

local function chooseTip(): string
	if attr("NoStore", false) then
		return "All stores on this server are taken. You'll get one as soon as someone leaves - visit your friends' stores meanwhile!"
	end
	if attr("PlotIndex", 0) == 0 then
		return "Finding you a store..."
	end
	if attr("ItemsOwned", 0) == 0 then
		return "Walk to the glowing button in front of your store and press E to open it!"
	end
	if not attr("HasRegister", false) or attr("Racks", 0) == 0 then
		return "Build a Cash Register and a Dress Rack so shoppers can buy your dresses!"
	end
	if attr("CanRebirth", false) then
		return "Your store is complete! 🎉 Press ⭐ Rebirth to start again and earn more money."
	end
	if attr("Waiting", 0) > 0 and not attr("HasCashier", false) then
		return "A shopper is waiting! Press E at the Cash Register to get paid. 💳"
	end
	if attr("Stock", 0) == 0 then
		return "Your racks are empty! Hold E at the Sewing Table to sew dresses. ✂️"
	end
	if attr("Stock", 0) < attr("StockMax", 0) and attr("ItemsOwned", 0) < 6 then
		return "Sew more dresses at the Sewing Table so your racks stay full!"
	end
	return "Shoppers buy dresses from your racks. Build upgrades to get more shoppers!"
end

local function refresh()
	local stock = attr("Stock", 0)
	local stockMax = attr("StockMax", 0)
	statsLabel.Text = string.format(
		"👗 %d/%d dresses   🛍️ %d shoppers   💝 %d sold",
		stock,
		stockMax,
		attr("Shoppers", 0),
		attr("Sold", 0)
	)

	local multiplier = attr("Multiplier", 1)
	multiplierBadge.Visible = multiplier > 1
	multiplierLabel.Text = string.format("x%.1f", multiplier)

	tipLabel.Text = chooseTip()

	local nextName = attr("NextItem", "")
	local nextPrice = attr("NextPrice", 0)
	if nextName ~= "" then
		goalTitle.Visible = true
		goalBar.Visible = true
		goalName.Text = nextName
		local progress = if nextPrice > 0 then math.clamp(currentCash() / nextPrice, 0, 1) else 1
		goalFill.Size = UDim2.fromScale(progress, 1)
		goalFill.BackgroundColor3 = if progress >= 1 then COLORS.green else COLORS.pink
		goalText.Text = if progress >= 1
			then "Ready to buy! " .. Util.formatPrice(nextPrice)
			else Util.formatMoney(currentCash()) .. " / " .. Util.formatMoney(nextPrice)
	else
		goalTitle.Visible = attr("CanRebirth", false)
		goalBar.Visible = false
		goalName.Text = if attr("CanRebirth", false)
			then string.format("Rebirth for x%.1f money!", 1 + (attr("Rebirths", 0) + 1) * Config.REBIRTH_BONUS)
			else ""
	end

	rebirthButton.Visible = attr("CanRebirth", false)
end

task.spawn(function()
	while true do
		refresh()
		task.wait(0.25)
	end
end)

----------------------------------------------------------------------------
-- Buttons
----------------------------------------------------------------------------

homeButton.Activated:Connect(function()
	play(sounds.click)
	goHomeEvent:FireServer()
end)

rebirthButton.Activated:Connect(function()
	play(sounds.click)
	local nextMultiplier = 1 + (attr("Rebirths", 0) + 1) * Config.REBIRTH_BONUS
	confirmText.Text = string.format(
		"Your store starts over from the beginning, but you will earn x%.1f money forever!",
		nextMultiplier
	)
	confirm.Visible = true
end)

yesButton.Activated:Connect(function()
	play(sounds.click)
	confirm.Visible = false
	rebirthEvent:FireServer()
end)

noButton.Activated:Connect(function()
	play(sounds.click)
	confirm.Visible = false
end)
