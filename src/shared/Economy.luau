--[[
	Pure money / XP / rank maths. No engine calls, so it is unit-tested outside Roblox
	(see tests/). Positions only need .X and .Z fields, so Vector3s and plain tables both work.
]]

local Config = require(script.Parent.Config)

local Economy = {}

local E = Config.Economy

-- Ranks -------------------------------------------------------------------------

function Economy.rankIndexForXp(xp: number): number
	local index = 1
	for i, rank in Config.Ranks do
		if xp >= rank.XP then
			index = i
		else
			break
		end
	end
	return index
end

-- Everything the HUD needs to draw the XP bar.
function Economy.rankInfo(xp: number)
	local index = Economy.rankIndexForXp(xp)
	local rank = Config.Ranks[index]
	local nextRank = Config.Ranks[index + 1]
	local fraction = 1
	if nextRank then
		fraction = (xp - rank.XP) / (nextRank.XP - rank.XP)
	end
	return {
		Index = index,
		Name = rank.Name,
		XPStart = rank.XP,
		XPNext = nextRank and nextRank.XP or nil,
		Fraction = math.clamp(fraction, 0, 1),
		PayMult = rank.PayMult,
	}
end

-- Orders ------------------------------------------------------------------------

-- Cars can't cut across blocks, so distance along the street grid is what matters.
function Economy.routeDistance(a, b): number
	return math.abs(a.X - b.X) + math.abs(a.Z - b.Z)
end

function Economy.timeLimit(distance: number, vehicleMaxSpeed: number, package): number
	local seconds = E.TimeBase + distance / (vehicleMaxSpeed * E.TimeSpeedFactor)
	return math.floor(seconds * package.TimeMult + 0.5)
end

function Economy.basePay(distance: number, rank, package, vehicle): number
	local pay = (E.BasePay + distance * E.PayPerStud) * rank.PayMult * package.PayMult
	pay *= 1 + (vehicle.PayBonus or 0)
	return math.floor(pay + 0.5)
end

function Economy.stars(timeUsed: number, timeLimit: number): number
	local ratio = timeUsed / timeLimit
	local thresholds = E.StarThresholds
	if ratio <= thresholds[1] then
		return 5
	elseif ratio <= thresholds[2] then
		return 4
	elseif ratio <= thresholds[3] then
		return 3
	elseif ratio <= thresholds[4] then
		return 2
	end
	return 1
end

-- The least time any legitimate driver could need; used to ignore teleport-style cheating.
function Economy.minTravelTime(distance: number): number
	return distance / Config.MaxPlausibleSpeed
end

-- Works out what a finished delivery earns.
-- order needs: Distance, TimeLimit, BasePay.  streakBefore = on-time deliveries in a row so far.
function Economy.settle(order, timeUsed: number, streakBefore: number)
	local onTime = timeUsed <= order.TimeLimit
	local stars = Economy.stars(timeUsed, order.TimeLimit)
	local base = order.BasePay

	local timeBonus, tip, streakBonus = 0, 0, 0
	if onTime then
		local ratio = timeUsed / order.TimeLimit
		local fraction = math.clamp((1 - ratio) / 0.5, 0, 1)
		timeBonus = math.floor(base * E.TimeBonusMax * fraction + 0.5)
		tip = math.floor(base * (E.TipByStars[stars] or 0) + 0.5)
		streakBonus = math.floor(base * math.min(E.StreakMax, streakBefore * E.StreakStep) + 0.5)
	end

	local xp = (E.XPBase + order.Distance * E.XPPerStud) * (onTime and 1 or E.LateXPMult) + stars * E.XPPerStar

	return {
		OnTime = onTime,
		Stars = stars,
		Base = base,
		TimeBonus = timeBonus,
		Tip = tip,
		StreakBonus = streakBonus,
		Total = base + timeBonus + tip + streakBonus,
		XP = math.floor(xp + 0.5),
	}
end

-- Formatting (kept here so server toasts and client UI agree) ---------------------

function Economy.formatMoney(amount: number): string
	local n = math.floor(amount + 0.5)
	local negative = n < 0
	local digits = tostring(math.abs(n))
	-- insert thousands separators
	local out = digits:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if out:sub(1, 1) == "," then
		out = out:sub(2)
	end
	return (negative and "-$" or "$") .. out
end

function Economy.formatTime(seconds: number): string
	seconds = math.max(0, math.floor(seconds + 0.5))
	return string.format("%d:%02d", seconds // 60, seconds % 60)
end

return Economy
