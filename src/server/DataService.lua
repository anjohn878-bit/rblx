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

-- Session locking: while a server has a player's data loaded it stamps the
-- save with its JobId. Another server waits for the lock to be released (or
-- to go stale) before loading, and a server that lost the lock stops saving.
-- Without this, hopping servers right after a trade could duplicate birds.
local LOCK_STALE_AFTER = 300 -- seconds without a save before a lock is ignored
local LOCK_WAIT_ATTEMPTS = 6
local LOCK_WAIT_SECONDS = 5
local LOAD_ATTEMPTS = 3 -- when the DataStore itself errors
local SAVE_ATTEMPTS = 3

local jobId = "studio"
pcall(function()
	if game.JobId ~= "" then
		jobId = game.JobId
	end
end)

local function lockedByOtherServer(stored)
	local lock = type(stored) == "table" and stored.Lock
	return type(lock) == "table" and lock.JobId ~= jobId and os.time() - (tonumber(lock.Time) or 0) < LOCK_STALE_AFTER
end

-- Reads the save and takes the lock in one step. Returns ok, data, lockedElsewhere.
local function loadAndLock(key, force)
	local result, locked
	local ok, err = pcall(function()
		store:UpdateAsync(key, function(stored)
			result, locked = stored, false
			if not force and lockedByOtherServer(stored) then
				locked = true
				return nil -- leave it alone
			end
			if type(stored) ~= "table" then
				-- new player: write just the lock, so the key is ours from the start
				return { Lock = { JobId = jobId, Time = os.time() } }
			end
			stored.Lock = { JobId = jobId, Time = os.time() }
			return stored
		end)
	end)
	return ok, result, locked, err
end

-- Gives back a lock this server holds (for a player who left while loading).
local function unlock(key)
	pcall(function()
		store:UpdateAsync(key, function(stored)
			if type(stored) == "table" and type(stored.Lock) == "table" and stored.Lock.JobId == jobId then
				stored.Lock = nil
				return stored
			end
			return nil
		end)
	end)
end

function DataService.Load(player)
	local data, ok, err = nil, store ~= nil, nil
	if store then
		local key = keyFor(player)
		local errors, waits = 0, 0
		while true do
			local locked
			-- after waiting long enough, take over the lock (that server is stuck)
			ok, data, locked, err = loadAndLock(key, waits >= LOCK_WAIT_ATTEMPTS)
			if ok and not locked then
				break
			end
			if not ok then
				errors += 1
				if errors >= LOAD_ATTEMPTS then
					break
				end
			else
				waits += 1
				if waits == 1 then
					Net.Notify:FireClient(
						player,
						"Your garden is still being saved on another server. One moment...",
						"Info"
					)
				end
			end
			if player.Parent ~= Players then
				return nil
			end
			task.wait(ok and LOCK_WAIT_SECONDS or errors)
		end
		if player.Parent ~= Players then
			-- left while loading: don't keep their save locked
			if ok then
				unlock(key)
			end
			return nil
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

-- release = true for the final save when the player leaves (frees the lock).
-- Retries a few times: a lost save could undo a trade on the next server.
function DataService.Save(player, release)
	local profile = profiles[player]
	if not profile or not profile.CanSave or not store then
		return false
	end
	for attempt = 1, SAVE_ATTEMPTS do
		if profile.Released and not release then
			return false -- the final save is already on its way; don't lock it again
		end
		local lostLock = false
		local ok, err = pcall(function()
			store:UpdateAsync(keyFor(player), function(stored)
				lostLock = false
				if lockedByOtherServer(stored) then
					-- another server took over this player's data; don't overwrite it
					lostLock = true
					return nil
				end
				if profile.Released and not release then
					return nil
				end
				profile.Data.Lock = not release and { JobId = jobId, Time = os.time() } or nil
				return profile.Data
			end)
		end)
		if ok and lostLock then
			warn("[BirdGarden] Another server owns " .. player.Name .. "'s data now; stopped saving here")
			profile.CanSave = false
			return false
		elseif ok then
			return true
		end
		warn("[BirdGarden] Failed to save data for", player.Name, err)
		if attempt < SAVE_ATTEMPTS then
			task.wait(attempt * 2)
		end
	end
	return false
end

function DataService.Release(player)
	local profile = profiles[player]
	if profile then
		profile.Released = true
	end
	DataService.Save(player, true)
	profiles[player] = nil
end

function DataService.SaveAll()
	local threads = {}
	for player, profile in pairs(profiles) do
		profile.Released = true
		table.insert(threads, task.spawn(DataService.Save, player, true))
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
