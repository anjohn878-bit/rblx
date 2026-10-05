--[[
	ShopService
	Handles every purchase: skates, upgrades, rink unlocks and rebirths.
	All prices come from Formulas so the server is the only authority.
]]

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Format = require(Shared.Format)
local Formulas = require(Shared.Formulas)
local Remotes = require(Shared.Remotes)

local DataService = require(script.Parent.DataService)

local ShopService = {}

local lastPurchase = {}

local function notEnough(profile, cost)
	return false,
		string.format("You need %s more %s.", Format.abbreviate(cost - profile.Snowflakes), Config.CurrencyName)
end

function ShopService.buySkate(player, tier)
	local profile = DataService.get(player)
	if not profile then
		return false, "Still loading your data..."
	end
	if type(tier) ~= "number" or tier ~= profile.SkateTier + 1 then
		return false, "Buy the skates before these first."
	end
	local skate = Config.Skates[tier]
	if not skate then
		return false, "Those skates don't exist."
	end
	if not DataService.spend(player, skate.Price) then
		return notEnough(profile, skate.Price)
	end
	profile.SkateTier = tier
	DataService.markChanged(player)
	return true, "Equipped " .. skate.Name .. "!"
end

function ShopService.buyUpgrade(player, upgradeId)
	local profile = DataService.get(player)
	if not profile then
		return false, "Still loading your data..."
	end
	local upgrade = Formulas.getUpgrade(upgradeId)
	if not upgrade then
		return false, "Unknown upgrade."
	end
	local level = Formulas.upgradeLevel(profile, upgradeId)
	local cost = Formulas.upgradeCost(upgradeId, level)
	if not cost then
		return false, upgrade.Name .. " is already maxed!"
	end
	if not DataService.spend(player, cost) then
		return notEnough(profile, cost)
	end
	profile.Upgrades[upgradeId] = level + 1
	DataService.markChanged(player)
	return true, string.format("%s upgraded to level %d!", upgrade.Name, level + 1)
end

function ShopService.unlockRink(player, rinkId)
	local profile = DataService.get(player)
	if not profile then
		return false, "Still loading your data..."
	end
	local rink = Formulas.getRink(rinkId)
	if not rink then
		return false, "Unknown rink."
	end
	if Formulas.isRinkUnlocked(profile, rinkId) then
		return false, rink.Name .. " is already unlocked."
	end
	if not DataService.spend(player, rink.Price) then
		return notEnough(profile, rink.Price)
	end
	profile.UnlockedRinks[rinkId] = true
	DataService.markChanged(player)
	return true, rink.Name .. " unlocked! " .. Format.multiplier(rink.Multiplier) .. " snowflakes there."
end

function ShopService.rebirth(player)
	local profile = DataService.get(player)
	if not profile then
		return false, "Still loading your data..."
	end
	local cost = Formulas.rebirthCost(profile.Rebirths)
	if not DataService.spend(player, cost) then
		return notEnough(profile, cost)
	end
	profile.Rebirths += 1
	profile.Snowflakes = 0
	profile.SkateTier = 1
	for upgradeId in profile.Upgrades do
		profile.Upgrades[upgradeId] = 0
	end
	DataService.markChanged(player)
	Remotes.Rebirthed:FireClient(player, profile.Rebirths)
	return true,
		string.format(
			"Rebirth %d! You now earn %s snowflakes.",
			profile.Rebirths,
			Format.multiplier(Formulas.rebirthMultiplier(profile))
		)
end

local handlers = {
	Skate = ShopService.buySkate,
	Upgrade = ShopService.buyUpgrade,
	Rink = ShopService.unlockRink,
	Rebirth = ShopService.rebirth,
}

local function onPurchase(player, kind, id)
	local now = os.clock()
	if now - (lastPurchase[player] or 0) < 0.15 then
		return false, "Slow down!"
	end
	lastPurchase[player] = now

	local handler = type(kind) == "string" and handlers[kind]
	if not handler then
		return false, "Unknown purchase."
	end
	return handler(player, id)
end

function ShopService.init()
	Remotes.Purchase.OnServerInvoke = onPurchase

	-- Rink gates are unlocked straight from their proximity prompt.
	ProximityPromptService.PromptTriggered:Connect(function(prompt, player)
		if prompt:GetAttribute("Action") ~= "UnlockRink" then
			return
		end
		local ok, message = ShopService.unlockRink(player, prompt:GetAttribute("RinkId"))
		Remotes.Notify:FireClient(player, message, if ok then "success" else "error")
	end)

	Players.PlayerRemoving:Connect(function(player)
		lastPurchase[player] = nil
	end)
end

return ShopService
