--[[
	LeaderboardService
	Fills the "Top Skaters" board in the lobby with the all-time best skaters
	from an OrderedDataStore. When DataStores aren't available (Studio without
	API access) it shows the players in the server instead.
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Format = require(Shared.Format)

local DataService = require(script.Parent.DataService)

local LeaderboardService = {}

local ROWS = 10
local nameCache = {}

local orderedStore
do
	local ok, result = pcall(function()
		return DataStoreService:GetOrderedDataStore(Config.LeaderboardStoreName)
	end)
	if ok then
		orderedStore = result
	end
end

local function getBoardList()
	local map = workspace:FindFirstChild("Map")
	local board = map and map:FindFirstChild("LeaderboardBoard", true)
	local gui = board and board:FindFirstChild("Leaderboard")
	return gui and gui:FindFirstChild("List")
end

local function nameFor(userId)
	if nameCache[userId] then
		return nameCache[userId]
	end
	local player = Players:GetPlayerByUserId(userId)
	if player then
		nameCache[userId] = player.DisplayName
		return player.DisplayName
	end
	local ok, name = pcall(Players.GetNameFromUserIdAsync, Players, userId)
	if ok and name then
		nameCache[userId] = name
		return name
	end
	return "Skater " .. userId
end

local function render(entries)
	local list = getBoardList()
	if not list then
		return
	end
	for rank = 1, ROWS do
		local row = list:FindFirstChild("Row" .. rank)
		if row then
			local entry = entries[rank]
			row.PlayerName.Text = if entry then entry.name else "—"
			row.Value.Text = if entry then Format.abbreviate(entry.value) .. " ❄" else ""
		end
	end
end

local function submitScores()
	if not orderedStore then
		return
	end
	for _, player in Players:GetPlayers() do
		local profile = DataService.get(player)
		if profile then
			pcall(orderedStore.SetAsync, orderedStore, tostring(player.UserId), math.floor(profile.LifetimeSnowflakes))
		end
	end
end

local function fetchGlobal()
	if not orderedStore then
		return nil
	end
	local ok, pages = pcall(orderedStore.GetSortedAsync, orderedStore, false, ROWS)
	if not ok then
		return nil
	end
	local entries = {}
	for _, item in pages:GetCurrentPage() do
		local userId = tonumber(item.key)
		if userId then
			table.insert(entries, { name = nameFor(userId), value = item.value })
		end
	end
	return entries
end

local function fetchLocal()
	local entries = {}
	for _, player in Players:GetPlayers() do
		local profile = DataService.get(player)
		if profile then
			table.insert(entries, { name = player.DisplayName, value = profile.LifetimeSnowflakes })
		end
	end
	table.sort(entries, function(a, b)
		return a.value > b.value
	end)
	return entries
end

function LeaderboardService.refresh()
	submitScores()
	render(fetchGlobal() or fetchLocal())
end

function LeaderboardService.init()
	task.spawn(function()
		task.wait(5)
		while true do
			LeaderboardService.refresh()
			task.wait(Config.LeaderboardRefreshInterval)
		end
	end)
end

return LeaderboardService
