--[[
	A mock Roblox engine for end-to-end tests. Instances are Lune's real ones (so every property name,
	enum and class is validated against Roblox's API database); everything the engine would normally
	provide - time, services, remotes, seats, raycasts - is faked here:

	  * a virtual-time task scheduler:     ctx:advance(seconds) runs task.wait / task.delay forward
	  * fake services:                     Players, DataStoreService, CollectionService, PhysicsService,
	                                       RunService, TweenService, UserInputService, Debris
	  * RemoteEvent / RemoteFunction:      FireClient / FireServer / InvokeServer with a log of calls
	  * VehicleSeat:Sit, Model:PivotTo, Workspace:Raycast, ...

	One context is "current" at a time (Mocks.new makes it current), because Lune's method
	polyfills are installed process-wide.
]]

local roblox = require("@lune/roblox")
local Env = require("../tools/env")

local Instance = roblox.Instance
local Vector3 = roblox.Vector3
local CFrame = roblox.CFrame

local Mocks = {}

local REPO_ROOT = "."
function Mocks.setRepoRoot(path: string)
	REPO_ROOT = path
end

-- Helpers -------------------------------------------------------------------------

local function deepCopy(value)
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for k, v in value do
		copy[k] = deepCopy(v)
	end
	return copy
end

-- In Lune, Position and CFrame are independent properties; in Roblox they are one. Always set both.
function Mocks.setPart(part, cframe)
	part.CFrame = cframe
	part.Position = cframe.Position
end

-- Scheduler -------------------------------------------------------------------------

function Mocks.newScheduler()
	local scheduler = { now = 0, errors = {} }
	local queue = {}
	local counter = 0

	local function push(wake: number, co: thread, args)
		counter += 1
		table.insert(queue, { wake = wake, order = counter, co = co, args = args })
	end

	local function resume(co: thread, ...)
		local ok, err = coroutine.resume(co, ...)
		if not ok then
			local message = tostring(err) .. "\n" .. debug.traceback(co)
			table.insert(scheduler.errors, message)
			print("[task error] " .. message)
		end
	end

	local task = {}
	function task.spawn(fn, ...)
		local co = type(fn) == "thread" and fn or coroutine.create(fn)
		resume(co, ...)
		return co
	end
	function task.defer(fn, ...)
		local co = coroutine.create(fn)
		push(scheduler.now, co, { ... })
		return co
	end
	function task.delay(seconds: number?, fn, ...)
		local co = coroutine.create(fn)
		push(scheduler.now + (seconds or 0), co, { ... })
		return co
	end
	function task.wait(seconds: number?)
		push(scheduler.now + (seconds or 0.03), coroutine.running(), nil)
		return coroutine.yield()
	end
	function task.cancel(co: thread)
		for i = #queue, 1, -1 do
			if queue[i].co == co then
				table.remove(queue, i)
			end
		end
	end

	function scheduler.advance(seconds: number)
		local target = scheduler.now + seconds
		while true do
			table.sort(queue, function(a, b)
				if a.wake ~= b.wake then
					return a.wake < b.wake
				end
				return a.order < b.order
			end)
			local entry = queue[1]
			if not entry or entry.wake > target then
				break
			end
			table.remove(queue, 1)
			scheduler.now = math.max(scheduler.now, entry.wake)
			if entry.args then
				resume(entry.co, table.unpack(entry.args))
			else
				resume(entry.co, 0)
			end
		end
		scheduler.now = target
	end

	function scheduler.pending(): number
		return #queue
	end

	scheduler.task = task
	return scheduler
end

-- Fake services -------------------------------------------------------------------------

local function newPlayersService(dm)
	local instance = dm:GetService("Players")
	local service = {
		Instance = instance,
		PlayerAdded = Env.newSignal(),
		PlayerRemoving = Env.newSignal(),
		CharacterOwners = {},
		LocalPlayer = nil,
	}
	function service:GetPlayers()
		return instance:GetChildren()
	end
	function service:GetPlayerFromCharacter(model)
		return self.CharacterOwners[model]
	end
	return service
end

local function newDataStoreService()
	local service = { Data = {}, FailGets = false, FailSets = false, GetCalls = 0, WriteCalls = 0, Error = "503: DataStore request was added to queue" }
	function service:GetDataStore(name: string)
		service.Data[name] = service.Data[name] or {}
		local store = {}
		function store:GetAsync(key)
			service.GetCalls += 1
			if service.FailGets then
				error(service.Error, 0)
			end
			return deepCopy(service.Data[name][key])
		end
		function store:UpdateAsync(key, fn)
			service.WriteCalls += 1
			if service.FailSets then
				error(service.Error, 0)
			end
			service.Data[name][key] = deepCopy(fn(deepCopy(service.Data[name][key])))
			return service.Data[name][key]
		end
		function store:SetAsync(key, value)
			service.WriteCalls += 1
			if service.FailSets then
				error(service.Error, 0)
			end
			service.Data[name][key] = deepCopy(value)
		end
		return store
	end
	return service
end

-- Like the engine, only reports tagged instances once they are actually in the game tree, so the
-- "added" signal fires on the next scheduler step rather than inside AddTag (the instance may not be parented yet).
local function newCollectionService(scheduler)
	local service = { Tagged = {}, Signals = {} }
	function service:AddTag(instance, tag: string)
		service.Tagged[tag] = service.Tagged[tag] or {}
		table.insert(service.Tagged[tag], instance)
		scheduler.task.defer(function()
			if service.Signals[tag] and instance.Parent then
				service.Signals[tag]:Fire(instance)
			end
		end)
	end
	function service:HasTag(instance, tag: string): boolean
		return table.find(service.Tagged[tag] or {}, instance) ~= nil
	end
	function service:GetTagged(tag: string)
		local list = {}
		for _, instance in service.Tagged[tag] or {} do
			if instance.Parent then
				table.insert(list, instance)
			end
		end
		return list
	end
	function service:GetInstanceAddedSignal(tag: string)
		service.Signals[tag] = service.Signals[tag] or Env.newSignal()
		return service.Signals[tag]
	end
	return service
end

local function newPhysicsService()
	local service = { Groups = {}, Collidable = {} }
	function service:IsCollisionGroupRegistered(name: string)
		return service.Groups[name] == true
	end
	function service:RegisterCollisionGroup(name: string)
		assert(not service.Groups[name], "group already registered: " .. name)
		service.Groups[name] = true
	end
	function service:CollisionGroupSetCollidable(a: string, b: string, collidable: boolean)
		assert(service.Groups[a] and service.Groups[b], "unregistered collision group")
		service.Collidable[a .. "|" .. b] = collidable
		service.Collidable[b .. "|" .. a] = collidable
	end
	return service
end

local function newTweenService()
	local service = { Created = 0 }
	function service:Create(instance, _info, goals)
		service.Created += 1
		return {
			Play = function()
				for property, value in goals do
					instance[property] = value -- instant; also validates every property name/type
				end
			end,
			Cancel = function() end,
		}
	end
	return service
end

-- Context -------------------------------------------------------------------------------

Mocks.current = nil
local installed = false

local function install()
	if installed then
		return
	end
	installed = true

	Env.installPolyfills({
		ProximityPrompt = { "Triggered" },
		RemoteEvent = { "OnServerEvent", "OnClientEvent" },
		TextButton = { "MouseEnter", "MouseLeave", "MouseButton1Down", "Activated" },
		Player = { "CharacterAdded" },
		Model = { "DescendantAdded" },
	})

	local function ctx()
		return Mocks.current
	end

	-- Time
	roblox.implementMethod("Workspace", "GetServerTimeNow", function()
		return ctx().scheduler.now
	end)

	-- A flat, endless road at y = 0.1 plus optional solid boxes (ctx.Obstacles) for spawn-blocking tests.
	roblox.implementMethod("Workspace", "Raycast", function(_, origin, direction)
		if direction.Y >= 0 then
			return nil
		end
		local t = (0.1 - origin.Y) / direction.Y
		if t < 0 or t > 1 then
			return nil
		end
		local hit = origin + direction * t
		return { Position = hit, Normal = Vector3.yAxis, Distance = (hit - origin).Magnitude }
	end)
	roblox.implementMethod("Workspace", "GetPartBoundsInBox", function(_, cframe, size)
		local center = cframe.Position
		local half = math.max(size.X, size.Z) / 2
		local hits = {}
		for _, box in ctx().Obstacles do
			local overlapX = math.abs(center.X - box.Center.X) < half + box.Half.X
			local overlapZ = math.abs(center.Z - box.Center.Z) < half + box.Half.Z
			local overlapY = math.abs(center.Y - box.Center.Y) < size.Y / 2 + box.Half.Y
			if overlapX and overlapZ and overlapY then
				table.insert(hits, { CanCollide = true, Name = "Obstacle" })
			end
		end
		return hits
	end)

	-- Models
	roblox.implementMethod("Model", "PivotTo", function(self, target)
		local delta = target * self.PrimaryPart.CFrame:Inverse()
		for _, descendant in self:GetDescendants() do
			if descendant:IsA("BasePart") then
				Mocks.setPart(descendant, delta * descendant.CFrame)
				-- Real parts always have a velocity; Lune's have none until one is assigned.
				if not pcall(function()
					return descendant.AssemblyLinearVelocity
				end) then
					descendant.AssemblyLinearVelocity = Vector3.zero
					descendant.AssemblyAngularVelocity = Vector3.zero
				end
			end
		end
	end)
	roblox.implementMethod("Model", "GetPivot", function(self)
		return self.PrimaryPart.CFrame
	end)
	roblox.implementMethod("Model", "GetExtentsSize", function(self)
		local minV, maxV = Vector3.new(math.huge, math.huge, math.huge), Vector3.new(-math.huge, -math.huge, -math.huge)
		for _, descendant in self:GetDescendants() do
			if descendant:IsA("BasePart") then
				local p, s = descendant.CFrame.Position, descendant.Size
				minV = Vector3.new(math.min(minV.X, p.X - s.X / 2), math.min(minV.Y, p.Y - s.Y / 2), math.min(minV.Z, p.Z - s.Z / 2))
				maxV = Vector3.new(math.max(maxV.X, p.X + s.X / 2), math.max(maxV.Y, p.Y + s.Y / 2), math.max(maxV.Z, p.Z + s.Z / 2))
			end
		end
		return maxV - minV
	end)

	-- Physics ownership (errors on anchored parts, like the real thing)
	local function setNetworkOwner(self, player)
		if self.Anchored then
			error("Network Ownership API cannot be called on Anchored parts or parts welded to Anchored parts.")
		end
		ctx().NetworkOwners[self] = player
	end
	for _, className in { "BasePart", "Part", "VehicleSeat", "Seat", "MeshPart" } do
		pcall(roblox.implementMethod, className, "SetNetworkOwner", setNetworkOwner)
	end

	-- Sitting
	roblox.implementMethod("VehicleSeat", "Sit", function(seat, humanoid)
		Mocks.sit(seat, humanoid)
	end)

	-- Particles
	roblox.implementMethod("ParticleEmitter", "Emit", function(_, count)
		ctx().ParticlesEmitted += count or 1
	end)

	-- Remotes
	local remoteFunctionHandlers = setmetatable({}, { __mode = "k" })
	roblox.implementMethod("RemoteEvent", "FireClient", function(self, player, ...)
		table.insert(ctx().Fired, { Remote = self.Name, Player = player, Args = { ... } })
		self.OnClientEvent:Fire(...)
	end)
	roblox.implementMethod("RemoteEvent", "FireServer", function(self, ...)
		table.insert(ctx().FiredToServer, { Remote = self.Name, Args = { ... } })
		self.OnServerEvent:Fire(ctx().players.LocalPlayer, ...)
	end)
	roblox.implementProperty("RemoteFunction", "OnServerInvoke", function(self)
		return remoteFunctionHandlers[self]
	end, function(self, handler)
		remoteFunctionHandlers[self] = handler
	end)
	roblox.implementMethod("RemoteFunction", "InvokeServer", function(self, ...)
		local handler = remoteFunctionHandlers[self]
		assert(handler, self.Name .. " has no OnServerInvoke handler")
		return handler(ctx().players.LocalPlayer, ...)
	end)
end

-- Seat simulation: the humanoid sits, the seat reports its occupant.
function Mocks.sit(seat, humanoid)
	seat.Occupant = humanoid
	humanoid.SeatPart = seat
	Env.fireChanged(seat, "Occupant")
end

-- Lune can't assign nil to a Ref property, but a Ref to a destroyed instance reads as nil. So the humanoid
-- "stands up" by being swapped for a fresh one (the game always re-fetches it). Returns the new humanoid.
function Mocks.leaveSeat(humanoid)
	local seat = humanoid.SeatPart
	local character = humanoid.Parent
	local replacement = Instance.new("Humanoid")
	replacement.Health = humanoid.Health
	humanoid:Destroy()
	replacement.Parent = character
	if seat then
		Env.fireChanged(seat, "Occupant")
	end
	return replacement
end

-- Builds a fresh world: DataModel with the game's scripts injected, fake services, virtual time.
-- options.localPlayer: true to make the first created player the LocalPlayer (for client tests)
function Mocks.new()
	install()

	local dm = Instance.new("DataModel")
	Env.injectSources(dm, REPO_ROOT)

	local scheduler = Mocks.newScheduler()
	local players = newPlayersService(dm)
	local runService = {
		Server = true,
		PreSimulation = Env.newSignal(),
		RenderStepped = Env.newSignal(),
		Heartbeat = Env.newSignal(),
	}
	function runService:IsServer()
		return self.Server
	end
	function runService:IsClient()
		return not self.Server
	end
	function runService:IsStudio()
		return true
	end

	local services = {
		Players = players,
		RunService = runService,
		DataStoreService = newDataStoreService(),
		CollectionService = newCollectionService(scheduler),
		PhysicsService = newPhysicsService(),
		TweenService = newTweenService(),
		UserInputService = { InputBegan = Env.newSignal() },
		Debris = {
			AddItem = function(_, instance, seconds)
				scheduler.task.delay(seconds, function()
					instance:Destroy()
				end)
			end,
		},
	}

	local simulatedOs = table.clone(os)
	simulatedOs.clock = function()
		return scheduler.now
	end

	local context = {
		DataModel = dm,
		Workspace = dm:GetService("Workspace"),
		scheduler = scheduler,
		services = services,
		players = players,
		runService = runService,
		Fired = {}, -- server -> client remote calls
		FiredToServer = {}, -- client -> server remote calls
		NetworkOwners = {},
		ParticlesEmitted = 0,
		Obstacles = {}, -- { Center = Vector3, Half = Vector3 }
		Tick = 0,
	}

	context.runtime = Env.new(dm, {
		services = services,
		globals = {
			task = scheduler.task,
			os = simulatedOs,
			TweenInfo = {
				new = function(...)
					return { ... }
				end,
			},
			RaycastParams = {
				new = function()
					return { FilterDescendantsInstances = {}, FilterType = nil }
				end,
			},
			OverlapParams = {
				new = function()
					return { FilterDescendantsInstances = {}, FilterType = nil }
				end,
			},
		},
	})

	Mocks.current = context

	-- Module access ---------------------------------------------------------------------

	local function find(path: string)
		local instance = dm
		for part in string.gmatch(path, "[^%.]+") do
			instance = instance:FindFirstChild(part) or instance:GetService(part)
		end
		return instance
	end

	function context:find(path: string)
		return find(path)
	end
	function context:require(path: string)
		return self.runtime:require(find(path))
	end
	function context:run(path: string)
		return self.runtime:run(find(path))
	end

	-- Time ---------------------------------------------------------------------------------

	-- Advances virtual time in small steps, mirroring attribute changes to the client's signals as it goes.
	function context:advance(seconds: number, step: number?)
		step = step or 0.1
		local remaining = seconds
		while remaining > 1e-9 do
			local dt = math.min(step, remaining)
			scheduler.advance(dt)
			remaining -= dt
			self:flush()
		end
		assert(#scheduler.errors == 0, "a background task errored:\n" .. table.concat(scheduler.errors, "\n"))
	end

	-- Attribute change notification ----------------------------------------------------------
	-- Lune can't tell us when SetAttribute is called, so compare against a snapshot instead.
	local snapshots = setmetatable({}, { __mode = "k" })
	function context:flush()
		for _, player in players.Instance:GetChildren() do
			local previous = snapshots[player] or {}
			local current = player:GetAttributes()
			for name, value in current do
				if previous[name] ~= value then
					Env.fireChanged(player, "attr:" .. name)
				end
			end
			for name in previous do
				if current[name] == nil then
					Env.fireChanged(player, "attr:" .. name)
				end
			end
			snapshots[player] = current
		end
	end

	-- Players -----------------------------------------------------------------------------------

	function context:newPlayer(name: string, userId: number)
		local player = Instance.new("Player")
		player.Name = name
		player.UserId = userId
		player.Parent = players.Instance
		return player
	end

	function context:spawnCharacter(player, position)
		local model = Instance.new("Model")
		model.Name = player.Name
		local root = Instance.new("Part")
		root.Name = "HumanoidRootPart"
		root.Size = Vector3.new(2, 2, 1)
		Mocks.setPart(root, CFrame.new(position))
		root.AssemblyLinearVelocity = Vector3.zero
		root.Parent = model
		local humanoid = Instance.new("Humanoid")
		humanoid.Health = 100
		humanoid.Parent = model
		model.PrimaryPart = root
		model.Parent = self.Workspace
		player.Character = model
		players.CharacterOwners[model] = player
		player.CharacterAdded:Fire(model)
		return model
	end

	-- Moves a player's character (and sets its speed along +X).
	function context:teleport(player, position, speed: number?)
		local root = player.Character.HumanoidRootPart
		Mocks.setPart(root, CFrame.new(position))
		root.AssemblyLinearVelocity = Vector3.new(speed or 0, 0, 0)
	end

	-- Joins a player the way the engine would: parented, then PlayerAdded fires.
	function context:join(name: string, userId: number, position)
		local player = self:newPlayer(name, userId)
		players.PlayerAdded:Fire(player)
		self:flush()
		local character = self:spawnCharacter(player, position or Vector3.new(0, 3, 34))
		return player, character
	end

	function context:leave(player)
		players.PlayerRemoving:Fire(player)
		player.Parent = nil
	end

	-- Client side ------------------------------------------------------------------------------

	-- Makes `player` the local player with a PlayerGui and a camera (1280x720, at (0, 10, 0) looking down -Z).
	function context:setupClient(player)
		players.LocalPlayer = player
		local gui = Instance.new("PlayerGui")
		gui.Parent = player
		local camera = Instance.new("Camera")
		camera.ViewportSize = roblox.Vector2.new(1280, 720)
		camera.CFrame = CFrame.new(0, 10, 0)
		camera.Parent = self.Workspace
		self.Workspace.CurrentCamera = camera
		self.Camera = camera
		self.PlayerGui = gui
		return gui
	end

	-- Fires the per-frame signals the UI listens to.
	function context:frames(count: number?, dt: number?)
		for _ = 1, count or 1 do
			self.runService.RenderStepped:Fire(dt or 1 / 60)
			self.runService.PreSimulation:Fire(dt or 1 / 60)
		end
	end

	-- Server -> client remote calls received by a remote name.
	function context:fired(remoteName: string)
		local list = {}
		for _, call in self.Fired do
			if call.Remote == remoteName then
				table.insert(list, call)
			end
		end
		return list
	end

	function context:clearFired()
		table.clear(self.Fired)
		table.clear(self.FiredToServer)
	end

	return context
end

return Mocks
