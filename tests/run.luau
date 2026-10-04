--[[
	Unit tests for the pure shared modules (Progression, KickMath, Catalog, Config).
	Run with:  lune run tests/run.luau
	Roblox datatypes come from @lune/roblox; `script` is faked so modules can
	require their siblings exactly as they do in Roblox.
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")
local process = require("@lune/process")

local SHARED = "src/shared/"
local cache = {}

local env = setmetatable({
	Vector3 = roblox.Vector3,
	Vector2 = roblox.Vector2,
	CFrame = roblox.CFrame,
	Color3 = roblox.Color3,
	ColorSequence = roblox.ColorSequence,
	NumberSequence = roblox.NumberSequence,
	UDim = roblox.UDim,
	UDim2 = roblox.UDim2,
	Enum = roblox.Enum,
}, { __index = _G })

-- Deterministic Random shim (Lune has no Roblox Random)
local RandomShim = {}
RandomShim.__index = RandomShim
function RandomShim.new(seed)
	return setmetatable({ s = seed or 1 }, RandomShim)
end
function RandomShim:NextNumber(a, b)
	self.s = (self.s * 1103515245 + 12345) % 2147483648
	local r = self.s / 2147483648
	if a then
		return a + (b - a) * r
	end
	return r
end
function RandomShim:NextInteger(a, b)
	return math.floor(self:NextNumber(a, b + 1))
end
env.Random = RandomShim

local function loadShared(name)
	if cache[name] then
		return cache[name]
	end
	local source = fs.readFile(SHARED .. name .. ".luau")
	local parent = setmetatable({}, {
		__index = function(_, child)
			return { __module = child }
		end,
	})
	-- luau.load only sees raw fields of the environment, so copy them in
	local moduleEnv = {
		script = { Parent = parent },
		require = function(target)
			return loadShared(target.__module)
		end,
	}
	for k, v in env do
		moduleEnv[k] = v
	end
	for _, k in { "math", "string", "table", "pairs", "ipairs", "type", "tostring", "tonumber", "error", "assert", "pcall", "setmetatable", "getmetatable", "select", "next", "print" } do
		moduleEnv[k] = (_G :: any)[k] or (getfenv and getfenv(0)[k])
	end
	local fn = luau.load(luau.compile(source), { debugName = name, environment = moduleEnv })
	local result = fn()
	cache[name] = result
	return result
end

local passed, failed = 0, 0
local function test(name, fn)
	local ok, err = pcall(fn)
	if ok then
		passed += 1
		print("  ok   " .. name)
	else
		failed += 1
		print("  FAIL " .. name .. "\n       " .. tostring(err))
	end
end
local function eq(a, b, msg)
	if a ~= b then
		error(string.format("%s: expected %s, got %s", msg or "eq", tostring(b), tostring(a)), 2)
	end
end
local function near(a, b, tol, msg)
	if math.abs(a - b) > (tol or 1e-3) then
		error(string.format("%s: expected ~%s, got %s", msg or "near", tostring(b), tostring(a)), 2)
	end
end
local function truthy(v, msg)
	if not v then
		error(msg or "expected truthy", 2)
	end
end

local Config = loadShared("Config")
local Progression = loadShared("Progression")
local KickMath = loadShared("KickMath")
local Catalog = loadShared("Catalog")

print("Progression")
test("XP curve increases", function()
	eq(Progression.XPToNext(1), 100)
	truthy(Progression.XPToNext(10) > Progression.XPToNext(9))
end)
test("ApplyXP carries leftover and counts levels", function()
	local level, xp, gained = Progression.ApplyXP(1, 0, 100 + Progression.XPToNext(2) + 7)
	eq(level, 3, "level")
	eq(xp, 7, "xp")
	eq(gained, 2, "gained")
end)
test("ApplyXP ignores negative XP", function()
	local level, xp, gained = Progression.ApplyXP(4, 50, -500)
	eq(level, 4); eq(xp, 50); eq(gained, 0)
end)
test("ApplyXP caps at max level", function()
	local level, _, _ = Progression.ApplyXP(1, 0, 1e12)
	eq(level, Progression.MaxLevel)
end)
test("titles by level", function()
	eq(Progression.GetTitle(1), "Fresh Laces")
	eq(Progression.GetTitle(7), "Block Baller")
	eq(Progression.GetTitle(30), "Concrete King")
	eq(Progression.GetTitle(49), "Concrete King")
end)
test("reputation tiers", function()
	local i, name, nextMin = Progression.GetReputationTier(0)
	eq(i, 1); eq(name, "Unknown"); eq(nextMin, 100)
	i, name = Progression.GetReputationTier(300)
	eq(name, "Regular")
	local _, legend, none = Progression.GetReputationTier(99999)
	eq(legend, "Legend"); eq(none, nil)
	eq(Progression.TierIndexByName("Star"), 5)
end)
test("match rewards: win beats loss, caps apply", function()
	local win = Progression.ComputeMatchRewards({ Goals = 2, Assists = 1, Passes = 10 }, "Win")
	local loss = Progression.ComputeMatchRewards({ Goals = 2, Assists = 1, Passes = 10 }, "Loss")
	truthy(win.XP > loss.XP and win.Kicks > loss.Kicks and win.Reputation > loss.Reputation)
	eq(loss.XP, 60 + 60 + 20 + 30)
	local huge = Progression.ComputeMatchRewards({ Goals = 100, Assists = 100, Passes = 1000, Tackles = 1000 }, "Win")
	eq(huge.XP, Config.Rewards.XP.CapPerMatch)
	eq(huge.Kicks, Config.Rewards.Kicks.CapPerMatch)
end)

print("KickMath")
local V3 = roblox.Vector3
local function flatLen(v) return math.sqrt(v.X * v.X + v.Z * v.Z) end
local function base(kind, extra)
	local p = { Kind = kind, Origin = V3.new(0, 1.1, 0), Direction = V3.new(1, 0, 0), Power = 0.5,
		Passing = 0.5, Shooting = 0.5, Mates = {}, Gravity = 196.2, Random = RandomShim.new(7) }
	for k, v in extra or {} do p[k] = v end
	return p
end
test("pass targets the teammate in the aim cone", function()
	local mates = { { Position = V3.new(30, 3, 4), Velocity = V3.new(0, 0, 0), Id = "a" },
		{ Position = V3.new(-30, 3, 0), Velocity = V3.new(0, 0, 0), Id = "behind" } }
	local v, target = KickMath.Compute(base("Pass", { Mates = mates }))
	eq(target and target.Id, "a", "target")
	truthy(v.X > 0, "goes forward")
	truthy(v.X >= Config.Kick.PassMinSpeed * 0.9 and flatLen(v) <= Config.Kick.PassMaxSpeed + 1, "speed in range")
end)
test("pass ignores teammates outside the cone", function()
	local mates = { { Position = V3.new(0, 3, 30), Velocity = V3.new(0, 0, 0), Id = "side" } }
	local _, target = KickMath.Compute(base("Pass", { Mates = mates }))
	eq(target, nil)
end)
test("through ball leads a running teammate", function()
	local mate = { Position = V3.new(30, 3, 0), Velocity = V3.new(0, 0, 20), Id = "run" }
	local v = KickMath.Compute(base("Through", { Mates = { mate }, Passing = 1 }))
	truthy(v.Z > 1, "aimed ahead of runner (z>0), got " .. tostring(v.Z))
end)
test("lob lands near the requested distance", function()
	local v = KickMath.Compute(base("Lob", { Power = 0.5, Passing = 1 }))
	local g = KickMath.EffectiveGravity(196.2)
	local t = 2 * v.Y / g
	local range = flatLen(v) * t
	near(range, 18 + 0.5 * Config.Kick.LobMaxRange, 1, "range")
	near(t, Config.Kick.LobFlightTime, 0.01, "flight time")
end)
test("shot power scales speed and lift", function()
	local soft = KickMath.Compute(base("Shot", { Power = 0 }))
	local hard = KickMath.Compute(base("Shot", { Power = 1 }))
	truthy(flatLen(hard) > flatLen(soft), "faster")
	truthy(hard.Y > soft.Y, "higher")
	truthy(flatLen(hard) <= Config.Kick.ShotMaxSpeed + 1e-6, "under max speed")
end)
test("shot assist bends toward the goal", function()
	local p = base("Shot", { Direction = V3.new(1, 0, 0.5), GoalCenter = V3.new(50, 4, 0), GoalWidth = 16, Shooting = 1 })
	local v = KickMath.Compute(p)
	local angleRaw = math.deg(math.atan2(0.5, 1))
	local angleShot = math.deg(math.atan2(v.Z, v.X))
	truthy(math.abs(angleShot) < angleRaw, "assisted angle " .. angleShot .. " < raw " .. angleRaw)
end)
test("hard shot from mid range can clear the bar, soft shot stays under", function()
	local g = KickMath.EffectiveGravity(196.2)
	local function heightAt(v, dist)
		local t = dist / flatLen(v)
		return 1.1 + v.Y * t - 0.5 * g * t * t
	end
	local hard = KickMath.Compute(base("Shot", { Power = 1 }))
	local mid = KickMath.Compute(base("Shot", { Power = 0.5 }))
	truthy(heightAt(hard, 45) > 8, "full power from 45 studs flies over: " .. heightAt(hard, 45))
	truthy(heightAt(mid, 25) < 8, "half power from 25 studs on target: " .. heightAt(mid, 25))
end)
test("unknown kick kind errors", function()
	truthy(not pcall(KickMath.Compute, base("Banana")))
end)
test("tackle chance bounded and attribute sensitive", function()
	truthy(KickMath.TackleChance(1, 0) > KickMath.TackleChance(0, 1))
	truthy(KickMath.TackleChance(1, 0) <= 0.92 and KickMath.TackleChance(0, 1) >= 0.2)
end)
test("first touch is clean on soft balls", function()
	eq(KickMath.FirstTouchChance(0, 30), 1)
	truthy(KickMath.FirstTouchChance(1, 110) > KickMath.FirstTouchChance(0, 110))
end)

print("Catalog")
test("every category has exactly one default", function()
	for _, cat in Catalog.Categories do
		local n = 0
		for _, item in Catalog.ByCategory[cat] do
			if item.Default then n += 1 end
			eq(item.Category, cat)
		end
		eq(n, 1, cat .. " defaults")
	end
end)
test("required tiers exist and ids are unique", function()
	local seen = {}
	for id, item in Catalog.Items do
		truthy(not seen[id]); seen[id] = true
		if item.RequiredTier then
			truthy(Progression.TierIndexByName(item.RequiredTier) > 1 or item.RequiredTier == "Unknown", "tier " .. item.RequiredTier)
		end
		truthy(item.Price >= 0)
	end
	local eqp = Catalog.DefaultEquipped()
	local inv = Catalog.DefaultInventory()
	for _, id in eqp do truthy(inv[id], "default equipped owned") end
end)

print("Config")
test("controls all have inputs", function()
	for name, b in Config.Controls do
		truthy(#b.Keyboard > 0 and #b.Gamepad > 0, name)
	end
end)
test("pitch geometry is sane", function()
	for _, p in Config.Pitches do
		truthy(p.GoalWidth < p.Width and p.GoalHeight < p.WallHeight)
	end
end)

print(string.format("\n%d passed, %d failed", passed, failed))
if failed > 0 then
	process.exit(1)
end
