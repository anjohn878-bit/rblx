--[[
	Work as a Doctor - server entry point.
	Builds the world, starts every service and wires up the player lifecycle.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))

local Collision = require(script.Parent.Util.Collision)
local RateLimiter = require(script.Parent.Util.RateLimiter)
local RigBuilder = require(script.Parent.NPC.RigBuilder)
local Services = script.Parent.Services

local DataService = require(Services.DataService)
local DiagnosisService = require(Services.DiagnosisService)
local EconomyService = require(Services.EconomyService)
local HospitalService = require(Services.HospitalService)
local LeaderboardService = require(Services.LeaderboardService)
local PlotService = require(Services.PlotService)
local ShopService = require(Services.ShopService)
local WorldBuilder = require(Services.WorldBuilder)

local services = {
	DataService = DataService,
	DiagnosisService = DiagnosisService,
	EconomyService = EconomyService,
	HospitalService = HospitalService,
	LeaderboardService = LeaderboardService,
	PlotService = PlotService,
	ShopService = ShopService,
}

Remotes.Init()
Collision.Init()
RigBuilder.Init()
local world = WorldBuilder.Build()
PlotService.Init()
DataService.Init()
EconomyService.Init(services)
HospitalService.Init(services)
DiagnosisService.Init(services)
ShopService.Init(services)
LeaderboardService.Init(services, world.Boards)

-- Simple remotes ------------------------------------------------------------------

local miscLimiter = RateLimiter.new(1, 3)

Remotes.Function("GetState").OnServerInvoke = function(player: Player)
	return EconomyService.Snapshot(player)
end

Remotes.Event("TutorialAction").OnServerEvent:Connect(function(player: Player, action: any)
	if not miscLimiter:Check(player) then
		return
	end
	local data = DataService.Get(player)
	if data and (action == "Complete" or action == "Skip") then
		data.TutorialDone = true
		EconomyService.MarkDirty(player)
	end
end)

Remotes.Event("TeleportHome").OnServerEvent:Connect(function(player: Player)
	if not miscLimiter:Check(player) then
		return
	end
	local sim = HospitalService.Get(player)
	if sim then
		sim:TeleportOwnerHome()
	end
end)

-- Player lifecycle ------------------------------------------------------------------

local function onPlayerAdded(player: Player)
	local profile = DataService.Load(player)
	if not profile or not player.Parent then
		return
	end

	local plot = PlotService.Assign(player)
	if not plot then
		DataService.Release(player)
		player:Kick("This server's hospital plots are all taken! Please join another server.")
		return
	end

	EconomyService.SetupPlayer(player)
	local sim = HospitalService.Start(player, plot, profile.Data)

	local function onCharacter(character: Model)
		local root = character:WaitForChild("HumanoidRootPart", 10)
		if not root or not sim.Layout then
			return
		end
		task.wait(0.15)
		if character.Parent and not sim.Destroyed then
			character:PivotTo(sim.Layout.PlayerSpawn)
		end
	end
	player.CharacterAdded:Connect(onCharacter)
	if player.Character then
		task.spawn(onCharacter, player.Character)
	end

	EconomyService.SendState(player)
	if DataService.Enabled and not profile.CanSave then
		EconomyService.Notify(player, {
			Style = "Error",
			Text = "⚠️ We couldn't load your save, so progress this session won't be saved. Try rejoining later!",
		})
	end
	if profile.Data.TutorialDone then
		EconomyService.Notify(player, {
			Style = "Info",
			Text = "👋 Welcome back, Dr. " .. player.DisplayName .. "! Your patients missed you.",
		})
	end
end

local function onPlayerRemoving(player: Player)
	DiagnosisService.EndSession(player, false)
	HospitalService.Stop(player)
	PlotService.Release(player)
	task.spawn(LeaderboardService.PushPlayer, player)
	DataService.Release(player)
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)
for _, player in Players:GetPlayers() do
	task.spawn(onPlayerAdded, player)
end
