--[[
	HUD
	On-screen interface: snowflake counter, menu buttons, speedometer, trick
	and combo popups, rink banners, notifications and control hints.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Format = require(Shared.Format)
local Formulas = require(Shared.Formulas)
local Remotes = require(Shared.Remotes)

local ClientData = require(script.Parent.ClientData)
local SkateController = require(script.Parent.SkateController)
local UI = require(script.Parent.UI)

local Colors = UI.Colors
local create, label = UI.create, UI.label

local HUD = {}

local player = Players.LocalPlayer
local gui
local amountLabel, multiplierLabel, gainAnchor
local speedFrame, speedLabel, speedFill, rinkTag
local trickName, trickAmount, trickScale
local comboFrame, comboLabel, comboFill
local bannerTitle, bannerSubtitle
local toastList
local hintLabel

local displayedSnowflakes = 0
local targetSnowflakes = 0
local pendingGain = 0
local lastGainShown = 0
local comboExpires = 0
local comboDuration = 1
local trickToken = 0
local bannerToken = 0
local toastCount = 0
local activeToasts = {}

local KIND_COLORS = {
	success = Colors.Success,
	error = Colors.Danger,
	info = Colors.Accent,
	gold = Colors.Gold,
	rebirth = Colors.Purple,
}

-- Notifications ------------------------------------------------------------------

function HUD.notify(message, kind)
	if not toastList or type(message) ~= "string" then
		return
	end
	local color = KIND_COLORS[kind] or Colors.Accent
	toastCount += 1
	local toast = create("Frame", {
		BackgroundColor3 = Colors.Panel,
		BackgroundTransparency = 0.1,
		LayoutOrder = toastCount,
		Size = UDim2.new(1, 0, 0, 38),
		Parent = toastList,
	}, {
		UI.corner(10),
		UI.stroke(color, 2),
		label({
			Font = UI.BodyFont,
			Position = UDim2.fromOffset(12, 6),
			Size = UDim2.new(1, -24, 1, -12),
			Text = message,
			TextColor3 = Colors.Text,
		}, { UI.maxText(18) }),
	})

	table.insert(activeToasts, toast)
	if #activeToasts > 4 then
		table.remove(activeToasts, 1):Destroy()
	end

	task.delay(3.2, function()
		local index = table.find(activeToasts, toast)
		if index then
			table.remove(activeToasts, index)
			UI.tween(toast, 0.3, { BackgroundTransparency = 1 })
			for _, descendant in toast:GetDescendants() do
				if descendant:IsA("TextLabel") then
					UI.tween(descendant, 0.3, { TextTransparency = 1 })
				elseif descendant:IsA("UIStroke") then
					UI.tween(descendant, 0.3, { Transparency = 1 })
				end
			end
			task.wait(0.32)
			toast:Destroy()
		end
	end)
end

-- Snowflake counter -----------------------------------------------------------------

local function showGain(amount)
	local popup = label({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.fromOffset(160, 26),
		Text = "+" .. Format.abbreviate(amount) .. " " .. Config.CurrencyIcon,
		TextColor3 = Colors.Accent,
		Parent = gainAnchor,
	}, { UI.textStroke(2) })
	UI.tween(popup, 0.9, { Position = UDim2.new(0.5, 0, 0, 34), TextTransparency = 1 })
	task.delay(0.95, function()
		popup:Destroy()
	end)
end

local function onProfile(profile, previous)
	targetSnowflakes = profile.Snowflakes
	if previous and profile.Snowflakes > previous.Snowflakes then
		pendingGain += profile.Snowflakes - previous.Snowflakes
	elseif not previous then
		displayedSnowflakes = profile.Snowflakes
	end

	local rebirthMultiplier = Formulas.rebirthMultiplier(profile)
	multiplierLabel.Text =
		string.format("🔄 %d rebirths  •  %s boost", profile.Rebirths, Format.multiplier(rebirthMultiplier))
end

-- Tricks & combos ------------------------------------------------------------------

function HUD.showTrick(result)
	trickToken += 1
	local token = trickToken
	trickName.Text = string.upper(result.name) .. "!"
	trickAmount.Text = "+" .. Format.abbreviate(result.amount) .. " " .. Config.CurrencyIcon
	trickName.TextTransparency = 0
	trickAmount.TextTransparency = 0
	trickScale.Scale = 0.4
	UI.tween(trickScale, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)

	task.delay(1.4, function()
		if token == trickToken then
			UI.tween(trickName, 0.4, { TextTransparency = 1 })
			UI.tween(trickAmount, 0.4, { TextTransparency = 1 })
		end
	end)

	if result.combo >= 2 then
		comboFrame.Visible = true
		comboLabel.Text = string.format("COMBO %d  •  %s", result.combo, Format.multiplier(result.comboMultiplier))
		comboDuration = result.comboWindow
		comboExpires = os.clock() + result.comboWindow
	end
end

function HUD.showBanner(title, subtitle, color)
	bannerToken += 1
	local token = bannerToken
	bannerTitle.Text = title
	bannerTitle.TextColor3 = color or Colors.Text
	bannerSubtitle.Text = subtitle or ""
	bannerTitle.TextTransparency = 1
	bannerSubtitle.TextTransparency = 1
	UI.tween(bannerTitle, 0.4, { TextTransparency = 0 })
	UI.tween(bannerSubtitle, 0.4, { TextTransparency = 0 })
	task.delay(2.4, function()
		if token == bannerToken then
			UI.tween(bannerTitle, 0.6, { TextTransparency = 1 })
			UI.tween(bannerSubtitle, 0.6, { TextTransparency = 1 })
		end
	end)
end

local function onRinkChanged(rinkId)
	local rink = rinkId and Formulas.getRink(rinkId)
	if rink then
		HUD.showBanner(string.upper(rink.Name), Format.multiplier(rink.Multiplier) .. " SNOWFLAKES", Colors.Accent)
		rinkTag.Text = rink.Name .. "  " .. Format.multiplier(rink.Multiplier)
	end
end

-- Per-frame updates ------------------------------------------------------------------

local function onRenderStep(dt)
	-- Count the snowflake total up smoothly.
	if displayedSnowflakes ~= targetSnowflakes then
		local difference = targetSnowflakes - displayedSnowflakes
		displayedSnowflakes += difference * (1 - math.exp(-10 * dt))
		if math.abs(targetSnowflakes - displayedSnowflakes) < 1 then
			displayedSnowflakes = targetSnowflakes
		end
	end
	amountLabel.Text = Format.abbreviate(displayedSnowflakes)

	local now = os.clock()
	if pendingGain >= 1 and now - lastGainShown > 0.35 then
		showGain(pendingGain)
		pendingGain = 0
		lastGainShown = now
	end

	local skating = SkateController.isSkating()
	speedFrame.Visible = skating
	hintLabel.Visible = skating and hintLabel.Text ~= ""
	if skating then
		local speed = SkateController.getSpeed()
		speedLabel.Text = tostring(math.floor(speed + 0.5))
		speedFill.Size = UDim2.fromScale(math.clamp(speed / SkateController.getMaxSpeed(), 0, 1), 1)
	end

	if comboFrame.Visible then
		local remaining = comboExpires - now
		if remaining <= 0 then
			comboFrame.Visible = false
		else
			comboFill.Size = UDim2.fromScale(remaining / comboDuration, 1)
		end
	end
end

local function updateHint()
	if UserInputService.GamepadEnabled and not UserInputService.KeyboardEnabled then
		hintLabel.Text = "A  jump & spin    Y  scratch spin    Pull back  hockey stop"
	elseif UserInputService.KeyboardEnabled then
		hintLabel.Text = "SPACE  jump & spin    F  scratch spin    Hold S  hockey stop"
	else
		hintLabel.Text = ""
	end
end

-- Construction -------------------------------------------------------------------------

local function build(callbacks)
	local screen = create("ScreenGui", {
		Name = "HUD",
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = player:WaitForChild("PlayerGui"),
	})
	-- Everything lives in one full-screen frame so it can be scaled down on small screens.
	gui = create("Frame", {
		Name = "Root",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Parent = screen,
	})

	-- Snowflake counter, top centre.
	local counter = create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundColor3 = Colors.Panel,
		BackgroundTransparency = 0.15,
		Position = UDim2.new(0.5, 0, 0, 8),
		Size = UDim2.fromOffset(240, 50),
		Parent = gui,
	}, {
		UI.corner(25),
		UI.stroke(Colors.Accent, 2, 0.2),
		label({
			Position = UDim2.fromOffset(10, 4),
			Size = UDim2.new(0, 42, 1, -8),
			Text = Config.CurrencyIcon,
			TextColor3 = Colors.Accent,
		}),
	})
	amountLabel = label({
		Position = UDim2.fromOffset(56, 6),
		Size = UDim2.new(1, -70, 1, -12),
		Text = "0",
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = counter,
	}, { UI.maxText(34) })
	multiplierLabel = label({
		AnchorPoint = Vector2.new(0.5, 0),
		Font = UI.BodyFont,
		Position = UDim2.new(0.5, 0, 0, 60),
		Size = UDim2.fromOffset(280, 18),
		Text = "",
		TextColor3 = Colors.SubText,
		Parent = gui,
	}, { UI.textStroke(1.5) })
	gainAnchor = create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundTransparency = 1,
		Position = UDim2.new(0.5, 0, 0, 80),
		Size = UDim2.fromOffset(200, 60),
		Parent = gui,
	})

	-- Notifications under the counter.
	toastList = create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundTransparency = 1,
		Position = UDim2.new(0.5, 0, 0, 120),
		Size = UDim2.new(0, 420, 0, 220),
		Parent = gui,
	}, {
		create("UIListLayout", {
			Padding = UDim.new(0, 6),
			SortOrder = Enum.SortOrder.LayoutOrder,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
		}),
	})

	-- Menu buttons on the left.
	local menu = create("Frame", {
		AnchorPoint = Vector2.new(0, 0.5),
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 12, 0.5, 0),
		Size = UDim2.fromOffset(78, 168),
		Parent = gui,
	}, {
		create("UIListLayout", { Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	local function menuButton(order, icon, text, color, callback)
		local button = UI.button({
			BackgroundColor3 = color,
			LayoutOrder = order,
			Size = UDim2.fromOffset(78, 78),
			Text = "",
			Parent = menu,
		}, {
			UI.stroke(Colors.Outline, 3),
			label({ Position = UDim2.fromScale(0.1, 0.06), Size = UDim2.fromScale(0.8, 0.56), Text = icon }),
			label(
				{ Position = UDim2.fromScale(0.05, 0.62), Size = UDim2.fromScale(0.9, 0.3), Text = text },
				{ UI.textStroke(1.5) }
			),
		})
		button.Activated:Connect(callback)
		return button
	end
	menuButton(1, "🛒", "SHOP", Color3.fromRGB(60, 150, 235), callbacks.onShop)
	menuButton(2, "🔄", "REBIRTH", Color3.fromRGB(140, 85, 230), callbacks.onRebirth)

	-- Speedometer, bottom centre.
	speedFrame = create("Frame", {
		AnchorPoint = Vector2.new(0.5, 1),
		BackgroundColor3 = Colors.Panel,
		BackgroundTransparency = 0.2,
		Position = UDim2.new(0.5, 0, 1, -14),
		Size = UDim2.fromOffset(230, 74),
		Visible = false,
		Parent = gui,
	}, {
		UI.corner(14),
		UI.stroke(Colors.Accent, 2, 0.3),
	})
	speedLabel = label({
		Position = UDim2.fromOffset(14, 6),
		Size = UDim2.fromOffset(110, 42),
		Text = "0",
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = speedFrame,
	})
	label({
		Font = UI.BodyFont,
		Position = UDim2.fromOffset(130, 18),
		Size = UDim2.fromOffset(80, 22),
		Text = "STUDS/S",
		TextColor3 = Colors.SubText,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = speedFrame,
	})
	local bar = create("Frame", {
		BackgroundColor3 = Colors.PanelLighter,
		Position = UDim2.new(0, 14, 1, -20),
		Size = UDim2.new(1, -28, 0, 10),
		Parent = speedFrame,
	}, { UI.corner(5) })
	speedFill = create("Frame", {
		BackgroundColor3 = Colors.Accent,
		Size = UDim2.fromScale(0, 1),
		Parent = bar,
	}, {
		UI.corner(5),
		create("UIGradient", { Color = ColorSequence.new(Colors.Accent, Color3.fromRGB(190, 120, 255)) }),
	})
	rinkTag = label({
		AnchorPoint = Vector2.new(0.5, 1),
		Font = UI.BodyFont,
		Position = UDim2.new(0.5, 0, 0, -4),
		Size = UDim2.fromOffset(230, 18),
		Text = "",
		TextColor3 = Colors.SubText,
		Parent = speedFrame,
	}, { UI.textStroke(1.5) })

	hintLabel = label({
		AnchorPoint = Vector2.new(0.5, 1),
		Font = UI.BodyFont,
		Position = UDim2.new(0.5, 0, 1, -112),
		Size = UDim2.fromOffset(520, 18),
		Text = "",
		TextColor3 = Colors.SubText,
		TextTransparency = 0.15,
		Visible = false,
		Parent = gui,
	}, { UI.textStroke(1.5) })

	-- Trick popup and combo meter.
	local trickFrame = create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Position = UDim2.fromScale(0.5, 0.32),
		Size = UDim2.fromOffset(520, 100),
		Parent = gui,
	})
	trickScale = create("UIScale", { Parent = trickFrame })
	trickName = label({
		Size = UDim2.new(1, 0, 0, 56),
		Text = "",
		TextColor3 = Colors.Gold,
		TextTransparency = 1,
		Parent = trickFrame,
	}, { UI.textStroke(3) })
	trickAmount = label({
		Position = UDim2.fromOffset(0, 58),
		Size = UDim2.new(1, 0, 0, 34),
		Text = "",
		TextColor3 = Colors.Accent,
		TextTransparency = 1,
		Parent = trickFrame,
	}, { UI.textStroke(2.5) })

	comboFrame = create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundColor3 = Colors.Panel,
		BackgroundTransparency = 0.2,
		Position = UDim2.new(0.5, 0, 0.32, 58),
		Size = UDim2.fromOffset(220, 40),
		Visible = false,
		Parent = gui,
	}, {
		UI.corner(10),
		UI.stroke(Colors.Gold, 2, 0.2),
	})
	comboLabel = label({
		Position = UDim2.fromOffset(10, 4),
		Size = UDim2.new(1, -20, 0, 22),
		Text = "",
		TextColor3 = Colors.Gold,
		Parent = comboFrame,
	})
	local comboBar = create("Frame", {
		BackgroundColor3 = Colors.PanelLighter,
		Position = UDim2.new(0, 10, 1, -11),
		Size = UDim2.new(1, -20, 0, 6),
		Parent = comboFrame,
	}, { UI.corner(3) })
	comboFill = create("Frame", {
		BackgroundColor3 = Colors.Gold,
		Size = UDim2.fromScale(1, 1),
		Parent = comboBar,
	}, { UI.corner(3) })

	-- Big banner for entering rinks and rebirths.
	bannerTitle = label({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.17),
		Size = UDim2.fromOffset(600, 64),
		Text = "",
		TextTransparency = 1,
		Parent = gui,
	}, { UI.textStroke(3) })
	bannerSubtitle = label({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Font = UI.BodyFont,
		Position = UDim2.new(0.5, 0, 0.17, 44),
		Size = UDim2.fromOffset(400, 24),
		Text = "",
		TextColor3 = Colors.SubText,
		TextTransparency = 1,
		Parent = gui,
	}, { UI.textStroke(2) })

	-- Shrink fixed-size elements on small phone screens. The root frame is enlarged by the
	-- inverse amount so that, once scaled, it still covers the whole screen.
	local scale = create("UIScale", { Parent = gui })
	local function rescale()
		local viewport = workspace.CurrentCamera.ViewportSize
		local amount = math.clamp(math.min(viewport.X / 900, viewport.Y / 560), 0.6, 1)
		scale.Scale = amount
		gui.Size = UDim2.fromScale(1 / amount, 1 / amount)
	end
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(rescale)
	rescale()
end

function HUD.init(callbacks)
	build(callbacks)
	updateHint()
	UserInputService.LastInputTypeChanged:Connect(updateHint)

	ClientData.observe(onProfile)
	SkateController.RinkChanged:Connect(onRinkChanged)
	RunService.RenderStepped:Connect(onRenderStep)

	Remotes.Notify.OnClientEvent:Connect(HUD.notify)
	Remotes.TrickResult.OnClientEvent:Connect(HUD.showTrick)
	Remotes.CollectiblePicked.OnClientEvent:Connect(function(_, amount)
		HUD.notify("Golden snowflake! +" .. Format.abbreviate(amount) .. " " .. Config.CurrencyIcon, "gold")
	end)
	Remotes.Rebirthed.OnClientEvent:Connect(function(rebirths)
		HUD.showBanner("REBIRTH " .. rebirths .. "!", "Your snowflake boost is now permanent", Colors.Purple)
	end)

	task.delay(2, function()
		HUD.notify("Welcome to " .. Config.GameName .. "! Head to the Frozen Pond to start skating.", "info")
	end)
end

return HUD
