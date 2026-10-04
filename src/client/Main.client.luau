--[[
	Client bootstrap. Controllers are initialised in order, then started.
]]

local ClientState = require(script.Parent:WaitForChild("ClientState"))
local Controllers = script.Parent:WaitForChild("Controllers")
local UI = script.Parent:WaitForChild("UI")

local BallController = require(Controllers:WaitForChild("BallController"))
local MovementController = require(Controllers:WaitForChild("MovementController"))
local InputController = require(Controllers:WaitForChild("InputController"))
local CameraController = require(Controllers:WaitForChild("CameraController"))
local UIController = require(UI:WaitForChild("UIController"))

local ordered = { ClientState, BallController, MovementController, InputController, CameraController, UIController }

for _, module in ordered do
	module.Init()
end

InputController.ActionCallbacks.CameraMode = CameraController.ToggleMode
InputController.ActionCallbacks.Menu = UIController.ToggleMenu

for _, module in ordered do
	if module.Start then
		module.Start()
	end
end
