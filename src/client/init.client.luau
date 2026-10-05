-- Become a Delivery Driver: client entry point. Receives state from the server and keeps the
-- HUD, garage, waypoints and driving controller in sync with it.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local Driving = require(script.Driving)
local Hud = require(script.Hud)
local Shop = require(script.Shop)
local Waypoints = require(script.Waypoints)

local state = nil
local welcomed = false

local function apply(newState)
	if type(newState) ~= "table" then
		return
	end
	state = newState
	Waypoints.update(state)
	Hud.update(state)
	Shop.update(state)

	if not welcomed then
		welcomed = true
		if state.Deliveries == 0 then
			Hud.banner(string.upper(Config.GameName), "Welcome to " .. Config.CityName .. "! Load packages at the counter and deliver them around town.")
		else
			Hud.toast("Welcome back, " .. state.RankName .. "!", "success")
		end
	end
end

Driving.init()
Waypoints.init()
Shop.init(Hud.toast)
Hud.init({
	onGarage = Shop.toggle,
	onSpawn = function()
		Remotes.SpawnVehicle:FireServer()
	end,
	onSelectJob = Waypoints.select,
	getTarget = Waypoints.getTarget,
	getSelectedId = Waypoints.selectedId,
	isDriving = Driving.isDriving,
	getSpeed = Driving.getSpeed,
})

Remotes.StateChanged.OnClientEvent:Connect(apply)
Remotes.OpenShop.OnClientEvent:Connect(Shop.open)
Remotes.Notify.OnClientEvent:Connect(function(text, kind, position)
	if kind == "rank" then
		Hud.banner("PROMOTED!", text)
		Waypoints.celebrate(nil)
	else
		Hud.toast(text, kind)
	end
	if kind == "delivered" then
		Waypoints.celebrate(position)
	end
end)

task.spawn(function()
	local initial = Remotes.GetState:InvokeServer()
	if initial and not state then
		apply(initial)
	end
end)

RunService.RenderStepped:Connect(function()
	if state then
		Waypoints.tick()
		Hud.tick(state)
	end
end)

-- Close the garage if the character respawns.
Players.LocalPlayer.CharacterAdded:Connect(function()
	Shop.close()
end)
