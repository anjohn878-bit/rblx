--!nocheck
-- A tiny fake Roblox engine for running the game's scripts under Lune.
--
-- It uses Lune's real Instance implementation (so bad property names and
-- wrong value types error just like in Roblox) and fills in the engine
-- pieces Lune doesn't have: signals, a virtual-time task scheduler, tweens,
-- remotes, DataStores, players and a few Model helpers.

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")

local Instance = roblox.Instance
local Vector3 = roblox.Vector3
local CFrame = roblox.CFrame
local Enum = roblox.Enum

local Mock = {}

Mock.Errors = {}
Mock.Warnings = {}
Mock.Clock = 0
-- Lune stores number attributes as 32-bit floats (Roblox uses doubles), so
-- keep simulated unix times small enough to stay precise.
local EPOCH = 100000

------------------------------------------------------------------------------
-- Scheduler (virtual time)

local queue = {}

local function report(thread, err)
	local message = debug.traceback(thread, tostring(err))
	table.insert(Mock.Errors, message)
	print("[ERROR] " .. message)
end

local function resume(thread, ...)
	if coroutine.status(thread) ~= "suspended" then
		return
	end
	local ok, err = coroutine.resume(thread, ...)
	if not ok then
		report(thread, err)
	end
end

local function schedule(at, thread, ...)
	table.insert(queue, { At = at, Thread = thread, Args = table.pack(...) })
end

local task = {}
function task.spawn(fn, ...)
	local thread = type(fn) == "thread" and fn or coroutine.create(fn)
	resume(thread, ...)
	return thread
end
function task.defer(fn, ...)
	local thread = type(fn) == "thread" and fn or coroutine.create(fn)
	schedule(Mock.Clock, thread, ...)
	return thread
end
function task.delay(seconds, fn, ...)
	local thread = coroutine.create(fn)
	schedule(Mock.Clock + (seconds or 0), thread, ...)
	return thread
end
function task.wait(seconds)
	seconds = seconds or 0.03
	local thread = coroutine.running()
	schedule(Mock.Clock + seconds, thread, seconds)
	return coroutine.yield()
end
Mock.task = task

------------------------------------------------------------------------------
-- Signals

local Signal = {}
Signal.__index = Signal

function Signal.new()
	return setmetatable({ Handlers = {}, Waiting = {} }, Signal)
end

function Signal:Connect(fn)
	local handler = { Fn = fn, Connected = true }
	table.insert(self.Handlers, handler)
	return {
		Disconnect = function()
			handler.Connected = false
		end,
	}
end
Signal.connect = Signal.Connect

function Signal:Once(fn)
	local connection
	connection = self:Connect(function(...)
		connection.Disconnect()
		fn(...)
	end)
	return connection
end

function Signal:Wait()
	table.insert(self.Waiting, coroutine.running())
	return coroutine.yield()
end

function Signal:Fire(...)
	for _, handler in ipairs(table.clone(self.Handlers)) do
		if handler.Connected then
			task.spawn(handler.Fn, ...)
		end
	end
	local waiting = self.Waiting
	self.Waiting = {}
	for _, thread in ipairs(waiting) do
		resume(thread, ...)
	end
end
Mock.Signal = Signal

-- strong keys: keeps Lune's instance userdata alive so identity stays stable
local signals = {}
local function signalFor(object, name)
	local bucket = signals[object]
	if not bucket then
		bucket = {}
		signals[object] = bucket
	end
	local signal = bucket[name]
	if not signal then
		signal = Signal.new()
		bucket[name] = signal
	end
	return signal
end
Mock.SignalFor = signalFor

local function signalProperty(className, name)
	roblox.implementProperty(className, name, function(instance)
		return signalFor(instance, name)
	end)
end

------------------------------------------------------------------------------
-- Data types Lune doesn't provide

local TweenInfo = {}
function TweenInfo.new(time, style, direction, repeatCount, reverses, delayTime)
	return {
		Time = time or 1,
		EasingStyle = style,
		EasingDirection = direction,
		RepeatCount = repeatCount or 0,
		Reverses = reverses or false,
		DelayTime = delayTime or 0,
	}
end

local Random = {}
Random.__index = Random
function Random.new(seed)
	return setmetatable({ Seed = seed or 1 }, Random)
end
function Random:NextNumber(min, max)
	min, max = min or 0, max or 1
	return min + math.random() * (max - min)
end
function Random:NextInteger(min, max)
	return math.random(min, max)
end

local DateTime = {}
function DateTime.now()
	return {
		UnixTimestampMillis = math.floor((EPOCH + Mock.Clock) * 1000),
		UnixTimestamp = math.floor(EPOCH + Mock.Clock),
	}
end

------------------------------------------------------------------------------
-- DataModel

local game = Instance.new("DataModel")
local workspace = game:GetService("Workspace")
Mock.Game = game
Mock.Workspace = workspace

local camera = Instance.new("Camera")
camera.Parent = workspace

local function isBasePart(instance)
	return instance:IsA("BasePart")
end

-- Instance helpers ---------------------------------------------------------

roblox.implementMethod("Instance", "WaitForChild", function(instance, name, timeout)
	local child = instance:FindFirstChild(name)
	if child then
		return child
	end
	local deadline = Mock.Clock + (timeout or 10)
	while Mock.Clock < deadline do
		task.wait(0.1)
		child = instance:FindFirstChild(name)
		if child then
			return child
		end
	end
	if not timeout then
		error("Infinite yield on " .. instance:GetFullName() .. ":WaitForChild(" .. name .. ")")
	end
	return nil
end)

roblox.implementMethod("Instance", "GetDebugId", function(instance)
	return tostring(instance)
end)

signalProperty("Instance", "DescendantAdded")
signalProperty("Instance", "Destroying")
signalProperty("Instance", "ChildAdded")
signalProperty("Instance", "ChildRemoved")
signalProperty("Instance", "AttributeChanged")
signalProperty("TextBox", "FocusLost")
roblox.implementMethod("TextBox", "IsFocused", function()
	return false
end)

local function pivotOf(model)
	if model.PrimaryPart then
		return model.PrimaryPart.CFrame
	end
	for _, descendant in ipairs(model:GetDescendants()) do
		if isBasePart(descendant) then
			return descendant.CFrame
		end
	end
	return CFrame.new()
end

roblox.implementMethod("Model", "GetPivot", pivotOf)

roblox.implementMethod("Model", "PivotTo", function(model, target)
	local delta = target * pivotOf(model):Inverse()
	for _, descendant in ipairs(model:GetDescendants()) do
		if isBasePart(descendant) then
			descendant.CFrame = delta * descendant.CFrame
		end
	end
end)

roblox.implementMethod("Model", "GetBoundingBox", function(model)
	local pivot = pivotOf(model)
	local minV, maxV
	for _, descendant in ipairs(model:GetDescendants()) do
		if isBasePart(descendant) then
			local half = descendant.Size / 2
			for _, sx in ipairs({ -1, 1 }) do
				for _, sy in ipairs({ -1, 1 }) do
					for _, sz in ipairs({ -1, 1 }) do
						local corner = pivot:PointToObjectSpace(
							descendant.CFrame * Vector3.new(half.X * sx, half.Y * sy, half.Z * sz)
						)
						minV = minV and minV:Min(corner) or corner
						maxV = maxV and maxV:Max(corner) or corner
					end
				end
			end
		end
	end
	if not minV then
		return pivot, Vector3.zero
	end
	return pivot * CFrame.new((minV + maxV) / 2), maxV - minV
end)

-- Workspace -----------------------------------------------------------------

roblox.implementProperty("Workspace", "CurrentCamera", function()
	return camera
end)
roblox.implementMethod("Workspace", "GetServerTimeNow", function()
	return EPOCH + Mock.Clock
end)
-- no physics here: raycasts never hit, so code falls back to its defaults
roblox.implementMethod("Workspace", "Raycast", function()
	return nil
end)

local RaycastParams = {}
function RaycastParams.new()
	return { FilterDescendantsInstances = {} }
end

-- Services ------------------------------------------------------------------

roblox.implementMethod("DataModel", "BindToClose", function(_, fn)
	Mock.CloseCallbacks = Mock.CloseCallbacks or {}
	table.insert(Mock.CloseCallbacks, fn)
end)

local side = "server"
function Mock.SetSide(value)
	side = value
end

roblox.implementMethod("RunService", "IsServer", function()
	return side == "server"
end)
roblox.implementMethod("RunService", "IsClient", function()
	return side == "client"
end)
roblox.implementMethod("RunService", "IsStudio", function()
	return false
end)
signalProperty("RunService", "RenderStepped")
signalProperty("RunService", "Heartbeat")
signalProperty("RunService", "Stepped")

signalProperty("UserInputService", "InputBegan")
signalProperty("ProximityPromptService", "PromptShown")
signalProperty("ProximityPromptService", "PromptHidden")
roblox.implementMethod("StarterGui", "SetCoreGuiEnabled", function() end)

roblox.implementMethod("Debris", "AddItem", function(_, instance, lifetime)
	task.delay(lifetime or 10, function()
		instance:Destroy()
	end)
end)

-- CollectionService
roblox.implementMethod("CollectionService", "AddTag", function(service, instance, tag)
	instance:AddTag(tag)
	signalFor(service, "Added:" .. tag):Fire(instance)
end)
roblox.implementMethod("CollectionService", "HasTag", function(_, instance, tag)
	return instance:HasTag(tag)
end)
roblox.implementMethod("CollectionService", "GetTagged", function(_, tag)
	local found = {}
	for _, descendant in ipairs(game:GetDescendants()) do
		if descendant:HasTag(tag) then
			table.insert(found, descendant)
		end
	end
	return found
end)
roblox.implementMethod("CollectionService", "GetInstanceAddedSignal", function(service, tag)
	return signalFor(service, "Added:" .. tag)
end)
roblox.implementMethod("CollectionService", "GetInstanceRemovedSignal", function(service, tag)
	return signalFor(service, "Removed:" .. tag)
end)

-- TweenService: applies goals when the tween finishes.
Mock.ActiveTweens = 0
roblox.implementMethod("TweenService", "Create", function(_, instance, info, goals)
	for key, value in pairs(goals) do
		-- assigning the current value validates the property name and type
		instance[key] = instance[key]
		assert(typeof(instance[key]) == typeof(value), "Tween goal " .. key .. " has the wrong type")
	end
	local tween = { Completed = Signal.new(), PlaybackState = Enum.PlaybackState.Begin }
	function tween.Play(self)
		self.PlaybackState = Enum.PlaybackState.Playing
		Mock.ActiveTweens += 1
		task.delay(info.Time + info.DelayTime, function()
			if self.PlaybackState ~= Enum.PlaybackState.Playing then
				return
			end
			Mock.ActiveTweens -= 1
			if not info.Reverses then
				for key, value in pairs(goals) do
					instance[key] = value
				end
			end
			self.PlaybackState = Enum.PlaybackState.Completed
			self.Completed:Fire(Enum.PlaybackState.Completed)
		end)
	end
	function tween.Cancel(self)
		if self.PlaybackState == Enum.PlaybackState.Playing then
			Mock.ActiveTweens -= 1
			self.PlaybackState = Enum.PlaybackState.Cancelled
			self.Completed:Fire(Enum.PlaybackState.Cancelled)
		end
	end
	return tween
end)

-- DataStoreService: an in-memory store that survives "rejoins".
Mock.SavedData = {}
local function deepCopy(value)
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for k, v in pairs(value) do
		assert(type(k) == "string" or type(k) == "number", "DataStore keys must be strings or numbers")
		copy[k] = deepCopy(v)
	end
	return copy
end
roblox.implementMethod("DataStoreService", "GetDataStore", function(_, name)
	local store = Mock.SavedData[name] or {}
	Mock.SavedData[name] = store
	return {
		GetAsync = function(_, key)
			task.wait(0.1)
			return deepCopy(store[key])
		end,
		UpdateAsync = function(_, key, transform)
			task.wait(0.1)
			store[key] = deepCopy(transform(deepCopy(store[key])))
		end,
	}
end)

-- GUI buttons and prompts
for _, name in ipairs({
	"Activated",
	"MouseButton1Down",
	"MouseButton1Up",
	"MouseButton1Click",
	"MouseLeave",
	"MouseEnter",
}) do
	signalProperty("GuiButton", name)
end
signalProperty("ProximityPrompt", "Triggered")
signalProperty("ProximityPrompt", "PromptShown")
signalProperty("BindableEvent", "Event")
roblox.implementMethod("BindableEvent", "Fire", function(bindable, ...)
	signalFor(bindable, "Event"):Fire(...)
end)

-- Players and remotes ----------------------------------------------------------

local Players = game:GetService("Players")
signalProperty("Players", "PlayerAdded")
signalProperty("Players", "PlayerRemoving")
signalProperty("Player", "CharacterAdded")
roblox.implementMethod("Players", "GetPlayers", function(service)
	local list = {}
	for _, child in ipairs(service:GetChildren()) do
		if child:IsA("Player") then
			table.insert(list, child)
		end
	end
	return list
end)

roblox.implementMethod("Players", "GetPlayerByUserId", function(service, userId)
	for _, child in ipairs(service:GetChildren()) do
		if child:IsA("Player") and child.UserId == userId then
			return child
		end
	end
	return nil
end)

local localPlayer
Mock.LocalPlayer = function()
	return localPlayer
end

signalProperty("RemoteEvent", "OnServerEvent")
signalProperty("RemoteEvent", "OnClientEvent")
roblox.implementMethod("RemoteEvent", "FireClient", function(remote, player, ...)
	assert(typeof(player) == "Instance" and player:IsA("Player"), "FireClient needs a Player")
	Mock.RemoteLog = Mock.RemoteLog or {}
	table.insert(Mock.RemoteLog, { Remote = remote.Name, Player = player.Name, Args = table.pack(...) })
	if player == localPlayer then
		signalFor(remote, "OnClientEvent"):Fire(...)
	end
end)
roblox.implementMethod("RemoteEvent", "FireAllClients", function(remote, ...)
	if localPlayer then
		signalFor(remote, "OnClientEvent"):Fire(...)
	end
end)
roblox.implementMethod("RemoteEvent", "FireServer", function(remote, ...)
	signalFor(remote, "OnServerEvent"):Fire(localPlayer, ...)
end)

local callbacks = {}
roblox.implementProperty("RemoteFunction", "OnServerInvoke", function(remote)
	return callbacks[remote]
end, function(remote, fn)
	callbacks[remote] = fn
end)
roblox.implementMethod("RemoteFunction", "InvokeServer", function(remote, ...)
	local callback = callbacks[remote]
	assert(callback, "No OnServerInvoke for " .. remote.Name)
	return callback(localPlayer, ...)
end)

function Mock.AddPlayer(name, userId, isLocal)
	local player = Instance.new("Player")
	player.Name = name
	player.DisplayName = name
	player.UserId = userId
	local gui = Instance.new("PlayerGui")
	gui.Parent = player
	player.Parent = Players
	if isLocal then
		localPlayer = player
		pcall(function()
			Players.LocalPlayer = player
		end)
	end
	signalFor(Players, "PlayerAdded"):Fire(player)
	return player
end

function Mock.SpawnCharacter(player)
	local character = Instance.new("Model")
	character.Name = player.Name
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(2, 2, 1)
	root.CFrame = CFrame.new(0, 3, 0)
	root.Parent = character
	character.PrimaryPart = root
	character.Parent = workspace
	player.Character = character
	signalFor(player, "CharacterAdded"):Fire(character)
	return character
end

function Mock.RemovePlayer(player)
	signalFor(Players, "PlayerRemoving"):Fire(player)
	if player.Character then
		player.Character:Destroy()
	end
	player.Parent = nil
end

------------------------------------------------------------------------------
-- Loading scripts from src/ with Rojo naming

local SCRIPT_TYPES = {
	{ Suffix = ".server.lua", ClassName = "Script" },
	{ Suffix = ".client.lua", ClassName = "LocalScript" },
	{ Suffix = ".lua", ClassName = "ModuleScript" },
}

local function loadFolder(path, name, parent)
	local folder = Instance.new("Folder")
	folder.Name = name
	local entries = fs.readDir(path)
	table.sort(entries)
	for _, entry in ipairs(entries) do
		local entryPath = path .. "/" .. entry
		if fs.isDir(entryPath) then
			loadFolder(entryPath, entry, folder)
		else
			for _, scriptType in ipairs(SCRIPT_TYPES) do
				if entry:sub(-#scriptType.Suffix) == scriptType.Suffix then
					local script = Instance.new(scriptType.ClassName)
					script.Name = entry:sub(1, -#scriptType.Suffix - 1)
					script.Source = fs.readFile(entryPath)
					script.Parent = folder
					break
				end
			end
		end
	end
	folder.Parent = parent
	return folder
end
Mock.LoadFolder = loadFolder

local moduleCache = { server = {}, client = {} }

local function makeEnvironment(script, scriptSide)
	local env = {
		game = game,
		workspace = workspace,
		script = script,
		Instance = Instance,
		Vector3 = Vector3,
		Vector2 = roblox.Vector2,
		CFrame = CFrame,
		Color3 = roblox.Color3,
		UDim = roblox.UDim,
		UDim2 = roblox.UDim2,
		Enum = Enum,
		BrickColor = roblox.BrickColor,
		NumberSequence = roblox.NumberSequence,
		NumberRange = roblox.NumberRange,
		ColorSequence = roblox.ColorSequence,
		TweenInfo = TweenInfo,
		RaycastParams = RaycastParams,
		Random = Random,
		DateTime = DateTime,
		task = task,
		typeof = typeof,
		print = print,
		warn = function(...)
			local parts = table.pack(...)
			for i = 1, parts.n do
				parts[i] = tostring(parts[i])
			end
			local message = table.concat(parts, " ", 1, parts.n)
			table.insert(Mock.Warnings, message)
			print("[WARN] " .. message)
		end,
		os = {
			clock = function()
				return Mock.Clock
			end,
			time = function()
				return math.floor(EPOCH + Mock.Clock)
			end,
			date = os.date,
		},
		math = math,
		string = string,
		table = table,
		coroutine = coroutine,
		utf8 = utf8,
		bit32 = bit32,
		debug = debug,
		pairs = pairs,
		ipairs = ipairs,
		next = next,
		select = select,
		type = type,
		tostring = tostring,
		tonumber = tonumber,
		pcall = pcall,
		xpcall = xpcall,
		error = error,
		assert = assert,
		setmetatable = setmetatable,
		getmetatable = getmetatable,
		rawget = rawget,
		rawset = rawset,
		rawequal = rawequal,
		unpack = table.unpack,
	}
	env.require = function(module)
		local cache = moduleCache[scriptSide]
		if cache[module] == nil then
			assert(typeof(module) == "Instance" and module:IsA("ModuleScript"), "require expects a ModuleScript")
			local chunk = luau.load(module.Source, {
				debugName = module:GetFullName(),
				environment = makeEnvironment(module, scriptSide),
				injectGlobals = false,
			})
			local result = chunk()
			assert(result ~= nil, module:GetFullName() .. " did not return a value")
			cache[module] = result
		end
		return cache[module]
	end
	return env
end

-- Returns a module as already required by the given side (shares its cache).
function Mock.Require(module, scriptSide)
	return makeEnvironment(module, scriptSide).require(module)
end

-- Runs a Script / LocalScript in its own thread.
function Mock.RunScript(script, scriptSide)
	local chunk = luau.load(script.Source, {
		debugName = script:GetFullName(),
		environment = makeEnvironment(script, scriptSide),
		injectGlobals = false,
	})
	local previous = side
	side = scriptSide
	task.spawn(chunk)
	side = previous
end

------------------------------------------------------------------------------
-- Advancing time

function Mock.Advance(seconds, step)
	step = step or 0.1
	local target = Mock.Clock + seconds
	local RunService = game:GetService("RunService")
	while Mock.Clock < target - 1e-9 do
		local stepEnd = math.min(target, Mock.Clock + step)
		while true do
			local index, earliest
			for i, item in ipairs(queue) do
				if item.At <= stepEnd and (not earliest or item.At < earliest.At) then
					index, earliest = i, item
				end
			end
			if not earliest then
				break
			end
			table.remove(queue, index)
			Mock.Clock = math.max(Mock.Clock, earliest.At)
			resume(earliest.Thread, table.unpack(earliest.Args, 1, earliest.Args.n))
		end
		Mock.Clock = stepEnd
		signalFor(RunService, "Heartbeat"):Fire(step)
		signalFor(RunService, "RenderStepped"):Fire(step)
	end
end

return Mock
