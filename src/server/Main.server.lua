-- Grow a Bird Garden: server entry point.
-- Buy seeds, plant them, wait for them to grow, and befriend the birds they
-- attract. Better seeds take longer to grow but attract rarer birds.
-- Befriended birds become pets: they roam your garden giving perks, can be
-- bred into families, sold for coins and traded with other players.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Util = require(Shared.Util)

local BirdService = require(script.Parent.BirdService)
local DataService = require(script.Parent.DataService)
local NestService = require(script.Parent.NestService)
local PetService = require(script.Parent.PetService)
local PlotService = require(script.Parent.PlotService)
local ShopService = require(script.Parent.ShopService)
local TradeService = require(script.Parent.TradeService)
local WorldBuilder = require(script.Parent.WorldBuilder)

local world = WorldBuilder.Build()
BirdService.Init(world.BirdsFolder)
PlotService.Init(world.Plots)
ShopService.Init()
PetService.Init()
PetService.SeedsChanged = PlotService.UpdatePlantPrompts
PetService.IsInTrade = TradeService.IsOffered
PetService.OnChanged(TradeService.Revalidate)

local loaded = {} -- [Player] = true once their save has loaded

world.ShopPrompt.Triggered:Connect(function(player)
	Net.OpenShop:FireClient(player)
end)

------------------------------------------------------------------------------
-- Players

local function onCharacterAdded(player, character)
	local root = character:WaitForChild("HumanoidRootPart", 10)
	if not root then
		return
	end
	task.wait() -- let the default spawn finish before moving them
	PlotService.TeleportToPlot(player)
end

local function onPlayerAdded(player)
	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	local coins = Instance.new("IntValue")
	coins.Name = "Coins"
	coins.Parent = leaderstats
	local birds = Instance.new("IntValue")
	birds.Name = "Birds"
	birds.Parent = leaderstats
	leaderstats.Parent = player

	local plot = PlotService.Assign(player)
	if plot then
		NestService.SetupPlot(player)
	else
		Net.Notify:FireClient(player, "Every garden on this server is taken, sorry! Try another server.", "Error")
	end

	player.CharacterAdded:Connect(function(character)
		onCharacterAdded(player, character)
	end)
	if player.Character then
		task.spawn(onCharacterAdded, player, player.Character)
	end

	if not DataService.Load(player) or player.Parent ~= Players then
		-- left while their data was loading: nothing changed, just free the save lock
		DataService.Release(player)
		return
	end

	DataService.EnsureSelection(player)
	PlotService.LoadPlants(player)
	PlotService.EnsureNotStuck(player)
	loaded[player] = true
	PetService.PlayerLoaded(player)
	NestService.UpdateVisuals(player)
	DataService.Push(player)
	Net.ShopUpdated:FireClient(player, ShopService.Snapshot(player))
	Net.Notify:FireClient(
		player,
		"Welcome to your Bird Garden! Plant seeds, befriend the birds that visit, and sell spares for coins. 🐦",
		"Success"
	)
end

local function onPlayerRemoving(player)
	loaded[player] = nil
	TradeService.PlayerLeft(player)
	NestService.ClearPlot(player)
	PetService.PlayerLeft(player)
	PlotService.Release(player)
	DataService.Release(player)
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)
for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(onPlayerAdded, player)
end

game:BindToClose(function()
	DataService.SaveAll()
end)

------------------------------------------------------------------------------
-- Remotes

Net.GetState.OnServerInvoke = function(player)
	local deadline = os.clock() + 20
	while not loaded[player] and player.Parent == Players and os.clock() < deadline do
		task.wait(0.2)
	end
	return DataService.Snapshot(player)
end

Net.GetShop.OnServerInvoke = function(player)
	return ShopService.Snapshot(player)
end

Net.BuySeed.OnServerInvoke = function(player, seedId)
	if not loaded[player] then
		return false, "Your garden is still loading..."
	end
	local ok, message = ShopService.Buy(player, seedId)
	if ok then
		PlotService.UpdatePlantPrompts(player)
	end
	return ok, message
end

Net.SelectSeed.OnServerEvent:Connect(function(player, seedId)
	local profile = DataService.GetProfile(player)
	if not profile or type(seedId) ~= "string" then
		return
	end
	if (profile.Data.Seeds[seedId] or 0) > 0 then
		profile.SelectedSeed = seedId
		PlotService.UpdatePlantPrompts(player)
		DataService.Push(player)
	end
end)

Net.PetAction.OnServerInvoke = function(player, action, a, b, c)
	if not loaded[player] then
		return false, "Your garden is still loading..."
	end
	if action == "Equip" then
		return PetService.Equip(player, a)
	elseif action == "Unequip" then
		return PetService.Unequip(player, a)
	elseif action == "Favorite" then
		return PetService.SetFavorite(player, a, b == true)
	elseif action == "Sell" then
		return PetService.Sell(player, a)
	elseif action == "EquipBest" then
		return PetService.EquipBest(player)
	elseif action == "SellBulk" then
		return PetService.SellBulk(player, a)
	elseif action == "Breed" then
		return NestService.StartBreeding(player, a, b, c)
	elseif action == "CancelNest" then
		return NestService.Cancel(player, a)
	end
	return false, "Unknown action."
end

Net.TradeRequest.OnServerEvent:Connect(function(player, targetUserId)
	if loaded[player] then
		TradeService.Request(player, targetUserId)
	end
end)

Net.TradeRespond.OnServerEvent:Connect(function(player, fromUserId, accept)
	if loaded[player] then
		TradeService.Respond(player, fromUserId, accept)
	end
end)

Net.TradeUpdate.OnServerEvent:Connect(function(player, action, value)
	if loaded[player] then
		TradeService.Update(player, action, value)
	end
end)

Net.Teleport.OnServerEvent:Connect(function(player, target)
	if target == "Garden" then
		PlotService.TeleportToPlot(player)
	elseif target == "Shop" then
		local character = player.Character
		if character and character.PrimaryPart then
			character:PivotTo(world.ShopTeleport)
		end
	end
end)

------------------------------------------------------------------------------
-- Game loop

task.spawn(function()
	while true do
		local now = Util.Now()
		local ok, err = pcall(PlotService.Tick, now)
		if not ok then
			warn("[BirdGarden] Plot tick failed:", err)
		end
		for name, tick in pairs({
			Shop = ShopService.Tick,
			Pet = PetService.Tick,
			Nest = NestService.Tick,
			Trade = TradeService.Tick,
		}) do
			ok, err = pcall(tick, now)
			if not ok then
				warn("[BirdGarden] " .. name .. " tick failed:", err)
			end
		end
		task.wait(0.5)
	end
end)

task.spawn(function()
	while true do
		task.wait(Config.AutosaveInterval)
		for player in pairs(loaded) do
			task.spawn(DataService.Save, player)
		end
	end
end)
