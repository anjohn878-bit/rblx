--[[
	DataService
	Loads, saves and replicates player profiles.

	Profiles are plain tables. Anything that changes a profile calls
	DataService.markChanged, which updates leaderstats and queues a sync to the
	owning client. Data is saved on leave, on shutdown and every few minutes.
	If the DataStore can't be reached (for example in Studio with API access
	turned off) the player still gets a fresh profile, it just isn't saved.
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local Signal = require(Shared.Signal)

local DataService = {}
DataService.ProfileLoaded = Signal.new() -- (player, profile)
DataService.ProfileChanged = Signal.new() -- (player, profile)

local profiles = {}
local saveEnabled = {}
local pendingSync = {}

local store
do
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(Config.DataStoreName)
	end)
	if ok then
		store = result
	else
		warn("[DataService] DataStore unavailable, progress will not save:", result)
	end
end

local function defaultProfile()
	return {
		Snowflakes = 0,
		LifetimeSnowflakes = 0,
		Rebirths = 0,
		SkateTier = 1,
		Upgrades = {
			Speed = 0,
			Jump = 0,
			Style = 0,
		},
		UnlockedRinks = {
			Pond = true,
		},
		Stats = {
			TricksLanded = 0,
			BestCombo = 0,
			BestTrick = "",
			BestTrickPoints = 0,
			GoldenSnowflakes = 0,
		},
	}
end

-- Fills in any keys that were added to the default profile after this one was saved.
local function reconcile(data, template)
	for key, value in template do
		if data[key] == nil then
			data[key] = if type(value) == "table" then table.clone(value) else value
		elseif type(value) == "table" and type(data[key]) == "table" then
			reconcile(data[key], value)
		end
	end
	return data
end

local function storeKey(player)
	return "Player_" .. player.UserId
end

local function loadProfile(player)
	if not store then
		return defaultProfile(), false
	end

	local attempts = if RunService:IsStudio() then 1 else 3
	for attempt = 1, attempts do
		local ok, result = pcall(store.GetAsync, store, storeKey(player))
		if ok then
			local data = if type(result) == "table" then result else defaultProfile()
			return reconcile(data, defaultProfile()), true
		end
		warn(string.format("[DataService] Load attempt %d for %s failed: %s", attempt, player.Name, tostring(result)))
		if attempt < attempts then
			task.wait(attempt * 2)
		end
	end

	return defaultProfile(), false
end

local function saveProfile(player)
	local profile = profiles[player]
	if not profile or not saveEnabled[player] or not store then
		return
	end

	local snapshot = table.clone(profile)
	local ok, err = pcall(store.UpdateAsync, store, storeKey(player), function()
		return snapshot
	end)
	if not ok then
		warn(string.format("[DataService] Save for %s failed: %s", player.Name, tostring(err)))
	end
end

local function createLeaderstats(player, profile)
	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"

	local snowflakes = Instance.new("IntValue")
	snowflakes.Name = Config.CurrencyName
	snowflakes.Value = math.floor(profile.Snowflakes)
	snowflakes.Parent = leaderstats

	local rebirths = Instance.new("IntValue")
	rebirths.Name = "Rebirths"
	rebirths.Value = profile.Rebirths
	rebirths.Parent = leaderstats

	leaderstats.Parent = player
end

local function updateLeaderstats(player, profile)
	local leaderstats = player:FindFirstChild("leaderstats")
	if not leaderstats then
		return
	end
	leaderstats[Config.CurrencyName].Value = math.floor(profile.Snowflakes)
	leaderstats.Rebirths.Value = profile.Rebirths
end

local function onPlayerAdded(player)
	local profile, canSave = loadProfile(player)

	if not player.Parent then
		return
	end

	profiles[player] = profile
	saveEnabled[player] = canSave
	createLeaderstats(player, profile)
	pendingSync[player] = true

	if store and not canSave then
		Remotes.Notify:FireClient(
			player,
			"Your saved data couldn't be loaded. Progress this session won't be saved.",
			"error"
		)
	end

	DataService.ProfileLoaded:Fire(player, profile)
end

local function onPlayerRemoving(player)
	saveProfile(player)
	profiles[player] = nil
	saveEnabled[player] = nil
	pendingSync[player] = nil
end

function DataService.get(player)
	return profiles[player]
end

-- Yields until the player's profile has loaded (or they leave).
function DataService.waitFor(player, timeout)
	local deadline = os.clock() + (timeout or 30)
	while not profiles[player] and player.Parent and os.clock() < deadline do
		task.wait(0.1)
	end
	return profiles[player]
end

function DataService.markChanged(player)
	local profile = profiles[player]
	if not profile then
		return
	end
	pendingSync[player] = true
	updateLeaderstats(player, profile)
	DataService.ProfileChanged:Fire(player, profile)
end

function DataService.addSnowflakes(player, amount)
	local profile = profiles[player]
	if not profile or amount <= 0 then
		return
	end
	profile.Snowflakes += amount
	profile.LifetimeSnowflakes += amount
	pendingSync[player] = true
	updateLeaderstats(player, profile)
end

-- Returns true and deducts the cost if the player can afford it.
function DataService.spend(player, amount)
	local profile = profiles[player]
	if not profile or profile.Snowflakes < amount then
		return false
	end
	profile.Snowflakes -= amount
	return true
end

function DataService.init()
	Remotes.GetProfile.OnServerInvoke = function(player)
		return DataService.waitFor(player, 15)
	end

	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end

	-- Batch profile syncs so a skater earning every tick doesn't flood the network.
	task.spawn(function()
		while true do
			task.wait(Config.Server.ProfileSyncInterval)
			for player in pendingSync do
				pendingSync[player] = nil
				local profile = profiles[player]
				if profile and player.Parent then
					Remotes.ProfileUpdated:FireClient(player, profile)
				end
			end
		end
	end)

	task.spawn(function()
		while true do
			task.wait(Config.AutosaveInterval)
			for player in profiles do
				task.spawn(saveProfile, player)
			end
		end
	end)

	game:BindToClose(function()
		local remaining = 0
		for player in profiles do
			remaining += 1
			task.spawn(function()
				saveProfile(player)
				remaining -= 1
			end)
		end
		local deadline = os.clock() + 25
		while remaining > 0 and os.clock() < deadline do
			task.wait(0.1)
		end
	end)
end

return DataService
