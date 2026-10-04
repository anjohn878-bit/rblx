--[[
	MatchService
	Runs small-sided matches on each pitch.

	Flow (one coroutine per match):
	  MatchFound (rosters shown) -> Kickoff countdown -> Playing
	    -> Goal (celebration) -> Kickoff -> Playing ... -> Ended (results, rewards)
	    -> players returned to the Grounds -> Idle

	Replication: ReplicatedStorage.Matches.<PitchId> (a Configuration) carries
	attributes every client can read: State, ScoreA, ScoreB, EndsAt, TimeLeft,
	QueueCount, QueueNeeded. Players in a match get attributes MatchId, Team
	and AttackDir. One-off moments (match found, goal, results) go through the
	MatchEvent remote.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)

local Actors = require(script.Parent.Actors)
local BallService = require(script.Parent.BallService)
local BotService = require(script.Parent.BotService)
local InventoryService = require(script.Parent.InventoryService)
local ProgressionService = require(script.Parent.ProgressionService)

local MatchService = {}

local PASS_KINDS = { Pass = true, Through = true, Lob = true }

local matches: { [string]: any } = {}
local matchEvent

local Match = {}
Match.__index = Match

local function otherTeam(team: string): string
	return if team == "A" then "B" else "A"
end

local function newStatLine()
	return { Goals = 0, Assists = 0, Passes = 0, Tackles = 0, SkillMoves = 0, Shots = 0 }
end

function Match.new(pitch)
	local self = setmetatable({}, Match)
	self.Pitch = pitch
	self.Id = pitch.Id
	self.State = "Idle"
	self.Teams = { A = {}, B = {} }
	self.TeamOf = {} -- actor -> "A"/"B"
	self.Stats = {} -- actor -> stat line
	self.Score = { A = 0, B = 0 }
	self.TimeLeft = Config.Match.DurationSeconds
	self.Ball = nil
	self.GoalConnection = nil
	self.PendingGoal = nil
	self.Aborted = false

	local folder = ReplicatedStorage:FindFirstChild("Matches")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Matches"
		folder.Parent = ReplicatedStorage
	end
	local state = Instance.new("Configuration")
	state.Name = pitch.Id
	state.Parent = folder
	self.StateObject = state
	state:SetAttribute("PitchName", pitch.DisplayName)
	state:SetAttribute("TeamSize", Config.Match.TeamSize)
	state:SetAttribute("CenterX", pitch.Center.X)
	state:SetAttribute("CenterZ", pitch.Center.Z)
	self:SetState("Idle")
	self:PublishScore()
	return self
end

function Match:SetState(state: string)
	self.State = state
	self.StateObject:SetAttribute("State", state)
end

function Match:PublishScore()
	self.StateObject:SetAttribute("ScoreA", self.Score.A)
	self.StateObject:SetAttribute("ScoreB", self.Score.B)
end

function Match:PublishTimer(running: boolean)
	self.StateObject:SetAttribute("TimeLeft", math.max(0, self.TimeLeft))
	self.StateObject:SetAttribute("EndsAt", if running then Workspace:GetServerTimeNow() + self.TimeLeft else 0)
end

function Match:IsBusy(): boolean
	return self.State ~= "Idle"
end

function Match:GetAllActors()
	local list = {}
	for _, team in { "A", "B" } do
		for _, actor in self.Teams[team] do
			table.insert(list, actor)
		end
	end
	return list
end

function Match:GetHumans()
	local list = {}
	for _, actor in self:GetAllActors() do
		if not Actors.IsBot(actor) then
			table.insert(list, actor)
		end
	end
	return list
end

function Match:GetTeam(actor): string?
	return self.TeamOf[actor]
end

function Match:GetMates(actor)
	local team = self.TeamOf[actor]
	return if team then self.Teams[team] else {}
end

-- Goal that `team` attacks. Team A attacks +X.
function Match:GetAttackGoal(team: string): Vector3
	local p = self.Pitch
	local dir = if team == "A" then 1 else -1
	return Vector3.new(p.Center.X + dir * p.Length / 2, p.SurfaceY + p.GoalHeight / 2, p.Center.Z)
end

function Match:FireToHumans(kind: string, payload)
	for _, player in self:GetHumans() do
		matchEvent:FireClient(player, kind, payload)
	end
end

-- Broadcast to everyone (spectators get goal banners etc.)
function Match:FireAll(kind: string, payload)
	payload.PitchId = self.Id
	matchEvent:FireAllClients(kind, payload)
end

-------------------------------------------------------------------------------
-- Positions
-------------------------------------------------------------------------------
local FORMATIONS = {
	[1] = { Vector3.new(-10, 0, 0) },
	[2] = { Vector3.new(-8, 0, -6), Vector3.new(-24, 0, 8) },
	[3] = { Vector3.new(-7, 0, 0), Vector3.new(-24, 0, -14), Vector3.new(-24, 0, 14) },
	[4] = { Vector3.new(-7, 0, -6), Vector3.new(-7, 0, 6), Vector3.new(-26, 0, -14), Vector3.new(-26, 0, 14) },
	[5] = { Vector3.new(-7, 0, 0), Vector3.new(-18, 0, -16), Vector3.new(-18, 0, 16), Vector3.new(-32, 0, -8), Vector3.new(-32, 0, 8) },
}

function Match:GetSpawnCFrame(team: string, index: number, kickoffTeam: string?): CFrame
	local p = self.Pitch
	local count = math.max(#self.Teams[team], 1)
	local formation = FORMATIONS[math.min(count, 5)]
	local offset = formation[((index - 1) % #formation) + 1]
	if kickoffTeam == team and index == 1 then
		offset = Vector3.new(-2.5, 0, 0) -- take the kickoff
	end
	local dir = if team == "A" then 1 else -1
	local pos = Vector3.new(p.Center.X + offset.X * dir, p.SurfaceY + 3.2, p.Center.Z + offset.Z * dir)
	return CFrame.lookAt(pos, pos + Vector3.new(dir, 0, 0))
end

local function setAnchored(actor, anchored: boolean)
	local root = Actors.GetRoot(actor)
	if root then
		root.Anchored = anchored
	end
end

function Match:PlaceActors(kickoffTeam: string?, anchored: boolean)
	for _, team in { "A", "B" } do
		for i, actor in self.Teams[team] do
			local character = Actors.GetCharacter(actor)
			if character then
				local root = Actors.GetRoot(actor)
				if root then
					root.AssemblyLinearVelocity = Vector3.zero
				end
				character:PivotTo(self:GetSpawnCFrame(team, i, kickoffTeam))
				setAnchored(actor, anchored)
				if Actors.IsBot(actor) then
					local humanoid = Actors.GetHumanoid(actor)
					if humanoid and root then
						humanoid:MoveTo(root.Position)
					end
				end
			end
		end
	end
end

function Match:SetAllAnchored(anchored: boolean)
	for _, actor in self:GetAllActors() do
		setAnchored(actor, anchored)
	end
end

-------------------------------------------------------------------------------
-- Ball and goal detection
-------------------------------------------------------------------------------
function Match:CreateBall()
	local p = self.Pitch
	local spawnPos = Vector3.new(p.Center.X, p.SurfaceY + Config.Ball.Size / 2 + 0.1, p.Center.Z)
	self.Ball = BallService.CreateBall({
		SpawnPosition = spawnPos,
		SurfaceY = p.SurfaceY,
		Bounds = {
			Center = p.Center,
			HalfSize = Vector3.new(p.Length / 2 + p.GoalDepth + 6, p.ColliderHeight + 10, p.Width / 2 + 6),
		},
		Handlers = {
			GetActors = function()
				if self.State == "Playing" then
					return self:GetAllActors()
				end
				return {}
			end,
			GetMates = function(actor)
				return self:GetMates(actor)
			end,
			GetAttackGoal = function(actor)
				local team = self.TeamOf[actor]
				if not team then
					return nil, nil
				end
				return self:GetAttackGoal(team), p.GoalWidth
			end,
			OnPossession = function(_, actor, previous)
				if previous and PASS_KINDS[previous.Kind] and previous.Actor ~= actor
					and self.TeamOf[previous.Actor] == self.TeamOf[actor] and self.Stats[previous.Actor] then
					self.Stats[previous.Actor].Passes += 1
				end
			end,
			OnKick = function(_, actor, kind)
				if kind == "Shot" and self.Stats[actor] then
					self.Stats[actor].Shots += 1
				end
			end,
			OnTackle = function(_, tackler, _victim, success)
				if success and self.Stats[tackler] then
					self.Stats[tackler].Tackles += 1
				end
			end,
			OnSkillMove = function(_, actor)
				if self.Stats[actor] then
					self.Stats[actor].SkillMoves += 1
				end
			end,
			OnOutOfBounds = function(ball)
				-- Should not happen inside the cage, but never lose the ball.
				BallService.Reset(ball, spawnPos)
			end,
		},
	})
	self.SpawnPosition = spawnPos
end

-- Returns "A"/"B" for the team that scored, or nil.
function Match:CheckGoal(): string?
	local p = self.Pitch
	local pos = self.Ball.Part.Position
	local r = Config.Ball.Size / 2
	local rel = pos - p.Center
	if math.abs(rel.Z) > p.GoalWidth / 2 or pos.Y > p.SurfaceY + p.GoalHeight then
		return nil
	end
	local line = p.Length / 2 + r
	if rel.X > line then
		return "A" -- in the +X goal that B defends
	elseif rel.X < -line then
		return "B"
	end
	return nil
end

function Match:ResolveGoalCredit(scoringTeam: string)
	local touches = self.Ball.Touches
	local last = touches[#touches]
	local scorer = last and last.Actor
	if not scorer or self.TeamOf[scorer] ~= scoringTeam then
		return nil, nil, true -- own goal (or no touch)
	end
	local i = #touches
	while i >= 1 and touches[i].Actor == scorer do
		i -= 1
	end
	local prev = touches[i]
	local assister = nil
	if prev and PASS_KINDS[prev.Kind] and self.TeamOf[prev.Actor] == scoringTeam and os.clock() - prev.Time < 15 then
		assister = prev.Actor
	end
	return scorer, assister, false
end

-------------------------------------------------------------------------------
-- Roster management
-------------------------------------------------------------------------------
function Match:AddActor(actor, team: string)
	table.insert(self.Teams[team], actor)
	self.TeamOf[actor] = team
	self.Stats[actor] = self.Stats[actor] or newStatLine()
	if Actors.IsBot(actor) then
		BotService.AssignMatch(actor, self, team)
	else
		local player = actor :: Player
		player:SetAttribute("MatchId", self.Id)
		player:SetAttribute("Team", team)
		player:SetAttribute("AttackDir", if team == "A" then 1 else -1)
		InventoryService.SetTeamColor(player, Config.Teams[team].Color)
	end
end

local function clearPlayerMatchAttributes(player: Player)
	player:SetAttribute("MatchId", nil)
	player:SetAttribute("Team", nil)
	player:SetAttribute("AttackDir", nil)
	player:SetAttribute("HasBall", false)
end

local function returnToGrounds(player: Player)
	clearPlayerMatchAttributes(player)
	BallService.ReleaseActor(player)
	InventoryService.SetTeamColor(player, nil)
	local character = player.Character
	if character then
		local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			root.Anchored = false
		end
		local offset = Vector3.new(math.random(-8, 8), 3, math.random(-6, 6))
		character:PivotTo(CFrame.new(Config.Hub.Spawn + offset))
	end
end

-- A player left or disconnected mid-match.
function Match:RemoveActor(actor)
	local team = self.TeamOf[actor]
	if not team then
		return
	end
	local idx = table.find(self.Teams[team], actor)
	if idx then
		table.remove(self.Teams[team], idx)
	end
	self.TeamOf[actor] = nil
	BallService.ReleaseActor(actor)
	if not Actors.IsBot(actor) and (actor :: Player).Parent then
		returnToGrounds(actor)
	end

	if #self:GetHumans() == 0 then
		self.Aborted = true
		return
	end
	if Config.Match.FillWithBots and self.State ~= "Ended" then
		local bot = BotService.CreateBot(team)
		self:AddActor(bot, team)
		if self.Ball then
			bot.Model:PivotTo(self:GetSpawnCFrame(team, #self.Teams[team], nil))
			setAnchored(bot, self.State == "Kickoff")
		end
	end
end

-------------------------------------------------------------------------------
-- Match flow
-------------------------------------------------------------------------------
local function waitOrAbort(self, seconds: number): boolean
	local deadline = os.clock() + seconds
	while os.clock() < deadline do
		if self.Aborted then
			return false
		end
		task.wait(0.1)
	end
	return not self.Aborted
end

function Match:Kickoff(kickoffTeam: string?)
	BallService.Reset(self.Ball, self.SpawnPosition)
	BallService.SetFrozen(self.Ball, true)
	self:PlaceActors(kickoffTeam, true)
	self:SetState("Kickoff")
	self:PublishTimer(false)
	local countdown = Config.Match.KickoffCountdown
	self.StateObject:SetAttribute("CountdownEnds", Workspace:GetServerTimeNow() + countdown)
	self:FireAll("Countdown", { Seconds = countdown })
	if not waitOrAbort(self, countdown) then
		return false
	end
	self:SetAllAnchored(false)
	BallService.SetFrozen(self.Ball, false)
	self:SetState("Playing")
	self:PublishTimer(true)
	return true
end

function Match:PlayUntilStop(): string
	-- Returns "Goal", "Time", "Abort"
	local result = nil
	local last = os.clock()
	self.GoalConnection = RunService.Heartbeat:Connect(function()
		if result or self.State ~= "Playing" then
			return
		end
		local now = os.clock()
		self.TimeLeft -= now - last
		last = now
		if self.Aborted then
			result = "Abort"
			return
		end
		local scoringTeam = self:CheckGoal()
		if scoringTeam then
			self.PendingGoal = scoringTeam
			result = "Goal"
		elseif self.TimeLeft <= 0 then
			result = "Time"
		end
	end)
	while not result do
		task.wait()
	end
	self.GoalConnection:Disconnect()
	self.GoalConnection = nil
	return result
end

function Match:HandleGoal()
	local team = self.PendingGoal
	self.PendingGoal = nil
	self.Score[team] += 1
	self:PublishScore()
	local scorer, assister, ownGoal = self:ResolveGoalCredit(team)
	if scorer and self.Stats[scorer] then
		self.Stats[scorer].Goals += 1
	end
	if assister and self.Stats[assister] then
		self.Stats[assister].Assists += 1
	end
	BallService.SetFrozen(self.Ball, true)
	self:SetState("Goal")
	self:PublishTimer(false)
	self:FireAll("Goal", {
		Team = team,
		Scorer = scorer and Actors.GetName(scorer) or nil,
		ScorerId = scorer and Actors.GetId(scorer) or nil,
		Assister = assister and Actors.GetName(assister) or nil,
		OwnGoal = ownGoal,
		ScoreA = self.Score.A,
		ScoreB = self.Score.B,
		BallPosition = self.Ball.Part.Position,
	})
	return waitOrAbort(self, Config.Match.GoalCelebrationSeconds)
end

function Match:BuildResults()
	local list = {}
	for _, actor in self:GetAllActors() do
		local s = self.Stats[actor] or newStatLine()
		table.insert(list, {
			Name = Actors.GetName(actor),
			Id = Actors.GetId(actor),
			Team = self.TeamOf[actor],
			IsBot = Actors.IsBot(actor),
			Goals = s.Goals,
			Assists = s.Assists,
			Passes = s.Passes,
			Tackles = s.Tackles,
			Shots = s.Shots,
			Rating = s.Goals * 3 + s.Assists * 2 + s.Tackles + s.Passes * 0.3 + s.Shots * 0.2,
		})
	end
	table.sort(list, function(a, b)
		return a.Rating > b.Rating
	end)
	return list
end

function Match:Finish(awardRewards: boolean)
	self:SetState("Ended")
	self:PublishTimer(false)
	if self.Ball then
		BallService.SetFrozen(self.Ball, true)
	end
	self:SetAllAnchored(false)

	local results = self:BuildResults()
	local winner = if self.Score.A > self.Score.B then "A" elseif self.Score.B > self.Score.A then "B" else nil
	for _, player in self:GetHumans() do
		local team = self.TeamOf[player]
		local outcome = if winner == nil then "Draw" elseif winner == team then "Win" else "Loss"
		local rewards = nil
		if awardRewards then
			rewards = ProgressionService.ApplyMatchResult(player, self.Stats[player] or newStatLine(), outcome)
		end
		matchEvent:FireClient(player, "Results", {
			PitchId = self.Id,
			Outcome = outcome,
			MyTeam = team,
			ScoreA = self.Score.A,
			ScoreB = self.Score.B,
			MyStats = self.Stats[player],
			Rewards = rewards,
			Players = results,
			Aborted = not awardRewards,
		})
	end
end

function Match:Cleanup()
	for _, actor in self:GetAllActors() do
		if Actors.IsBot(actor) then
			BotService.DestroyBot(actor)
		elseif (actor :: Player).Parent then
			returnToGrounds(actor)
		end
	end
	if self.Ball then
		BallService.DestroyBall(self.Ball)
		self.Ball = nil
	end
	self.Teams = { A = {}, B = {} }
	self.TeamOf = {}
	self.Stats = {}
	self.Score = { A = 0, B = 0 }
	self.TimeLeft = Config.Match.DurationSeconds
	self.Aborted = false
	self:PublishScore()
	self:PublishTimer(false)
	self:SetState("Idle")
end

function Match:Run()
	local rosters = { A = {}, B = {} }
	for _, team in { "A", "B" } do
		for _, actor in self.Teams[team] do
			table.insert(rosters[team], { Name = Actors.GetName(actor), Id = Actors.GetId(actor), IsBot = Actors.IsBot(actor) })
		end
	end
	self:SetState("MatchFound")
	self:FireToHumans("MatchFound", { PitchId = self.Id, PitchName = self.Pitch.DisplayName, Teams = rosters })

	local completed = false
	if waitOrAbort(self, Config.Match.MatchFoundSeconds) then
		self:CreateBall()
		local kickoffTeam = if math.random() < 0.5 then "A" else "B"
		local running = self:Kickoff(kickoffTeam)
		while running do
			local stop = self:PlayUntilStop()
			if stop == "Goal" then
				local scored = self.PendingGoal
				if not self:HandleGoal() then
					break
				end
				if math.abs(self.Score.A - self.Score.B) >= Config.Match.MercyGoalDifference then
					completed = true
					break
				end
				running = self:Kickoff(otherTeam(scored))
			elseif stop == "Time" then
				completed = true
				break
			else
				break
			end
		end
	end

	self:Finish(completed)
	-- Give players a moment to see the final whistle, then send them back.
	task.wait(3)
	self:Cleanup()
end

-------------------------------------------------------------------------------
-- Public API
-------------------------------------------------------------------------------
function MatchService.GetMatch(pitchId: string)
	return matches[pitchId]
end

function MatchService.GetMatches()
	return matches
end

function MatchService.GetMatchForActor(actor)
	for _, match in matches do
		if match.TeamOf[actor] then
			return match
		end
	end
	return nil
end

-- teams = { A = { actors }, B = { actors } }; humans only, bots are added here.
function MatchService.StartMatch(pitchId: string, teams)
	local match = matches[pitchId]
	assert(match and not match:IsBusy(), "Pitch is busy")
	for _, team in { "A", "B" } do
		for _, actor in teams[team] do
			match:AddActor(actor, team)
		end
		if Config.Match.FillWithBots then
			while #match.Teams[team] < Config.Match.TeamSize do
				match:AddActor(BotService.CreateBot(team), team)
			end
		end
	end
	match.TimeLeft = Config.Match.DurationSeconds
	task.spawn(function()
		local ok, err = pcall(match.Run, match)
		if not ok then
			warn("[MatchService] match crashed: " .. tostring(err))
			pcall(match.Cleanup, match)
		end
	end)
	return match
end

function MatchService.Init()
	matchEvent = Remotes.Get("MatchEvent")
	for _, pitch in Config.Pitches do
		matches[pitch.Id] = Match.new(pitch)
	end
end

function MatchService.Start()
	Players.PlayerRemoving:Connect(function(player)
		local match = MatchService.GetMatchForActor(player)
		if match then
			match:RemoveActor(player)
		end
	end)

	-- Respawned mid-match: put the player back on the pitch in their team kit.
	local function onPlayer(player: Player)
		player.CharacterAdded:Connect(function(character)
			local match = MatchService.GetMatchForActor(player)
			if not match then
				-- Safety net: never leave a non-match player stuck on the cage roof
				-- (e.g. if they spawned before the map finished building).
				task.wait(0.5)
				local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
				if root and root.Position.Y > 30 and not player:GetAttribute("MatchId") then
					character:PivotTo(CFrame.new(Config.Hub.Spawn + Vector3.new(0, 3, 0)))
				end
				return
			end
			task.wait(0.2)
			local team = match.TeamOf[player]
			if team and character.Parent then
				local index = table.find(match.Teams[team], player) or 1
				character:PivotTo(match:GetSpawnCFrame(team, index, nil))
				InventoryService.SetTeamColor(player, Config.Teams[team].Color)
				if match.State == "Kickoff" then
					setAnchored(player, true)
				end
			end
		end)
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, p in Players:GetPlayers() do
		onPlayer(p)
	end
end

return MatchService
