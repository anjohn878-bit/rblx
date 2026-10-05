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
local DataService = Mock.Require(server.DataService, "server")

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
local coinsBefore = data.Coins
local multiplier = Config.DiscoveryBonusMultiplier * (bird:GetAttribute("Shiny") and Config.ShinyMultiplier or 1)
Mock.SignalFor(prompt, "Triggered"):Fire(bob)
Mock.Advance(0.2)
check(data.Coins == coinsBefore, "Bob can't befriend Alice's bird")
Mock.SignalFor(prompt, "Triggered"):Fire(alice)
Mock.Advance(0.2)
check(data.Coins == coinsBefore + birdDef.Reward * multiplier, "befriending pays coins with discovery bonus")
check(data.Journal[birdDef.Id] == 1, "journal records the bird")
check(data.TotalBefriended == 1, "total befriended")
check(leaderstats.Birds.Value == 1, "leaderstats birds")
Mock.Advance(5)
check(bird.Parent == nil, "bird flies away after being befriended")
check(plant:GetAttribute("HasBird") == false, "plant is free for the next bird")

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
section("Seed shop")

local Net = Mock.Require(shared.Net, "server")
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
local ok, message = Net.BuySeed.OnServerInvoke(alice, "EmberBloom")
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
local newPlot = plotsFolder:FindFirstChild("Plot" .. alice2:GetAttribute("PlotId"))
local restored = newPlot.Plants:FindFirstChild("Plant1")
check(restored and restored:GetAttribute("Stage") == 4, "planted Sunflower is restored, still blooming")

------------------------------------------------------------------------------
section("Growth continues while offline")

Mock.RemovePlayer(alice2)
Mock.Advance(1)
local saved = Mock.SavedData[Config.DataStoreName]["Player_101"]
saved.Plants["5"] = { Seed = "MangoTree", PlantedAt = saved.Plants["1"].PlantedAt }
local alice3 = Mock.AddPlayer("Alice", 101, false)
Mock.SpawnCharacter(alice3)
Mock.Advance(2)
newPlot = plotsFolder:FindFirstChild("Plot" .. alice3:GetAttribute("PlotId"))
local mango = newPlot.Plants:FindFirstChild("Plant5")
check(mango ~= nil, "Mango Tree restored")
check(
	mango and mango:GetAttribute("Stage") == 3,
	"Mango Tree kept growing while away (stage " .. tostring(mango and mango:GetAttribute("Stage")) .. ")"
)

------------------------------------------------------------------------------
section("Never stuck without seeds")

local data3 = DataService.Get(alice3)
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

Mock.RemovePlayer(bob)
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
