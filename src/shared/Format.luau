--[[
	Format
	Number formatting for the UI: 1234 -> "1,234", 1250000 -> "1.25M".
]]

local Format = {}

local SUFFIXES = { "", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc" }

local function trimZeros(text)
	if string.find(text, "%.") then
		text = string.gsub(text, "0+$", "")
		text = string.gsub(text, "%.$", "")
	end
	return text
end

function Format.commas(number)
	local negative = number < 0
	local text = tostring(math.floor(math.abs(number)))
	local formatted = string.reverse((string.gsub(string.reverse(text), "(%d%d%d)", "%1,")))
	formatted = string.gsub(formatted, "^,", "")
	return if negative then "-" .. formatted else formatted
end

function Format.abbreviate(number)
	local negative = number < 0
	local value = math.floor(math.abs(number))
	if value < 10000 then
		return Format.commas(if negative then -value else value)
	end

	local index = 1
	local scaled = value
	while scaled >= 1000 and index < #SUFFIXES do
		scaled /= 1000
		index += 1
	end

	local text
	if scaled < 10 then
		text = trimZeros(string.format("%.2f", math.floor(scaled * 100) / 100))
	elseif scaled < 100 then
		text = trimZeros(string.format("%.1f", math.floor(scaled * 10) / 10))
	else
		text = tostring(math.floor(scaled))
	end

	return (if negative then "-" else "") .. text .. SUFFIXES[index]
end

function Format.multiplier(value)
	return "x" .. trimZeros(string.format("%.2f", value))
end

return Format
