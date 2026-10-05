-- The Aviary: every bird you've befriended. Send birds out to roam your
-- garden (they give perks while they're out), mark favorites, and sell the
-- ones you don't need.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BirdBuilder = require(Shared.BirdBuilder)
local Config = require(Shared.Config)
local Pets = require(Shared.Pets)
local Rarities = require(Shared.Rarities)
local Util = require(Shared.Util)
local Actions = require(script.Parent.Actions)
local Store = require(script.Parent.Store)
local UI = require(script.Parent.UI)
local Viewport = require(script.Parent.Viewport)

local AviaryWindow = {}

local BIRD_VIEW = Vector3.new(-0.8, 0.35, -1)

local window, body, headerInfo, perkLabel, bulkRarityButton
local cards = {} -- [petId] = card
local bulkRarity = 1
local openNests -- set in Init

local function perkSummary(perks)
	local parts = {}
	for _, perkId in ipairs(Pets.PerkOrder) do
		if (perks[perkId] or 0) > 0 then
			table.insert(parts, Pets.PerkText(perkId, perks[perkId]))
		end
	end
	if #parts == 0 then
		return "Send birds out into your garden: each kind gives a perk!"
	end
	return "Your garden: " .. table.concat(parts, "   ")
end

-- What "Sell spares" would sell right now (same rules as the server).
local function bulkSellPreview()
	local data = Store.Data
	if not data then
		return 0, 0
	end
	local now = Store.Now()
	local maxRank = Rarities.Rank(Rarities.Order[bulkRarity])
	local offered = Store.Trade and Store.Trade.Active and Store.Trade.MyPets or {}
	local count, coins = 0, 0
	for id, pet in pairs(data.Pets) do
		local def = Pets.Def(pet)
		if def and Rarities.Rank(def.Rarity) <= maxRank and Pets.IsSpare(pet, now) and not table.find(offered, id) then
			count += 1
			coins += Pets.SellPrice(pet, now, data.Perks)
		end
	end
	return count, coins
end

local function buildCard(petId)
	local card = {}
	card.Frame = UI.new("Frame", {
		Name = petId,
		BackgroundColor3 = UI.Colors.PanelDark,
		Parent = body,
	}, { UI.corner(12) })
	card.Stroke = UI.stroke(UI.Colors.Wood, 2)
	card.Stroke.Parent = card.Frame

	card.View = UI.new("ViewportFrame", {
		Position = UDim2.fromOffset(6, 6),
		Size = UDim2.new(1, -12, 0, 78),
		BackgroundColor3 = Color3.fromRGB(200, 230, 245),
		Parent = card.Frame,
	}, { UI.corner(10) })
	card.Badge = UI.label({
		Text = "",
		Font = UI.TitleFont,
		TextColor3 = UI.Colors.White,
		TextStrokeTransparency = 0.3,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(10, 8),
		Size = UDim2.new(1, -20, 0, 18),
		Parent = card.Frame,
	})
	card.Name = UI.label({
		Font = UI.TitleFont,
		TextStrokeTransparency = 0.7,
		Position = UDim2.fromOffset(6, 88),
		Size = UDim2.new(1, -12, 0, 20),
		Parent = card.Frame,
	})
	card.Kind = UI.label({
		TextColor3 = UI.Colors.SubText,
		Position = UDim2.fromOffset(6, 109),
		Size = UDim2.new(1, -12, 0, 15),
		Parent = card.Frame,
	})
	card.Info = UI.label({
		TextColor3 = UI.Colors.Text,
		Position = UDim2.fromOffset(6, 126),
		Size = UDim2.new(1, -12, 0, 15),
		Parent = card.Frame,
	})
	card.Family = UI.label({
		TextColor3 = UI.Colors.SubText,
		Position = UDim2.fromOffset(6, 142),
		Size = UDim2.new(1, -12, 0, 14),
		Parent = card.Frame,
	})

	card.Equip = UI.button({
		Position = UDim2.new(0, 6, 1, -54),
		Size = UDim2.new(0.62, -8, 0, 24),
		Parent = card.Frame,
	}, function()
		local pet = Store.Data and Store.Data.Pets[petId]
		if pet then
			Actions.Pet(pet.Equipped and "Unequip" or "Equip", petId)
		end
	end)
	card.Favorite = UI.button({
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -6, 1, -54),
		Size = UDim2.new(0.38, -4, 0, 24),
		BackgroundColor3 = Color3.fromRGB(240, 130, 160),
		Parent = card.Frame,
	}, function()
		local pet = Store.Data and Store.Data.Pets[petId]
		if pet then
			Actions.Pet("Favorite", petId, not pet.Favorite)
		end
	end)
	card.Sell, card.SellArmed = UI.confirmButton({
		Position = UDim2.new(0, 6, 1, -27),
		Size = UDim2.new(1, -12, 0, 22),
		BackgroundColor3 = UI.Colors.Gold,
		TextColor3 = UI.Colors.Text,
		Parent = card.Frame,
	}, function()
		return card.SellText or "Sell"
	end, function()
		Actions.Pet("Sell", petId)
	end)
	cards[petId] = card
	return card
end

local function updateCard(card, pet, order, now, perks)
	local def = Pets.Def(pet)
	card.Frame.LayoutOrder = order
	card.Stroke.Color = pet.Equipped and UI.Colors.Green or Rarities.Color(def.Rarity)
	card.Stroke.Thickness = pet.Equipped and 4 or 2

	local baby = Pets.IsBaby(pet, now)
	local viewKey = pet.Species .. tostring(pet.Shiny) .. tostring(baby)
	if card.ViewKey ~= viewKey then
		card.ViewKey = viewKey
		Viewport.Show(
			card.View,
			BirdBuilder.Build(def, { Shiny = pet.Shiny, Scale = baby and Pets.BabyScale or 1 }),
			BIRD_VIEW
		)
	end

	local badges = {}
	if pet.Equipped then
		table.insert(badges, "🌳 OUT")
	end
	if pet.Nest then
		table.insert(badges, "🥚 NEST")
	end
	if pet.Shiny then
		table.insert(badges, "✨")
	end
	if pet.Favorite then
		table.insert(badges, "❤")
	end
	card.Badge.Text = table.concat(badges, " ")

	card.Name.Text = (baby and "👶 " or "") .. pet.Name
	card.Name.TextColor3 = pet.Shiny and Color3.fromRGB(230, 170, 30) or Rarities.Color(def.Rarity)
	card.Kind.Text = def.Name .. " " .. Pets.StarText(pet.Stars)
	if baby then
		card.Info.Text = Pets.PetPerkText(pet, now) .. "  •  grows up in " .. Util.FormatTime(pet.GrowsUpAt - now)
	else
		card.Info.Text = Pets.PetPerkText(pet, now) .. " " .. Pets.Perks[def.Perk].Name
	end
	if pet.Family then
		card.Family.Text = "🏡 "
			.. pet.Family
			.. " family"
			.. ((pet.Generation or 0) > 0 and (" • gen " .. pet.Generation) or "")
	else
		card.Family.Text = "Wild bird"
	end

	card.Equip.Text = pet.Nest and "Nesting" or (pet.Equipped and "Put away" or "Send out")
	card.Equip.BackgroundColor3 = pet.Nest and UI.Colors.Grey or (pet.Equipped and UI.Colors.Wood or UI.Colors.Green)
	card.Favorite.Text = pet.Favorite and "❤" or "♡"
	card.SellText = "Sell 🪙 " .. Util.FormatNumber(Pets.SellPrice(pet, now, perks))
	if not card.SellArmed() then
		card.Sell.Text = card.SellText
	end
	local canSell = not pet.Favorite and not pet.Nest
	card.Sell.BackgroundColor3 = canSell and UI.Colors.Gold or UI.Colors.Grey
end

local function refresh()
	if not window or not window.Visible then
		return
	end
	local data = Store.Data
	if not data then
		return
	end
	local now = Store.Now()
	local perks = data.Perks or {}
	local ids = Pets.SortKeys(data.Pets)
	local seen = {}
	for order, petId in ipairs(ids) do
		seen[petId] = true
		local card = cards[petId] or buildCard(petId)
		updateCard(card, data.Pets[petId], order, now, perks)
	end
	for petId, card in pairs(cards) do
		if not seen[petId] then
			card.Frame:Destroy()
			cards[petId] = nil
		end
	end

	headerInfo.Text = #ids
		.. "/"
		.. Config.MaxPets
		.. " birds  •  "
		.. Pets.CountEquipped(data.Pets)
		.. "/"
		.. Config.MaxEquippedPets
		.. " out"
	perkLabel.Text = perkSummary(perks)
	body.Empty.Visible = #ids == 0
end

function AviaryWindow.Init(screenGui, callbacks)
	openNests = callbacks.OpenNests
	window, body, headerInfo = UI.window(screenGui, "🐦 My Birds", function()
		AviaryWindow.Close()
	end)

	perkLabel = UI.label({
		Name = "Perks",
		Text = "",
		TextColor3 = UI.Colors.Text,
		TextWrapped = true,
		Position = UDim2.new(0, 12, 0, 56),
		Size = UDim2.new(1, -24, 0, 36),
		Parent = window,
	})
	body.Position = UDim2.new(0, 10, 0, 96)
	body.Size = UDim2.new(1, -20, 1, -150)
	UI.new("UIGridLayout", {
		CellSize = UDim2.fromOffset(140, 214),
		CellPadding = UDim2.fromOffset(8, 8),
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = body,
	})
	UI.new("UIPadding", { PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 8), Parent = body })
	UI.label({
		Name = "Empty",
		Text = "No birds yet! Befriend birds that visit your plants and they'll live here.",
		TextWrapped = true,
		TextColor3 = UI.Colors.SubText,
		LayoutOrder = -1,
		Visible = false,
		Parent = body,
	})

	-- bottom bar: nests and bulk selling
	local bar = UI.new("Frame", {
		Name = "Bottom",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 10, 1, -8),
		Size = UDim2.new(1, -20, 0, 40),
		BackgroundTransparency = 1,
		Parent = window,
	})
	UI.button({
		Text = "🥚 Breed",
		BackgroundColor3 = Color3.fromRGB(230, 170, 80),
		Size = UDim2.new(0.22, -4, 1, 0),
		Parent = bar,
	}, function()
		AviaryWindow.Close()
		openNests(nil)
	end)
	UI.button({
		Name = "BestOut",
		Text = "⭐ Best out",
		BackgroundColor3 = UI.Colors.Green,
		Position = UDim2.new(0.22, 2, 0, 0),
		Size = UDim2.new(0.24, -4, 1, 0),
		Parent = bar,
	}, function()
		Actions.Pet("EquipBest")
	end)
	bulkRarityButton = UI.button({
		BackgroundColor3 = UI.Colors.Wood,
		Position = UDim2.new(0.46, 2, 0, 0),
		Size = UDim2.new(0.24, -4, 1, 0),
		Parent = bar,
	}, function()
		bulkRarity = bulkRarity % #Rarities.Order + 1
		bulkRarityButton.Text = "≤ " .. Rarities.Order[bulkRarity] .. " ▾"
		bulkRarityButton.TextColor3 = Rarities.Color(Rarities.Order[bulkRarity])
	end)
	bulkRarityButton.Text = "≤ " .. Rarities.Order[bulkRarity] .. " ▾"
	bulkRarityButton.TextColor3 = Rarities.Color(Rarities.Order[bulkRarity])
	UI.confirmButton({
		Name = "SellSpares",
		BackgroundColor3 = UI.Colors.Gold,
		TextColor3 = UI.Colors.Text,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 0),
		Size = UDim2.new(0.3, -2, 1, 0),
		Parent = bar,
	}, function()
		-- spares: not out, nesting, favorites, shiny, in a family, babies or 4+ stars
		return "💰 Sell spares"
	end, function()
		Actions.Pet("SellBulk", Rarities.Order[bulkRarity])
	end, function()
		local count, coins = bulkSellPreview()
		if count == 0 then
			return false -- let the server explain there's nothing to sell
		end
		return "Sell " .. count .. " for 🪙 " .. Util.FormatNumber(coins) .. "?"
	end)

	Store.Changed:Connect(function(what)
		if what == "Data" then
			refresh()
		end
	end)
	-- keep baby timers ticking
	task.spawn(function()
		while true do
			task.wait(1)
			refresh()
		end
	end)
end

function AviaryWindow.Open()
	window.Visible = true
	UI.pop(window)
	refresh()
end

function AviaryWindow.Close()
	window.Visible = false
end

function AviaryWindow.IsOpen()
	return window.Visible
end

return AviaryWindow
