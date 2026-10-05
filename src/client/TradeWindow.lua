-- Trading birds and coins with other players.
-- Lobby: send requests to players in the server and answer requests.
-- Trade: build your offer, see theirs, both press Ready, and after a short
-- countdown the server swaps everything.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Birds = require(Shared.Birds)
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Pets = require(Shared.Pets)
local Rarities = require(Shared.Rarities)
local Util = require(Shared.Util)
local Notifications = require(script.Parent.Notifications)
local Store = require(script.Parent.Store)
local UI = require(script.Parent.UI)

local TradeWindow = {}

local localPlayer = Players.LocalPlayer

local window, lobby, headerInfo
local tradeFrame, myCoinsBox, myCoinsHint, myOfferList, addList, theirTitle, theirCoins, theirList, theirReady
local statusLabel, readyButton
local popup, popupLabel
local wasActive = false

local function petLine(name, species, stars, shiny, baby, value)
	local def = Birds.Get(species)
	return (shiny and "✨" or "")
		.. (baby and "👶" or "")
		.. name
		.. " "
		.. Pets.StarText(stars)
		.. "  "
		.. (def and def.Name or species)
		.. (value and ("  •  🪙 " .. Util.FormatNumber(value)) or "")
end

local function clearRows(list)
	for _, child in ipairs(list:GetChildren()) do
		if child:IsA("Frame") or child:IsA("TextLabel") then
			child:Destroy()
		end
	end
end

local function row(list, order, text, color, buttonText, buttonColor, onClick)
	local frame = UI.new("Frame", {
		LayoutOrder = order,
		Size = UDim2.new(1, -6, 0, 32),
		BackgroundColor3 = UI.Colors.PanelDark,
		Parent = list,
	}, { UI.corner(8) })
	UI.label({
		Text = text,
		TextColor3 = color or UI.Colors.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(8, 4),
		Size = UDim2.new(1, buttonText and -86 or -16, 1, -8),
		Parent = frame,
	})
	if buttonText then
		UI.button({
			Text = buttonText,
			BackgroundColor3 = buttonColor or UI.Colors.Green,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -4, 0.5, 0),
			Size = UDim2.fromOffset(74, 26),
			Parent = frame,
		}, onClick)
	end
	return frame
end

local function emptyRow(list, text)
	UI.label({
		LayoutOrder = 0,
		Text = text,
		TextColor3 = UI.Colors.SubText,
		TextWrapped = true,
		Size = UDim2.new(1, -6, 0, 30),
		Parent = list,
	})
end

local function scrollList(parent, position, size)
	return UI.new("ScrollingFrame", {
		Position = position,
		Size = size,
		BackgroundColor3 = UI.Colors.Panel,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = UI.Colors.Wood,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		Parent = parent,
	}, {
		UI.corner(8),
		UI.new("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }),
		UI.new("UIPadding", { PaddingTop = UDim.new(0, 4), PaddingLeft = UDim.new(0, 4) }),
	})
end

------------------------------------------------------------------------------
-- Lobby

local function refreshLobby()
	clearRows(lobby)
	local order = 0
	local now = Store.Now()

	UI.label({
		LayoutOrder = order,
		Text = "Trade requests",
		Font = UI.TitleFont,
		TextColor3 = UI.Colors.Wood,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, -6, 0, 24),
		Parent = lobby,
	})
	local anyRequest = false
	for _, request in ipairs(Store.TradeRequests) do
		if request.ExpiresAt > now then
			anyRequest = true
			order += 1
			local frame = row(
				lobby,
				order,
				"🤝 " .. request.FromName .. " wants to trade!",
				nil,
				"Accept",
				UI.Colors.Green,
				function()
					Net.TradeRespond:FireServer(request.FromUserId, true)
					Store.RemoveTradeRequest(request.FromUserId)
				end
			)
			UI.button({
				Text = "No",
				BackgroundColor3 = UI.Colors.Red,
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -82, 0.5, 0),
				Size = UDim2.fromOffset(50, 26),
				Parent = frame,
			}, function()
				Net.TradeRespond:FireServer(request.FromUserId, false)
				Store.RemoveTradeRequest(request.FromUserId)
			end)
		end
	end
	if not anyRequest then
		order += 1
		local label = UI.label({
			LayoutOrder = order,
			Text = "No requests right now.",
			TextColor3 = UI.Colors.SubText,
			Size = UDim2.new(1, -6, 0, 22),
			Parent = lobby,
		})
		label.Name = "NoRequests"
	end

	order += 1
	UI.label({
		LayoutOrder = order,
		Text = "Players in this server",
		Font = UI.TitleFont,
		TextColor3 = UI.Colors.Wood,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, -6, 0, 24),
		Parent = lobby,
	})
	local anyPlayer = false
	for _, player in ipairs(Players:GetPlayers()) do
		if player ~= localPlayer then
			anyPlayer = true
			order += 1
			row(lobby, order, player.DisplayName, nil, "Request", Color3.fromRGB(90, 140, 220), function()
				Net.TradeRequest:FireServer(player.UserId)
			end)
		end
	end
	if not anyPlayer then
		order += 1
		UI.label({
			LayoutOrder = order,
			Text = "Nobody else is here yet. Invite a friend to trade birds!",
			TextColor3 = UI.Colors.SubText,
			TextWrapped = true,
			Size = UDim2.new(1, -6, 0, 40),
			Parent = lobby,
		})
	end
end

------------------------------------------------------------------------------
-- Active trade

local function refreshTrade(trade)
	local data = Store.Data
	local now = Store.Now()
	local myPets = data and data.Pets or {}

	headerInfo.Text = "with " .. trade.PartnerName
	theirTitle.Text = trade.PartnerName .. " gives"
	if not myCoinsBox:IsFocused() then
		myCoinsBox.Text = tostring(trade.MyCoins)
	end
	-- show what each side is worth so lopsided trades are easy to spot
	local myTotal = trade.MyCoins
	for _, petId in ipairs(trade.MyPets) do
		local pet = myPets[petId]
		if pet then
			myTotal += Pets.BaseValue(pet, now)
		end
	end
	local theirTotal = trade.TheirCoins
	for _, summary in ipairs(trade.TheirPets) do
		theirTotal += summary.Value or 0
	end
	myCoinsHint.Text = "Worth 🪙 "
		.. Util.FormatNumber(myTotal)
		.. " (you have "
		.. Util.FormatNumber(data and data.Coins or 0)
		.. ")"
	theirCoins.Text = "🪙 "
		.. Util.FormatNumber(trade.TheirCoins)
		.. " coins  •  worth 🪙 "
		.. Util.FormatNumber(theirTotal)

	clearRows(myOfferList)
	if #trade.MyPets == 0 then
		emptyRow(myOfferList, "Add birds from the list below.")
	end
	for order, petId in ipairs(trade.MyPets) do
		local pet = myPets[petId]
		if pet then
			local def = Pets.Def(pet)
			row(
				myOfferList,
				order,
				petLine(pet.Name, pet.Species, pet.Stars, pet.Shiny, Pets.IsBaby(pet, now), Pets.BaseValue(pet, now)),
				Rarities.Color(def.Rarity),
				"Remove",
				UI.Colors.Red,
				function()
					Net.TradeUpdate:FireServer("RemovePet", petId)
				end
			)
		end
	end

	clearRows(addList)
	local order = 0
	for _, petId in ipairs(Pets.SortKeys(myPets)) do
		local pet = myPets[petId]
		if not table.find(trade.MyPets, petId) and not pet.Favorite and not pet.Nest then
			order += 1
			row(
				addList,
				order,
				petLine(pet.Name, pet.Species, pet.Stars, pet.Shiny, Pets.IsBaby(pet, now), Pets.BaseValue(pet, now)),
				Rarities.Color(Pets.Def(pet).Rarity),
				"Add",
				UI.Colors.Green,
				function()
					Net.TradeUpdate:FireServer("AddPet", petId)
				end
			)
		end
	end
	if order == 0 then
		emptyRow(addList, "No birds to add. Favorites (❤) and nesting birds can't be traded.")
	end

	clearRows(theirList)
	if #trade.TheirPets == 0 then
		emptyRow(theirList, "No birds offered yet.")
	end
	for index, summary in ipairs(trade.TheirPets) do
		local def = Birds.Get(summary.Species)
		row(
			theirList,
			index,
			petLine(summary.Name, summary.Species, summary.Stars, summary.Shiny, summary.Baby, summary.Value),
			def and Rarities.Color(def.Rarity)
		)
	end
	theirReady.Text = trade.TheirReady and ("✅ " .. trade.PartnerName .. " is ready") or "⏳ Not ready yet"
	theirReady.TextColor3 = trade.TheirReady and UI.Colors.Green or UI.Colors.SubText

	readyButton.Text = trade.MyReady and "Not ready" or "✅ Ready"
	readyButton.BackgroundColor3 = trade.MyReady and UI.Colors.Wood or UI.Colors.Green
end

local function updateStatus()
	local trade = Store.Trade
	if not trade or not trade.Active then
		return
	end
	if trade.ExecuteAt then
		local remaining = math.max(0, math.ceil(trade.ExecuteAt - Store.Now()))
		statusLabel.Text = "🤝 Both ready! Trading in " .. remaining .. "..."
		statusLabel.TextColor3 = UI.Colors.Green
	elseif trade.MyReady then
		statusLabel.Text = "Waiting for " .. trade.PartnerName .. " to be ready..."
		statusLabel.TextColor3 = UI.Colors.SubText
	else
		statusLabel.Text = "Check both sides, then press Ready. Any change un-readies you both."
		statusLabel.TextColor3 = UI.Colors.SubText
	end
end

local function refresh()
	local trade = Store.Trade
	local active = trade ~= nil and trade.Active
	wasActive = active
	lobby.Visible = not active
	tradeFrame.Visible = active
	if not window.Visible then
		return
	end
	if active then
		refreshTrade(trade)
		updateStatus()
	else
		headerInfo.Text = ""
		refreshLobby()
	end
end

------------------------------------------------------------------------------
-- Request popup

local function refreshPopup()
	local now = Store.Now()
	local latest
	for _, request in ipairs(Store.TradeRequests) do
		if request.ExpiresAt > now then
			latest = request
		end
	end
	local trading = Store.Trade and Store.Trade.Active
	popup.Visible = latest ~= nil and not trading
	if latest then
		popupLabel.Text = "🤝 "
			.. latest.FromName
			.. " wants to trade! ("
			.. math.ceil(latest.ExpiresAt - now)
			.. "s)"
		popup:SetAttribute("FromUserId", latest.FromUserId)
	end
end

local function buildPopup(screenGui)
	popup = UI.new("Frame", {
		Name = "TradeRequestPopup",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.3, 0),
		Size = UDim2.fromOffset(340, 96),
		BackgroundColor3 = UI.Colors.Panel,
		Visible = false,
		ZIndex = 20, -- above any open window
		Parent = screenGui,
	}, { UI.corner(14), UI.stroke(UI.Colors.Wood, 3) })
	popupLabel = UI.label({
		Font = UI.TitleFont,
		Position = UDim2.fromOffset(10, 8),
		Size = UDim2.new(1, -20, 0, 30),
		Parent = popup,
	})
	local function answer(accept)
		local fromUserId = popup:GetAttribute("FromUserId")
		if fromUserId then
			Net.TradeRespond:FireServer(fromUserId, accept)
			Store.RemoveTradeRequest(fromUserId)
		end
	end
	UI.button({
		Name = "Accept",
		Text = "Accept",
		Position = UDim2.new(0, 10, 1, -48),
		Size = UDim2.new(0.5, -15, 0, 38),
		Parent = popup,
	}, function()
		answer(true)
	end)
	UI.button({
		Name = "Decline",
		Text = "Decline",
		BackgroundColor3 = UI.Colors.Red,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -10, 1, -48),
		Size = UDim2.new(0.5, -15, 0, 38),
		Parent = popup,
	}, function()
		answer(false)
	end)
end

------------------------------------------------------------------------------

function TradeWindow.Init(screenGui)
	local body
	window, body, headerInfo = UI.window(screenGui, "🤝 Trade", function()
		if Store.Trade and Store.Trade.Active then
			-- closing with the X during a trade cancels it, so nobody gets stuck
			Net.TradeUpdate:FireServer("Cancel")
		end
		TradeWindow.Close()
	end)
	lobby = body
	UI.new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder, Parent = lobby })

	tradeFrame = UI.new("Frame", {
		Name = "Trade",
		Position = UDim2.new(0, 10, 0, 58),
		Size = UDim2.new(1, -20, 1, -66),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = window,
	})

	-- left: your side
	local left = UI.new("Frame", { Size = UDim2.new(0.5, -5, 1, -54), BackgroundTransparency = 1, Parent = tradeFrame })
	UI.label({
		Text = "You give",
		Font = UI.TitleFont,
		TextColor3 = UI.Colors.Wood,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, 0, 0, 22),
		Parent = left,
	})
	UI.label({ Text = "🪙", Position = UDim2.fromOffset(0, 26), Size = UDim2.fromOffset(24, 26), Parent = left })
	myCoinsBox = UI.new("TextBox", {
		Name = "Coins",
		Position = UDim2.fromOffset(26, 26),
		Size = UDim2.new(0.45, -26, 0, 26),
		BackgroundColor3 = UI.Colors.White,
		Font = UI.BodyFont,
		Text = "0",
		PlaceholderText = "coins",
		TextColor3 = UI.Colors.Text,
		TextScaled = true,
		ClearTextOnFocus = false,
		Parent = left,
	}, { UI.corner(6) })
	myCoinsBox.FocusLost:Connect(function()
		local amount = tonumber(myCoinsBox.Text)
		if amount then
			Net.TradeUpdate:FireServer("SetCoins", math.max(0, math.floor(amount)))
		else
			myCoinsBox.Text = tostring(Store.Trade and Store.Trade.MyCoins or 0)
		end
	end)
	myCoinsHint = UI.label({
		TextColor3 = UI.Colors.SubText,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.new(0.45, 6, 0, 30),
		Size = UDim2.new(0.55, -6, 0, 18),
		Parent = left,
	})
	myOfferList = scrollList(left, UDim2.fromOffset(0, 56), UDim2.new(1, 0, 0.5, -56))
	UI.label({
		Text = "Add a bird (up to " .. Config.TradeMaxPets .. ")",
		Font = UI.TitleFont,
		TextColor3 = UI.Colors.Wood,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.new(0, 0, 0.5, 4),
		Size = UDim2.new(1, 0, 0, 20),
		Parent = left,
	})
	addList = scrollList(left, UDim2.new(0, 0, 0.5, 26), UDim2.new(1, 0, 0.5, -26))

	-- right: their side
	local right = UI.new("Frame", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 0),
		Size = UDim2.new(0.5, -5, 1, -54),
		BackgroundTransparency = 1,
		Parent = tradeFrame,
	})
	theirTitle = UI.label({
		Font = UI.TitleFont,
		TextColor3 = UI.Colors.Wood,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, 0, 0, 22),
		Parent = right,
	})
	theirCoins = UI.label({
		Font = UI.TitleFont,
		TextColor3 = UI.Colors.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(0, 26),
		Size = UDim2.new(1, 0, 0, 24),
		Parent = right,
	})
	theirList = scrollList(right, UDim2.fromOffset(0, 56), UDim2.new(1, 0, 1, -84))
	theirReady = UI.label({
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 1, 0),
		Size = UDim2.new(1, 0, 0, 22),
		Parent = right,
	})

	-- bottom bar
	local bottom = UI.new("Frame", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 1, 0),
		Size = UDim2.new(1, 0, 0, 46),
		BackgroundTransparency = 1,
		Parent = tradeFrame,
	})
	statusLabel = UI.label({
		TextWrapped = true,
		Size = UDim2.new(0.5, -6, 1, 0),
		Parent = bottom,
	})
	readyButton = UI.button({
		Name = "Ready",
		Position = UDim2.new(0.5, 0, 0, 2),
		Size = UDim2.new(0.25, -4, 1, -4),
		Parent = bottom,
	}, function()
		local trade = Store.Trade
		if trade and trade.Active then
			-- Ready is tied to the version of the offer on screen
			Net.TradeUpdate:FireServer(trade.MyReady and "Unready" or "Ready", trade.Revision)
		end
	end)
	UI.button({
		Name = "Cancel",
		Text = "Cancel",
		BackgroundColor3 = UI.Colors.Red,
		Position = UDim2.new(0.75, 4, 0, 2),
		Size = UDim2.new(0.25, -4, 1, -4),
		Parent = bottom,
	}, function()
		Net.TradeUpdate:FireServer("Cancel")
	end)

	buildPopup(screenGui)

	Store.Changed:Connect(function(what)
		if what == "Trade" then
			local trade = Store.Trade
			if trade and not trade.Active and trade.Reason and wasActive then
				Notifications.Show(trade.Reason, trade.Completed and "Success" or "Info")
			end
			refresh()
			refreshPopup()
		elseif what == "TradeRequests" then
			refreshPopup()
			if window.Visible and not (Store.Trade and Store.Trade.Active) then
				refreshLobby()
			end
		elseif what == "Data" and Store.Trade and Store.Trade.Active and window.Visible then
			refreshTrade(Store.Trade)
		end
	end)
	task.spawn(function()
		while true do
			task.wait(0.25)
			updateStatus()
			refreshPopup()
		end
	end)
	Players.PlayerAdded:Connect(function()
		if window.Visible and not (Store.Trade and Store.Trade.Active) then
			refreshLobby()
		end
	end)
	Players.PlayerRemoving:Connect(function()
		task.defer(function()
			if window.Visible and not (Store.Trade and Store.Trade.Active) then
				refreshLobby()
			end
		end)
	end)
end

function TradeWindow.Open()
	window.Visible = true
	UI.pop(window)
	refresh()
end

-- Just hides the window (the trade carries on; the Trade button brings it back).
function TradeWindow.Close()
	window.Visible = false
end

function TradeWindow.IsOpen()
	return window.Visible
end

return TradeWindow
