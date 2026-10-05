--[[
	Pure order logic: picking a destination, and deciding what a position/speed/time means.
	No engine calls - the OrderService wires this to players, prompts and attributes.

	An order is a plain table:
	  Id, HouseId, Address, Dest (Vector3), Distance, Package, TimeLimit, BasePay,
	  StartTime (server clock, set by the caller), VehicleId
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local Economy = require(ReplicatedStorage.Shared.Economy)

local Orders = {}

-- rng(a, b) must return an integer in [a, b].
-- avoidIds is a set of house ids to skip (recent deliveries) when there is any alternative.
function Orders.generate(houses, origin, rankIndex: number, vehicleSpec, rng, avoidIds)
	local rank = Config.Ranks[rankIndex]
	local candidates = {}
	local fallback = {}
	for _, house in houses do
		local distance = Economy.routeDistance(origin, house.MarkerPos)
		if distance >= rank.MinDist and distance <= rank.MaxDist then
			local entry = { House = house, Distance = distance }
			table.insert(fallback, entry)
			if not (avoidIds and avoidIds[house.Id]) then
				table.insert(candidates, entry)
			end
		end
	end

	if #candidates == 0 then
		candidates = fallback
	end
	if #candidates == 0 then
		-- Town too small for this rank's range: take the house closest to the middle of it.
		local target = (rank.MinDist + rank.MaxDist) / 2
		local best, bestScore = nil, math.huge
		for _, house in houses do
			local distance = Economy.routeDistance(origin, house.MarkerPos)
			local score = math.abs(distance - target)
			if score < bestScore then
				best, bestScore = { House = house, Distance = distance }, score
			end
		end
		assert(best, "no houses to deliver to")
		candidates = { best }
	end

	local pick = candidates[rng(1, #candidates)]
	local package = Config.Packages[rng(1, #Config.Packages)]
	local house = pick.House

	return {
		HouseId = house.Id,
		Address = house.Address,
		Dest = house.MarkerPos,
		Distance = pick.Distance,
		Package = package,
		TimeLimit = Economy.timeLimit(pick.Distance, vehicleSpec.MaxSpeed, package),
		BasePay = Economy.basePay(pick.Distance, rank, package, vehicleSpec),
		VehicleId = vehicleSpec.Id,
	}
end

-- What should happen right now, given where the player is and how fast they're going?
--   "none"     not at the marker
--   "toofast"  at the marker but must slow down
--   "early"    would deliver, but impossibly fast for the distance (teleport-style cheating); keep waiting
--   "deliver"  hand the package over
function Orders.checkArrival(order, position, speed: number, elapsed: number): string
	local dx, dz = position.X - order.Dest.X, position.Z - order.Dest.Z
	if math.sqrt(dx * dx + dz * dz) > Config.DeliveryRadius then
		return "none"
	end
	if speed > Config.DeliveryMaxSpeed then
		return "toofast"
	end
	if elapsed < Economy.minTravelTime(order.Distance) then
		return "early"
	end
	return "deliver"
end

-- "ok" while there's time, "late" once past the deadline, "failed" once the customer gives up.
function Orders.status(order, elapsed: number): string
	if elapsed <= order.TimeLimit then
		return "ok"
	elseif elapsed <= order.TimeLimit + Config.OrderFailGrace then
		return "late"
	end
	return "failed"
end

return Orders
