-- Become a Delivery Driver: server entry point.
-- Builds the town, then wires up saving, characters, vehicles and parcel jobs.

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local CityBuilder = require(script.CityBuilder)
local Characters = require(script.Characters)
local Jobs = require(script.Jobs)
local PlayerData = require(script.PlayerData)
local Vehicles = require(script.Vehicles)

local registry = CityBuilder.build()

PlayerData.init(registry.Depot.Counter)
Characters.init()
Vehicles.init(registry)
Jobs.init(registry)

-- Day and night: the street lights come on after sunset, and nights pass twice as fast as days
-- (12 daylight hours at 1x plus 12 night hours at 2x = 18 "day-speed" hours per cycle).
Lighting.ClockTime = 9
task.spawn(function()
	local dayRate = 18 / (Config.DayLengthMinutes * 60) -- in-game hours per real second
	local lightsOn: boolean? = nil
	while true do
		local dt = task.wait(0.5)
		local night = Lighting.ClockTime >= 18.25 or Lighting.ClockTime < 6.25
		local rate = if night then dayRate * 2 else dayRate
		Lighting.ClockTime = (Lighting.ClockTime + dt * rate) % 24
		if night ~= lightsOn then
			lightsOn = night
			for _, bulb in registry.StreetLights do
				bulb.Material = if night then Enum.Material.Neon else Enum.Material.SmoothPlastic
				local light = bulb:FindFirstChildOfClass("PointLight")
				if light then
					light.Enabled = night
				end
			end
		end
	end
end)

print(string.format("[%s] %s is open for business: %d addresses to deliver to.", Config.GameName, Config.CityName, #registry.Addresses))
