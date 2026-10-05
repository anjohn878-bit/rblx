-- Loads and saves each player's progress (cash, built items, rebirths).

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local shared = ReplicatedStorage:WaitForChild("DressStore")
local Config = require(shared:WaitForChild("Config"))
local Util = require(shared:WaitForChild("Util"))

export type SaveData = {
	cash: number,
	owned: { [string]: boolean },
	rebirths: number,
	sold: number,
}

export type Profile = {
	player: Player,
	data: SaveData,
	canSave: boolean,
	cashValue: IntValue,
	rebirthsValue: IntValue,
}

local DataManager = {}

local profiles: { [Player]: Profile } = {}
local dataStore: DataStore? = nil
local warned = false

local function disableSaving(reason: string)
	dataStore = nil
	if not warned then
		warned = true
		warn(
			"[DressStore] Saving is turned off: "
				.. reason
				.. "\nTo save progress, publish the game and turn on 'Enable Studio Access to API Services' in Game Settings > Security."
		)
	end
end

do
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(Config.DATASTORE_NAME)
	end)
	if ok then
		dataStore = result
	else
		disableSaving(tostring(result))
	end
end

local function keyFor(player: Player): string
	return "player_" .. player.UserId
end

local function defaultData(): SaveData
	return {
		cash = Config.STARTING_CASH,
		owned = {},
		rebirths = 0,
		sold = 0,
	}
end

local function isAccessError(message: string): boolean
	local lower = string.lower(message)
	return string.find(lower, "studio", 1, true) ~= nil
		or string.find(lower, "publish", 1, true) ~= nil
		or string.find(lower, "403", 1, true) ~= nil
end

local function readSaved(saved: any, data: SaveData)
	if type(saved) ~= "table" then
		return
	end
	data.cash = math.max(0, math.floor(tonumber(saved.cash) or Config.STARTING_CASH))
	data.rebirths = math.max(0, math.floor(tonumber(saved.rebirths) or 0))
	data.sold = math.max(0, math.floor(tonumber(saved.sold) or 0))
	if type(saved.owned) == "table" then
		for _, id in saved.owned do
			if type(id) == "string" and Config.ItemById[id] then
				data.owned[id] = true
			end
		end
	end
end

local function serialize(data: SaveData)
	local owned = {}
	for _, item in Config.Items do
		if data.owned[item.id] then
			table.insert(owned, item.id)
		end
	end
	return {
		version = 1,
		cash = data.cash,
		owned = owned,
		rebirths = data.rebirths,
		sold = data.sold,
	}
end

local function refreshStats(profile: Profile)
	profile.cashValue.Value = profile.data.cash
	profile.rebirthsValue.Value = profile.data.rebirths
	profile.player:SetAttribute("Rebirths", profile.data.rebirths)
	profile.player:SetAttribute("Multiplier", DataManager.multiplier(profile.player))
	profile.player:SetAttribute("Sold", profile.data.sold)
end

-- Loads (or creates) the player's data. Yields while talking to the DataStore.
function DataManager.load(player: Player): Profile
	local data = defaultData()
	local canSave = false

	local store = dataStore
	if store then
		local success, result = false, nil
		for attempt = 1, 3 do
			success, result = pcall(function()
				return store:GetAsync(keyFor(player))
			end)
			if success then
				break
			end
			if isAccessError(tostring(result)) then
				disableSaving(tostring(result))
				break
			end
			warn("[DressStore] Loading data failed (attempt " .. attempt .. "):", result)
			task.wait(1.5)
		end
		if success then
			readSaved(result, data)
			canSave = true
		elseif dataStore then
			warn("[DressStore] Could not load " .. player.Name .. "'s data. Their progress will not be saved this time.")
		end
	end

	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	local cashValue = Instance.new("IntValue")
	cashValue.Name = "Cash"
	cashValue.Parent = leaderstats
	local rebirthsValue = Instance.new("IntValue")
	rebirthsValue.Name = "Rebirths"
	rebirthsValue.Parent = leaderstats
	leaderstats.Parent = player

	local profile: Profile = {
		player = player,
		data = data,
		canSave = canSave,
		cashValue = cashValue,
		rebirthsValue = rebirthsValue,
	}
	profiles[player] = profile
	refreshStats(profile)
	return profile
end

function DataManager.get(player: Player): Profile?
	return profiles[player]
end

function DataManager.getCash(player: Player): number
	local profile = profiles[player]
	return if profile then profile.data.cash else 0
end

function DataManager.addCash(player: Player, amount: number)
	local profile = profiles[player]
	if not profile then
		return
	end
	profile.data.cash = math.max(0, math.floor(profile.data.cash + amount))
	refreshStats(profile)
end

-- Takes money if the player has enough. Returns true when paid.
function DataManager.spend(player: Player, amount: number): boolean
	local profile = profiles[player]
	if not profile or profile.data.cash < amount then
		return false
	end
	DataManager.addCash(player, -amount)
	return true
end

function DataManager.addSold(player: Player, count: number)
	local profile = profiles[player]
	if profile then
		profile.data.sold += count
		refreshStats(profile)
	end
end

function DataManager.multiplier(player: Player): number
	local profile = profiles[player]
	if not profile then
		return 1
	end
	return Util.multiplierFor(profile.data.rebirths, Config.REBIRTH_BONUS)
end

function DataManager.isOwned(player: Player, itemId: string): boolean
	local profile = profiles[player]
	return profile ~= nil and profile.data.owned[itemId] == true
end

function DataManager.setOwned(player: Player, itemId: string)
	local profile = profiles[player]
	if profile then
		profile.data.owned[itemId] = true
	end
end

-- Starts over with an empty store and a permanent money bonus.
function DataManager.rebirth(player: Player)
	local profile = profiles[player]
	if not profile then
		return
	end
	profile.data.rebirths += 1
	profile.data.cash = Config.STARTING_CASH
	profile.data.owned = {}
	refreshStats(profile)
end

function DataManager.save(player: Player)
	local profile = profiles[player]
	local store = dataStore
	if not profile or not profile.canSave or not store then
		return
	end
	local payload = serialize(profile.data)
	local ok, err = pcall(function()
		store:UpdateAsync(keyFor(player), function()
			return payload
		end)
	end)
	if not ok then
		warn("[DressStore] Saving " .. player.Name .. "'s data failed:", err)
	end
end

-- Saves and forgets the player (when they leave).
function DataManager.release(player: Player)
	DataManager.save(player)
	profiles[player] = nil
end

task.spawn(function()
	while true do
		task.wait(Config.AUTOSAVE_INTERVAL)
		for player in profiles do
			task.spawn(DataManager.save, player)
		end
	end
end)

game:BindToClose(function()
	local pending = 0
	for _, player in Players:GetPlayers() do
		if profiles[player] then
			pending += 1
			task.spawn(function()
				DataManager.save(player)
				pending -= 1
			end)
		end
	end
	local started = os.clock()
	while pending > 0 and os.clock() - started < 25 do
		task.wait(0.1)
	end
end)

return DataManager
