-- Player-to-player trading of birds and coins.
--
-- 1. A player sends a request; the other player accepts or declines.
-- 2. Both add birds and coins to their side. Any change un-readies both.
-- 3. When both are ready a short countdown starts, then the server checks
--    everything again and swaps the birds and coins in one go.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Pets = require(Shared.Pets)
local Util = require(Shared.Util)

local DataService = require(script.Parent.DataService)
local PetService = require(script.Parent.PetService)

local TradeService = {}

local sessions = {} -- [Player] = session (both players point at the same session)
local requests = {} -- [target Player] = { [from Player] = expiresAt }
local lastRequest = {} -- [Player] = time of their last request

local function partnerOf(session, player)
	return session.Players[1] == player and session.Players[2] or session.Players[1]
end

local function stateFor(session, player)
	local other = partnerOf(session, player)
	local mine, theirs = session.Offers[player], session.Offers[other]
	local theirData = DataService.Get(other)
	local theirPets = {}
	for _, id in ipairs(theirs.Pets) do
		local pet = theirData and theirData.Pets[id]
		if pet then
			table.insert(theirPets, PetService.Summary(pet, id))
		end
	end
	return {
		Active = true,
		PartnerName = other.DisplayName,
		PartnerUserId = other.UserId,
		MyPets = table.clone(mine.Pets),
		MyCoins = mine.Coins,
		TheirPets = theirPets,
		TheirCoins = theirs.Coins,
		MyReady = session.Ready[player] == true,
		TheirReady = session.Ready[other] == true,
		ExecuteAt = session.ExecuteAt,
		ServerNow = Util.Now(),
	}
end

local function sendState(session)
	for _, player in ipairs(session.Players) do
		if player.Parent == Players then
			Net.TradeState:FireClient(player, stateFor(session, player))
		end
	end
end

local function endSession(session, reason, completed)
	for _, player in ipairs(session.Players) do
		if sessions[player] == session then
			sessions[player] = nil
		end
		if player.Parent == Players then
			Net.TradeState:FireClient(player, { Active = false, Reason = reason, Completed = completed == true })
		end
	end
end

local function unready(session)
	session.Ready = {}
	session.ExecuteAt = nil
end

local function isEmpty(session)
	for _, offer in pairs(session.Offers) do
		if #offer.Pets > 0 or offer.Coins > 0 then
			return false
		end
	end
	return true
end

------------------------------------------------------------------------------
-- Requests

function TradeService.Request(player, targetUserId)
	if type(targetUserId) ~= "number" then
		return
	end
	local target = Players:GetPlayerByUserId(targetUserId)
	local now = Util.Now()
	if not target or target == player then
		return
	end
	if not DataService.Get(player) or not DataService.Get(target) then
		Net.Notify:FireClient(player, "That player is still loading.", "Error")
		return
	end
	if sessions[player] then
		Net.Notify:FireClient(player, "Finish your current trade first.", "Error")
		return
	end
	if sessions[target] then
		Net.Notify:FireClient(player, target.DisplayName .. " is already trading.", "Error")
		return
	end
	if lastRequest[player] and now - lastRequest[player] < Config.TradeRequestCooldown then
		Net.Notify:FireClient(player, "Slow down! Wait a moment before sending another request.", "Error")
		return
	end
	lastRequest[player] = now
	requests[target] = requests[target] or {}
	requests[target][player] = now + Config.TradeRequestTimeout
	Net.TradeIncoming:FireClient(target, {
		FromUserId = player.UserId,
		FromName = player.DisplayName,
		ExpiresAt = now + Config.TradeRequestTimeout,
		ServerNow = now,
	})
	Net.Notify:FireClient(player, "🤝 Trade request sent to " .. target.DisplayName .. ".", "Info")
end

function TradeService.Respond(player, fromUserId, accept)
	if type(fromUserId) ~= "number" then
		return
	end
	local from = Players:GetPlayerByUserId(fromUserId)
	local pending = from and requests[player] and requests[player][from]
	if not pending or Util.Now() > pending then
		if requests[player] and from then
			requests[player][from] = nil
		end
		Net.Notify:FireClient(player, "That trade request has expired.", "Error")
		return
	end
	requests[player][from] = nil
	if accept ~= true then
		Net.Notify:FireClient(from, player.DisplayName .. " declined your trade request.", "Info")
		return
	end
	if sessions[player] or sessions[from] then
		Net.Notify:FireClient(player, "One of you is already trading.", "Error")
		return
	end
	if not DataService.Get(player) or not DataService.Get(from) then
		return
	end
	local session = {
		Players = { from, player },
		Offers = {
			[from] = { Pets = {}, Coins = 0 },
			[player] = { Pets = {}, Coins = 0 },
		},
		Ready = {},
	}
	sessions[from] = session
	sessions[player] = session
	sendState(session)
end

------------------------------------------------------------------------------
-- Changing offers

function TradeService.Update(player, action, value)
	local session = sessions[player]
	local data = DataService.Get(player)
	if not session or not data then
		return
	end
	local offer = session.Offers[player]

	if action == "AddPet" then
		local pet = type(value) == "string" and data.Pets[value]
		if not pet or table.find(offer.Pets, value) then
			return
		end
		if #offer.Pets >= Config.TradeMaxPets then
			Net.Notify:FireClient(player, "You can offer up to " .. Config.TradeMaxPets .. " birds.", "Error")
			return
		elseif pet.Favorite then
			Net.Notify:FireClient(player, pet.Name .. " is a favorite. Unfavorite it to trade it.", "Error")
			return
		elseif pet.Nest then
			Net.Notify:FireClient(player, pet.Name .. " is busy sitting on an egg.", "Error")
			return
		end
		table.insert(offer.Pets, value)
		unready(session)
	elseif action == "RemovePet" then
		local index = type(value) == "string" and table.find(offer.Pets, value)
		if not index then
			return
		end
		table.remove(offer.Pets, index)
		unready(session)
	elseif action == "SetCoins" then
		local coins = tonumber(value)
		if not coins or coins ~= coins or coins == math.huge then
			return
		end
		coins = math.clamp(math.floor(coins), 0, data.Coins)
		if coins == offer.Coins then
			sendState(session)
			return
		end
		offer.Coins = coins
		unready(session)
	elseif action == "Ready" then
		if isEmpty(session) then
			Net.Notify:FireClient(player, "Add a bird or some coins to the trade first.", "Error")
			return
		end
		session.Ready[player] = true
		local other = partnerOf(session, player)
		if session.Ready[other] then
			session.ExecuteAt = Util.Now() + Config.TradeCountdown
		end
	elseif action == "Unready" then
		session.Ready[player] = nil
		session.ExecuteAt = nil
	elseif action == "Cancel" then
		endSession(session, player.DisplayName .. " cancelled the trade.")
		return
	else
		return
	end
	sendState(session)
end

------------------------------------------------------------------------------
-- Doing the trade

local function problemWith(player, data, offer)
	if not data or player.Parent ~= Players then
		return player.DisplayName .. " left."
	end
	for _, id in ipairs(offer.Pets) do
		local pet = data.Pets[id]
		if not pet then
			return player.DisplayName .. " no longer has one of those birds."
		elseif pet.Nest then
			return Pets.DisplayName(pet) .. " is sitting on an egg."
		end
	end
	if offer.Coins > data.Coins then
		return player.DisplayName .. " doesn't have that many coins any more."
	end
	return nil
end

local function execute(session)
	local a, b = session.Players[1], session.Players[2]
	local dataA, dataB = DataService.Get(a), DataService.Get(b)
	local offerA, offerB = session.Offers[a], session.Offers[b]

	local problem = problemWith(a, dataA, offerA) or problemWith(b, dataB, offerB)
	if not problem then
		if Pets.CountPets(dataA.Pets) - #offerA.Pets + #offerB.Pets > Config.MaxPets then
			problem = a.DisplayName .. "'s aviary doesn't have room."
		elseif Pets.CountPets(dataB.Pets) - #offerB.Pets + #offerA.Pets > Config.MaxPets then
			problem = b.DisplayName .. "'s aviary doesn't have room."
		end
	end
	if problem then
		unready(session)
		for _, player in ipairs(session.Players) do
			if player.Parent == Players then
				Net.Notify:FireClient(player, "Trade stopped: " .. problem, "Error")
			end
		end
		if dataA and dataB and a.Parent == Players and b.Parent == Players then
			sendState(session)
		else
			endSession(session, "Trade cancelled.")
		end
		return
	end

	-- take everything out first, then hand it over
	local fromA, fromB = {}, {}
	for _, id in ipairs(offerA.Pets) do
		table.insert(fromA, dataA.Pets[id])
		dataA.Pets[id] = nil
	end
	for _, id in ipairs(offerB.Pets) do
		table.insert(fromB, dataB.Pets[id])
		dataB.Pets[id] = nil
	end
	local function receive(data, pets)
		for _, pet in ipairs(pets) do
			pet.Equipped = false
			pet.Favorite = false
			pet.Nest = nil
			pet.ParentIds = nil -- those ids belonged to the old owner
			PetService.AddPet(data, pet)
		end
	end
	receive(dataB, fromA)
	receive(dataA, fromB)
	dataA.Coins += offerB.Coins - offerA.Coins
	dataB.Coins += offerA.Coins - offerB.Coins

	endSession(session, "Trade complete!", true)
	for _, player in ipairs(session.Players) do
		PetService.Refresh(player)
		Net.Notify:FireClient(player, "🤝 Trade complete! Check your aviary.", "Success")
		-- save straight away so a crash can't undo half a trade
		task.spawn(DataService.Save, player)
	end
end

------------------------------------------------------------------------------
-- Hooks

function TradeService.IsOffered(player, petId)
	local session = sessions[player]
	return session ~= nil and table.find(session.Offers[player].Pets, petId) ~= nil
end

-- Called when a player's pets change: drops birds that can't be traded any more.
function TradeService.Revalidate(player)
	local session = sessions[player]
	if not session then
		return
	end
	local data = DataService.Get(player)
	local offer = session.Offers[player]
	local changed = false
	for i = #offer.Pets, 1, -1 do
		local pet = data and data.Pets[offer.Pets[i]]
		if not pet or pet.Nest or pet.Favorite then
			table.remove(offer.Pets, i)
			changed = true
		end
	end
	if data and offer.Coins > data.Coins then
		offer.Coins = data.Coins
		changed = true
	end
	if changed then
		unready(session)
	end
	sendState(session)
end

function TradeService.PlayerLeft(player)
	local session = sessions[player]
	if session then
		endSession(session, player.DisplayName .. " left the game.")
	end
	requests[player] = nil
	lastRequest[player] = nil
	for _, pending in pairs(requests) do
		pending[player] = nil
	end
end

function TradeService.Tick(now)
	local done = {}
	for _, session in pairs(sessions) do
		if not done[session] then
			done[session] = true
			if session.ExecuteAt and now >= session.ExecuteAt then
				session.ExecuteAt = nil
				execute(session)
			end
		end
	end
end

return TradeService
