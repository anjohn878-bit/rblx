local roblox = require("@lune/roblox")
local Fixture = require("./fixture")

local Vector3 = roblox.Vector3

return function(T)
	local fx = Fixture.new()
	local Config = fx:require("ReplicatedStorage.Shared.Config")
	local Economy = fx:require("ReplicatedStorage.Shared.Economy")
	local Profile = fx:require("ServerScriptService.Server.Profile")
	local Orders = fx:require("ServerScriptService.Server.Orders")

	-- Profile ---------------------------------------------------------------------------

	T.test("profile: a new player starts with the free vehicle equipped and no progress", function()
		local p = Profile.new()
		T.eq(p.Cash, Config.StartingCash)
		T.eq(p.XP, 0)
		T.eq(p.Equipped, Config.DefaultVehicle)
		T.truthy(Profile.owns(p, Config.DefaultVehicle))
		T.falsy(Profile.owns(p, "Hyper"))
		T.eq(p.Streak, 0)
		T.falsy(p.Temporary)
	end)

	T.test("profile: loading nothing or garbage gives a valid default profile", function()
		for _, input in { nil, "hello", 42, true } do
			local p = Profile.fromSaved(input)
			T.eq(p.Equipped, Config.DefaultVehicle)
			T.eq(p.Cash, 0)
		end
	end)

	T.test("profile: loading restores saved progress", function()
		local p = Profile.fromSaved({
			Cash = 500,
			XP = 130,
			Deliveries = 9,
			TotalEarned = 900,
			BestStreak = 4,
			Owned = { Scooter = true, Van = true },
			Equipped = "Van",
		})
		T.eq(p.Cash, 500)
		T.eq(p.XP, 130)
		T.eq(p.Deliveries, 9)
		T.eq(p.TotalEarned, 900)
		T.eq(p.BestStreak, 4)
		T.truthy(Profile.owns(p, "Van"))
		T.eq(p.Equipped, "Van")
		T.eq(p.Streak, 0, "streak is per session")
	end)

	T.test("profile: loading sanitises corrupt or tampered data", function()
		local p = Profile.fromSaved({
			Cash = -50,
			XP = 0 / 0,
			Deliveries = "lots",
			TotalEarned = math.huge,
			Owned = { Hovercraft = true, Hyper = "yes", Van = true },
			Equipped = "Hyper", -- not actually owned
		})
		T.eq(p.Cash, 0)
		T.eq(p.XP, 0)
		T.eq(p.Deliveries, 0)
		T.eq(p.TotalEarned, 0)
		T.falsy(Profile.owns(p, "Hovercraft"), "unknown vehicle ids are dropped")
		T.falsy(Profile.owns(p, "Hyper"), "only literal true counts as owned")
		T.truthy(Profile.owns(p, "Van"))
		T.eq(p.Equipped, Config.DefaultVehicle, "can't equip what you don't own")
	end)

	T.test("profile: saving keeps only persistent fields and copies the vehicle set", function()
		local p = Profile.new()
		p.Streak = 7
		p.Temporary = true
		local saved = Profile.toSaved(p)
		T.eq(saved.Streak, nil)
		T.eq(saved.Temporary, nil)
		T.eq(saved.Cash, p.Cash)
		saved.Owned.Hyper = true
		T.falsy(Profile.owns(p, "Hyper"), "mutating the saved copy must not touch the live profile")
	end)

	T.test("profile: save -> load round trip", function()
		local p = Profile.new()
		Profile.award(p, 777, 140)
		p.Owned.Hatchback = true
		p.Equipped = "Hatchback"
		local back = Profile.fromSaved(Profile.toSaved(p))
		T.eq(back.Cash, 777)
		T.eq(back.XP, 140)
		T.eq(back.Equipped, "Hatchback")
		T.truthy(Profile.owns(back, "Hatchback"))
	end)

	T.test("profile: buying checks vehicle, ownership, rank and cash in that order", function()
		local p = Profile.new()
		local ok, reason = Profile.canBuy(p, "Nope")
		T.falsy(ok)
		T.eq(reason, "Unknown vehicle")

		ok, reason = Profile.canBuy(p, "Scooter")
		T.falsy(ok)
		T.eq(reason, "You already own this vehicle")

		p.Cash = 100000
		ok, reason = Profile.canBuy(p, "Hyper")
		T.falsy(ok)
		T.truthy(reason:find("Requires rank"), reason)

		p.XP = 10 ^ 6
		p.Cash = 5
		ok, reason = Profile.canBuy(p, "Hatchback")
		T.falsy(ok)
		T.eq(reason, "Not enough cash")

		p.Cash = Config.VehicleById.Hatchback.Price
		ok = Profile.canBuy(p, "Hatchback")
		T.truthy(ok)
	end)

	T.test("profile: buying spends exactly the price, owns and equips the vehicle", function()
		local p = Profile.new()
		local price = Config.VehicleById.Hatchback.Price
		p.Cash = price + 33
		T.truthy(Profile.buy(p, "Hatchback"))
		T.eq(p.Cash, 33)
		T.truthy(Profile.owns(p, "Hatchback"))
		T.eq(p.Equipped, "Hatchback")
		local ok = Profile.buy(p, "Hatchback")
		T.falsy(ok, "can't buy twice")
		T.eq(p.Cash, 33, "a failed purchase costs nothing")
	end)

	T.test("profile: equip requires ownership", function()
		local p = Profile.new()
		local ok, reason = Profile.equip(p, "Van")
		T.falsy(ok)
		T.eq(reason, "You don't own this vehicle")
		p.Owned.Van = true
		T.truthy(Profile.equip(p, "Van"))
		T.eq(p.Equipped, "Van")
		T.falsy(Profile.equip(p, "Nope"))
	end)

	T.test("profile: award adds cash/XP and reports rank-ups", function()
		local p = Profile.new()
		local r = Profile.award(p, 50, 100)
		T.falsy(r.RankedUp)
		T.eq(p.Cash, 50)
		T.eq(p.TotalEarned, 50)
		r = Profile.award(p, 10, 30)
		T.truthy(r.RankedUp)
		T.eq(r.OldRank, 1)
		T.eq(r.NewRank, 2)
		r = Profile.award(p, 10, 10 ^ 6)
		T.eq(r.NewRank, #Config.Ranks)
		T.eq(p.TotalEarned, 70)
	end)

	T.test("profile: streak grows on time, resets when late or broken, best is remembered", function()
		local p = Profile.new()
		Profile.recordDelivery(p, true)
		Profile.recordDelivery(p, true)
		Profile.recordDelivery(p, true)
		T.eq(p.Streak, 3)
		T.eq(p.BestStreak, 3)
		Profile.recordDelivery(p, false)
		T.eq(p.Streak, 0)
		T.eq(p.BestStreak, 3)
		T.eq(p.Deliveries, 4)
		Profile.recordDelivery(p, true)
		Profile.breakStreak(p)
		T.eq(p.Streak, 0)
	end)

	-- Orders ------------------------------------------------------------------------------

	local origin = Vector3.new(0, 0, 0)
	local function house(id, x, z)
		return { Id = id, Address = id .. " Test St", MarkerPos = Vector3.new(x, 0, z) }
	end
	local first = function(a)
		return a
	end
	local last = function(_, b)
		return b
	end
	local scooter = Config.VehicleById.Scooter

	T.test("orders: only houses within the rank's distance band are chosen", function()
		local houses = { house(1, 50, 0), house(2, 200, 100), house(3, 5000, 0), house(4, 0, -300) }
		for _, pick in { first, last } do
			local order = Orders.generate(houses, origin, 1, scooter, pick, {})
			T.truthy(order.Distance >= Config.Ranks[1].MinDist and order.Distance <= Config.Ranks[1].MaxDist, "distance " .. order.Distance)
			T.truthy(order.HouseId == 2 or order.HouseId == 4)
		end
	end)

	T.test("orders: higher ranks reach farther houses", function()
		local houses = { house(1, 300, 0), house(2, 1000, 0) }
		local low = Orders.generate(houses, origin, 1, scooter, first, {})
		T.eq(low.HouseId, 1)
		local high = Orders.generate(houses, origin, 5, scooter, last, {})
		T.truthy(high.Distance >= Config.Ranks[5].MinDist)
	end)

	T.test("orders: recently used houses are skipped when there is an alternative", function()
		local houses = { house(1, 200, 0), house(2, 250, 0) }
		local order = Orders.generate(houses, origin, 1, scooter, first, { [1] = true })
		T.eq(order.HouseId, 2)
		-- ...but still used if it's the only option
		local only = Orders.generate({ house(1, 200, 0) }, origin, 1, scooter, first, { [1] = true })
		T.eq(only.HouseId, 1)
	end)

	T.test("orders: when nothing is in range the closest-to-range house is used", function()
		local order = Orders.generate({ house(1, 5000, 0), house(2, 2000, 0) }, origin, 1, scooter, first, {})
		T.eq(order.HouseId, 2)
	end)

	T.test("orders: time limit and pay come from Economy", function()
		local package = Config.Packages[3]
		local pick = function(a, b)
			return a == 1 and b == 1 and 1 or 3 -- package pick is the call with a larger range
		end
		local order = Orders.generate({ house(1, 300, 0) }, origin, 1, scooter, pick, {})
		T.eq(order.Distance, 300)
		T.eq(order.Package, package)
		T.eq(order.TimeLimit, Economy.timeLimit(300, scooter.MaxSpeed, package))
		T.eq(order.BasePay, Economy.basePay(300, Config.Ranks[1], package, scooter))
		T.eq(order.Dest, Vector3.new(300, 0, 0))
		T.eq(order.VehicleId, "Scooter")
		T.eq(order.Address, "1 Test St")
	end)

	T.test("orders: faster vehicles get tighter time limits", function()
		local houses = { house(1, 300, 0) }
		local slow = Orders.generate(houses, origin, 1, Config.VehicleById.Scooter, first, {})
		local fast = Orders.generate(houses, origin, 1, Config.VehicleById.Hyper, first, {})
		T.truthy(fast.TimeLimit < slow.TimeLimit)
	end)

	local order = { Dest = Vector3.new(100, 0, 100), Distance = 400, TimeLimit = 60 }

	T.test("orders: arrival is judged by distance to the marker, speed, and plausible travel time", function()
		T.eq(Orders.checkArrival(order, Vector3.new(0, 0, 0), 0, 30), "none")
		T.eq(Orders.checkArrival(order, Vector3.new(100 + Config.DeliveryRadius + 1, 0, 100), 0, 30), "none")
		T.eq(Orders.checkArrival(order, Vector3.new(105, 50, 100), 0, 30), "deliver", "height is ignored")
		T.eq(Orders.checkArrival(order, Vector3.new(105, 0, 100), Config.DeliveryMaxSpeed + 1, 30), "toofast")
		T.eq(Orders.checkArrival(order, Vector3.new(105, 0, 100), Config.DeliveryMaxSpeed, 30), "deliver")
		T.eq(Orders.checkArrival(order, Vector3.new(105, 0, 100), 0, 0.5), "early", "teleporting there instantly is ignored")
	end)

	T.test("orders: status goes ok -> late -> failed", function()
		T.eq(Orders.status(order, 0), "ok")
		T.eq(Orders.status(order, 60), "ok")
		T.eq(Orders.status(order, 61), "late")
		T.eq(Orders.status(order, 60 + Config.OrderFailGrace), "late")
		T.eq(Orders.status(order, 60 + Config.OrderFailGrace + 1), "failed")
	end)
end
