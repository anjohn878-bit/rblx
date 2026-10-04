--[[
	DataService
	Loads, session-locks, autosaves and releases player profiles.

	Safety rules:
	  * A profile is only saved if it was loaded successfully (never overwrite good
	    data with an empty table after a failed load).
	  * Every write goes through UpdateAsync and checks that this server still owns
	    the session lock. If another server stole the lock we stop saving.
	  * Loads retry with backoff; a lock held by a live server is waited on, a lock
	    older than Config.DataStore.SessionLockTimeout is treated as stale.
	  * In Studio without API access the game still runs with temporary,
	    non-saving profiles.

	Stored value shape: { Data = <profile>, Lock = { JobId, Time } | nil, SavedAt }
]]

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Catalog = require(Shared.Catalog)

local DataService = {}

local JOB_ID = if game.JobId ~= "" then game.JobId else ("Studio_" .. HttpService:GenerateGUID(false))

local store: DataStore? = nil
local profiles: { [Player]: any } = {}
local meta: { [Player]: { CanSave: boolean, Dirty: boolean, Saving: boolean } } = {}
local loadedCallbacks = {}
local releasingCallbacks = {}
local shuttingDown = false

local function makeTemplate()
	local attributes = {}
	for _, name in Config.Attributes.List do
		attributes[name] = Config.Attributes.Start
	end
	return {
		Version = 1,
		Level = 1,
		XP = 0,
		Kicks = 150,
		Reputation = 0,
		AttributePoints = 0,
		Attributes = attributes,
		Stats = {
			Matches = 0,
			Wins = 0,
			Draws = 0,
			Losses = 0,
			Goals = 0,
			Assists = 0,
			Passes = 0,
			Tackles = 0,
			SkillMoves = 0,
			WinStreak = 0,
			BestWinStreak = 0,
		},
		Inventory = Catalog.DefaultInventory(),
		Equipped = Catalog.DefaultEquipped(),
		UnlockedAreas = { CommunityCourt = true },
		Challenges = {},
		Settings = { CameraSensitivity = 1, CameraMode = "Follow", ShowControls = true },
		FirstJoin = os.time(),
	}
end

-- Fill in any keys missing from older saves without touching existing values.
local function reconcile(data, template)
	for key, value in template do
		if data[key] == nil then
			if type(value) == "table" then
				data[key] = table.clone(value)
				reconcile(data[key], value)
			else
				data[key] = value
			end
		elseif type(value) == "table" and type(data[key]) == "table" then
			reconcile(data[key], value)
		end
	end
	return data
end

local function keyFor(player: Player): string
	return "Player_" .. player.UserId
end

local function retry(attempts: number, fn: () -> any): (boolean, any)
	local lastErr
	for i = 1, attempts do
		local ok, result = pcall(fn)
		if ok then
			return true, result
		end
		lastErr = result
		warn(string.format("[DataService] attempt %d/%d failed: %s", i, attempts, tostring(result)))
		if i < attempts then
			task.wait(math.min(2 ^ i, 16))
		end
	end
	return false, lastErr
end

-- Returns: status ("ok" | "locked" | "error"), data
local function tryLoad(player: Player)
	local result = nil
	local lockedByOther = false
	local ok, err = pcall(function()
		(store :: DataStore):UpdateAsync(keyFor(player), function(stored)
			stored = stored or {}
			local lock = stored.Lock
			if lock and lock.JobId ~= JOB_ID and (os.time() - (lock.Time or 0)) < Config.DataStore.SessionLockTimeout then
				lockedByOther = true
				return nil -- cancel the write, leave data untouched
			end
			lockedByOther = false
			stored.Lock = { JobId = JOB_ID, Time = os.time() }
			stored.Data = reconcile(stored.Data or makeTemplate(), makeTemplate())
			result = stored.Data
			return stored
		end)
	end)
	if not ok then
		return "error", err
	end
	if lockedByOther then
		return "locked", nil
	end
	return "ok", result
end

local function loadProfile(player: Player)
	for attempt = 1, Config.DataStore.LoadRetries do
		local status, data = tryLoad(player)
		if status == "ok" then
			return data
		end
		if not player.Parent then
			return nil
		end
		if status == "error" and RunService:IsStudio() then
			-- Usually "Studio access to API services" is off; do not stall testing.
			warn("[DataService] " .. tostring(data))
			return nil
		end
		warn(string.format("[DataService] load %s for %s (attempt %d)", status, player.Name, attempt))
		-- A locked session usually means the player just left another server that is
		-- still saving. Wait a bit longer for it to release.
		task.wait(if status == "locked" then 6 else math.min(2 ^ attempt, 12))
	end
	return nil
end

-- Writes the profile. release = true clears the session lock.
local function saveProfile(player: Player, release: boolean): boolean
	local profile = profiles[player]
	local m = meta[player]
	if not profile or not m or not m.CanSave or not store then
		return false
	end
	-- Avoid two overlapping saves for the same player.
	while m.Saving do
		task.wait(0.1)
	end
	m.Saving = true
	local lostLock = false
	local ok = retry(Config.DataStore.SaveRetries, function()
		(store :: DataStore):UpdateAsync(keyFor(player), function(stored)
			stored = stored or {}
			local lock = stored.Lock
			if lock and lock.JobId ~= JOB_ID then
				lostLock = true
				return nil
			end
			stored.Data = profile
			stored.SavedAt = os.time()
			stored.Lock = if release then nil else { JobId = JOB_ID, Time = os.time() }
			return stored
		end)
	end)
	m.Saving = false
	if lostLock then
		warn("[DataService] session lock lost for " .. player.Name .. "; data will no longer be saved here")
		m.CanSave = false
		if player.Parent and not release then
			player:Kick("Your data was opened on another server. Please rejoin.")
		end
		return false
	end
	if ok then
		m.Dirty = false
	end
	return ok
end

function DataService.Init()
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(Config.DataStoreName)
	end)
	if ok then
		store = result
	else
		warn("[DataService] DataStores unavailable, using temporary profiles: " .. tostring(result))
	end
end

local function onPlayerAdded(player: Player)
	local data = nil
	local canSave = false

	if store then
		data = loadProfile(player)
		if data then
			canSave = true
		elseif RunService:IsStudio() then
			warn("[DataService] Studio load failed, enable 'Studio Access to API Services' to test saving")
		else
			if player.Parent then
				player:Kick("Could not load your data. Please rejoin in a moment.")
			end
			return
		end
	end

	if not player.Parent then
		-- Left while loading: release the lock we may have taken.
		if canSave and store then
			profiles[player] = data
			meta[player] = { CanSave = true, Dirty = false, Saving = false }
			saveProfile(player, true)
			profiles[player] = nil
			meta[player] = nil
		end
		return
	end

	if not data then
		data = makeTemplate()
	end

	profiles[player] = data
	meta[player] = { CanSave = canSave, Dirty = false, Saving = false }
	player:SetAttribute("ProfileLoaded", true)

	for _, callback in loadedCallbacks do
		task.spawn(callback, player, data)
	end
end

local function onPlayerRemoving(player: Player)
	if not profiles[player] then
		return
	end
	for _, callback in releasingCallbacks do
		local ok, err = pcall(callback, player, profiles[player])
		if not ok then
			warn("[DataService] release callback error: " .. tostring(err))
		end
	end
	saveProfile(player, true)
	profiles[player] = nil
	meta[player] = nil
end

function DataService.Start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end

	-- Autosave loop, staggered so we do not hit DataStore limits in one burst.
	task.spawn(function()
		while not shuttingDown do
			task.wait(Config.DataStore.AutosaveInterval)
			for player in profiles do
				if shuttingDown then
					break
				end
				task.spawn(saveProfile, player, false)
				task.wait(1)
			end
		end
	end)

	game:BindToClose(function()
		shuttingDown = true
		if not store then
			return
		end
		local pending = 0
		for player in profiles do
			pending += 1
			task.spawn(function()
				saveProfile(player, true)
				pending -= 1
			end)
		end
		local deadline = os.clock() + 25
		while pending > 0 and os.clock() < deadline do
			task.wait(0.1)
		end
	end)
end

function DataService.GetProfile(player: Player)
	return profiles[player]
end

-- Waits up to `timeout` seconds for a profile to load.
function DataService.WaitForProfile(player: Player, timeout: number?)
	local deadline = os.clock() + (timeout or 30)
	while not profiles[player] and player.Parent and os.clock() < deadline do
		task.wait(0.1)
	end
	return profiles[player]
end

function DataService.MarkDirty(player: Player)
	local m = meta[player]
	if m then
		m.Dirty = true
	end
end

function DataService.OnProfileLoaded(callback: (Player, any) -> ())
	table.insert(loadedCallbacks, callback)
	for player, data in profiles do
		task.spawn(callback, player, data)
	end
end

-- Called just before a profile is saved and released (player leaving).
function DataService.OnProfileReleasing(callback: (Player, any) -> ())
	table.insert(releasingCallbacks, callback)
end

DataService._makeTemplate = makeTemplate
DataService._reconcile = reconcile

return DataService
