-- Loads, holds and saves each player's progress.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Birds = require(Shared.Birds)
local Net = require(Shared.Net)
local Pets = require(Shared.Pets)
local Seeds = require(Shared.Seeds)
local Util = require(Shared.Util)

local DataService = {}

local profiles = {} -- [Player] = { Data = table, CanSave = bool, SelectedSeed = string? }

local store
do
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(Config.DataStoreName)
	end)
	if ok then
		store = result
	else
		warn("[BirdGarden] DataStore unavailable, progress will not be saved:", result)
	end
end

local function defaultData()
	return {
		Coins = Config.StartingCoins,
		Seeds = Util.DeepCopy(Config.StartingSeeds),
		Plants = {}, -- ["tileIndex"] = { Seed = id, Grown = seconds of growth, SavedAt = unixSeconds }
		Journal = {}, -- [birdId] = times befriended
		ShinyJournal = {}, -- [birdId] = shiny times befriended
		TotalBefriended = 0,
		Pets = {}, -- [petId] = pet table, see Pets.lua
		NextPetId = 1,
		Nests = {}, -- ["nestIndex"] = { Species, ParentA, ParentB, StartedAt, HatchAt, Restore }
		TotalHatched = 0,
	}
end

local function reconcile(data)
	local template = defaultData()
	for key, value in pairs(template) do
		if data[key] == nil then
			data[key] = value
		end
	end
	-- drop anything that no longer exists in the game
	for seedId in pairs(data.Seeds) do
		if not Seeds.Get(seedId) then
			data.Seeds[seedId] = nil
		end
	end
	for tile, plant in pairs(data.Plants) do
		if type(plant) ~= "table" or not Seeds.Get(plant.Seed) then
			data.Plants[tile] = nil
		end
	end
	for id, pet in pairs(data.Pets) do
		if type(pet) ~= "table" or not Birds.Get(pet.Species) then
			data.Pets[id] = nil
		else
			pet.Stars = math.clamp(math.floor(tonumber(pet.Stars) or 1), 1, Pets.MaxStars)
			pet.Name = type(pet.Name) == "string" and pet.Name or Pets.FirstNames[1]
		end
	end
	-- a nest is only valid while both parents are still sitting on it
	for key, nest in pairs(data.Nests) do
		local index = tonumber(key)
		local a = type(nest) == "table" and data.Pets[nest.ParentA]
		local b = type(nest) == "table" and data.Pets[nest.ParentB]
		if not (index and a and b and a.Nest == index and b.Nest == index) then
			data.Nests[key] = nil
		end
	end
	for _, pet in pairs(data.Pets) do
		if pet.Nest and not data.Nests[tostring(pet.Nest)] then
			pet.Nest = nil
		end
	end
	return data
end

local function keyFor(player)
	return "Player_" .. player.UserId
end

function DataService.Load(player)
	local data, ok, err = nil, store ~= nil, nil
	if store then
		for attempt = 1, 3 do
			ok, err = pcall(function()
				data = store:GetAsync(keyFor(player))
			end)
			if ok then
				break
			end
			task.wait(attempt)
		end
	end

	local profile = {
		Data = (ok and type(data) == "table") and reconcile(data) or defaultData(),
		-- never overwrite a save we failed to read
		CanSave = store ~= nil and ok,
		SelectedSeed = nil,
	}
	profiles[player] = profile

	if not ok then
		if store then
			warn("[BirdGarden] Failed to load data for", player.Name, err)
		end
		if RunService:IsStudio() then
			Net.Notify:FireClient(
				player,
				"Saving is off in Studio. Enable 'Studio Access to API Services' in Game Settings to test saving.",
				"Info"
			)
		else
			Net.Notify:FireClient(player, "We couldn't load your save, so progress this visit won't be saved.", "Error")
		end
	end
	return profile
end

function DataService.GetProfile(player)
	return profiles[player]
end

function DataService.Get(player)
	local profile = profiles[player]
	return profile and profile.Data
end

function DataService.Save(player)
	local profile = profiles[player]
	if not profile or not profile.CanSave or not store then
		return false
	end
	local ok, err = pcall(function()
		store:UpdateAsync(keyFor(player), function()
			return profile.Data
		end)
	end)
	if not ok then
		warn("[BirdGarden] Failed to save data for", player.Name, err)
	end
	return ok
end

function DataService.Release(player)
	DataService.Save(player)
	profiles[player] = nil
end

-- Drops a profile without saving it.
function DataService.Forget(player)
	profiles[player] = nil
end

function DataService.SaveAll()
	local threads = {}
	for player in pairs(profiles) do
		table.insert(threads, task.spawn(DataService.Save, player))
	end
	-- wait (up to a limit) for the saves to finish
	local deadline = os.clock() + 20
	while os.clock() < deadline do
		local running = false
		for _, thread in ipairs(threads) do
			if coroutine.status(thread) ~= "dead" then
				running = true
				break
			end
		end
		if not running then
			break
		end
		task.wait(0.2)
	end
end

------------------------------------------------------------------------------
-- Seeds selection (not saved) and state sync

-- Makes sure the selected seed is one the player actually owns.
function DataService.EnsureSelection(player)
	local profile = profiles[player]
	if not profile then
		return nil
	end
	local owned = profile.Data.Seeds
	if profile.SelectedSeed and (owned[profile.SelectedSeed] or 0) > 0 then
		return profile.SelectedSeed
	end
	profile.SelectedSeed = nil
	for _, seed in ipairs(Seeds.List) do
		if (owned[seed.Id] or 0) > 0 then
			profile.SelectedSeed = seed.Id
			break
		end
	end
	return profile.SelectedSeed
end

function DataService.Snapshot(player)
	local profile = profiles[player]
	if not profile then
		return nil
	end
	local data = profile.Data
	local now = Util.Now()
	return {
		Coins = data.Coins,
		Seeds = data.Seeds,
		Journal = data.Journal,
		ShinyJournal = data.ShinyJournal,
		TotalBefriended = data.TotalBefriended,
		SelectedSeed = profile.SelectedSeed,
		Pets = data.Pets,
		Nests = data.Nests,
		Perks = Pets.ComputePerks(data.Pets, now),
		ServerNow = now,
	}
end

-- Sends the latest state to the player's UI and updates leaderstats.
function DataService.Push(player)
	local profile = profiles[player]
	if not profile or player.Parent ~= Players then
		return
	end
	local leaderstats = player:FindFirstChild("leaderstats")
	if leaderstats then
		leaderstats.Coins.Value = profile.Data.Coins
		leaderstats.Birds.Value = profile.Data.TotalBefriended
	end
	Net.DataUpdated:FireClient(player, DataService.Snapshot(player))
end

return DataService
