-- Become a Delivery Driver: main server logic
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")
local ServerScriptService = game:GetService("ServerScriptService")

local Server = ServerScriptService:WaitForChild("Server")
local WorldBuilder = require(Server:WaitForChild("WorldBuilder"))
local CarSpawner = require(Server:WaitForChild("CarSpawner"))
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

-- Remotes
local remotes = Instance.new("Folder")
remotes.Name = "Remotes"
remotes.Parent = ReplicatedStorage
local function remote(name: string)
	local r = Instance.new("RemoteEvent")
	r.Name = name
	r.Parent = remotes
	return r
end
local OrderUpdate = remote("OrderUpdate") -- server -> client: {active, house, timeLeft, text}
local Notify = remote("Notify") -- server -> client: message, color
local ShopAction = remote("ShopAction") -- client -> server: "buy"/"equip", carId
local ShopData = remote("ShopData") -- server -> client: owned, equipped
local SpawnCar = remote("SpawnCar") -- client -> server

local world = WorldBuilder.build()

-- Persistence
local store
pcall(function()
	store = DataStoreService:GetDataStore("DeliveryDriverV1")
end)
local profiles: { [Player]: any } = {}
local orders: { [Player]: any } = {}
local cars: { [Player]: Model } = {}

local function defaultProfile()
	return { cash = Config.StartCash, deliveries = 0, earned = 0, owned = { Scooter = true }, equipped = "Scooter" }
end

local function load(player: Player)
	local data
	if store then
		pcall(function()
			data = store:GetAsync("p_" .. player.UserId)
		end)
	end
	local p = defaultProfile()
	if typeof(data) == "table" then
		for k, v in data do
			p[k] = v
		end
	end
	profiles[player] = p
	return p
end

local function save(player: Player)
	local p = profiles[player]
	if store and p then
		pcall(function()
			store:SetAsync("p_" .. player.UserId, p)
		end)
	end
end

local function syncStats(player: Player)
	local p = profiles[player]
	local ls = player:FindFirstChild("leaderstats")
	if not p or not ls then
		return
	end
	ls.Cash.Value = p.cash
	ls.Deliveries.Value = p.deliveries
	ls.Rank.Value = Config.getRank(p.deliveries)
	ShopData:FireClient(player, p.owned, p.equipped)
end

local function setupPlayer(player: Player)
	local ls = Instance.new("Folder")
	ls.Name = "leaderstats"
	ls.Parent = player
	local cash = Instance.new("IntValue")
	cash.Name = "Cash"
	cash.Parent = ls
	local del = Instance.new("IntValue")
	del.Name = "Deliveries"
	del.Parent = ls
	local rank = Instance.new("StringValue")
	rank.Name = "Rank"
	rank.Parent = ls
	load(player)
	syncStats(player)
end

-- Highlight beacon on destination
local function makeBeacon(door: BasePart, player: Player)
	local hl = Instance.new("Highlight")
	hl.FillColor = Color3.fromRGB(80, 255, 120)
	hl.OutlineColor = Color3.new(1, 1, 1)
	hl.Parent = door.Parent
	local beam = Instance.new("Part")
	beam.Name = "Beacon_" .. player.Name
	beam.Anchored, beam.CanCollide, beam.CanQuery = true, false, false
	beam.Material = Enum.Material.Neon
	beam.Color = Color3.fromRGB(80, 255, 120)
	beam.Transparency = 0.5
	beam.Size = Vector3.new(3, 200, 3)
	beam.Position = door.Position + Vector3.new(0, 100, 0)
	beam.Parent = workspace
	return function()
		hl:Destroy()
		beam:Destroy()
	end
end

local function clearOrder(player: Player)
	local o = orders[player]
	if o then
		o.cleanup()
		o.door:FindFirstChildOfClass("ProximityPrompt").Enabled = false
		orders[player] = nil
	end
	OrderUpdate:FireClient(player, { active = false })
end

local rng = Random.new()
local houseDoors = {}
for _, h in world.Houses:GetChildren() do
	table.insert(houseDoors, h:FindFirstChild("Door"))
end

local function startOrder(player: Player)
	if orders[player] then
		Notify:FireClient(player, "Finish your current delivery first!", Color3.fromRGB(255, 120, 120))
		return
	end
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end
	local door = houseDoors[rng:NextInteger(1, #houseDoors)]
	local dist = (door.Position - world.PickupPrompt.Parent.Position).Magnitude
	local limit = Config.TimeLimitBase + dist * Config.TimePerStud
	local prompt = door:FindFirstChildOfClass("ProximityPrompt")
	prompt.Enabled = true
	orders[player] = {
		door = door,
		dist = dist,
		limit = limit,
		started = os.clock(),
		cleanup = makeBeacon(door, player),
	}
	-- delivered by anyone triggering; only valid for order owner
	Notify:FireClient(player, "Order picked up! Deliver it to the green house.", Color3.fromRGB(120, 255, 160))

	task.spawn(function()
		local o = orders[player]
		while orders[player] == o and player.Parent do
			local left = o.limit - (os.clock() - o.started)
			OrderUpdate:FireClient(player, { active = true, timeLeft = math.max(left, 0), target = door.Position })
			if left <= -10 then
				-- hard fail: tips gone, order expires
				clearOrder(player)
				Notify:FireClient(player, "Order expired! No pay.", Color3.fromRGB(255, 90, 90))
				return
			end
			task.wait(0.25)
		end
	end)
end

local function completeOrder(player: Player, door: BasePart)
	local o = orders[player]
	if not o or o.door ~= door then
		return
	end
	local p = profiles[player]
	local elapsed = os.clock() - o.started
	local pay = Config.BasePay + o.dist * Config.PayPerStud
	local bonus = 0
	if elapsed < o.limit then
		bonus = math.floor(Config.SpeedBonusMax * (1 - elapsed / o.limit))
	else
		pay *= 0.5 -- late
	end
	local total = math.floor(pay + bonus)
	p.cash += total
	p.earned += total
	p.deliveries += 1
	clearOrder(player)
	syncStats(player)
	Notify:FireClient(
		player,
		("Delivered! +$%d%s"):format(total, bonus > 0 and (" (speed bonus $%d)"):format(bonus) or " (late)"),
		Color3.fromRGB(255, 230, 90)
	)
end

for _, door in houseDoors do
	local prompt = door:FindFirstChildOfClass("ProximityPrompt")
	prompt.Triggered:Connect(function(player)
		completeOrder(player, door)
	end)
end

world.PickupPrompt.Triggered:Connect(startOrder)

-- Shop / cars
local function findCar(id: string)
	for _, c in Config.Cars do
		if c.id == id then
			return c
		end
	end
end

ShopAction.OnServerEvent:Connect(function(player, action, carId)
	local p = profiles[player]
	local def = typeof(carId) == "string" and findCar(carId)
	if not p or not def then
		return
	end
	if action == "buy" then
		if p.owned[carId] then
			return
		end
		if p.cash < def.price then
			Notify:FireClient(player, "Not enough cash!", Color3.fromRGB(255, 90, 90))
			return
		end
		p.cash -= def.price
		p.owned[carId] = true
		p.equipped = carId
		Notify:FireClient(player, "Bought " .. def.name .. "!", Color3.fromRGB(120, 255, 160))
	elseif action == "equip" and p.owned[carId] then
		p.equipped = carId
	end
	syncStats(player)
end)

SpawnCar.OnServerEvent:Connect(function(player)
	local p = profiles[player]
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not p or not root then
		return
	end
	if cars[player] then
		cars[player]:Destroy()
	end
	local cf = CFrame.new(root.Position + root.CFrame.LookVector * 12 + Vector3.new(0, 3, 0)) * CFrame.Angles(0, math.atan2(-root.CFrame.LookVector.X, -root.CFrame.LookVector.Z), 0)
	local model, seat = CarSpawner.spawn(p.equipped, cf, player)
	cars[player] = model
end)

world.ShopPrompt.Triggered:Connect(function(player)
	ShopData:FireClient(player, profiles[player].owned, profiles[player].equipped, true)
end)

Players.PlayerAdded:Connect(setupPlayer)
for _, pl in Players:GetPlayers() do
	task.spawn(setupPlayer, pl)
end

Players.PlayerRemoving:Connect(function(player)
	clearOrder(player)
	if cars[player] then
		cars[player]:Destroy()
		cars[player] = nil
	end
	save(player)
	profiles[player] = nil
end)

game:BindToClose(function()
	for _, pl in Players:GetPlayers() do
		save(pl)
	end
end)

-- autosave
task.spawn(function()
	while true do
		task.wait(120)
		for _, pl in Players:GetPlayers() do
			save(pl)
		end
	end
end)
