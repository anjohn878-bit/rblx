--!strict
-- Pure state machine for one perch on a plant:
--   idle --(wait elapsed)--> visiting --(lands: pay feathers)--> visiting --(leaves)--> idle
-- The server ticks it; the Roblox-specific work (spawning, paying) lives in BirdService.

local Config = require(script.Parent.Config)

local Scheduler = {}

export type Slot = {
	visiting: boolean,
	nextVisitAt: number,
	rewardAt: number,
	endAt: number,
	paid: boolean,
	visitId: number?,
}

export type Timing = { arrive: number, stay: number, leave: number }

function Scheduler.newSlot(now: number, rng: Random, first: boolean): Slot
	local v = Config.VISIT
	local wait = if first
		then rng:NextNumber(v.FIRST_WAIT_MIN, v.FIRST_WAIT_MAX)
		else rng:NextNumber(v.WAIT_MIN, v.WAIT_MAX)
	return { visiting = false, nextVisitAt = now + wait, rewardAt = 0, endAt = 0, paid = false, visitId = nil }
end

-- What should happen to this slot right now?
function Scheduler.due(slot: Slot, now: number): "start" | "reward" | "finish" | nil
	if not slot.visiting then
		if now >= slot.nextVisitAt then
			return "start"
		end
		return nil
	end
	if not slot.paid and now >= slot.rewardAt then
		return "reward"
	end
	if now >= slot.endAt then
		return "finish"
	end
	return nil
end

function Scheduler.start(slot: Slot, now: number, rng: Random): Timing
	local v = Config.VISIT
	local timing = { arrive = v.ARRIVE, stay = rng:NextNumber(v.STAY_MIN, v.STAY_MAX), leave = v.LEAVE }
	slot.visiting = true
	slot.paid = false
	slot.rewardAt = now + timing.arrive
	slot.endAt = now + timing.arrive + timing.stay + timing.leave
	return timing
end

function Scheduler.markPaid(slot: Slot)
	slot.paid = true
end

function Scheduler.finish(slot: Slot, now: number, rng: Random)
	local v = Config.VISIT
	slot.visiting = false
	slot.visitId = nil
	slot.nextVisitAt = now + rng:NextNumber(v.WAIT_MIN, v.WAIT_MAX)
end

return Scheduler
