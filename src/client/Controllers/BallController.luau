--[[
	BallController (client)
	When the server hands us network ownership of a ball (we have possession),
	we steer it in front of our feet every physics step so dribbling feels
	instant. The server still validates distance and decides every kick.

	Also exposes helpers the InputController uses: GetMyBall / GetNearestBall.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)

local BallController = {}

local player = Players.LocalPlayer
local ballsFolder: Instance? = nil
local dribbleConnection: RBXScriptConnection? = nil
local myBall: BasePart? = nil

local function getRoot(): BasePart?
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function getHumanoid(): Humanoid?
	local character = player.Character
	return character and character:FindFirstChildOfClass("Humanoid")
end

local function getBalls(): { BasePart }
	if not ballsFolder then
		local grounds = Workspace:FindFirstChild("Grounds")
		ballsFolder = grounds and grounds:FindFirstChild("Balls")
	end
	if not ballsFolder then
		return {}
	end
	local list = {}
	for _, child in (ballsFolder :: Instance):GetChildren() do
		if child:IsA("BasePart") then
			table.insert(list, child)
		end
	end
	return list
end

function BallController.GetMyBall(): BasePart?
	for _, ball in getBalls() do
		if ball:GetAttribute("PossessorId") == player.UserId then
			return ball
		end
	end
	return nil
end

function BallController.GetNearestBall(maxDistance: number): BasePart?
	local root = getRoot()
	if not root then
		return nil
	end
	local best, bestDist = nil, maxDistance
	for _, ball in getBalls() do
		local d = (ball.Position - root.Position).Magnitude
		if d <= bestDist then
			best, bestDist = ball, d
		end
	end
	return best
end

local function dribbleStep(_dt: number)
	local ball = myBall
	local root = getRoot()
	local humanoid = getHumanoid()
	if not ball or not ball.Parent or not root or not humanoid then
		return
	end
	if ball:GetAttribute("PossessorId") ~= player.UserId then
		return
	end
	local cfg = Config.Ball
	local moveDir = humanoid.MoveDirection
	local forward = if moveDir.Magnitude > 0.1 then moveDir.Unit else root.CFrame.LookVector
	forward = Vector3.new(forward.X, 0, forward.Z)
	if forward.Magnitude < 1e-3 then
		forward = Vector3.new(0, 0, -1)
	end
	forward = forward.Unit

	local surfaceY = ball:GetAttribute("SurfaceY") or 0
	local radius = ball.Size.X / 2
	local rootVel = root.AssemblyLinearVelocity
	local target = root.Position + forward * cfg.DribbleDistance
	target = Vector3.new(target.X, surfaceY + radius, target.Z)

	local delta = target - ball.Position
	local horizontal = Vector3.new(delta.X, 0, delta.Z) * cfg.DribbleStiffness + Vector3.new(rootVel.X, 0, rootVel.Z)
	if horizontal.Magnitude > 75 then
		horizontal = horizontal.Unit * 75
	end
	local vy = math.clamp(delta.Y * 10, -40, 15)
	local velocity = Vector3.new(horizontal.X, vy, horizontal.Z)
	ball.AssemblyLinearVelocity = velocity
	ball.AssemblyAngularVelocity = Vector3.new(velocity.Z, 0, -velocity.X) / radius
end

local function refreshPossession()
	local ball = BallController.GetMyBall()
	myBall = ball
	if ball and not dribbleConnection then
		dribbleConnection = RunService.PreSimulation:Connect(dribbleStep)
	elseif not ball and dribbleConnection then
		dribbleConnection:Disconnect()
		dribbleConnection = nil
	end
end

function BallController.Init() end

function BallController.Start()
	-- The server mirrors possession onto the player as the HasBall attribute,
	-- so we only run the dribble loop while we actually have the ball.
	player:GetAttributeChangedSignal("HasBall"):Connect(function()
		task.defer(refreshPossession)
	end)
	-- Safety net in case attribute order races the ball attribute.
	task.spawn(function()
		while true do
			task.wait(0.5)
			refreshPossession()
		end
	end)
end

function BallController.HasBall(): boolean
	return player:GetAttribute("HasBall") == true
end

return BallController
