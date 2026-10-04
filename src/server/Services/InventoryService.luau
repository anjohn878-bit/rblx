--[[
	InventoryService (also handles customization)
	Server-validated purchases and equips, and applies the equipped kit to the
	character every time it spawns. During matches a team colour replaces the shirt.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Catalog = require(Shared.Catalog)
local Cosmetics = require(Shared.Cosmetics)
local Progression = require(Shared.Progression)
local Remotes = require(Shared.Remotes)

local DataService = require(script.Parent.DataService)
local ProgressionService = require(script.Parent.ProgressionService)

local InventoryService = {}

local teamColorOverride: { [Player]: Color3? } = {}
local lastRequest: { [Player]: number } = {}

local function rateLimited(player: Player): boolean
	local now = os.clock()
	if lastRequest[player] and now - lastRequest[player] < 0.25 then
		return true
	end
	lastRequest[player] = now
	return false
end

function InventoryService.ApplyToCharacter(player: Player)
	local character = player.Character
	local profile = DataService.GetProfile(player)
	if character and profile then
		Cosmetics.Apply(character, profile.Equipped, teamColorOverride[player])
	end
end

-- Used by MatchService: nil clears the override.
function InventoryService.SetTeamColor(player: Player, color: Color3?)
	teamColorOverride[player] = color
	InventoryService.ApplyToCharacter(player)
end

local function meetsTier(profile, item): boolean
	if not item.RequiredTier then
		return true
	end
	local tierIndex = Progression.GetReputationTier(profile.Reputation)
	return tierIndex >= Progression.TierIndexByName(item.RequiredTier)
end

local function purchase(player: Player, itemId)
	if rateLimited(player) then
		return false, "Slow down"
	end
	if type(itemId) ~= "string" then
		return false, "Invalid item"
	end
	local item = Catalog.Get(itemId)
	local profile = DataService.GetProfile(player)
	if not item or not profile then
		return false, "Invalid item"
	end
	if profile.Inventory[itemId] then
		return false, "Already owned"
	end
	if not meetsTier(profile, item) then
		return false, "Requires reputation: " .. item.RequiredTier
	end
	if not ProgressionService.SpendKicks(player, item.Price) then
		return false, "Not enough Kicks"
	end
	profile.Inventory[itemId] = true
	DataService.MarkDirty(player)
	ProgressionService.Sync(player)
	return true, "Bought " .. item.Name
end

local function equip(player: Player, itemId)
	if rateLimited(player) then
		return false, "Slow down"
	end
	if type(itemId) ~= "string" then
		return false, "Invalid item"
	end
	local item = Catalog.Get(itemId)
	local profile = DataService.GetProfile(player)
	if not item or not profile then
		return false, "Invalid item"
	end
	if not profile.Inventory[itemId] then
		return false, "You do not own this"
	end
	profile.Equipped[item.Category] = itemId
	DataService.MarkDirty(player)
	ProgressionService.Sync(player)
	InventoryService.ApplyToCharacter(player)
	return true, "Equipped " .. item.Name
end

function InventoryService.Init() end

function InventoryService.Start()
	Remotes.Get("PurchaseItem").OnServerInvoke = purchase
	Remotes.Get("EquipItem").OnServerInvoke = equip

	local function hookPlayer(player: Player)
		player.CharacterAppearanceLoaded:Connect(function()
			InventoryService.ApplyToCharacter(player)
		end)
		player.CharacterAdded:Connect(function()
			-- CharacterAppearanceLoaded can fire before the profile loads, so also
			-- apply shortly after spawn.
			task.delay(1, InventoryService.ApplyToCharacter, player)
		end)
	end
	Players.PlayerAdded:Connect(hookPlayer)
	for _, p in Players:GetPlayers() do
		hookPlayer(p)
	end

	DataService.OnProfileLoaded(function(player)
		InventoryService.ApplyToCharacter(player)
	end)

	Players.PlayerRemoving:Connect(function(player)
		teamColorOverride[player] = nil
		lastRequest[player] = nil
	end)
end

return InventoryService
