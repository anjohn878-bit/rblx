--[[
	HUDController
	Always-visible UI:
	  top     - money, hospital level, patients treated, "next upgrade" goal bar
	  left    - SHOP / STATS / HOME buttons
	  bottom  - doctor level XP bar and combo streak
	  right   - "patients need you!" alert with a GO button
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local HospitalLevels = require(Shared:WaitForChild("Config"):WaitForChild("HospitalLevels"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Format = require(Shared:WaitForChild("Util"):WaitForChild("Format"))
local UIKit = require(script.Parent.Parent.UI.UIKit)
local Theme = UIKit.Theme

local HUDController = {}

local controllers: any = nil
local player = Players.LocalPlayer

local moneyLabel: TextLabel
local moneyFrame: Frame
local levelLabel: TextLabel
local treatedLabel: TextLabel
local goalFill: Frame
local goalLabel: TextLabel
local doctorLabel: TextLabel
local xpFill: Frame
local xpLabel: TextLabel
local comboLabel: TextLabel
local shopButton: TextButton
local shopBadge: TextLabel
local needsFrame: Frame
local needsLabel: TextLabel
local topContainer: Frame

local displayedMoney = 0
local targetMoney = 0
local needsTarget: Model? = nil

local function pill(parent: Instance, width: number, order: number): TextLabel
	local frame = UIKit.New("Frame", {
		Size = UDim2.fromOffset(width, 36),
		BackgroundColor3 = Theme.Colors.PanelDark,
		BackgroundTransparency = 0.1,
		LayoutOrder = order,
		Parent = parent,
	}, {
		UIKit.Corner(18),
		UIKit.Stroke(2, Theme.Colors.Stroke),
	})
	return UIKit.Label({
		Size = UDim2.new(1, -16, 1, 0),
		Position = UDim2.fromOffset(8, 0),
		TextSize = 19,
		Parent = frame,
	})
end

local function menuButton(parent: Instance, emoji: string, text: string, color: Color3, order: number, onClick: () -> ()): TextButton
	local holder = UIKit.New("Frame", {
		Size = UDim2.fromOffset(84, 98),
		BackgroundTransparency = 1,
		LayoutOrder = order,
		Parent = parent,
	})
	local button = UIKit.Button({
		Text = emoji,
		Color = color,
		Size = UDim2.fromOffset(76, 72),
		Position = UDim2.fromOffset(4, 0),
		TextSize = 38,
		Parent = holder,
		OnClick = onClick,
	})
	local label = UIKit.Label({
		Text = text,
		TextSize = 20,
		Size = UDim2.new(1, 0, 0, 24),
		Position = UDim2.fromOffset(0, 74),
		Parent = holder,
	})
	UIKit.TextStroke(2).Parent = label
	return button
end

function HUDController.Init(all: any)
	controllers = all
	local gui = UIKit.New("ScreenGui", {
		Name = "HUD",
		ResetOnSpawn = false,
		DisplayOrder = 1,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = player:WaitForChild("PlayerGui"),
	})

	-- Top: money + stats + goal ------------------------------------------------
	topContainer = UIKit.New("Frame", {
		Name = "Top",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 4),
		Size = UDim2.fromOffset(560, 160),
		BackgroundTransparency = 1,
		Parent = gui,
	})
	UIKit.Scaled(topContainer)

	moneyFrame = UIKit.New("Frame", {
		Name = "Money",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.fromOffset(310, 62),
		BackgroundColor3 = Theme.Colors.PanelDark,
		Parent = topContainer,
	}, {
		UIKit.Corner(31),
		UIKit.Stroke(4, Theme.Colors.Stroke),
	})
	UIKit.Label({
		Text = "💵",
		TextSize = 40,
		Size = UDim2.fromOffset(60, 62),
		Position = UDim2.fromOffset(6, 0),
		Parent = moneyFrame,
	})
	moneyLabel = UIKit.Label({
		Text = "$0",
		TextSize = 42,
		TextColor3 = Theme.Colors.Money,
		Size = UDim2.new(1, -76, 1, 0),
		Position = UDim2.fromOffset(62, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = moneyFrame,
	})
	UIKit.TextStroke(3).Parent = moneyLabel

	local row = UIKit.New("Frame", {
		Name = "Row",
		Position = UDim2.fromOffset(0, 68),
		Size = UDim2.new(1, 0, 0, 36),
		BackgroundTransparency = 1,
		Parent = topContainer,
	}, {
		UIKit.List(Enum.FillDirection.Horizontal, 8),
	})
	levelLabel = pill(row, 300, 1)
	treatedLabel = pill(row, 190, 2)

	local goalButton = UIKit.New("TextButton", {
		Name = "Goal",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 110),
		Size = UDim2.fromOffset(420, 34),
		BackgroundColor3 = Theme.Colors.PanelDark,
		AutoButtonColor = false,
		Text = "",
		Parent = topContainer,
	}, {
		UIKit.Corner(17),
		UIKit.Stroke(3, Theme.Colors.Stroke),
	})
	goalFill = UIKit.New("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		Parent = goalButton,
	}, {
		UIKit.Corner(17),
		UIKit.Gradient(Theme.Colors.Green, Theme.Colors.GreenDark),
	})
	goalLabel = UIKit.Label({
		Text = "",
		TextSize = 18,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 2,
		Parent = goalButton,
	})
	UIKit.TextStroke(2).Parent = goalLabel
	goalButton.Activated:Connect(function()
		controllers.ShopController.Open("Hospital")
	end)

	-- Left menu --------------------------------------------------------------------
	local menu = UIKit.New("Frame", {
		Name = "Menu",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 10, 0.5, 0),
		Size = UDim2.fromOffset(90, 320),
		BackgroundTransparency = 1,
		Parent = gui,
	}, {
		UIKit.List(Enum.FillDirection.Vertical, 4),
	})
	UIKit.Scaled(menu)
	shopButton = menuButton(menu, "🛒", "SHOP", Theme.Colors.Yellow, 1, function()
		controllers.ShopController.Toggle()
	end)
	shopBadge = UIKit.Label({
		Name = "Badge",
		Text = "!",
		TextSize = 22,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(1, -4, 0, 4),
		Size = UDim2.fromOffset(30, 30),
		BackgroundTransparency = 0,
		BackgroundColor3 = Theme.Colors.Red,
		ZIndex = 5,
		Visible = false,
		Parent = shopButton,
	})
	UIKit.Corner(15).Parent = shopBadge
	UIKit.Stroke(2, Theme.Colors.Stroke).Parent = shopBadge
	menuButton(menu, "📊", "STATS", Theme.Colors.Blue, 2, function()
		controllers.StatsController.Toggle()
	end)
	menuButton(menu, "🏠", "HOME", Theme.Colors.Green, 3, function()
		Remotes.Event("TeleportHome"):FireServer()
	end)

	-- Bottom: doctor level ------------------------------------------------------------
	local bottom = UIKit.New("Frame", {
		Name = "Doctor",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -10),
		Size = UDim2.fromOffset(460, 60),
		BackgroundColor3 = Theme.Colors.PanelDark,
		BackgroundTransparency = 0.1,
		Parent = gui,
	}, {
		UIKit.Corner(16),
		UIKit.Stroke(3, Theme.Colors.Stroke),
	})
	UIKit.Scaled(bottom)
	doctorLabel = UIKit.Label({
		Text = "🥼 Dr. Lv 1",
		TextSize = 22,
		Size = UDim2.fromOffset(150, 60),
		Position = UDim2.fromOffset(10, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = bottom,
	})
	local xpBar = UIKit.New("Frame", {
		Position = UDim2.fromOffset(160, 16),
		Size = UDim2.fromOffset(200, 28),
		BackgroundColor3 = Color3.fromRGB(20, 24, 40),
		Parent = bottom,
	}, {
		UIKit.Corner(14),
	})
	xpFill = UIKit.New("Frame", {
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		Parent = xpBar,
	}, {
		UIKit.Corner(14),
		UIKit.Gradient(Theme.Colors.Purple, Theme.Colors.Blue, 0),
	})
	xpLabel = UIKit.Label({
		Text = "0 / 50 XP",
		TextSize = 16,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 2,
		Parent = xpBar,
	})
	UIKit.TextStroke(2).Parent = xpLabel
	comboLabel = UIKit.Label({
		Text = "",
		TextSize = 24,
		TextColor3 = Theme.Colors.Orange,
		Size = UDim2.fromOffset(90, 60),
		Position = UDim2.fromOffset(366, 0),
		Parent = bottom,
	})
	UIKit.TextStroke(2).Parent = comboLabel

	-- Right: patients need you -----------------------------------------------------------
	needsFrame = UIKit.New("Frame", {
		Name = "NeedsYou",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -10, 0.42, 0),
		Size = UDim2.fromOffset(230, 110),
		BackgroundColor3 = Theme.Colors.PanelDark,
		Visible = false,
		Parent = gui,
	}, {
		UIKit.Corner(16),
		UIKit.Stroke(4, Theme.Colors.Yellow),
	})
	UIKit.Scaled(needsFrame)
	needsLabel = UIKit.Label({
		Text = "",
		TextSize = 20,
		TextWrapped = true,
		Size = UDim2.new(1, -16, 0, 50),
		Position = UDim2.fromOffset(8, 4),
		Parent = needsFrame,
	})
	UIKit.Button({
		Text = "GO! ➜",
		Color = Theme.Colors.Yellow,
		Size = UDim2.fromOffset(150, 44),
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 56),
		Parent = needsFrame,
		OnClick = function()
			if needsTarget then
				controllers.GuideController.PointTo(needsTarget, 12)
			end
		end,
	})
end

function HUDController.FlashMoney(amount: number)
	if amount <= 0 then
		return
	end
	UIKit.Bounce(moneyFrame, 1.08)
	local gain = UIKit.Label({
		Text = "+" .. Format.Money(amount),
		TextSize = 30,
		TextColor3 = Theme.Colors.Money,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(1, 8, 0.5, 0),
		Size = UDim2.fromOffset(160, 40),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = moneyFrame,
	})
	UIKit.TextStroke(2).Parent = gain
	UIKit.Tween(gain, 1, { Position = UDim2.new(1, 8, 0.5, -40), TextTransparency = 1 })
	task.delay(1.05, function()
		gain:Destroy()
	end)
end

local function updateGoal(state: any)
	local nextLevel = HospitalLevels.GetNext(state.HospitalLevel)
	if not nextLevel then
		goalFill.Size = UDim2.fromScale(1, 1)
		goalLabel.Text = "🏆 MAX HOSPITAL LEVEL!"
		return
	end
	local progress = math.clamp(state.Money / nextLevel.Cost, 0, 1)
	UIKit.Tween(goalFill, 0.3, { Size = UDim2.fromScale(math.max(progress, 0.04), 1) })
	if progress >= 1 then
		goalLabel.Text = string.format("✨ %s READY! Tap to upgrade ✨", nextLevel.Name)
	else
		goalLabel.Text = string.format("Next: %s  %s / %s", nextLevel.Name, Format.Money(state.Money), Format.Money(nextLevel.Cost))
	end
end

function HUDController.Update(state: any)
	targetMoney = state.Money
	local level = HospitalLevels.Get(state.HospitalLevel)
	levelLabel.Text = string.format("🏥 Lv.%d · %s", level.Level, level.Name)
	treatedLabel.Text = string.format("🩺 %s treated", Format.Short(state.PatientsTreated))
	doctorLabel.Text = string.format("🥼 Dr. Lv %d", state.DoctorLevel)
	local xpProgress = if state.DoctorXPNeeded > 0 then state.DoctorXP / state.DoctorXPNeeded else 1
	UIKit.Tween(xpFill, 0.3, { Size = UDim2.fromScale(math.clamp(xpProgress, 0.03, 1), 1) })
	xpLabel.Text = if state.DoctorXPNeeded > 0 then string.format("%d / %d XP", state.DoctorXP, state.DoctorXPNeeded) else "MAX LEVEL"
	if state.Combo and state.Combo >= 2 then
		comboLabel.Text = "🔥 x" .. state.Combo
	else
		comboLabel.Text = ""
	end
	updateGoal(state)

	local affordable = controllers.ShopController.CountAffordable(state)
	shopBadge.Visible = affordable > 0
	shopBadge.Text = tostring(affordable)
end

function HUDController.SetNeedsYou(count: number, target: Model?)
	needsTarget = target
	if count > 0 then
		if not needsFrame.Visible then
			needsFrame.Visible = true
			UIKit.PopIn(needsFrame)
		end
		needsLabel.Text = if count == 1 then "🔔 1 patient needs you!" else string.format("🔔 %d patients need you!", count)
	else
		needsFrame.Visible = false
	end
end

function HUDController.GetShopButton(): TextButton
	return shopButton
end

function HUDController.Start()
	controllers.ClientState.Changed:Connect(function(state)
		HUDController.Update(state)
	end)
	if controllers.ClientState.Get() then
		HUDController.Update(controllers.ClientState.Get())
	end

	-- Smooth money counter
	task.spawn(function()
		while true do
			local dt = task.wait(1 / 30)
			if displayedMoney ~= targetMoney then
				local diff = targetMoney - displayedMoney
				local step = diff * math.min(1, dt * 8)
				if math.abs(diff) < 1 or math.abs(step) < 0.5 then
					displayedMoney = targetMoney
				else
					displayedMoney += step
				end
				moneyLabel.Text = Format.Money(math.floor(displayedMoney + 0.5))
			end
		end
	end)
end

return HUDController
