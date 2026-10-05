--!strict
-- Player profiles: loading, sanitising, saving, and syncing to the client.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Birds = require(Shared:WaitForChild("Birds"))
local Clock = require(Shared:WaitForChild("Clock"))
local Config = require(Shared:WaitForChild("Config"))
local Growth = require(Shared:WaitForChild("Growth"))
local Remotes = require(Shared:WaitForChild("Remotes")).get()
local Seeds = require(Shared:WaitForChild("Seeds"))
local Types = require(Shared:WaitForChild("Types"))

local DataService = {}

export type PlantRecord = { seedId: string, plantedAt: number }

export type Profile = {
	version: number,
	feathers: number,
	seeds: { [string]: number },
	birds: { [string]: number },
	plots: number,
	plants: { [string]: PlantRecord }, -- keyed by plot index as a string
	totalVisits: number,
}

local PROFILE_VERSION = 1

local store: DataStore? = nil
local storeWarned = false
local profiles: { [Player]: Profile } = {}
local ephemeral: { [Player]: boolean } = {} -- Studio without API access: play, but never save
local dirty: { [Player]: boolean } = {}
local pushPending: { [Player]: boolean } = {}

local function getStore(): DataStore?
	if store then
		return store
	end
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(Config.DATASTORE_NAME)
	end)
	if ok then
		store = result
	end
	return store
end

local function keyFor(player: Player): string
	return "Player_" .. player.UserId
end

local function defaultProfile(): Profile
	local seeds: { [string]: number } = {}
	for id, count in Config.START_SEEDS do
		seeds[id] = count
	end
	return {
		version = PROFILE_VERSION,
		feathers = Config.START_FEATHERS,
		seeds = seeds,
		birds = {},
		plots = Config.START_PLOTS,
		plants = {},
		totalVisits = 0,
	}
end

local function isCount(v: any): boolean
	return type(v) == "number" and v == v and v >= 0 and v < 1e15
end

-- Never trust stored data: rebuild a valid profile from whatever was loaded.
local function sanitize(raw: any): Profile
	local profile = defaultProfile()
	if type(raw) ~= "table" then
		return profile
	end

	if isCount(raw.feathers) then
		profile.feathers = math.floor(raw.feathers)
	end
	if isCount(raw.totalVisits) then
		profile.totalVisits = math.floor(raw.totalVisits)
	end
	if isCount(raw.plots) then
		profile.plots = math.clamp(math.floor(raw.plots), Config.START_PLOTS, Config.MAX_PLOTS)
	end

	if type(raw.seeds) == "table" then
		profile.seeds = {}
		for id, count in raw.seeds do
			if Seeds.isValid(id) and isCount(count) and count >= 1 then
				profile.seeds[id] = math.floor(count)
			end
		end
	end
	if type(raw.birds) == "table" then
		for id, count in raw.birds do
			if type(id) == "string" and Birds.get(id) and isCount(count) and count >= 1 then
				profile.birds[id] = math.floor(count)
			end
		end
	end
	if type(raw.plants) == "table" then
		local now = Clock.now()
		for key, record in raw.plants do
			local index = tonumber(key)
			if
				index
				and index == math.floor(index)
				and index >= 1
				and index <= profile.plots
				and type(record) == "table"
				and Seeds.isValid(record.seedId)
				and type(record.plantedAt) == "number"
			then
				profile.plants[tostring(index)] = {
					seedId = record.seedId,
					plantedAt = math.min(record.plantedAt, now), -- no planting in the future
				}
			end
		end
	end
	return profile
end

function DataService.snapshot(profile: Profile): Types.Snapshot
	local seeds, birds = {}, {}
	for id, count in profile.seeds do
		seeds[id] = count
	end
	for id, count in profile.birds do
		birds[id] = count
	end
	return {
		feathers = profile.feathers,
		seeds = seeds,
		birds = birds,
		plots = profile.plots,
		nextPlotPrice = Growth.plotPrice(profile.plots),
		totalVisits = profile.totalVisits,
	}
end

local function updateLeaderstats(player: Player, profile: Profile)
	local stats = player:FindFirstChild("leaderstats")
	if not stats then
		return
	end
	local feathers = stats:FindFirstChild("Feathers") :: IntValue?
	if feathers then
		feathers.Value = profile.feathers
	end
	local species = stats:FindFirstChild("Birds") :: IntValue?
	if species then
		local count = 0
		for _ in profile.birds do
			count += 1
		end
		species.Value = count
	end
end

-- Call after changing a profile: marks it for saving and syncs the client
-- (batched, so many changes in one frame send one update).
function DataService.push(player: Player)
	local profile = profiles[player]
	if not profile then
		return
	end
	dirty[player] = true
	updateLeaderstats(player, profile)
	if pushPending[player] then
		return
	end
	pushPending[player] = true
	task.defer(function()
		pushPending[player] = nil
		local current = profiles[player]
		if current and player.Parent == Players then
			Remotes.StateUpdate:FireClient(player, DataService.snapshot(current))
		end
	end)
end

-- Soft-lock protection: a player with no plants, no seeds and too few feathers
-- to buy the cheapest seed would be stuck forever, so give them one free seed.
function DataService.rescue(player: Player): boolean
	local profile = profiles[player]
	if not profile or next(profile.plants) ~= nil then
		return false
	end
	for _, count in profile.seeds do
		if count > 0 then
			return false
		end
	end
	local cheapest = Seeds.list[1]
	if profile.feathers >= cheapest.price then
		return false
	end
	profile.seeds[cheapest.id] = 1
	DataService.push(player)
	return true
end

function DataService.get(player: Player): Profile?
	return profiles[player]
end

-- Loads (yields). Returns nil if the player was kicked because loading failed.
function DataService.load(player: Player): Profile?
	local raw: any = nil
	local ok = true
	local ds = getStore()

	if ds then
		for attempt = 1, 3 do
			local success, result = pcall(function()
				return ds:GetAsync(keyFor(player))
			end)
			if success then
				raw, ok = result, true
				break
			end
			ok = false
			if attempt < 3 then
				task.wait(1.5 * attempt)
			else
				warn(`[DataService] Could not load {player.Name}: {result}`)
			end
		end
	else
		ok = false
	end

	if not ok then
		if RunService:IsStudio() then
			-- Studio without "Enable Studio Access to API Services": play with fresh data.
			ephemeral[player] = true
			if not storeWarned then
				storeWarned = true
				warn(
					"[DataService] DataStore unavailable - progress will NOT be saved in this session. "
						.. "Enable Game Settings > Security > 'Enable Studio Access to API Services' to test saving."
				)
			end
		else
			-- Never let a player continue on default data: saving would overwrite their real save.
			player:Kick("We couldn't load your garden. Please rejoin in a moment.")
			return nil
		end
	end

	local profile = sanitize(raw)
	profiles[player] = profile
	return profile
end

-- Creates the leaderboard entries (call once the profile is loaded).
function DataService.attach(player: Player)
	local profile = profiles[player]
	if not profile or player:FindFirstChild("leaderstats") then
		return
	end
	local stats = Instance.new("Folder")
	stats.Name = "leaderstats"
	local feathers = Instance.new("IntValue")
	feathers.Name = "Feathers"
	feathers.Parent = stats
	local species = Instance.new("IntValue")
	species.Name = "Birds"
	species.Parent = stats
	stats.Parent = player
	updateLeaderstats(player, profile)
end

function DataService.save(player: Player): boolean
	local profile = profiles[player]
	local ds = getStore()
	if not profile or not ds or ephemeral[player] then
		return false
	end
	for attempt = 1, 3 do
		local success, err = pcall(function()
			ds:UpdateAsync(keyFor(player), function()
				return profile
			end)
		end)
		if success then
			dirty[player] = nil
			return true
		end
		if attempt < 3 then
			task.wait(1.5 * attempt)
		else
			warn(`[DataService] Could not save {player.Name}: {err}`)
		end
	end
	return false
end

function DataService.release(player: Player)
	profiles[player] = nil
	ephemeral[player] = nil
	dirty[player] = nil
	pushPending[player] = nil
end

-- Saves everyone in parallel (used when the server shuts down).
function DataService.saveAll()
	local pending = 0
	for player in profiles do
		pending += 1
		task.spawn(function()
			DataService.save(player)
			pending -= 1
		end)
	end
	local deadline = os.clock() + 25
	while pending > 0 and os.clock() < deadline do
		task.wait(0.1)
	end
end

function DataService.startAutosave()
	task.spawn(function()
		while true do
			task.wait(Config.AUTOSAVE_INTERVAL)
			for player in profiles do
				if dirty[player] then
					task.spawn(DataService.save, player)
				end
			end
		end
	end)
end

return DataService
