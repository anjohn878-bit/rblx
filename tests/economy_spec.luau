local Fixture = require("./fixture")

return function(T)
	local fx = Fixture.new()
	local Config = fx:require("ReplicatedStorage.Shared.Config")
	local Economy = fx:require("ReplicatedStorage.Shared.Economy")
	local VehicleBuilder = fx:require("ReplicatedStorage.Shared.VehicleBuilder")

	local function pos(x, z)
		return { X = x, Z = z }
	end

	T.test("config: ranks are sorted by XP and start at zero", function()
		T.eq(Config.Ranks[1].XP, 0)
		for i = 2, #Config.Ranks do
			T.truthy(Config.Ranks[i].XP > Config.Ranks[i - 1].XP, "rank " .. i .. " XP must increase")
			T.truthy(Config.Ranks[i].PayMult >= Config.Ranks[i - 1].PayMult, "pay multiplier must not fall")
			T.truthy(Config.Ranks[i].MaxDist >= Config.Ranks[i - 1].MaxDist, "max distance must not fall")
			T.truthy(Config.Ranks[i].MinDist < Config.Ranks[i].MaxDist)
		end
	end)

	T.test("config: vehicles have unique ids, a model design, and the first is free", function()
		local seen = {}
		T.eq(Config.Vehicles[1].Price, 0, "starter vehicle must be free")
		T.eq(Config.DefaultVehicle, Config.Vehicles[1].Id)
		for i, v in Config.Vehicles do
			T.falsy(seen[v.Id], "duplicate vehicle id " .. v.Id)
			seen[v.Id] = true
			T.truthy(VehicleBuilder.hasDesign(v.Id), v.Id .. " needs a design in VehicleBuilder")
			T.truthy(v.RankRequired >= 1 and v.RankRequired <= #Config.Ranks, v.Id .. " rank requirement out of range")
			T.truthy(v.MaxSpeed < Config.MaxPlausibleSpeed, v.Id .. " is faster than the anti-cheat speed cap")
			if i > 1 then
				T.truthy(v.Price > Config.Vehicles[i - 1].Price, v.Id .. " should cost more than the previous vehicle")
				T.truthy(v.MaxSpeed > Config.Vehicles[i - 1].MaxSpeed, v.Id .. " should be faster than the previous vehicle")
			end
		end
	end)

	T.test("config: delivery rules are coherent with vehicle speeds", function()
		-- Every vehicle must be able to be slow enough to deliver, trivially, but the threshold has to be above walking speed.
		T.truthy(Config.DeliveryMaxSpeed > 16)
		T.truthy(Config.DeliveryRadius > 4)
	end)

	T.test("rank index follows XP thresholds", function()
		T.eq(Economy.rankIndexForXp(0), 1)
		T.eq(Economy.rankIndexForXp(119), 1)
		T.eq(Economy.rankIndexForXp(120), 2)
		T.eq(Economy.rankIndexForXp(349), 2)
		T.eq(Economy.rankIndexForXp(350), 3)
		T.eq(Economy.rankIndexForXp(10 ^ 9), #Config.Ranks)
	end)

	T.test("rank info reports progress to the next rank", function()
		local info = Economy.rankInfo(60)
		T.eq(info.Index, 1)
		T.eq(info.Name, "Rookie")
		T.eq(info.XPNext, 120)
		T.near(info.Fraction, 0.5)
		local top = Economy.rankInfo(10 ^ 9)
		T.eq(top.Index, #Config.Ranks)
		T.eq(top.XPNext, nil)
		T.eq(top.Fraction, 1)
	end)

	T.test("route distance is Manhattan on the XZ plane", function()
		T.eq(Economy.routeDistance(pos(0, 0), pos(30, -40)), 70)
		T.eq(Economy.routeDistance(pos(-5, 5), pos(5, -5)), 20)
	end)

	T.test("time limit grows with distance and shrinks with vehicle speed", function()
		local package = { TimeMult = 1 }
		local near = Economy.timeLimit(200, 60, package)
		local far = Economy.timeLimit(800, 60, package)
		local fast = Economy.timeLimit(800, 120, package)
		T.truthy(far > near)
		T.truthy(fast < far)
		T.truthy(Economy.timeLimit(200, 60, { TimeMult = 0.8 }) < near, "hot food gets less time")
	end)

	T.test("base pay scales with distance, rank, package and vehicle bonus", function()
		local plain = { PayMult = 1 }
		local rank1 = Config.Ranks[1]
		local rank5 = Config.Ranks[5]
		local a = Economy.basePay(300, rank1, plain, {})
		T.truthy(Economy.basePay(600, rank1, plain, {}) > a)
		T.truthy(Economy.basePay(300, rank5, plain, {}) > a)
		T.truthy(Economy.basePay(300, rank1, { PayMult = 1.2 }, {}) > a)
		T.truthy(Economy.basePay(300, rank1, plain, { PayBonus = 0.1 }) > a)
	end)

	T.test("stars follow the time ratio thresholds", function()
		T.eq(Economy.stars(10, 100), 5)
		T.eq(Economy.stars(55, 100), 5)
		T.eq(Economy.stars(56, 100), 4)
		T.eq(Economy.stars(75, 100), 4)
		T.eq(Economy.stars(90, 100), 3)
		T.eq(Economy.stars(100, 100), 3)
		T.eq(Economy.stars(120, 100), 2)
		T.eq(Economy.stars(300, 100), 1)
	end)

	local order = { Distance = 400, TimeLimit = 60, BasePay = 100 }

	T.test("an on-time delivery earns bonus, tip and streak; total is the sum of parts", function()
		local r = Economy.settle(order, 24, 3)
		T.truthy(r.OnTime)
		T.eq(r.Stars, 5)
		T.eq(r.Base, 100)
		T.eq(r.TimeBonus, 35, "full time bonus when finishing in half the time or less")
		T.eq(r.Tip, 25)
		T.eq(r.StreakBonus, 15)
		T.eq(r.Total, r.Base + r.TimeBonus + r.Tip + r.StreakBonus)
	end)

	T.test("a barely-on-time delivery earns almost no time bonus", function()
		local r = Economy.settle(order, 60, 0)
		T.truthy(r.OnTime)
		T.eq(r.TimeBonus, 0)
		T.eq(r.Stars, 3)
		T.eq(r.Tip, 8)
		T.eq(r.StreakBonus, 0)
	end)

	T.test("a late delivery pays base only and earns less XP", function()
		local onTime = Economy.settle(order, 30, 5)
		local late = Economy.settle(order, 90, 5)
		T.falsy(late.OnTime)
		T.eq(late.Total, late.Base)
		T.eq(late.TimeBonus + late.Tip + late.StreakBonus, 0)
		T.truthy(late.XP < onTime.XP)
		T.truthy(late.XP > 0)
	end)

	T.test("streak bonus is capped", function()
		local r = Economy.settle(order, 30, 500)
		T.eq(r.StreakBonus, math.floor(100 * Config.Economy.StreakMax + 0.5))
	end)

	T.test("minimum travel time rejects instant deliveries", function()
		local t = Economy.minTravelTime(850)
		T.truthy(t > 4 and t < 6)
	end)

	T.test("money and time formatting", function()
		T.eq(Economy.formatMoney(0), "$0")
		T.eq(Economy.formatMoney(7), "$7")
		T.eq(Economy.formatMoney(999), "$999")
		T.eq(Economy.formatMoney(1000), "$1,000")
		T.eq(Economy.formatMoney(1234567), "$1,234,567")
		T.eq(Economy.formatMoney(12.6), "$13")
		T.eq(Economy.formatTime(0), "0:00")
		T.eq(Economy.formatTime(65), "1:05")
		T.eq(Economy.formatTime(-4), "0:00")
	end)
end
