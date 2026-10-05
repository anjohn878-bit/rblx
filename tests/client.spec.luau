--!nocheck
-- Client simulation: the real init.client.luau and every UI module run in a
-- second mock world that is bridged to a live server world (remotes forwarded
-- both ways, garden/plants replicated). A scripted player then uses the UI.

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

	----------------------------------------------------------------------------
	-- world setup + bridge
	----------------------------------------------------------------------------
	local S = H.newWorld({ studio = true })
	S.runScript(S.serverScript)
	local C = H.newWorld({ isClient = true, studio = true })
	local Seeds = S.requireShared("Seeds")
	local Birds = S.requireShared("Birds")
	local Config = S.requireShared("Config")

	local aliceS = S.addPlayer("Alice", 111)
	S.advance(0.1)
	S.spawnCharacter(aliceS)
	local aliceC = C.makeLocalPlayer("Alice", 111)

	-- remotes exist on both sides (the server creates them; clients see copies)
	local remotesC = C.Instance.new("Folder")
	remotesC.Name = "Remotes"
	remotesC.Parent = C.services.ReplicatedStorage
	for _, r in S.services.ReplicatedStorage.Remotes:GetChildren() do
		local copy = C.Instance.new(r.ClassName)
		copy.Name = r.Name
		copy.Parent = remotesC
	end
	function S.onFireClient(remote, target, packed)
		if target == "all" or target == aliceS then
			remotesC[remote.Name].OnClientEvent:Fire(table.unpack(packed, 1, packed.n))
		end
	end
	function C.onFireServer(remote, packed)
		S.localPlayer = aliceS
		S.services.ReplicatedStorage.Remotes[remote.Name]:FireServer(table.unpack(packed, 1, packed.n))
	end
	function C.onInvokeServer(remote, packed)
		S.localPlayer = aliceS
		return S.services.ReplicatedStorage.Remotes[remote.Name]:InvokeServer(table.unpack(packed, 1, packed.n))
	end

	-- replicate Gardens/Plants from server to client (what Roblox does for free)
	local function copyInstance(src)
		local dst = C.Instance.new(src.ClassName)
		dst.Name = src.Name
		for k, v in src._attrs do
			dst:SetAttribute(k, v)
		end
		for _, key in { "CFrame", "Size", "Transparency", "Anchored" } do
			if rawget(src, key) ~= nil then
				rawset(dst, key, rawget(src, key))
			end
		end
		for _, c in src._children do
			copyInstance(c).Parent = dst
		end
		if rawget(src, "PrimaryPart") then
			dst.PrimaryPart = dst:FindFirstChild(src.PrimaryPart.Name)
		end
		for _, tag in S.tagsOf(src) do
			C.services.CollectionService:AddTag(dst, tag)
		end
		return dst
	end
	local function syncAttrs(src, dst, depth)
		for k, v in src._attrs do
			dst:SetAttribute(k, v)
		end
		if depth > 0 then
			for _, c in src._children do
				local d = dst:FindFirstChild(c.Name)
				if d then
					syncAttrs(c, d, depth - 1)
				end
			end
		end
	end
	local function sync()
		for _, name in { "Gardens", "Plants" } do
			local sf = S.workspace:FindFirstChild(name)
			if sf then
				local cf = C.workspace:FindFirstChild(name)
				if not cf then
					cf = C.Instance.new("Folder")
					cf.Name = name
					cf.Parent = C.workspace
				end
				local seen = {}
				for _, sm in sf._children do
					seen[sm.Name] = true
					local cm = cf:FindFirstChild(sm.Name)
					if not cm then
						copyInstance(sm).Parent = cf
					else
						syncAttrs(sm, cm, name == "Gardens" and 1 or 0)
					end
				end
				for _, cm in table.clone(cf._children) do
					if not seen[cm.Name] then
						cm:Destroy()
					end
				end
			end
		end
	end
	local function step(total, dt)
		dt = dt or 0.25
		local t = 0
		while t < total - 1e-9 do
			local d = math.min(dt, total - t)
			S.advance(d)
			sync()
			C.advance(d)
			C.services.RunService.RenderStepped:Fire(d)
			t += d
		end
	end

	-- helpers to poke at the UI tree
	local function textOf(inst)
		local t = rawget(inst, "Text")
		return type(t) == "string" and t or nil
	end
	local function findText(root, sub)
		for _, d in root:GetDescendants() do
			local t = textOf(d)
			if t and string.find(t, sub, 1, true) then
				return d
			end
		end
	end
	local function findButton(root, text)
		for _, d in root:GetDescendants() do
			if d.ClassName == "TextButton" and textOf(d) == text then
				return d
			end
		end
	end
	local function clientPlot(i)
		for _, g in C.workspace.Gardens:GetChildren() do
			if g:GetAttribute("OwnerUserId") == 111 then
				return g["Plot_" .. i]
			end
		end
	end
	local function serverState()
		S.localPlayer = aliceS
		return S.services.ReplicatedStorage.Remotes.Init.OnServerInvoke(aliceS).state
	end

	----------------------------------------------------------------------------
	section("Client boots")
	----------------------------------------------------------------------------
	sync()
	C.runScript(C.clientScript)
	step(0.5)
	check("client script ran without errors", #C.errors == 0, C.errors[1])
	check("server still healthy", #S.errors == 0, S.errors[1])
	local gui = aliceC.PlayerGui:FindFirstChild("BirdGardenUI")
	check("main ScreenGui was created", gui ~= nil)
	for _, name in
		{
			"Toasts",
			"DiscoveryBanner",
			"Feathers",
			"SideButtons",
			"Objective",
			"Hotbar",
			"ShopOverlay",
			"BirdpediaOverlay",
			"DevPanel",
		}
	do
		check("UI has " .. name, gui:FindFirstChild(name) ~= nil)
	end
	check("feathers counter shows 30", findText(gui.Feathers, "30") ~= nil)
	check("Birdpedia button shows 0/18", findButton(gui.SideButtons, "Birdpedia 0/18") ~= nil)

	local hotbar = gui.Hotbar.Slots
	local visible = {}
	for _, slot in hotbar:GetChildren() do
		if slot.ClassName == "Frame" and slot.Visible then
			table.insert(visible, slot.Name)
		end
	end
	check("hotbar shows only the owned seed", #visible == 1 and visible[1] == "sunflower", table.concat(visible, ","))
	check("hotbar shows the count", findText(hotbar.sunflower, "x3") ~= nil)
	check("hotbar names the selected seed", findText(gui.Hotbar, "Sunflower") ~= nil)
	check(
		"objective guides a new player",
		string.find(textOf(gui.Objective), "soil plot", 1, true) ~= nil
			and string.find(textOf(gui.Objective), "Sunflower", 1, true) ~= nil,
		textOf(gui.Objective)
	)

	----------------------------------------------------------------------------
	section("Proximity prompts")
	----------------------------------------------------------------------------
	local plot1, plot5, plot6 = clientPlot(1), clientPlot(5), clientPlot(6)
	local p1, p5, p6 =
		plot1:FindFirstChild("PlotPrompt"), plot5:FindFirstChild("PlotPrompt"), plot6:FindFirstChild("PlotPrompt")
	check(
		"owned empty plot has a plant prompt",
		p1 ~= nil and p1.Enabled == true and p1.ActionText == "Plant Sunflower",
		p1 and p1.ActionText
	)
	check(
		"next locked plot offers an unlock",
		p5 ~= nil and p5.Enabled == true and string.find(p5.ActionText, "150") ~= nil,
		p5 and p5.ActionText
	)
	check("later locked plots stay quiet", p6 ~= nil and p6.Enabled == false)
	local others = 0
	for _, g in C.workspace.Gardens:GetChildren() do
		if g:GetAttribute("OwnerUserId") ~= 111 then
			for _, d in g:GetDescendants() do
				if d.ClassName == "ProximityPrompt" then
					others += 1
				end
			end
		end
	end
	check("no prompts appear in other people's gardens", others == 0, others)

	----------------------------------------------------------------------------
	section("Planting through the UI")
	----------------------------------------------------------------------------
	p1.Triggered:Fire()
	step(1)
	check("server planted it", serverState().seeds.sunflower == 2)
	local plantC = C.workspace.Plants:GetChildren()[1]
	check("plant replicated to the client", plantC ~= nil)
	check("plot prompt hides once occupied", p1.Enabled == false)
	local label = plantC.Root:FindFirstChild("PlantLabel")
	check("plant gets a floating label", label ~= nil)
	check(
		"label shows name and countdown",
		label and findText(label, "Sunflower") ~= nil and findText(label, "Growing") ~= nil
	)
	local dig = plantC.Root:FindFirstChild("DigPrompt")
	check(
		"dig prompt appears on your plant",
		dig ~= nil and dig.HoldDuration > 1 and string.find(dig.ActionText, "seed returned") ~= nil,
		dig and dig.ActionText
	)
	check("hotbar count dropped", findText(hotbar.sunflower, "x2") ~= nil)
	check(
		"objective now says it's growing",
		string.find(textOf(gui.Objective), "growing", 1, true) ~= nil,
		textOf(gui.Objective)
	)

	step(8)
	local growingText = findText(label, "Growing")
	check(
		"countdown ticks down",
		growingText ~= nil and growingText.Text ~= "Growing  0:20",
		growingText and growingText.Text
	)

	----------------------------------------------------------------------------
	section("Blooming and birds")
	----------------------------------------------------------------------------
	step(14)
	check("label switches to blooming", findText(label, "Blooming") ~= nil)
	check("dig prompt warns the seed is lost", string.find(dig.ActionText, "seed is lost") ~= nil, dig.ActionText)
	check("bloom toast is shown", findText(gui.Toasts, "fully grown") ~= nil)

	-- run frame by frame until the first bird has landed
	local visit
	for _ = 1, 600 do
		step(1 / 30, 1 / 30)
		visit = S.services.ReplicatedStorage.Remotes.BirdVisit._fired[1]
			and S.services.ReplicatedStorage.Remotes.BirdVisit._fired[1].args[1]
		if visit then
			break
		end
	end
	check("a bird visit reached the client", visit ~= nil)
	local birdsFolder = C.workspace.ClientBirds
	step(1 / 30, 1 / 30)
	check("bird model is spawned locally", #birdsFolder:GetChildren() == 1)
	local rigModel = birdsFolder:GetChildren()[1]
	check("bird is named for its species", rigModel.Name == visit.birdId)
	check(
		"bird has a name tag",
		rigModel.Root:FindFirstChild("NameTag") ~= nil
			and findText(rigModel.Root.NameTag, Birds.get(visit.birdId).name) ~= nil
	)

	-- sample the bird in flight: it must move smoothly and flap
	local positions, wingAngles = {}, {}
	for i = 1, 90 do
		step(1 / 30, 1 / 30)
		table.insert(positions, rigModel.Root.CFrame.Position)
		table.insert(wingAngles, rigModel.WingR.CFrame.Position.Y)
	end
	local maxJump = 0
	for i = 2, #positions do
		maxJump = math.max(maxJump, (positions[i] - positions[i - 1]).Magnitude)
	end
	check("bird flight is smooth frame to frame", maxJump < 3, maxJump)
	local lo, hi = math.huge, -math.huge
	for _, y in wingAngles do
		lo, hi = math.min(lo, y), math.max(hi, y)
	end
	check("wings flap while flying", hi - lo > 0.2, hi - lo)

	-- wait for landing and check it sits on the perch
	local landedAt = visit.startTime + visit.arrive + 1.5
	step(math.max(0, landedAt - C.now))
	local feetPos = rigModel.Root.CFrame.Position
	check("bird sits on the perch", (feetPos - visit.perch).Magnitude < 0.3, (feetPos - visit.perch).Magnitude)
	local w1 = rigModel.WingR.CFrame.Position
	step(0.5)
	check("wings fold while perched", (rigModel.WingR.CFrame.Position - w1).Magnitude < 0.2)

	local rewardAnchor
	for _, c in C.workspace.ClientFX:GetChildren() do
		if c.Name == "RewardAnchor" then
			rewardAnchor = c
		end
	end
	check("+feathers popup appeared over the bird", rewardAnchor ~= nil)
	local state = serverState()
	check("feathers went up on the HUD", findText(gui.Feathers, tostring(state.feathers)) ~= nil, state.feathers)
	check(
		"discovery banner shows",
		gui.DiscoveryBanner.Visible == true and findText(gui.DiscoveryBanner, "NEW BIRD DISCOVERED") ~= nil
	)
	check("banner names the species", findText(gui.DiscoveryBanner, Birds.get(visit.birdId).name) ~= nil)
	check("Birdpedia button counts it", findButton(gui.SideButtons, "Birdpedia 1/18") ~= nil)

	-- let the visit finish: the bird disappears again
	step(visit.stay + visit.leave + 2)
	local stillThere = false
	for _, b in birdsFolder:GetChildren() do
		if b.Name == visit.birdId and b == rigModel then
			stillThere = true
		end
	end
	check("bird is removed after it leaves", not stillThere)
	check("no errors during the visit", #C.errors == 0 and #S.errors == 0, C.errors[1] or S.errors[1])

	----------------------------------------------------------------------------
	section("Seed shop window")
	----------------------------------------------------------------------------
	local overlay = gui.ShopOverlay
	check("shop starts closed", overlay.Visible == false)
	gui.SideButtons.Shop.Activated:Fire()
	step(0.3)
	check("shop button opens the shop", overlay.Visible == true)
	local rowCount = 0
	for _, seed in Seeds.list do
		if overlay:FindFirstChild(seed.id, true) then
			rowCount += 1
		end
	end
	check("a row for every seed", rowCount == 6, rowCount)
	check("shop shows the restock countdown", findText(overlay, "New stock in") ~= nil)
	local row = overlay:FindFirstChild("sunflower", true)
	local buy = findButton(row, "Buy")
	check("buy button exists", buy ~= nil)
	check("sunflower affordable and in stock", buy and buy.Active == true)
	local starbloomBuy = findButton(overlay:FindFirstChild("starbloom", true), "Buy")
	check("unaffordable seed is greyed out", starbloomBuy and starbloomBuy.Active == false)
	check("price is shown", findText(row, "15") ~= nil)
	check("expected pay per visit is shown", findText(row, "per visit") ~= nil)
	check("shop lists attracted birds", findText(row, "Attracts: House Sparrow") ~= nil)

	local before = serverState()
	buy.Activated:Fire()
	step(0.5)
	local after = serverState()
	check(
		"clicking Buy buys",
		after.seeds.sunflower == before.seeds.sunflower + 1 and after.feathers == before.feathers - 15,
		`{after.feathers} vs {before.feathers}`
	)
	check("HUD reflects the purchase", findText(gui.Feathers, tostring(after.feathers)) ~= nil)
	check("purchase toast shown", findText(gui.Toasts, "Bought 1x Sunflower") ~= nil)

	-- buy-max button
	step(0.3)
	S.localPlayer = aliceS
	local maxButton
	for _, d in row:GetDescendants() do
		if d.ClassName == "TextButton" and textOf(d) and string.find(textOf(d), "^Buy x") then
			maxButton = d
		end
	end
	check(
		"buy-max shows a quantity when affordable",
		maxButton ~= nil and maxButton.Active == true,
		maxButton and maxButton.Text
	)
	local feathersBefore = serverState().feathers
	maxButton.Activated:Fire()
	step(0.5)
	check("buy-max spends feathers", serverState().feathers < feathersBefore)

	-- close
	overlay.Activated:Fire()
	check("clicking outside closes the shop", overlay.Visible == false)

	----------------------------------------------------------------------------
	section("Birdpedia")
	----------------------------------------------------------------------------
	local pedia = gui.BirdpediaOverlay
	gui.SideButtons.Birdpedia.Activated:Fire()
	step(0.3)
	check("Birdpedia opens", pedia.Visible == true)
	local cardCount = 0
	for _, bird in Birds.list do
		if pedia:FindFirstChild(bird.id, true) then
			cardCount += 1
		end
	end
	check("a card for every species", cardCount == 18, cardCount)
	local seenCard = pedia:FindFirstChild(visit.birdId, true)
	check("discovered bird shows its name", findText(seenCard, Birds.get(visit.birdId).name) ~= nil)
	check("discovered bird shows how often it was seen", findText(seenCard, "Seen x") ~= nil)
	local unseen
	for _, bird in Birds.list do
		if bird.id ~= visit.birdId then
			unseen = bird
		end
	end
	local hidden = pedia:FindFirstChild(unseen.id, true)
	check("undiscovered birds are hidden", findText(hidden, "???") ~= nil)
	check("undiscovered birds hint which seed attracts them", findText(hidden, "Try:") ~= nil)
	check("header counts discoveries", findText(pedia, "1 / 18 discovered") ~= nil)
	local silhouetteColor = hidden:FindFirstChildOfClass("ViewportFrame"):FindFirstChildOfClass("Model").Body.Color
	check("silhouette is dark", silhouetteColor.R < 0.2 and silhouetteColor.G < 0.2)
	-- keyboard shortcut
	C.services.UserInputService.InputBegan:Fire({ KeyCode = C.env.Enum.KeyCode.B }, false)
	check("B closes the Birdpedia", pedia.Visible == false)
	C.services.UserInputService.InputBegan:Fire({ KeyCode = C.env.Enum.KeyCode.B }, false)
	check("B opens the Birdpedia", pedia.Visible == true)
	C.services.UserInputService.InputBegan:Fire({ KeyCode = C.env.Enum.KeyCode.B }, true)
	check("keys typed into chat are ignored", pedia.Visible == true)
	pedia.Activated:Fire()

	-- the plaza kiosks
	local kiosk = C.Instance.new("ProximityPrompt")
	kiosk.Name = "ShopPrompt"
	C.services.ProximityPromptService.PromptTriggered:Fire(kiosk)
	check("shop kiosk prompt opens the shop", overlay.Visible == true)
	overlay.Activated:Fire()
	local board = C.Instance.new("ProximityPrompt")
	board.Name = "BirdpediaPrompt"
	C.services.ProximityPromptService.PromptTriggered:Fire(board)
	check("Birdpedia board prompt opens the Birdpedia", pedia.Visible == true)
	pedia.Activated:Fire()

	----------------------------------------------------------------------------
	section("Hotbar selection and dev tools")
	----------------------------------------------------------------------------
	local devPanel = gui.DevPanel
	findButton(devPanel, "+5 of every seed").Activated:Fire()
	step(0.5)
	local slotsVisible = 0
	for _, slot in hotbar:GetChildren() do
		if slot.ClassName == "Frame" and slot.Visible then
			slotsVisible += 1
		end
	end
	check("all six seeds appear in the hotbar", slotsVisible == 6, slotsVisible)
	C.services.UserInputService.InputBegan:Fire({ KeyCode = C.env.Enum.KeyCode.Two }, false)
	step(0.2)
	check("number keys select seeds", findText(gui.Hotbar, "Berry Bush") ~= nil)
	local p2 = clientPlot(2):FindFirstChild("PlotPrompt")
	check("plant prompt follows the selected seed", p2.ActionText == "Plant Berry Bush", p2.ActionText)
	-- clicking a slot
	local click
	for _, d in hotbar.cherry:GetChildren() do
		if d.ClassName == "TextButton" then
			click = d
		end
	end
	click.Activated:Fire()
	step(0.2)
	check("clicking a slot selects it", clientPlot(2):FindFirstChild("PlotPrompt").ActionText == "Plant Cherry Blossom")
	p2.Triggered:Fire()
	step(0.5)
	local cherryPlanted = false
	for _, p in C.workspace.Plants:GetChildren() do
		if p:GetAttribute("SeedId") == "cherry" then
			cherryPlanted = true
		end
	end
	check("planting with the selected seed works", cherryPlanted)
	local cherryLabel
	for _, p in C.workspace.Plants:GetChildren() do
		if p:GetAttribute("SeedId") == "cherry" then
			cherryLabel = p.Root:FindFirstChild("PlantLabel")
		end
	end
	local rare = Config.RARITY_COLORS.Rare
	local strokeColor
	for _, d in cherryLabel:GetDescendants() do
		if d.ClassName == "UIStroke" then
			strokeColor = d.Color
		end
	end
	check(
		"plant label colours follow rarity",
		strokeColor ~= nil and math.abs(strokeColor.R - rare.R) < 0.01 and math.abs(strokeColor.B - rare.B) < 0.01
	)

	findButton(devPanel, "Grow all plants").Activated:Fire()
	step(3)
	findButton(devPanel, "+100K Feathers").Activated:Fire()
	step(0.5)
	check(
		"feathers shown with thousands separators",
		findText(gui.Feathers, ",") ~= nil,
		textOf(findText(gui.Feathers, ",") or gui.Feathers)
	)

	----------------------------------------------------------------------------
	section("Unlocking plots and digging")
	----------------------------------------------------------------------------
	local plotsBefore = serverState().plots
	local unlockPrompt = clientPlot(plotsBefore + 1):FindFirstChild("PlotPrompt")
	check("next plot offers an unlock", unlockPrompt.Enabled == true)
	unlockPrompt.Triggered:Fire()
	step(0.6)
	check("unlocking via prompt works", serverState().plots == plotsBefore + 1)
	check("toast confirms the unlock", findText(gui.Toasts, "unlocked") ~= nil)
	check(
		"the new plot becomes plantable",
		clientPlot(plotsBefore + 1):FindFirstChild("PlotPrompt").ActionText:find("^Plant") ~= nil,
		clientPlot(plotsBefore + 1):FindFirstChild("PlotPrompt").ActionText
	)
	check(
		"the next one offers the next unlock",
		clientPlot(plotsBefore + 2):FindFirstChild("PlotPrompt").Enabled == true
	)

	local victim = C.workspace.Plants:GetChildren()[1]
	local plotIndex = victim:GetAttribute("PlotIndex")
	local digPrompt = victim.Root:FindFirstChild("DigPrompt")
	digPrompt.Triggered:Fire()
	step(0.6)
	local gone = true
	for _, p in C.workspace.Plants:GetChildren() do
		if p:GetAttribute("PlotIndex") == plotIndex then
			gone = false
		end
	end
	check("digging removes the plant for the client", gone)
	check("the plot can be planted again", clientPlot(plotIndex):FindFirstChild("PlotPrompt").Enabled == true)

	----------------------------------------------------------------------------
	section("Long idle session")
	----------------------------------------------------------------------------
	-- fill the garden with plants of every tier so lots of visits overlap
	for i, seed in Seeds.list do
		C.services.UserInputService.InputBegan:Fire(
			{ KeyCode = C.env.Enum.KeyCode[({ "One", "Two", "Three", "Four", "Five", "Six" })[i]] },
			false
		)
		local promptsFree = {}
		for idx = 1, 12 do
			local pr = clientPlot(idx):FindFirstChild("PlotPrompt")
			if pr and pr.Enabled and string.find(pr.ActionText, "^Plant") then
				table.insert(promptsFree, pr)
			end
		end
		if promptsFree[1] then
			promptsFree[1].Triggered:Fire()
		end
		step(0.3)
	end
	findButton(devPanel, "Grow all plants").Activated:Fire()
	step(3)
	local maxConcurrent, samples = 0, 0
	for _ = 1, 300 do
		step(1, 0.5)
		maxConcurrent = math.max(maxConcurrent, #C.workspace.ClientBirds:GetChildren())
		samples += 1
	end
	check(
		"five idle minutes with many birds is error free",
		#C.errors == 0 and #S.errors == 0,
		C.errors[1] or S.errors[1]
	)
	print(string.format("  peak simultaneous birds on screen: %d", maxConcurrent))
	check("several birds are on screen at once", maxConcurrent >= 4, maxConcurrent)
	local before = #C.workspace.ClientBirds:GetChildren()
	step(120, 0.5)
	check(
		"birds don't leak (models are cleaned up)",
		#C.workspace.ClientBirds:GetChildren() <= before + 6,
		#C.workspace.ClientBirds:GetChildren()
	)
	local tags = 0
	for _, g in C.workspace.ClientFX:GetChildren() do
		tags += 1
	end
	check("reward popups are cleaned up", tags <= 12, tags)

	print(string.format("\n%d checks passed, %d failed", passed, #failed))
	for _, f in failed do
		print("  FAIL: " .. f)
	end
	return #failed == 0
end
