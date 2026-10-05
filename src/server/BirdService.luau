--!strict
-- Runs bird visits. Each perch on a mature plant is an independent slot driven
-- by the pure Scheduler; this module turns its events into real effects
-- (spawn a visit for every client, pay feathers, record discoveries).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BirdFlight = require(Shared:WaitForChild("BirdFlight"))
local Birds = require(Shared:WaitForChild("Birds"))
local Config = require(Shared:WaitForChild("Config"))
local Growth = require(Shared:WaitForChild("Growth"))
local Remotes = require(Shared:WaitForChild("Remotes")).get()
local Scheduler = require(Shared:WaitForChild("Scheduler"))
local Types = require(Shared:WaitForChild("Types"))

local DataService = require(script.Parent.DataService)

local BirdService = {}

-- What BirdService needs to know about a plant (PlantService's state has all of it).
export type Habitat = {
	player: Player,
	plotIndex: number,
	seed: Types.SeedDef,
	root: BasePart,
	slots: { Scheduler.Slot },
}

type Active = { info: Types.VisitInfo, habitat: Habitat }

local active: { [number]: Active } = {}
local nextId = 1
local rng = Random.new()

local function startVisit(h: Habitat, slotIndex: number, slot: Scheduler.Slot, now: number)
	local timing = Scheduler.start(slot, now, rng)
	local birdId = Growth.pickBird(h.seed, rng)
	local offset = h.seed.perches[slotIndex]
	local perch = h.root.CFrame:PointToWorldSpace(Vector3.new(offset[1], offset[2], offset[3]))
	local plan = BirdFlight.plan(perch, rng)

	local id = nextId
	nextId += 1
	local info: Types.VisitInfo = {
		id = id,
		birdId = birdId,
		ownerUserId = h.player.UserId,
		perch = perch,
		from = plan.from,
		to = plan.to,
		facing = plan.facing,
		startTime = now,
		arrive = timing.arrive,
		stay = timing.stay,
		leave = timing.leave,
		seed = plan.seed,
	}
	active[id] = { info = info, habitat = h }
	slot.visitId = id
	Remotes.BirdVisit:FireAllClients(info)
end

-- The bird has landed: pay the owner and record the species.
local function payVisit(h: Habitat, slot: Scheduler.Slot)
	Scheduler.markPaid(slot)
	local entry = if slot.visitId then active[slot.visitId] else nil
	local profile = DataService.get(h.player)
	if not entry or not profile then
		return
	end
	local def = Birds.get(entry.info.birdId)
	if not def then
		return
	end

	local seenBefore = profile.birds[def.id] or 0
	profile.birds[def.id] = seenBefore + 1
	profile.totalVisits += 1
	local bonus = if seenBefore == 0 then def.value * Config.DISCOVERY_MULTIPLIER else 0
	profile.feathers += def.value + bonus
	DataService.push(h.player)

	local reward: Types.Notice = {
		kind = "reward",
		amount = def.value,
		birdId = def.id,
		position = entry.info.perch + Vector3.new(0, 1.5 + def.scale, 0),
		bonus = if bonus > 0 then bonus else nil,
	}
	Remotes.Notify:FireClient(h.player, reward)
	if bonus > 0 then
		local discovery: Types.Notice = { kind = "discovery", birdId = def.id, bonus = bonus }
		Remotes.Notify:FireClient(h.player, discovery)
	end
end

local function finishVisit(slot: Scheduler.Slot, now: number)
	if slot.visitId then
		active[slot.visitId] = nil
	end
	Scheduler.finish(slot, now, rng)
end

function BirdService.update(h: Habitat, now: number)
	for index, slot in h.slots do
		local action = Scheduler.due(slot, now)
		if action == "start" then
			startVisit(h, index, slot, now)
		elseif action == "reward" then
			payVisit(h, slot)
		elseif action == "finish" then
			finishVisit(slot, now)
		end
	end
end

-- The plant is going away: tell clients to drop any birds that were headed for it.
function BirdService.cancelHabitat(h: Habitat)
	for _, slot in h.slots do
		local id = slot.visitId
		if id and active[id] then
			active[id] = nil
			Remotes.BirdCancel:FireAllClients(id)
		end
		slot.visitId = nil
		slot.visiting = false
	end
end

-- For players who join mid-visit.
function BirdService.activeVisits(): { Types.VisitInfo }
	local list = {}
	for _, entry in active do
		table.insert(list, entry.info)
	end
	return list
end

return BirdService
