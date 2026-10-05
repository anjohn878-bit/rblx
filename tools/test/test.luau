--[[
	Plays through Build a Dress Store with a fake engine and checks that things work.

	Run from the repository root with Lune (https://lune-org.github.io/docs):
		lune run tools/test/test.luau          -- blocky R6 shoppers (avatar loading off)
		lune run tools/test/test.luau r15      -- R15 shoppers

	Game time is simulated, so ~25 minutes of play takes a few seconds.
]]
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local Engine = require("./engine")

local ROOT = "."
Engine.R15 = process.args[1] == "r15"

local game = Engine.game
local Vector3 = roblox.Vector3
local failures = 0
local function check(condition, message)
	if condition then
		print("[ok]   " .. message)
	else
		failures += 1
		print("[FAIL] " .. message)
	end
end

local server, client = Engine.mount(ROOT)
Engine.runScript(server)
Engine.run(1)
check(#Engine.errors == 0, "server script starts without errors")

local Config = Engine.require(game.ReplicatedStorage.DressStore.Config)
local Data = Engine.require(server.DataManager)
local Layout = Engine.require(server.Layout)

local town = game.Workspace:FindFirstChild("DressStoreTown")
local storesFolder = town and town:FindFirstChild("Stores")
check(storesFolder and #storesFolder:GetChildren() == Config.PLOT_COUNT, "all store plots are built")

local function plotCf(plot)
	for _, child in plot:GetChildren() do
		if child:IsA("BasePart") and child.Size.X > 80 then
			return child.CFrame
		end
	end
	error("no lawn")
end

local function rebuildObstacles()
	table.clear(Engine.obstacles)
	for _, plot in storesFolder:GetChildren() do
		local cf = plotCf(plot)
		for _, part in plot:GetDescendants() do
			if part:IsA("BasePart") and part.CanCollide and part.Parent ~= plot.Buttons and not part:IsDescendantOf(plot.Shoppers) then
				local top = cf:PointToObjectSpace(part.CFrame.Position).Y + part.Size.Y / 2
				local isFloorLike = part.Size.Y < 1.2 and top < 1.5
				if not isFloorLike and part.Size.X < 80 then
					table.insert(Engine.obstacles, { part = part, name = part:GetFullName(), plotCf = cf })
				end
			end
		end
	end
end

local function storeOf(player)
	local index = player:GetAttribute("PlotIndex")
	return storesFolder:FindFirstChild("Store" .. tostring(index))
end

local function trigger(prompt, player)
	assert(prompt and prompt:IsA("ProximityPrompt"), "not a prompt")
	if not prompt.Enabled then
		return false
	end
	Engine.signalFor(prompt, "Triggered"):Fire(player)
	Engine.run(0.05)
	return true
end

local function buy(player, itemId)
	local plot = storeOf(player)
	local pad = plot.Buttons:FindFirstChild("Buy_" .. itemId)
	if not pad then
		return false
	end
	return trigger(pad.Button.BuyPrompt, player)
end

local function owns(player, itemId)
	return Data.isOwned(player, itemId)
end

-- Finds a prompt by name inside the player's store items
local function findPrompt(player, name)
	local plot = storeOf(player)
	for _, d in plot.Items:GetDescendants() do
		if d:IsA("ProximityPrompt") and d.Name == name then
			return d
		end
	end
	return nil
end

----------------------------------------------------------------------------
print("\n== Joining ==")
local alice = Engine.addPlayer(101, "Alice")
Engine.run(1)
Engine.spawnCharacter(alice)
Engine.run(1)
check(alice:GetAttribute("PlotIndex") == 1, "Alice gets store 1")
check(alice.leaderstats.Cash.Value == Config.STARTING_CASH, "Alice starts with $" .. Config.STARTING_CASH)
local aliceStore = storeOf(alice)
check(aliceStore.Buttons:FindFirstChild("Buy_starter") ~= nil, "the free 'Open Your Store' button is there")
check(#aliceStore.Buttons:GetChildren() == 1, "only one button at the start")
local spawnCf = plotCf(aliceStore) * roblox.CFrame.new(Layout.PLAYER_SPAWN.X, Layout.PLAYER_SPAWN.Y, Layout.PLAYER_SPAWN.Z)
check((alice.Character.HumanoidRootPart.CFrame.Position - spawnCf.Position).Magnitude < 0.5, "Alice is teleported to her store")
local gateLabel = nil
for _, d in aliceStore:GetDescendants() do
	if d:IsA("TextLabel") and string.find(d.Text, "Alice") then
		gateLabel = d
	end
end
check(gateLabel ~= nil, "Alice's name is on her store")

print("\n== Client UI ==")
game.Players.LocalPlayer = alice
Engine.localPlayer = alice
Engine.runScript(client)
Engine.onStep(function(dt)
	Engine.signalFor(game:GetService("RunService"), "RenderStepped"):Fire(dt)
end)
Engine.run(1)
check(#Engine.errors == 0, "client UI starts without errors")
local hud = alice.PlayerGui:FindFirstChild("DressStoreHUD")
check(hud ~= nil, "HUD is created")

print("\n== Early game ==")
check(buy(alice, "starter"), "press the starter button")
check(owns(alice, "starter"), "store opened")
check(findPrompt(alice, "SewPrompt") ~= nil, "sewing table has a prompt")
check(aliceStore.Buttons:FindFirstChild("Buy_register") and aliceStore.Buttons:FindFirstChild("Buy_rack1"), "register and rack buttons appear")
check(buy(alice, "register") and buy(alice, "rack1"), "buy register and first rack")
check(alice.leaderstats.Cash.Value == Config.STARTING_CASH - 25 - 40, "money was spent")
Engine.run(1)
check(alice:GetAttribute("Stock") == Config.Sewing.NEW_RACK_STOCK, "new rack comes with dresses")

-- try to buy something too expensive
Engine.firedClient = {}
buy(alice, "walls")
check(not owns(alice, "walls"), "can't buy walls without enough money")
local gotError = false
for _, f in Engine.firedClient do
	if f[1] == "Notify" and f[4] == "error" then
		gotError = true
	end
end
check(gotError, "player is told they need more money")

rebuildObstacles()
local sewPrompt = findPrompt(alice, "SewPrompt")
local registerPrompt = findPrompt(alice, "CheckoutPrompt")
local startCash = alice.leaderstats.Cash.Value
local rang = 0
for _ = 1, 240 do
	Engine.run(0.5)
	if registerPrompt.Enabled then
		trigger(registerPrompt, alice)
		rang += 1
	end
	if (alice:GetAttribute("Stock") or 0) < (alice:GetAttribute("StockMax") or 0) then
		trigger(sewPrompt, alice)
	end
	-- buy things as soon as we can afford them, like a real player
	for _, item in Config.Items do
		if not owns(alice, item.id) and item.price <= alice.leaderstats.Cash.Value then
			buy(alice, item.id)
		end
	end
end
print(string.format("   after 2 minutes: cash $%d, sold %d, rang up %d, owns %d items", alice.leaderstats.Cash.Value, alice:GetAttribute("Sold"), rang, alice:GetAttribute("ItemsOwned")))
check(alice:GetAttribute("Sold") > 5, "shoppers bought dresses")
check(rang > 5, "ringing up shoppers at the register works")
check(alice:GetAttribute("ItemsOwned") >= 5, "early upgrades are affordable within 2 minutes")
check(#Engine.errors == 0, "no script errors during early game")

print("\n== Impatient shoppers ==")
-- stop ringing people up: shoppers should give up and their dress goes back on the rack
Engine.hops = {}
local soldBeforeWait = alice:GetAttribute("Sold")
local gaveUp = 0
local stockBefore = alice:GetAttribute("Stock")
for _ = 1, Config.Customer.PATIENCE + 30 do
	Engine.run(1)
	for _, d in aliceStore.Shoppers:GetDescendants() do
		if d:IsA("TextLabel") and d.Text == "😠 Too slow!" and not d:GetAttribute("Counted") then
			d:SetAttribute("Counted", true)
			gaveUp += 1
		end
	end
end
print("   shoppers who gave up:", gaveUp, "stock before/after:", stockBefore, alice:GetAttribute("Stock"))
check(gaveUp > 0, "shoppers give up after waiting too long")
for _, f in Engine.firedAll do
	-- nothing to count here, popups only
end
check(alice:GetAttribute("Sold") == soldBeforeWait, "nobody pays when nobody is at the register")
check((alice:GetAttribute("Waiting") or 0) <= alice:GetAttribute("StockMax"), "the line stays a sensible length")
local bubbleTexts = {}
for _, d in aliceStore.Shoppers:GetDescendants() do
	if d:IsA("TextLabel") then
		bubbleTexts[d.Text] = true
	end
end
print("   shopper bubbles seen:", table.concat((function() local t = {} for k in bubbleTexts do table.insert(t, k) end return t end)(), " | "))
check(#Engine.errors == 0, "no errors while shoppers wait")
check(#Engine.hops == 0, "no shopper got stuck (" .. #Engine.hops .. " hops)")

print("\n== Building everything ==")
Data.addCash(alice, 10_000_000)
for _, item in Config.Items do
	if not owns(alice, item.id) then
		buy(alice, item.id)
		Engine.run(1)
	end
end
local allOwned = true
for _, item in Config.Items do
	if not owns(alice, item.id) then
		allOwned = false
		print("   missing: " .. item.id)
	end
end
check(allOwned, "every item can be bought")
check(alice:GetAttribute("CanRebirth") == true, "rebirth unlocks when everything is built")
check(#aliceStore.Buttons:GetChildren() == 0, "no buttons left")
check(alice:GetAttribute("HasCashier") == true, "cashier is hired")
check(aliceStore.Items.cashier:FindFirstChild("Cashier") ~= nil, "cashier character stands behind the counter")
check(#Engine.warnings <= 1, "no warnings while building (" .. #Engine.warnings .. ")")
for _, w in Engine.warnings do
	print("   warning: " .. w)
end

print("\n== Busy store with a cashier ==")
rebuildObstacles()
Engine.hops = {}
Engine.collisions = {}
local soldBefore = alice:GetAttribute("Sold")
local cashBefore = alice.leaderstats.Cash.Value
local maxShoppers = 0
for _ = 1, 600 do
	Engine.run(0.5)
	maxShoppers = math.max(maxShoppers, alice:GetAttribute("Shoppers") or 0)
end
local sold = alice:GetAttribute("Sold") - soldBefore
local earned = alice.leaderstats.Cash.Value - cashBefore
print(string.format("   5 minutes: sold %d dresses, earned $%d, max shoppers %d", sold, earned, maxShoppers))
check(sold > 40, "the cashier and sewing machines keep the store selling")
check(maxShoppers >= 5, "upgrades allow more shoppers")
check(#Engine.collisions == 0, "shoppers never walk into furniture (" .. #Engine.collisions .. ")")
check(#Engine.hops == 0, "no shopper got stuck in the busy store (" .. #Engine.hops .. " hops)")
for i, c in Engine.collisions do
	if i <= 15 then
		print("   " .. c)
	end
end
check(#Engine.errors == 0, "no script errors in the busy store")

print("\n== Rebirth ==")
local rebirthEvent = game.ReplicatedStorage.DressStore.Remotes.Rebirth
Engine.signalFor(rebirthEvent, "OnServerEvent"):Fire(alice)
Engine.run(2)
check(alice.leaderstats.Rebirths.Value == 1, "rebirth counted")
check(alice:GetAttribute("Multiplier") == 1 + Config.REBIRTH_BONUS, "money multiplier goes up")
check(alice.leaderstats.Cash.Value == Config.STARTING_CASH, "cash resets")
check(alice:GetAttribute("ItemsOwned") == 0 and #aliceStore.Items:GetChildren() == 0, "store is empty again")
check(#aliceStore.Shoppers:GetChildren() == 0, "shoppers are cleared")
check(aliceStore.Buttons:FindFirstChild("Buy_starter") ~= nil, "starter button is back")
Engine.signalFor(rebirthEvent, "OnServerEvent"):Fire(alice)
Engine.run(1)
check(alice.leaderstats.Rebirths.Value == 1, "can't rebirth again with an empty store")

buy(alice, "starter")
buy(alice, "register")
buy(alice, "rack1")
Engine.run(20)

print("\n== Second player ==")
local bob = Engine.addPlayer(202, "Bob")
Engine.run(1)
Engine.spawnCharacter(bob)
Engine.run(1)
check(bob:GetAttribute("PlotIndex") == 2, "Bob gets store 2")
Engine.firedClient = {}
local alicePad = aliceStore.Buttons:FindFirstChild("Buy_machine1") or aliceStore.Buttons:GetChildren()[1]
trigger(alicePad.Button.BuyPrompt, bob)
check(alice:GetAttribute("ItemsOwned") == 3, "Bob can't buy things in Alice's store")
check(#Engine.firedClient > 0 and Engine.firedClient[1][2] == "Bob", "Bob is told it's not his store")

print("\n== Saving ==")
local aliceCash = alice.leaderstats.Cash.Value
Engine.removePlayer(alice)
Engine.run(2)
local saved = Engine.saved["player_101"]
check(saved ~= nil, "Alice's progress is saved when she leaves")
check(saved and saved.rebirths == 1 and #saved.owned == 3, "saved data has rebirths and items")
check(#storeOf(bob).Parent:FindFirstChild("Store1").Items:GetChildren() == 0, "Alice's store is cleared when she leaves")

local alice2 = Engine.addPlayer(101, "Alice")
Engine.run(1)
Engine.spawnCharacter(alice2)
Engine.run(1)
check(alice2:GetAttribute("PlotIndex") == 1, "Alice gets a store again")
check(alice2.leaderstats.Rebirths.Value == 1 and alice2:GetAttribute("ItemsOwned") == 3, "Alice's store is rebuilt from her save")
check(alice2.leaderstats.Cash.Value == aliceCash, "Alice's cash is restored")

print("\n== Studio without API access ==")
Engine.dataStoreMode = "studio"
local carol = Engine.addPlayer(303, "Carol")
Engine.run(2)
check(carol:GetAttribute("PlotIndex") == 3, "Carol can still play without DataStores")
Engine.removePlayer(carol)
Engine.run(1)
check(Engine.saved["player_303"] == nil, "nothing saved without API access")

print("\n== Full server ==")
local extras = {}
for i = 1, Config.PLOT_COUNT do
	table.insert(extras, Engine.addPlayer(1000 + i, "Guest" .. i))
end
Engine.run(2)
local waitingGuests = {}
local leaver = nil
for _, guest in extras do
	if guest:GetAttribute("NoStore") then
		table.insert(waitingGuests, guest)
	elseif guest:GetAttribute("PlotIndex") then
		leaver = guest
	end
end
check(#waitingGuests > 0, "a player who joins a full server has to wait for a store")
local freedIndex = leaver:GetAttribute("PlotIndex")
Engine.removePlayer(leaver)
Engine.run(2)
local newOwner = nil
for _, guest in waitingGuests do
	if guest:GetAttribute("PlotIndex") == freedIndex and not guest:GetAttribute("NoStore") then
		newOwner = guest
	end
end
check(newOwner ~= nil, "a waiting player gets the store as soon as someone leaves")

print("\n== Shutdown ==")
for _, fn in Engine.closeHandlers do
	Engine.task.spawn(fn)
end
Engine.run(5)

check(#Engine.errors == 0, "no script errors at all")
print(string.format("\n%d failure(s), %d warning(s), %d error(s)", failures, #Engine.warnings, #Engine.errors))
for _, w in Engine.warnings do
	print("   warning: " .. string.sub(w, 1, 160))
end
process.exit(if failures == 0 then 0 else 1)
