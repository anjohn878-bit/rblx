--!strict
-- The client's copy of the player's data, plus which seed is selected.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Seeds = require(Shared:WaitForChild("Seeds"))
local Signal = require(Shared:WaitForChild("Signal"))
local Types = require(Shared:WaitForChild("Types"))

local State = {
	feathers = 0,
	seeds = {} :: { [string]: number },
	birds = {} :: { [string]: number },
	plots = 0,
	nextPlotPrice = nil :: number?,
	totalVisits = 0,
	stock = {} :: { [string]: number },
	nextRestock = 0,
	selected = nil :: string?,
	changed = Signal.new(), -- any data change
	stockChanged = Signal.new(),
	selectedChanged = Signal.new(),
}

local function ensureSelection()
	local current = State.selected
	if current and (State.seeds[current] or 0) > 0 then
		return
	end
	local pick: string? = nil
	for _, seed in Seeds.list do
		if (State.seeds[seed.id] or 0) > 0 then
			pick = seed.id
			break
		end
	end
	if pick ~= current then
		State.selected = pick
		State.selectedChanged:Fire(pick)
	end
end

function State.apply(snapshot: Types.Snapshot)
	State.feathers = snapshot.feathers
	State.seeds = snapshot.seeds
	State.birds = snapshot.birds
	State.plots = snapshot.plots
	State.nextPlotPrice = snapshot.nextPlotPrice
	State.totalVisits = snapshot.totalVisits
	ensureSelection()
	State.changed:Fire()
end

function State.setStock(info: Types.StockInfo)
	State.stock = info.stock
	State.nextRestock = info.nextRestock
	State.stockChanged:Fire()
end

function State.select(id: string?)
	if id ~= nil and (State.seeds[id] or 0) < 1 then
		return
	end
	if State.selected ~= id then
		State.selected = id
		State.selectedChanged:Fire(id)
	end
end

function State.seedCount(id: string): number
	return State.seeds[id] or 0
end

function State.totalSeeds(): number
	local total = 0
	for _, count in State.seeds do
		total += count
	end
	return total
end

function State.speciesDiscovered(): number
	local n = 0
	for _ in State.birds do
		n += 1
	end
	return n
end

return State
