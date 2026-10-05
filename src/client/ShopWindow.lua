-- The Seed Shop window: lists every seed with its stock, grow time and the
-- birds it attracts.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Birds = require(Shared.Birds)
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local PlantBuilder = require(Shared.PlantBuilder)
local Rarities = require(Shared.Rarities)
local Seeds = require(Shared.Seeds)
local Util = require(Shared.Util)
local Notifications = require(script.Parent.Notifications)
local Store = require(script.Parent.Store)
local UI = require(script.Parent.UI)
local Viewport = require(script.Parent.Viewport)

local ShopWindow = {}

local ROW_HEIGHT = 118
local PLANT_VIEW = Vector3.new(0.55, 0.45, 1)

local window, body, restockLabel
local rows = {} -- [seedId] = { Stock, Owned, Buy }
local built = false

local function birdNames(seed)
	local names = {}
	for _, entry in ipairs(seed.Birds) do
		table.insert(names, Birds.Get(entry.Id).Name)
	end
	return table.concat(names, ", ")
end

local function refresh()
	local data, shop = Store.Data, Store.Shop
	for _, seed in ipairs(Seeds.List) do
		local row = rows[seed.Id]
		if row then
			local stock = shop and shop.Stock[seed.Id] or 0
			local coins = data and data.Coins or 0
			local canBuy = stock > 0 and coins >= seed.Price
			row.Stock.Text = stock > 0 and ("x" .. stock .. " in stock") or "Sold out"
			row.Stock.TextColor3 = stock > 0 and UI.Colors.Green or UI.Colors.Red
			row.Owned.Text = "You have: " .. ((data and data.Seeds[seed.Id]) or 0)
			row.Buy.BackgroundColor3 = canBuy and UI.Colors.Green or UI.Colors.Grey
		end
	end
end

local function buildRow(seed)
	local row = UI.new("Frame", {
		Name = seed.Id,
		LayoutOrder = seed.Order,
		Size = UDim2.new(1, -12, 0, ROW_HEIGHT),
		BackgroundColor3 = UI.Colors.PanelDark,
		Parent = body,
	}, { UI.corner(12), UI.stroke(Rarities.Color(seed.Rarity), 2) })

	local view = UI.new("ViewportFrame", {
		Position = UDim2.fromOffset(8, 8),
		Size = UDim2.fromOffset(ROW_HEIGHT - 16, ROW_HEIGHT - 16),
		BackgroundColor3 = Color3.fromRGB(200, 230, 245),
		Parent = row,
	}, { UI.corner(10) })
	Viewport.Show(view, PlantBuilder.Build(seed, 4), PLANT_VIEW)

	local infoX = ROW_HEIGHT
	UI.label({
		Text = seed.Icon .. " " .. seed.Name,
		Font = UI.TitleFont,
		TextColor3 = Rarities.Color(seed.Rarity),
		TextStrokeTransparency = 0.7,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(infoX, 8),
		Size = UDim2.new(1, -infoX - 130, 0, 26),
		Parent = row,
	})
	local growTime = seed.GrowTime / math.max(Config.GrowthSpeed, 0.001)
	UI.label({
		Text = seed.Rarity .. "  •  ⏳ Grows in " .. Util.FormatTime(growTime),
		TextColor3 = UI.Colors.SubText,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(infoX, 36),
		Size = UDim2.new(1, -infoX - 130, 0, 18),
		Parent = row,
	})
	UI.label({
		Text = "🐦 Attracts: " .. birdNames(seed),
		TextColor3 = UI.Colors.Text,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Position = UDim2.fromOffset(infoX, 58),
		Size = UDim2.new(1, -infoX - 130, 0, 34),
		Parent = row,
	})
	local owned = UI.label({
		Text = "",
		TextColor3 = UI.Colors.SubText,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(infoX, 94),
		Size = UDim2.new(1, -infoX - 130, 0, 16),
		Parent = row,
	})

	local stock = UI.label({
		Text = "",
		Font = UI.TitleFont,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -10, 0, 14),
		Size = UDim2.fromOffset(112, 22),
		Parent = row,
	})
	local buy = UI.button({
		Text = "🪙 " .. Util.FormatNumber(seed.Price),
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -10, 1, -12),
		Size = UDim2.fromOffset(112, 48),
		Parent = row,
	})
	UI.stroke(UI.Colors.Wood, 2).Parent = buy

	local busy = false
	buy.Activated:Connect(function()
		if busy then
			return
		end
		busy = true
		local ok, success, message = pcall(function()
			return Net.BuySeed:InvokeServer(seed.Id)
		end)
		if ok then
			Notifications.Show(message or "", success and "Success" or "Error")
		end
		busy = false
	end)

	rows[seed.Id] = { Stock = stock, Owned = owned, Buy = buy }
end

local function build()
	if built then
		return
	end
	built = true
	UI.new("UIListLayout", {
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Parent = body,
	})
	UI.new("UIPadding", { PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 8), Parent = body })
	for _, seed in ipairs(Seeds.List) do
		buildRow(seed)
	end
	refresh()
end

function ShopWindow.Init(screenGui)
	window, body, restockLabel = UI.window(screenGui, "🌱 Seed Shop", function()
		ShopWindow.Close()
	end)
	Store.Changed:Connect(function()
		if built then
			refresh()
		end
	end)

	-- restock countdown
	task.spawn(function()
		while true do
			if window.Visible and Store.Shop then
				local remaining = Store.Shop.NextRestock - Store.Now()
				restockLabel.Text = remaining > 0 and ("New seeds in " .. Util.FormatTime(remaining)) or "Restocking..."
			end
			task.wait(0.25)
		end
	end)
end

function ShopWindow.Open()
	build()
	window.Visible = true
	UI.pop(window)
end

function ShopWindow.Close()
	window.Visible = false
end

function ShopWindow.IsOpen()
	return window.Visible
end

return ShopWindow
