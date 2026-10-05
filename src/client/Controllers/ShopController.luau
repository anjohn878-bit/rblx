--[[
	ShopController
	The upgrade shop: Hospital levels, special Rooms, Auto Doctors and Boosts.
	Prices are computed with the shared Economy module for display; the
	server re-validates every purchase.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local AutoDoctors = require(Config:WaitForChild("AutoDoctors"))
local HospitalLevels = require(Config:WaitForChild("HospitalLevels"))
local Improvements = require(Config:WaitForChild("Improvements"))
local Rooms = require(Config:WaitForChild("Rooms"))
local Economy = require(Shared:WaitForChild("Economy"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Format = require(Shared:WaitForChild("Util"):WaitForChild("Format"))
local Signal = require(Shared:WaitForChild("Util"):WaitForChild("Signal"))
local UIKit = require(script.Parent.Parent.UI.UIKit)
local Theme = UIKit.Theme

local ShopController = {}
ShopController.Opened = Signal.new()

local controllers: any = nil
local panel: Frame
local list: ScrollingFrame
local tabButtons: { [string]: TextButton } = {}
local currentTab = "Hospital"
local isOpen = false
local busy = false

local TABS = {
	{ Id = "Hospital", Text = "🏥 Hospital", Color = Theme.Colors.Blue },
	{ Id = "Rooms", Text = "🚪 Rooms", Color = Theme.Colors.Teal },
	{ Id = "Doctors", Text = "🤖 Doctors", Color = Theme.Colors.Purple },
	{ Id = "Boosts", Text = "📈 Boosts", Color = Theme.Colors.Orange },
}

-- What can be bought right now (used for the HUD badge) ---------------------------
type Offer = { Cost: number, Available: boolean }

local function collectOffers(state: any): { Offer }
	local offers = {}
	local nextLevel = HospitalLevels.GetNext(state.HospitalLevel)
	if nextLevel then
		table.insert(offers, { Cost = nextLevel.Cost, Available = true })
	end
	for _, room in Rooms.List do
		if not state.Rooms[room.Id] then
			table.insert(offers, { Cost = room.Cost, Available = state.HospitalLevel >= room.RequiredLevel })
		end
	end
	local level = HospitalLevels.Get(state.HospitalLevel)
	if #state.Doctors < level.ExamRooms then
		table.insert(offers, { Cost = Economy.HireCost(#state.Doctors), Available = true })
	end
	for _, tier in state.Doctors do
		local nextTier = AutoDoctors.Tiers[tier + 1]
		if nextTier then
			table.insert(offers, { Cost = nextTier.UpgradeCost, Available = state.HospitalLevel >= nextTier.RequiredLevel })
		end
	end
	for _, item in Improvements.List do
		local cost = Economy.ImprovementCost(item.Id, Economy.ImprovementLevel(state, item.Id))
		if cost then
			table.insert(offers, { Cost = cost, Available = true })
		end
	end
	return offers
end

function ShopController.CountAffordable(state: any): number
	local count = 0
	for _, offer in collectOffers(state) do
		if offer.Available and offer.Cost <= state.Money then
			count += 1
		end
	end
	return count
end

-- Purchasing ---------------------------------------------------------------------------

local function purchase(kind: string, arg: any, card: Frame?)
	if busy then
		return
	end
	busy = true
	task.spawn(function()
		local ok, result = pcall(function()
			return Remotes.Function("Purchase"):InvokeServer(kind, arg)
		end)
		busy = false
		if not ok or type(result) ~= "table" then
			controllers.NotificationController.Toast("Purchase failed, try again!", "Error")
			return
		end
		if result.Ok then
			if card then
				UIKit.Bounce(card, 1.05)
			end
		else
			controllers.SoundController.Play("Wrong")
			controllers.NotificationController.Toast(result.Message or "Can't buy that yet", "Error")
			if card then
				UIKit.Shake(card)
			end
		end
	end)
end

-- Card building --------------------------------------------------------------------------

type CardSpec = {
	Emoji: string,
	Title: string,
	Description: string,
	ButtonText: string?,
	ButtonColor: Color3?,
	Cost: number?,
	Money: number,
	Disabled: boolean?,
	Highlight: Color3?,
	Height: number?,
	OnBuy: ((card: Frame) -> ())?,
}

local function clearList()
	for _, child in list:GetChildren() do
		if not child:IsA("UIListLayout") and not child:IsA("UIPadding") then
			child:Destroy()
		end
	end
end

local cardOrder = 0

local function addCard(spec: CardSpec): Frame
	cardOrder += 1
	local height = spec.Height or 104
	local card = UIKit.New("Frame", {
		Size = UDim2.new(1, -16, 0, height),
		BackgroundColor3 = Theme.Colors.White,
		LayoutOrder = cardOrder,
		Parent = list,
	}, {
		UIKit.Corner(16),
		UIKit.Stroke(3, spec.Highlight or Theme.Colors.PanelAlt:Lerp(Theme.Colors.Stroke, 0.25)),
	})
	local iconBack = UIKit.New("Frame", {
		Size = UDim2.fromOffset(78, 78),
		Position = UDim2.new(0, 12, 0.5, -39),
		BackgroundColor3 = Theme.Colors.PanelAlt,
		Parent = card,
	}, {
		UIKit.Corner(39),
	})
	UIKit.Label({ Text = spec.Emoji, TextSize = 44, Size = UDim2.fromScale(1, 1), Parent = iconBack })

	local hasButton = spec.ButtonText ~= nil
	local textWidth = if hasButton then -310 else -120
	UIKit.Label({
		Text = spec.Title,
		TextSize = 25,
		TextColor3 = Theme.Colors.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, textWidth, 0, 30),
		Position = UDim2.fromOffset(104, 10),
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = card,
	})
	UIKit.Label({
		Text = spec.Description,
		Font = Theme.BodyFont,
		TextSize = 15,
		TextColor3 = Theme.Colors.TextMuted,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextWrapped = true,
		Size = UDim2.new(1, textWidth, 1, -46),
		Position = UDim2.fromOffset(104, 42),
		Parent = card,
	})

	if hasButton then
		local affordable = spec.Cost == nil or spec.Money >= spec.Cost
		local color = spec.ButtonColor or Theme.Colors.Green
		if spec.Disabled then
			color = Theme.Colors.Gray
		elseif not affordable then
			color = Theme.Colors.GrayDark
		end
		local button = UIKit.Button({
			Text = spec.ButtonText :: string,
			Color = color,
			Size = UDim2.fromOffset(190, 68),
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -14, 0.5, 0),
			TextSize = 22,
			Parent = card,
			OnClick = function()
				if not spec.Disabled and spec.OnBuy then
					spec.OnBuy(card)
				end
			end,
		})
		if spec.Cost and not spec.Disabled and not affordable then
			UIKit.Label({
				Text = "Need " .. Format.Money(spec.Cost - spec.Money) .. " more",
				Font = Theme.BodyFont,
				TextSize = 13,
				TextColor3 = Theme.Colors.Red,
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.new(0.5, 0, 1, 2),
				Size = UDim2.new(1, 0, 0, 14),
				Parent = button,
			})
		end
	end
	return card
end

local function header(text: string)
	cardOrder += 1
	UIKit.Label({
		Text = text,
		TextSize = 20,
		TextColor3 = Theme.Colors.Text,
		TextWrapped = true,
		Size = UDim2.new(1, -16, 0, 44),
		LayoutOrder = cardOrder,
		Parent = list,
	})
end

-- Tabs ----------------------------------------------------------------------------------------

local function renderHospital(state: any)
	local current = HospitalLevels.Get(state.HospitalLevel)
	local nextLevel = HospitalLevels.GetNext(state.HospitalLevel)
	addCard({
		Emoji = "🏥",
		Title = string.format("Current: Lv.%d %s", current.Level, current.Name),
		Description = table.concat(current.Perks, " • "),
		Money = state.Money,
		Highlight = Theme.Colors.Blue,
	})
	if nextLevel then
		addCard({
			Emoji = "⬆️",
			Title = string.format("Lv.%d %s", nextLevel.Level, nextLevel.Name),
			Description = table.concat(nextLevel.Perks, " • "),
			ButtonText = "UPGRADE\n" .. Format.Money(nextLevel.Cost),
			ButtonColor = Theme.Colors.Green,
			Cost = nextLevel.Cost,
			Money = state.Money,
			Highlight = Theme.Colors.Yellow,
			Height = 120,
			OnBuy = function(card)
				purchase("HospitalLevel", nil, card)
			end,
		})
		local after = HospitalLevels.GetNext(nextLevel.Level)
		if after then
			addCard({
				Emoji = "🔭",
				Title = string.format("Then: Lv.%d %s", after.Level, after.Name),
				Description = "Costs " .. Format.Money(after.Cost) .. ". Keep growing your hospital!",
				Money = state.Money,
			})
		end
	else
		addCard({
			Emoji = "🏆",
			Title = "Max level reached!",
			Description = "Your hospital is legendary. Fill it with the best doctors and rooms!",
			Money = state.Money,
		})
	end
end

local function renderRooms(state: any)
	header("Special rooms give your hospital permanent bonuses ✨")
	for _, room in Rooms.List do
		local owned = state.Rooms[room.Id] == true
		local locked = state.HospitalLevel < room.RequiredLevel
		local buttonText
		if owned then
			buttonText = "OWNED ✔"
		elseif locked then
			buttonText = "🔒 Hospital\nLv." .. room.RequiredLevel
		else
			buttonText = "UNLOCK\n" .. Format.Money(room.Cost)
		end
		addCard({
			Emoji = room.Emoji,
			Title = room.Name,
			Description = room.Benefit,
			ButtonText = buttonText,
			ButtonColor = if owned then Theme.Colors.Green else Theme.Colors.Teal,
			Cost = if owned or locked then nil else room.Cost,
			Money = state.Money,
			Disabled = owned or locked,
			Highlight = if owned then room.Color else nil,
			OnBuy = function(card)
				purchase("Room", room.Id, card)
			end,
		})
	end
end

local function renderDoctors(state: any)
	local level = HospitalLevels.Get(state.HospitalLevel)
	local owned = #state.Doctors
	header(string.format("🤖 Auto Doctors treat patients for you! (%d / %d exam rooms staffed)", owned, level.ExamRooms))
	local firstTier = AutoDoctors.Tiers[1]
	if owned < level.ExamRooms then
		local cost = Economy.HireCost(owned)
		addCard({
			Emoji = "🥼",
			Title = "Hire " .. firstTier.Name,
			Description = string.format("Works in Exam Room %d. Treats 1 patient every %ss, forever.", owned + 1, tostring(firstTier.TreatTime)),
			ButtonText = "HIRE\n" .. Format.Money(cost),
			ButtonColor = Theme.Colors.Purple,
			Cost = cost,
			Money = state.Money,
			Highlight = Theme.Colors.Purple,
			OnBuy = function(card)
				purchase("HireDoctor", nil, card)
			end,
		})
	else
		addCard({
			Emoji = "🏗️",
			Title = "All exam rooms are staffed",
			Description = "Upgrade your hospital to build more exam rooms and hire more doctors.",
			Money = state.Money,
		})
	end
	for slot, tier in state.Doctors do
		local info = AutoDoctors.Tiers[tier]
		local nextTier = AutoDoctors.Tiers[tier + 1]
		local buttonText, cost, disabled
		if not nextTier then
			buttonText = "MAX ⭐"
			disabled = true
		elseif state.HospitalLevel < nextTier.RequiredLevel then
			buttonText = "🔒 Hospital\nLv." .. nextTier.RequiredLevel
			disabled = true
		else
			buttonText = "UPGRADE\n" .. Format.Money(nextTier.UpgradeCost)
			cost = nextTier.UpgradeCost
		end
		local description = string.format("Treats 1 patient every %ss.", tostring(info.TreatTime))
		if nextTier then
			description ..= string.format(" Next: %s (%ss)", nextTier.Name, tostring(nextTier.TreatTime))
		end
		addCard({
			Emoji = if info.Robot then "🤖" else "🩺",
			Title = string.format("Room %d · %s", slot, info.Name),
			Description = description,
			ButtonText = buttonText,
			ButtonColor = Theme.Colors.Blue,
			Cost = cost,
			Money = state.Money,
			Disabled = disabled,
			OnBuy = function(card)
				purchase("UpgradeDoctor", slot, card)
			end,
		})
	end
end

local function renderBoosts(state: any)
	header("Boosts stack up: buy them again and again! 📈")
	for _, item in Improvements.List do
		local current = Economy.ImprovementLevel(state, item.Id)
		local cost = Economy.ImprovementCost(item.Id, current)
		addCard({
			Emoji = item.Emoji,
			Title = string.format("%s  (Lv %d/%d)", item.Name, current, item.MaxLevel),
			Description = item.Description,
			ButtonText = if cost then "BUY\n" .. Format.Money(cost) else "MAX ⭐",
			ButtonColor = Theme.Colors.Orange,
			Cost = cost,
			Money = state.Money,
			Disabled = cost == nil,
			OnBuy = function(card)
				purchase("Improvement", item.Id, card)
			end,
		})
	end
end

local function render()
	local state = controllers.ClientState.Get()
	if not state or not isOpen then
		return
	end
	local scroll = list.CanvasPosition
	clearList()
	cardOrder = 0
	if currentTab == "Hospital" then
		renderHospital(state)
	elseif currentTab == "Rooms" then
		renderRooms(state)
	elseif currentTab == "Doctors" then
		renderDoctors(state)
	else
		renderBoosts(state)
	end
	list.CanvasPosition = scroll
	for id, button in tabButtons do
		local tab
		for _, t in TABS do
			if t.Id == id then
				tab = t
			end
		end
		UIKit.SetButtonColor(button, if id == currentTab then tab.Color else Theme.Colors.Gray)
	end
end

function ShopController.SetTab(tabId: string)
	if currentTab ~= tabId then
		currentTab = tabId
		list.CanvasPosition = Vector2.zero
	end
	render()
end

function ShopController.Open(tabId: string?)
	if tabId then
		currentTab = tabId
	end
	controllers.StatsController.Close()
	isOpen = true
	panel.Visible = true
	UIKit.PopIn(panel)
	controllers.SoundController.Play("Open")
	render()
	ShopController.Opened:Fire()
end

function ShopController.Close()
	isOpen = false
	panel.Visible = false
end

function ShopController.Toggle()
	if isOpen then
		ShopController.Close()
	else
		ShopController.Open()
	end
end

function ShopController.IsOpen(): boolean
	return isOpen
end

function ShopController.Init(all: any)
	controllers = all
	local gui = UIKit.New("ScreenGui", {
		Name = "Shop",
		ResetOnSpawn = false,
		DisplayOrder = 5,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
	})
	local content
	panel, content = UIKit.Panel({
		Name = "ShopPanel",
		Title = "🛒 HOSPITAL SHOP",
		Size = Vector2.new(780, 540),
		Color = Theme.Colors.Yellow,
		Parent = gui,
		OnClose = ShopController.Close,
	})

	local tabs = UIKit.New("Frame", {
		Name = "Tabs",
		Size = UDim2.new(1, -24, 0, 54),
		Position = UDim2.fromOffset(12, 10),
		BackgroundTransparency = 1,
		Parent = content,
	}, {
		UIKit.List(Enum.FillDirection.Horizontal, 10),
	})
	for index, tab in TABS do
		tabButtons[tab.Id] = UIKit.Button({
			Text = tab.Text,
			Color = Theme.Colors.Gray,
			Size = UDim2.fromOffset(175, 48),
			TextSize = 22,
			LayoutOrder = index,
			Parent = tabs,
			OnClick = function()
				ShopController.SetTab(tab.Id)
			end,
		})
	end

	list = UIKit.New("ScrollingFrame", {
		Name = "List",
		Position = UDim2.fromOffset(12, 74),
		Size = UDim2.new(1, -24, 1, -86),
		BackgroundColor3 = Theme.Colors.PanelAlt,
		BorderSizePixel = 0,
		ScrollBarThickness = 8,
		ScrollBarImageColor3 = Theme.Colors.GrayDark,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		Parent = content,
	}, {
		UIKit.Corner(14),
		UIKit.List(Enum.FillDirection.Vertical, 10),
		UIKit.Padding(10, 8),
	})
end

function ShopController.Start()
	local pending = false
	controllers.ClientState.Changed:Connect(function()
		if isOpen and not pending then
			pending = true
			task.delay(0.4, function()
				pending = false
				render()
			end)
		end
	end)
end

return ShopController
