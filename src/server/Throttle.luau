--!strict
-- Tiny per-player rate limiter for remote handlers.

local Throttle = {}

local last: { [string]: { [Player]: number } } = {}

function Throttle.ok(player: Player, key: string, interval: number): boolean
	local bucket = last[key]
	if not bucket then
		bucket = setmetatable({}, { __mode = "k" }) :: any
		last[key] = bucket
	end
	local now = os.clock()
	local previous = (bucket :: { [Player]: number })[player]
	if previous and now - previous < interval then
		return false
	end
	(bucket :: { [Player]: number })[player] = now
	return true
end

return Throttle
