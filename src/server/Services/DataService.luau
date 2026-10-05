--[[
	DataService
	Loads / saves player progress with DataStoreService.

	* Retries with exponential backoff on every DataStore call
	* Light session lock so two servers never overwrite each other
	* Autosave every GameConfig.AutosaveInterval seconds + save on leave
	* game:BindToClose saves everyone before shutdown
	* If loading fails the player can still play, but saving is disabled
	  for that session so their real save is never overwritten with defaults
	* Works in Studio without API access (in-memory only, with a warning)
]]

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local GameConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("GameConfig"))

local DATA_VERSION = 1
local MAX_ATTEMPTS = 5
local LOCK_WAIT_ATTEMPTS = 5

local TEMPLATE = {
	Version = DATA_VERSION,
	Money = GameConfig.StartingMoney,
	LifetimeEarned = 0,
	HospitalLevel = 1,
	Rooms = {},
	Doctors = {},
	Improvements = {},
	DoctorXP = 0,
	PatientsTreated = 0,
	ManualTreated = 0,
	AutoTreated = 0,
	BestCombo = 0,
	RareTreated = {},
	TutorialDone = false,
	PlayTime = 0,
}

export type Profile = {
	Player: Player,
	Data: any,
	CanSave: boolean,
	Key: string,
	JoinedAt: number,
	Saving: boolean,
}

local DataService = {}
DataService.Enabled = true

local store: DataStore? = nil
local profiles: { [Player]: Profile } = {}
local sessionId = if game.JobId ~= "" then game.JobId else ("studio-" .. HttpService:GenerateGUID(false))

local function deepCopy<T>(value: T): T
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for k, v in value :: any do
		copy[deepCopy(k)] = deepCopy(v)
	end
	return copy :: any
end

-- Fill in keys that were added to the template after the save was created.
local function reconcile(data: any, template: any)
	for key, value in template do
		if data[key] == nil then
			data[key] = deepCopy(value)
		elseif type(value) == "table" and type(data[key]) == "table" and next(value) ~= nil then
			reconcile(data[key], value)
		end
	end
end

local function sanitize(data: any)
	data.HospitalLevel = math.max(1, math.floor(tonumber(data.HospitalLevel) or 1))
	data.Money = math.max(0, tonumber(data.Money) or 0)
	if type(data.Doctors) ~= "table" then
		data.Doctors = {}
	end
	if type(data.Rooms) ~= "table" then
		data.Rooms = {}
	end
	if type(data.Improvements) ~= "table" then
		data.Improvements = {}
	end
end

local function withRetries<T>(label: string, callback: () -> T): (boolean, T | string)
	local lastError: any = nil
	for attempt = 1, MAX_ATTEMPTS do
		local ok, result = pcall(callback)
		if ok then
			return true, result
		end
		lastError = result
		warn(string.format("[DataService] %s failed (attempt %d/%d): %s", label, attempt, MAX_ATTEMPTS, tostring(result)))
		if attempt < MAX_ATTEMPTS then
			task.wait(2 ^ attempt * 0.5)
		end
	end
	return false, tostring(lastError)
end

function DataService.Init()
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(GameConfig.DataStoreName)
	end)
	if ok then
		store = result
		-- Probe once so Studio without API access is detected early.
		local probeOk, probeError = pcall(function()
			return (result :: DataStore):GetAsync("__probe")
		end)
		if not probeOk then
			local message = tostring(probeError)
			if RunService:IsStudio() then
				warn("[DataService] DataStores unavailable in Studio (" .. message .. "). Progress will NOT be saved. Enable 'Studio Access to API Services' in Game Settings > Security to test saving.")
				DataService.Enabled = false
			else
				warn("[DataService] DataStore probe failed: " .. message)
			end
		end
	else
		warn("[DataService] Could not open DataStore: " .. tostring(result) .. " - progress will not be saved.")
		DataService.Enabled = false
	end

	task.spawn(function()
		while true do
			task.wait(GameConfig.AutosaveInterval)
			for player in profiles do
				task.spawn(DataService.Save, player, false)
				task.wait(0.5)
			end
		end
	end)

	game:BindToClose(function()
		local pending = 0
		for player in profiles do
			pending += 1
			task.spawn(function()
				DataService.Save(player, true)
				pending -= 1
			end)
		end
		local started = os.clock()
		while pending > 0 and os.clock() - started < 25 do
			task.wait(0.2)
		end
	end)
end

local function keyFor(player: Player): string
	return "Player_" .. player.UserId
end

-- Loads (or creates) the player's data. Returns nil if the player left.
function DataService.Load(player: Player): Profile?
	local key = keyFor(player)
	local profile: Profile = {
		Player = player,
		Data = deepCopy(TEMPLATE),
		CanSave = false,
		Key = key,
		JoinedAt = os.clock(),
		Saving = false,
	}

	if DataService.Enabled and store then
		local dataStore = store :: DataStore
		local loaded = nil
		local success = false
		for lockAttempt = 1, LOCK_WAIT_ATTEMPTS do
			local locked = false
			local ok, err = withRetries("Load " .. key, function()
				return dataStore:UpdateAsync(key, function(old)
					locked = false
					local data = old
					if type(data) ~= "table" then
						data = deepCopy(TEMPLATE)
					end
					local lock = data._Session
					local stale = type(lock) ~= "table" or (os.time() - (tonumber(lock.Time) or 0)) > GameConfig.SessionLockTimeout
					if not stale and lock.Id ~= sessionId and lockAttempt < LOCK_WAIT_ATTEMPTS then
						locked = true
						return nil -- another server still owns this save; don't write
					end
					data._Session = { Id = sessionId, Time = os.time() }
					loaded = data
					return data
				end)
			end)
			if not ok then
				warn("[DataService] Giving up loading data for " .. player.Name .. ": " .. tostring(err))
				break
			end
			if not locked then
				success = true
				break
			end
			-- The previous server is probably still saving; give it a moment.
			task.wait(5)
			if not player.Parent then
				return nil
			end
		end

		if success and loaded then
			local data = loaded :: any
			reconcile(data, TEMPLATE)
			sanitize(data)
			profile.Data = data
			profile.CanSave = true
		else
			warn("[DataService] Using temporary data for " .. player.Name .. " (saving disabled this session)")
		end
	end

	if not player.Parent then
		-- Left while loading: release the session lock we may have taken.
		if profile.CanSave then
			profiles[player] = profile
			DataService.Release(player)
		end
		return nil
	end
	profiles[player] = profile
	return profile
end

function DataService.Get(player: Player): any
	local profile = profiles[player]
	return profile and profile.Data
end

function DataService.GetProfile(player: Player): Profile?
	return profiles[player]
end

function DataService.Save(player: Player, release: boolean)
	local profile = profiles[player]
	if not profile then
		return
	end
	profile.Data.PlayTime = (profile.Data.PlayTime or 0) + (os.clock() - profile.JoinedAt)
	profile.JoinedAt = os.clock()
	if not (DataService.Enabled and store and profile.CanSave) then
		return
	end
	if profile.Saving and not release then
		return
	end
	profile.Saving = true
	local snapshot = deepCopy(profile.Data)
	local dataStore = store :: DataStore
	withRetries("Save " .. profile.Key, function()
		return dataStore:UpdateAsync(profile.Key, function(old)
			if type(old) == "table" and type(old._Session) == "table" and old._Session.Id ~= sessionId then
				-- Another server took over this save; never overwrite it.
				return nil
			end
			snapshot.Version = DATA_VERSION
			snapshot._Session = if release then nil else { Id = sessionId, Time = os.time() }
			return snapshot
		end)
	end)
	profile.Saving = false
end

function DataService.Release(player: Player)
	DataService.Save(player, true)
	profiles[player] = nil
end

function DataService.IsLoaded(player: Player): boolean
	return profiles[player] ~= nil
end

function DataService.GetAll(): { [Player]: Profile }
	return profiles
end

return DataService
