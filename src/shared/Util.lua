-- Small helpers shared by the server and the client.

local Util = {}

-- Unix time in seconds (with milliseconds). Used for growth and timers.
function Util.Now()
	return DateTime.now().UnixTimestampMillis / 1000
end

function Util.FormatNumber(n)
	n = math.floor(n or 0)
	if n >= 1e9 then
		return string.format("%.1fB", n / 1e9)
	elseif n >= 1e6 then
		return string.format("%.1fM", n / 1e6)
	end
	local text = tostring(n)
	local formatted = text:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if formatted:sub(1, 1) == "," then
		formatted = formatted:sub(2)
	end
	return formatted
end

function Util.FormatTime(seconds)
	seconds = math.max(0, math.ceil(seconds or 0))
	local hours = math.floor(seconds / 3600)
	local minutes = math.floor((seconds % 3600) / 60)
	local secs = seconds % 60
	if hours > 0 then
		return string.format("%dh %02dm", hours, minutes)
	elseif minutes > 0 then
		return string.format("%dm %02ds", minutes, secs)
	end
	return string.format("%ds", secs)
end

-- Picks an entry from a list of { Weight = number } tables.
function Util.WeightedPick(list, rng)
	local total = 0
	for _, entry in ipairs(list) do
		total += entry.Weight
	end
	local roll = (rng and rng:NextNumber() or math.random()) * total
	for _, entry in ipairs(list) do
		roll -= entry.Weight
		if roll <= 0 then
			return entry
		end
	end
	return list[#list]
end

function Util.DeepCopy(value)
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for k, v in pairs(value) do
		copy[k] = Util.DeepCopy(v)
	end
	return copy
end

return Util
