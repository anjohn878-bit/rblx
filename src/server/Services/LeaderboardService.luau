--[[
	LeaderboardService
	Global leaderboards (OrderedDataStore) shown on the boards in the plaza:
	  Richest Doctor (lifetime earnings) / Most Patients Treated / Highest
	  Hospital Level.
	Falls back to the players in the current server when DataStores are
	unavailable (e.g. Studio without API access).
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("Config"):WaitForChild("GameConfig"))
local Format = require(Shared:WaitForChild("Util"):WaitForChild("Format"))

local LeaderboardService = {}

type BoardDef = {
	Key: string,
	StoreName: string,
	Value: (data: any) -> number,
	Format: (value: number) -> string,
}

local BOARDS: { BoardDef } = {
	{
		Key = "Richest",
		StoreName = "WAAD_Richest_v1",
		Value = function(data)
			return math.floor(data.LifetimeEarned)
		end,
		Format = function(value)
			return Format.Money(value)
		end,
	},
	{
		Key = "Treated",
		StoreName = "WAAD_Treated_v1",
		Value = function(data)
			return math.floor(data.PatientsTreated)
		end,
		Format = function(value)
			return Format.Short(value)
		end,
	},
	{
		Key = "Level",
		StoreName = "WAAD_Level_v1",
		Value = function(data)
			return math.floor(data.HospitalLevel)
		end,
		Format = function(value)
			return "Lv " .. value
		end,
	},
}

local services: any = nil
local boards: any = nil
local stores: { [string]: OrderedDataStore } = {}
local nameCache: { [number]: string } = {}

local function nameFor(userId: number): string
	if nameCache[userId] then
		return nameCache[userId]
	end
	local player = Players:GetPlayerByUserId(userId)
	if player then
		nameCache[userId] = player.DisplayName
		return player.DisplayName
	end
	local ok, name = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	if ok and name then
		nameCache[userId] = name
		return name
	end
	return "Doctor #" .. userId
end

type Entry = { Name: string, Value: number }

local function render(def: BoardDef, entries: { Entry })
	local board = boards[def.Key]
	if not board then
		return
	end
	for i = 1, GameConfig.LeaderboardSize do
		local row = board.Rows:FindFirstChild("Row" .. i)
		if row then
			local entry = entries[i]
			local nameLabel = row:FindFirstChild("PlayerName") :: TextLabel
			local valueLabel = row:FindFirstChild("Value") :: TextLabel
			nameLabel.Text = if entry then entry.Name else "---"
			valueLabel.Text = if entry then def.Format(entry.Value) else ""
		end
	end
end

local function renderFromServer(def: BoardDef)
	local entries = {}
	for player, profile in services.DataService.GetAll() do
		table.insert(entries, { Name = player.DisplayName, Value = def.Value(profile.Data) })
	end
	table.sort(entries, function(a, b)
		return a.Value > b.Value
	end)
	render(def, entries)
end

local function pushPlayer(player: Player)
	local data = services.DataService.Get(player)
	local profile = services.DataService.GetProfile(player)
	if not data or not profile or not profile.CanSave then
		return
	end
	for _, def in BOARDS do
		local store = stores[def.Key]
		if store then
			pcall(function()
				store:SetAsync(tostring(player.UserId), def.Value(data))
			end)
		end
	end
end

local function refresh()
	for _, def in BOARDS do
		local store = stores[def.Key]
		local rendered = false
		if store then
			local ok, pages = pcall(function()
				return store:GetSortedAsync(false, GameConfig.LeaderboardSize)
			end)
			if ok and pages then
				local entries = {}
				for _, item in (pages :: DataStorePages):GetCurrentPage() do
					local userId = tonumber(item.key)
					if userId then
						table.insert(entries, { Name = nameFor(userId), Value = item.value })
					end
				end
				render(def, entries)
				rendered = true
			end
		end
		if not rendered then
			renderFromServer(def)
		end
	end
end

function LeaderboardService.Init(allServices: any, worldBoards: any)
	services = allServices
	boards = worldBoards
	if services.DataService.Enabled then
		for _, def in BOARDS do
			local ok, store = pcall(function()
				return DataStoreService:GetOrderedDataStore(def.StoreName)
			end)
			if ok then
				stores[def.Key] = store
			end
		end
	end

	task.spawn(function()
		task.wait(8)
		while true do
			if next(stores) then
				for player in services.DataService.GetAll() do
					pushPlayer(player)
					task.wait(0.2)
				end
			end
			refresh()
			task.wait(if next(stores) then GameConfig.LeaderboardUpdateInterval else 15)
		end
	end)
end

LeaderboardService.PushPlayer = pushPlayer

return LeaderboardService
