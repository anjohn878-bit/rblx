--[[
	Client entry point: builds the UI, wires it to the state the server publishes, and starts the
	vehicle scripts. See the other modules in this folder for the details.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)

local GarageUI = require(script.Parent.GarageUI)
local Hud = require(script.Parent.Hud)
local OrderPanel = require(script.Parent.OrderPanel)
local Splash = require(script.Parent.Splash)
local State = require(script.Parent.State)
local UIKit = require(script.Parent.UIKit)
local VehicleController = require(script.Parent.VehicleController)
local VehicleVisuals = require(script.Parent.VehicleVisuals)
local Waypoint = require(script.Parent.Waypoint)

UIKit.watchViewport()
local gui = UIKit.createGui("DeliveryDriver")

-- Build the UI. Garage and hud both need to open/toast, so create the panel first.
local orders = OrderPanel.build(gui)
local garage = GarageUI.build(gui, { toast = orders.toast })
local hud = Hud.build(gui, { openGarage = garage.toggle })
local waypoint = Waypoint.build(gui)
Splash.build(gui)

-- Where should the arrow point? At the order if there is one, otherwise back to the depot.
local town = Workspace:WaitForChild("Town")
local dispatchPosition = town:GetAttribute("DispatchPos")

local function refreshGuidance()
	if State.get("OrderId", 0) > 0 then
		local destination = State.get("OrderDest")
		if destination then
			waypoint.setTarget({ Position = destination, Label = State.get("OrderAddress", ""), HideWithin = 0 }, true)
			hud.setObjective("Drive to the glowing ring and slow down to deliver")
			return
		end
	end
	waypoint.setTarget({ Position = dispatchPosition, Label = "DISPATCH DEPOT", HideWithin = 20 }, false)
	if State.get("Deliveries", 0) == 0 then
		hud.setObjective("Head to the DISPATCH counter and press E to take an order")
	else
		hud.setObjective("Head back to the depot for your next order")
	end
end
State.watch("OrderId", refreshGuidance)
State.watch("Deliveries", refreshGuidance)

-- Server events.
Remotes.Notify.OnClientEvent:Connect(orders.toast)
Remotes.OpenGarage.OnClientEvent:Connect(garage.open)
Remotes.DeliveryResult.OnClientEvent:Connect(function(result)
	orders.showResult(result)
	if result.Position then
		waypoint.celebrate(result.Position)
	end
end)

-- Press V to call your vehicle (the HUD button does the same for touch/gamepad).
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end
	if input.KeyCode == Enum.KeyCode.V then
		Remotes.CallVehicle:FireServer()
	end
end)

VehicleController.start()
VehicleVisuals.start()
