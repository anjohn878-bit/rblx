--[[
	Server entry point for "Become a Delivery Driver".

	Order matters: Remotes first (creates the RemoteEvents), then the town, then the services
	that rely on both.
]]

local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
require(Shared.Remotes)

local GarageService = require(script.Parent.GarageService)
local OrderService = require(script.Parent.OrderService)
local PlayerService = require(script.Parent.PlayerService)
local VehicleService = require(script.Parent.VehicleService)
local WorldBuilder = require(script.Parent.WorldBuilder)

local Config = require(Shared.Config)
for property, value in Config.Lighting do
	Lighting[property] = value
end

-- The place ships with the town baked in. If it's missing (e.g. scripts synced into an empty place), build it now.
local town = Workspace:FindFirstChild("Town")
if not town then
	town = WorldBuilder.build(Workspace)
end

-- The default template's baseplate and spawn would sit inside our ground.
for _, name in { "Baseplate", "SpawnLocation" } do
	local leftover = Workspace:FindFirstChild(name)
	if leftover then
		leftover:Destroy()
	end
end

local world = WorldBuilder.info(town)

PlayerService.start()
VehicleService.start()
OrderService.start(world)
GarageService.start(world)
