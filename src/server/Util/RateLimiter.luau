--[[
	RateLimiter
	Token bucket per player, used to throttle every client->server remote.
]]

local Players = game:GetService("Players")

local RateLimiter = {}
RateLimiter.__index = RateLimiter

export type RateLimiter = typeof(setmetatable(
	{} :: { Rate: number, Burst: number, Buckets: { [Player]: { Tokens: number, Last: number } } },
	RateLimiter
))

function RateLimiter.new(ratePerSecond: number, burst: number): RateLimiter
	local self = setmetatable({
		Rate = ratePerSecond,
		Burst = burst,
		Buckets = {},
	}, RateLimiter)
	Players.PlayerRemoving:Connect(function(player)
		self.Buckets[player] = nil
	end)
	return self
end

function RateLimiter.Check(self: RateLimiter, player: Player): boolean
	local now = os.clock()
	local bucket = self.Buckets[player]
	if not bucket then
		bucket = { Tokens = self.Burst, Last = now }
		self.Buckets[player] = bucket
	end
	bucket.Tokens = math.min(self.Burst, bucket.Tokens + (now - bucket.Last) * self.Rate)
	bucket.Last = now
	if bucket.Tokens >= 1 then
		bucket.Tokens -= 1
		return true
	end
	return false
end

return RateLimiter
