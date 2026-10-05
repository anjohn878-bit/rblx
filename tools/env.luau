--[[
	A small Roblox-like environment for Lune, shared by the place build (tools/build.luau) and the
	tests (tests/). It lets us run the game's real ModuleScripts outside Roblox:

	  * Env.injectSources(dataModel, repoRoot)   copies src/ into the DataModel as Script / LocalScript /
	                                             ModuleScript instances, exactly where Rojo would put them.
	  * Env.new(dataModel, options)              returns a runtime whose :require() runs those scripts with
	                                             Roblox globals (Instance, Vector3, Enum, script, game, ...).

	Instances are Lune's real ones, so setting a property or enum that does not exist in Roblox's API
	raises an error here - that is the main thing the tests use it for.
	Signals / yielding methods do not exist in Lune; install the polyfills below or pass fakes.
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")
local task = require("@lune/task")

local Instance = roblox.Instance

local Env = {}
Env.roblox = roblox

-- Same mapping as default.project.json.
Env.MAPPING = {
	{ src = "src/shared", service = "ReplicatedStorage", path = { "Shared" } },
	{ src = "src/server", service = "ServerScriptService", path = { "Server" } },
	{ src = "src/client", service = "StarterPlayer", path = { "StarterPlayerScripts", "Client" } },
}

-- Source injection ---------------------------------------------------------------

local function parseFileName(entry: string): (string?, string?)
	local base = entry:match("^(.*)%.luau$") or entry:match("^(.*)%.lua$")
	if not base then
		return nil, nil
	end
	if base:match("%.server$") then
		return base:gsub("%.server$", ""), "Script"
	elseif base:match("%.client$") then
		return base:gsub("%.client$", ""), "LocalScript"
	end
	return base, "ModuleScript"
end

local function loadDirectory(dirPath: string, parent)
	local entries = fs.readDir(dirPath)
	table.sort(entries)
	for _, entry in entries do
		local full = dirPath .. "/" .. entry
		if fs.isDir(full) then
			local folder = Instance.new("Folder")
			folder.Name = entry
			folder.Parent = parent
			loadDirectory(full, folder)
		else
			local name, className = parseFileName(entry)
			if name then
				local script = Instance.new(className)
				script.Name = name
				script.Source = fs.readFile(full)
				script.Parent = parent
			end
		end
	end
end

-- Idempotent: replaces anything it injected on a previous run.
function Env.injectSources(dm, repoRoot: string)
	for _, mapping in Env.MAPPING do
		local container = dm:GetService(mapping.service)
		for i = 1, #mapping.path do
			local name = mapping.path[i]
			local isLast = i == #mapping.path
			local existing = container:FindFirstChild(name)
			if isLast and existing then
				existing:Destroy()
				existing = nil
			end
			if not existing then
				-- StarterPlayerScripts is a real class; everything else is a Folder.
				existing = Instance.new(name == "StarterPlayerScripts" and "StarterPlayerScripts" or "Folder")
				existing.Name = name
				existing.Parent = container
			end
			container = existing
		end
		loadDirectory(repoRoot .. "/" .. mapping.src, container)
	end
end

-- Polyfills for engine API Lune's Instance does not have -------------------------------

-- A tiny signal: enough for :Connect / :Once / :Wait-free tests, plus :Fire to drive handlers.
function Env.newSignal()
	local handlers = {}
	local signal = {}
	function signal:Connect(fn)
		local entry = { fn = fn, connected = true }
		table.insert(handlers, entry)
		return {
			Connected = true,
			Disconnect = function()
				entry.connected = false
			end,
		}
	end
	function signal:Once(fn)
		local connection
		connection = signal:Connect(function(...)
			connection:Disconnect()
			fn(...)
		end)
		return connection
	end
	function signal:Fire(...)
		for _, entry in table.clone(handlers) do
			if entry.connected then
				entry.fn(...)
			end
		end
	end
	function signal:HandlerCount()
		local n = 0
		for _, entry in handlers do
			if entry.connected then
				n += 1
			end
		end
		return n
	end
	return signal
end

local changedSignals = setmetatable({}, { __mode = "k" })

-- Fires the signal returned by instance:GetPropertyChangedSignal(property)
-- (or GetAttributeChangedSignal(name) when called with "attr:" .. name), if anyone asked for it.
function Env.fireChanged(instance, key: string)
	local signals = changedSignals[instance]
	if signals and signals[key] then
		signals[key]:Fire()
	end
end

local baseInstalled = false
local installedSignals = {}

-- Safe to call repeatedly: the base polyfills install once, and each (class, event) pair in signalMap
-- installs the first time it is asked for.
-- signalMap: { [className] = { "EventName", ... } } - events become per-instance fake signals.
function Env.installPolyfills(signalMap)
	if not baseInstalled then
		baseInstalled = true

		roblox.implementMethod("Instance", "WaitForChild", function(self, name)
			return self:FindFirstChild(name)
		end)
		roblox.implementMethod("Instance", "GetPropertyChangedSignal", function(self, property)
			changedSignals[self] = changedSignals[self] or {}
			changedSignals[self][property] = changedSignals[self][property] or Env.newSignal()
			return changedSignals[self][property]
		end)
		roblox.implementMethod("Instance", "GetAttributeChangedSignal", function(self, attribute)
			changedSignals[self] = changedSignals[self] or {}
			local key = "attr:" .. attribute
			changedSignals[self][key] = changedSignals[self][key] or Env.newSignal()
			return changedSignals[self][key]
		end)
	end

	for className, events in signalMap or {} do
		for _, eventName in events do
			local id = className .. "." .. eventName
			if not installedSignals[id] then
				installedSignals[id] = true
				local perInstance = setmetatable({}, { __mode = "k" })
				roblox.implementProperty(className, eventName, function(self)
					perInstance[self] = perInstance[self] or Env.newSignal()
					return perInstance[self]
				end, function()
					error(eventName .. " is read-only")
				end)
			end
		end
	end
end

-- Lune's CFrame.lookAt is wrong when looking straight down +Z / -Z (it returns a frame turned 180 degrees),
-- which real Roblox gets right. Everything else is Lune's own CFrame.
Env.CFrame = setmetatable({
	lookAt = function(at, target, up)
		up = up or roblox.Vector3.yAxis
		local look = (target - at).Unit
		local right = look:Cross(up).Unit
		local trueUp = right:Cross(look)
		return roblox.CFrame.fromMatrix(at, right, trueUp, -look)
	end,
}, { __index = roblox.CFrame })

-- Runtime ----------------------------------------------------------------------------

export type Options = {
	services: { [string]: any }?, -- fake services returned by game:GetService
	globals: { [string]: any }?, -- extra globals (e.g. workspace, TweenInfo)
}

function Env.new(dm, options: Options?)
	options = options or {}
	local services = options.services or {}

	local game = {
		GetService = function(_, name: string)
			return services[name] or dm:GetService(name)
		end,
		BindToClose = function() end,
		PlaceId = 0,
		JobId = "test",
	}

	local globals = {
		game = game,
		workspace = dm:GetService("Workspace"),
		task = task,
		typeof = typeof,
		-- Roblox datatypes Lune provides
		Instance = Instance,
		Enum = roblox.Enum,
		Vector3 = roblox.Vector3,
		Vector2 = roblox.Vector2,
		CFrame = Env.CFrame,
		Color3 = roblox.Color3,
		UDim = roblox.UDim,
		UDim2 = roblox.UDim2,
		Rect = roblox.Rect,
		NumberRange = roblox.NumberRange,
		NumberSequence = roblox.NumberSequence,
		NumberSequenceKeypoint = roblox.NumberSequenceKeypoint,
		ColorSequence = roblox.ColorSequence,
		ColorSequenceKeypoint = roblox.ColorSequenceKeypoint,
		PhysicalProperties = roblox.PhysicalProperties,
		Font = roblox.Font,
		BrickColor = roblox.BrickColor,
		Ray = roblox.Ray,
		Region3 = roblox.Region3,
	}
	for name, value in options.globals or {} do
		globals[name] = value
	end

	local runtime = { Game = game, Globals = globals }
	local cache = {}

	local function fullName(instance): string
		local parts = {}
		local current = instance
		while current and current.ClassName ~= "DataModel" do
			table.insert(parts, 1, current.Name)
			current = current.Parent
		end
		return table.concat(parts, ".")
	end

	local function compile(instance)
		local environment = {}
		for k, v in globals do
			environment[k] = v
		end
		environment.script = instance
		environment.require = function(target)
			return runtime:require(target)
		end
		return luau.load(instance.Source, { debugName = "=" .. fullName(instance), environment = environment })
	end

	function runtime:require(target)
		assert(typeof(target) == "Instance" and target.ClassName == "ModuleScript", "require expects a ModuleScript, got " .. typeof(target))
		if cache[target] ~= nil then
			return cache[target].value
		end
		local chunk = compile(target)
		cache[target] = { value = nil } -- guards against cycles
		local value = chunk()
		cache[target].value = value
		return value
	end

	-- Runs a Script / LocalScript body (not cached).
	function runtime:run(scriptInstance)
		return compile(scriptInstance)()
	end

	return runtime
end

return Env
