--[[
	Quick checks that run outside of Roblox:

	    lune run test

	* every source file compiles
	* the shared Format / Formulas modules behave as expected
	* the config is consistent and every jump tier can actually be landed
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

local failures = 0
local passes = 0

local function check(condition, message)
	if condition then
		passes += 1
	else
		failures += 1
		print("FAIL: " .. message)
	end
end

local function equal(actual, expected, message)
	check(actual == expected, string.format("%s (expected %s, got %s)", message, tostring(expected), tostring(actual)))
end

-- Compile every source file -----------------------------------------------------------

local function eachSource(path, callback)
	for _, entry in fs.readDir(path) do
		local fullPath = path .. "/" .. entry
		if fs.isDir(fullPath) then
			eachSource(fullPath, callback)
		elseif string.find(entry, "%.luau$") then
			callback(fullPath)
		end
	end
end

eachSource("src", function(path)
	local ok, err = pcall(luau.compile, fs.readFile(path))
	check(ok, "compile " .. path .. ": " .. tostring(err))
end)

-- Load the shared modules ----------------------------------------------------------------

local modules = {}
local environment = {
	Enum = roblox.Enum,
	Vector2 = roblox.Vector2,
	Vector3 = roblox.Vector3,
	Color3 = roblox.Color3,
}
local sharedFolder = {}
environment.script = { Parent = sharedFolder }
environment.require = function(module)
	return modules[module] or error("unknown module")
end

local function load(name)
	local path = "src/shared/" .. name .. ".luau"
	local result = luau.load(fs.readFile(path), { debugName = path, environment = environment })()
	sharedFolder[name] = name
	modules[name] = result
	return result
end

local Config = load("Config")
local Format = load("Format")
local Formulas = load("Formulas")

-- Format --------------------------------------------------------------------------------------

equal(Format.commas(0), "0", "commas 0")
equal(Format.commas(999), "999", "commas 999")
equal(Format.commas(1234567), "1,234,567", "commas 1234567")
equal(Format.abbreviate(9999), "9,999", "abbreviate 9999")
equal(Format.abbreviate(12345), "12.3K", "abbreviate 12345")
equal(Format.abbreviate(250000), "250K", "abbreviate 250000")
equal(Format.abbreviate(1500000), "1.5M", "abbreviate 1.5M")
equal(Format.abbreviate(3000000000), "3B", "abbreviate 3B")
equal(Format.abbreviate(999999), "999K", "abbreviate never rounds up past a suffix")
equal(Format.multiplier(1), "x1", "multiplier 1")
equal(Format.multiplier(1.5), "x1.5", "multiplier 1.5")
equal(Format.multiplier(2.25), "x2.25", "multiplier 2.25")

-- Formulas -------------------------------------------------------------------------------------

local function profile(overrides)
	local base = {
		Snowflakes = 0,
		Rebirths = 0,
		SkateTier = 1,
		Upgrades = { Speed = 0, Jump = 0, Style = 0 },
		UnlockedRinks = { Pond = true },
	}
	for key, value in overrides or {} do
		base[key] = value
	end
	return base
end

local gravity = 196.2
local starter = profile()
local maxed = profile({
	SkateTier = #Config.Skates,
	Upgrades = { Speed = 25, Jump = 20, Style = 25 },
})

equal(Formulas.maxSpeed(starter), Config.Skates[1].MaxSpeed, "starter top speed")
equal(Formulas.jumpHeight(starter), Config.Skating.BaseJumpHeight, "starter jump height")
equal(Formulas.upgradeCost("Speed", 0), 150, "first Leg Power level price")
equal(Formulas.upgradeCost("Speed", 25), nil, "maxed upgrade has no price")
equal(Formulas.rebirthCost(0), Config.Rebirth.BaseCost, "first rebirth price")
equal(Formulas.rebirthMultiplier(profile({ Rebirths = 2 })), 2, "two rebirths double earnings")
check(Formulas.isRinkUnlocked(starter, "Pond"), "the pond is always open")
check(not Formulas.isRinkUnlocked(starter, "PineLake"), "Pine Lake starts locked")
check(
	Formulas.isRinkUnlocked(profile({ UnlockedRinks = { Pond = true, PineLake = true } }), "PineLake"),
	"Pine Lake unlocks"
)
equal(Formulas.comboMultiplier(1), 1, "no combo bonus on the first trick")
equal(Formulas.comboMultiplier(100), Config.Tricks.MaxComboMultiplier, "combo bonus is capped")
equal(Formulas.countRotations(math.pi * 2 * 0.69), 0, "69% of a turn isn't a rotation")
equal(Formulas.countRotations(math.pi * 2 * 0.71), 1, "71% of a turn counts")

-- What a skater can actually land, using the client's own spin maths.
local function landable(p)
	local airTime = Formulas.airTime(Formulas.jumpHeight(p), gravity)
	return Formulas.countRotations(airTime * Formulas.airSpinRate(Formulas.maxSpeed(p)))
end

equal(landable(starter), 1, "a new player can land a single")
equal(landable(maxed), #Config.Tricks.Rotations, "a maxed player can land the top jump")
check(Formulas.maxRotations(starter, gravity) >= landable(starter), "server allows what a starter can land")
check(Formulas.maxRotations(maxed, gravity) >= landable(maxed), "server allows what a maxed player can land")
check(Formulas.maxRotations(starter, gravity) < #Config.Tricks.Rotations, "server rejects a quint from a new player")

-- Config consistency -----------------------------------------------------------------------------

for index = 2, #Config.Skates do
	local previous, skate = Config.Skates[index - 1], Config.Skates[index]
	check(skate.Price > previous.Price, skate.Name .. " costs more than " .. previous.Name)
	check(skate.MaxSpeed > previous.MaxSpeed, skate.Name .. " is faster than " .. previous.Name)
	check(skate.EarnMultiplier > previous.EarnMultiplier, skate.Name .. " earns more than " .. previous.Name)
end

local seenRinks = {}
for _, rink in Config.Rinks do
	check(not seenRinks[rink.Id], "rink id " .. rink.Id .. " is unique")
	seenRinks[rink.Id] = true
end
equal(Config.Rinks[1].Price, 0, "the first rink is free")

-- Rinks (plus their boards, gates and lamps) must not overlap each other or the plaza.
local MARGIN = 12
local function rinkBounds(rink)
	local toLobby = Config.Lobby.Center - rink.Center
	local yaw = math.atan2(toLobby.X, toLobby.Z)
	local minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
	for _, corner in { { -1, -1 }, { -1, 1 }, { 1, -1 }, { 1, 1 } } do
		local localX, localZ = corner[1] * rink.Size.X / 2, corner[2] * rink.Size.Y / 2
		local x = rink.Center.X + localX * math.cos(yaw) + localZ * math.sin(yaw)
		local z = rink.Center.Z - localX * math.sin(yaw) + localZ * math.cos(yaw)
		minX, maxX = math.min(minX, x), math.max(maxX, x)
		minZ, maxZ = math.min(minZ, z), math.max(maxZ, z)
	end
	return minX - MARGIN, maxX + MARGIN, minZ - MARGIN, maxZ + MARGIN
end

for i, a in Config.Rinks do
	local aMinX, aMaxX, aMinZ, aMaxZ = rinkBounds(a)
	local lobby = Config.Lobby.Center
	local nearestX = math.clamp(lobby.X, aMinX, aMaxX)
	local nearestZ = math.clamp(lobby.Z, aMinZ, aMaxZ)
	local toPlaza = math.sqrt((nearestX - lobby.X) ^ 2 + (nearestZ - lobby.Z) ^ 2)
	check(toPlaza > Config.Lobby.PlazaRadius + 10, a.Name .. " is clear of the plaza")
	for j = i + 1, #Config.Rinks do
		local b = Config.Rinks[j]
		local bMinX, bMaxX, bMinZ, bMaxZ = rinkBounds(b)
		local overlaps = aMinX < bMaxX and bMinX < aMaxX and aMinZ < bMaxZ and bMinZ < aMaxZ
		check(not overlaps, a.Name .. " doesn't overlap " .. b.Name)
	end
end

print(string.format("%d checks passed, %d failed", passes, failures))
if failures > 0 then
	process.exit(1)
end
