--[[
	CameraController (client)
	Outside matches the normal Roblox camera is used. In a match we take over:

	  Follow    - elevated third-person behind the player. Mouse (locked to the
	              centre), right stick or touch drag turns it. Sensitivity setting.
	  Broadcast - fixed side-on-from-behind view facing the goal you attack,
	              framing you and the ball. Great for mobile/gamepad.

	Important moments (kickoff, goals, full time) blend to the ball/goal. All
	motion is exponentially smoothed; there is no camera shake.
	Toggle with C (Config.Controls.CameraMode).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)

local ClientState = require(script.Parent.Parent.ClientState)
local BallController = require(script.Parent.BallController)

local CameraController = {}

local player = Players.LocalPlayer
local camera = Workspace.CurrentCamera

local active = false
local mode = "Follow"
local yaw = 0
local pitch = math.rad(-20)
local focus = Vector3.zero
local camPos = Vector3.zero
local goalFocus: Vector3? = nil
local goalFocusUntil = 0

local FOLLOW_DISTANCE = 20
local FOLLOW_HEIGHT = 7
local BROADCAST_BACK = 34
local BROADCAST_HEIGHT = 24

local function smooth(rate: number, dt: number): number
	return 1 - math.exp(-rate * dt)
end

local function getRoot(): BasePart?
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function getMatchState(): Instance?
	local matchId = player:GetAttribute("MatchId")
	local matches = ReplicatedStorage:FindFirstChild("Matches")
	return matchId and matches and matches:FindFirstChild(matchId)
end

local function sensitivity(): number
	local p = ClientState.Profile
	return (p and p.Settings and p.Settings.CameraSensitivity) or 1
end

local function matchBall(): BasePart?
	local root = getRoot()
	if not root then
		return nil
	end
	return BallController.GetNearestBall(150)
end

local function setActive(on: boolean)
	if on == active then
		return
	end
	active = on
	if on then
		camera.CameraType = Enum.CameraType.Scriptable
		local root = getRoot()
		local dir = player:GetAttribute("AttackDir") or 1
		yaw = if dir > 0 then math.rad(-90) else math.rad(90)
		if root then
			focus = root.Position
			camPos = camera.CFrame.Position
		end
	else
		camera.CameraType = Enum.CameraType.Custom
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			camera.CameraSubject = humanoid
		end
	end
end

function CameraController.ToggleMode()
	mode = if mode == "Follow" then "Broadcast" else "Follow"
	Remotes.Get("UpdateSettings"):FireServer({ CameraMode = mode })
end

function CameraController.GetMode(): string
	return mode
end

local function update(dt: number)
	local state = getMatchState()
	local matchState = state and state:GetAttribute("State")
	local inMatch = state ~= nil and matchState ~= nil and matchState ~= "Idle" and matchState ~= "MatchFound"
	setActive(inMatch)
	if not active then
		return
	end

	local root = getRoot()
	if not root then
		return
	end

	local attackDir = player:GetAttribute("AttackDir") or 1
	local ball = matchBall()
	local ballPos = ball and ball.Position or root.Position

	-- Mouse lock only for Follow mode on PC, and never while a menu is open.
	local lockMouse = mode == "Follow" and not ClientState.MenuOpen and UserInputService.KeyboardEnabled
	UserInputService.MouseBehavior = if lockMouse then Enum.MouseBehavior.LockCenter else Enum.MouseBehavior.Default

	local desiredFocus: Vector3
	local desiredPos: Vector3
	local now = os.clock()

	if goalFocus and now < goalFocusUntil then
		-- Goal replay-style framing
		desiredFocus = goalFocus
		desiredPos = goalFocus + Vector3.new(-attackDir * 26, 14, 18)
	elseif matchState == "Kickoff" or matchState == "Ended" then
		-- Wide view from behind our half
		desiredFocus = ballPos:Lerp(root.Position, 0.3)
		desiredPos = desiredFocus + Vector3.new(-attackDir * 46, 30, 0)
	elseif mode == "Broadcast" then
		desiredFocus = root.Position:Lerp(ballPos, 0.35) + Vector3.new(attackDir * 8, 0, 0)
		desiredPos = desiredFocus + Vector3.new(-attackDir * BROADCAST_BACK, BROADCAST_HEIGHT, 0)
	else
		-- Follow: orbit by input, slight lean toward the ball
		if lockMouse then
			local delta = UserInputService:GetMouseDelta()
			yaw -= delta.X * 0.0045 * sensitivity()
			pitch = math.clamp(pitch - delta.Y * 0.003 * sensitivity(), math.rad(-45), math.rad(-8))
		end
		desiredFocus = root.Position + Vector3.new(0, 2, 0)
		local toBall = ballPos - root.Position
		if toBall.Magnitude < 40 then
			desiredFocus += Vector3.new(toBall.X, 0, toBall.Z) * 0.15
		end
		local rot = CFrame.Angles(0, yaw, 0) * CFrame.Angles(pitch, 0, 0)
		desiredPos = desiredFocus + rot:VectorToWorldSpace(Vector3.new(0, 0, FOLLOW_DISTANCE)) + Vector3.new(0, FOLLOW_HEIGHT * 0.3, 0)
	end

	focus = focus:Lerp(desiredFocus, smooth(10, dt))
	camPos = camPos:Lerp(desiredPos, smooth(8, dt))
	camera.CFrame = CFrame.lookAt(camPos, focus)
end

-- Gamepad right stick / touch drag for the Follow camera
local function onInputChanged(input: InputObject, processed: boolean)
	if not active or mode ~= "Follow" then
		return
	end
	if input.KeyCode == Enum.KeyCode.Thumbstick2 then
		local v = input.Position
		if v.Magnitude > 0.15 then
			yaw -= v.X * 0.06 * sensitivity()
			pitch = math.clamp(pitch + v.Y * 0.03 * sensitivity(), math.rad(-45), math.rad(-8))
		end
	elseif input.UserInputType == Enum.UserInputType.Touch and not processed then
		-- Only drags on the right half of the screen turn the camera
		if input.Position.X > camera.ViewportSize.X * 0.5 then
			yaw -= input.Delta.X * 0.008 * sensitivity()
			pitch = math.clamp(pitch - input.Delta.Y * 0.005 * sensitivity(), math.rad(-45), math.rad(-8))
		end
	end
end

function CameraController.Init() end

function CameraController.Start()
	ClientState.Changed:Connect(function(profile)
		if profile.Settings and (profile.Settings.CameraMode == "Follow" or profile.Settings.CameraMode == "Broadcast") then
			mode = profile.Settings.CameraMode
		end
	end)
	if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		mode = "Broadcast"
	end

	Remotes.Get("MatchEvent").OnClientEvent:Connect(function(kind, payload)
		if kind == "Goal" and payload.PitchId == player:GetAttribute("MatchId") and payload.BallPosition then
			goalFocus = payload.BallPosition
			goalFocusUntil = os.clock() + 3
		end
	end)

	UserInputService.InputChanged:Connect(onInputChanged)
	RunService:BindToRenderStep("CK_Camera", Enum.RenderPriority.Camera.Value + 1, update)
end

return CameraController
