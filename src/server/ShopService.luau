--!strict
-- The seed shop. Stock restocks on a fixed global clock (the roll is seeded by
-- the restock number, so every server shows the same shelves) and is shared by
-- everyone on the server, so rare seeds can sell out.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Clock = require(Shared:WaitForChild("Clock"))
local Config = require(Shared:WaitForChild("Config"))
local Format = require(Shared:WaitForChild("Format"))
local Growth = require(Shared:WaitForChild("Growth"))
local Remotes = require(Shared:WaitForChild("Remotes")).get()
local Seeds = require(Shared:WaitForChild("Seeds"))
local Types = require(Shared:WaitForChild("Types"))

local DataService = require(script.Parent.DataService)
local GardenService = require(script.Parent.GardenService)

local ShopService = {}

local currentIndex = -1
local stock: { [string]: number } = {}

-- Returns true if a new restock just happened.
local function refresh(): boolean
	local index = Growth.restockIndex(Clock.now())
	if index == currentIndex then
		return false
	end
	currentIndex = index
	stock = Growth.rollStock(index)
	return true
end

function ShopService.getStock(): Types.StockInfo
	refresh()
	local copy = {}
	for id, count in stock do
		copy[id] = count
	end
	return { stock = copy, nextRestock = Growth.nextRestock(Clock.now()) }
end

local function broadcast()
	Remotes.StockUpdate:FireAllClients(ShopService.getStock())
end

function ShopService.init()
	refresh()
	task.spawn(function()
		while true do
			task.wait(1)
			if refresh() then
				broadcast()
			end
		end
	end)
end

function ShopService.buySeed(player: Player, seedId: any, amount: any): Types.Result
	local profile = DataService.get(player)
	if not profile then
		return { ok = false, message = "Still loading your garden..." }
	end
	if not Seeds.isValid(seedId) then
		return { ok = false, message = "Unknown seed." }
	end
	if type(amount) ~= "number" or amount ~= math.floor(amount) or amount < 1 or amount > Config.MAX_BUY_AMOUNT then
		return { ok = false, message = "Invalid amount." }
	end

	refresh()
	local id = seedId :: string
	local seed = Seeds.get(id) :: Types.SeedDef
	local available = stock[id] or 0
	if available < 1 then
		return { ok = false, message = `{seed.name} is out of stock. Check back after the restock!` }
	end
	if amount > available then
		return { ok = false, message = `Only {available} left in stock.` }
	end
	local cost = seed.price * amount
	if profile.feathers < cost then
		return { ok = false, message = `Not enough feathers (need {Format.feathers(cost)}).` }
	end

	profile.feathers -= cost
	profile.seeds[id] = (profile.seeds[id] or 0) + amount
	stock[id] = available - amount
	DataService.push(player)
	broadcast()
	return { ok = true, message = `Bought {amount}x {seed.name}!` }
end

function ShopService.unlockPlot(player: Player): Types.Result
	local profile = DataService.get(player)
	if not profile then
		return { ok = false, message = "Still loading your garden..." }
	end
	local price = Growth.plotPrice(profile.plots)
	if not price then
		return { ok = false, message = "Every plot is already unlocked!" }
	end
	if profile.feathers < price then
		return { ok = false, message = `Not enough feathers (need {Format.feathers(price)}).` }
	end
	profile.feathers -= price
	profile.plots += 1
	GardenService.refreshPlots(player, profile.plots)
	DataService.push(player)
	return { ok = true, message = `Plot {profile.plots} unlocked!` }
end

-- Dev helper: fill every shelf.
function ShopService.devFillStock()
	refresh()
	for _, seed in Seeds.list do
		stock[seed.id] = 10
	end
	broadcast()
end

return ShopService
