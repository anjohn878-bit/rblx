-- Owns each player's session: saved progress (cash, deliveries, vehicles), the parcels they
-- are carrying, leaderstats, and the state snapshot sent to their client.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local PlayerData = {}

export type SavedData = {
	Cash: number,
	Deliveries: number,
	Earned: number,
	Owned: { [string]: boolean },
	Equipped: string,
}

export type Job = {
	Id: number,
	AddressId: number,
	Name: string?,
	Address: string,
	Position: Vector3,
	Kind: string,
	Reward: number,
	Deadline: number,
	LoadedAt: number,
}

export type Session = {
	Player: Player,
	Data: SavedData,
	CanSave: boolean,
	Jobs: { Job },
	LastSpawn: number,
	Stats: { Cash: IntValue, Deliveries: IntValue, Rank: StringValue },
}

local sessions: { [Player]: Session } = {}
local changedCallbacks: { (Session) -> () } = {}
local depotPosition = Vector3.zero

local store: DataStore? = nil
do
	local ok, result = pcall(DataStoreService.GetDataStore, DataStoreService, Config.DataStoreName)
	if ok then
		store = result
	else
		warn("[PlayerData] DataStores unavailable, progress will not be saved:", result)
	end
end

local function defaultData(): SavedData
	return {
		Cash = Config.Economy.StartingCash,
		Deliveries = 0,
		Earned = 0,
		Owned = { [Config.Vehicles[1].Id] = true },
		Equipped = Config.Vehicles[1].Id,
	}
end

-- Fill in anything missing from older saves and drop vehicles that no longer exist.
local function reconcile(saved: any): SavedData
	local data = defaultData()
	if type(saved) ~= "table" then
		return data
	end
	if type(saved.Cash) == "number" then
		data.Cash = math.max(0, math.floor(saved.Cash))
	end
	if type(saved.Deliveries) == "number" then
		data.Deliveries = math.max(0, math.floor(saved.Deliveries))
	end
	if type(saved.Earned) == "number" then
		data.Earned = math.max(0, math.floor(saved.Earned))
	end
	if type(saved.Owned) == "table" then
		for id, owned in saved.Owned do
			if owned == true and Config.getVehicle(id) then
				data.Owned[id] = true
			end
		end
	end
	if type(saved.Equipped) == "string" and data.Owned[saved.Equipped] then
		data.Equipped = saved.Equipped
	end
	return data
end

local function keyFor(player: Player): string
	return "player_" .. player.UserId
end

local function load(player: Player): (SavedData, boolean)
	if not store then
		return defaultData(), false
	end
	for attempt = 1, 3 do
		local ok, result = pcall(function()
			return (store :: DataStore):GetAsync(keyFor(player))
		end)
		if ok then
			return reconcile(result), true
		end
		warn(string.format("[PlayerData] Load attempt %d failed for %s: %s", attempt, player.Name, tostring(result)))
		if RunService:IsStudio() then
			-- Usually "Studio access to API services" is switched off; retrying won't help.
			break
		end
		task.wait(attempt)
	end
	-- Never overwrite a real save with defaults just because loading failed.
	return defaultData(), false
end

local function save(session: Session)
	if not store or not session.CanSave then
		return
	end
	local snapshot = table.clone(session.Data)
	snapshot.Owned = table.clone(session.Data.Owned)
	local ok, err = pcall(function()
		(store :: DataStore):UpdateAsync(keyFor(session.Player), function()
			return snapshot
		end)
	end)
	if not ok then
		warn("[PlayerData] Save failed for " .. session.Player.Name .. ": " .. tostring(err))
	end
end

function PlayerData.rankIndex(session: Session): number
	return Config.getRankIndex(session.Data.Deliveries)
end

function PlayerData.capacity(session: Session): number
	local vehicle = Config.getVehicle(session.Data.Equipped)
	return if vehicle then vehicle.Capacity else 1
end

function PlayerData.buildState(session: Session)
	local data = session.Data
	local rankIndex = PlayerData.rankIndex(session)
	local rank = Config.Ranks[rankIndex]
	local nextRank = Config.Ranks[rankIndex + 1]

	local jobs = {}
	for _, job in session.Jobs do
		table.insert(jobs, {
			Id = job.Id,
			Name = job.Name,
			Address = job.Address,
			Position = job.Position,
			Kind = job.Kind,
			Reward = job.Reward,
			Deadline = job.Deadline,
		})
	end

	return {
		Cash = data.Cash,
		Deliveries = data.Deliveries,
		RankIndex = rankIndex,
		RankName = rank.Name,
		RankFloor = rank.Deliveries,
		NextRankName = if nextRank then nextRank.Name else nil,
		NextRankAt = if nextRank then nextRank.Deliveries else nil,
		Owned = table.clone(data.Owned),
		Equipped = data.Equipped,
		Capacity = PlayerData.capacity(session),
		Jobs = jobs,
		Depot = depotPosition,
	}
end

-- Push the latest state to the client and refresh leaderstats.
function PlayerData.changed(session: Session)
	local data = session.Data
	session.Stats.Cash.Value = data.Cash
	session.Stats.Deliveries.Value = data.Deliveries
	session.Stats.Rank.Value = Config.Ranks[PlayerData.rankIndex(session)].Name
	for _, callback in changedCallbacks do
		task.spawn(callback, session)
	end
	Remotes.StateChanged:FireClient(session.Player, PlayerData.buildState(session))
end

function PlayerData.onChanged(callback: (Session) -> ())
	table.insert(changedCallbacks, callback)
end

function PlayerData.get(player: Player): Session?
	return sessions[player]
end

function PlayerData.waitFor(player: Player, timeout: number): Session?
	local started = os.clock()
	while not sessions[player] and player.Parent and os.clock() - started < timeout do
		task.wait(0.1)
	end
	return sessions[player]
end

function PlayerData.all(): { [Player]: Session }
	return sessions
end

function PlayerData.notify(player: Player, text: string, kind: string?)
	Remotes.Notify:FireClient(player, text, kind or "info")
end

local function makeStats(player: Player)
	local folder = Instance.new("Folder")
	folder.Name = "leaderstats"
	local cash = Instance.new("IntValue")
	cash.Name = "Cash"
	cash.Parent = folder
	local deliveries = Instance.new("IntValue")
	deliveries.Name = "Deliveries"
	deliveries.Parent = folder
	local rank = Instance.new("StringValue")
	rank.Name = "Rank"
	rank.Parent = folder
	folder.Parent = player
	return { Cash = cash, Deliveries = deliveries, Rank = rank }
end

local function onPlayerAdded(player: Player)
	local data, canSave = load(player)
	if not player.Parent then
		return
	end
	local session: Session = {
		Player = player,
		Data = data,
		CanSave = canSave,
		Jobs = {},
		LastSpawn = -math.huge,
		Stats = makeStats(player),
	}
	sessions[player] = session
	PlayerData.changed(session)
	if not canSave then
		if RunService:IsStudio() then
			PlayerData.notify(player, "Saving is off in Studio. Enable API Services to test it.", "info")
		else
			PlayerData.notify(player, "Couldn't load your save. Progress this session won't be saved.", "error")
		end
	end
end

function PlayerData.init(depot: Vector3)
	depotPosition = depot

	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end

	Players.PlayerRemoving:Connect(function(player)
		local session = sessions[player]
		if session then
			sessions[player] = nil
			save(session)
		end
	end)

	Remotes.GetState.OnServerInvoke = function(player)
		local session = PlayerData.waitFor(player, 20)
		return if session then PlayerData.buildState(session) else nil
	end

	task.spawn(function()
		while true do
			task.wait(Config.AutosaveSeconds)
			for _, session in sessions do
				task.spawn(save, session)
			end
		end
	end)

	game:BindToClose(function()
		if not store then
			return
		end
		local pending = 0
		for _, session in sessions do
			pending += 1
			task.spawn(function()
				save(session)
				pending -= 1
			end)
		end
		local started = os.clock()
		while pending > 0 and os.clock() - started < 25 do
			task.wait(0.2)
		end
	end)
end

return PlayerData
