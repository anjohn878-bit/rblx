-- The seed hotbar at the bottom of the screen. Pick which seed to plant.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Rarities = require(Shared.Rarities)
local Seeds = require(Shared.Seeds)
local Store = require(script.Parent.Store)
local UI = require(script.Parent.UI)

local SeedBag = {}

local NUMBER_KEYS = {
	One = 1,
	Two = 2,
	Three = 3,
	Four = 4,
	Five = 5,
	Six = 6,
	Seven = 7,
	Eight = 8,
	Nine = 9,
}

local SLOT_SIZE = 78

function SeedBag.Init(screenGui, openShop)
	local root = UI.new("Frame", {
		Name = "SeedBag",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -10),
		Size = UDim2.new(0.6, 0, 0, SLOT_SIZE + 40),
		BackgroundTransparency = 1,
		Parent = screenGui,
	}, { UI.new("UISizeConstraint", { MaxSize = Vector2.new(760, SLOT_SIZE + 40) }) })

	local hint = UI.label({
		Name = "Hint",
		Text = "",
		TextColor3 = UI.Colors.White,
		TextStrokeTransparency = 0.4,
		Size = UDim2.new(1, 0, 0, 22),
		Parent = root,
	})

	local list = UI.new("ScrollingFrame", {
		Name = "Slots",
		Position = UDim2.fromOffset(0, 28),
		Size = UDim2.new(1, 0, 0, SLOT_SIZE + 10),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 4,
		ScrollingDirection = Enum.ScrollingDirection.X,
		AutomaticCanvasSize = Enum.AutomaticSize.X,
		CanvasSize = UDim2.new(),
		Parent = root,
	}, {
		UI.new("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			Padding = UDim.new(0, 8),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
		UI.new(
			"UIPadding",
			{ PaddingLeft = UDim.new(0, 4), PaddingRight = UDim.new(0, 4), PaddingTop = UDim.new(0, 4) }
		),
	})

	local emptyButton = UI.button({
		Name = "Empty",
		Text = "No seeds! Tap here to visit the 🌱 Seed Shop",
		Font = UI.TitleFont,
		Size = UDim2.fromOffset(340, 50),
		Visible = false,
		Parent = list,
	}, openShop)
	UI.stroke(UI.Colors.Wood, 3).Parent = emptyButton

	local ownedOrder = {} -- seed ids in slot order, for number keys

	local function selectSeed(seedId)
		if Store.Data and Store.Data.SelectedSeed ~= seedId then
			Store.SelectSeed(seedId)
			Net.SelectSeed:FireServer(seedId)
		end
	end

	local function refresh()
		for _, child in ipairs(list:GetChildren()) do
			if child:IsA("TextButton") and child ~= emptyButton then
				child:Destroy()
			end
		end
		table.clear(ownedOrder)

		local data = Store.Data
		if not data then
			hint.Text = "Loading your garden..."
			emptyButton.Visible = false
			return
		end

		for _, seed in ipairs(Seeds.List) do
			local count = data.Seeds[seed.Id] or 0
			if count > 0 then
				table.insert(ownedOrder, seed.Id)
				local slotNumber = #ownedOrder
				local selected = data.SelectedSeed == seed.Id
				local slot = UI.button({
					Name = seed.Id,
					LayoutOrder = seed.Order,
					Size = UDim2.fromOffset(SLOT_SIZE, SLOT_SIZE),
					BackgroundColor3 = selected and Color3.fromRGB(210, 245, 190) or UI.Colors.Panel,
					Parent = list,
				}, function()
					selectSeed(seed.Id)
				end)
				UI.stroke(selected and UI.Colors.Green or Rarities.Color(seed.Rarity), selected and 4 or 2).Parent =
					slot
				UI.label({
					Text = seed.Icon,
					Position = UDim2.fromOffset(0, 6),
					Size = UDim2.new(1, 0, 0, 36),
					Parent = slot,
				})
				UI.label({
					Text = seed.Name,
					Font = UI.TitleFont,
					Position = UDim2.new(0, 4, 1, -26),
					Size = UDim2.new(1, -8, 0, 18),
					Parent = slot,
				})
				UI.label({
					Text = "x" .. count,
					Font = UI.TitleFont,
					TextColor3 = UI.Colors.SubText,
					TextXAlignment = Enum.TextXAlignment.Right,
					Position = UDim2.new(1, -40, 0, 2),
					Size = UDim2.fromOffset(36, 16),
					Parent = slot,
				})
				if slotNumber <= 9 then
					UI.label({
						Text = tostring(slotNumber),
						TextColor3 = UI.Colors.SubText,
						TextXAlignment = Enum.TextXAlignment.Left,
						Position = UDim2.fromOffset(5, 2),
						Size = UDim2.fromOffset(16, 14),
						Parent = slot,
					})
				end
			end
		end

		local hasSeeds = #ownedOrder > 0
		emptyButton.Visible = not hasSeeds
		if hasSeeds then
			local selected = data.SelectedSeed and Seeds.Get(data.SelectedSeed)
			hint.Text = selected and ("Walk up to empty soil to plant your " .. selected.Name .. " " .. selected.Icon)
				or "Pick a seed to plant"
		else
			hint.Text = "Befriend birds to earn coins, then buy more seeds!"
		end
	end

	Store.Changed:Connect(function(what)
		if what == "Data" then
			refresh()
		end
	end)
	refresh()

	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then
			return
		end
		local slotNumber = NUMBER_KEYS[input.KeyCode.Name]
		if slotNumber and ownedOrder[slotNumber] then
			selectSeed(ownedOrder[slotNumber])
		end
	end)
end

return SeedBag
