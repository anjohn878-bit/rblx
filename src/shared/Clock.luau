--!strict
-- One clock for the whole game. GetServerTimeNow is synchronised between the
-- server and every client, so timers agree everywhere (and survive restarts).

local Clock = {}

function Clock.now(): number
	return workspace:GetServerTimeNow()
end

return Clock
