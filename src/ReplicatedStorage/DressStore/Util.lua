-- Small helpers shared by the server and the client.

local Util = {}

local function withCommas(n: number): string
	local text = tostring(math.floor(n))
	local sign = ""
	if string.sub(text, 1, 1) == "-" then
		sign = "-"
		text = string.sub(text, 2)
	end
	local formatted = string.reverse((string.gsub(string.reverse(text), "(%d%d%d)", "%1,")))
	if string.sub(formatted, 1, 1) == "," then
		formatted = string.sub(formatted, 2)
	end
	return sign .. formatted
end

-- 1234 -> "$1,234", 2500000 -> "$2.5M"
function Util.formatMoney(n: number): string
	local abs = math.abs(n)
	if abs >= 1e12 then
		return string.format("$%.2fT", n / 1e12)
	elseif abs >= 1e9 then
		return string.format("$%.2fB", n / 1e9)
	elseif abs >= 1e6 then
		return string.format("$%.2fM", n / 1e6)
	end
	return "$" .. withCommas(n)
end

function Util.formatPrice(n: number): string
	if n <= 0 then
		return "FREE"
	end
	return Util.formatMoney(n)
end

function Util.multiplierFor(rebirths: number, rebirthBonus: number): number
	return 1 + rebirths * rebirthBonus
end

return Util
