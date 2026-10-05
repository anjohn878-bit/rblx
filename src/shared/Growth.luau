--!strict
-- Pure game rules (no Instances), so they can be unit-tested outside Roblox.

local Config = require(script.Parent.Config)
local Seeds = require(script.Parent.Seeds)
local Types = require(script.Parent.Types)
type SeedDef = Types.SeedDef

local Growth = {}

-- 0 = just planted, 1 = fully grown
function Growth.progress(plantedAt: number, growTime: number, now: number): number
	if growTime <= 0 then
		return 1
	end
	return math.clamp((now - plantedAt) / growTime, 0, 1)
end

-- Visual size of a plant at a given progress
function Growth.scale(progress: number): number
	return Config.SCALE_MIN + (1 - Config.SCALE_MIN) * progress
end

function Growth.pickBird(seed: SeedDef, rng: Random): string
	local total = 0
	for _, entry in seed.birds do
		total += entry.weight
	end
	local roll = rng:NextNumber() * total
	for _, entry in seed.birds do
		roll -= entry.weight
		if roll <= 0 then
			return entry.id
		end
	end
	return seed.birds[#seed.birds].id
end

-- The shop restocks on a fixed global clock. The roll is seeded by the interval
-- number, so every server sees the same stock (like the real Grow a Garden).
function Growth.restockIndex(now: number): number
	return math.floor(now / Config.RESTOCK_INTERVAL)
end

function Growth.nextRestock(now: number): number
	return (Growth.restockIndex(now) + 1) * Config.RESTOCK_INTERVAL
end

function Growth.rollStock(index: number): { [string]: number }
	local rng = Random.new(index * 7919 + 17)
	local stock: { [string]: number } = {}
	for _, seed in Seeds.list do
		-- Always consume the same rolls so one seed's luck never shifts another's.
		local roll = rng:NextNumber()
		local amount = rng:NextInteger(seed.stock.min, seed.stock.max)
		if roll < seed.stock.chance then
			stock[seed.id] = amount
		end
	end
	return stock
end

-- Price of the next plot to unlock, or nil when every plot is already unlocked.
function Growth.plotPrice(unlocked: number): number?
	return Config.PLOT_PRICES[unlocked - Config.START_PLOTS + 1]
end

-- Expected feathers per visit for a seed (used for balancing and the shop UI).
function Growth.expectedVisitValue(seed: SeedDef, birdValue: (string) -> number): number
	local total, weighted = 0, 0
	for _, entry in seed.birds do
		total += entry.weight
		weighted += entry.weight * birdValue(entry.id)
	end
	return weighted / total
end

return Growth
