--[[
	Helpers shared by the end-to-end specs: boot a whole game (server scripts) against the mock engine,
	join players, hand out cash, take orders, drive to markers.
]]

local roblox = require("@lune/roblox")
local Mocks = require("./mocks")

local Vector3 = roblox.Vector3

local Game = {}

Game.SPAWN = Vector3.new(0, 3, 34)
local SPAWN = Game.SPAWN

-- Boots a fresh server. Returns the context plus handy handles.
function Game.boot(options)
	options = options or {}
	math.randomseed(12345)
	local ctx = Mocks.new()
	ctx.runtime.Game.BindToClose = function(_, callback)
		ctx.closeHandler = callback
	end
	if options.beforeBoot then
		options.beforeBoot(ctx)
	end
	ctx:run("ServerScriptService.Server.Main")

	local game = {
		ctx = ctx,
		Config = ctx:require("ReplicatedStorage.Shared.Config"),
		Economy = ctx:require("ReplicatedStorage.Shared.Economy"),
		Remotes = ctx:require("ReplicatedStorage.Shared.Remotes"),
		WorldBuilder = ctx:require("ServerScriptService.Server.WorldBuilder"),
		store = ctx.services.DataStoreService,
	}
	game.world = game.WorldBuilder.info(ctx.Workspace.Town)
	return game
end

-- Joins a player and makes them the "local" player for client->server remote calls.
function Game.join(g, name: string, userId: number)
	local player, character = g.ctx:join(name, userId, SPAWN)
	g.ctx.players.LocalPlayer = player
	return player, character
end

function Game.giveCash(g, player, amount: number, xp: number?)
	-- the profile is server-private; reach it the way the services do
	local PlayerService = g.ctx:require("ServerScriptService.Server.PlayerService")
	local profile = PlayerService.get(player)
	profile.Cash += amount
	profile.XP += xp or 0
	PlayerService.sync(player)
end

function Game.profileOf(g, player)
	return g.ctx:require("ServerScriptService.Server.PlayerService").get(player)
end

function Game.takeOrder(g, player)
	g.world.DispatchPrompt.Triggered:Fire(player)
	g.ctx:flush()
end

function Game.lastNotice(g, player)
	local calls = g.ctx:fired("Notify")
	for i = #calls, 1, -1 do
		if calls[i].Player == player then
			return calls[i].Args[1], calls[i].Args[2]
		end
	end
	return nil, nil
end

function Game.noticesContaining(g, text: string)
	local count = 0
	for _, call in g.ctx:fired("Notify") do
		if string.find(call.Args[1], text, 1, true) then
			count += 1
		end
	end
	return count
end

function Game.vehicleOf(g, player)
	for _, model in g.ctx.Workspace.Vehicles:GetChildren() do
		if model:GetAttribute("OwnerUserId") == player.UserId then
			return model
		end
	end
	return nil
end

-- Drives the player to the order's marker and returns once the delivery has been processed.
function Game.deliver(g, player, speed: number?)
	local dest = player:GetAttribute("OrderDest")
	g.ctx:teleport(player, dest + Vector3.new(0, 3, 0), speed or 0)
	g.ctx:advance(0.6)
end

-- Boots the server, joins "Alice" as the local player, and starts the client scripts.
function Game.bootClient(options)
	local g = Game.boot(options)
	local player = Game.join(g, "Alice", 1001)
	g.player = player
	g.ctx:setupClient(player)
	g.ctx:run("StarterPlayer.StarterPlayerScripts.Client.Main")
	g.gui = player.PlayerGui.DeliveryDriver
	return g
end

return Game
