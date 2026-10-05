--!nocheck
-- Plays through the game in a simulated server + client.
--
-- Usage (from the repo root, needs Lune):
--   lune run tests/run

local process = require("@lune/process")
local roblox = require("@lune/roblox")

local Mock = require("./mock")

local Instance = roblox.Instance
local Vector3 = roblox.Vector3
local CFrame = roblox.CFrame

local game = Mock.Game
local workspace = Mock.Workspace
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local StarterPlayerScripts = Instance.new("StarterPlayerScripts")
StarterPlayerScripts.Parent = game:GetService("StarterPlayer")

local failures = 0
local function check(condition, message)
	if condition then
		print("  ok   " .. message)
	else
		failures += 1
		print("  FAIL " .. message)
	end
end

local function section(name)
	print("\n== " .. name)
end

-- The default baseplate from the place file
local baseplate = Instance.new("Part")
baseplate.Name = "Baseplate"
baseplate.Size = Vector3.new(2048, 16, 2048)
baseplate.CFrame = CFrame.new(0, -8, 0)
local texture = Instance.new("Texture")
texture.Parent = baseplate
baseplate.Parent = workspace

local shared = Mock.LoadFolder("src/shared", "Shared", ReplicatedStorage)
local server = Mock.LoadFolder("src/server", "BirdGardenServer", ServerScriptService)
local client = Mock.LoadFolder("src/client", "BirdGardenClient", StarterPlayerScripts)

------------------------------------------------------------------------------
section("Server starts and builds the world")

Mock.RunScript(server.Main, "server")
Mock.Advance(1)

local Config = Mock.Require(shared.Config, "server")
local Seeds = Mock.Require(shared.Seeds, "server")
local Birds = Mock.Require(shared.Birds, "server")
local Pets = Mock.Require(shared.Pets, "server")
local Util = Mock.Require(shared.Util, "server")
local DataService = Mock.Require(server.DataService, "server")
local PetService = Mock.Require(server.PetService, "server")

local root = workspace:FindFirstChild("BirdGarden")
check(root ~= nil, "BirdGarden folder exists")
local plotsFolder = root and root:FindFirstChild("Plots")
check(plotsFolder and #plotsFolder:GetChildren() == Config.PlotCount, "all plots built")
local plot1 = plotsFolder and plotsFolder:FindFirstChild("Plot1")
check(plot1 and plot1:FindFirstChild("Tile12") ~= nil, "plot has 12 tiles")
check(baseplate.Material == roblox.Enum.Material.Grass and texture.Parent == nil, "baseplate turned into grass")
local shop = root.Hub:FindFirstChild("SeedShop")
check(shop and shop.Counter:FindFirstChild("ShopPrompt") ~= nil, "seed shop has a prompt")
check(shop and shop:FindFirstChild("Polly") ~= nil, "Polly the shopkeeper is there")

-- every bird and plant model must build at every stage
for _, seed in ipairs(Seeds.List) do
	for stage = 1, 4 do
		local ok, err = pcall(function()
			local PlantBuilder = Mock.Require(shared.PlantBuilder, "server")
			local model = PlantBuilder.Build(seed, stage)
			assert(model.PrimaryPart and model.PrimaryPart:FindFirstChild("Perch"), "missing perch")
			assert(model:GetAttribute("TopY") > 0, "bad TopY")
		end)
		if not ok then
			check(false, seed.Id .. " stage " .. stage .. " builds: " .. tostring(err))
		end
	end
end
check(true, "all plants build at all stages")
for _, bird in ipairs(Birds.List) do
	local ok, err = pcall(function()
		local BirdBuilder = Mock.Require(shared.BirdBuilder, "server")
		local model = BirdBuilder.Build(bird, { Shiny = true })
		assert(model.PrimaryPart and model.PrimaryPart.Anchored, "body must be anchored")
		assert(model:GetAttribute("StandHeight") > 0, "bad StandHeight")
	end)
	if not ok then
		check(false, bird.Id .. " builds: " .. tostring(err))
	end
end
check(true, "all birds build")
for _, seed in ipairs(Seeds.List) do
	for _, entry in ipairs(seed.Birds) do
		check(Birds.Get(entry.Id) ~= nil, seed.Id .. " attracts known bird " .. entry.Id)
	end
end

------------------------------------------------------------------------------
section("A player joins")

local alice = Mock.AddPlayer("Alice", 101, true)
Mock.SpawnCharacter(alice)
Mock.RunScript(client.Main, "client")
Mock.Advance(2)

local data = DataService.Get(alice)
check(data ~= nil, "Alice's data loaded")
check(data.Coins == Config.StartingCoins, "starting coins")
check(data.Seeds.Sunflower == 3, "starting seeds")
check(alice:GetAttribute("PlotId") == 1, "Alice got plot 1")
check(plot1.GateSign.Sign.Label.Text == "Alice's Garden", "gate sign shows owner")
local leaderstats = alice:FindFirstChild("leaderstats")
check(leaderstats and leaderstats.Coins.Value == Config.StartingCoins, "leaderstats coins")
local character = alice.Character
local spawnDistance = (character.PrimaryPart.CFrame.Position - plot1.Ground.CFrame.Position).Magnitude
check(spawnDistance < 30, "character teleported to their garden")

local gui = alice.PlayerGui:FindFirstChild("BirdGardenUI")
check(gui ~= nil, "UI created")
local ClientStore = Mock.Require(client.Store, "client")
check(ClientStore.Data and ClientStore.Data.Coins == Config.StartingCoins, "client received state")
local slots = gui.SeedBag.Slots
check(slots:FindFirstChild("Sunflower") ~= nil, "seed bag shows Sunflower")

------------------------------------------------------------------------------
section("Planting and growing")

local tile1 = plot1.Tile1
local plantPrompt = tile1:FindFirstChild("PlantPrompt")
check(plantPrompt and plantPrompt.ActionText == "Plant Sunflower", "empty tile prompt says Plant Sunflower")
Mock.SignalFor(plantPrompt, "Triggered"):Fire(alice)
Mock.Advance(0.5)
check(data.Seeds.Sunflower == 2, "a seed was used")
check(data.Plants["1"] and data.Plants["1"].Seed == "Sunflower", "plant saved in data")
local plant = plot1.Plants:FindFirstChild("Plant1")
check(plant and plant:GetAttribute("Stage") == 1, "seed mound appears")
check(
	tile1:FindFirstChild("DigPrompt") ~= nil and tile1:FindFirstChild("PlantPrompt") == nil,
	"tile now has a dig prompt"
)

-- someone else can't plant in Alice's garden
local bob = Mock.AddPlayer("Bob", 202, false)
Mock.SpawnCharacter(bob)
Mock.Advance(1)
check(bob:GetAttribute("PlotId") == 2, "Bob got plot 2")
Mock.SignalFor(plot1.Tile2.PlantPrompt, "Triggered"):Fire(bob)
Mock.Advance(0.2)
check(plot1.Plants:FindFirstChild("Plant2") == nil, "Bob can't plant in Alice's garden")
check(plot1.Tile2.PlantPrompt:GetAttribute("OwnerUserId") == 101, "prompts are tagged with their owner")

Mock.Advance(10)
plant = plot1.Plants:FindFirstChild("Plant1")
check(plant and plant:GetAttribute("Stage") == 2, "sprout after 10s")
Mock.Advance(10)
plant = plot1.Plants:FindFirstChild("Plant1")
check(plant and plant:GetAttribute("Stage") == 3, "young plant after 20s")
local status = plant.Root.PlantStatus.Status.Text
check(status:find("⏳") ~= nil, "client shows a countdown (" .. status .. ")")
Mock.Advance(11)
plant = plot1.Plants:FindFirstChild("Plant1")
check(plant and plant:GetAttribute("Stage") == 4, "bloomed after 30s")

------------------------------------------------------------------------------
section("Birds visit")

local birdsFolder = root.Birds
local bird
for _ = 1, 40 do
	Mock.Advance(0.5)
	bird = birdsFolder:GetChildren()[1]
	if bird then
		break
	end
end
check(bird ~= nil, "a bird flies in after blooming")
check(plant:GetAttribute("HasBird") == true, "plant knows it has a bird")
local sunflowerBirds = {}
for _, entry in ipairs(Seeds.Get("Sunflower").Birds) do
	sunflowerBirds[entry.Id] = true
end
check(bird and sunflowerBirds[bird:GetAttribute("BirdId")], "bird is one a Sunflower attracts")

local prompt
for _ = 1, 40 do
	Mock.Advance(0.5)
	prompt = bird.Body:FindFirstChild("BefriendPrompt")
	if prompt then
		break
	end
end
check(prompt ~= nil, "bird lands and can be befriended")
local perchHeight = bird.Body.CFrame.Position.Y
check(perchHeight > plant.Root.CFrame.Position.Y + 2, "bird perches on top of the plant")

local birdDef = Birds.Get(bird:GetAttribute("BirdId"))
local birdWasShiny = bird:GetAttribute("Shiny")
local coinsBefore = data.Coins
Mock.SignalFor(prompt, "Triggered"):Fire(bob)
Mock.Advance(0.2)
check(next(data.Pets) == nil, "Bob can't befriend Alice's bird")
Mock.SignalFor(prompt, "Triggered"):Fire(alice)
Mock.Advance(0.2)
local firstPetId, firstPet = next(data.Pets)
check(firstPet and firstPet.Species == birdDef.Id, "befriended bird joins the aviary as a pet")
check(firstPet and firstPet.Shiny == (birdWasShiny == true), "pet keeps the bird's shininess")
check(firstPet and firstPet.Equipped == true, "first pets go straight out into the garden")
check(firstPet and firstPet.Stars >= 1 and firstPet.Stars <= 3, "wild birds have 1-3 stars")
check(type(firstPet and firstPet.Name) == "string", "pet gets a name (" .. tostring(firstPet and firstPet.Name) .. ")")
local discoveryBonus = math.floor(Pets.BaseValue(firstPet, 0) * Config.DiscoveryBonusMultiplier)
check(data.Coins == coinsBefore + discoveryBonus, "first of a species pays a discovery bonus")
check(data.Journal[birdDef.Id] == 1, "journal records the bird")
check(data.TotalBefriended == 1, "total befriended")
check(leaderstats.Birds.Value == 1, "leaderstats birds")
check(bird.Parent == nil, "the wild bird is replaced by the pet")
check(plant:GetAttribute("HasBird") == false, "plant is free for the next bird")
local markers = ReplicatedStorage:FindFirstChild("BirdGardenPets")
local firstMarkerName = "101_" .. tostring(firstPetId)
local firstMarker = markers and markers:FindFirstChild(firstMarkerName)
check(firstMarker ~= nil, "a roaming marker is published for the pet")
check(firstMarker and typeof(firstMarker:GetAttribute("SpawnAt")) == "Vector3", "pet starts where the bird was")

-- an ignored bird leaves on its own
local secondBird
for _ = 1, 80 do
	Mock.Advance(0.5)
	secondBird = birdsFolder:GetChildren()[1]
	if secondBird and secondBird.Body:FindFirstChild("BefriendPrompt") then
		break
	end
end
check(secondBird ~= nil, "another bird arrives later")
Mock.Advance(Config.BirdStayTime + 6)
check(secondBird.Parent == nil, "ignored bird flies away after its stay")

------------------------------------------------------------------------------
section("Pets roam and help")

local Net = Mock.Require(shared.Net, "server")

local function givePet(player, fields)
	local d = DataService.Get(player)
	local id = PetService.AddPet(d, PetService.NewPet(fields))
	PetService.Refresh(player)
	return id, d.Pets[id]
end
local function petAction(...)
	return Net.PetAction:InvokeServer(...)
end
local function notified(pattern, since)
	for i = since or 1, #Mock.RemoteLog do
		local entry = Mock.RemoteLog[i]
		if entry.Remote == "Notify" and tostring(entry.Args[1]):find(pattern) then
			return true
		end
	end
	return false
end

-- the client draws the pet hopping around the garden
Mock.SignalFor(markers, "ChildAdded"):Fire(firstMarker)
Mock.Advance(3, 1 / 30)
local petModels = workspace:FindFirstChild("BirdGardenPetModels")
local petModel = petModels and petModels:FindFirstChild(firstMarkerName)
check(petModel ~= nil, "client draws the pet bird")
local ground = plot1.Ground
local inside, moved = true, false
local lastPosition = petModel and petModel.Body.CFrame.Position
for _ = 1, 30 do
	Mock.Advance(2, 1 / 30)
	local position = petModel.Body.CFrame.Position
	local localPosition = ground.CFrame:PointToObjectSpace(position)
	if math.abs(localPosition.X) > ground.Size.X / 2 or math.abs(localPosition.Z) > ground.Size.Z / 2 then
		inside = false
	end
	if (position - lastPosition).Magnitude > 0.5 then
		moved = true
	end
	lastPosition = position
end
check(moved, "pet moves around")
check(inside, "pet stays inside its own garden")
check(
	ClientStore.Data.Perks[birdDef.Perk] and ClientStore.Data.Perks[birdDef.Perk] > 0,
	"roaming pet gives its " .. birdDef.Perk .. " perk"
)

local ok, message = petAction("Unequip", firstPetId)
check(ok and not data.Pets[firstPetId].Equipped, "put a bird away")
check(markers:FindFirstChild(firstMarkerName) == nil, "it leaves the garden")
ok = petAction("Equip", firstPetId)
check(ok and markers:FindFirstChild(firstMarkerName) ~= nil, "send it back out")

local sparrows = {}
for i = 1, 6 do
	sparrows[i] = givePet(alice, { Species = "Sparrow" })
end
for i = 1, 6 do
	ok, message = petAction("Equip", sparrows[i])
end
check(
	not ok and Pets.CountEquipped(data.Pets) == Config.MaxEquippedPets,
	"only 6 birds out at once (" .. tostring(message) .. ")"
)

local spare = sparrows[6]
petAction("Favorite", spare, true)
ok = petAction("Sell", spare)
check(not ok and data.Pets[spare] ~= nil, "favorites can't be sold")
petAction("Favorite", spare, false)
coinsBefore = data.Coins
local price = Pets.SellPrice(data.Pets[spare], Util.Now(), PetService.GetPerks(alice))
ok = petAction("Sell", spare)
check(ok and data.Pets[spare] == nil and data.Coins == coinsBefore + price, "sold a bird for " .. price .. " coins")
ok = petAction("Sell", "P9999")
check(not ok, "can't sell a bird you don't have")
ok = petAction("Sell", { "bad" })
check(not ok, "bad input is rejected")

local pigeons = {}
for i = 1, 3 do
	pigeons[i] = givePet(alice, { Species = "Pigeon" })
end
local favoritePigeon = givePet(alice, { Species = "Pigeon", Favorite = true })
local toucan = givePet(alice, { Species = "Toucan" })
ok, message = petAction("SellBulk", "Common")
check(
	ok and data.Pets[pigeons[1]] == nil and data.Pets[pigeons[3]] == nil,
	"bulk sell sells spare commons (" .. tostring(message) .. ")"
)
check(
	data.Pets[favoritePigeon] and data.Pets[toucan] and data.Pets[sparrows[1]],
	"bulk sell keeps favorites, rarer birds and birds that are out"
)

-- aviary window
for _, child in ipairs(gui.Hud.Buttons:GetChildren()) do
	if child:IsA("TextButton") and child.LayoutOrder == 4 then
		Mock.SignalFor(child, "Activated"):Fire()
	end
end
Mock.Advance(0.5)
local aviary = gui:FindFirstChild("🐦 My Birds")
check(aviary and aviary.Visible, "aviary window opens")
check(aviary and aviary.Body:FindFirstChild(toucan) ~= nil, "aviary shows a card per bird")

-- Green Thumb: plants grow faster
for i = 1, 5 do
	petAction("Unequip", sparrows[i])
end
local hummingbird = givePet(alice, { Species = "Hummingbird", Stars = 5, Shiny = true })
petAction("Equip", hummingbird)
Mock.Advance(1)
local speed = plot1.Plants.Plant1:GetAttribute("Speed")
check(speed and speed > 1.2, "Hummingbird makes plants grow faster (x" .. tostring(speed) .. ")")

-- Seed finders bring seeds
local function seedCount()
	local total = 0
	for _, count in pairs(data.Seeds) do
		total += count
	end
	return total
end
local finders = { toucan }
petAction("Equip", toucan)
for i = 1, 3 do
	finders[i + 1] = givePet(alice, { Species = "Toucan", Stars = 5, Shiny = true })
	petAction("Equip", finders[i + 1])
end
check(PetService.GetPerks(alice).SeedFinder >= 0.89, "seed finder chance is capped at 90%")
local seedsBefore = seedCount()
local logStart = #Mock.RemoteLog
Mock.Advance(Config.SeedFinderInterval * 5 + 1, 0.5)
check(seedCount() > seedsBefore, "pets found seeds (" .. seedCount() - seedsBefore .. ")")
check(notified("found a", logStart), "player is told what was found")

------------------------------------------------------------------------------
section("Seed shop")

Mock.SignalFor(shop.Counter.ShopPrompt, "Triggered"):Fire(alice)
Mock.Advance(0.5)
local shopWindow = gui:FindFirstChild("🌱 Seed Shop")
check(shopWindow and shopWindow.Visible, "shop window opens from the counter")
local sunflowerRow = shopWindow.Body:FindFirstChild("Sunflower")
check(sunflowerRow ~= nil, "shop lists Sunflower")
local buyButton
for _, child in ipairs(sunflowerRow:GetChildren()) do
	if child:IsA("TextButton") then
		buyButton = child
	end
end
local seedsBefore = data.Seeds.Sunflower or 0
coinsBefore = data.Coins
Mock.SignalFor(buyButton, "Activated"):Fire()
Mock.Advance(0.5)
check((data.Seeds.Sunflower or 0) == seedsBefore + 1, "bought a Sunflower seed")
check(data.Coins == coinsBefore - Seeds.Get("Sunflower").Price, "paid for the seed")

-- can't afford the Ember Bloom
ok, message = Net.BuySeed.OnServerInvoke(alice, "EmberBloom")
check(not ok, "can't buy what you can't afford (" .. tostring(message) .. ")")
ok = Net.BuySeed.OnServerInvoke(alice, 12345)
check(not ok, "bad input is rejected")

-- select a different seed
data.Seeds.BerryBush = 1
Net.SelectSeed:FireServer("BerryBush")
Mock.Advance(0.2)
check(plot1.Tile2.PlantPrompt.ActionText == "Plant Berry Bush", "prompt follows selected seed")
Net.SelectSeed:FireServer("Phoenix")
Mock.Advance(0.2)
check(plot1.Tile2.PlantPrompt.ActionText == "Plant Berry Bush", "can't select a seed you don't own")
Mock.SignalFor(plot1.Tile2.PlantPrompt, "Triggered"):Fire(alice)
Mock.Advance(0.2)
check(data.Plants["2"] and data.Plants["2"].Seed == "BerryBush", "planted the Berry Bush")
check(data.Seeds.BerryBush == nil, "used the last Berry Bush seed")
check(plot1.Tile3.PlantPrompt.ActionText == "Plant Sunflower", "selection falls back to Sunflower")

-- client hides other gardens' prompts and highlights the soil you're facing
local bobPrompt = plotsFolder.Plot2.Tile1.PlantPrompt
Mock.SignalFor(workspace, "DescendantAdded"):Fire(bobPrompt)
Mock.Advance(0.1)
check(bobPrompt.Enabled == false, "client hides prompts in Bob's garden")
check(plot1.Tile3.PlantPrompt.Enabled == true, "client keeps its own prompts")
Mock.SignalFor(game:GetService("ProximityPromptService"), "PromptShown"):Fire(plot1.Tile3.PlantPrompt)
Mock.Advance(0.1)
check(workspace.CurrentCamera.PlantPromptHighlight.Adornee == plot1.Tile3, "soil tile is highlighted")

-- number keys pick seeds from the bag
data.Seeds.Lavender = 2
DataService.Push(alice)
Mock.Advance(0.1)
Mock.SignalFor(game:GetService("UserInputService"), "InputBegan")
	:Fire({ KeyCode = roblox.Enum.KeyCode.Two, UserInputType = roblox.Enum.UserInputType.Keyboard }, false)
Mock.Advance(0.2)
check(DataService.GetProfile(alice).SelectedSeed == "Lavender", "pressing 2 selects the second seed")
check(plot1.Tile3.PlantPrompt.ActionText == "Plant Lavender", "prompt updates after key select")

-- the Garden button brings you home
character.PrimaryPart.CFrame = CFrame.new(500, 3, 500)
for _, child in ipairs(gui.Hud.Buttons:GetChildren()) do
	if child:IsA("TextButton") and child.LayoutOrder == 2 then
		Mock.SignalFor(child, "Activated"):Fire()
	end
end
Mock.Advance(0.2)
spawnDistance = (character.PrimaryPart.CFrame.Position - plot1.Ground.CFrame.Position).Magnitude
check(spawnDistance < 30, "Garden button teleports home")

-- journal UI
local hudButtons = gui.Hud.Buttons
for _, child in ipairs(hudButtons:GetChildren()) do
	if child:IsA("TextButton") and child.LayoutOrder == 3 then
		Mock.SignalFor(child, "Activated"):Fire()
	end
end
Mock.Advance(0.5)
local journalWindow = gui:FindFirstChild("📖 Bird Journal")
check(journalWindow and journalWindow.Visible and not shopWindow.Visible, "journal opens and shop closes")
local card = journalWindow.Body:FindFirstChild(birdDef.Id)
check(card ~= nil, "journal has a card for " .. birdDef.Id)

------------------------------------------------------------------------------
section("Breeding and families")

for _, id in ipairs(finders) do
	petAction("Unequip", id)
end
local mum = givePet(alice, { Species = "Cardinal", Stars = 2 })
local dad = givePet(alice, { Species = "Cardinal", Stars = 4, Shiny = true })
local jay = givePet(alice, { Species = "BlueJay" })
ok = petAction("Breed", mum, jay)
check(not ok, "different kinds can't breed")
ok = petAction("Breed", mum, mum)
check(not ok, "a bird can't breed with itself")
petAction("Equip", mum)
ok, message = petAction("Breed", mum, dad)
check(ok, "two Cardinals start a nest (" .. tostring(message) .. ")")
local nestEntry = data.Nests["1"]
check(nestEntry and nestEntry.Species == "Cardinal", "nest 1 has a Cardinal egg")
check(data.Pets[mum].Nest == 1 and not data.Pets[mum].Equipped, "parents sit on the nest")
check(markers:FindFirstChild("101_" .. mum):GetAttribute("Mode") == "Nest", "parents are drawn at the nest")
check(plot1.Nest1:FindFirstChild("Egg") ~= nil, "an egg appears in the nest")
check(plot1.Nest1.NestBase:GetAttribute("Species") == "Cardinal", "nest shows what's hatching")
ok = petAction("Sell", mum)
check(not ok, "nesting birds can't be sold")
ok = petAction("Equip", mum)
check(not ok, "nesting birds can't go out")

Mock.SignalFor(plot1.Nest1.NestBase.NestPrompt, "Triggered"):Fire(alice)
Mock.Advance(0.5)
local nestWindow = gui:FindFirstChild("🥚 Nests & Families")
check(nestWindow and nestWindow.Visible, "nest prompt opens the nest window")

logStart = #Mock.RemoteLog
Mock.Advance(Pets.BreedTime("Cardinal") + 1, 0.5)
local babyId, baby
for id, pet in pairs(data.Pets) do
	if pet.Generation == 1 then
		babyId, baby = id, pet
	end
end
check(baby ~= nil and baby.Species == "Cardinal", "a baby Cardinal hatched")
check(
	baby and baby.Family and data.Pets[mum].Family == baby.Family and data.Pets[dad].Family == baby.Family,
	"parents and baby share a family name (" .. tostring(baby and baby.Family) .. ")"
)
check(
	baby and (baby.Stars == 3 or baby.Stars == 4),
	"baby inherits its parents' stars (" .. tostring(baby and baby.Stars) .. ")"
)
check(baby and Pets.IsBaby(baby, Util.Now()), "it starts as a baby")
check(data.Nests["1"] == nil and plot1.Nest1:FindFirstChild("Egg") == nil, "the nest is empty again")
check(not data.Pets[mum].Nest and data.Pets[mum].Equipped, "mum goes back out after hatching")
check(data.TotalHatched == 1, "hatch counted")
check(notified("hatched", logStart), "player hears about the baby")
local babyMarker = markers:FindFirstChild("101_" .. babyId)
check(babyMarker and babyMarker:GetAttribute("Baby") == true, "baby roams the garden")
check(babyMarker and babyMarker:GetAttribute("Follow") == "101_" .. mum, "baby follows its mum")

ok = petAction("Breed", babyId, mum)
check(not ok, "babies are too young to breed")
Mock.Advance(Pets.GrowUpTime("Cardinal") + 1, 1)
check(baby.GrowsUpAt == nil, "baby grows up")
check(markers:FindFirstChild("101_" .. babyId):GetAttribute("Baby") == false, "grown-up is drawn full size")

ok = petAction("Breed", mum, dad, 2)
check(ok and data.Nests["2"] ~= nil, "can pick a nest")
ok = petAction("CancelNest", 2)
check(ok and data.Nests["2"] == nil and not data.Pets[dad].Nest, "cancelling a nest frees the parents")

------------------------------------------------------------------------------
section("Trading")

local bobData = DataService.Get(bob)
local peacock = givePet(bob, { Species = "Peacock", Stars = 3 })
bobData.Coins = 500
logStart = #Mock.RemoteLog
Net.TradeRequest:FireServer(bob.UserId)
Mock.Advance(0.2)
local requested = false
for i = logStart, #Mock.RemoteLog do
	local entry = Mock.RemoteLog[i]
	if entry.Remote == "TradeIncoming" and entry.Player == "Bob" then
		requested = true
	end
end
check(requested, "Bob gets the trade request")
Mock.SignalFor(Net.TradeRespond, "OnServerEvent"):Fire(bob, alice.UserId, true)
Mock.Advance(0.2)
check(ClientStore.Trade and ClientStore.Trade.Active, "trade starts after Bob accepts")
local tradeWindow = gui:FindFirstChild("🤝 Trade")
check(tradeWindow and tradeWindow.Visible and tradeWindow.Trade.Visible, "trade window opens")

local function bobDoes(action, value)
	Mock.SignalFor(Net.TradeUpdate, "OnServerEvent"):Fire(bob, action, value)
	Mock.Advance(0.1)
end
Net.TradeUpdate:FireServer("AddPet", jay)
bobDoes("AddPet", peacock)
bobDoes("SetCoins", 100)
check(
	ClientStore.Trade.TheirPets[1] and ClientStore.Trade.TheirPets[1].Species == "Peacock",
	"Alice sees Bob's Peacock"
)
check(ClientStore.Trade.TheirCoins == 100, "and his coins")
ok = petAction("Sell", jay)
check(not ok and data.Pets[jay], "a bird in a trade can't be sold")
Net.TradeUpdate:FireServer("AddPet", favoritePigeon)
Mock.Advance(0.1)
check(#ClientStore.Trade.MyPets == 1, "favorites can't be offered")
Net.TradeUpdate:FireServer("AddPet", mum)
Mock.Advance(0.1)

Net.TradeUpdate:FireServer("Ready")
bobDoes("Ready")
check(ClientStore.Trade.ExecuteAt ~= nil, "both ready starts the countdown")
bobDoes("SetCoins", 50)
check(not ClientStore.Trade.MyReady and ClientStore.Trade.ExecuteAt == nil, "any change un-readies both")
Net.TradeUpdate:FireServer("RemovePet", mum)
Net.TradeUpdate:FireServer("Ready")
bobDoes("Ready")
local aliceCoins, bobCoins = data.Coins, bobData.Coins
Mock.Advance(Config.TradeCountdown + 1)
local gotPeacock = false
for _, pet in pairs(data.Pets) do
	if pet.Species == "Peacock" then
		gotPeacock = not pet.Equipped
	end
end
local gotJay = false
for _, pet in pairs(bobData.Pets) do
	if pet.Species == "BlueJay" then
		gotJay = true
	end
end
check(gotPeacock and data.Pets[jay] == nil, "Alice traded her Blue Jay for the Peacock")
check(gotJay and bobData.Pets[peacock] == nil, "Bob got the Blue Jay")
check(data.Coins == aliceCoins + 50 and bobData.Coins == bobCoins - 50, "coins changed hands")
check(ClientStore.Trade and not ClientStore.Trade.Active, "trade is over")
Mock.Advance(0.5)
local savedBob = Mock.SavedData[Config.DataStoreName]["Player_202"]
local savedHasPeacock = false
for _, pet in pairs(savedBob.Pets) do
	if pet.Species == "Peacock" then
		savedHasPeacock = true
	end
end
check(not savedHasPeacock, "trade is saved straight away")

-- coins are capped, and leaving cancels the trade
Mock.Advance(Config.TradeRequestCooldown + 1)
Net.TradeRequest:FireServer(bob.UserId)
Mock.Advance(0.1)
Mock.SignalFor(Net.TradeRespond, "OnServerEvent"):Fire(bob, alice.UserId, true)
Mock.Advance(0.1)
bobDoes("SetCoins", 1e12)
check(ClientStore.Trade.TheirCoins == bobData.Coins, "can't offer more coins than you have")
bobDoes("SetCoins", 0 / 0)
check(ClientStore.Trade.TheirCoins == bobData.Coins, "nonsense coin amounts are ignored")
Mock.RemovePlayer(bob)
Mock.Advance(0.5)
check(ClientStore.Trade and not ClientStore.Trade.Active, "trade ends when the other player leaves")

------------------------------------------------------------------------------
section("Restock")

local restocked = false
for _, entry in ipairs(Mock.RemoteLog) do
	entry.Seen = true
end
Mock.Advance(Config.RestockInterval + 1, 0.5)
for _, entry in ipairs(Mock.RemoteLog) do
	if not entry.Seen and entry.Remote == "ShopUpdated" and entry.Player == "Alice" then
		restocked = true
	end
end
check(restocked, "shop restocks for everyone")

------------------------------------------------------------------------------
section("Digging up")

Mock.SignalFor(plot1.Tile2.DigPrompt, "Triggered"):Fire(alice)
Mock.Advance(0.2)
check(data.Plants["2"] == nil and plot1.Plants:FindFirstChild("Plant2") == nil, "dug up the Berry Bush")
check(plot1.Tile2:FindFirstChild("PlantPrompt") ~= nil, "tile is plantable again")

------------------------------------------------------------------------------
section("Leaving and coming back")

local coinsAtLeave = data.Coins
local petsAtLeave = Pets.CountPets(data.Pets)
Mock.RemovePlayer(alice)
Mock.Advance(1)
check(plot1.GateSign.Sign.Label.Text == "Empty Garden", "plot is freed")
check(#plot1.Plants:GetChildren() == 0, "plants are cleared from the world")

local alice2 = Mock.AddPlayer("Alice", 101, false)
Mock.SpawnCharacter(alice2)
Mock.Advance(2)
local data2 = DataService.Get(alice2)
check(data2 and data2.Coins == coinsAtLeave, "coins were saved")
check(data2 and data2.Journal[birdDef.Id] == 1, "journal was saved")
check(data2 and Pets.CountPets(data2.Pets) == petsAtLeave, "pets were saved")
check(data2 and data2.Pets[babyId] and data2.Pets[babyId].Family == baby.Family, "families were saved")
local newPlot = plotsFolder:FindFirstChild("Plot" .. alice2:GetAttribute("PlotId"))
local restored = newPlot.Plants:FindFirstChild("Plant1")
check(restored and restored:GetAttribute("Stage") == 4, "planted Sunflower is restored, still blooming")

------------------------------------------------------------------------------
section("Growth continues while offline")

Mock.RemovePlayer(alice2)
Mock.Advance(1)
local saved = Mock.SavedData[Config.DataStoreName]["Player_101"]
local nowSeconds = math.floor(Util.Now())
saved.Plants["5"] = { Seed = "MangoTree", Grown = 0, SavedAt = nowSeconds - 400 }
-- a plant saved before pets existed
saved.Plants["6"] = { Seed = "Sunflower", PlantedAt = nowSeconds - 100 }
local alice3 = Mock.AddPlayer("Alice", 101, false)
Mock.SpawnCharacter(alice3)
Mock.Advance(2)
newPlot = plotsFolder:FindFirstChild("Plot" .. alice3:GetAttribute("PlotId"))
local mango = newPlot.Plants:FindFirstChild("Plant5")
check(mango ~= nil, "Mango Tree restored")
local data3 = DataService.Get(alice3)
check(
	data3.Plants["5"].Grown >= 400,
	"Mango Tree kept growing while away (" .. math.floor(data3.Plants["5"].Grown) .. "s of growth)"
)
local oldSunflower = newPlot.Plants:FindFirstChild("Plant6")
check(oldSunflower and oldSunflower:GetAttribute("Stage") == 4, "old-style saves still load")
check(data3.Plants["6"].PlantedAt == nil and data3.Plants["6"].Grown ~= nil, "and are converted")

------------------------------------------------------------------------------
section("Never stuck without seeds")

table.clear(data3.Seeds)
data3.Coins = 0
for key in pairs(data3.Plants) do
	local tile = newPlot:FindFirstChild("Tile" .. key)
	Mock.SignalFor(tile.DigPrompt, "Triggered"):Fire(alice3)
	Mock.Advance(0.1)
end
check(next(data3.Plants) == nil, "all plants dug up")
check(data3.Seeds.Sunflower == 1, "got a free Sunflower seed")

------------------------------------------------------------------------------
section("A long session")

Mock.SignalFor(newPlot.Tile1.PlantPrompt, "Triggered"):Fire(alice3)
for _ = 1, 30 do
	Mock.Advance(60, 0.5)
	for _, b in ipairs(birdsFolder:GetChildren()) do
		local p = b.Body:FindFirstChild("BefriendPrompt")
		if p and p:GetAttribute("OwnerUserId") == 101 then
			Mock.SignalFor(p, "Triggered"):Fire(alice3)
		end
	end
end
check(data3.TotalBefriended > 10, "befriended lots of birds over 30 minutes (" .. data3.TotalBefriended .. ")")

Mock.RemovePlayer(alice3)
Mock.Advance(15)
check(#birdsFolder:GetChildren() == 0, "no birds left once everyone leaves")
check(Mock.ActiveTweens == 0, "no tweens left running")

------------------------------------------------------------------------------
print()
print(#Mock.Errors .. " script errors, " .. #Mock.Warnings .. " warnings, " .. failures .. " failed checks")
if #Mock.Errors > 0 or failures > 0 then
	process.exit(1)
end
