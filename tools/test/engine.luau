-- A tiny fake Roblox engine for smoke-testing the game's scripts with Lune.
-- Virtual clock + scheduler, signals, humanoid walking, DataStore, module loader.
-- Only the parts of the Roblox API that the game uses are faked.

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")

local Instance = roblox.Instance
local Vector3 = roblox.Vector3
local CFrame = roblox.CFrame

local Engine = {}
Engine.now = 0
Engine.warnings = {}
Engine.errors = {}
Engine.firedClient = {}
Engine.firedAll = {}
Engine.teleports = 0
Engine.collisions = {}
Engine.obstacles = {} -- list of {cf, size, name}
Engine.R15 = false

----------------------------------------------------------------------------
-- Scheduler
----------------------------------------------------------------------------
local queue = {} -- {time, seq, thread, args}
local seq = 0

local function schedule(at, thread, ...)
	seq += 1
	table.insert(queue, { time = at, seq = seq, thread = thread, args = table.pack(...) })
end

local function resume(thread, ...)
	local ok, err = coroutine.resume(thread, ...)
	if not ok then
		table.insert(Engine.errors, tostring(err) .. "\n" .. debug.traceback(thread))
		print("[ERROR] " .. tostring(err))
		print(debug.traceback(thread))
	end
end

local task = {}
function task.spawn(f, ...)
	local thread = if type(f) == "thread" then f else coroutine.create(f)
	resume(thread, ...)
	return thread
end
function task.defer(f, ...)
	local thread = if type(f) == "thread" then f else coroutine.create(f)
	schedule(Engine.now, thread, ...)
	return thread
end
function task.delay(t, f, ...)
	local thread = if type(f) == "thread" then f else coroutine.create(f)
	schedule(Engine.now + (t or 0), thread, ...)
	return thread
end
function task.wait(t)
	local thread = coroutine.running()
	local started = Engine.now
	schedule(Engine.now + math.max(t or 0.03, 0.03), thread)
	coroutine.yield()
	return Engine.now - started
end
function task.cancel() end
Engine.task = task

local physicsHooks = {}
function Engine.onStep(fn)
	table.insert(physicsHooks, fn)
end

-- Runs the world forward by `seconds` of game time.
function Engine.run(seconds)
	local stopAt = Engine.now + seconds
	local nextStep = Engine.now
	while true do
		table.sort(queue, function(a, b)
			if a.time == b.time then
				return a.seq < b.seq
			end
			return a.time < b.time
		end)
		local item = queue[1]
		local nextTime = if item then item.time else math.huge
		if nextStep <= nextTime and nextStep <= stopAt then
			Engine.now = nextStep
			for _, hook in physicsHooks do
				hook(1 / 20)
			end
			nextStep += 1 / 20
		elseif item and item.time <= stopAt then
			table.remove(queue, 1)
			Engine.now = math.max(Engine.now, item.time)
			resume(item.thread, table.unpack(item.args, 1, item.args.n))
		else
			Engine.now = stopAt
			break
		end
	end
end

----------------------------------------------------------------------------
-- Signals
----------------------------------------------------------------------------
local Signal = {}
Signal.__index = Signal
function Signal.new()
	return setmetatable({ handlers = {}, waiting = {} }, Signal)
end
function Signal:Connect(fn)
	local handler = { fn = fn, connected = true }
	table.insert(self.handlers, handler)
	local connection = { Connected = true }
	function connection.Disconnect()
		handler.connected = false
		connection.Connected = false
	end
	return connection
end
function Signal:Once(fn)
	local connection
	connection = self:Connect(function(...)
		connection.Disconnect()
		fn(...)
	end)
	return connection
end
function Signal:Wait()
	table.insert(self.waiting, coroutine.running())
	return coroutine.yield()
end
function Signal:Fire(...)
	for _, handler in table.clone(self.handlers) do
		if handler.connected then
			task.spawn(handler.fn, ...)
		end
	end
	local waiting = self.waiting
	self.waiting = {}
	for _, thread in waiting do
		task.spawn(thread, ...)
	end
end
Engine.Signal = Signal

local signals = {}
local function signalFor(instance, name)
	signals[instance] = signals[instance] or {}
	local s = signals[instance][name]
	if not s then
		s = Signal.new()
		signals[instance][name] = s
	end
	return s
end
Engine.signalFor = signalFor

for _, pair in {
	{ "ProximityPrompt", "Triggered" },
	{ "Humanoid", "Running" },
	{ "Humanoid", "MoveToFinished" },
	{ "Players", "PlayerAdded" },
	{ "Players", "PlayerRemoving" },
	{ "Player", "CharacterAdded" },
	{ "RemoteEvent", "OnServerEvent" },
	{ "RemoteEvent", "OnClientEvent" },
	{ "Instance", "DescendantAdded" },
	{ "Instance", "ChildAdded" },
	{ "IntValue", "Changed" },
	{ "GuiButton", "Activated" },
	{ "RunService", "RenderStepped" },
	{ "RunService", "Heartbeat" },
} do
	roblox.implementProperty(pair[1], pair[2], function(self)
		return signalFor(self, pair[2])
	end)
end
roblox.implementMethod("Instance", "GetPropertyChangedSignal", function(self, prop)
	return signalFor(self, "Changed:" .. prop)
end)
roblox.implementMethod("Instance", "GetAttributeChangedSignal", function(self, prop)
	return signalFor(self, "Attr:" .. prop)
end)
roblox.implementMethod("Instance", "WaitForChild", function(self, name, timeout)
	local child = self:FindFirstChild(name)
	if not child and timeout == nil then
		error("WaitForChild would wait forever for " .. self:GetFullName() .. "." .. name)
	end
	return child
end)

----------------------------------------------------------------------------
-- Parts, models, humanoids
----------------------------------------------------------------------------
local function syncPosition(part)
	part.Position = part.CFrame.Position
end

local function modelPivot(model)
	if model.PrimaryPart then
		return model.PrimaryPart.CFrame
	end
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			return d.CFrame
		end
	end
	return CFrame.new()
end

roblox.implementMethod("Model", "GetPivot", function(self)
	return modelPivot(self)
end)
roblox.implementMethod("Model", "PivotTo", function(self, target)
	local current = modelPivot(self)
	local delta = target * current:Inverse()
	for _, d in self:GetDescendants() do
		if d:IsA("BasePart") then
			d.CFrame = delta * d.CFrame
			syncPosition(d)
		end
	end
end)
roblox.implementMethod("BasePart", "SetNetworkOwner", function(self) end)
roblox.implementMethod("Humanoid", "SetStateEnabled", function(self) end)

local moving = {} -- humanoid -> {target, started}
roblox.implementMethod("Humanoid", "MoveTo", function(self, target)
	moving[self] = { target = target, started = Engine.now }
end)

local trackMeta = {}
trackMeta.__index = trackMeta
function trackMeta:Play() self.IsPlaying = true end
function trackMeta:Stop() self.IsPlaying = false end
roblox.implementMethod("Animator", "LoadAnimation", function(self, animation)
	assert(animation:IsA("Animation"), "LoadAnimation needs an Animation")
	assert(string.find(animation.AnimationId, "rbxassetid://"), "bad AnimationId")
	return setmetatable({ Looped = false, IsPlaying = false }, trackMeta)
end)

local function overlapsObstacle(position, radius)
	for _, o in Engine.obstacles do
		if o.part.Parent then
			local localP = o.part.CFrame:PointToObjectSpace(position)
			local half = o.part.Size / 2
			if math.abs(localP.X) < half.X + radius and math.abs(localP.Z) < half.Z + radius and math.abs(localP.Y) < half.Y + 2 then
				return o
			end
		end
	end
	return nil
end

local lastRoot = {}
Engine.hops = {}
Engine.onStep(function(dt)
	-- detect shoppers being "hopped" because they got stuck
	for _, d in Engine.game:GetService("Workspace"):GetDescendants() do
		if d.Name == "HumanoidRootPart" and d.Parent and d.Parent.Name == "Shopper" then
			local pos = d.CFrame.Position
			local last = lastRoot[d]
			if last and (pos - last).Magnitude > 3 then
				table.insert(Engine.hops, pos)
			end
			lastRoot[d] = pos
		end
	end
end)
Engine.onStep(function(dt)
	for humanoid, move in moving do
		local model = humanoid.Parent
		if not model or not model.Parent then
			moving[humanoid] = nil
			continue
		end
		local root = model:FindFirstChild("HumanoidRootPart")
		if not root then
			continue
		end
		local position = root.CFrame.Position
		local flat = Vector3.new(move.target.X - position.X, 0, move.target.Z - position.Z)
		local distance = flat.Magnitude
		if distance < 0.3 then
			moving[humanoid] = nil
			signalFor(humanoid, "MoveToFinished"):Fire(true)
			signalFor(humanoid, "Running"):Fire(0)
		elseif Engine.now - move.started > 8 then
			moving[humanoid] = nil
			signalFor(humanoid, "MoveToFinished"):Fire(false)
		else
			if not move.running then
				move.running = true
				signalFor(humanoid, "Running"):Fire(humanoid.WalkSpeed)
			end
			local step = math.min(distance, humanoid.WalkSpeed * dt)
			local newPos = position + flat.Unit * step
			local hit = overlapsObstacle(newPos + Vector3.new(0, 0.5, 0), 0.8)
			if hit and not move.reported then
				move.reported = true
				local lp = hit.plotCf:PointToObjectSpace(newPos)
				table.insert(Engine.collisions, string.format("%s at plot (%.1f, %.1f) walking to (%.1f, %.1f) bumped into %s", model.Name, lp.X, lp.Z, hit.plotCf:PointToObjectSpace(move.target).X, hit.plotCf:PointToObjectSpace(move.target).Z, hit.name))
			end
			model:PivotTo(CFrame.lookAt(newPos, newPos + flat.Unit))
		end
	end
end)

----------------------------------------------------------------------------
-- Services
----------------------------------------------------------------------------
Engine.game = Instance.new("DataModel")
local game = Engine.game
local workspace = game:GetService("Workspace")
local camera = Instance.new("Camera")
camera.Parent = workspace
workspace.CurrentCamera = camera
pcall(function()
	camera.ViewportSize = roblox.Vector2.new(1280, 720)
end)
for _, name in { "ReplicatedStorage", "ServerScriptService", "StarterPlayer", "Players", "Lighting", "SoundService", "TweenService", "CollectionService", "PhysicsService", "DataStoreService", "RunService" } do
	game:GetService(name)
end

local closeHandlers = {}
roblox.implementMethod("DataModel", "BindToClose", function(self, fn)
	table.insert(closeHandlers, fn)
end)
Engine.closeHandlers = closeHandlers

roblox.implementMethod("PhysicsService", "RegisterCollisionGroup", function() end)
roblox.implementMethod("PhysicsService", "CollisionGroupSetCollidable", function() end)

local tagged = {}
roblox.implementMethod("CollectionService", "AddTag", function(self, instance, tag)
	instance:AddTag(tag)
	tagged[tag] = tagged[tag] or {}
	table.insert(tagged[tag], instance)
	signalFor(self, "Added:" .. tag):Fire(instance)
end)
roblox.implementMethod("CollectionService", "GetTagged", function(self, tag)
	local list = {}
	for _, instance in game:GetService("Workspace"):GetDescendants() do
		if instance:HasTag(tag) then
			table.insert(list, instance)
		end
	end
	return list
end)
roblox.implementMethod("CollectionService", "GetInstanceAddedSignal", function(self, tag)
	return signalFor(self, "Added:" .. tag)
end)

roblox.implementMethod("TweenService", "Create", function(self, instance, info, props)
	assert(type(info) == "table" and info.__tweenInfo, "TweenService:Create needs TweenInfo")
	for key, _ in props do
		local _ = instance[key] -- property must exist
	end
	return {
		Play = function()
			for key, value in props do
				instance[key] = value
				if key == "CFrame" then
					syncPosition(instance)
				end
			end
		end,
		Cancel = function() end,
	}
end)

roblox.implementMethod("SoundService", "PlayLocalSound", function(self, sound)
	assert(sound:IsA("Sound"))
end)

-- RemoteEvents
roblox.implementMethod("RemoteEvent", "FireClient", function(self, player, ...)
	assert(player:IsA("Player"), "FireClient needs a player")
	table.insert(Engine.firedClient, { self.Name, player.Name, ... })
	signalFor(self, "OnClientEvent"):Fire(...)
end)
roblox.implementMethod("RemoteEvent", "FireAllClients", function(self, ...)
	table.insert(Engine.firedAll, { self.Name, ... })
	signalFor(self, "OnClientEvent"):Fire(...)
end)
roblox.implementMethod("RemoteEvent", "FireServer", function(self, ...)
	signalFor(self, "OnServerEvent"):Fire(Engine.localPlayer, ...)
end)

-- Players
local players = game:GetService("Players")
roblox.implementMethod("Players", "GetPlayers", function(self)
	local list = {}
	for _, child in self:GetChildren() do
		if child:IsA("Player") then
			table.insert(list, child)
		end
	end
	return list
end)

local function fakeR15()
	local model = Instance.new("Model")
	local function part(name, size, y)
		local p = Instance.new("MeshPart")
		p.Name = name
		p.Size = size
		p.CFrame = CFrame.new(0, y, 0)
		syncPosition(p)
		p.Parent = model
		return p
	end
	part("HumanoidRootPart", Vector3.new(2, 2, 1), 3).Transparency = 1
	part("Head", Vector3.new(1.2, 1.2, 1.2), 4.6)
	for _, n in { "UpperTorso", "LowerTorso", "LeftUpperArm", "RightUpperArm", "LeftLowerArm", "RightLowerArm", "LeftHand", "RightHand", "LeftUpperLeg", "RightUpperLeg", "LeftLowerLeg", "RightLowerLeg", "LeftFoot", "RightFoot" } do
		part(n, Vector3.new(1, 1, 1), 2)
	end
	local humanoid = Instance.new("Humanoid")
	humanoid.RigType = roblox.Enum.HumanoidRigType.R15
	humanoid.HipHeight = 2
	humanoid.Parent = model
	Instance.new("BodyColors").Parent = model
	local animate = Instance.new("LocalScript")
	animate.Name = "Animate"
	animate.Parent = model
	return model
end

roblox.implementMethod("Players", "CreateHumanoidModelFromDescription", function(self, description, rigType)
	assert(description:IsA("HumanoidDescription"))
	assert(rigType == roblox.Enum.HumanoidRigType.R15)
	task.wait(0.5)
	if not Engine.R15 then
		error("HTTP 403 (avatar loading disabled in test)")
	end
	return fakeR15()
end)

function Engine.addPlayer(userId, name)
	local player = Instance.new("Player")
	player.Name = name
	player.DisplayName = name
	player.UserId = userId
	local playerGui = Instance.new("PlayerGui")
	playerGui.Name = "PlayerGui"
	playerGui.Parent = player
	player.Parent = players
	signalFor(players, "PlayerAdded"):Fire(player)
	return player
end

function Engine.spawnCharacter(player)
	local model = Instance.new("Model")
	model.Name = player.Name
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(2, 2, 1)
	root.CFrame = CFrame.new(0, 3, 0)
	syncPosition(root)
	root.Parent = model
	model.PrimaryPart = root
	local humanoid = Instance.new("Humanoid")
	humanoid.Parent = model
	model.Parent = workspace
	player.Character = model
	signalFor(player, "CharacterAdded"):Fire(model)
	return model
end

function Engine.removePlayer(player)
	signalFor(players, "PlayerRemoving"):Fire(player)
	player.Parent = nil
end

-- DataStore
Engine.saved = {}
Engine.dataStoreMode = "ok" -- "ok" | "studio" | "flaky"
local store = {}
function store:GetAsync(key)
	task.wait(0.1)
	if Engine.dataStoreMode == "studio" then
		error("StudioAccessToApisNotAllowed: Studio access to APIs is not allowed.")
	end
	return Engine.saved[key]
end
function store:UpdateAsync(key, fn)
	task.wait(0.1)
	if Engine.dataStoreMode == "studio" then
		error("StudioAccessToApisNotAllowed")
	end
	local value = fn(Engine.saved[key])
	Engine.saved[key] = value
	return value
end
roblox.implementMethod("DataStoreService", "GetDataStore", function(self, name)
	assert(type(name) == "string")
	return store
end)

----------------------------------------------------------------------------
-- Module loading
----------------------------------------------------------------------------
local TweenInfo = {
	new = function(...)
		return { __tweenInfo = true, ... }
	end,
}

local paths = {} -- instance -> file path
local sources = {} -- file path -> source
local cache = {}

local envBase
local function makeEnv(scriptInstance)
	local env = {}
	for key, value in envBase do
		env[key] = value
	end
	env.script = scriptInstance
	return env
end

local function load(instance)
	local path = paths[instance]
	assert(path, "no source for " .. instance:GetFullName())
	-- sources are read up front: Lune's fs calls yield to Lune's own scheduler
	local source = sources[path]
	local chunk = luau.load(source, { debugName = path, environment = makeEnv(instance) })
	return chunk
end

local function requireModule(instance)
	assert(typeof(instance) == "Instance" and instance:IsA("ModuleScript"), "require needs a ModuleScript")
	if cache[instance] == nil then
		cache[instance] = load(instance)()
	end
	return cache[instance]
end

-- Lune stores Part.Position separately from CFrame; give it a value so reads work
local FakeInstance = {
	new = function(className, parent)
		local instance = Instance.new(className)
		if instance:IsA("BasePart") then
			instance.Position = instance.CFrame.Position
		end
		if parent then
			instance.Parent = parent
		end
		return instance
	end,
}
local syncTimer = 0
Engine.onStep(function(dt)
	syncTimer += dt
	if syncTimer >= 2 then
		syncTimer = 0
		for _, d in workspace:GetDescendants() do
			if d:IsA("BasePart") then
				d.Position = d.CFrame.Position
			end
		end
	end
end)

local realOs = os
envBase = setmetatable({
	game = game,
	workspace = workspace,
	require = requireModule,
	Enum = roblox.Enum,
	Instance = FakeInstance,
	Vector3 = Vector3,
	Vector2 = roblox.Vector2,
	CFrame = CFrame,
	Color3 = roblox.Color3,
	UDim = roblox.UDim,
	UDim2 = roblox.UDim2,
	ColorSequence = roblox.ColorSequence,
	NumberSequence = roblox.NumberSequence,
	NumberRange = roblox.NumberRange,
	TweenInfo = TweenInfo,
	task = task,
	os = setmetatable({ clock = function() return Engine.now end, time = function() return Engine.now end }, { __index = realOs }),
	tick = function() return Engine.now end,
	warn = function(...)
		local parts = {}
		for i = 1, select("#", ...) do
			table.insert(parts, tostring((select(i, ...))))
		end
		local message = table.concat(parts, " ")
		table.insert(Engine.warnings, message)
		print("[WARN] " .. message)
	end,
}, { __index = _G })

-- Builds the Rojo tree and returns the script instances to run.
function Engine.mount(root)
	local function scriptFor(path, name)
		local class = "ModuleScript"
		if string.find(path, "%.server%.lua$") then
			class = "Script"
		elseif string.find(path, "%.client%.lua$") then
			class = "LocalScript"
		end
		local s = Instance.new(class)
		s.Name = name
		paths[s] = path
		sources[path] = fs.readFile(path)
		return s
	end
	local function mountDir(dir, name)
		local initPath = nil
		for _, candidate in { "init.server.lua", "init.client.lua", "init.lua" } do
			if fs.isFile(dir .. "/" .. candidate) then
				initPath = dir .. "/" .. candidate
			end
		end
		local node = if initPath then scriptFor(initPath, name) else Instance.new("Folder")
		node.Name = name
		local entries = fs.readDir(dir)
		table.sort(entries)
		for _, entry in entries do
			local full = dir .. "/" .. entry
			if string.sub(entry, 1, 5) == "init." then
				continue
			end
			if fs.isDir(full) then
				mountDir(full, entry).Parent = node
			elseif string.find(entry, "%.lua$") then
				scriptFor(full, (string.gsub(entry, "%..*$", ""))).Parent = node
			end
		end
		return node
	end

	mountDir(root .. "/src/ReplicatedStorage/DressStore", "DressStore").Parent = game:GetService("ReplicatedStorage")
	local server = mountDir(root .. "/src/ServerScriptService/DressStoreServer", "DressStoreServer")
	server.Parent = game:GetService("ServerScriptService")
	local starterScripts = Instance.new("StarterPlayerScripts")
	starterScripts.Parent = game:GetService("StarterPlayer")
	local client = scriptFor(root .. "/src/StarterPlayer/StarterPlayerScripts/DressStoreClient.client.lua", "DressStoreClient")
	client.Parent = starterScripts
	return server, client
end

function Engine.runScript(instance)
	task.spawn(load(instance))
end

Engine.require = requireModule

return Engine
