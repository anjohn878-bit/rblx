-- Coins, birds befriended and the side buttons.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Pets = require(Shared:WaitForChild("Pets"))
local Util = require(Shared:WaitForChild("Util"))
local Store = require(script.Parent.Store)
local UI = require(script.Parent.UI)

local Hud = {}

local function pill(parent, position, icon, color)
	local frame = UI.new("Frame", {
		Position = position,
		Size = UDim2.fromOffset(190, 44),
		BackgroundColor3 = UI.Colors.Panel,
		Parent = parent,
	}, { UI.corner(22), UI.stroke(UI.Colors.Wood, 3) })
	UI.label({
		Text = icon,
		Position = UDim2.fromOffset(6, 4),
		Size = UDim2.fromOffset(36, 36),
		Parent = frame,
	})
	local value = UI.label({
		Text = "0",
		Font = UI.TitleFont,
		TextColor3 = color,
		TextStrokeTransparency = 0.6,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(46, 6),
		Size = UDim2.new(1, -56, 1, -12),
		Parent = frame,
	})
	return frame, value
end

local function sideButton(parent, order, icon, caption, color, onClick)
	local button = UI.button({
		LayoutOrder = order,
		Text = "",
		BackgroundColor3 = color,
		Size = UDim2.fromOffset(70, 70),
		Parent = parent,
	}, onClick)
	UI.stroke(UI.Colors.Wood, 3).Parent = button
	UI.label({
		Text = icon,
		Position = UDim2.fromOffset(0, 6),
		Size = UDim2.new(1, 0, 0, 36),
		Parent = button,
	})
	UI.label({
		Text = caption,
		Font = UI.TitleFont,
		TextColor3 = UI.Colors.White,
		TextStrokeTransparency = 0.5,
		Position = UDim2.new(0, 4, 1, -24),
		Size = UDim2.new(1, -8, 0, 18),
		Parent = button,
	})
	return button
end

-- callbacks = { OnSeeds, OnGarden, OnJournal, OnBirds, OnTrade }
function Hud.Init(screenGui, callbacks)
	local root = UI.new("Frame", {
		Name = "Hud",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Parent = screenGui,
	})

	local coinPill, coinLabel = pill(root, UDim2.fromOffset(12, 12), "🪙", UI.Colors.Gold)
	local _, birdLabel = pill(root, UDim2.fromOffset(12, 62), "🐦", Color3.fromRGB(90, 170, 230))

	local buttons = UI.new("Frame", {
		Name = "Buttons",
		-- below the coin and bird counters
		Position = UDim2.fromOffset(12, 116),
		Size = UDim2.fromOffset(70, 400),
		BackgroundTransparency = 1,
		Parent = root,
	}, {
		UI.new("UIListLayout", {
			Padding = UDim.new(0, 10),
			SortOrder = Enum.SortOrder.LayoutOrder,
			VerticalAlignment = Enum.VerticalAlignment.Top,
		}),
	})
	sideButton(buttons, 1, "🌱", "Seeds", Color3.fromRGB(95, 180, 80), callbacks.OnSeeds)
	sideButton(buttons, 2, "🏡", "Garden", Color3.fromRGB(205, 150, 80), callbacks.OnGarden)
	sideButton(buttons, 3, "📖", "Journal", Color3.fromRGB(90, 140, 220), callbacks.OnJournal)
	sideButton(buttons, 4, "🐦", "Birds", Color3.fromRGB(230, 120, 150), callbacks.OnBirds)
	sideButton(buttons, 5, "🤝", "Trade", Color3.fromRGB(150, 110, 210), callbacks.OnTrade)

	local lastCoins
	local function refresh()
		local data = Store.Data
		if not data then
			coinLabel.Text = "..."
			birdLabel.Text = "..."
			return
		end
		coinLabel.Text = Util.FormatNumber(data.Coins)
		birdLabel.Text = Pets.CountPets(data.Pets or {})
			.. "/"
			.. Config.MaxPets
			.. "  •  "
			.. Pets.CountEquipped(data.Pets or {})
			.. " out"
		if lastCoins and data.Coins ~= lastCoins then
			UI.pop(coinPill)
		end
		lastCoins = data.Coins
	end
	Store.Changed:Connect(function(what)
		if what == "Data" then
			refresh()
		end
	end)
	refresh()
end

return Hud
