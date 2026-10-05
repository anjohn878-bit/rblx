--!nocheck
-- Pure game rules: content tables, growth, shop stock, scheduler, flight math, economy.

return function(H)
	local world = H.newWorld({})
	local Config = world.requireShared("Config")
	local Seeds = world.requireShared("Seeds")
	local Birds = world.requireShared("Birds")
	local Growth = world.requireShared("Growth")
	local Scheduler = world.requireShared("Scheduler")
	local BirdFlight = world.requireShared("BirdFlight")
	local Format = world.requireShared("Format")
	local Signal = world.requireShared("Signal")
	local Random, Vector3 = world.env.Random, world.Vector3

	local passed, failed = 0, {}
	local function check(name, cond, detail)
		if cond then
			passed += 1
		else
			table.insert(failed, name .. (detail and (" -- " .. tostring(detail)) or ""))
		end
	end
	local function near(a, b, eps)
		return math.abs(a - b) <= (eps or 1e-6)
	end
	local function section(title)
		print("\n== " .. title)
	end

	------------------------------------------------------------------------------
	section("Content data")
	------------------------------------------------------------------------------
	do
		local rarityRank = {}
		for i, r in Config.RARITY_ORDER do
			rarityRank[r] = i
		end

		local referenced = {}
		local lastPrice, lastGrow, lastTierValue = 0, 0, 0
		for i, seed in Seeds.list do
			check(seed.id .. " tier matches order", seed.tier == i)
			check(seed.id .. " rarity matches tier", rarityRank[seed.rarity] == seed.tier, seed.rarity)
			check(seed.id .. " costs more than previous seed", seed.price > lastPrice)
			check(seed.id .. " grows slower than previous seed (better seeds take longer)", seed.growTime > lastGrow)
			lastPrice, lastGrow = seed.price, seed.growTime
			check(seed.id .. " has a perch", #seed.perches >= 1)
			for _, p in seed.perches do
				check(seed.id .. " perch is {x,y,z}", #p == 3)
			end
			check(seed.id .. " has a stock rule", seed.stock.min >= 1 and seed.stock.max >= seed.stock.min)

			local total, ownTier, topOwnValue = 0, 0, 0
			for _, entry in seed.birds do
				local bird = Birds.get(entry.id)
				check(seed.id .. " references real bird " .. entry.id, bird ~= nil)
				if bird then
					referenced[bird.id] = true
					total += entry.weight
					if bird.rarity == seed.rarity then
						ownTier += entry.weight
					end
				end
			end
			check(seed.id .. " mostly attracts its own tier", ownTier / total >= 0.95, ownTier / total)
		end

		for _, bird in Birds.list do
			check(bird.id .. " is attracted by some seed", referenced[bird.id])
			check(bird.id .. " has positive value", bird.value > 0)
		end
		check("18 species", #Birds.list == 18, #Birds.list)

		-- better rarity => better pay, strictly
		local lastRank, lastValue = 0, 0
		for _, bird in Birds.list do
			local rank = rarityRank[bird.rarity]
			check(bird.id .. " rarity order", rank >= lastRank)
			check(bird.id .. " pays more than the one before", bird.value > lastValue)
			lastRank, lastValue = rank, bird.value
		end
	end

	------------------------------------------------------------------------------
	section("Growth rules")
	------------------------------------------------------------------------------
	do
		check("progress start", Growth.progress(100, 20, 100) == 0)
		check("progress half", near(Growth.progress(100, 20, 110), 0.5))
		check("progress clamps high", Growth.progress(100, 20, 500) == 1)
		check("progress clamps low (clock skew)", Growth.progress(100, 20, 90) == 0)
		check("scale at start", near(Growth.scale(0), Config.SCALE_MIN))
		check("scale at end", near(Growth.scale(1), 1))

		local a, b = Growth.rollStock(12345), Growth.rollStock(12345)
		local same = true
		for _, seed in Seeds.list do
			if a[seed.id] ~= b[seed.id] then
				same = false
			end
		end
		check("restock is deterministic per interval", same)

		local sunflowerAlways, rareSeen, mythicSeen = true, 0, 0
		local intervals = 4000
		for i = 1, intervals do
			local s = Growth.rollStock(i)
			if not s.sunflower then
				sunflowerAlways = false
			end
			if s.sunflower then
				check("sunflower qty in range", s.sunflower >= 6 and s.sunflower <= 12)
			end
			if s.goldenapple then
				rareSeen += 1
			end
			if s.starbloom then
				mythicSeen += 1
			end
		end
		check("sunflowers are always in stock (never soft-locked)", sunflowerAlways)
		check("golden apple ~10% of restocks", near(rareSeen / intervals, 0.10, 0.025), rareSeen / intervals)
		check("starbloom ~5% of restocks", near(mythicSeen / intervals, 0.05, 0.02), mythicSeen / intervals)

		check("next restock is in the future", Growth.nextRestock(1000) > 1000)
		check("restock boundary", Growth.nextRestock(0) == Config.RESTOCK_INTERVAL)

		check("first plot price", Growth.plotPrice(Config.START_PLOTS) == Config.PLOT_PRICES[1])
		check("no price when maxed", Growth.plotPrice(Config.MAX_PLOTS) == nil)
		check("price list covers every locked plot", #Config.PLOT_PRICES == Config.MAX_PLOTS - Config.START_PLOTS)

		-- pickBird should follow the weights
		local sunflower = Seeds.get("sunflower")
		local rng = Random.new(7)
		local counts = {}
		local n = 20000
		for _ = 1, n do
			local id = Growth.pickBird(sunflower, rng)
			counts[id] = (counts[id] or 0) + 1
		end
		check("sparrow ~60%", near(counts.sparrow / n, 0.60, 0.02), counts.sparrow / n)
		check("goldfinch ~29%", near(counts.goldfinch / n, 0.29, 0.02), counts.goldfinch / n)
		check("lucky robin sometimes visits sunflowers", (counts.robin or 0) > 0)
		for id in counts do
			check("picked bird exists " .. id, Birds.get(id) ~= nil)
		end
	end

	------------------------------------------------------------------------------
	section("Economy simulation")
	------------------------------------------------------------------------------
	-- Run the real Scheduler for each seed for a few simulated hours and report
	-- how fast a plant pays for itself.
	do
		local function simulate(seed, hours)
			local rng = Random.new(99)
			local slots = {}
			for i = 1, #seed.perches do
				slots[i] = Scheduler.newSlot(0, rng, true)
			end
			local feathers, visits = 0, 0
			local firstReward
			local tick = Config.TICK
			local t = 0
			while t < hours * 3600 do
				t += tick
				for _, slot in slots do
					local action = Scheduler.due(slot, t)
					if action == "start" then
						Scheduler.start(slot, t, rng)
						slot.birdId = Growth.pickBird(seed, rng)
					elseif action == "reward" then
						Scheduler.markPaid(slot)
						feathers += Birds.get(slot.birdId).value
						visits += 1
						firstReward = firstReward or t
					elseif action == "finish" then
						Scheduler.finish(slot, t, rng)
					end
				end
			end
			return feathers / (hours * 60), visits / (hours * 60), firstReward
		end

		local birdValue = function(id)
			return Birds.get(id).value
		end
		print(
			string.format(
				"%-18s %9s %9s %7s %10s %11s %9s",
				"seed",
				"price",
				"grow",
				"perch",
				"visit avg",
				"feathers/m",
				"payback"
			)
		)
		local lastPayback = 0
		local perMinute = {}
		for _, seed in Seeds.list do
			local fpm, vpm = simulate(seed, 6)
			perMinute[seed.id] = fpm
			local avg = Growth.expectedVisitValue(seed, birdValue)
			local payback = seed.price / fpm
			print(
				string.format(
					"%-18s %9s %9s %7d %10.1f %11.1f %7.1f m",
					seed.name,
					Format.commas(seed.price),
					Format.growTime(seed.growTime),
					#seed.perches,
					avg,
					fpm,
					payback
				)
			)
			check(seed.id .. " pays for itself within 10 minutes of blooming", payback <= 10, payback)
			check(seed.id .. " is not an instant payback", payback >= 1.5, payback)
			check(seed.id .. " payback does not shrink with tier", payback >= lastPayback - 0.5, payback)
			lastPayback = payback
			-- simulated rate ~ analytic estimate
			local cycle = (Config.VISIT.WAIT_MIN + Config.VISIT.WAIT_MAX) / 2
				+ Config.VISIT.ARRIVE
				+ (Config.VISIT.STAY_MIN + Config.VISIT.STAY_MAX) / 2
				+ Config.VISIT.LEAVE
			local analytic = #seed.perches * (60 / cycle) * avg
			check(seed.id .. " simulation matches analytic income", near(fpm / analytic, 1, 0.12), fpm / analytic)
			check(
				seed.id .. " visits happen at a sane rate",
				vpm > 0.8 * #seed.perches and vpm < 2.5 * #seed.perches,
				vpm
			)
		end

		-- A new player's opening: how long until the first bird pays?
		local _, _, first = simulate(Seeds.get("sunflower"), 0.1)
		print(
			string.format(
				"\nFirst feather arrives %.1fs after a sunflower blooms (grow time %ds)",
				first,
				Seeds.get("sunflower").growTime
			)
		)
		check("first bird comes quickly", first < 15, first)

		-- Rough opening: 30 feathers + 3 free sunflowers -> buy 2 more (30) -> 5 sunflowers.
		local startIncome = perMinute.sunflower * 5
		local toFirstBerry = Seeds.get("berrybush").price / startIncome
		print(
			string.format(
				"5 sunflowers earn %.0f/min -> first Berry Bush after ~%.1f min of bird income",
				startIncome,
				toFirstBerry
			)
		)
		check("first upgrade is reachable in a few minutes", toFirstBerry < 6, toFirstBerry)

		-- Time-to-afford each tier from scratch with a full set of plots of the previous tier.
		print("")
		for i = 2, #Seeds.list do
			local prev, cur = Seeds.list[i - 1], Seeds.list[i]
			local income = perMinute[prev.id] * Config.START_PLOTS
			print(
				string.format(
					"  %d x %-18s earn %10.0f/min -> %-18s (%s) in %5.1f min",
					Config.START_PLOTS,
					prev.name,
					income,
					cur.name,
					Format.commas(cur.price),
					cur.price / income
				)
			)
		end
	end

	------------------------------------------------------------------------------
	section("Scheduler")
	------------------------------------------------------------------------------
	do
		local rng = Random.new(1)
		local slot = Scheduler.newSlot(100, rng, true)
		check("not due before first wait", Scheduler.due(slot, 100) == nil)
		check(
			"first visit arrives within the first-wait window",
			slot.nextVisitAt >= 100 + Config.VISIT.FIRST_WAIT_MIN
				and slot.nextVisitAt <= 100 + Config.VISIT.FIRST_WAIT_MAX
		)
		check("starts when due", Scheduler.due(slot, slot.nextVisitAt) == "start")
		local timing = Scheduler.start(slot, 110, rng)
		check(
			"pays when the bird lands",
			Scheduler.due(slot, 110 + timing.arrive - 0.01) == nil
				and Scheduler.due(slot, 110 + timing.arrive) == "reward"
		)
		Scheduler.markPaid(slot)
		check("only pays once", Scheduler.due(slot, 110 + timing.arrive + 0.1) == nil)
		local endAt = 110 + timing.arrive + timing.stay + timing.leave
		check("finishes when the bird has left", Scheduler.due(slot, endAt) == "finish")
		Scheduler.finish(slot, endAt, rng)
		check("idle again with a fresh wait", not slot.visiting and slot.nextVisitAt > endAt)
	end

	------------------------------------------------------------------------------
	section("Bird flight")
	------------------------------------------------------------------------------
	do
		local function finite(v)
			return v.X == v.X
				and v.Y == v.Y
				and v.Z == v.Z
				and math.abs(v.X) < 1e6
				and math.abs(v.Y) < 1e6
				and math.abs(v.Z) < 1e6
		end
		local rng = Random.new(5)
		local worstJump, worstLook = 0, 0
		for trial = 1, 200 do
			local perch = Vector3.new(rng:NextNumber(-200, 200), rng:NextNumber(3, 18), rng:NextNumber(-200, 200))
			local plan = BirdFlight.plan(perch, rng)
			local visit = {
				id = trial,
				birdId = "sparrow",
				ownerUserId = 1,
				perch = perch,
				from = plan.from,
				to = plan.to,
				facing = plan.facing,
				startTime = 0,
				arrive = Config.VISIT.ARRIVE,
				stay = rng:NextNumber(10, 16),
				leave = Config.VISIT.LEAVE,
				seed = plan.seed,
			}
			local total = BirdFlight.duration(visit)

			local start = BirdFlight.sample(visit, 0)
			check("starts at 'from'", (start.position - visit.from).Magnitude < 1e-6)
			check("starts arriving", start.phase == "arrive")
			local landed = BirdFlight.sample(visit, visit.arrive)
			check("lands on the perch", (landed.position - perch).Magnitude < 0.2, (landed.position - perch).Magnitude)
			check("perched phase", landed.phase == "perch" and landed.flap == 0)
			local over = BirdFlight.sample(visit, total + 5)
			check("ends at 'to'", (over.position - visit.to).Magnitude < 1e-6)
			check("done phase", over.phase == "done")

			local prev
			local t = 0
			while t <= total + 1 do
				local s = BirdFlight.sample(visit, t)
				if not (finite(s.position) and finite(s.look)) then
					check("finite sample", false, string.format("t=%.2f", t))
					break
				end
				local mag = s.look.Magnitude
				worstLook = math.max(worstLook, math.abs(mag - 1))
				if prev then
					-- 60fps-ish step: no teleporting between frames
					worstJump = math.max(worstJump, (s.position - prev).Magnitude)
				end
				prev = s.position
				t += 1 / 30
			end
		end
		check("look vectors are unit length", worstLook < 1e-6, worstLook)
		check("motion is continuous (max per-frame step)", worstJump < 4.5, worstJump)
		print(string.format("worst per-frame step: %.2f studs at 30fps", worstJump))
	end

	------------------------------------------------------------------------------
	section("Format + Signal")
	------------------------------------------------------------------------------
	do
		check("commas", Format.commas(1234567) == "1,234,567")
		check("commas small", Format.commas(12) == "12")
		check("feathers small", Format.feathers(999) == "999")
		check("feathers medium", Format.feathers(123456) == "123,456")
		check("feathers millions", Format.feathers(1234567) == "1.23M", Format.feathers(1234567))
		check("feathers round millions", Format.feathers(2000000) == "2M", Format.feathers(2000000))
		check("feathers billions", Format.feathers(4500000000) == "4.5B", Format.feathers(4500000000))
		check("duration seconds", Format.duration(34) == "0:34")
		check("duration minutes", Format.duration(754) == "12:34")
		check("duration hours", Format.duration(7320) == "2h 02m", Format.duration(7320))
		check("duration negative", Format.duration(-5) == "0:00")
		check(
			"growTime",
			Format.growTime(20) == "20 sec"
				and Format.growTime(90) == "1.5 min"
				and Format.growTime(900) == "15 min"
				and Format.growTime(7200) == "2 hr"
		)

		local sig = Signal.new()
		local got = {}
		local c1 = sig:Connect(function(x)
			table.insert(got, x)
		end)
		sig:Fire(1)
		c1.Disconnect()
		sig:Fire(2)
		check("signal fires then disconnects", #got == 1 and got[1] == 1)
	end

	print(string.format("\n%d checks passed, %d failed", passed, #failed))
	for _, f in failed do
		print("  FAIL: " .. f)
	end
	return #failed == 0
end
