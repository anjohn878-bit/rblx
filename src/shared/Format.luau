-- Text formatting helpers shared by the server (notifications) and the client (HUD).

local Format = {}

local STUDS_TO_METRES = 0.28
local STUDS_PER_SECOND_TO_MPH = STUDS_TO_METRES * 2.23694

function Format.commas(n: number): string
	local s = tostring(math.floor(math.abs(n)))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if out:sub(1, 1) == "," then
		out = out:sub(2)
	end
	return (if n < 0 then "-" else "") .. out
end

function Format.money(n: number): string
	return "$" .. Format.commas(n)
end

function Format.distance(studs: number): string
	local metres = studs * STUDS_TO_METRES
	if metres >= 1000 then
		return string.format("%.1f km", metres / 1000)
	end
	return string.format("%d m", math.floor(metres + 0.5))
end

function Format.speed(studsPerSecond: number): string
	return string.format("%d", math.floor(math.abs(studsPerSecond) * STUDS_PER_SECOND_TO_MPH + 0.5))
end

function Format.clock(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	return string.format("%d:%02d", seconds // 60, seconds % 60)
end

return Format
