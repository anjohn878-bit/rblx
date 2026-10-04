--[[
	Server bootstrap. Init() every service in dependency order (create state,
	no cross-service calls), then Start() them (connect events, start loops).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
Remotes.Init()

local Services = script.Parent:WaitForChild("Services")

local order = {
	"DataService",
	"ProgressionService",
	"InventoryService",
	"MapBuilder",
	"BallService",
	"BotService",
	"MatchService",
	"MatchmakingService",
	"LeaderboardService",
	"AmbientService",
}

local loaded = {}
for _, name in order do
	loaded[name] = require(Services:WaitForChild(name))
end
for _, name in order do
	loaded[name].Init()
end
for _, name in order do
	local ok, err = pcall(loaded[name].Start)
	if not ok then
		warn(string.format("[Main] %s failed to start: %s", name, tostring(err)))
	end
end

print("[Concrete Kings] server ready")
