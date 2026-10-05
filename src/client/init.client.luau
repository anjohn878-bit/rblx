--!strict
-- Grow a Bird Garden - client entry point.

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes")).get()

local BirdRenderer = require(script.BirdRenderer)
local BirdpediaUI = require(script.BirdpediaUI)
local DevPanel = require(script.DevPanel)
local Hotbar = require(script.Hotbar)
local Hud = require(script.Hud)
local Objective = require(script.Objective)
local PlantLabels = require(script.PlantLabels)
local Prompts = require(script.Prompts)
local ShopUI = require(script.ShopUI)
local State = require(script.State)
local Toasts = require(script.Toasts)
local Ui = require(script.Ui)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Ask the server for everything we need (it replies once our garden is ready).
local init: any = nil
for _ = 1, 5 do
	local ok, result = pcall(function()
		return Remotes.Init:InvokeServer()
	end)
	if ok and result then
		init = result
		break
	end
	task.wait(2)
end
if not init then
	warn("[BirdGarden] Could not load game data from the server.")
	return
end

State.apply(init.state)
State.setStock(init.stock)

local gui = Ui.new("ScreenGui", {
	Name = "BirdGardenUI",
	ResetOnSpawn = false,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	DisplayOrder = 5,
	Parent = playerGui,
})

Toasts.init(gui)
Hud.init(gui, ShopUI.toggle, BirdpediaUI.toggle)
Objective.init(gui)
Hotbar.init(gui)
ShopUI.init(gui)
BirdpediaUI.init(gui)
DevPanel.init(gui)
PlantLabels.init()
Prompts.init()
BirdRenderer.init(init.visits)

Remotes.StateUpdate.OnClientEvent:Connect(State.apply)
Remotes.StockUpdate.OnClientEvent:Connect(State.setStock)
Remotes.Notify.OnClientEvent:Connect(Toasts.handle)
Remotes.BirdVisit.OnClientEvent:Connect(BirdRenderer.add)
Remotes.BirdCancel.OnClientEvent:Connect(BirdRenderer.remove)

-- The kiosk and the field-guide board in the plaza open the matching window.
ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt)
	if prompt.Name == "ShopPrompt" then
		ShopUI.open()
	elseif prompt.Name == "BirdpediaPrompt" then
		BirdpediaUI.open()
	end
end)

UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
	if not processed and input.KeyCode == Enum.KeyCode.B then
		BirdpediaUI.toggle()
	end
end)
