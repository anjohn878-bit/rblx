--[[
	Delivery orders: take one at the dispatch desk, drive to the marker, hand it over.

	All rules live in Orders (what an order is, when it counts as delivered) and Economy (what it
	pays). This module just connects them to players, prompts and the client.

	Each player's active order is published as attributes so the client UI can simply react:
	  OrderId (0 = none), OrderAddress, OrderDest, OrderPackage, OrderDistance, OrderReward,
	  OrderStart, OrderTimeLimit, OrderDeadline   (times are Workspace:GetServerTimeNow() values)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Economy = require(ReplicatedStorage.Shared.Economy)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Orders = require(script.Parent.Orders)
local PlayerService = require(script.Parent.PlayerService)
local Profile = require(script.Parent.Profile)
local VehicleService = require(script.Parent.VehicleService)

local OrderService = {}

local TICK = 0.2
local SLOW_DOWN_COOLDOWN = 3
local RECENT_TO_AVOID = 3

local active = {} -- [Player] = order
local recentHouses = {} -- [Player] = { houseId, ... } most recent last
local lastSlowDownNotice = {} -- [Player] = os.clock()
local nextOrderId = 0
local world

local ORDER_ATTRIBUTES = {
	"OrderAddress",
	"OrderDest",
	"OrderPackage",
	"OrderDistance",
	"OrderReward",
	"OrderStart",
	"OrderTimeLimit",
	"OrderDeadline",
}

local function randomInt(a: number, b: number): number
	return math.random(a, b)
end

local function publish(player: Player, order)
	player:SetAttribute("OrderAddress", order.Address)
	player:SetAttribute("OrderDest", order.Dest)
	player:SetAttribute("OrderPackage", order.Package.Name)
	player:SetAttribute("OrderDistance", order.Distance)
	player:SetAttribute("OrderReward", order.BasePay)
	player:SetAttribute("OrderStart", order.StartTime)
	player:SetAttribute("OrderTimeLimit", order.TimeLimit)
	player:SetAttribute("OrderDeadline", order.StartTime + order.TimeLimit)
	player:SetAttribute("OrderId", order.Id) -- last: the client reacts to this one
end

local function clear(player: Player)
	active[player] = nil
	player:SetAttribute("OrderId", 0)
	for _, name in ORDER_ATTRIBUTES do
		player:SetAttribute(name, nil)
	end
end

local function rememberHouse(player: Player, houseId: number)
	local list = recentHouses[player] or {}
	table.insert(list, houseId)
	while #list > RECENT_TO_AVOID do
		table.remove(list, 1)
	end
	recentHouses[player] = list
end

local function avoidSet(player: Player)
	local set = {}
	for _, id in recentHouses[player] or {} do
		set[id] = true
	end
	return set
end

function OrderService.hasOrder(player: Player): boolean
	return active[player] ~= nil
end

function OrderService.take(player: Player)
	local profile = PlayerService.get(player)
	if not profile then
		return
	end
	if active[player] then
		PlayerService.notify(player, "Finish your current delivery first!", "warn")
		return
	end

	local vehicle = Config.VehicleById[profile.Equipped]
	local order = Orders.generate(world.Houses, world.DispatchPos, Profile.rankIndex(profile), vehicle, randomInt, avoidSet(player))
	nextOrderId += 1
	order.Id = nextOrderId
	order.StartTime = Workspace:GetServerTimeNow()
	active[player] = order
	publish(player, order)

	PlayerService.notify(player, string.format("New order: %s to %s. Follow the marker!", order.Package.Name, order.Address), "info")
	VehicleService.ensureVehicle(player)
end

local function complete(player: Player, order, elapsed: number)
	local profile = PlayerService.get(player)
	if not profile then
		clear(player)
		return
	end

	local result = Economy.settle(order, elapsed, profile.Streak)
	Profile.recordDelivery(profile, result.OnTime)
	local summary = PlayerService.award(player, result.Total, result.XP)
	rememberHouse(player, order.HouseId)
	clear(player)

	Remotes.DeliveryResult:FireClient(player, {
		Address = order.Address,
		Package = order.Package.Name,
		OnTime = result.OnTime,
		Stars = result.Stars,
		Base = result.Base,
		TimeBonus = result.TimeBonus,
		Tip = result.Tip,
		StreakBonus = result.StreakBonus,
		Total = result.Total,
		XP = result.XP,
		Streak = profile.Streak,
		Position = order.Dest,
		RankedUpTo = summary and summary.RankedUp and Config.Ranks[summary.NewRank].Name or nil,
	})
end

local function fail(player: Player)
	local profile = PlayerService.get(player)
	if profile then
		Profile.breakStreak(profile)
		PlayerService.sync(player)
	end
	clear(player)
	PlayerService.notify(player, "The customer gave up waiting and cancelled the order.", "error")
end

function OrderService.cancel(player: Player)
	if not active[player] then
		return
	end
	local profile = PlayerService.get(player)
	if profile then
		Profile.breakStreak(profile)
		PlayerService.sync(player)
	end
	clear(player)
	PlayerService.notify(player, "Order cancelled.", "warn")
end

local function tick()
	local now = Workspace:GetServerTimeNow()
	for player, order in active do
		local elapsed = now - order.StartTime
		if Orders.status(order, elapsed) == "failed" then
			fail(player)
		else
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			if root and humanoid and humanoid.Health > 0 then
				local verdict = Orders.checkArrival(order, root.Position, root.AssemblyLinearVelocity.Magnitude, elapsed)
				if verdict == "deliver" then
					complete(player, order, elapsed)
				elseif verdict == "toofast" then
					local last = lastSlowDownNotice[player]
					if not last or os.clock() - last > SLOW_DOWN_COOLDOWN then
						lastSlowDownNotice[player] = os.clock()
						PlayerService.notify(player, "Slow down to hand over the package!", "warn")
					end
				end
			end
		end
	end
end

function OrderService.start(worldInfo)
	world = worldInfo

	world.DispatchPrompt.Triggered:Connect(function(player)
		OrderService.take(player)
	end)

	Remotes.CancelOrder.OnServerEvent:Connect(function(player)
		OrderService.cancel(player)
	end)

	Players.PlayerAdded:Connect(function(player)
		player:SetAttribute("OrderId", 0)
	end)
	for _, player in Players:GetPlayers() do
		player:SetAttribute("OrderId", 0)
	end

	Players.PlayerRemoving:Connect(function(player)
		active[player] = nil
		recentHouses[player] = nil
		lastSlowDownNotice[player] = nil
	end)

	task.spawn(function()
		while true do
			task.wait(TICK)
			tick()
		end
	end)
end

return OrderService
