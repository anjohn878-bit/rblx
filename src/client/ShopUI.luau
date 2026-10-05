--!strict
-- The seed shop window: live stock, restock countdown, buy buttons.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Birds = require(Shared:WaitForChild("Birds"))
local Clock = require(Shared:WaitForChild("Clock"))
local Config = require(Shared:WaitForChild("Config"))
local Format = require(Shared:WaitForChild("Format"))
local Growth = require(Shared:WaitForChild("Growth"))
local PlantModels = require(Shared:WaitForChild("PlantModels"))
local Remotes = require(Shared:WaitForChild("Remotes")).get()
local Seeds = require(Shared:WaitForChild("Seeds"))
local Types = require(Shared:WaitForChild("Types"))

local State = require(script.Parent.State)
local Toasts = require(script.Parent.Toasts)
local Ui = require(script.Parent.Ui)
local Viewport = require(script.Parent.Viewport)

local ShopUI = {}

type Row = {
	seed: Types.SeedDef,
	frame: Frame,
	price: TextLabel,
	stock: TextLabel,
	buyOne: TextButton,
	buyMax: TextButton,
}

local overlay: TextButton
local timerLabel: TextLabel
local rows: { Row } = {}
local busy = false

local function birdsFor(seed: Types.SeedDef): string
	local names = {}
	for _, entry in seed.birds do
		local bird = Birds.get(entry.id)
		if bird and bird.rarity == seed.rarity then
			table.insert(names, bird.name)
		end
	end
	return table.concat(names, ", ")
end

local function buy(seedId: string, amount: number)
	if busy then
		return
	end
	busy = true
	task.spawn(function()
		local ok, result = pcall(function()
			return Remotes.BuySeed:InvokeServer(seedId, amount)
		end)
		busy = false
		if ok then
			Toasts.result(result)
		end
	end)
end

local function refresh()
	for _, row in rows do
		local seed = row.seed
		local inStock = State.stock[seed.id] or 0
		local afford = math.floor(State.feathers / seed.price)
		local maxN = math.min(inStock, afford, Config.MAX_BUY_AMOUNT)

		row.price.Text = Format.feathers(seed.price)
		if inStock > 0 then
			row.stock.Text = `In stock: {inStock}`
			row.stock.TextColor3 = Ui.COLORS.good
		else
			row.stock.Text = "Sold out"
			row.stock.TextColor3 = Ui.COLORS.bad
		end
		Ui.setEnabled(row.buyOne, inStock > 0 and afford >= 1, Ui.COLORS.good)
		row.buyOne.Text = "Buy"
		Ui.setEnabled(row.buyMax, maxN >= 2, Color3.fromRGB(82, 160, 216))
		row.buyMax.Text = if maxN >= 2 then `Buy x{maxN}` else "Buy max"
		row.frame.LayoutOrder = seed.tier
	end
end

local function buildRow(seed: Types.SeedDef, parent: Instance): Row
	local color = Config.RARITY_COLORS[seed.rarity]
	local frame = Ui.new("Frame", {
		Name = seed.id,
		Size = UDim2.new(1, -8, 0, 124),
		BackgroundColor3 = Ui.COLORS.row,
		Parent = parent,
	}, { Ui.corner(14), Ui.stroke(color, 2, 0.35) })

	local preview = Ui.new("ViewportFrame", {
		Position = UDim2.fromOffset(10, 12),
		Size = UDim2.fromOffset(100, 100),
		BackgroundColor3 = Ui.COLORS.bg,
		BackgroundTransparency = 0,
		Parent = frame,
	}, { Ui.corner(12) })
	local model = PlantModels.build(seed.id, CFrame.new(), true)
	if model then
		Viewport.mount(preview, model, Vector3.new(0.4, 0.3, -1))
		preview.BackgroundTransparency = 0
	end

	local info = Ui.new("Frame", {
		Position = UDim2.fromOffset(122, 8),
		Size = UDim2.new(1, -122 - 138, 1, -16),
		BackgroundTransparency = 1,
		Parent = frame,
	})
	Ui.label({
		Size = UDim2.new(1, 0, 0, 28),
		Text = seed.name .. " Seed",
		Font = Ui.FONT,
		TextSize = 22,
		TextColor3 = color,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = info,
	})
	Ui.label({
		Position = UDim2.fromOffset(0, 28),
		Size = UDim2.new(1, 0, 0, 16),
		Text = seed.rarity,
		Font = Ui.FONT_BOLD,
		TextSize = 12,
		TextColor3 = color,
		Parent = info,
	})
	Ui.label({
		Position = UDim2.fromOffset(0, 46),
		Size = UDim2.new(1, 0, 0, 30),
		Text = seed.blurb,
		TextSize = 13,
		TextColor3 = Ui.COLORS.muted,
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
		Parent = info,
	})

	local perVisit = Growth.expectedVisitValue(seed, function(id: string): number
		local bird = Birds.get(id)
		return if bird then bird.value else 0
	end)
	local perches = if #seed.perches == 1 then "1 perch" else `{#seed.perches} perches`
	Ui.label({
		Position = UDim2.fromOffset(0, 78),
		Size = UDim2.new(1, 0, 0, 16),
		Text = `Grows in {Format.growTime(seed.growTime)}  |  {perches}  |  ~{Format.feathers(perVisit)} per visit`,
		Font = Ui.FONT_BOLD,
		TextSize = 12,
		TextColor3 = Ui.COLORS.text,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = info,
	})
	Ui.label({
		Position = UDim2.fromOffset(0, 94),
		Size = UDim2.new(1, 0, 0, 16),
		Text = "Attracts: " .. birdsFor(seed),
		TextSize = 12,
		TextColor3 = Ui.COLORS.muted,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = info,
	})

	local right = Ui.new("Frame", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -10, 0, 8),
		Size = UDim2.fromOffset(120, 108),
		BackgroundTransparency = 1,
		Parent = frame,
	})
	local price = Ui.label({
		Size = UDim2.new(1, 0, 0, 26),
		Font = Ui.FONT,
		TextSize = 22,
		TextColor3 = Ui.COLORS.gold,
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = right,
	})
	local stock = Ui.label({
		Position = UDim2.fromOffset(0, 26),
		Size = UDim2.new(1, 0, 0, 16),
		Font = Ui.FONT_BOLD,
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = right,
	})
	local buyOne =
		Ui.button({ Position = UDim2.fromOffset(0, 46), Size = UDim2.new(1, 0, 0, 28), TextSize = 16, Parent = right })
	local buyMax =
		Ui.button({ Position = UDim2.fromOffset(0, 78), Size = UDim2.new(1, 0, 0, 28), TextSize = 15, Parent = right })

	buyOne.Activated:Connect(function()
		buy(seed.id, 1)
	end)
	buyMax.Activated:Connect(function()
		local inStock = State.stock[seed.id] or 0
		local afford = math.floor(State.feathers / seed.price)
		local n = math.min(inStock, afford, Config.MAX_BUY_AMOUNT)
		if n >= 2 then
			buy(seed.id, n)
		end
	end)

	return { seed = seed, frame = frame, price = price, stock = stock, buyOne = buyOne, buyMax = buyMax }
end

function ShopUI.isOpen(): boolean
	return overlay.Visible
end

function ShopUI.close()
	overlay.Visible = false
end

function ShopUI.open()
	if overlay.Visible then
		return
	end
	overlay.Visible = true
	refresh()
	task.spawn(function()
		while overlay.Visible do
			timerLabel.Text = "New stock in " .. Format.duration(State.nextRestock - Clock.now())
			task.wait(0.25)
		end
	end)
end

function ShopUI.toggle()
	if overlay.Visible then
		ShopUI.close()
	else
		ShopUI.open()
	end
end

function ShopUI.init(gui: ScreenGui)
	overlay = Ui.new("TextButton", {
		Name = "ShopOverlay",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.5,
		AutoButtonColor = false,
		Text = "",
		Visible = false,
		ZIndex = 10,
		Parent = gui,
	})
	overlay.Activated:Connect(ShopUI.close)

	local panel = Ui.new("Frame", {
		Name = "Panel",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.82, 0.82),
		BackgroundColor3 = Ui.COLORS.panel,
		Active = true, -- swallow clicks so the overlay behind doesn't close
		Parent = overlay,
	}, {
		Ui.corner(20),
		Ui.stroke(Color3.fromRGB(214, 112, 60), 4),
		Ui.new("UISizeConstraint", { MaxSize = Vector2.new(760, 580), MinSize = Vector2.new(300, 280) }),
	})

	Ui.label({
		Position = UDim2.fromOffset(20, 10),
		Size = UDim2.new(0.5, 0, 0, 40),
		Text = "Seed Shop",
		Font = Ui.FONT,
		TextSize = 34,
		TextColor3 = Ui.COLORS.gold,
		Parent = panel,
	})
	timerLabel = Ui.label({
		Position = UDim2.fromOffset(22, 48),
		Size = UDim2.new(0.6, 0, 0, 20),
		Text = "",
		Font = Ui.FONT_BOLD,
		TextSize = 14,
		TextColor3 = Ui.COLORS.muted,
		Parent = panel,
	})

	local close = Ui.button({
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -14, 0, 14),
		Size = UDim2.fromOffset(40, 40),
		Text = "X",
		BackgroundColor3 = Ui.COLORS.bad,
		Parent = panel,
	})
	close.Activated:Connect(ShopUI.close)

	local list = Ui.new("ScrollingFrame", {
		Position = UDim2.fromOffset(12, 76),
		Size = UDim2.new(1, -24, 1, -88),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		Parent = panel,
	}, { Ui.new("UIListLayout", { Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }) })

	for _, seed in Seeds.list do
		table.insert(rows, buildRow(seed, list))
	end

	State.changed:Connect(refresh)
	State.stockChanged:Connect(refresh)
	refresh()
end

return ShopUI
