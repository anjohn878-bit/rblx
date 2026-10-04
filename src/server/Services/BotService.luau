--[[
	BotService
	"Ground Regulars": AI footballers that fill empty match slots so a match can
	always start, even with one human. Bots are server-owned R15 rigs that use the
	same BallService API as players (no special powers).

	AI runs on a fixed 0.15s tick for all bots together, not per-frame.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Cosmetics = require(Shared.Cosmetics)
local KickMath = require(Shared.KickMath)

local Actors = require(script.Parent.Actors)
local BallService = require(script.Parent.BallService)
local MapBuilder = require(script.Parent.MapBuilder)
local NPCAnimator = require(script.Parent.NPCAnimator)

local BotService = {}

local AI_TICK = 0.15
local NAMES = {
	"Dex", "Kofi", "Mateo", "Rio", "Jax", "Nico", "Sami", "Theo", "Zane", "Malik",
	"Yusuf", "Leo", "Ivo", "Bo", "Remy", "Tariq", "Enzo", "Caz", "Obi", "Luca",
}
local SKIN_TONES = {
	Color3.fromRGB(255, 220, 190), Color3.fromRGB(234, 184, 146), Color3.fromRGB(198, 134, 94),
	Color3.fromRGB(141, 85, 54), Color3.fromRGB(96, 58, 38), Color3.fromRGB(60, 38, 28),
}
local SHORTS = { "shorts_black", "shorts_white", "shorts_navy" }
local BOOTS = { "boots_black", "boots_white", "boots_volt", "boots_blaze" }

local bots = {}
local nextBotId = 0
local rng = Random.new()

local function buildRig(name: string): Model
	local desc = Instance.new("HumanoidDescription")
	local skin = SKIN_TONES[rng:NextInteger(1, #SKIN_TONES)]
	desc.HeadColor = skin
	desc.LeftArmColor = skin
	desc.RightArmColor = skin
	desc.TorsoColor = skin
	desc.LeftLegColor = skin
	desc.RightLegColor = skin
	local model = Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15)
	model.Name = name
	local humanoid = model:FindFirstChildOfClass("Humanoid") :: Humanoid
	humanoid.DisplayName = name
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.Viewer
	humanoid.NameDisplayDistance = 60
	humanoid.BreakJointsOnDeath = false
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Dead, false)
	-- Remove any client Animate script the factory may have added; NPCAnimator handles it.
	local animate = model:FindFirstChild("Animate")
	if animate then
		animate:Destroy()
	end
	return model
end

function BotService.CreateBot(team: string)
	nextBotId += 1
	local name = NAMES[rng:NextInteger(1, #NAMES)]
	local model = buildRig(name)
	local attributes = {}
	for _, attr in Config.Attributes.List do
		attributes[attr] = rng:NextInteger(44, 62)
	end
	local bot = {
		IsBot = true,
		Id = -nextBotId,
		Name = name,
		Model = model,
		Attributes = attributes,
		Team = team,
		Match = nil,
		Role = 1,
		SlowUntil = 0,
		PossessedSince = 0,
		Animator = nil,
	}
	local kit = {
		Shirt = "shirt_white",
		Shorts = SHORTS[rng:NextInteger(1, #SHORTS)],
		Socks = "socks_white",
		Boots = BOOTS[rng:NextInteger(1, #BOOTS)],
		Headwear = "head_none",
		Trail = "trail_none",
	}
	Cosmetics.Apply(model, kit, Config.Teams[team].Color)
	model:PivotTo(CFrame.new(0, -200, 0)) -- out of sight until the match places it
	model.Parent = MapBuilder.GetRoot().NPCs
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart
	root.Anchored = true
	pcall(function()
		root:SetNetworkOwner(nil)
	end)
	BallService.TagCharacter(model)
	bot.Animator = NPCAnimator.Attach(model)
	bots[bot] = true
	return bot
end

function BotService.AssignMatch(bot, match, team: string)
	bot.Match = match
	bot.Team = team
	bot.Role = #match.Teams[team]
end

function BotService.DestroyBot(bot)
	bots[bot] = nil
	BallService.ReleaseActor(bot)
	if bot.Model then
		bot.Model:Destroy()
	end
	bot.Model = nil
	bot.Match = nil
end

-------------------------------------------------------------------------------
-- AI
-------------------------------------------------------------------------------
local function flatDist(a: Vector3, b: Vector3): number
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

local function closestToPoint(actors, point: Vector3)
	local best, bestDist = nil, math.huge
	for _, actor in actors do
		local root = Actors.GetRoot(actor)
		if root then
			local d = flatDist(root.Position, point)
			if d < bestDist then
				best, bestDist = actor, d
			end
		end
	end
	return best, bestDist
end

local function clampToPitch(match, pos: Vector3): Vector3
	local p = match.Pitch
	local x = math.clamp(pos.X, p.Center.X - p.Length / 2 + 3, p.Center.X + p.Length / 2 - 3)
	local z = math.clamp(pos.Z, p.Center.Z - p.Width / 2 + 3, p.Center.Z + p.Width / 2 - 3)
	return Vector3.new(x, p.SurfaceY, z)
end

local function nearestOpponentDistance(match, team: string, point: Vector3): number
	local _, d = closestToPoint(match.Teams[if team == "A" then "B" else "A"], point)
	return d
end

local function choosePassTarget(bot, match, root: BasePart, attackDir: number)
	local best, bestScore = nil, -math.huge
	for _, mate in match.Teams[bot.Team] do
		local mateRoot = Actors.GetRoot(mate)
		if mate ~= bot and mateRoot then
			local space = nearestOpponentDistance(match, bot.Team, mateRoot.Position)
			local progress = (mateRoot.Position.X - root.Position.X) * attackDir
			local dist = flatDist(mateRoot.Position, root.Position)
			if dist > 6 and dist < 70 then
				local score = space * 1.2 + progress * 0.6 - dist * 0.15
				if score > bestScore then
					best, bestScore = mateRoot, score
				end
			end
		end
	end
	return best, bestScore
end

local function think(bot)
	local match = bot.Match
	local humanoid = Actors.GetHumanoid(bot)
	local root = Actors.GetRoot(bot)
	if not match or not humanoid or not root or not match.Ball then
		return
	end
	if match.State ~= "Playing" then
		humanoid:Move(Vector3.zero)
		return
	end

	local now = os.clock()
	local ball = match.Ball
	local ballPos = ball.Part.Position
	local team = bot.Team
	local attackDir = if team == "A" then 1 else -1
	local attackGoal = match:GetAttackGoal(team)
	local ownGoal = match:GetAttackGoal(if team == "A" then "B" else "A")
	local pace = Actors.Alpha(bot, "Pace")

	local walk = Config.Movement.BaseWalkSpeed + pace * Config.Movement.PaceWalkBonus
	local sprint = Config.Movement.BaseSprintSpeed + pace * Config.Movement.PaceSprintBonus
	local speed = walk
	local target: Vector3

	local possessor = ball.Possessor
	if possessor == bot then
		if bot.PossessedSince == 0 then
			bot.PossessedSince = now
		end
		local held = now - bot.PossessedSince
		local goalDist = flatDist(root.Position, attackGoal)
		local pressure = nearestOpponentDistance(match, team, root.Position)
		speed = walk * Config.Movement.DribbleSpeedMultiplier

		if goalDist < 40 and held > 0.4 and rng:NextNumber() < 0.45 then
			local aim = attackGoal + Vector3.new(0, 0, rng:NextNumber(-5, 5))
			BallService.Kick(bot, "Shot", KickMath.Flat(aim - root.Position), rng:NextNumber(0.55, 0.95))
			return
		end
		if (pressure < 8 and held > 0.5) or held > 4 then
			local mateRoot, score = choosePassTarget(bot, match, root, attackDir)
			if mateRoot and (score > 0 or pressure < 6) and rng:NextNumber() < 0.6 then
				local kind = if rng:NextNumber() < 0.2 then "Through" else "Pass"
				BallService.Kick(bot, kind, KickMath.Flat(mateRoot.Position - root.Position), 0.6)
				return
			elseif pressure < 6 and rng:NextNumber() < 0.25 then
				BallService.SkillMove(bot)
			end
		end
		-- Dribble toward goal, drifting away from the nearest defender
		local lateral = math.sin(now * 0.8 + bot.Id) * 10
		target = Vector3.new(attackGoal.X, root.Position.Y, attackGoal.Z + lateral)
	else
		bot.PossessedSince = 0
		local possessorTeam = possessor and match:GetTeam(possessor)
		local chaser = closestToPoint(match.Teams[team], ballPos)

		if possessorTeam == team then
			-- Support run: get ahead of the ball carrier, spread out by role
			local lane = if bot.Role % 2 == 0 then -1 else 1
			target = ballPos + Vector3.new(attackDir * 16, 0, lane * 14)
		elseif possessor then
			-- Opponent has it: closest bot presses, others drop goal-side
			if chaser == bot then
				local carrierRoot = Actors.GetRoot(possessor)
				target = carrierRoot and carrierRoot.Position or ballPos
				speed = sprint
				if carrierRoot and flatDist(carrierRoot.Position, root.Position) < Config.Tackle.Range - 1 and rng:NextNumber() < 0.35 then
					BallService.Tackle(bot)
				end
			else
				local lane = if bot.Role % 2 == 0 then -1 else 1
				target = ballPos:Lerp(ownGoal, 0.45) + Vector3.new(0, 0, lane * 8)
			end
		else
			-- Loose ball
			if chaser == bot then
				local vel = ball.Part.AssemblyLinearVelocity
				target = ballPos + Vector3.new(vel.X, 0, vel.Z) * 0.25
				speed = sprint
			else
				local lane = if bot.Role % 2 == 0 then -1 else 1
				local depth = if bot.Role == 1 then 6 else -14
				target = Vector3.new(ballPos.X + attackDir * depth, root.Position.Y, match.Pitch.Center.Z + lane * 14)
			end
		end
	end

	if bot.SlowUntil > now then
		speed = 8
	end
	humanoid.WalkSpeed = speed
	local dest = clampToPitch(match, target)
	if flatDist(dest, root.Position) < 1.5 then
		humanoid:Move(Vector3.zero)
	else
		humanoid:MoveTo(Vector3.new(dest.X, root.Position.Y, dest.Z))
	end
end

function BotService.Init() end

function BotService.Start()
	task.spawn(function()
		while true do
			task.wait(AI_TICK)
			for bot in bots do
				if bot.Match then
					local ok, err = pcall(think, bot)
					if not ok then
						warn("[BotService] " .. tostring(err))
					end
				end
			end
		end
	end)
end

return BotService
