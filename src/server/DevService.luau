--!strict
-- Studio-only cheats so the whole progression can be tested in minutes.
-- Ignored completely on live servers.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes")).get()
local Seeds = require(Shared:WaitForChild("Seeds"))

local DataService = require(script.Parent.DataService)
local GardenService = require(script.Parent.GardenService)
local PlantService = require(script.Parent.PlantService)
local ShopService = require(script.Parent.ShopService)

local DevService = {}

function DevService.init()
	if not RunService:IsStudio() then
		return
	end
	Remotes.Dev.OnServerEvent:Connect(function(player: Player, action: any)
		local profile = DataService.get(player)
		if not profile or type(action) ~= "string" then
			return
		end
		if action == "feathers" then
			profile.feathers += 100000
		elseif action == "seeds" then
			for _, seed in Seeds.list do
				profile.seeds[seed.id] = (profile.seeds[seed.id] or 0) + 5
			end
		elseif action == "grow" then
			PlantService.growAll(player)
		elseif action == "plots" then
			profile.plots = Config.MAX_PLOTS
			GardenService.refreshPlots(player, profile.plots)
		elseif action == "stock" then
			ShopService.devFillStock()
		end
		DataService.push(player)
	end)
end

return DevService
