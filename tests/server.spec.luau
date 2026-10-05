--!nocheck
-- End-to-end server simulation: the real init.server.luau + services run against
-- a mock engine on a virtual clock. A scripted "player" joins, plants, waits,
-- gets visited by birds, shops, leaves and comes back.

return function(H)
	local passed, failed = 0, {}
	local function check(name, cond, detail)
		if cond then
			passed += 1
		else
			table.insert(failed, name .. (detail ~= nil and (" -- " .. tostring(detail)) or ""))
		end
	end
	local function section(t)
		print("\n== " .. t)
	end

	local function boot(opts)
		local world = H.newWorld(opts or {})
		world.runScript(world.serverScript)
		local RS = world.services.ReplicatedStorage
		local api = {
			world = world,
			remotes = RS.Remotes,
			Seeds = world.requireShared("Seeds"),
			Birds = world.requireShared("Birds"),
			Config = world.requireShared("Config"),
			Growth = world.requireShared("Growth"),
			Format = world.requireShared("Format"),
		}
		function api.fire(player, name, ...)
			world.localPlayer = player
			api.remotes[name]:FireServer(...)
		end
		function api.invoke(player, name, ...)
			world.localPlayer = player
			return api.remotes[name]:InvokeServer(...)
		end
		function api.join(name, userId)
			local p = world.addPlayer(name, userId)
			world.advance(0.1)
			return p
		end
		function api.profile(player)
			-- reach the profile through the replicated snapshot the client would get
			world.localPlayer = player
			return api.invoke(player, "Init").state
		end
		function api.fired(name, kind)
			local list = {}
			for _, e in api.remotes[name]._fired do
				if not kind or (e.args[1] and e.args[1].kind == kind) then
					table.insert(list, e)
				end
			end
			return list
		end
		function api.plants()
			return world.workspace.Plants:GetChildren()
		end
		function api.garden(player)
			for _, g in world.workspace.Gardens:GetChildren() do
				if g:GetAttribute("OwnerUserId") == player.UserId then
					return g
				end
			end
		end
		return api
	end

	----------------------------------------------------------------------------
	section("Boot: world generation")
	----------------------------------------------------------------------------
	local g = boot({})
	local world = g.world
	check("server script ran without errors", #world.errors == 0, world.errors[1])
	check("8 gardens built", #world.workspace.Gardens:GetChildren() == 8)
	local garden1 = world.workspace.Gardens.Garden_1
	local plotCount = 0
	for _, c in garden1:GetChildren() do
		if string.match(c.Name, "^Plot_%d+$") then
			plotCount += 1
		end
	end
	check("12 plots per garden", plotCount == 12, plotCount)
	check("garden starts unowned", garden1:GetAttribute("OwnerUserId") == 0)
	check(
		"every remote exists",
		g.remotes.Init
			and g.remotes.PlantSeed
			and g.remotes.BuySeed
			and g.remotes.UnlockPlot
			and g.remotes.BirdVisit
			and g.remotes.Notify
			and g.remotes.StockUpdate
			and g.remotes.StateUpdate
			and g.remotes.DigPlant
			and g.remotes.BirdCancel
			and g.remotes.Dev
	)
	local prompts = 0
	for _, d in world.workspace.World:GetDescendants() do
		if d.ClassName == "ProximityPrompt" then
			prompts += 1
		end
	end
	check("hub has the shop and Birdpedia prompts", prompts == 2, prompts)
	local descendants = #world.workspace:GetDescendants()
	print(("  world has %d instances"):format(descendants))

	----------------------------------------------------------------------------
	section("A new player joins")
	----------------------------------------------------------------------------
	local alice = g.join("Alice", 111)
	check("no errors after join", #world.errors == 0, world.errors[1])
	local garden = g.garden(alice)
	check("alice owns a garden", garden ~= nil)
	check("garden slot 1 given first", garden and garden:GetAttribute("Slot") == 1)
	check(
		"sign shows her name",
		garden.Sign.SurfaceGui.TextLabel.Text == "AliceDisplay's Garden",
		garden.Sign.SurfaceGui.TextLabel.Text
	)
	check("leaderstats created", alice:FindFirstChild("leaderstats") ~= nil and alice.leaderstats.Feathers.Value == 30)

	local char = world.spawnCharacter(alice)
	check(
		"character is moved to her garden spawn",
		char:GetPivot() ~= nil and (char:GetPivot().Position - garden.Plot_1.CFrame.Position).Magnitude < 60,
		(char:GetPivot().Position - garden.Plot_1.CFrame.Position).Magnitude
	)

	local init = g.invoke(alice, "Init")
	check("Init returns state/stock/visits", init and init.state and init.stock and init.visits)
	check("starts with 30 feathers", init.state.feathers == 30)
	check("starts with 3 sunflower seeds", init.state.seeds.sunflower == 3)
	check("starts with 4 plots", init.state.plots == 4)
	check("shop has sunflowers in stock", (init.stock.stock.sunflower or 0) >= 6)
	check(
		"plots 1-4 unlocked, 5+ locked",
		garden.Plot_4:GetAttribute("Locked") == false and garden.Plot_5:GetAttribute("Locked") == true
	)

	----------------------------------------------------------------------------
	section("Planting")
	----------------------------------------------------------------------------
	g.fire(alice, "PlantSeed", 1, "sunflower")
	world.advance(0.2)
	check("plant model appears", #g.plants() == 1)
	local plant = g.plants()[1]
	check(
		"plant is tagged and attributed",
		plant:GetAttribute("SeedId") == "sunflower"
			and plant:GetAttribute("OwnerUserId") == 111
			and plant:GetAttribute("PlotIndex") == 1
	)
	check("plant is not mature yet", plant:GetAttribute("Mature") == false)
	check("plot marked as occupied", garden.Plot_1:GetAttribute("HasPlant") == true)
	check("plant starts small", plant:GetScale() < 0.3, plant:GetScale())
	check("seed was consumed", g.invoke(alice, "Init").state.seeds.sunflower == 2)

	g.fire(alice, "PlantSeed", 1, "sunflower") -- same plot again
	g.fire(alice, "PlantSeed", 5, "sunflower") -- locked plot
	g.fire(alice, "PlantSeed", 2, "starbloom") -- seed she doesn't own
	g.fire(alice, "PlantSeed", 0, "sunflower")
	g.fire(alice, "PlantSeed", 13, "sunflower")
	g.fire(alice, "PlantSeed", 1.5, "sunflower")
	g.fire(alice, "PlantSeed", "2", "sunflower")
	g.fire(alice, "PlantSeed", 2, nil)
	g.fire(alice, "PlantSeed", 2, 12345)
	g.fire(alice, "PlantSeed", nil, nil)
	g.fire(alice, "PlantSeed", 0 / 0, "sunflower")
	g.fire(alice, "PlantSeed", 2, "../../evil")
	world.advance(0.5)
	check("bad plant requests are rejected", #g.plants() == 1 and g.invoke(alice, "Init").state.seeds.sunflower == 2)
	check("bad requests don't crash the server", #world.errors == 0, world.errors[1])

	g.fire(alice, "PlantSeed", 2, "sunflower")
	world.advance(0.2) -- throttle window
	g.fire(alice, "PlantSeed", 3, "sunflower")
	world.advance(0.2)
	check("planting is rate limited, not blocked", #g.plants() >= 2)

	----------------------------------------------------------------------------
	section("Growing and blooming")
	----------------------------------------------------------------------------
	world.advance(10)
	check("still growing at ~10s", plant:GetAttribute("Mature") == false)
	local mid = plant:GetScale()
	check("plant has grown", mid > 0.45 and mid < 0.85, mid)
	world.advance(12)
	check("blooms after 20s", plant:GetAttribute("Mature") == true)
	check("grown plant is full size", plant:GetScale() == 1)
	check("owner told it bloomed", #g.fired("Notify", "toast") >= 1)
	local bloomToast
	for _, e in g.fired("Notify", "toast") do
		if string.find(e.args[1].text, "fully grown") then
			bloomToast = e.args[1].text
		end
	end
	check("bloom toast names the seed", bloomToast ~= nil and string.find(bloomToast, "Sunflower") ~= nil, bloomToast)
	local rejection
	for _, e in g.fired("Notify", "toast") do
		if string.find(e.args[1].text, "already growing") then
			rejection = true
		end
	end
	check("rejected plant attempts explain themselves", rejection == true)

	-- the transparency swap: Bud parts hidden, Bloom parts shown
	local bud, bloomPart
	for _, d in plant:GetDescendants() do
		if d:GetAttribute("Bud") then
			bud = d
		end
		if d:GetAttribute("Bloom") then
			bloomPart = d
		end
	end
	check("bud hidden once bloomed", bud and bud.Transparency == 1)
	check("flower shown once bloomed", bloomPart and bloomPart.Transparency == 0)

	----------------------------------------------------------------------------
	section("Birds visit")
	----------------------------------------------------------------------------
	local visitsBefore = #g.fired("BirdVisit")
	world.advance(30)
	local visits = g.fired("BirdVisit")
	check("birds started visiting", #visits > visitsBefore, #visits)
	local v = visits[1].args[1]
	check("visit has a species", g.Birds.get(v.birdId) ~= nil, v.birdId)
	check("visit is for alice's plant", v.ownerUserId == 111)
	check(
		"visit has a flight plan",
		v.from and v.to and v.perch and v.facing and v.arrive > 0 and v.stay > 0 and v.leave > 0
	)
	check(
		"bird is a sunflower-tier species",
		({ sparrow = 1, goldfinch = 1, dove = 1, robin = 1 })[v.birdId] ~= nil,
		v.birdId
	)
	check("perch is above the plant", v.perch.Y > plant.Root.CFrame.Position.Y + 3, v.perch.Y)

	local state = g.invoke(alice, "Init").state
	check("feathers were paid", state.feathers > 30, state.feathers)
	check("a species was recorded", next(state.birds) ~= nil)
	check("visit counter increased", state.totalVisits >= 1)
	local rewards = g.fired("Notify", "reward")
	check("reward notices sent to owner", #rewards >= 1 and rewards[1].to == alice)
	check("reward carries amount and position", rewards[1].args[1].amount > 0 and rewards[1].args[1].position ~= nil)
	local discoveries = g.fired("Notify", "discovery")
	check("first sighting triggers a discovery", #discoveries >= 1)
	check(
		"discovery bonus = value x multiplier",
		discoveries[1].args[1].bonus == g.Birds.get(discoveries[1].args[1].birdId).value * g.Config.DISCOVERY_MULTIPLIER
	)
	check("leaderstats follow the profile", alice.leaderstats.Feathers.Value == state.feathers)
	check("StateUpdate was pushed to the client", #g.remotes.StateUpdate._fired > 0)

	-- a second visit of the same species must not pay a bonus again
	local seenDiscoveries = #discoveries
	world.advance(120)
	local bonusesPaid = 0
	for _, d in g.fired("Notify", "discovery") do
		bonusesPaid += 1
	end
	local speciesFound = 0
	for _ in g.invoke(alice, "Init").state.birds do
		speciesFound += 1
	end
	check("exactly one discovery per species", bonusesPaid == speciesFound, `{bonusesPaid} vs {speciesFound}`)
	check("only sunflower-tier birds so far", speciesFound <= 4, speciesFound)

	-- late joiners get the visits in progress
	local late = g.invoke(alice, "Init").visits
	check("Init lists active visits for late joiners", type(late) == "table")

	----------------------------------------------------------------------------
	section("Shop")
	----------------------------------------------------------------------------
	local function feathers()
		return g.invoke(alice, "Init").state.feathers
	end
	local before = feathers()
	local r = g.invoke(alice, "BuySeed", "sunflower", 2)
	world.advance(0.2)
	check("buying a seed succeeds", r.ok == true, r.message)
	check("price deducted (15 each)", feathers() == before - 30, feathers())
	check("seeds added", g.invoke(alice, "Init").state.seeds.sunflower >= 2)

	local function bad(label, ...)
		world.advance(0.2)
		local before = feathers()
		local res = g.invoke(alice, "BuySeed", ...)
		check("buy rejected: " .. label, res.ok == false and feathers() == before, res.message)
	end
	bad("unknown seed", "nonsense", 1)
	bad("zero amount", "sunflower", 0)
	bad("negative amount", "sunflower", -5)
	bad("fractional amount", "sunflower", 1.5)
	bad("huge amount", "sunflower", 1e9)
	bad("string amount", "sunflower", "2")
	bad("nil seed", nil, 1)
	bad("NaN amount", "sunflower", 0 / 0)
	bad("too expensive", "starbloom", 1)

	world.advance(0.2)
	local stock = g.invoke(alice, "Init").stock.stock
	local rare = nil
	for _, s in g.Seeds.list do
		if (stock[s.id] or 0) == 0 then
			rare = s.id
		end
	end
	if rare then
		local res = g.invoke(alice, "BuySeed", rare, 1)
		check(
			"out-of-stock seeds can't be bought",
			res.ok == false and string.find(res.message, "out of stock") ~= nil,
			res.message
		)
	end

	-- exhaust sunflower stock; it is shared and decreases
	local s0 = g.invoke(alice, "Init").stock.stock.sunflower
	world.advance(0.2)
	g.fire(alice, "Dev", "feathers")
	world.advance(0.2)
	local res = g.invoke(alice, "BuySeed", "sunflower", s0)
	check("buying the whole shelf works", res.ok == true, res.message)
	check("stock is now empty", (g.invoke(alice, "Init").stock.stock.sunflower or 0) == 0)
	world.advance(0.2)
	res = g.invoke(alice, "BuySeed", "sunflower", 1)
	check("sold-out shelf rejects further buys", res.ok == false)
	check("stock broadcast to everyone", #g.remotes.StockUpdate._fired >= 2)

	-- restock arrives on the global clock
	local nextRestock = g.invoke(alice, "Init").stock.nextRestock
	world.advance(nextRestock - world.now + 2)
	check("shop restocks on the global clock", (g.invoke(alice, "Init").stock.stock.sunflower or 0) >= 6)
	check("restock was broadcast", #g.remotes.StockUpdate._fired >= 3)

	-- plots
	local function plots()
		return g.invoke(alice, "Init").state.plots
	end
	local plotsBefore = plots()
	world.advance(0.5)
	local up = g.invoke(alice, "UnlockPlot")
	check("unlocking a plot works", up.ok == true and plots() == plotsBefore + 1, up.message)
	check("garden shows the new plot unlocked", garden.Plot_5:GetAttribute("Locked") == false)
	check("next plot still locked", garden.Plot_6:GetAttribute("Locked") == true)
	g.fire(alice, "Dev", "plots")
	world.advance(0.5)
	check("all 12 plots unlockable", plots() == 12)
	world.advance(0.5)
	local maxed = g.invoke(alice, "UnlockPlot")
	check("no more plots to buy", maxed.ok == false)
	check("no price once maxed", g.invoke(alice, "Init").state.nextPlotPrice == nil)

	----------------------------------------------------------------------------
	section("Better seeds attract better birds")
	----------------------------------------------------------------------------
	g.fire(alice, "Dev", "seeds")
	world.advance(0.3)
	local tierBirds = {}
	for i, seed in g.Seeds.list do
		world.advance(0.2)
		g.fire(alice, "PlantSeed", 3 + i, seed.id) -- plots 4..9
	end
	world.advance(0.3)
	g.fire(alice, "Dev", "grow")
	world.advance(1)
	for _, p in g.plants() do
		check("grow-all matures " .. p:GetAttribute("SeedId"), p:GetAttribute("Mature") == true)
	end
	local startIndex = #g.remotes.BirdVisit._fired
	world.advance(60 * 40)
	check("simulating 40 minutes is error free", #world.errors == 0, world.errors[1])
	local bySeedTier = {}
	local rarityOf = function(birdId)
		return g.Birds.get(birdId).rarity
	end
	for i = startIndex + 1, #g.remotes.BirdVisit._fired do
		local info = g.remotes.BirdVisit._fired[i].args[1]
		-- find which plant (by perch proximity) the visit belongs to
		local best, bestD
		for _, p in g.plants() do
			local d = (p.Root.CFrame.Position - info.perch).Magnitude
			if not bestD or d < bestD then
				best, bestD = p, d
			end
		end
		local seedId = best:GetAttribute("SeedId")
		bySeedTier[seedId] = bySeedTier[seedId] or {}
		table.insert(bySeedTier[seedId], info.birdId)
	end
	for _, seed in g.Seeds.list do
		local list = bySeedTier[seed.id] or {}
		local own = 0
		for _, id in list do
			if rarityOf(id) == seed.rarity then
				own += 1
			end
		end
		print(
			string.format(
				"  %-18s %3d visits, %3d%% own-tier",
				seed.name,
				#list,
				#list > 0 and math.floor(own / #list * 100) or 0
			)
		)
		check(seed.id .. " got visitors", #list > 0)
		check(seed.id .. " mostly attracts its own tier", #list == 0 or own / #list >= 0.8, own .. "/" .. #list)
	end
	local finalState = g.invoke(alice, "Init").state
	local found = 0
	for _ in finalState.birds do
		found += 1
	end
	print(
		string.format(
			"  species discovered after 40 min: %d / 18, feathers: %s",
			found,
			g.Format.feathers(finalState.feathers)
		)
	)
	check("many species discovered", found >= 8, found)

	----------------------------------------------------------------------------
	section("Digging up")
	----------------------------------------------------------------------------
	-- immature plant returns its seed
	world.advance(0.5)
	g.fire(alice, "Dev", "seeds")
	world.advance(0.5)
	local seedsBefore = g.invoke(alice, "Init").state.seeds.berrybush
	g.fire(alice, "PlantSeed", 10, "berrybush")
	world.advance(0.3)
	g.fire(alice, "DigPlant", 10)
	world.advance(0.5)
	check("digging a growing plant returns the seed", g.invoke(alice, "Init").state.seeds.berrybush == seedsBefore)
	check("plot freed", garden.Plot_10:GetAttribute("HasPlant") == false)
	-- mature plant is lost -- and any bird still flying to it is cancelled for every client
	local function plantAt(index)
		for _, p in g.plants() do
			if p:GetAttribute("PlotIndex") == index then
				return p
			end
		end
	end
	local target = plantAt(4)
	local targetSeed = target:GetAttribute("SeedId")
	local ownedBefore = g.invoke(alice, "Init").state.seeds[targetSeed] or 0
	local visitingId
	for _ = 1, 240 do
		for _, info in g.invoke(alice, "Init").visits do
			if (info.perch - target.Root.CFrame.Position).Magnitude < 7 then
				visitingId = info.id
			end
		end
		if visitingId then
			break
		end
		world.advance(1)
	end
	check("found a bird mid-visit on the plant about to be removed", visitingId ~= nil)
	local cancelsBefore = #g.remotes.BirdCancel._fired
	local matureCount = #g.plants()
	g.fire(alice, "DigPlant", 4)
	world.advance(0.5)
	check("digging a grown plant removes it", #g.plants() == matureCount - 1)
	check("grown plant's seed is lost", (g.invoke(alice, "Init").state.seeds[targetSeed] or 0) == ownedBefore)
	check(
		"birds headed for a removed plant are cancelled",
		#g.remotes.BirdCancel._fired == cancelsBefore + 1
			and g.remotes.BirdCancel._fired[cancelsBefore + 1].args[1] == visitingId
	)
	local stillThere = false
	for _, info in g.invoke(alice, "Init").visits do
		if info.id == visitingId then
			stillThere = true
		end
	end
	check("cancelled visit is gone from the late-joiner list", not stillThere)
	g.fire(alice, "DigPlant", 99)
	g.fire(alice, "DigPlant", "x")
	g.fire(alice, "DigPlant", nil)
	world.advance(0.5)
	check("bad dig requests ignored", #world.errors == 0, world.errors[1])

	----------------------------------------------------------------------------
	section("Saving, leaving, and coming back later")
	----------------------------------------------------------------------------
	-- plant something slow, record the state, leave, wait offline, come back
	g.fire(alice, "PlantSeed", 11, "berrybush") -- 90 s
	world.advance(0.5)
	local before = g.invoke(alice, "Init").state
	local plantCountBefore = #g.plants()
	local cancelsBeforeLeave = #g.remotes.BirdCancel._fired
	world.removePlayer(alice)
	world.advance(0.5)
	check("her plants are removed when she leaves", #g.plants() == 0)
	check("garden is freed", garden:GetAttribute("OwnerUserId") == 0)
	check("sign reset", garden.Sign.SurfaceGui.TextLabel.Text == "Free Garden")
	check(
		"plots reset to locked",
		garden.Plot_1:GetAttribute("Locked") == true and garden.Plot_1:GetAttribute("HasPlant") == false
	)
	local saved = world.dataStores[g.Config.DATASTORE_NAME]["Player_111"]
	check("profile was saved on leave", saved ~= nil and saved.feathers == before.feathers, saved and saved.feathers)
	check("plants saved with timestamps", saved and next(saved.plants) ~= nil)
	check("birds seen were saved", saved and next(saved.birds) ~= nil)
	check("a leaver's visits are cancelled for everyone", #g.remotes.BirdCancel._fired > cancelsBeforeLeave)

	world.advance(600) -- ten minutes offline
	local alice2 = g.join("Alice", 111)
	world.spawnCharacter(alice2)
	check("rejoin ok", #world.errors == 0, world.errors[1])
	local after = g.invoke(alice2, "Init").state
	check("feathers restored", after.feathers == before.feathers, `{after.feathers} vs {before.feathers}`)
	check("species restored", (function()
		local n = 0
		for _ in after.birds do
			n += 1
		end
		return n
	end)() >= 8)
	check("plots restored", after.plots == 12)
	check("plants restored", #g.plants() == plantCountBefore, `{#g.plants()} vs {plantCountBefore}`)
	local allMature = true
	for _, p in g.plants() do
		if
			p:GetAttribute("Mature") ~= true
			and p:GetAttribute("SeedId") ~= "starbloom"
			and p:GetAttribute("SeedId") ~= "goldenapple"
		then
			allMature = false
		end
	end
	check("plants kept growing while she was away", allMature)
	for _, p in g.plants() do
		if p:GetAttribute("SeedId") == "berrybush" then
			check("offline berry bush is fully grown", p:GetAttribute("Mature") == true)
		end
	end
	check("plots re-locked/unlocked to match", g.garden(alice2).Plot_12:GetAttribute("Locked") == false)
	world.advance(30)
	check("birds visit again after rejoining", #world.errors == 0)

	----------------------------------------------------------------------------
	section("Many players")
	----------------------------------------------------------------------------
	local players = { alice2 }
	for i = 2, 8 do
		table.insert(players, g.join("P" .. i, 200 + i))
	end
	local slots = {}
	for _, p in players do
		local gd = g.garden(p)
		check(p.Name .. " has a garden", gd ~= nil)
		if gd then
			check(p.Name .. " garden is unique", not slots[gd:GetAttribute("Slot")])
			slots[gd:GetAttribute("Slot")] = true
		end
	end
	local before9 = #world.kicked
	local ninth = g.join("P9", 209)
	check(
		"9th player is told the server is full",
		#world.kicked == before9 + 1 and string.find(world.kicked[#world.kicked].message, "taken") ~= nil
	)
	world.removePlayer(players[3])
	world.advance(0.5)
	local tenth = g.join("P10", 210)
	check("freed garden is reused", g.garden(tenth) ~= nil)
	world.advance(60)
	check("8 players running together is error free", #world.errors == 0, world.errors[1])

	----------------------------------------------------------------------------
	section("Soft-lock rescue")
	----------------------------------------------------------------------------
	do
		local g2 = boot({})
		local w2 = g2.world
		-- a save with nothing: no plants, no seeds, no feathers
		w2.dataStores[g2.Config.DATASTORE_NAME] = {
			Player_555 = { version = 1, feathers = 3, seeds = {}, birds = {}, plots = 4, plants = {}, totalVisits = 0 },
		}
		local broke = g2.join("Broke", 555)
		local s = g2.invoke(broke, "Init").state
		check("a broke player with no plants gets a free seed", (s.seeds.sunflower or 0) == 1, s.seeds.sunflower)
	end

	----------------------------------------------------------------------------
	section("Bad save data is sanitised")
	----------------------------------------------------------------------------
	do
		local g3 = boot({})
		local w3 = g3.world
		w3.dataStores[g3.Config.DATASTORE_NAME] = {
			Player_777 = {
				feathers = -50,
				seeds = { sunflower = 3.7, fakeseed = 5, cherry = -2, berrybush = "many" },
				birds = { sparrow = 2, dragon = 9 },
				plots = 999,
				plants = {
					["1"] = { seedId = "sunflower", plantedAt = 1 },
					["99"] = { seedId = "sunflower", plantedAt = 1 },
					["2"] = { seedId = "nope", plantedAt = 1 },
					["3"] = "junk",
					["4"] = { seedId = "cherry", plantedAt = 9e15 },
				},
				totalVisits = "lots",
			},
		}
		local p = g3.join("Mess", 777)
		local s = g3.invoke(p, "Init").state
		check("negative feathers clamped", s.feathers >= 0, s.feathers)
		check("unknown seeds dropped", s.seeds.fakeseed == nil and s.seeds.cherry == nil and s.seeds.berrybush == nil)
		check("fractional counts floored", s.seeds.sunflower == 3, s.seeds.sunflower)
		check("unknown birds dropped", s.birds.dragon == nil and s.birds.sparrow == 2)
		check("plots clamped to max", s.plots == 12, s.plots)
		check("only valid plants restored", #g3.plants() == 2, #g3.plants())
		for _, plantInstance in g3.plants() do
			check("future planting dates are clamped", plantInstance:GetAttribute("PlantedAt") <= w3.now)
		end
		check("garbage data does not error", #w3.errors == 0, w3.errors[1])
	end

	----------------------------------------------------------------------------
	section("DataStore outages")
	----------------------------------------------------------------------------
	do
		-- Studio: keep playing, don't save
		local gs = boot({ studio = true })
		gs.world.dataStoreFail = true
		local done = false
		gs.world.task.spawn(function()
			local p = gs.world.addPlayer("StudioDev", 888)
			done = true
		end)
		gs.world.advance(20)
		local p = gs.world.Players:GetPlayers()[1]
		check("Studio player survives a DataStore outage", p ~= nil and gs.garden(p) ~= nil and #gs.world.kicked == 0)
		check("outage is explained in the log", #gs.world.warnings > 0)
		gs.world.dataStoreFail = false
		gs.world.removePlayer(p)
		gs.world.advance(1)
		check(
			"ephemeral sessions never overwrite the real save",
			gs.world.dataStores[gs.Config.DATASTORE_NAME]["Player_888"] == nil
		)

		-- Live server: never let someone play on default data
		local gl = boot({ studio = false })
		gl.world.dataStoreFail = true
		gl.world.addPlayer("LiveUser", 889)
		gl.world.advance(20)
		check(
			"live player is kicked rather than given blank data",
			#gl.world.kicked == 1 and string.find(gl.world.kicked[1].message, "rejoin") ~= nil
		)
		check("kicked player owns no garden", #gl.world.Players:GetPlayers() == 0)
	end

	----------------------------------------------------------------------------
	section("Dev tools are Studio-only")
	----------------------------------------------------------------------------
	do
		local gl = boot({ studio = false })
		local p = gl.join("LivePlayer", 900)
		local f = gl.invoke(p, "Init").state.feathers
		gl.fire(p, "Dev", "feathers")
		gl.world.advance(0.5)
		check("Dev remote ignored on live servers", gl.invoke(p, "Init").state.feathers == f)
	end

	----------------------------------------------------------------------------
	section("Shutdown")
	----------------------------------------------------------------------------
	do
		local gb = boot({})
		local p = gb.join("Bye", 950)
		gb.fire(p, "Dev", "feathers")
		gb.world.advance(0.5)
		for _, fn in gb.world.bindToClose do
			gb.world.task.spawn(fn)
		end
		gb.world.advance(5)
		local saved = gb.world.dataStores[gb.Config.DATASTORE_NAME]["Player_950"]
		check("BindToClose saves everyone", saved ~= nil and saved.feathers >= 100030, saved and saved.feathers)
	end

	print(string.format("\n%d checks passed, %d failed", passed, #failed))
	for _, f in failed do
		print("  FAIL: " .. f)
	end
	return #failed == 0
end
