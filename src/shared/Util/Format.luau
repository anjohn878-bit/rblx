--[[
	Format
	Number formatting helpers: $1,250 / $12.5K / $3.40M ...
]]

local Format = {}

local SUFFIXES = { "K", "M", "B", "T", "Qa", "Qi" }

function Format.Commas(value: number): string
	local negative = value < 0
	local whole = tostring(math.floor(math.abs(value)))
	local formatted = whole:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if formatted:sub(1, 1) == "," then
		formatted = formatted:sub(2)
	end
	return (negative and "-" or "") .. formatted
end

-- Short form for big numbers, full commas for small ones.
function Format.Short(value: number): string
	local absValue = math.abs(value)
	if absValue < 100000 then
		return Format.Commas(value)
	end
	local index = 0
	local scaled = absValue
	while scaled >= 1000 and index < #SUFFIXES do
		scaled /= 1000
		index += 1
	end
	local text
	if scaled >= 100 then
		text = string.format("%d", math.floor(scaled))
	elseif scaled >= 10 then
		text = string.format("%.1f", math.floor(scaled * 10) / 10)
	else
		text = string.format("%.2f", math.floor(scaled * 100) / 100)
	end
	return (value < 0 and "-" or "") .. text .. SUFFIXES[index]
end

function Format.Money(value: number): string
	return "$" .. Format.Short(value)
end

function Format.Time(seconds: number): string
	if seconds < 60 then
		return string.format("%ds", math.floor(seconds))
	end
	return string.format("%dm %02ds", math.floor(seconds / 60), math.floor(seconds % 60))
end

return Format
