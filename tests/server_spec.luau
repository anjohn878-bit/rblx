--[[
	End-to-end server tests: boots the real Main.server script against the mock engine and plays
	through joining, ordering, delivering, driving, shopping and saving in virtual time.
]]

local roblox = require("@lune/roblox")
local Mocks = require("./mocks")

local Vector3, CFrame = roblox.Vector3, roblox.CFrame

local Game = require("./game")

local SPAWN = Game.SPAWN
local boot, join, giveCash, profileOf = Game.boot, Game.join, Game.giveCash, Game.profileOf
local takeOrder, lastNotice, noticesContaining, vehicleOf, deliver = Game.takeOrder, Game.lastNotice, Game.noticesContaining, Game.vehicleOf, Game.deliver

return function(T)
	-- Boot ----------------------------------------------------------------------------

	T.test("boot: remotes, town, vehicles folder, collision groups and lighting are set up", function()
		local g = boot()
		local ctx = g.ctx
		local folder = ctx.DataModel:GetService("ReplicatedStorage"):FindFirstChild("Remotes")
		T.truthy(folder)
		for _, name in { "Notify", "DeliveryResult", "OpenGarage", "CallVehicle", "CancelOrder" } do
			T.eq(folder:FindFirstChild(name).ClassName, "RemoteEvent", name)
		end
		T.eq(folder:FindFirstChild("GarageRequest").ClassName, "RemoteFunction")

		T.truthy(ctx.Workspace:FindFirstChild("Town"))
		T.truthy(ctx.Workspace:FindFirstChild("Vehicles"))
		T.eq(#g.world.Houses, 144)
		T.truthy(ctx.services.PhysicsService.Groups.Vehicles and ctx.services.PhysicsService.Groups.Characters)
		T.eq(ctx.services.PhysicsService.Collidable["Vehicles|Characters"], false)
		T.near(ctx.DataModel:GetService("Lighting").ClockTime, g.Config.Lighting.ClockTime, 1e-4)
	end)

	T.test("boot: the template baseplate and spawn are removed if present", function()
		local g = boot({
			beforeBoot = function(ctx)
				for _, name in { "Baseplate", "SpawnLocation" } do
					local part = roblox.Instance.new("Part")
					part.Name = name
					part.Parent = ctx.Workspace
				end
			end,
		})
		T.falsy(g.ctx.Workspace:FindFirstChild("Baseplate"))
		T.falsy(g.ctx.Workspace:FindFirstChild("SpawnLocation"))
	end)

	T.test("boot: an already-baked town is reused, not rebuilt", function()
		local baked
		local g = boot({
			beforeBoot = function(ctx)
				baked = ctx:require("ServerScriptService.Server.WorldBuilder").build(ctx.Workspace)
			end,
		})
		T.eq(g.ctx.Workspace.Town, baked)
		local towns = 0
		for _, child in g.ctx.Workspace:GetChildren() do
			if child.Name == "Town" then
				towns += 1
			end
		end
		T.eq(towns, 1)
	end)

	-- Joining -------------------------------------------------------------------------------

	T.test("join: a new player gets a default profile, published as attributes and leaderstats", function()
		local g = boot()
		local player = join(g, "Alice", 1001)
		T.eq(player:GetAttribute("Loaded"), true)
		T.eq(player:GetAttribute("Cash"), 0)
		T.eq(player:GetAttribute("XP"), 0)
		T.eq(player:GetAttribute("RankIndex"), 1)
		T.eq(player:GetAttribute("RankName"), "Rookie")
		T.eq(player:GetAttribute("RankXPStart"), 0)
		T.eq(player:GetAttribute("RankXPNext"), 120)
		T.eq(player:GetAttribute("Deliveries"), 0)
		T.eq(player:GetAttribute("Streak"), 0)
		T.eq(player:GetAttribute("Equipped"), "Scooter")
		T.eq(player:GetAttribute("Owned"), ",Scooter,")
		T.eq(player:GetAttribute("OrderId"), 0)

		local stats = player:FindFirstChild("leaderstats")
		T.eq(stats.Cash.Value, 0)
		T.eq(stats.Deliveries.Value, 0)
		T.eq(stats.Rank.Value, "Rookie")
	end)

	T.test("join: the character is put in the Characters collision group (including late accessories)", function()
		local g = boot()
		local _, character = join(g, "Alice", 1001)
		T.eq(character.HumanoidRootPart.CollisionGroup, "Characters")
		local hat = roblox.Instance.new("Part")
		hat.Name = "Hat"
		hat.Parent = character
		character.DescendantAdded:Fire(hat) -- the engine would fire this when the accessory loads in
		T.eq(hat.CollisionGroup, "Characters")
	end)

	T.test("join: saved progress is restored", function()
		local g = boot()
		g.store.Data[g.Config.DataStoreName] = {
			Player_1002 = {
				Cash = 321,
				XP = 200,
				Deliveries = 14,
				Owned = { Scooter = true, Hatchback = true },
				Equipped = "Hatchback",
				BestStreak = 6,
				TotalEarned = 999,
			},
		}
		local player = join(g, "Bob", 1002)
		T.eq(player:GetAttribute("Cash"), 321)
		T.eq(player:GetAttribute("RankIndex"), 2)
		T.eq(player:GetAttribute("RankName"), "Courier")
		T.eq(player:GetAttribute("Equipped"), "Hatchback")
		T.eq(player:GetAttribute("Owned"), ",Hatchback,Scooter,")
		T.eq(player:GetAttribute("Deliveries"), 14)
		T.eq(player.leaderstats.Cash.Value, 321)
	end)

	T.test("join: a failed load gives a temporary profile, warns the player and never overwrites their save", function()
		local g = boot()
		g.store.Data[g.Config.DataStoreName] = { Player_1003 = { Cash = 5000 } }
		g.store.FailGets = true
		local player, joined
		-- joining retries with waits, so it has to run as a task
		g.ctx.scheduler.task.spawn(function()
			player = g.ctx:newPlayer("Carol", 1003)
			g.ctx.players.PlayerAdded:Fire(player)
			joined = true
		end)
		g.ctx:advance(10)
		T.truthy(joined)
		T.eq(g.store.GetCalls, 3, "load is retried three times")
		T.eq(player:GetAttribute("Loaded"), true, "the game is still playable")
		T.eq(player:GetAttribute("Cash"), 0)
		T.truthy(noticesContaining(g, "progress won't be saved") == 1)

		g.store.FailGets = false
		g.ctx:leave(player)
		T.eq(g.store.WriteCalls, 0, "a temporary profile must never be written")
		T.eq(g.store.Data[g.Config.DataStoreName].Player_1003.Cash, 5000)
	end)

	T.test("join: Studio without API access doesn't retry or delay, and still plays", function()
		local g = boot()
		g.store.FailGets = true
		g.store.Error = "StudioAccessToApisNotAllowed: 403: Studio access to APIs is not allowed"
		local player = join(g, "Dan", 1004)
		T.eq(g.store.GetCalls, 1)
		T.eq(player:GetAttribute("Loaded"), true)
	end)

	-- Orders --------------------------------------------------------------------------------

	T.test("order: taking one publishes everything the HUD needs and puts you in your vehicle", function()
		local g = boot()
		local player = join(g, "Alice", 1001)
		T.falsy(vehicleOf(g, player))
		takeOrder(g, player)

		T.truthy(player:GetAttribute("OrderId") > 0)
		local address = player:GetAttribute("OrderAddress")
		local house
		for _, h in g.world.Houses do
			if h.Address == address then
				house = h
			end
		end
		T.truthy(house, "address " .. tostring(address) .. " must belong to a real house")
		T.eq(player:GetAttribute("OrderDest"), house.MarkerPos)
		local rank = g.Config.Ranks[1]
		local distance = player:GetAttribute("OrderDistance")
		T.eq(distance, g.Economy.routeDistance(g.world.DispatchPos, house.MarkerPos))
		T.truthy(distance >= rank.MinDist and distance <= rank.MaxDist)
		T.eq(player:GetAttribute("OrderDeadline"), player:GetAttribute("OrderStart") + player:GetAttribute("OrderTimeLimit"))
		T.truthy(player:GetAttribute("OrderReward") > 0)
		T.truthy(player:GetAttribute("OrderPackage"))
		T.truthy(noticesContaining(g, "New order") == 1)

		local vehicle = vehicleOf(g, player)
		T.truthy(vehicle, "taking an order brings your vehicle")
		T.eq(vehicle:GetAttribute("VehicleId"), "Scooter")
		T.eq(player.Character.Humanoid.SeatPart, vehicle.Seat)
		T.falsy(vehicle.PrimaryPart.Anchored, "unparked while driven")
		T.eq(g.ctx.NetworkOwners[vehicle.PrimaryPart], player)
		T.eq(vehicle:GetAttribute("Occupied"), true)
		T.truthy(g.ctx.services.CollectionService:HasTag(vehicle, "DeliveryVehicle"))
		T.eq(vehicle.PrimaryPart.CollisionGroup, "Vehicles")
		T.eq(vehicle.Seat.CollisionGroup, "Vehicles")
	end)

	T.test("order: the vehicle appears on the ground in front of the player, facing the same way", function()
		local g = boot()
		local player = join(g, "Alice", 1001)
		takeOrder(g, player)
		local vehicle = vehicleOf(g, player)
		local chassis = vehicle.PrimaryPart
		local hullHalf = vehicle:GetAttribute("HullHalfHeight")
		T.near(chassis.CFrame.Position.Y, 0.1 + hullHalf + 0.05, 1e-3, "resting on the road")
		T.near(chassis.CFrame.UpVector.Y, 1, 1e-4)
		-- player stands at SPAWN looking -Z; the car should be ahead (more negative z)
		T.truthy(chassis.CFrame.Position.Z < SPAWN.Z - 4, "car z = " .. chassis.CFrame.Position.Z)
		T.near(chassis.CFrame.LookVector.Z, -1, 1e-3)
	end)

	T.test("order: you can only hold one at a time", function()
		local g = boot()
		local player = join(g, "Alice", 1001)
		takeOrder(g, player)
		local id, address = player:GetAttribute("OrderId"), player:GetAttribute("OrderAddress")
		takeOrder(g, player)
		T.eq(player:GetAttribute("OrderId"), id)
		T.eq(player:GetAttribute("OrderAddress"), address)
		T.eq((lastNotice(g, player)), "Finish your current delivery first!")
	end)

	T.test("order: delivering pays out, awards XP, extends the streak and clears the order", function()
		local g = boot()
		local player = join(g, "Alice", 1001)
		takeOrder(g, player)
		local reward = player:GetAttribute("OrderReward")
		local limit = player:GetAttribute("OrderTimeLimit")
		local distance = player:GetAttribute("OrderDistance")
		local address = player:GetAttribute("OrderAddress")

		g.ctx:advance(5)
		deliver(g, player, 10)

		T.eq(player:GetAttribute("OrderId"), 0)
		T.eq(player:GetAttribute("OrderAddress"), nil)
		T.eq(player:GetAttribute("OrderDest"), nil)

		local results = g.ctx:fired("DeliveryResult")
		T.eq(#results, 1)
		local r = results[1].Args[1]
		local expected = g.Economy.settle({ Distance = distance, TimeLimit = limit, BasePay = reward }, r.Total and 5.6 or 0, 0)
		T.eq(r.Address, address)
		T.eq(r.Base, reward)
		T.eq(r.OnTime, true)
		T.eq(r.Stars, expected.Stars)
		T.eq(r.Total, r.Base + r.TimeBonus + r.Tip + r.StreakBonus)
		T.eq(r.Streak, 1)
		T.truthy(r.Position)

		T.eq(player:GetAttribute("Cash"), r.Total)
		T.eq(player:GetAttribute("XP"), r.XP)
		T.eq(player:GetAttribute("Deliveries"), 1)
		T.eq(player:GetAttribute("Streak"), 1)
		T.eq(player.leaderstats.Cash.Value, r.Total)
		T.eq(player.leaderstats.Deliveries.Value, 1)
	end)

	T.test("order: a second on-time delivery earns a streak bonus", function()
		local g = boot()
		local player = join(g, "Alice", 1001)
		takeOrder(g, player)
		g.ctx:advance(4)
		deliver(g, player, 0)
		takeOrder(g, player)
		T.truthy(player:GetAttribute("OrderId") > 0)
		g.ctx:advance(4)
		deliver(g, player, 0)

		local results = g.ctx:fired("DeliveryResult")
		T.eq(#results, 2)
		T.eq(results[1].Args[1].StreakBonus, 0)
		T.truthy(results[2].Args[1].StreakBonus > 0, "second delivery should include a streak bonus")
		T.eq(results[2].Args[1].Streak, 2)
		T.eq(player:GetAttribute("Streak"), 2)
	end)

	T.test("order: arriving too fast asks you to slow down (not spammed) and delivers once you do", function()
		local g = boot()
		local player = join(g, "Alice", 1001)
		takeOrder(g, player)
		g.ctx:advance(4)
		local dest = player:GetAttribute("OrderDest")
		g.ctx:teleport(player, dest + Vector3.new(0, 3, 0), g.Config.DeliveryMaxSpeed + 20)
		g.ctx:advance(2)
		T.eq(player:GetAttribute("OrderId") > 0, true, "still active")
		T.eq(noticesContaining(g, "Slow down"), 1, "told once, not every tick")
		g.ctx:advance(4)
		T.eq(noticesContaining(g, "Slow down"), 2, "reminded again after the cooldown")

		g.ctx:teleport(player, dest + Vector3.new(0, 3, 0), 5)
		g.ctx:advance(0.5)
		T.eq(player:GetAttribute("OrderId"), 0)
		T.eq(#g.ctx:fired("DeliveryResult"), 1)
	end)

	T.test("order: an impossibly quick arrival is held back until it is plausible", function()
		local g = boot()
		local player = join(g, "Alice", 1001)
		takeOrder(g, player)
		deliver(g, player, 0) -- teleport onto the marker immediately
		T.truthy(player:GetAttribute("OrderId") > 0, "too early to count")
		T.eq(#g.ctx:fired("DeliveryResult"), 0)
		g.ctx:advance(6)
		T.eq(player:GetAttribute("OrderId"), 0)
		T.eq(#g.ctx:fired("DeliveryResult"), 1)
	end)

	T.test("order: not being at the marker never delivers", function()
		local g = boot()
		local player = join(g, "Alice", 1001)
		takeOrder(g, player)
		local limit = player:GetAttribute("OrderTimeLimit")
		g.ctx:advance(limit - 1)
		T.truthy(player:GetAttribute("OrderId") > 0)
		T.eq(#g.ctx:fired("DeliveryResult"), 0)
	end)

	T.test("order: a late delivery pays base only and breaks the streak", function()
		local g = boot()
		local player = join(g, "Alice", 1001)
		-- build a streak first
		takeOrder(g, player)
		g.ctx:advance(4)
		deliver(g, player)
		T.eq(player:GetAttribute("Streak"), 1)

		takeOrder(g, player)
		local limit = player:GetAttribute("OrderTimeLimit")
		g.ctx:advance(limit + 10) -- late, but inside the grace period
		T.truthy(player:GetAttribute("OrderId") > 0, "customer is still waiting")
		deliver(g, player)

		local r = g.ctx:fired("DeliveryResult")[2].Args[1]
		T.eq(r.OnTime, false)
		T.eq(r.Total, r.Base)
		T.eq(r.Tip + r.TimeBonus + r.StreakBonus, 0)
		T.eq(player:GetAttribute("Streak"), 0)
		T.eq(player:GetAttribute("Deliveries"), 2)
	end)

	T.test("order: the customer cancels if you take far too long", function()
		local g = boot()
		local player = join(g, "Alice", 1001)
		takeOrder(g, player)
		local limit = player:GetAttribute("OrderTimeLimit")
		g.ctx:advance(limit + g.Config.OrderFailGrace + 2)
		T.eq(player:GetAttribute("OrderId"), 0)
		T.eq(player:GetAttribute("Cash"), 0)
		T.eq(player:GetAttribute("Deliveries"), 0)
		local message, kind = lastNotice(g, player)
		T.truthy(string.find(message, "cancelled", 1, true))
		T.eq(kind, "error")
	end)

	T.test("order: cancelling clears it and resets the streak; cancelling with no order does nothing", function()
		local g = boot()
		local player = join(g, "Alice", 1001)
		g.Remotes.CancelOrder:FireServer() -- nothing to cancel
		T.eq(noticesContaining(g, "cancelled"), 0)

		takeOrder(g, player)
		g.ctx:advance(4)
		deliver(g, player)
		T.eq(player:GetAttribute("Streak"), 1)
		takeOrder(g, player)
		g.Remotes.CancelOrder:FireServer()
		g.ctx:flush()
		T.eq(player:GetAttribute("OrderId"), 0)
		T.eq(player:GetAttribute("Streak"), 0)
		T.eq((lastNotice(g, player)), "Order cancelled.")
	end)

	T.test("order: the same houses aren't offered back to back", function()
		local g = boot()
		local player = join(g, "Alice", 1001)
		local seen = {}
		for _ = 1, 8 do
			takeOrder(g, player)
			local address = player:GetAttribute("OrderAddress")
			-- the last three deliveries are avoided
			T.falsy(seen[#seen] == address or seen[#seen - 1] == address or seen[#seen - 2] == address, "repeated " .. address)
			table.insert(seen, address)
			g.ctx:advance(4)
			deliver(g, player)
		end
	end)

	T.test("order: players can't deliver for each other (orders are per player)", function()
		local g = boot()
		local alice = join(g, "Alice", 1001)
		local bob = join(g, "Bob", 1002)
		takeOrder(g, alice)
		g.ctx:advance(4)
		g.ctx:teleport(bob, alice:GetAttribute("OrderDest") + Vector3.new(0, 3, 0), 0)
		g.ctx:advance(1)
		T.truthy(alice:GetAttribute("OrderId") > 0)
		T.eq(bob:GetAttribute("OrderId"), 0)
		T.eq(#g.ctx:fired("DeliveryResult"), 0)
	end)

	T.test("order: dying mid-delivery doesn't deliver or crash the tick loop", function()
		local g = boot()
		local player = join(g, "Alice", 1001)
		takeOrder(g, player)
		g.ctx:advance(4)
		player.Character.Humanoid.Health = 0
		g.ctx:teleport(player, player:GetAttribute("OrderDest") + Vector3.new(0, 3, 0), 0)
		g.ctx:advance(1)
		T.truthy(player:GetAttribute("OrderId") > 0)
		player.Character:Destroy() -- character removed entirely
		g.ctx:advance(1)
		T.truthy(player:GetAttribute("OrderId") > 0, "order survives respawn")
	end)

	T.test("order: higher ranks get longer orders", function()
		local g = boot()
		local player = join(g, "Alice", 1001)
		giveCash(g, player, 0, 10000) -- top rank
		T.eq(player:GetAttribute("RankIndex"), #g.Config.Ranks)
		local longest = 0
		for _ = 1, 6 do
			takeOrder(g, player)
			longest = math.max(longest, player:GetAttribute("OrderDistance"))
			T.truthy(player:GetAttribute("OrderDistance") >= g.Config.Ranks[#g.Config.Ranks - 1].MinDist)
			g.Remotes.CancelOrder:FireServer()
		end
		T.truthy(longest > g.Config.Ranks[1].MaxDist)
	end)

	T.test("order: reaching a new rank is announced with the delivery", function()
		local g = boot()
		local player = join(g, "Alice", 1001)
		giveCash(g, player, 0, 115) -- 5 XP short of Courier
		takeOrder(g, player)
		g.ctx:advance(4)
		deliver(g, player)
		T.eq(player:GetAttribute("RankIndex"), 2)
		local r = g.ctx:fired("DeliveryResult")[1].Args[1]
		T.eq(r.RankedUpTo, "Courier")
		T.truthy(noticesContaining(g, "RANK UP") == 1)
	end)

	-- Vehicles ------------------------------------------------------------------------------

	T.test("vehicle: V (CallVehicle) brings your vehicle and sits you in it; calling again is a no-op", function()
		local g = boot()
		local player = join(g, "Alice", 1001)
		g.Remotes.CallVehicle:FireServer()
		local vehicle = vehicleOf(g, player)
		T.truthy(vehicle)
		T.eq(player.Character.Humanoid.SeatPart, vehicle.Seat)
		g.ctx:advance(5)
		g.Remotes.CallVehicle:FireServer()
		T.eq(vehicleOf(g, player), vehicle, "still the same vehicle")
		T.eq(#g.ctx.Workspace.Vehicles:GetChildren(), 1)
	end)

	T.test("vehicle: calling it again too soon is refused politely", function()
		local g = boot()
		local player = join(g, "Alice", 1001)
		g.Remotes.CallVehicle:FireServer()
		local humanoid = Mocks.leaveSeat(player.Character.Humanoid)
		g.ctx:advance(0.5)
		g.Remotes.CallVehicle:FireServer()
		T.eq((lastNotice(g, player)), "Give it a moment...")
		T.falsy(humanoid.SeatPart, "not re-seated yet")
		g.ctx:advance(3)
		g.Remotes.CallVehicle:FireServer()
		T.truthy(player.Character.Humanoid.SeatPart)
	end)

	T.test("vehicle: a parked vehicle is brought to you (same model), not duplicated", function()
		local g = boot()
		local player = join(g, "Alice", 1001)
		g.Remotes.CallVehicle:FireServer()
		local vehicle = vehicleOf(g, player)
		Mocks.leaveSeat(player.Character.Humanoid)
		g.ctx:advance(1)
		T.truthy(vehicle.PrimaryPart.Anchored, "parks itself shortly after you get out")
		T.eq(vehicle:GetAttribute("Occupied"), false)

		g.ctx:teleport(player, Vector3.new(200, 3, 90), 0)
		g.ctx:advance(3)
		g.Remotes.CallVehicle:FireServer()
		T.eq(vehicleOf(g, player), vehicle)
		T.eq(#g.ctx.Workspace.Vehicles:GetChildren(), 1)
		T.truthy(math.abs(vehicle.PrimaryPart.CFrame.Position.X - 200) < 25, "moved next to the player")
		T.eq(player.Character.Humanoid.SeatPart, vehicle.Seat)
		T.falsy(vehicle.PrimaryPart.Anchored)
	end)

	T.test("vehicle: it won't spawn inside a building (picks another free spot)", function()
		local g = boot()
		local player = join(g, "Alice", 1001)
		-- a wall right where it would normally appear (ahead of the player)
		table.insert(g.ctx.Obstacles, { Center = Vector3.new(0, 5, SPAWN.Z - 16), Half = Vector3.new(30, 5, 3) })
		g.Remotes.CallVehicle:FireServer()
		local vehicle = vehicleOf(g, player)
		local position = vehicle.PrimaryPart.CFrame.Position
		T.truthy(math.abs(position.Z - (SPAWN.Z - 16)) > 4 or math.abs(position.X) > 20, "spawned in the wall at " .. tostring(position))
	end)

	T.test("vehicle: boxed in on every side it still spawns (just ahead) rather than failing", function()
		local g = boot()
		local player = join(g, "Alice", 1001)
		table.insert(g.ctx.Obstacles, { Center = Vector3.new(0, 5, SPAWN.Z), Half = Vector3.new(80, 5, 80) })
		g.Remotes.CallVehicle:FireServer()
		T.truthy(vehicleOf(g, player))
	end)

	T.test("vehicle: it parks when the driver leaves the seat and un-parks when they return", function()
		local g = boot()
		local player = join(g, "Alice", 1001)
		g.Remotes.CallVehicle:FireServer()
		local vehicle = vehicleOf(g, player)
		T.falsy(vehicle.PrimaryPart.Anchored)
		local humanoid = Mocks.leaveSeat(player.Character.Humanoid)
		g.ctx:advance(0.2)
		T.falsy(vehicle.PrimaryPart.Anchored, "keeps rolling for a moment")
		g.ctx:advance(0.5)
		T.truthy(vehicle.PrimaryPart.Anchored)

		Mocks.sit(vehicle.Seat, humanoid)
		T.falsy(vehicle.PrimaryPart.Anchored)
		T.eq(vehicle:GetAttribute("Occupied"), true)
	end)

	T.test("vehicle: the seat refuses touch-sitting briefly after you get out, but a summon always works", function()
		local g = boot()
		local player = join(g, "Alice", 1001)
		g.Remotes.CallVehicle:FireServer()
		local vehicle = vehicleOf(g, player)
		local humanoid = Mocks.leaveSeat(player.Character.Humanoid)
		T.eq(vehicle.Seat.Disabled, true)
		g.ctx:advance(1)
		T.eq(vehicle.Seat.Disabled, true, "still cooling down")
		g.ctx:advance(1)
		T.eq(vehicle.Seat.Disabled, false, "walk-in sitting works again")

		-- leave again, and call the vehicle straight away (after the summon cooldown): must re-enable the seat first
		Mocks.sit(vehicle.Seat, humanoid)
		Mocks.leaveSeat(player.Character.Humanoid)
		g.ctx:advance(0.5)
		T.eq(vehicle.Seat.Disabled, true)
		g.ctx:advance(2.5)
		vehicle.Seat.Disabled = true
		g.Remotes.CallVehicle:FireServer()
		T.eq(vehicle.Seat.Disabled, false)
		T.eq(player.Character.Humanoid.SeatPart, vehicle.Seat)
	end)

	T.test("vehicle: other players can't drive your vehicle", function()
		local g = boot()
		local alice = join(g, "Alice", 1001)
		local bob = join(g, "Bob", 1002)
		g.ctx.players.LocalPlayer = alice
		g.Remotes.CallVehicle:FireServer()
		local vehicle = vehicleOf(g, alice)
		Mocks.leaveSeat(alice.Character.Humanoid)
		g.ctx:advance(1)

		-- Bob hops in
		local seatWeld = roblox.Instance.new("Weld")
		seatWeld.Name = "SeatWeld"
		seatWeld.Parent = vehicle.Seat
		Mocks.sit(vehicle.Seat, bob.Character.Humanoid)
		T.falsy(seatWeld.Parent, "the seat weld is removed to eject him")
		T.eq(bob.Character.Humanoid.Jump, true)
		T.truthy(vehicle.PrimaryPart.Anchored, "still parked")
	end)

	T.test("vehicle: each player gets their own", function()
		local g = boot()
		local alice = join(g, "Alice", 1001)
		g.Remotes.CallVehicle:FireServer()
		local bob = join(g, "Bob", 1002)
		g.Remotes.CallVehicle:FireServer()
		T.eq(#g.ctx.Workspace.Vehicles:GetChildren(), 2)
		T.truthy(vehicleOf(g, alice) ~= vehicleOf(g, bob))
		T.eq(g.ctx.NetworkOwners[vehicleOf(g, bob).PrimaryPart], bob)
	end)

	T.test("vehicle: it's removed when its owner leaves", function()
		local g = boot()
		local player = join(g, "Alice", 1001)
		g.Remotes.CallVehicle:FireServer()
		T.eq(#g.ctx.Workspace.Vehicles:GetChildren(), 1)
		g.ctx:leave(player)
		T.eq(#g.ctx.Workspace.Vehicles:GetChildren(), 0)
	end)

	T.test("vehicle: one that falls out of the world is removed and the player told", function()
		local g = boot()
		local player = join(g, "Alice", 1001)
		g.Remotes.CallVehicle:FireServer()
		local vehicle = vehicleOf(g, player)
		Mocks.setPart(vehicle.PrimaryPart, CFrame.new(0, -500, 0))
		g.ctx:advance(2.5)
		T.falsy(vehicleOf(g, player))
		T.truthy(string.find((lastNotice(g, player)), "fell off the map", 1, true))
		g.ctx:advance(3)
		g.Remotes.CallVehicle:FireServer()
		T.truthy(vehicleOf(g, player), "can call a new one")
	end)

	T.test("vehicle: can't summon while dead or before the profile loads", function()
		local g = boot()
		local player = join(g, "Alice", 1001)
		player.Character.Humanoid.Health = 0
		g.Remotes.CallVehicle:FireServer()
		T.falsy(vehicleOf(g, player))
		T.eq((lastNotice(g, player)), "You can't do that right now.")
	end)

	-- Garage ----------------------------------------------------------------------------------

	local function garage(g, action, id)
		return g.Remotes.GarageRequest:InvokeServer(action, id)
	end

	T.test("garage: the prompt opens the garage UI for the player who used it", function()
		local g = boot()
		local player = join(g, "Alice", 1001)
		g.world.GaragePrompt.Triggered:Fire(player)
		local calls = g.ctx:fired("OpenGarage")
		T.eq(#calls, 1)
		T.eq(calls[1].Player, player)
	end)

	T.test("garage: buying needs cash and rank, spends the right amount, and equips", function()
		local g = boot()
		local player = join(g, "Alice", 1001)
		local reply = garage(g, "Buy", "Hatchback")
		T.eq(reply.ok, false)
		T.eq(reply.message, "Not enough cash")
		T.eq(player:GetAttribute("Cash"), 0)

		local price = g.Config.VehicleById.Hatchback.Price
		giveCash(g, player, price + 10)
		g.ctx:advance(1)
		reply = garage(g, "Buy", "Hatchback")
		T.eq(reply.ok, true, reply.message)
		T.eq(player:GetAttribute("Cash"), 10)
		T.eq(player:GetAttribute("Equipped"), "Hatchback")
		T.eq(player:GetAttribute("Owned"), ",Hatchback,Scooter,")

		g.ctx:advance(1) -- past the request cooldown
		reply = garage(g, "Buy", "Hatchback")
		T.eq(reply.ok, false)
		T.eq(reply.message, "You already own this vehicle")
	end)

	T.test("garage: rank-locked vehicles can't be bought no matter how rich you are", function()
		local g = boot()
		local player = join(g, "Alice", 1001)
		giveCash(g, player, 10 ^ 7)
		local reply = garage(g, "Buy", "Hyper")
		T.eq(reply.ok, false)
		T.truthy(string.find(reply.message, "Requires rank", 1, true))
		T.eq(player:GetAttribute("Cash"), 10 ^ 7)
	end)

	T.test("garage: equipping swaps the spawned vehicle for the new model and keeps you driving", function()
		local g = boot()
		local player = join(g, "Alice", 1001)
		giveCash(g, player, 5000, 500)
		g.Remotes.CallVehicle:FireServer()
		local old = vehicleOf(g, player)
		T.eq(old:GetAttribute("VehicleId"), "Scooter")

		g.ctx:advance(1)
		T.eq(garage(g, "Buy", "Van").ok, true)
		g.ctx:advance(1)
		local van = vehicleOf(g, player)
		T.eq(van:GetAttribute("VehicleId"), "Van")
		T.truthy(van ~= old)
		T.falsy(old.Parent, "old model destroyed")
		T.eq(player.Character.Humanoid.SeatPart, van.Seat)
		T.eq(#g.ctx.Workspace.Vehicles:GetChildren(), 1)

		g.ctx:advance(1)
		T.eq(garage(g, "Equip", "Scooter").ok, true)
		T.eq(vehicleOf(g, player):GetAttribute("VehicleId"), "Scooter")
	end)

	T.test("garage: equipping before any vehicle exists just changes what you'll get", function()
		local g = boot()
		local player = join(g, "Alice", 1001)
		giveCash(g, player, 5000, 500)
		T.eq(garage(g, "Buy", "Hatchback").ok, true)
		T.falsy(vehicleOf(g, player), "nothing spawned yet")
		g.Remotes.CallVehicle:FireServer()
		T.eq(vehicleOf(g, player):GetAttribute("VehicleId"), "Hatchback")
	end)

	T.test("garage: you can't equip what you don't own", function()
		local g = boot()
		local player = join(g, "Alice", 1001)
		local reply = garage(g, "Equip", "Van")
		T.eq(reply.ok, false)
		T.eq(player:GetAttribute("Equipped"), "Scooter")
	end)

	T.test("garage: mid-delivery you can buy but not switch vehicles", function()
		local g = boot()
		local player = join(g, "Alice", 1001)
		giveCash(g, player, 5000, 500)
		takeOrder(g, player)
		T.truthy(player:GetAttribute("OrderId") > 0)

		local reply = garage(g, "Buy", "Hatchback")
		T.eq(reply.ok, true)
		T.truthy(string.find(reply.message, "Finish your delivery", 1, true))
		T.eq(player:GetAttribute("Equipped"), "Scooter")
		T.eq(player:GetAttribute("Owned"), ",Hatchback,Scooter,")

		g.ctx:advance(1)
		reply = garage(g, "Equip", "Hatchback")
		T.eq(reply.ok, false)
		T.eq(player:GetAttribute("Equipped"), "Scooter")
		T.eq(vehicleOf(g, player):GetAttribute("VehicleId"), "Scooter", "vehicle unchanged")

		g.ctx:advance(1)
		T.eq(garage(g, "Equip", "Scooter").ok, true, "re-equipping the current one is harmless")
	end)

	T.test("garage: malformed requests are rejected without side effects", function()
		local g = boot()
		local player = join(g, "Alice", 1001)
		giveCash(g, player, 5000, 500)
		local before = player:GetAttribute("Cash")
		local bad = {
			{ nil, nil },
			{ 5, "Van" },
			{ "Buy", 5 },
			{ "Buy", "Hovercraft" },
			{ "Steal", "Van" },
			{ { "Buy" }, "Van" },
		}
		for _, args in bad do
			g.ctx:advance(1)
			local reply = g.Remotes.GarageRequest:InvokeServer(args[1], args[2])
			T.eq(reply.ok, false)
		end
		T.eq(player:GetAttribute("Cash"), before)
		T.eq(player:GetAttribute("Owned"), ",Scooter,")
	end)

	T.test("garage: hammering the buy button is rate limited", function()
		local g = boot()
		local player = join(g, "Alice", 1001)
		giveCash(g, player, 5000, 500)
		T.eq(garage(g, "Buy", "Hatchback").ok, true)
		local reply = garage(g, "Equip", "Scooter")
		T.eq(reply.ok, false)
		T.eq(reply.message, "Slow down!")
	end)

	-- Saving ------------------------------------------------------------------------------------

	T.test("save: leaving writes progress (and only progress) to the DataStore", function()
		local g = boot()
		local player = join(g, "Alice", 1001)
		giveCash(g, player, 5000, 500)
		takeOrder(g, player)
		g.ctx:advance(4)
		deliver(g, player)
		g.ctx:leave(player)

		local saved = g.store.Data[g.Config.DataStoreName].Player_1001
		T.truthy(saved)
		T.truthy(saved.Cash > 5000)
		T.eq(saved.Deliveries, 1)
		T.eq(saved.XP, 500 + g.ctx:fired("DeliveryResult")[1].Args[1].XP)
		T.eq(saved.Equipped, "Scooter")
		T.truthy(saved.Owned.Scooter)
		T.eq(saved.Streak, nil, "session-only fields aren't saved")
		T.eq(saved.Temporary, nil)
	end)

	T.test("save: progress survives leaving and rejoining", function()
		local g = boot()
		local player = join(g, "Alice", 1001)
		giveCash(g, player, 5000, 500)
		T.eq(garage(g, "Buy", "Van").ok, true)
		local cash = player:GetAttribute("Cash")
		g.ctx:leave(player)

		local again = join(g, "Alice", 1001)
		T.eq(again:GetAttribute("Cash"), cash)
		T.eq(again:GetAttribute("Equipped"), "Van")
		T.eq(again:GetAttribute("Owned"), ",Scooter,Van,")
		T.eq(again:GetAttribute("XP"), 500)
	end)

	T.test("save: autosave runs every minute", function()
		local g = boot()
		local player = join(g, "Alice", 1001)
		giveCash(g, player, 777)
		T.eq(g.store.WriteCalls, 0)
		g.ctx:advance(g.Config.AutosaveInterval + 1)
		T.eq(g.store.WriteCalls, 1)
		T.eq(g.store.Data[g.Config.DataStoreName].Player_1001.Cash, 777)
		giveCash(g, player, 1)
		g.ctx:advance(g.Config.AutosaveInterval)
		T.eq(g.store.Data[g.Config.DataStoreName].Player_1001.Cash, 778)
	end)

	T.test("save: server shutdown saves everyone", function()
		local g = boot()
		local a = join(g, "Alice", 1001)
		local b = join(g, "Bob", 1002)
		giveCash(g, a, 11)
		giveCash(g, b, 22)
		T.truthy(g.ctx.closeHandler, "BindToClose handler registered")
		local finished = false
		g.ctx.scheduler.task.spawn(function()
			g.ctx.closeHandler()
			finished = true
		end)
		g.ctx:advance(5)
		T.truthy(finished)
		local data = g.store.Data[g.Config.DataStoreName]
		T.eq(data.Player_1001.Cash, 11)
		T.eq(data.Player_1002.Cash, 22)
	end)

	T.test("save: a failing DataStore is retried and doesn't crash the server", function()
		local g = boot()
		local player = join(g, "Alice", 1001)
		giveCash(g, player, 50)
		g.store.FailSets = true
		g.ctx.scheduler.task.spawn(function()
			g.ctx:leave(player)
		end)
		g.ctx:advance(10)
		T.eq(g.store.WriteCalls, 3, "three attempts")
		T.eq(g.store.Data[g.Config.DataStoreName].Player_1001, nil)
	end)

	T.test("save: a player leaving mid-load is handled", function()
		local g = boot()
		g.store.FailGets = true
		local player = g.ctx:newPlayer("Ghost", 1999)
		g.ctx.scheduler.task.spawn(function()
			g.ctx.players.PlayerAdded:Fire(player)
		end)
		g.ctx:advance(1)
		player.Parent = nil -- left while the first attempt was backing off
		g.ctx:advance(10)
		T.eq(player:GetAttribute("Loaded"), false)
	end)
end
