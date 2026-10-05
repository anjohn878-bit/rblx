--[[
	Minimal Roblox mock so pure game-logic modules can be unit tested outside
	Studio (run with any plain Luau runtime that provides __readfile and
	__loadstring; see tests/README.md).
]]

local ROOTS = {
	["ReplicatedStorage/Shared"] = "src/shared",
	["ServerScriptService/Server"] = "src/server",
}

local Harness = {}
local moduleCache = {}

local PathObject = {}

local function pathObject(path: string)
	return setmetatable({ __path = path }, PathObject)
end

local function parentPath(path: string): string
	return (path:match("^(.*)/[^/]+$")) or path
end

PathObject.__index = function(self, key)
	if key == "Parent" then
		return pathObject(parentPath(rawget(self, "__path")))
	elseif key == "WaitForChild" or key == "FindFirstChild" then
		return function(obj, name)
			return pathObject(rawget(obj, "__path") .. "/" .. name)
		end
	elseif key == "Name" then
		return (rawget(self, "__path"):match("([^/]+)$"))
	end
	return pathObject(rawget(self, "__path") .. "/" .. key)
end

local function resolveFile(path: string): string?
	for prefix, dir in ROOTS do
		if path == prefix or path:sub(1, #prefix + 1) == prefix .. "/" then
			local rest = path:sub(#prefix + 2)
			local base = if rest == "" then dir else dir .. "/" .. rest
			for _, candidate in { base .. ".luau", base .. "/init.luau" } do
				if __readfile(candidate) then
					return candidate
				end
			end
		end
	end
	return nil
end

-- Roblox-ish globals ---------------------------------------------------------------

local Color3Meta = {}
Color3Meta.__index = Color3Meta
function Color3Meta:Lerp(other, alpha)
	return setmetatable({ R = self.R + (other.R - self.R) * alpha, G = self.G + (other.G - self.G) * alpha, B = self.B + (other.B - self.B) * alpha }, Color3Meta)
end
local Color3 = {
	new = function(r, g, b)
		return setmetatable({ R = r or 0, G = g or 0, B = b or 0 }, Color3Meta)
	end,
	fromRGB = function(r, g, b)
		return setmetatable({ R = r / 255, G = g / 255, B = b / 255 }, Color3Meta)
	end,
}

local Enum = setmetatable({}, {
	__index = function(_, enumName)
		return setmetatable({}, {
			__index = function(_, item)
				return "Enum." .. enumName .. "." .. item
			end,
		})
	end,
})

local RandomMeta = {}
RandomMeta.__index = RandomMeta
local function lcg(self)
	self.state = (self.state * 1103515245 + 12345) % 2147483648
	return self.state / 2147483648
end
function RandomMeta:NextNumber(a, b)
	local x = lcg(self)
	if a and b then
		return a + (b - a) * x
	end
	return x
end
function RandomMeta:NextInteger(a, b)
	return a + math.floor(lcg(self) * (b - a + 1))
end
local Random = {
	new = function(seed)
		return setmetatable({ state = (seed or 1) % 2147483648 }, RandomMeta)
	end,
}

local services = setmetatable({}, {
	__index = function(_, name)
		return pathObject(name)
	end,
})

local game = {
	GetService = function(_, name)
		return services[name]
	end,
}

local function requireModule(target)
	local path = rawget(target, "__path")
	if moduleCache[path] ~= nil then
		return moduleCache[path]
	end
	local file = resolveFile(path)
	assert(file, "cannot resolve module " .. tostring(path))
	local source = __readfile(file)
	local fn, err = __loadstring(source, "@" .. file)
	assert(fn, err)
	local env = setmetatable({
		script = pathObject(path),
		game = game,
		Color3 = Color3,
		Enum = Enum,
		Random = Random,
		require = requireModule,
	}, { __index = _G })
	setfenv(fn, env)
	local result = fn()
	moduleCache[path] = result
	return result
end

Harness.Shared = pathObject("ReplicatedStorage/Shared")
Harness.Server = pathObject("ServerScriptService/Server")
Harness.require = requireModule
Harness.Random = Random

-- Tiny assertion helpers --------------------------------------------------------------

local failures = 0
local passes = 0

function Harness.eq(actual, expected, label)
	if actual == expected then
		passes += 1
	else
		failures += 1
		print(string.format("FAIL %s: expected %s, got %s", label, tostring(expected), tostring(actual)))
	end
end

function Harness.ok(condition, label)
	if condition then
		passes += 1
	else
		failures += 1
		print("FAIL " .. label)
	end
end

function Harness.summary(): boolean
	print(string.format("%d passed, %d failed", passes, failures))
	return failures == 0
end

return Harness
