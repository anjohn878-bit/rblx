-- The Bird Journal: every species, which ones you've befriended, and hints
-- for the ones you haven't found yet.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BirdBuilder = require(Shared.BirdBuilder)
local Birds = require(Shared.Birds)
local Rarities = require(Shared.Rarities)
local Seeds = require(Shared.Seeds)
local Util = require(Shared.Util)
local Store = require(script.Parent.Store)
local UI = require(script.Parent.UI)
local Viewport = require(script.Parent.Viewport)

local JournalWindow = {}

local BIRD_VIEW = Vector3.new(-0.8, 0.35, -1)

local window, body, progressLabel
local cards = {} -- [birdId] = { View, Name, Detail, Count }
local built = false

local function attractedBy(birdId)
	local names = {}
	for _, seed in ipairs(Seeds.List) do
		for _, entry in ipairs(seed.Birds) do
			if entry.Id == birdId then
				table.insert(names, seed.Name)
				break
			end
		end
	end
	return table.concat(names, ", ")
end

local function refresh()
	local data = Store.Data
	local journal = data and data.Journal or {}
	local shinies = data and data.ShinyJournal or {}
	local found = 0
	for _, bird in ipairs(Birds.List) do
		local count = journal[bird.Id] or 0
		local card = cards[bird.Id]
		if count > 0 then
			found += 1
		end
		if card then
			local discovered = count > 0
			card.View.ImageColor3 = discovered and Color3.new(1, 1, 1) or Color3.new(0, 0, 0)
			card.Name.Text = discovered and bird.Name or "???"
			if discovered then
				local shiny = shinies[bird.Id] or 0
				card.Count.Text = "Befriended x" .. count .. (shiny > 0 and ("  ✨x" .. shiny) or "")
				card.Detail.Text = bird.Description
			else
				card.Count.Text = "Not found yet"
				card.Detail.Text = "Try planting: " .. attractedBy(bird.Id)
			end
		end
	end
	progressLabel.Text = "Discovered " .. found .. " / " .. #Birds.List
end

local function buildCard(bird)
	local card = UI.new("Frame", {
		Name = bird.Id,
		LayoutOrder = bird.Order,
		BackgroundColor3 = UI.Colors.PanelDark,
		Parent = body,
	}, { UI.corner(12), UI.stroke(Rarities.Color(bird.Rarity), 2) })

	local view = UI.new("ViewportFrame", {
		Position = UDim2.fromOffset(8, 8),
		Size = UDim2.new(1, -16, 0, 96),
		BackgroundColor3 = Color3.fromRGB(200, 230, 245),
		Parent = card,
	}, { UI.corner(10) })
	Viewport.Show(view, BirdBuilder.Build(bird), BIRD_VIEW)

	local name = UI.label({
		Font = UI.TitleFont,
		TextColor3 = Rarities.Color(bird.Rarity),
		TextStrokeTransparency = 0.7,
		Position = UDim2.fromOffset(6, 108),
		Size = UDim2.new(1, -12, 0, 22),
		Parent = card,
	})
	UI.label({
		Text = bird.Rarity .. "  •  🪙 " .. Util.FormatNumber(bird.Reward),
		TextColor3 = UI.Colors.SubText,
		Position = UDim2.fromOffset(6, 132),
		Size = UDim2.new(1, -12, 0, 16),
		Parent = card,
	})
	local count = UI.label({
		Font = UI.TitleFont,
		TextColor3 = UI.Colors.Text,
		Position = UDim2.fromOffset(6, 150),
		Size = UDim2.new(1, -12, 0, 16),
		Parent = card,
	})
	local detail = UI.label({
		TextColor3 = UI.Colors.SubText,
		TextWrapped = true,
		Position = UDim2.fromOffset(6, 168),
		Size = UDim2.new(1, -12, 0, 34),
		Parent = card,
	})
	cards[bird.Id] = { View = view, Name = name, Detail = detail, Count = count }
end

local function build()
	if built then
		return
	end
	built = true
	UI.new("UIGridLayout", {
		CellSize = UDim2.fromOffset(180, 210),
		CellPadding = UDim2.fromOffset(10, 10),
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = body,
	})
	UI.new("UIPadding", { PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 8), Parent = body })
	for _, bird in ipairs(Birds.List) do
		buildCard(bird)
	end
	refresh()
end

function JournalWindow.Init(screenGui)
	window, body, progressLabel = UI.window(screenGui, "📖 Bird Journal", function()
		JournalWindow.Close()
	end)
	Store.Changed:Connect(function(what)
		if built and what == "Data" then
			refresh()
		end
	end)
end

function JournalWindow.Open()
	build()
	window.Visible = true
	UI.pop(window)
end

function JournalWindow.Close()
	window.Visible = false
end

function JournalWindow.IsOpen()
	return window.Visible
end

return JournalWindow
