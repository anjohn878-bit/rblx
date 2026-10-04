--[[
	MatchmakingService
	One queue per pitch. Players join from the queue pad (ProximityPrompt) or the
	PLAY button. Once a second it checks every idle pitch:
	  * enough humans for a full game -> start immediately
	  * fewer humans, but the oldest has waited Config.Match.BotFillDelay -> start
	    and fill the empty slots with bots
	Teams are balanced with a snake draft on skill rating.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Progression = require(Shared.Progression)
local Remotes = require(Shared.Remotes)

local DataService = require(script.Parent.DataService)
local MapBuilder = require(script.Parent.MapBuilder)
local MatchService = require(script.Parent.MatchService)

local MatchmakingService = {}

local queues: { [string]: { { Player: Player, JoinedAt: number } } } = {}
local notifyRemote

local function findEntry(queue, player: Player): number?
	for i, entry in queue do
		if entry.Player == player then
			return i
		end
	end
	return nil
end

local function publish(pitchId: string)
	local queue = queues[pitchId]
	local match = MatchService.GetMatch(pitchId)
	local needed = Config.Match.TeamSize * 2
	if match then
		match.StateObject:SetAttribute("QueueCount", #queue)
		match.StateObject:SetAttribute("QueueNeeded", needed)
		local oldest = queue[1]
		match.StateObject:SetAttribute("BotFillAt", if oldest and Config.Match.FillWithBots then oldest.JoinedAt + Config.Match.BotFillDelay else 0)
	end
	local model = MapBuilder.GetPitchModel(pitchId)
	local pad = model and model:FindFirstChild("QueuePad")
	local label = pad and pad:FindFirstChild("QueueBoard") and pad.QueueBoard:FindFirstChild("Label")
	if label then
		local stateText = if match and match:IsBusy() then "MATCH IN PROGRESS" else "WAITING FOR PLAYERS"
		label.Text = string.format("%s · %dv%d\nQUEUE %d/%d\n%s", match and match.Pitch.DisplayName or pitchId, Config.Match.TeamSize, Config.Match.TeamSize, #queue, needed, stateText)
	end
end

function MatchmakingService.GetQueuedPitch(player: Player): string?
	for pitchId, queue in queues do
		if findEntry(queue, player) then
			return pitchId
		end
	end
	return nil
end

function MatchmakingService.Leave(player: Player)
	for pitchId, queue in queues do
		local idx = findEntry(queue, player)
		if idx then
			table.remove(queue, idx)
			player:SetAttribute("QueuedPitch", nil)
			publish(pitchId)
		end
	end
end

function MatchmakingService.Join(player: Player, pitchId: string?): (boolean, string)
	pitchId = pitchId or Config.Pitches[1].Id
	local queue = queues[pitchId :: string]
	if not queue then
		return false, "Unknown pitch"
	end
	if player:GetAttribute("MatchId") then
		return false, "You are already in a match"
	end
	if not DataService.GetProfile(player) then
		return false, "Still loading your profile"
	end
	if findEntry(queue, player) then
		return true, "Already queued"
	end
	MatchmakingService.Leave(player)
	table.insert(queue, { Player = player, JoinedAt = os.time() })
	player:SetAttribute("QueuedPitch", pitchId)
	publish(pitchId :: string)
	return true, "Joined the queue"
end

-- Snake draft by skill so both teams end up with similar strength.
function MatchmakingService.BalanceTeams(players: { Player })
	local rated = {}
	for _, player in players do
		local profile = DataService.GetProfile(player)
		table.insert(rated, { Player = player, Rating = profile and Progression.SkillRating(profile) or 0 })
	end
	table.sort(rated, function(a, b)
		return a.Rating > b.Rating
	end)
	local teams = { A = {}, B = {} }
	local pattern = { "A", "B", "B", "A" }
	for i, entry in rated do
		local team = pattern[((i - 1) % 4) + 1]
		table.insert(teams[team], entry.Player)
	end
	-- With odd numbers keep team sizes within one of each other
	while #teams.A > #teams.B + 1 do
		table.insert(teams.B, table.remove(teams.A))
	end
	while #teams.B > #teams.A + 1 do
		table.insert(teams.A, table.remove(teams.B))
	end
	return teams
end

local function tryStart(pitchId: string)
	local match = MatchService.GetMatch(pitchId)
	local queue = queues[pitchId]
	if not match or match:IsBusy() then
		return
	end
	-- Drop anyone who left or is otherwise unavailable
	for i = #queue, 1, -1 do
		local p = queue[i].Player
		if not p.Parent or p:GetAttribute("MatchId") or not p.Character then
			table.remove(queue, i)
			if p.Parent then
				p:SetAttribute("QueuedPitch", nil)
			end
		end
	end

	local full = Config.Match.TeamSize * 2
	local ready = #queue >= full
	if not ready and Config.Match.FillWithBots and #queue >= Config.Match.MinHumansToStart then
		ready = os.time() - queue[1].JoinedAt >= Config.Match.BotFillDelay
	end
	if not ready then
		publish(pitchId)
		return
	end

	local chosen = {}
	for _ = 1, math.min(full, #queue) do
		local entry = table.remove(queue, 1)
		entry.Player:SetAttribute("QueuedPitch", nil)
		table.insert(chosen, entry.Player)
	end
	local teams = MatchmakingService.BalanceTeams(chosen)
	MatchService.StartMatch(pitchId, teams)
	publish(pitchId)
end

function MatchmakingService.Init()
	notifyRemote = Remotes.Get("Notify")
	for _, pitch in Config.Pitches do
		queues[pitch.Id] = {}
	end
end

function MatchmakingService.Start()
	Remotes.Get("RequestQueue").OnServerEvent:Connect(function(player, join)
		if join == true then
			local _, message = MatchmakingService.Join(player, nil)
			notifyRemote:FireClient(player, message, "info")
		else
			MatchmakingService.Leave(player)
			notifyRemote:FireClient(player, "Left the queue", "info")
		end
	end)

	-- Queue pads
	for _, pitch in Config.Pitches do
		local model = MapBuilder.GetPitchModel(pitch.Id)
		local prompt = model and model:FindFirstChild("QueuePad") and model.QueuePad:FindFirstChild("QueuePrompt")
		if prompt then
			prompt.Triggered:Connect(function(player)
				if MatchmakingService.GetQueuedPitch(player) == pitch.Id then
					MatchmakingService.Leave(player)
					notifyRemote:FireClient(player, "Left the queue", "info")
				else
					local _, message = MatchmakingService.Join(player, pitch.Id)
					notifyRemote:FireClient(player, message, "info")
				end
			end)
		end
		publish(pitch.Id)
	end

	Players.PlayerRemoving:Connect(MatchmakingService.Leave)

	task.spawn(function()
		while true do
			task.wait(1)
			for pitchId in queues do
				local ok, err = pcall(tryStart, pitchId)
				if not ok then
					warn("[Matchmaking] " .. tostring(err))
				end
			end
		end
	end)
end

return MatchmakingService
