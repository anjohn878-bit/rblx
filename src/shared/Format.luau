--!strict

local Format = {}

function Format.commas(n: number): string
	local s = string.format("%.0f", n)
	local k
	repeat
		s, k = string.gsub(s, "^(-?%d+)(%d%d%d)", "%1,%2")
	until k == 0
	return s
end

local SUFFIXES = { "K", "M", "B", "T" }

-- 950 -> "950", 123456 -> "123,456", 1234567 -> "1.23M"
function Format.feathers(n: number): string
	n = math.floor(n + 0.5)
	if n < 1_000_000 then
		return Format.commas(n)
	end
	local value = n
	local suffix = ""
	for _, s in SUFFIXES do
		value /= 1000
		suffix = s
		if value < 1000 then
			break
		end
	end
	local text = string.format("%.2f", value)
	text = string.gsub(text, "%.?0+$", "")
	return text .. suffix
end

-- 34 -> "0:34", 754 -> "12:34", 7300 -> "2h 02m"
function Format.duration(seconds: number): string
	seconds = math.max(0, math.ceil(seconds))
	if seconds >= 3600 then
		local h = seconds // 3600
		local m = (seconds % 3600) // 60
		return string.format("%dh %02dm", h, m)
	end
	return string.format("%d:%02d", seconds // 60, seconds % 60)
end

-- 20 -> "20 sec", 90 -> "1.5 min", 7200 -> "2 hr"
function Format.growTime(seconds: number): string
	if seconds < 60 then
		return string.format("%d sec", seconds)
	elseif seconds < 3600 then
		local minutes = seconds / 60
		if minutes == math.floor(minutes) then
			return string.format("%d min", minutes)
		end
		return string.format("%.1f min", minutes)
	end
	local hours = seconds / 3600
	if hours == math.floor(hours) then
		return string.format("%d hr", hours)
	end
	return string.format("%.1f hr", hours)
end

return Format
