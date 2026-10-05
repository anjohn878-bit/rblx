-- Build a Dress Store - server
-- Gives every player their own dress store plot, loads their progress,
-- and handles rebirths and teleporting home.

local Players = game:GetService("Players")
local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local shared = ReplicatedStorage:WaitForChild("DressStore")
local Config = require(shared:WaitForChild("Config"))

local Data = require(script.DataManager)
local Npc = require(script.Npc)
local Remotes = require(script.Remotes)
local Store = require(script.Store)
local WorldBuilder = require(script.WorldBuilder)

local PLAYER_GROUP = "DressStorePlayers"

-- Shoppers walk through each other and through players so nobody gets stuck
pcall(function()
	PhysicsService:RegisterCollisionGroup(Npc.COLLISION_GROUP)
	PhysicsService:RegisterCollisionGroup(PLAYER_GROUP)
	PhysicsService:CollisionGroupSetCollidable(Npc.COLLISION_GROUP, Npc.COLLISION_GROUP, false)
	PhysicsService:CollisionGroupSetCollidable(Npc.COLLISION_GROUP, PLAYER_GROUP, false)
end)

-- Load the shopper avatar now so the first shoppers don't have to wait
task.spawn(Npc.preload)

local stores = {}
for _, plot in WorldBuilder.build() do
	table.insert(stores, Store.new(plot))
end

local storeOf: { [Player]: any } = {}

local function findFreeStore()
	for _, store in stores do
		if not store.owner then
			return store
		end
	end
	return nil
end

local function sendHome(player: Player)
	local store = storeOf[player]
	local character = player.Character
	if store and character and character.Parent then
		character:PivotTo(store:spawnCFrame())
	end
end

local function giveStore(player: Player, store)
	storeOf[player] = store
	player:SetAttribute("NoStore", nil)
	store:assign(player)
end

local function onCharacterAdded(player: Player, character: Model)
	local function setGroup(part: Instance)
		if part:IsA("BasePart") then
			part.CollisionGroup = PLAYER_GROUP
		end
	end
	for _, part in character:GetDescendants() do
		setGroup(part)
	end
	character.DescendantAdded:Connect(setGroup)

	character:WaitForChild("HumanoidRootPart", 10)
	-- wait a moment so the default spawn doesn't move us back
	task.wait(0.15)
	if character.Parent and storeOf[player] then
		sendHome(player)
	end
end

local function onPlayerAdded(player: Player)
	Data.load(player)
	if not player.Parent then
		Data.release(player)
		return
	end

	local store = findFreeStore()
	if store then
		giveStore(player, store)
		Remotes.notify(player, "Welcome to " .. Config.GAME_NAME .. "! Your store is the one with your name on the gate. 👗", "success")
	else
		player:SetAttribute("NoStore", true)
		Remotes.notify(player, "All stores are taken - you'll get one as soon as someone leaves!", "error")
	end

	player.CharacterAdded:Connect(function(character)
		onCharacterAdded(player, character)
	end)
	if player.Character then
		task.spawn(onCharacterAdded, player, player.Character)
	end
end

local function onPlayerRemoving(player: Player)
	local store = storeOf[player]
	storeOf[player] = nil
	if store then
		store:release()
		-- someone who joined a full server gets the empty store
		for _, waiting in Players:GetPlayers() do
			if waiting ~= player and waiting:GetAttribute("NoStore") and Data.get(waiting) then
				giveStore(waiting, store)
				sendHome(waiting)
				Remotes.notify(waiting, "A store opened up - it's yours now! 👗", "success")
				break
			end
		end
	end
	Data.release(player)
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)
for _, player in Players:GetPlayers() do
	task.spawn(onPlayerAdded, player)
end

Remotes.GoHome.OnServerEvent:Connect(function(player)
	sendHome(player)
end)

Remotes.Rebirth.OnServerEvent:Connect(function(player)
	local store = storeOf[player]
	if not store or not store:isOwnedBy(player) then
		return
	end
	if not store:allBuilt() then
		Remotes.notify(player, "Build everything in your store first, then you can rebirth!", "error")
		return
	end
	store:release()
	Data.rebirth(player)
	storeOf[player] = store
	store:assign(player)
	sendHome(player)
	Data.save(player)
	local bonus = Data.multiplier(player)
	Remotes.notify(player, string.format("✨ Rebirth complete! You now earn x%.1f money forever!", bonus), "success")
end)
