-- The seed shop. Stock is rerolled every few minutes; rarer seeds show up
-- less often. Each player can buy up to the listed stock per restock.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Rarities = require(Shared.Rarities)
local Seeds = require(Shared.Seeds)
local Util = require(Shared.Util)

local DataService = require(script.Parent.DataService)

local ShopService = {}

local rng = Random.new()
local stock = {} -- [seedId] = amount available this restock
local purchased = {} -- [userId] = { [seedId] = amount bought this restock }
local nextRestock = 0

local function remainingFor(player, seedId)
	local bought = purchased[player.UserId]
	return math.max(0, (stock[seedId] or 0) - (bought and bought[seedId] or 0))
end

function ShopService.Snapshot(player)
	local remaining = {}
	for _, seed in ipairs(Seeds.List) do
		remaining[seed.Id] = remainingFor(player, seed.Id)
	end
	return {
		Stock = remaining,
		NextRestock = nextRestock,
		ServerNow = Util.Now(),
	}
end

function ShopService.Restock(announce)
	local rareFinds = {}
	for _, seed in ipairs(Seeds.List) do
		if rng:NextNumber() <= seed.Stock.Chance then
			stock[seed.Id] = rng:NextInteger(seed.Stock.Min, seed.Stock.Max)
			if Rarities.Rank(seed.Rarity) >= Rarities.Rank("Rare") then
				table.insert(rareFinds, seed.Icon .. " " .. seed.Name)
			end
		else
			stock[seed.Id] = 0
		end
	end
	nextRestock = Util.Now() + Config.RestockInterval
	table.clear(purchased)

	for _, player in ipairs(Players:GetPlayers()) do
		Net.ShopUpdated:FireClient(player, ShopService.Snapshot(player))
		if announce then
			if #rareFinds > 0 then
				Net.Notify:FireClient(
					player,
					"🌱 The Seed Shop restocked! Rare seeds: " .. table.concat(rareFinds, ", "),
					"Rare"
				)
			else
				Net.Notify:FireClient(player, "🌱 The Seed Shop has restocked!", "Info")
			end
		end
	end
end

function ShopService.Init()
	ShopService.Restock(false)
end

function ShopService.Tick(now)
	if now >= nextRestock then
		ShopService.Restock(true)
	end
end

-- Returns ok, message
function ShopService.Buy(player, seedId)
	if type(seedId) ~= "string" then
		return false, "That seed doesn't exist."
	end
	local seed = Seeds.Get(seedId)
	local profile = DataService.GetProfile(player)
	if not seed then
		return false, "That seed doesn't exist."
	end
	if not profile then
		return false, "Your garden is still loading..."
	end
	if remainingFor(player, seedId) <= 0 then
		return false, seed.Name .. " is sold out! Wait for the next restock."
	end
	local data = profile.Data
	if data.Coins < seed.Price then
		return false, "Not enough coins! Befriend more birds to earn coins."
	end

	data.Coins -= seed.Price
	data.Seeds[seedId] = (data.Seeds[seedId] or 0) + 1
	local bought = purchased[player.UserId] or {}
	bought[seedId] = (bought[seedId] or 0) + 1
	purchased[player.UserId] = bought

	if not profile.SelectedSeed then
		profile.SelectedSeed = seedId
	end
	DataService.Push(player)
	Net.ShopUpdated:FireClient(player, ShopService.Snapshot(player))
	return true, "Bought a " .. seed.Name .. " seed!"
end

return ShopService
