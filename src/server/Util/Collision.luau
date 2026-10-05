--[[
	Collision
	Collision groups so NPCs never get blocked by players, furniture or each
	other (a stuck NPC would stall the whole hospital loop).
]]

local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")

local Collision = {
	NPC = "NPC",
	Players = "Players",
	Furniture = "Furniture",
}

local function register(name: string)
	if not PhysicsService:IsCollisionGroupRegistered(name) then
		PhysicsService:RegisterCollisionGroup(name)
	end
end

local function setCharacterGroup(character: Model)
	for _, descendant in character:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.CollisionGroup = Collision.Players
		end
	end
	character.DescendantAdded:Connect(function(descendant)
		if descendant:IsA("BasePart") then
			descendant.CollisionGroup = Collision.Players
		end
	end)
end

function Collision.Init()
	register(Collision.NPC)
	register(Collision.Players)
	register(Collision.Furniture)

	PhysicsService:CollisionGroupSetCollidable(Collision.NPC, Collision.NPC, false)
	PhysicsService:CollisionGroupSetCollidable(Collision.NPC, Collision.Players, false)
	PhysicsService:CollisionGroupSetCollidable(Collision.NPC, Collision.Furniture, false)

	local function onPlayer(player: Player)
		player.CharacterAdded:Connect(setCharacterGroup)
		if player.Character then
			setCharacterGroup(player.Character)
		end
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, player in Players:GetPlayers() do
		onPlayer(player)
	end
end

function Collision.SetModelGroup(model: Instance, group: string)
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.CollisionGroup = group
		end
	end
end

return Collision
