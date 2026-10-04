--[[
	InputController (client)
	Binds every action listed in Config.Controls through ContextActionService,
	which gives keyboard/mouse, Xbox/PlayStation gamepads and mobile touch
	buttons from the same code. Rebind controls in Config.Controls only.

	The client only sends intents (Kick/Tackle/SkillMove). The server decides.
]]

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)

local ClientState = require(script.Parent.Parent.ClientState)
local BallController = require(script.Parent.BallController)
local MovementController = require(script.Parent.MovementController)

local InputController = {}

local player = Players.LocalPlayer
local kickRemote, tackleRemote, skillRemote
local chargeStart: number? = nil
local skillSide = 1
local lastTackle = 0
local lastSkill = 0

local Sink = Enum.ContextActionResult.Sink
local Pass = Enum.ContextActionResult.Pass

-- Other modules register callbacks for non-football actions (camera, menu)
InputController.ActionCallbacks = {}

local function canKick(): boolean
	if BallController.HasBall() then
		return true
	end
	return BallController.GetNearestBall(Config.Kick.ReachRadius) ~= nil
end

-- Kick direction: where you are moving, otherwise where the camera looks.
function InputController.GetAimDirection(): Vector3
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.MoveDirection.Magnitude > 0.1 then
		return humanoid.MoveDirection.Unit
	end
	local look = Workspace.CurrentCamera.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude > 1e-3 then
		return flat.Unit
	end
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	return root and root.CFrame.LookVector or Vector3.new(0, 0, -1)
end

local function kick(kind: string, power: number)
	kickRemote:FireServer(kind, InputController.GetAimDirection(), power)
end

local handlers = {}

function handlers.Sprint(state: Enum.UserInputState)
	MovementController.SetSprinting(state == Enum.UserInputState.Begin)
	return Pass
end

function handlers.Pass(state: Enum.UserInputState)
	if ClientState.MenuOpen then
		return Pass
	end
	if state == Enum.UserInputState.Begin and canKick() then
		kick("Pass", 0.5)
		return Sink
	end
	return Pass
end

function handlers.ThroughBall(state: Enum.UserInputState)
	if state == Enum.UserInputState.Begin and canKick() then
		kick("Through", 0.6)
		return Sink
	end
	return Pass
end

function handlers.Lob(state: Enum.UserInputState)
	-- Space: lob when we have the ball, otherwise let the jump through
	if state == Enum.UserInputState.Begin and BallController.HasBall() then
		kick("Lob", 0.55)
		return Sink
	end
	return Pass
end

function handlers.Shoot(state: Enum.UserInputState)
	if ClientState.MenuOpen then
		return Pass
	end
	if state == Enum.UserInputState.Begin then
		if canKick() then
			chargeStart = os.clock()
			ClientState.Charge = 0
			return Sink
		end
		return Pass
	elseif state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
		if chargeStart then
			local power = math.clamp((os.clock() - chargeStart) / Config.Kick.MaxChargeTime, 0.15, 1)
			chargeStart = nil
			ClientState.Charge = -1
			if state == Enum.UserInputState.End and canKick() then
				kick("Shot", power)
			end
			return Sink
		end
	end
	return Pass
end

function handlers.Tackle(state: Enum.UserInputState)
	if state ~= Enum.UserInputState.Begin or BallController.HasBall() then
		return Pass
	end
	local now = os.clock()
	if now - lastTackle < Config.Tackle.Cooldown then
		return Sink
	end
	lastTackle = now
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root then
		MovementController.Dash(root.CFrame.LookVector, 30, 0.2)
	end
	tackleRemote:FireServer()
	return Sink
end

function handlers.SkillMove(state: Enum.UserInputState)
	if state ~= Enum.UserInputState.Begin or not BallController.HasBall() then
		return Pass
	end
	local now = os.clock()
	if now - lastSkill < Config.SkillMove.Cooldown then
		return Sink
	end
	lastSkill = now
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root then
		-- Alternate left/right cuts
		skillSide = -skillSide
		MovementController.Dash(root.CFrame.RightVector * skillSide + root.CFrame.LookVector * 0.4, Config.SkillMove.DashSpeed, Config.SkillMove.DashTime)
	end
	skillRemote:FireServer()
	return Sink
end

function handlers.CameraMode(state: Enum.UserInputState)
	if state == Enum.UserInputState.Begin and InputController.ActionCallbacks.CameraMode then
		InputController.ActionCallbacks.CameraMode()
		return Sink
	end
	return Pass
end

function handlers.Menu(state: Enum.UserInputState)
	if state == Enum.UserInputState.Begin and InputController.ActionCallbacks.Menu then
		InputController.ActionCallbacks.Menu()
		return Sink
	end
	return Pass
end

-- Touch button layout (relative to the default jump button area)
local TOUCH_POSITIONS = {
	Shoot = UDim2.new(1, -95, 1, -230),
	Pass = UDim2.new(1, -175, 1, -170),
	ThroughBall = UDim2.new(1, -175, 1, -250),
	Lob = UDim2.new(1, -255, 1, -170),
	Tackle = UDim2.new(1, -255, 1, -90),
	SkillMove = UDim2.new(1, -255, 1, -250),
	Sprint = UDim2.new(1, -95, 1, -310),
}

local function bindAll()
	for actionName, binding in Config.Controls do
		local handler = handlers[actionName]
		if handler then
			local inputs = {}
			for _, input in binding.Keyboard or {} do
				table.insert(inputs, input)
			end
			for _, input in binding.Gamepad or {} do
				table.insert(inputs, input)
			end
			local function callback(_, state, _input)
				return handler(state)
			end
			ContextActionService:BindActionAtPriority("CK_" .. actionName, callback, binding.Touch == true, Enum.ContextActionPriority.High.Value, table.unpack(inputs))
			if binding.Touch then
				ContextActionService:SetTitle("CK_" .. actionName, binding.TouchTitle or actionName)
				if TOUCH_POSITIONS[actionName] then
					ContextActionService:SetPosition("CK_" .. actionName, TOUCH_POSITIONS[actionName])
				end
			end
		end
	end
end

function InputController.IsCharging(): boolean
	return chargeStart ~= nil
end

function InputController.GetChargeAlpha(): number
	if not chargeStart then
		return 0
	end
	return math.clamp((os.clock() - chargeStart) / Config.Kick.MaxChargeTime, 0, 1)
end

function InputController.IsTouch(): boolean
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end

function InputController.Init()
	kickRemote = Remotes.Get("Kick")
	tackleRemote = Remotes.Get("Tackle")
	skillRemote = Remotes.Get("SkillMove")
end

function InputController.Start()
	bindAll()
end

return InputController
