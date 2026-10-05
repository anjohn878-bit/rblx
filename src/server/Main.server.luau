--[[
	Ice Skating Simulator - server entry point.
	Makes sure the map exists, then starts every service.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
require(Shared.Remotes) -- creates the RemoteEvents before any client asks for them

local Services = script.Parent:WaitForChild("Services")

-- The map is normally baked into the place file; build it if it's missing.
if not workspace:FindFirstChild("Map") then
	require(Services.WorldBuilder).build(Config)
end

local order = {
	"DataService",
	"SkaterService",
	"TrickService",
	"ShopService",
	"CollectibleService",
	"LeaderboardService",
}

for _, name in order do
	require(Services[name]).init()
end
