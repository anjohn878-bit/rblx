--[[
	Owns every player's Profile for the session and mirrors it to the client.

	The client never receives profile tables. Instead the server publishes plain values as
	attributes on the Player instance, which replicate automatically (and are there for late
	joiners too):

	  Loaded, Cash, XP, RankIndex, RankName, RankXPStart, RankXPNext (-1 at max rank),
	  Deliveries, Streak, BestStreak, TotalEarned, Equipped, Owned (",Id,Id,")

	Order attributes (Order*) are published by OrderService.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Economy = require(ReplicatedStorage.Shared.Economy)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local DataService = require(script.Parent.DataService)
local Profile = require(script.Parent.Profile)

local PlayerService = {}

local profiles = {} -- [Player] = profile

function PlayerService.get(player: Player)
	return profiles[player]
end

function PlayerService.notify(player: Player, message: string, kind: string?)
	Remotes.Notify:FireClient(player, message, kind or "info")
end

local function ownedString(profile): string
	local ids = {}
	for id in profile.Owned do
		table.insert(ids, id)
	end
	table.sort(ids)
	return "," .. table.concat(ids, ",") .. ","
end

local function setLeaderstat(folder: Folder, name: string, className: string, value)
	local stat = folder:FindFirstChild(name)
	if not stat then
		stat = Instance.new(className)
		stat.Name = name
		stat.Parent = folder
	end
	stat.Value = value
end

-- Pushes the profile out to attributes + the leaderboard.
function PlayerService.sync(player: Player)
	local profile = profiles[player]
	if not profile then
		return
	end

	local rank = Economy.rankInfo(profile.XP)
	player:SetAttribute("Cash", profile.Cash)
	player:SetAttribute("XP", profile.XP)
	player:SetAttribute("RankIndex", rank.Index)
	player:SetAttribute("RankName", rank.Name)
	player:SetAttribute("RankXPStart", rank.XPStart)
	player:SetAttribute("RankXPNext", rank.XPNext or -1)
	player:SetAttribute("Deliveries", profile.Deliveries)
	player:SetAttribute("Streak", profile.Streak)
	player:SetAttribute("BestStreak", profile.BestStreak)
	player:SetAttribute("TotalEarned", profile.TotalEarned)
	player:SetAttribute("Equipped", profile.Equipped)
	player:SetAttribute("Owned", ownedString(profile))

	local stats = player:FindFirstChild("leaderstats")
	if stats then
		setLeaderstat(stats, "Cash", "IntValue", profile.Cash)
		setLeaderstat(stats, "Deliveries", "IntValue", profile.Deliveries)
		setLeaderstat(stats, "Rank", "StringValue", rank.Name)
	end
end

-- Gives money + XP, announces a rank-up, and returns Profile.award's summary.
function PlayerService.award(player: Player, cash: number, xp: number)
	local profile = profiles[player]
	if not profile then
		return nil
	end
	local summary = Profile.award(profile, cash, xp)
	PlayerService.sync(player)
	if summary.RankedUp then
		PlayerService.notify(player, "RANK UP! You are now a " .. Config.Ranks[summary.NewRank].Name .. ".", "success")
	end
	return summary
end

local function onPlayerAdded(player: Player)
	player:SetAttribute("Loaded", false)

	local stats = Instance.new("Folder")
	stats.Name = "leaderstats"
	stats.Parent = player

	local profile = DataService.load(player)
	if not player.Parent then
		return -- left while loading
	end
	profiles[player] = profile
	PlayerService.sync(player)
	player:SetAttribute("Loaded", true)

	if profile.Temporary then
		PlayerService.notify(player, "Your save couldn't be loaded, so progress won't be saved this session.", "warn")
	end
end

local function onPlayerRemoving(player: Player)
	local profile = profiles[player]
	if profile then
		DataService.save(player, profile)
		profiles[player] = nil
	end
end

function PlayerService.start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end

	-- Periodic autosave, so a crash loses at most a minute of progress.
	task.spawn(function()
		while true do
			task.wait(Config.AutosaveInterval)
			for player, profile in profiles do
				task.spawn(DataService.save, player, profile)
			end
		end
	end)

	-- Server shutting down: save everyone and wait for the writes to finish.
	game:BindToClose(function()
		local pending = 0
		for player, profile in profiles do
			pending += 1
			task.spawn(function()
				DataService.save(player, profile)
				pending -= 1
			end)
		end
		while pending > 0 do
			task.wait(0.1)
		end
	end)
end

return PlayerService
