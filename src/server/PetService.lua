-- Pet birds: befriended birds join your aviary, roam your garden when
-- equipped (giving perks), can be sold, and grow up from babies.
--
-- Roaming pets are drawn by each client. The server only publishes a marker
-- (a Folder with attributes) per roaming or nesting pet in
-- ReplicatedStorage.BirdGardenPets.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Birds = require(Shared.Birds)
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Pets = require(Shared.Pets)
local Rarities = require(Shared.Rarities)
local Seeds = require(Shared.Seeds)
local Util = require(Shared.Util)

local DataService = require(script.Parent.DataService)

local PetService = {}

local rng = Random.new()
local markers -- Folder of roaming pet markers
local perkCache = {} -- [Player] = perks table
local nextSeedRoll = {} -- [Player] = unix time
local changeListeners = {}

-- Set by Main: called after a pet finds a seed (so plant prompts update).
PetService.SeedsChanged = function(_player) end
-- Set by Main: returns true if the pet is offered in an active trade.
PetService.IsInTrade = function(_player, _petId)
	return false
end

------------------------------------------------------------------------------
-- Helpers

function PetService.MarkerName(player, petId)
	return player.UserId .. "_" .. petId
end

local function randomName()
	return Pets.FirstNames[rng:NextInteger(1, #Pets.FirstNames)]
end

local NUMERALS = { "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X" }

-- A surname nobody in this aviary uses yet, so families never get mixed up.
function PetService.NewFamilyName(data)
	local used = {}
	for _, pet in pairs(data.Pets) do
		if pet.Family then
			used[pet.Family] = true
		end
	end
	local free = {}
	for _, name in ipairs(Pets.FamilyNames) do
		if not used[name] then
			table.insert(free, name)
		end
	end
	if #free > 0 then
		return free[rng:NextInteger(1, #free)]
	end
	local base = Pets.FamilyNames[rng:NextInteger(1, #Pets.FamilyNames)]
	for n = 2, 1000 do
		local name = base .. " " .. (NUMERALS[n - 1] or tostring(n))
		if not used[name] then
			return name
		end
	end
	return base
end

local function rollWildStars()
	local weights = {}
	for stars, weight in ipairs(Config.WildStarWeights) do
		table.insert(weights, { Stars = stars, Weight = weight })
	end
	return Util.WeightedPick(weights, rng).Stars
end

function PetService.NewPet(fields)
	local pet = {
		Name = randomName(),
		Stars = 1,
		Shiny = false,
		Generation = 0,
		CaughtAt = os.time(),
	}
	for key, value in pairs(fields) do
		pet[key] = value
	end
	return pet
end

-- Adds a pet to the data and returns its new id.
function PetService.AddPet(data, pet)
	local id = "P" .. data.NextPetId
	data.NextPetId += 1
	data.Pets[id] = pet
	return id
end

function PetService.OnChanged(listener)
	table.insert(changeListeners, listener)
end

function PetService.GetPerks(player)
	local perks = perkCache[player]
	if not perks then
		local data = DataService.Get(player)
		perks = Pets.ComputePerks(data and data.Pets or {}, Util.Now())
		-- only remember real perks (not the empty ones from before the save loads)
		if data then
			perkCache[player] = perks
		end
	end
	return perks
end

------------------------------------------------------------------------------
-- Roaming markers

local function findRoamingParent(player, data, pet)
	-- babies tag along behind a parent (or any family member) out in the garden
	if type(pet.ParentIds) == "table" then
		for _, parentId in ipairs(pet.ParentIds) do
			local parent = data.Pets[parentId]
			if parent and parent.Equipped and not parent.Nest then
				return PetService.MarkerName(player, parentId)
			end
		end
	end
	if pet.Family then
		for id, other in pairs(data.Pets) do
			if
				other ~= pet
				and other.Family == pet.Family
				and other.Species == pet.Species
				and other.Equipped
				and not other.Nest
				and not other.GrowsUpAt
			then
				return PetService.MarkerName(player, id)
			end
		end
	end
	return ""
end

function PetService.SyncRoaming(player)
	local data = DataService.Get(player)
	local plotId = player:GetAttribute("PlotId")
	local now = Util.Now()
	local wanted = {}
	if data and plotId and player.Parent == Players then
		for id, pet in pairs(data.Pets) do
			if pet.Nest or pet.Equipped then
				wanted[PetService.MarkerName(player, id)] = id
			end
		end
	end

	for _, marker in ipairs(markers:GetChildren()) do
		if marker:GetAttribute("OwnerUserId") == player.UserId and not wanted[marker.Name] then
			marker:Destroy()
		end
	end

	for name, id in pairs(wanted) do
		local pet = data.Pets[id]
		local marker = markers:FindFirstChild(name)
		local isNew = marker == nil
		if isNew then
			marker = Instance.new("Folder")
			marker.Name = name
		end
		marker:SetAttribute("PetId", id)
		marker:SetAttribute("OwnerUserId", player.UserId)
		marker:SetAttribute("PlotId", plotId)
		marker:SetAttribute("Species", pet.Species)
		marker:SetAttribute("Shiny", pet.Shiny == true)
		marker:SetAttribute("Stars", pet.Stars or 1)
		marker:SetAttribute("Baby", Pets.IsBaby(pet, now))
		marker:SetAttribute("DisplayName", Pets.DisplayName(pet))
		marker:SetAttribute("Mode", pet.Nest and "Nest" or "Roam")
		marker:SetAttribute("NestIndex", pet.Nest or 0)
		marker:SetAttribute("Follow", Pets.IsBaby(pet, now) and findRoamingParent(player, data, pet) or "")
		if isNew then
			marker.Parent = markers
		end
	end
end

function PetService.FindMarker(player, petId)
	return markers:FindFirstChild(PetService.MarkerName(player, petId))
end

function PetService.RemoveRoaming(player)
	for _, marker in ipairs(markers:GetChildren()) do
		if marker:GetAttribute("OwnerUserId") == player.UserId then
			marker:Destroy()
		end
	end
end

-- Call after any change to a player's pets.
function PetService.Refresh(player)
	local data = DataService.Get(player)
	if not data then
		return
	end
	perkCache[player] = Pets.ComputePerks(data.Pets, Util.Now())
	PetService.SyncRoaming(player)
	for _, listener in ipairs(changeListeners) do
		listener(player)
	end
	DataService.Push(player)
end

------------------------------------------------------------------------------
-- Catching

-- The weakest roaming bird that could make way for a better one.
local function weakestOut(data, now)
	local weakestId, weakestPoints
	for id, pet in pairs(data.Pets) do
		if pet.Equipped and not pet.Nest and not pet.Favorite and not Pets.IsBaby(pet, now) then
			local points = Pets.Points(pet, now)
			if not weakestPoints or points < weakestPoints then
				weakestId, weakestPoints = id, points
			end
		end
	end
	return weakestId, weakestPoints
end

-- A befriended bird joins the aviary.
-- Returns pet, petId, coins earned, first time seen, refusal ("Full"), and the
-- pet it replaced in the garden (if it was better than one that was out).
function PetService.Befriend(player, def, shiny)
	local data = DataService.Get(player)
	if not data then
		return nil
	end
	local now = Util.Now()
	local perks = PetService.GetPerks(player)
	local pet = PetService.NewPet({ Species = def.Id, Shiny = shiny, Stars = rollWildStars() })
	local firstTime = (data.Journal[def.Id] or 0) == 0
	local count = Pets.CountPets(data.Pets)
	local full = count >= Config.MaxPets

	-- never throw away anything special just because the aviary is full
	if full and (shiny or firstTime or pet.Stars >= 3 or Rarities.Rank(def.Rarity) >= Rarities.Rank("Rare")) then
		return nil, nil, 0, false, "Full"
	end

	data.Journal[def.Id] = (data.Journal[def.Id] or 0) + 1
	if shiny then
		data.ShinyJournal[def.Id] = (data.ShinyJournal[def.Id] or 0) + 1
	end
	data.TotalBefriended += 1

	local coins = 0
	if firstTime then
		coins += math.floor(Pets.BaseValue(pet, now) * Config.DiscoveryBonusMultiplier * (1 + perks.Coins))
	end
	local id, replaced
	if full then
		-- a plain bird and no room: it's sold straight away
		coins += Pets.SellPrice(pet, now, perks)
	else
		id = PetService.AddPet(data, pet)
		if Pets.CountEquipped(data.Pets) < Config.MaxEquippedPets then
			pet.Equipped = true
		else
			-- better than one of the birds that's out? swap them
			local weakestId, weakestPoints = weakestOut(data, now)
			if weakestId and Pets.Points(pet, now) > weakestPoints then
				replaced = data.Pets[weakestId]
				replaced.Equipped = false
				pet.Equipped = true
			end
		end
		if count + 1 == Config.MaxPets - 5 then
			Net.Notify:FireClient(
				player,
				"Your aviary is almost full ("
					.. count + 1
					.. "/"
					.. Config.MaxPets
					.. "). Sell spares in 🐦 Birds to make room.",
				"Info"
			)
		end
	end
	data.Coins += coins
	PetService.Refresh(player)

	if data.TotalBefriended == 1 then
		task.delay(3, function()
			Net.Notify:FireClient(
				player,
				"💡 Your birds live in the 🐦 Birds aviary. Send the best ones out to help your garden, and sell spares for coins!",
				"Success"
			)
		end)
	end
	return pet, id, coins, firstTime, nil, replaced
end

------------------------------------------------------------------------------
-- Actions from the aviary window. Each returns ok, message.

local function getPet(player, petId)
	local data = DataService.Get(player)
	if not data or type(petId) ~= "string" then
		return nil, nil
	end
	return data.Pets[petId], data
end

function PetService.Equip(player, petId)
	local pet, data = getPet(player, petId)
	if not pet then
		return false, "That bird isn't in your aviary."
	end
	if pet.Nest then
		return false, pet.Name .. " is busy sitting on an egg."
	end
	if pet.Equipped then
		return true, pet.Name .. " is already out."
	end
	if Pets.CountEquipped(data.Pets) >= Config.MaxEquippedPets then
		return false, "Only " .. Config.MaxEquippedPets .. " birds can roam at once. Put one away first."
	end
	pet.Equipped = true
	PetService.Refresh(player)
	return true, pet.Name .. " is exploring your garden!"
end

function PetService.Unequip(player, petId)
	local pet = getPet(player, petId)
	if not pet then
		return false, "That bird isn't in your aviary."
	end
	pet.Equipped = false
	PetService.Refresh(player)
	return true, pet.Name .. " went back to the aviary."
end

function PetService.SetFavorite(player, petId, favorite)
	local pet = getPet(player, petId)
	if not pet then
		return false, "That bird isn't in your aviary."
	end
	if favorite and PetService.IsInTrade(player, petId) then
		return false, "Take " .. pet.Name .. " out of the trade first."
	end
	pet.Favorite = favorite == true
	PetService.Refresh(player)
	return true,
		pet.Favorite and (pet.Name .. " is a favorite. Favorites can't be sold or traded.")
			or (pet.Name .. " is no longer a favorite.")
end

local function sellBlocker(player, pet, petId)
	if pet.Favorite then
		return pet.Name .. " is a favorite. Unfavorite it to sell."
	elseif pet.Nest then
		return pet.Name .. " is busy sitting on an egg."
	elseif PetService.IsInTrade(player, petId) then
		return pet.Name .. " is part of a trade."
	end
	return nil
end

function PetService.Sell(player, petId)
	local pet, data = getPet(player, petId)
	if not pet then
		return false, "That bird isn't in your aviary."
	end
	local blocker = sellBlocker(player, pet, petId)
	if blocker then
		return false, blocker
	end
	local price = Pets.SellPrice(pet, Util.Now(), PetService.GetPerks(player))
	data.Pets[petId] = nil
	data.Coins += price
	PetService.Refresh(player)
	return true, "Sold " .. Pets.DisplayName(pet) .. " for " .. Util.FormatNumber(price) .. " coins."
end

-- Sends out the strongest birds (by perk points).
function PetService.EquipBest(player)
	local data = DataService.Get(player)
	if not data then
		return false, "Your garden is still loading..."
	end
	local now = Util.Now()
	local ids = {}
	for id, pet in pairs(data.Pets) do
		if not pet.Nest then
			table.insert(ids, id)
		end
	end
	if #ids == 0 then
		return false, "You don't have any birds to send out yet."
	end
	table.sort(ids, function(a, b)
		local pa, pb = Pets.Points(data.Pets[a], now), Pets.Points(data.Pets[b], now)
		if pa ~= pb then
			return pa > pb
		end
		return a < b
	end)
	for index, id in ipairs(ids) do
		data.Pets[id].Equipped = index <= Config.MaxEquippedPets
	end
	PetService.Refresh(player)
	return true, "Your best birds are out in the garden!"
end

-- Sells every spare bird (see Pets.IsSpare) at or below a rarity.
function PetService.SellBulk(player, maxRarity)
	local data = DataService.Get(player)
	local maxRank = Rarities.Rank(maxRarity)
	if not data or maxRank == 0 then
		return false, "Pick a rarity to sell."
	end
	local now = Util.Now()
	local perks = PetService.GetPerks(player)
	local sold, coins = 0, 0
	for id, pet in pairs(data.Pets) do
		local def = Pets.Def(pet)
		if
			def
			and Rarities.Rank(def.Rarity) <= maxRank
			and Pets.IsSpare(pet, now)
			and not PetService.IsInTrade(player, id)
		then
			coins += Pets.SellPrice(pet, now, perks)
			sold += 1
			data.Pets[id] = nil
		end
	end
	if sold == 0 then
		return false,
			"No spares to sell. Birds that are out, nesting, favorites, shiny, in a family, babies or 4⭐+ are kept."
	end
	data.Coins += coins
	PetService.Refresh(player)
	return true, "Sold " .. sold .. " birds for " .. Util.FormatNumber(coins) .. " coins."
end

------------------------------------------------------------------------------
-- Lifecycle and ticking

function PetService.Init()
	markers = ReplicatedStorage:FindFirstChild("BirdGardenPets")
	if not markers then
		markers = Instance.new("Folder")
		markers.Name = "BirdGardenPets"
		markers.Parent = ReplicatedStorage
	end
end

function PetService.PlayerLoaded(player)
	nextSeedRoll[player] = Util.Now() + Config.SeedFinderInterval
	PetService.Refresh(player)
end

function PetService.PlayerLeft(player)
	PetService.RemoveRoaming(player)
	perkCache[player] = nil
	nextSeedRoll[player] = nil
end

-- A bird finds seeds up to one rarity above its own; cheaper seeds are more
-- common, and the Lucky perk tilts it toward rarer ones.
local function pickFoundSeed(finderRank, luck)
	local weights = {}
	for _, seed in ipairs(Seeds.List) do
		local rank = Rarities.Rank(seed.Rarity)
		if rank <= finderRank + 1 then
			local weight = seed.Stock.Chance / math.sqrt(seed.Price) * (1 + luck * (rank - 1))
			table.insert(weights, { Seed = seed, Weight = weight })
		end
	end
	return Util.WeightedPick(weights, rng).Seed
end

local function pickSeedFinder(data, now)
	local weights = {}
	for id, pet in pairs(data.Pets) do
		local def = Pets.Def(pet)
		if pet.Equipped and not pet.Nest and def and def.Perk == "SeedFinder" then
			table.insert(weights, { Id = id, Pet = pet, Weight = Pets.Points(pet, now) })
		end
	end
	if #weights == 0 then
		return nil
	end
	return Util.WeightedPick(weights, rng)
end

local function rollSeedFinder(player, data, now)
	local perks = PetService.GetPerks(player)
	if perks.SeedFinder <= 0 or rng:NextNumber() >= perks.SeedFinder then
		return
	end
	local finder = pickSeedFinder(data, now)
	if not finder then
		return
	end
	local seed = pickFoundSeed(Rarities.Rank(Pets.Def(finder.Pet).Rarity), perks.Luck)
	data.Seeds[seed.Id] = (data.Seeds[seed.Id] or 0) + 1
	DataService.EnsureSelection(player)
	PetService.SeedsChanged(player)
	DataService.Push(player)
	Net.PetEvent:FireClient(
		player,
		PetService.MarkerName(player, finder.Id),
		"🎒 Found a " .. seed.Name .. " seed!",
		Rarities.Color(seed.Rarity)
	)
	Net.Notify:FireClient(
		player,
		"🎒 "
			.. finder.Pet.Name
			.. " the "
			.. Birds.Get(finder.Pet.Species).Name
			.. " found a "
			.. seed.Icon
			.. " "
			.. seed.Name
			.. " seed!",
		Rarities.Rank(seed.Rarity) >= Rarities.Rank("Rare") and "Rare" or "Success"
	)
end

function PetService.Tick(now)
	for player, rollAt in pairs(nextSeedRoll) do
		local data = DataService.Get(player)
		if data then
			-- babies growing up
			local grewUp = false
			for _, pet in pairs(data.Pets) do
				if pet.GrowsUpAt and now >= pet.GrowsUpAt then
					pet.GrowsUpAt = nil
					grewUp = true
					Net.Notify:FireClient(
						player,
						"🐦 "
							.. Pets.DisplayName(pet)
							.. " grew up into a fine "
							.. Birds.Get(pet.Species).Name
							.. "!",
						"Success"
					)
				end
			end
			if grewUp then
				PetService.Refresh(player)
			end

			if now >= rollAt then
				nextSeedRoll[player] = now + Config.SeedFinderInterval
				rollSeedFinder(player, data, now)
			end
		end
	end
end

-- What the other player sees about a pet in a trade.
function PetService.Summary(pet, id)
	local now = Util.Now()
	return {
		Id = id,
		Species = pet.Species,
		Name = Pets.DisplayName(pet),
		Stars = pet.Stars or 1,
		Shiny = pet.Shiny == true,
		Baby = Pets.IsBaby(pet, now),
		Value = Pets.BaseValue(pet, now),
	}
end

return PetService
