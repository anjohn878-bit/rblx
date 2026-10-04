--[[
	BallService
	Server-authoritative footballs.

	How the ball works:
	  * Free ball: owned by the server, simulated by Roblox physics plus custom
	    gravity (VectorForce) and custom rolling/air drag applied here.
	  * Possessed by a player: network ownership is handed to that player so the
	    dribble is perfectly smooth on their screen (client BallController steers
	    it). The server keeps checking the ball stays within a short leash of the
	    player, otherwise possession is dropped.
	  * Possessed by a bot: the server steers it.
	  * Kicks, tackles and possession changes are only decided here. Clients send
	    intents (Kick/Tackle/SkillMove) and the server validates them.
	  * Balls never collide with characters (collision groups). Contact with
	    players is handled by our own control/deflection logic instead, which is
	    what keeps the ball from behaving like a random physics object.

	Each ball has a `Handlers` table so the owner (MatchService or practice)
	decides who may touch it and receives callbacks for stats.
]]

local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local KickMath = require(Shared.KickMath)
local Remotes = require(Shared.Remotes)

local Actors = require(script.Parent.Actors)
local MapBuilder = require(script.Parent.MapBuilder)

local BallService = {}

local BALL_GROUP = "CK_Ball"
local CHARACTER_GROUP = "CK_Characters"
local KICK_KINDS = { Pass = true, Through = true, Lob = true, Shot = true }

local balls = {} -- list of ball objects
local nextBallId = 0
local rng = Random.new()

local lastKick: { [any]: number } = {}
local lastTackle: { [any]: number } = {}
local lastSkill: { [any]: number } = {}
local evadeUntil: { [any]: number } = {}

local ballEvent

-------------------------------------------------------------------------------
-- Collision groups
-------------------------------------------------------------------------------
local function setupCollisionGroups()
	for _, name in { BALL_GROUP, CHARACTER_GROUP } do
		if not PhysicsService:IsCollisionGroupRegistered(name) then
			PhysicsService:RegisterCollisionGroup(name)
		end
	end
	PhysicsService:CollisionGroupSetCollidable(BALL_GROUP, CHARACTER_GROUP, false)
end

function BallService.TagCharacter(character: Model)
	local function tag(d)
		if d:IsA("BasePart") then
			d.CollisionGroup = CHARACTER_GROUP
		end
	end
	for _, d in character:GetDescendants() do
		tag(d)
	end
	character.DescendantAdded:Connect(tag)
end

-------------------------------------------------------------------------------
-- Ball creation
-------------------------------------------------------------------------------
local function buildBallPart(id: number): Part
	local cfg = Config.Ball
	local p = Instance.new("Part")
	p.CFrame = CFrame.new()
	p.Name = "Ball_" .. id
	p.Shape = Enum.PartType.Ball
	p.Size = Vector3.one * cfg.Size
	p.Color = Color3.fromRGB(250, 250, 250)
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CustomPhysicalProperties = PhysicalProperties.new(cfg.Density, cfg.Friction, cfg.Elasticity, 1, 1)
	p.CollisionGroup = BALL_GROUP
	p.CastShadow = true

	-- Panels so the spin is visible
	local r = cfg.Size / 2
	local dirs = {
		Vector3.new(1, 0, 0), Vector3.new(-1, 0, 0), Vector3.new(0, 1, 0),
		Vector3.new(0, -1, 0), Vector3.new(0, 0, 1), Vector3.new(0, 0, -1),
	}
	for i, d in dirs do
		local patch = Instance.new("Part")
		patch.Name = "Panel" .. i
		patch.Shape = Enum.PartType.Cylinder
		patch.Size = Vector3.new(0.1, r * 0.9, r * 0.9)
		patch.Color = Color3.fromRGB(20, 20, 24)
		patch.Material = Enum.Material.SmoothPlastic
		patch.CanCollide = false
		patch.CanQuery = false
		patch.CanTouch = false
		patch.Massless = true
		patch.CFrame = CFrame.lookAt(d * (r - 0.03), d * 2) * CFrame.Angles(0, math.rad(90), 0)
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = p
		weld.Part1 = patch
		weld.Parent = patch
		patch.Parent = p
	end

	local att = Instance.new("Attachment")
	att.Name = "Center"
	att.Parent = p
	local antiGravity = Instance.new("VectorForce")
	antiGravity.Name = "CustomGravity"
	antiGravity.Attachment0 = att
	antiGravity.RelativeTo = Enum.ActuatorRelativeTo.World
	antiGravity.ApplyAtCenterOfMass = true
	antiGravity.Parent = p

	p:SetAttribute("PossessorId", 0)
	return p
end

local function updateGravityForce(ball)
	local part = ball.Part
	local force = part:FindFirstChild("CustomGravity") :: VectorForce
	force.Force = Vector3.new(0, part:GetMass() * Workspace.Gravity * (1 - Config.Ball.GravityScale), 0)
end

--[[
	opts = {
		SpawnPosition = Vector3,
		SurfaceY = number,
		Bounds = { Center = Vector3, HalfSize = Vector3 }?,
		Handlers = {
			GetActors = () -> { actor },            -- who may touch this ball
			GetMates = (actor) -> { actor },         -- for pass assist
			GetAttackGoal = (actor) -> (Vector3?, number?), -- goal centre + width
			OnPossession = (ball, actor, previousTouch)?,
			OnKick = (ball, actor, kind)?,
			OnTackle = (ball, tackler, victim, success)?,
			OnSkillMove = (ball, actor)?,
			OnOutOfBounds = (ball)?,
		}
	}
]]
function BallService.CreateBall(opts)
	nextBallId += 1
	local part = buildBallPart(nextBallId)
	part.CFrame = CFrame.new(opts.SpawnPosition)
	part:SetAttribute("SurfaceY", opts.SurfaceY or 0)
	part.Parent = MapBuilder.GetRoot().Balls

	local ball = {
		Id = nextBallId,
		Part = part,
		SpawnPosition = opts.SpawnPosition,
		SurfaceY = opts.SurfaceY or 0,
		Bounds = opts.Bounds,
		Handlers = opts.Handlers,
		Possessor = nil,
		Frozen = false,
		NoTouchUntil = {},
		Touches = {}, -- recent touch history, newest last
		Destroyed = false,
	}
	part:SetNetworkOwner(nil)
	updateGravityForce(ball)
	table.insert(balls, ball)
	return ball
end

function BallService.DestroyBall(ball)
	ball.Destroyed = true
	local idx = table.find(balls, ball)
	if idx then
		table.remove(balls, idx)
	end
	ball.Part:Destroy()
end

-------------------------------------------------------------------------------
-- Possession helpers
-------------------------------------------------------------------------------
local function recordTouch(ball, actor, kind: string)
	table.insert(ball.Touches, { Actor = actor, Kind = kind, Time = os.clock() })
	if #ball.Touches > 8 then
		table.remove(ball.Touches, 1)
	end
end

function BallService.GetLastTouch(ball)
	return ball.Touches[#ball.Touches]
end

local function setOwnerServer(ball)
	if not ball.Part.Anchored then
		pcall(function()
			ball.Part:SetNetworkOwner(nil)
		end)
	end
end

local function clearPossession(ball)
	if ball.Possessor and not Actors.IsBot(ball.Possessor) then
		(ball.Possessor :: Player):SetAttribute("HasBall", false)
	end
	ball.Possessor = nil
	ball.Part:SetAttribute("PossessorId", 0)
	setOwnerServer(ball)
end

local function setPossessor(ball, actor)
	local previous = BallService.GetLastTouch(ball)
	if ball.Possessor and ball.Possessor ~= actor then
		clearPossession(ball)
	end
	ball.Possessor = actor
	ball.Part:SetAttribute("PossessorId", Actors.GetId(actor))
	recordTouch(ball, actor, "Control")
	if Actors.IsBot(actor) then
		setOwnerServer(ball)
	else
		(actor :: Player):SetAttribute("HasBall", true)
		pcall(function()
			ball.Part:SetNetworkOwner(actor)
		end)
	end
	if ball.Handlers.OnPossession then
		ball.Handlers.OnPossession(ball, actor, previous)
	end
end

function BallService.Reset(ball, position: Vector3?)
	clearPossession(ball)
	local part = ball.Part
	part.Anchored = false
	part.AssemblyLinearVelocity = Vector3.zero
	part.AssemblyAngularVelocity = Vector3.zero
	part.CFrame = CFrame.new(position or ball.SpawnPosition)
	setOwnerServer(ball)
	table.clear(ball.Touches)
	table.clear(ball.NoTouchUntil)
	ball.Frozen = false
end

-- Freeze in place (goal celebrations, kickoff countdowns)
function BallService.SetFrozen(ball, frozen: boolean)
	ball.Frozen = frozen
	if frozen then
		clearPossession(ball)
		ball.Part.AssemblyLinearVelocity = Vector3.zero
		ball.Part.AssemblyAngularVelocity = Vector3.zero
		ball.Part.Anchored = true
	else
		ball.Part.Anchored = false
		setOwnerServer(ball)
	end
end

function BallService.ReleaseActor(actor)
	for _, ball in balls do
		if ball.Possessor == actor then
			clearPossession(ball)
		end
	end
	lastKick[actor] = nil
	lastTackle[actor] = nil
	lastSkill[actor] = nil
	evadeUntil[actor] = nil
end

local function canUse(ball, actor): boolean
	if ball.Frozen or not Actors.IsAlive(actor) then
		return false
	end
	for _, a in ball.Handlers.GetActors() do
		if a == actor then
			return true
		end
	end
	return false
end

-------------------------------------------------------------------------------
-- Kicks
-------------------------------------------------------------------------------
local function isFiniteVector(v): boolean
	return typeof(v) == "Vector3" and v.X == v.X and v.Y == v.Y and v.Z == v.Z
		and math.abs(v.X) < 1e6 and math.abs(v.Y) < 1e6 and math.abs(v.Z) < 1e6
end

local function mateInfos(ball, actor)
	local infos = {}
	for _, mate in ball.Handlers.GetMates(actor) do
		local root = Actors.GetRoot(mate)
		if mate ~= actor and root then
			table.insert(infos, { Position = root.Position, Velocity = root.AssemblyLinearVelocity, Id = mate })
		end
	end
	return infos
end

-- Finds the ball this actor may kick right now (possessed, or free and within reach).
local function findKickableBall(actor)
	local root = Actors.GetRoot(actor)
	if not root then
		return nil
	end
	for _, ball in balls do
		if ball.Possessor == actor then
			return ball
		end
	end
	local now = os.clock()
	for _, ball in balls do
		if not ball.Possessor and canUse(ball, actor) and (ball.NoTouchUntil[actor] or 0) < now then
			if (ball.Part.Position - root.Position).Magnitude <= Config.Kick.ReachRadius then
				return ball
			end
		end
	end
	return nil
end

function BallService.Kick(actor, kind: string, direction: Vector3, power: number): boolean
	if not KICK_KINDS[kind] or not isFiniteVector(direction) or type(power) ~= "number" or power ~= power then
		return false
	end
	local now = os.clock()
	if lastKick[actor] and now - lastKick[actor] < Config.Kick.RateLimit then
		return false
	end
	local ball = findKickableBall(actor)
	if not ball or not canUse(ball, actor) then
		return false
	end
	local root = Actors.GetRoot(actor) :: BasePart
	lastKick[actor] = now

	if direction.Magnitude < 0.05 then
		direction = root.CFrame.LookVector
	end
	local goalCenter, goalWidth = ball.Handlers.GetAttackGoal(actor)
	local velocity = KickMath.Compute({
		Kind = kind,
		Origin = ball.Part.Position,
		Direction = direction,
		Power = math.clamp(power, 0, 1),
		Passing = Actors.Alpha(actor, "Passing"),
		Shooting = Actors.Alpha(actor, "Shooting"),
		Mates = mateInfos(ball, actor),
		GoalCenter = goalCenter,
		GoalWidth = goalWidth,
		Gravity = Workspace.Gravity,
		Random = rng,
	})

	clearPossession(ball)
	local part = ball.Part
	-- If the replicated ball lags far behind the kicker, snap it to their feet first.
	local flatDir = KickMath.Flat(velocity)
	local feet = Vector3.new(root.Position.X, ball.SurfaceY + Config.Ball.Size / 2 + 0.05, root.Position.Z) + flatDir * 2
	if (part.Position - feet).Magnitude > 4 then
		part.CFrame = CFrame.new(feet)
	end
	part.AssemblyLinearVelocity = velocity
	part.AssemblyAngularVelocity = Vector3.yAxis:Cross(flatDir) * (velocity.Magnitude / (Config.Ball.Size / 2)) * 0.3

	ball.NoTouchUntil[actor] = now + Config.Ball.KickerCooldown
	recordTouch(ball, actor, kind)
	ballEvent:FireAllClients("Kick", { Position = part.Position, Speed = velocity.Magnitude, Kind = kind })
	if ball.Handlers.OnKick then
		ball.Handlers.OnKick(ball, actor, kind)
	end
	return true
end

-------------------------------------------------------------------------------
-- Tackles and skill moves
-------------------------------------------------------------------------------
function BallService.Tackle(actor): (boolean, string?)
	local now = os.clock()
	if lastTackle[actor] and now - lastTackle[actor] < Config.Tackle.Cooldown then
		return false, "cooldown"
	end
	local root = Actors.GetRoot(actor)
	if not root or not Actors.IsAlive(actor) then
		return false, "dead"
	end
	lastTackle[actor] = now

	for _, ball in balls do
		local victim = ball.Possessor
		if victim and victim ~= actor and canUse(ball, actor) then
			local mates = ball.Handlers.GetMates(actor)
			local isMate = table.find(mates, victim) ~= nil
			local victimRoot = Actors.GetRoot(victim)
			if not isMate and victimRoot then
				local offset = victimRoot.Position - root.Position
				local dist = Vector3.new(offset.X, 0, offset.Z).Magnitude
				local facing = root.CFrame.LookVector:Dot(KickMath.Flat(offset))
				if dist <= Config.Tackle.Range and facing > -0.3 then
					local success
					if (evadeUntil[victim] or 0) > now then
						success = false
					else
						local chance = KickMath.TackleChance(Actors.Alpha(actor, "Defending"), Actors.Alpha(victim, "Dribbling"))
						-- Physicality gives a small edge in shoulder-to-shoulder duels
						chance += (Actors.Alpha(actor, "Physicality") - Actors.Alpha(victim, "Physicality")) * 0.1
						success = rng:NextNumber() < chance
					end

					if success then
						clearPossession(ball)
						local away = KickMath.Flat(root.Position - ball.Part.Position)
						ball.Part.AssemblyLinearVelocity = away * 14 + Vector3.new(0, 4, 0)
						ball.NoTouchUntil[victim] = now + Config.Ball.TackledCooldown
						recordTouch(ball, actor, "Tackle")
					end
					ballEvent:FireAllClients("Tackle", { Position = root.Position, Success = success })
					if not success and not Actors.IsBot(actor) then
						ballEvent:FireClient(actor, "TackleFailed", { Duration = Config.Tackle.FailSlowTime })
					elseif not success then
						actor.SlowUntil = now + Config.Tackle.FailSlowTime
					end
					if ball.Handlers.OnTackle then
						ball.Handlers.OnTackle(ball, actor, victim, success)
					end
					return success, "attempt"
				end
			end
		end
	end
	return false, "whiff"
end

function BallService.SkillMove(actor): boolean
	local now = os.clock()
	if lastSkill[actor] and now - lastSkill[actor] < Config.SkillMove.Cooldown then
		return false
	end
	lastSkill[actor] = now
	evadeUntil[actor] = now + Config.Tackle.EvadeWindow
	for _, ball in balls do
		if ball.Possessor == actor then
			recordTouch(ball, actor, "Skill")
			if ball.Handlers.OnSkillMove then
				ball.Handlers.OnSkillMove(ball, actor)
			end
			return true
		end
	end
	return false
end

-------------------------------------------------------------------------------
-- Simulation step
-------------------------------------------------------------------------------
local function stepPossessed(ball)
	local actor = ball.Possessor
	local root = Actors.GetRoot(actor)
	if not root or not canUse(ball, actor) then
		clearPossession(ball)
		return
	end
	local part = ball.Part
	local offset = part.Position - root.Position
	if Vector3.new(offset.X, 0, offset.Z).Magnitude > Config.Ball.MaxDribbleLeash or math.abs(offset.Y) > 8 then
		-- Lost the ball (lag spike, fell behind, or a client misbehaving)
		clearPossession(ball)
		return
	end
	if Actors.IsBot(actor) then
		local target = root.Position + root.CFrame.LookVector * Config.Ball.DribbleDistance
		target = Vector3.new(target.X, ball.SurfaceY + Config.Ball.Size / 2, target.Z)
		local rootVel = root.AssemblyLinearVelocity
		local desired = (target - part.Position) * Config.Ball.DribbleStiffness + Vector3.new(rootVel.X, 0, rootVel.Z)
		if desired.Magnitude > 70 then
			desired = desired.Unit * 70
		end
		part.AssemblyLinearVelocity = desired
	end
end

local function stepFree(ball, dt: number)
	local part = ball.Part
	local cfg = Config.Ball
	local vel = part.AssemblyLinearVelocity
	local height = part.Position.Y - (ball.SurfaceY + cfg.Size / 2)
	local grounded = height < 0.35

	-- Custom drag
	local drag = if grounded then cfg.GroundDrag else cfg.AirDrag
	local factor = math.exp(-drag * dt)
	part.AssemblyLinearVelocity = Vector3.new(vel.X * factor, vel.Y, vel.Z * factor)

	-- Control / deflection by nearby actors
	local now = os.clock()
	local best, bestDist = nil, math.huge
	for _, actor in ball.Handlers.GetActors() do
		if (ball.NoTouchUntil[actor] or 0) < now and Actors.IsAlive(actor) then
			local root = Actors.GetRoot(actor) :: BasePart
			local offset = part.Position - root.Position
			local horizontal = Vector3.new(offset.X, 0, offset.Z).Magnitude
			if horizontal <= cfg.ControlRadius and offset.Y < cfg.ControlHeight - 3 and offset.Y > -4 and horizontal < bestDist then
				best, bestDist = actor, horizontal
			end
		end
	end
	if best then
		local speed = vel.Magnitude
		local chance = KickMath.FirstTouchChance(Actors.Alpha(best, "BallControl"), speed)
		if rng:NextNumber() <= chance then
			setPossessor(ball, best)
		else
			-- Heavy touch: the ball bounces off the player
			local root = Actors.GetRoot(best) :: BasePart
			local away = KickMath.Flat(part.Position - root.Position)
			part.AssemblyLinearVelocity = away * speed * 0.35 + Vector3.new(0, 8, 0)
			ball.NoTouchUntil[best] = now + 0.35
			recordTouch(ball, best, "Deflect")
			ballEvent:FireAllClients("Deflect", { Position = part.Position })
		end
	end
end

local function step(dt: number)
	for i = #balls, 1, -1 do
		local ball = balls[i]
		if ball and not ball.Destroyed and not ball.Frozen then
			local pos = ball.Part.Position
			local outOfBounds = pos.Y < ball.SurfaceY - 15
			if ball.Bounds and not outOfBounds then
				local rel = pos - ball.Bounds.Center
				local hs = ball.Bounds.HalfSize
				outOfBounds = math.abs(rel.X) > hs.X or math.abs(rel.Z) > hs.Z or rel.Y > hs.Y
			end
			if outOfBounds then
				if ball.Handlers.OnOutOfBounds then
					ball.Handlers.OnOutOfBounds(ball)
				else
					BallService.Reset(ball)
				end
			elseif ball.Possessor then
				stepPossessed(ball)
			else
				stepFree(ball, dt)
			end
		end
	end
end

-------------------------------------------------------------------------------
-- Practice balls (free to use by anyone not in a match)
-------------------------------------------------------------------------------
local function practiceActors()
	local list = {}
	for _, player in Players:GetPlayers() do
		if not player:GetAttribute("MatchId") then
			table.insert(list, player)
		end
	end
	return list
end

local function createPracticeBalls()
	local center = Config.Hub.PracticeArea
	local handlers = {
		GetActors = practiceActors,
		GetMates = function()
			return practiceActors()
		end,
		GetAttackGoal = function()
			return center + Vector3.new(20, 2, 0), 12
		end,
	}
	for i = 1, 3 do
		BallService.CreateBall({
			SpawnPosition = center + Vector3.new(-6 + i * 3, 3, -4 + i * 2),
			SurfaceY = 0.2,
			Bounds = { Center = center, HalfSize = Vector3.new(30, 60, 30) },
			Handlers = handlers,
		})
	end
end

-------------------------------------------------------------------------------
function BallService.Init()
	setupCollisionGroups()
	ballEvent = Remotes.Get("BallEvent")
end

function BallService.Start()
	local function onCharacter(character: Model)
		BallService.TagCharacter(character)
	end
	local function onPlayer(player: Player)
		player.CharacterAdded:Connect(onCharacter)
		if player.Character then
			onCharacter(player.Character)
		end
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, p in Players:GetPlayers() do
		onPlayer(p)
	end
	Players.PlayerRemoving:Connect(function(player)
		BallService.ReleaseActor(player)
		for _, ball in balls do
			ball.NoTouchUntil[player] = nil
		end
	end)

	-- Remotes: clients only send intents
	Remotes.Get("Kick").OnServerEvent:Connect(function(player, kind, direction, power)
		if type(kind) ~= "string" then
			return
		end
		BallService.Kick(player, kind, direction, power)
	end)
	Remotes.Get("Tackle").OnServerEvent:Connect(function(player)
		BallService.Tackle(player)
	end)
	Remotes.Get("SkillMove").OnServerEvent:Connect(function(player)
		BallService.SkillMove(player)
	end)

	createPracticeBalls()
	RunService.Heartbeat:Connect(step)
end

return BallService
