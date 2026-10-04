--[[
	ProgressionService
	The only code allowed to change XP, level, Kicks (currency), reputation,
	attributes and lifetime stats. Also replicates the profile to its owner and
	keeps the Roblox player-list leaderstats in sync.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Progression = require(Shared.Progression)
local Remotes = require(Shared.Remotes)

local DataService = require(script.Parent.DataService)

local ProgressionService = {}

local pendingSync: { [Player]: boolean } = {}
local profileUpdated

local function updateLeaderstats(player: Player, profile)
	local stats = player:FindFirstChild("leaderstats")
	if not stats then
		stats = Instance.new("Folder")
		stats.Name = "leaderstats"
		stats.Parent = player
		for _, name in { "Level", "Wins", "Goals" } do
			local v = Instance.new("IntValue")
			v.Name = name
			v.Parent = stats
		end
	end
	stats.Level.Value = profile.Level
	stats.Wins.Value = profile.Stats.Wins
	stats.Goals.Value = profile.Stats.Goals

	-- Attributes other systems (and other clients) read cheaply
	local _, tierName = Progression.GetReputationTier(profile.Reputation)
	player:SetAttribute("Level", profile.Level)
	player:SetAttribute("Title", Progression.GetTitle(profile.Level))
	player:SetAttribute("RepTier", tierName)
end

-- Batches profile replication to once per frame per player.
function ProgressionService.Sync(player: Player)
	if pendingSync[player] then
		return
	end
	pendingSync[player] = true
	task.defer(function()
		pendingSync[player] = nil
		local profile = DataService.GetProfile(player)
		if profile and player.Parent then
			updateLeaderstats(player, profile)
			profileUpdated:FireClient(player, profile)
		end
	end)
end

local function notify(player: Player, text: string, kind: string?)
	Remotes.Get("Notify"):FireClient(player, text, kind or "info")
end

function ProgressionService.AddXP(player: Player, amount: number)
	local profile = DataService.GetProfile(player)
	if not profile or amount <= 0 then
		return
	end
	local oldTitle = Progression.GetTitle(profile.Level)
	local level, xp, gained = Progression.ApplyXP(profile.Level, profile.XP, math.floor(amount))
	profile.Level = level
	profile.XP = xp
	if gained > 0 then
		profile.AttributePoints += gained * Config.Attributes.PointsPerLevel
		profile.Kicks += gained * Config.Rewards.LevelUpKicks
		notify(player, string.format("LEVEL UP! You reached level %d", level), "levelup")
		local newTitle = Progression.GetTitle(level)
		if newTitle ~= oldTitle then
			notify(player, "New title unlocked: " .. newTitle, "levelup")
		end
	end
	DataService.MarkDirty(player)
	ProgressionService.Sync(player)
end

function ProgressionService.AddKicks(player: Player, amount: number)
	local profile = DataService.GetProfile(player)
	if not profile or amount <= 0 then
		return
	end
	profile.Kicks += math.floor(amount)
	DataService.MarkDirty(player)
	ProgressionService.Sync(player)
end

-- Returns true if the player could afford it (and the Kicks were removed).
function ProgressionService.SpendKicks(player: Player, amount: number): boolean
	local profile = DataService.GetProfile(player)
	if not profile or amount < 0 or profile.Kicks < amount then
		return false
	end
	profile.Kicks -= amount
	DataService.MarkDirty(player)
	ProgressionService.Sync(player)
	return true
end

function ProgressionService.AddReputation(player: Player, amount: number)
	local profile = DataService.GetProfile(player)
	if not profile or amount <= 0 then
		return
	end
	local oldIndex = Progression.GetReputationTier(profile.Reputation)
	profile.Reputation += math.floor(amount)
	local newIndex, newName = Progression.GetReputationTier(profile.Reputation)
	if newIndex > oldIndex then
		notify(player, "Reputation up! The Grounds now know you as: " .. newName, "levelup")
	end
	DataService.MarkDirty(player)
	ProgressionService.Sync(player)
end

-- statDeltas: { Goals = 1, ... } added to lifetime stats
function ProgressionService.AddStats(player: Player, statDeltas: { [string]: number })
	local profile = DataService.GetProfile(player)
	if not profile then
		return
	end
	for key, delta in statDeltas do
		if type(profile.Stats[key]) == "number" then
			profile.Stats[key] += delta
		end
	end
	DataService.MarkDirty(player)
	ProgressionService.Sync(player)
end

-- Applies the end of match result for one player and returns the reward summary.
function ProgressionService.ApplyMatchResult(player: Player, matchStats, result: string)
	local profile = DataService.GetProfile(player)
	if not profile then
		return nil
	end
	local before = { Level = profile.Level, XP = profile.XP, Reputation = profile.Reputation }
	local rewards = Progression.ComputeMatchRewards(matchStats, result)

	local s = profile.Stats
	s.Matches += 1
	s.Goals += matchStats.Goals or 0
	s.Assists += matchStats.Assists or 0
	s.Passes += matchStats.Passes or 0
	s.Tackles += matchStats.Tackles or 0
	s.SkillMoves += matchStats.SkillMoves or 0
	if result == "Win" then
		s.Wins += 1
		s.WinStreak += 1
		s.BestWinStreak = math.max(s.BestWinStreak, s.WinStreak)
	elseif result == "Draw" then
		s.Draws += 1
		s.WinStreak = 0
	else
		s.Losses += 1
		s.WinStreak = 0
	end

	ProgressionService.AddKicks(player, rewards.Kicks)
	ProgressionService.AddReputation(player, rewards.Reputation)
	ProgressionService.AddXP(player, rewards.XP)

	rewards.Before = before
	rewards.After = { Level = profile.Level, XP = profile.XP, Reputation = profile.Reputation }
	return rewards
end

function ProgressionService.GetAttribute(player: Player, name: string): number
	local profile = DataService.GetProfile(player)
	if profile and profile.Attributes[name] then
		return profile.Attributes[name]
	end
	return Config.Attributes.Start
end

local VALID_ATTRIBUTE = {}
for _, name in Config.Attributes.List do
	VALID_ATTRIBUTE[name] = true
end

function ProgressionService.Init()
	profileUpdated = Remotes.Get("ProfileUpdated")
end

function ProgressionService.Start()
	DataService.OnProfileLoaded(function(player)
		ProgressionService.Sync(player)
	end)

	Remotes.Get("GetProfile").OnServerInvoke = function(player)
		return DataService.WaitForProfile(player, 20)
	end

	Remotes.Get("SpendAttribute").OnServerInvoke = function(player, name)
		if type(name) ~= "string" or not VALID_ATTRIBUTE[name] then
			return false, "Unknown attribute"
		end
		local profile = DataService.GetProfile(player)
		if not profile then
			return false, "Profile not loaded"
		end
		if profile.AttributePoints <= 0 then
			return false, "No attribute points. Level up to earn more!"
		end
		if profile.Attributes[name] >= Config.Attributes.Max then
			return false, "Already maxed"
		end
		profile.AttributePoints -= 1
		profile.Attributes[name] += 1
		DataService.MarkDirty(player)
		ProgressionService.Sync(player)
		return true, name .. " +1"
	end

	Remotes.Get("UpdateSettings").OnServerEvent:Connect(function(player, settings)
		local profile = DataService.GetProfile(player)
		if not profile or type(settings) ~= "table" then
			return
		end
		local sens = settings.CameraSensitivity
		if type(sens) == "number" and sens == sens then
			profile.Settings.CameraSensitivity = math.clamp(sens, 0.2, 3)
		end
		if settings.CameraMode == "Follow" or settings.CameraMode == "Broadcast" then
			profile.Settings.CameraMode = settings.CameraMode
		end
		if type(settings.ShowControls) == "boolean" then
			profile.Settings.ShowControls = settings.ShowControls
		end
		DataService.MarkDirty(player)
	end)

	Players.PlayerRemoving:Connect(function(player)
		pendingSync[player] = nil
	end)
end

return ProgressionService
