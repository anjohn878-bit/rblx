--[[
	ShopUI
	The Skate Shop (skates, upgrades, rinks) and the Rebirth window.
	Cards are built once and refreshed whenever the profile changes.
]]

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Format = require(Shared.Format)
local Formulas = require(Shared.Formulas)
local Remotes = require(Shared.Remotes)

local ClientData = require(script.Parent.ClientData)
local HUD = require(script.Parent.HUD)
local UI = require(script.Parent.UI)

local Colors = UI.Colors
local create, label = UI.create, UI.label
local ICON = Config.CurrencyIcon

local ShopUI = {}

local player = Players.LocalPlayer
local shopWindow, rebirthWindow
local tabs = {} -- [name] = { button, page }
local cards = {} -- list of update(profile) functions
local currentTab = "Skates"
local busy = false

local rebirthInfo, rebirthMultiplier, rebirthFill, rebirthProgress, rebirthButton
local rebirthConfirmUntil = 0

local function price(amount)
	return Format.abbreviate(amount) .. " " .. ICON
end

local function purchase(kind, id)
	if busy then
		return
	end
	busy = true
	local ok, success, message = pcall(function()
		return Remotes.Purchase:InvokeServer(kind, id)
	end)
	busy = false
	if not ok then
		HUD.notify("The shop couldn't be reached. Try again!", "error")
		return
	end
	HUD.notify(message, if success then "success" else "error")
end

local function setButton(button, text, enabled, color)
	button.Text = text
	button.Active = enabled
	button.AutoButtonColor = enabled
	button.BackgroundColor3 = if enabled then (color or Colors.Success) else Colors.Disabled
end

-- Window chrome ---------------------------------------------------------------------

local function window(name, title, size, maxSize, parent)
	local frame = create("Frame", {
		Name = name,
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = Colors.Panel,
		Position = UDim2.fromScale(0.5, 0.5),
		Size = size,
		Visible = false,
		Parent = parent,
	}, {
		UI.corner(18),
		UI.stroke(Colors.Accent, 3, 0.1),
		create("UISizeConstraint", { MaxSize = maxSize }),
	})
	label({
		Position = UDim2.fromOffset(18, 10),
		Size = UDim2.new(1, -90, 0, 40),
		Text = title,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = frame,
	}, { UI.textStroke(2) })
	local close = UI.button({
		AnchorPoint = Vector2.new(1, 0),
		BackgroundColor3 = Colors.Danger,
		Position = UDim2.new(1, -12, 0, 12),
		Size = UDim2.fromOffset(40, 40),
		Text = "✕",
		Parent = frame,
	})
	close.Activated:Connect(function()
		frame.Visible = false
	end)
	return frame
end

local function card(page, order, iconText, iconColor)
	local frame = create("Frame", {
		BackgroundColor3 = Colors.PanelLight,
		LayoutOrder = order,
		Size = UDim2.new(1, -10, 0, 78),
		Parent = page,
	}, { UI.corner(12) })
	create("Frame", {
		BackgroundColor3 = iconColor,
		Position = UDim2.fromOffset(12, 12),
		Size = UDim2.fromOffset(54, 54),
		Parent = frame,
	}, {
		UI.corner(12),
		UI.stroke(Colors.Outline, 2, 0.3),
		label({ Size = UDim2.fromScale(1, 1), Text = iconText }, { UI.padding(8) }),
	})
	local title = label({
		Position = UDim2.fromOffset(78, 10),
		Size = UDim2.new(1, -240, 0, 28),
		Text = "",
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = frame,
	}, { UI.maxText(24) })
	local description = label({
		Font = UI.BodyFont,
		Position = UDim2.fromOffset(78, 42),
		Size = UDim2.new(1, -240, 0, 24),
		Text = "",
		TextColor3 = Colors.SubText,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = true,
		Parent = frame,
	}, { UI.maxText(15) })
	local button = UI.button({
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -12, 0.5, 0),
		Size = UDim2.fromOffset(140, 46),
		Text = "",
		Parent = frame,
	}, { UI.maxText(20), UI.padding(6) })
	return title, description, button
end

-- Pages ------------------------------------------------------------------------------

local function buildSkatesPage(page)
	for tier, skate in Config.Skates do
		local title, description, button = card(page, tier, "⛸", skate.BootColor)
		title.Text = skate.Name
		button.Activated:Connect(function()
			if button.Active then
				purchase("Skate", tier)
			end
		end)
		table.insert(cards, function(profile)
			local speedBonus = Formulas.maxSpeed(profile) / Formulas.getSkate(profile.SkateTier).MaxSpeed
			description.Text = string.format(
				"Top speed %d  •  %s snowflakes",
				math.floor(skate.MaxSpeed * speedBonus),
				Format.multiplier(skate.EarnMultiplier)
			)
			if tier == profile.SkateTier then
				setButton(button, "Equipped", false)
			elseif tier < profile.SkateTier then
				setButton(button, "Owned", false)
			elseif tier == profile.SkateTier + 1 then
				local affordable = profile.Snowflakes >= skate.Price
				setButton(button, price(skate.Price), true, if affordable then Colors.Success else Colors.PanelLighter)
			else
				setButton(button, "🔒 " .. price(skate.Price), false)
			end
		end)
	end
end

local function upgradeEffect(upgrade, profile)
	if upgrade.Id == "Speed" then
		return string.format("Top speed %d", math.floor(Formulas.maxSpeed(profile)))
	elseif upgrade.Id == "Jump" then
		return string.format("Jump height %.1f", Formulas.jumpHeight(profile))
	elseif upgrade.Id == "Style" then
		return "Tricks " .. Format.multiplier(Formulas.styleMultiplier(profile))
	end
	return ""
end

local function buildUpgradesPage(page)
	for order, upgrade in Config.Upgrades do
		local title, description, button = card(page, order, upgrade.Icon, Colors.PanelLighter)
		button.Activated:Connect(function()
			if button.Active then
				purchase("Upgrade", upgrade.Id)
			end
		end)
		table.insert(cards, function(profile)
			local level = Formulas.upgradeLevel(profile, upgrade.Id)
			title.Text = string.format("%s  Lv %d/%d", upgrade.Name, level, upgrade.MaxLevel)
			description.Text = upgrade.Description .. "  •  " .. upgradeEffect(upgrade, profile)
			local cost = Formulas.upgradeCost(upgrade.Id, level)
			if cost then
				setButton(
					button,
					price(cost),
					true,
					if profile.Snowflakes >= cost then Colors.Success else Colors.PanelLighter
				)
			else
				setButton(button, "MAX", false)
			end
		end)
	end
end

local function buildRinksPage(page)
	for order, rink in Config.Rinks do
		local title, description, button = card(page, order, ICON, rink.AccentColor)
		title.Text = rink.Name
		description.Text = string.format(
			"%s snowflakes  •  %d × %d rink",
			Format.multiplier(rink.Multiplier),
			rink.Size.X,
			rink.Size.Y
		)
		button.Activated:Connect(function()
			if button.Active then
				purchase("Rink", rink.Id)
			end
		end)
		table.insert(cards, function(profile)
			if Formulas.isRinkUnlocked(profile, rink.Id) then
				setButton(button, "Unlocked", false)
			else
				setButton(
					button,
					price(rink.Price),
					true,
					if profile.Snowflakes >= rink.Price then Colors.Success else Colors.PanelLighter
				)
			end
		end)
	end
end

local function selectTab(name)
	currentTab = name
	for tabName, tab in tabs do
		local selected = tabName == name
		tab.page.Visible = selected
		tab.button.BackgroundColor3 = if selected then Colors.Accent else Colors.PanelLight
	end
end

local function buildShop(parent)
	shopWindow = window("Shop", "⛸ SKATE SHOP", UDim2.fromScale(0.92, 0.84), Vector2.new(680, 500), parent)

	local tabBar = create("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(16, 60),
		Size = UDim2.new(1, -32, 0, 40),
		Parent = shopWindow,
	}, {
		create("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			Padding = UDim.new(0, 8),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})

	local pages = {
		{ "Skates", "⛸ Skates", buildSkatesPage },
		{ "Upgrades", "💪 Upgrades", buildUpgradesPage },
		{ "Rinks", "🗺 Rinks", buildRinksPage },
	}
	for order, info in pages do
		local name = info[1]
		local button = UI.button({
			BackgroundColor3 = Colors.PanelLight,
			LayoutOrder = order,
			Size = UDim2.new(1 / #pages, -6, 1, 0),
			Text = info[2],
			Parent = tabBar,
		}, { UI.maxText(20), UI.padding(6) })
		local page = create("ScrollingFrame", {
			Name = name,
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			CanvasSize = UDim2.new(),
			Position = UDim2.fromOffset(16, 110),
			ScrollBarImageColor3 = Colors.Accent,
			ScrollBarThickness = 6,
			Size = UDim2.new(1, -24, 1, -122),
			Visible = false,
			Parent = shopWindow,
		}, {
			create("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }),
		})
		info[3](page)
		tabs[name] = { button = button, page = page }
		button.Activated:Connect(function()
			selectTab(name)
		end)
	end
	selectTab(currentTab)
end

-- Rebirth window ------------------------------------------------------------------------

local function buildRebirth(parent)
	rebirthWindow = window("Rebirth", "🔄 REBIRTH", UDim2.new(0.86, 0, 0, 330), Vector2.new(480, 330), parent)

	label({
		Font = UI.BodyFont,
		Position = UDim2.fromOffset(20, 60),
		Size = UDim2.new(1, -40, 0, 54),
		Text = "Reset your snowflakes, skates and upgrades for a permanent snowflake boost. Unlocked rinks are kept!",
		TextColor3 = Colors.SubText,
		TextWrapped = true,
		Parent = rebirthWindow,
	}, { UI.maxText(17) })
	rebirthInfo = label({
		Position = UDim2.fromOffset(20, 124),
		Size = UDim2.new(1, -40, 0, 28),
		Text = "",
		Parent = rebirthWindow,
	}, { UI.maxText(24) })
	rebirthMultiplier = label({
		Position = UDim2.fromOffset(20, 156),
		Size = UDim2.new(1, -40, 0, 32),
		Text = "",
		TextColor3 = Colors.Purple,
		Parent = rebirthWindow,
	}, { UI.maxText(28), UI.textStroke(1.5) })

	local bar = create("Frame", {
		BackgroundColor3 = Colors.PanelLight,
		Position = UDim2.fromOffset(20, 198),
		Size = UDim2.new(1, -40, 0, 26),
		Parent = rebirthWindow,
	}, { UI.corner(13) })
	rebirthFill = create("Frame", {
		BackgroundColor3 = Colors.Purple,
		Size = UDim2.fromScale(0, 1),
		Parent = bar,
	}, { UI.corner(13) })
	rebirthProgress = label({
		Size = UDim2.fromScale(1, 1),
		Text = "",
		ZIndex = 2,
		Parent = bar,
	}, { UI.padding(4), UI.textStroke(1.5) })

	rebirthButton = UI.button({
		AnchorPoint = Vector2.new(0.5, 1),
		BackgroundColor3 = Colors.Purple,
		Position = UDim2.new(0.5, 0, 1, -18),
		Size = UDim2.new(1, -40, 0, 56),
		Text = "",
		Parent = rebirthWindow,
	}, { UI.maxText(26), UI.padding(8) })
	rebirthButton.Activated:Connect(function()
		if not rebirthButton.Active then
			return
		end
		-- Rebirthing wipes progress, so ask for a second click.
		if os.clock() > rebirthConfirmUntil then
			rebirthConfirmUntil = os.clock() + 3
			rebirthButton.Text = "Click again to confirm"
			return
		end
		rebirthConfirmUntil = 0
		purchase("Rebirth")
	end)
end

local function refreshRebirth(profile)
	local cost = Formulas.rebirthCost(profile.Rebirths)
	local current = Formulas.rebirthMultiplier(profile)
	local nextMultiplier = 1 + (profile.Rebirths + 1) * Config.Rebirth.MultiplierPerRebirth
	rebirthInfo.Text = string.format("Rebirths: %d", profile.Rebirths)
	rebirthMultiplier.Text =
		string.format("%s  →  %s snowflakes", Format.multiplier(current), Format.multiplier(nextMultiplier))
	rebirthFill.Size = UDim2.fromScale(math.clamp(profile.Snowflakes / cost, 0, 1), 1)
	rebirthProgress.Text = string.format("%s / %s", Format.abbreviate(profile.Snowflakes), price(cost))
	if os.clock() > rebirthConfirmUntil then
		local affordable = profile.Snowflakes >= cost
		setButton(rebirthButton, if affordable then "Rebirth!" else "Need " .. price(cost), affordable, Colors.Purple)
	end
end

local function refresh(profile)
	for _, update in cards do
		update(profile)
	end
	refreshRebirth(profile)
end

-- Public -----------------------------------------------------------------------------

function ShopUI.openShop(tab)
	rebirthWindow.Visible = false
	selectTab(tab or currentTab)
	shopWindow.Visible = true
end

function ShopUI.toggleShop()
	if shopWindow.Visible then
		shopWindow.Visible = false
	else
		ShopUI.openShop()
	end
end

function ShopUI.openRebirth()
	shopWindow.Visible = false
	rebirthWindow.Visible = true
end

function ShopUI.toggleRebirth()
	if rebirthWindow.Visible then
		rebirthWindow.Visible = false
	else
		ShopUI.openRebirth()
	end
end

function ShopUI.init()
	local screen = create("ScreenGui", {
		Name = "ShopUI",
		DisplayOrder = 5,
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = player:WaitForChild("PlayerGui"),
	})
	buildShop(screen)
	buildRebirth(screen)

	ClientData.observe(refresh)

	ProximityPromptService.PromptTriggered:Connect(function(prompt)
		local action = prompt:GetAttribute("Action")
		if action == "OpenShop" then
			ShopUI.openShop("Skates")
		elseif action == "OpenRebirth" then
			ShopUI.openRebirth()
		end
	end)
end

return ShopUI
