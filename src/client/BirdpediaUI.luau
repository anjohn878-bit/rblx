--!strict
-- The field guide: every species in the game. Birds you haven't seen yet are
-- silhouettes with a hint about which seed attracts them.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BirdModel = require(Shared:WaitForChild("BirdModel"))
local Birds = require(Shared:WaitForChild("Birds"))
local Config = require(Shared:WaitForChild("Config"))
local Format = require(Shared:WaitForChild("Format"))
local Seeds = require(Shared:WaitForChild("Seeds"))
local Types = require(Shared:WaitForChild("Types"))

local State = require(script.Parent.State)
local Ui = require(script.Parent.Ui)
local Viewport = require(script.Parent.Viewport)

local BirdpediaUI = {}

type Card = {
	def: Types.BirdDef,
	viewport: ViewportFrame,
	name: TextLabel,
	detail: TextLabel,
	discovered: boolean?, -- what the viewport currently shows
}

local overlay: TextButton
local header: TextLabel
local listFrame: ScrollingFrame
local cards: { Card } = {}
local built = false

-- The seed that most likely brings this bird (highest weight wins).
local function hintSeed(birdId: string): Types.SeedDef?
	local best: Types.SeedDef? = nil
	local bestWeight = 0
	for _, seed in Seeds.list do
		for _, entry in seed.birds do
			if entry.id == birdId and entry.weight > bestWeight then
				best, bestWeight = seed, entry.weight
			end
		end
	end
	return best
end

local function refresh()
	if not built then
		return
	end
	header.Text = `Birdpedia   {State.speciesDiscovered()} / {#Birds.list} discovered   -   {Format.commas(
		State.totalVisits
	)} visits`
	for _, card in cards do
		local seen = State.birds[card.def.id]
		local discovered = seen ~= nil
		local color = Config.RARITY_COLORS[card.def.rarity]

		if card.discovered ~= discovered then
			card.discovered = discovered
			Viewport.mount(card.viewport, BirdModel.build(card.def, not discovered).model)
		end
		if discovered then
			card.name.Text = card.def.name
			card.name.TextColor3 = color
			card.detail.Text = `Seen x{seen}\n{Format.feathers(card.def.value)} per visit`
			card.detail.TextColor3 = Ui.COLORS.text
		else
			card.name.Text = "???"
			card.name.TextColor3 = Ui.COLORS.muted
			local seed = hintSeed(card.def.id)
			card.detail.Text = `{card.def.rarity}\nTry: {if seed then seed.name else "?"}`
			card.detail.TextColor3 = Ui.COLORS.muted
		end
	end
end

local function buildCards(list: Instance)
	for _, def in Birds.list do
		local color = Config.RARITY_COLORS[def.rarity]
		local frame = Ui.new(
			"Frame",
			{ Name = def.id, BackgroundColor3 = Ui.COLORS.row, Parent = list },
			{ Ui.corner(14), Ui.stroke(color, 2, 0.4) }
		)
		Ui.new(
			"Frame",
			{ Size = UDim2.new(1, 0, 0, 5), BackgroundColor3 = color, BorderSizePixel = 0, Parent = frame },
			{ Ui.corner(3) }
		)
		local viewport = Ui.new("ViewportFrame", {
			Position = UDim2.fromOffset(10, 12),
			Size = UDim2.new(1, -20, 0, 96),
			BackgroundColor3 = Ui.COLORS.bg,
			BackgroundTransparency = 0,
			Parent = frame,
		}, { Ui.corner(10) })
		local name = Ui.label({
			Position = UDim2.fromOffset(6, 112),
			Size = UDim2.new(1, -12, 0, 22),
			Font = Ui.FONT,
			TextSize = 17,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Parent = frame,
		})
		local detail = Ui.label({
			Position = UDim2.fromOffset(6, 136),
			Size = UDim2.new(1, -12, 0, 32),
			Font = Ui.FONT_BOLD,
			TextSize = 12,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextYAlignment = Enum.TextYAlignment.Top,
			TextWrapped = true,
			Parent = frame,
		})
		table.insert(cards, { def = def, viewport = viewport, name = name, detail = detail, discovered = nil })
	end
end

function BirdpediaUI.close()
	overlay.Visible = false
end

function BirdpediaUI.open()
	if overlay.Visible then
		return
	end
	overlay.Visible = true
	if not built then
		built = true
		buildCards(listFrame)
	end
	refresh()
end

function BirdpediaUI.toggle()
	if overlay.Visible then
		BirdpediaUI.close()
	else
		BirdpediaUI.open()
	end
end

function BirdpediaUI.init(gui: ScreenGui)
	overlay = Ui.new("TextButton", {
		Name = "BirdpediaOverlay",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.5,
		AutoButtonColor = false,
		Text = "",
		Visible = false,
		ZIndex = 10,
		Parent = gui,
	})
	overlay.Activated:Connect(BirdpediaUI.close)

	local panel = Ui.new("Frame", {
		Name = "Panel",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.86, 0.84),
		BackgroundColor3 = Ui.COLORS.panel,
		Active = true,
		Parent = overlay,
	}, {
		Ui.corner(20),
		Ui.stroke(Color3.fromRGB(70, 130, 196), 4),
		Ui.new("UISizeConstraint", { MaxSize = Vector2.new(860, 600), MinSize = Vector2.new(300, 280) }),
	})

	header = Ui.label({
		Position = UDim2.fromOffset(20, 12),
		Size = UDim2.new(1, -80, 0, 34),
		Text = "Birdpedia",
		Font = Ui.FONT,
		TextSize = 24,
		TextColor3 = Ui.COLORS.gold,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = panel,
	})
	Ui.label({
		Position = UDim2.fromOffset(22, 44),
		Size = UDim2.new(1, -80, 0, 18),
		Text = "Plant better seeds to attract rarer birds. Discovering a new species pays a big bonus!",
		TextSize = 13,
		TextColor3 = Ui.COLORS.muted,
		TextTruncate = Enum.TextTruncate.AtEnd,
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
	close.Activated:Connect(BirdpediaUI.close)

	listFrame = Ui.new("ScrollingFrame", {
		Name = "List",
		Position = UDim2.fromOffset(12, 72),
		Size = UDim2.new(1, -24, 1, -84),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		Parent = panel,
	}, {
		Ui.new("UIGridLayout", {
			CellSize = UDim2.fromOffset(138, 176),
			CellPadding = UDim2.fromOffset(10, 10),
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
		Ui.new("UIPadding", { PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 8) }),
	})

	State.changed:Connect(refresh)
end

return BirdpediaUI
