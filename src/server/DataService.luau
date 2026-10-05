--[[
	DataStore persistence. Thin wrapper: all rules about *what* is saved live in Profile.

	Safety rules:
	  * Loads/saves are retried, because DataStores fail transiently.
	  * If a load fails for good, the profile is flagged Temporary and is never saved,
	    so a hiccup can't overwrite a player's real progress with an empty profile.
	  * In Studio with API access disabled everything still works - nothing is saved.
]]

local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Profile = require(script.Parent.Profile)

local DataService = {}

local ATTEMPTS = 3
local studioWarningShown = false

local function keyFor(player: Player): string
	return "Player_" .. player.UserId
end

local function isStudioAccessError(err): boolean
	local text = string.lower(tostring(err))
	return string.find(text, "studio access to apis", 1, true) ~= nil or string.find(text, "studioaccesstoapisnotallowed", 1, true) ~= nil
end

-- Returns ok, result. Gives up immediately when retrying cannot help.
local function withRetries(fn: () -> any): (boolean, any)
	local lastError
	for attempt = 1, ATTEMPTS do
		local ok, result = pcall(fn)
		if ok then
			return true, result
		end
		lastError = result
		if isStudioAccessError(result) then
			break
		end
		if attempt < ATTEMPTS then
			task.wait(attempt * 1.5)
		end
	end
	return false, lastError
end

local function getStore()
	return DataStoreService:GetDataStore(Config.DataStoreName)
end

-- Always returns a usable profile; profile.Temporary tells you whether it can be saved.
function DataService.load(player: Player)
	local ok, data = withRetries(function()
		return getStore():GetAsync(keyFor(player))
	end)

	if ok then
		return Profile.fromSaved(data)
	end

	if isStudioAccessError(data) then
		if not studioWarningShown then
			studioWarningShown = true
			warn(
				"[DeliveryDriver] DataStore access is off, so progress will not be saved. Enable 'Studio Access to API Services' in Game Settings > Security to test saving."
			)
		end
	else
		warn(string.format("[DeliveryDriver] Could not load data for %s: %s", player.Name, tostring(data)))
	end

	local profile = Profile.new()
	profile.Temporary = true
	return profile
end

-- Returns true if the data was written.
function DataService.save(player: Player, profile): boolean
	if profile.Temporary then
		return false
	end
	local saved = Profile.toSaved(profile)
	local ok, err = withRetries(function()
		getStore():UpdateAsync(keyFor(player), function()
			return saved
		end)
	end)
	if not ok then
		warn(string.format("[DeliveryDriver] Could not save data for %s: %s", player.Name, tostring(err)))
	end
	return ok
end

return DataService
