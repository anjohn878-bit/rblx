--!strict
-- Grow a Bird Garden - server entry point.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes")).get() -- creates every remote first

local BirdService = require(script.BirdService)
local DataService = require(script.DataService)
local DevService = require(script.DevService)
local GardenService = require(script.GardenService)
local PlantService = require(script.PlantService)
local ShopService = require(script.ShopService)
local Throttle = require(script.Throttle)
local WorldBuilder = require(script.WorldBuilder)

local ready: { [Player]: boolean } = {}
local joining: { [Player]: boolean } = {}

-- Remote handlers are assigned before the world is built, so a client that
-- connects while the map is still being generated never calls an empty handler.
-- (Everything they touch only becomes reachable once `ready[player]` is set.)

-- The client asks for everything it needs once it has loaded.
Remotes.Init.OnServerInvoke = function(player: Player)
	local deadline = os.clock() + 30
	while not ready[player] and player.Parent == Players and os.clock() < deadline do
		task.wait(0.1)
	end
	local profile = DataService.get(player)
	if not ready[player] or not profile then
		return nil
	end
	return {
		state = DataService.snapshot(profile),
		stock = ShopService.getStock(),
		visits = BirdService.activeVisits(),
	}
end

Remotes.PlantSeed.OnServerEvent:Connect(function(player: Player, plotIndex: any, seedId: any)
	if ready[player] and Throttle.ok(player, "plant", 0.1) then
		PlantService.plant(player, plotIndex, seedId)
	end
end)

Remotes.DigPlant.OnServerEvent:Connect(function(player: Player, plotIndex: any)
	if ready[player] and Throttle.ok(player, "dig", 0.2) then
		PlantService.dig(player, plotIndex)
	end
end)

Remotes.BuySeed.OnServerInvoke = function(player: Player, seedId: any, amount: any)
	if not ready[player] or not Throttle.ok(player, "buy", 0.1) then
		return { ok = false, message = "Slow down a little!" }
	end
	return ShopService.buySeed(player, seedId, amount)
end

Remotes.UnlockPlot.OnServerInvoke = function(player: Player)
	if not ready[player] or not Throttle.ok(player, "unlock", 0.3) then
		return { ok = false, message = "Slow down a little!" }
	end
	return ShopService.unlockPlot(player)
end

local world = WorldBuilder.build()
GardenService.init(world)
PlantService.init(world)
ShopService.init()
DevService.init()
DataService.startAutosave()

local function onJoin(player: Player)
	if joining[player] then
		return
	end
	joining[player] = true

	player.CharacterAdded:Connect(function()
		if ready[player] then
			GardenService.placeCharacter(player)
		end
	end)

	local profile = DataService.load(player)
	if not profile or player.Parent ~= Players then
		return
	end

	local garden = GardenService.assign(player)
	if not garden then
		player:Kick("Every garden on this server is taken. Please join another server!")
		return
	end

	DataService.attach(player)
	GardenService.refreshPlots(player, profile.plots)
	PlantService.loadPlayer(player, profile)
	DataService.rescue(player)
	ready[player] = true
	GardenService.placeCharacter(player)
end

local function onLeave(player: Player)
	ready[player] = nil
	joining[player] = nil
	PlantService.clearPlayer(player)
	GardenService.release(player)
	DataService.save(player)
	DataService.release(player)
end

Players.PlayerAdded:Connect(onJoin)
Players.PlayerRemoving:Connect(onLeave)
for _, player in Players:GetPlayers() do
	task.spawn(onJoin, player)
end

game:BindToClose(function()
	DataService.saveAll()
end)
