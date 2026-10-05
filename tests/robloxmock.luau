--!nocheck
-- A small fake of the Roblox engine, just big enough to run this game's real
-- server and client scripts under the plain Luau CLI:
--   * Instance tree (parenting, attributes, FindFirstChild, tags, Destroy ...)
--   * Vector3 / CFrame math, Color3, Enum, UDim2 and friends
--   * a cooperative task scheduler on a *virtual clock* (advance(dt))
--   * Players, RemoteEvent/RemoteFunction, DataStore (in memory), TweenService ...

local M = {}

--------------------------------------------------------------------------
-- Math types
--------------------------------------------------------------------------
local Vector3 = {}
Vector3.__index = function(self, key)
	if key == "Magnitude" then
		return math.sqrt(self.X * self.X + self.Y * self.Y + self.Z * self.Z)
	elseif key == "Unit" then
		local m = math.sqrt(self.X * self.X + self.Y * self.Y + self.Z * self.Z)
		return Vector3.new(self.X / m, self.Y / m, self.Z / m)
	end
	return Vector3[key]
end
function Vector3.new(x, y, z)
	return setmetatable({ X = x or 0, Y = y or 0, Z = z or 0 }, Vector3)
end
Vector3.zero = Vector3.new(0, 0, 0)
Vector3.one = Vector3.new(1, 1, 1)
function Vector3.__add(a, b)
	return Vector3.new(a.X + b.X, a.Y + b.Y, a.Z + b.Z)
end
function Vector3.__sub(a, b)
	return Vector3.new(a.X - b.X, a.Y - b.Y, a.Z - b.Z)
end
function Vector3.__unm(a)
	return Vector3.new(-a.X, -a.Y, -a.Z)
end
function Vector3.__mul(a, b)
	if type(a) == "number" then
		return Vector3.new(a * b.X, a * b.Y, a * b.Z)
	end
	if type(b) == "number" then
		return Vector3.new(a.X * b, a.Y * b, a.Z * b)
	end
	return Vector3.new(a.X * b.X, a.Y * b.Y, a.Z * b.Z)
end
function Vector3.__div(a, b)
	if type(b) == "number" then
		return Vector3.new(a.X / b, a.Y / b, a.Z / b)
	end
	return Vector3.new(a.X / b.X, a.Y / b.Y, a.Z / b.Z)
end
function Vector3.Lerp(a, b, t)
	return a + (b - a) * t
end
function Vector3.Dot(a, b)
	return a.X * b.X + a.Y * b.Y + a.Z * b.Z
end
function Vector3.Cross(a, b)
	return Vector3.new(a.Y * b.Z - a.Z * b.Y, a.Z * b.X - a.X * b.Z, a.X * b.Y - a.Y * b.X)
end

local function mat3mul(a, b)
	local r = {}
	for i = 0, 2 do
		for j = 0, 2 do
			r[i * 3 + j + 1] = a[i * 3 + 1] * b[j + 1] + a[i * 3 + 2] * b[3 + j + 1] + a[i * 3 + 3] * b[6 + j + 1]
		end
	end
	return r
end
local function mat3vec(a, v)
	return Vector3.new(
		a[1] * v.X + a[2] * v.Y + a[3] * v.Z,
		a[4] * v.X + a[5] * v.Y + a[6] * v.Z,
		a[7] * v.X + a[8] * v.Y + a[9] * v.Z
	)
end
local IDENTITY = { 1, 0, 0, 0, 1, 0, 0, 0, 1 }

local CFrame = {}
CFrame.__index = function(self, key)
	if key == "Position" then
		return Vector3.new(self.x, self.y, self.z)
	end
	if key == "Rotation" then
		return setmetatable({ r = self.r, x = 0, y = 0, z = 0 }, CFrame)
	end
	if key == "LookVector" then
		return Vector3.new(-self.r[3], -self.r[6], -self.r[9])
	end
	if key == "RightVector" then
		return Vector3.new(self.r[1], self.r[4], self.r[7])
	end
	if key == "UpVector" then
		return Vector3.new(self.r[2], self.r[5], self.r[8])
	end
	if key == "X" then
		return self.x
	elseif key == "Y" then
		return self.y
	elseif key == "Z" then
		return self.z
	end
	return CFrame[key]
end
local function cf(r, x, y, z)
	return setmetatable({ r = r, x = x, y = y, z = z }, CFrame)
end
function CFrame.new(a, b, c)
	if a == nil then
		return cf(IDENTITY, 0, 0, 0)
	end
	if type(a) == "table" then
		return cf(IDENTITY, a.X, a.Y, a.Z)
	end
	return cf(IDENTITY, a, b, c)
end
function CFrame.Angles(rx, ry, rz)
	local cx, sx, cy, sy, cz, sz = math.cos(rx), math.sin(rx), math.cos(ry), math.sin(ry), math.cos(rz), math.sin(rz)
	local Rx = { 1, 0, 0, 0, cx, -sx, 0, sx, cx }
	local Ry = { cy, 0, sy, 0, 1, 0, -sy, 0, cy }
	local Rz = { cz, -sz, 0, sz, cz, 0, 0, 0, 1 }
	return cf(mat3mul(mat3mul(Rx, Ry), Rz), 0, 0, 0)
end
function CFrame.lookAt(at, target, up)
	up = up or Vector3.new(0, 1, 0)
	local z = (at - target).Unit
	local x = up:Cross(z)
	if x.Magnitude < 1e-6 then
		error("CFrame.lookAt: look direction parallel to up vector")
	end
	x = x.Unit
	local y = z:Cross(x)
	return cf({ x.X, y.X, z.X, x.Y, y.Y, z.Y, x.Z, y.Z, z.Z }, at.X, at.Y, at.Z)
end
function CFrame.__mul(a, b)
	if getmetatable(b) == CFrame then
		local p = mat3vec(a.r, Vector3.new(b.x, b.y, b.z))
		return cf(mat3mul(a.r, b.r), p.X + a.x, p.Y + a.y, p.Z + a.z)
	end
	local p = mat3vec(a.r, b)
	return Vector3.new(p.X + a.x, p.Y + a.y, p.Z + a.z)
end
function CFrame.__add(a, v)
	return cf(a.r, a.x + v.X, a.y + v.Y, a.z + v.Z)
end
function CFrame.__sub(a, v)
	return cf(a.r, a.x - v.X, a.y - v.Y, a.z - v.Z)
end
function CFrame.PointToWorldSpace(self, v)
	return self * v
end
function CFrame.Inverse(self)
	local r = self.r
	local rt = { r[1], r[4], r[7], r[2], r[5], r[8], r[3], r[6], r[9] }
	local p = mat3vec(rt, Vector3.new(-self.x, -self.y, -self.z))
	return cf(rt, p.X, p.Y, p.Z)
end

-- Generic value constructors (UDim2, NumberSequence ...): they just keep their arguments.
local function constructorLib(name, fields)
	return setmetatable({}, {
		__index = function(_, ctor)
			return function(...)
				return { kind = name, ctor = ctor, args = table.pack(...) }
			end
		end,
	})
end
local Vector2 = {
	new = function(x, y)
		return { X = x or 0, Y = y or 0 }
	end,
}
local Color3 = {
	fromRGB = function(r, g, b)
		return { R = r / 255, G = g / 255, B = b / 255 }
	end,
	new = function(r, g, b)
		return { R = r, G = g, B = b }
	end,
}

local enumCache = {}
local Enum = setmetatable({}, {
	__index = function(_, enumName)
		local items = {}
		local proxy = setmetatable({}, {
			__index = function(_, item)
				local key = enumName .. "." .. item
				if not enumCache[key] then
					enumCache[key] = { EnumType = enumName, Name = item }
				end
				return enumCache[key]
			end,
		})
		return proxy
	end,
})

-- Deterministic PRNG with the same surface as Roblox's Random.
local Random = {}
Random.__index = Random
function Random.new(seed)
	local s = (math.floor(seed or 0) * 2654435761 + 12345) % 4294967296
	if s == 0 then
		s = 1
	end
	return setmetatable({ state = s }, Random)
end
local function nextRaw(self)
	local x = self.state
	x = bit32.bxor(x, bit32.lshift(x, 13))
	x = bit32.bxor(x, bit32.rshift(x, 17))
	x = bit32.bxor(x, bit32.lshift(x, 5))
	self.state = x
	return x / 4294967296
end
function Random:NextNumber(min, max)
	local r = nextRaw(self)
	if min == nil then
		return r
	end
	return min + (max - min) * r
end
function Random:NextInteger(min, max)
	return min + math.floor(nextRaw(self) * (max - min + 1))
end
M.Random = Random

function M.create(opts)
	opts = opts or {}
	local world = { errors = {}, warnings = {}, kicked = {}, now = opts.startTime or 1_700_000_000.0 }

	--------------------------------------------------------------------------
	-- Virtual-time scheduler
	--------------------------------------------------------------------------
	local queue, seq = {}, 0
	local function schedule(at, fn)
		seq += 1
		table.insert(queue, { at = at, seq = seq, fn = fn })
	end
	local function resume(co, ...)
		local ok, err = coroutine.resume(co, ...)
		if not ok then
			local trace = debug.traceback(co, tostring(err))
			table.insert(world.errors, trace)
			print("[mock] thread error: " .. trace)
		end
	end
	local task = {}
	function task.spawn(f, ...)
		local co = type(f) == "thread" and f or coroutine.create(f)
		resume(co, ...)
		return co
	end
	function task.defer(f, ...)
		local co = type(f) == "thread" and f or coroutine.create(f)
		local args = table.pack(...)
		schedule(world.now, function()
			resume(co, table.unpack(args, 1, args.n))
		end)
		return co
	end
	function task.delay(t, f, ...)
		local co = type(f) == "thread" and f or coroutine.create(f)
		local args = table.pack(...)
		schedule(world.now + t, function()
			resume(co, table.unpack(args, 1, args.n))
		end)
		return co
	end
	function task.wait(t)
		local co, isMain = coroutine.running()
		t = t or 1 / 30
		schedule(world.now + t, function()
			resume(co, t)
		end)
		return coroutine.yield()
	end
	function task.cancel() end

	function world.advance(dt)
		local target = world.now + dt
		while true do
			local bestIndex
			for i, ev in queue do
				if
					ev.at <= target
					and (
						not bestIndex
						or ev.at < queue[bestIndex].at
						or (ev.at == queue[bestIndex].at and ev.seq < queue[bestIndex].seq)
					)
				then
					bestIndex = i
				end
			end
			if not bestIndex then
				break
			end
			local ev = table.remove(queue, bestIndex)
			world.now = math.max(world.now, ev.at)
			ev.fn()
		end
		world.now = target
	end

	--------------------------------------------------------------------------
	-- Signals
	--------------------------------------------------------------------------
	local function newSignal()
		local s = { handlers = {}, waiters = {} }
		function s:Connect(fn)
			local token = {}
			self.handlers[token] = fn
			return {
				Connected = true,
				Disconnect = function()
					self.handlers[token] = nil
				end,
			}
		end
		function s:Once(fn)
			local c
			c = self:Connect(function(...)
				c.Disconnect()
				fn(...)
			end)
			return c
		end
		function s:Wait()
			local co = coroutine.running()
			table.insert(self.waiters, co)
			return coroutine.yield()
		end
		function s:Fire(...)
			for _, fn in table.clone(self.handlers) do
				task.spawn(fn, ...)
			end
			local waiters = self.waiters
			self.waiters = {}
			for _, co in waiters do
				task.spawn(co, ...)
			end
		end
		return s
	end

	local EVENT_KEYS = {}
	for _, k in
		{
			"PlayerAdded",
			"PlayerRemoving",
			"CharacterAdded",
			"OnServerEvent",
			"OnClientEvent",
			"Triggered",
			"Activated",
			"Heartbeat",
			"RenderStepped",
			"InputBegan",
			"PromptTriggered",
			"Completed",
			"Changed",
			"ChildAdded",
			"ChildRemoved",
			"Touched",
			"Died",
			"DescendantAdded",
			"MouseButton1Click",
		}
	do
		EVENT_KEYS[k] = true
	end

	--------------------------------------------------------------------------
	-- Instances
	--------------------------------------------------------------------------
	local CLASS_PARENTS = {
		Part = { "BasePart", "PVInstance" },
		SpawnLocation = { "Part", "BasePart", "PVInstance" },
		Model = { "PVInstance" },
		WedgePart = { "BasePart", "PVInstance" },
		Frame = { "GuiObject", "GuiBase2d" },
		TextLabel = { "GuiObject", "GuiBase2d" },
		TextButton = { "GuiButton", "GuiObject", "GuiBase2d" },
		ViewportFrame = { "GuiObject", "GuiBase2d" },
		ScrollingFrame = { "GuiObject", "GuiBase2d" },
		ImageLabel = { "GuiObject", "GuiBase2d" },
		ScreenGui = { "LayerCollector", "GuiBase2d" },
		BillboardGui = { "LayerCollector", "GuiBase2d" },
		SurfaceGui = { "LayerCollector", "GuiBase2d" },
	}
	local InstanceMT = {}
	local METHODS = {}
	local tagged = {} -- tag -> { [instance] = true }
	local tagSignals = {}

	local function isDescendantOfGame(inst)
		local p = rawget(inst, "_parent")
		while p do
			if p == world.game then
				return true
			end
			p = rawget(p, "_parent")
		end
		return false
	end
	local function fireTagSignals(inst, kind)
		for tag, set in tagged do
			if set[inst] and tagSignals[tag] then
				tagSignals[tag][kind]:Fire(inst)
			end
		end
	end
	local function setParent(inst, newParent)
		local old = rawget(inst, "_parent")
		if old == newParent then
			return
		end
		local wasIn = isDescendantOfGame(inst)
		if old then
			for i, c in old._children do
				if c == inst then
					table.remove(old._children, i)
					break
				end
			end
			if rawget(old, "_signals") and old._signals.ChildRemoved then
				old._signals.ChildRemoved:Fire(inst)
			end
		end
		rawset(inst, "_parent", newParent)
		if newParent then
			table.insert(newParent._children, inst)
			if rawget(newParent, "_signals") and newParent._signals.ChildAdded then
				newParent._signals.ChildAdded:Fire(inst)
			end
		end
		local isIn = isDescendantOfGame(inst)
		if isIn and not wasIn then
			fireTagSignals(inst, "added")
		elseif wasIn and not isIn then
			fireTagSignals(inst, "removed")
		end
	end

	InstanceMT.__index = function(self, key)
		local m = METHODS[key]
		if m then
			return m
		end
		if key == "Parent" then
			return rawget(self, "_parent")
		end
		if key == "Position" and rawget(self, "CFrame") then
			return self.CFrame.Position
		end
		for _, c in rawget(self, "_children") do
			if c.Name == key then
				return c
			end
		end
		if EVENT_KEYS[key] then
			local s = newSignal()
			self._signals[key] = s
			rawset(self, key, s)
			return s
		end
		return nil
	end
	InstanceMT.__newindex = function(self, key, value)
		if key == "Parent" then
			setParent(self, value)
		elseif key == "Position" and rawget(self, "CFrame") then
			local c = self.CFrame
			rawset(self, "CFrame", cf(c.r, value.X, value.Y, value.Z))
		else
			rawset(self, key, value)
		end
	end

	local function newInstance(className)
		local self = setmetatable(
			{ ClassName = className, Name = className, _children = {}, _attrs = {}, _signals = {}, _parent = nil },
			InstanceMT
		)
		if className == "Part" or className == "SpawnLocation" or className == "WedgePart" then
			rawset(self, "Size", Vector3.new(4, 1, 2))
			rawset(self, "CFrame", CFrame.new())
			rawset(self, "Anchored", false)
		elseif className == "Camera" then
			rawset(self, "CFrame", CFrame.new())
		elseif className == "RemoteEvent" or className == "RemoteFunction" then
			rawset(self, "_fired", {})
		end
		return self
	end

	function METHODS.IsA(self, name)
		if self.ClassName == name or name == "Instance" then
			return true
		end
		for _, p in CLASS_PARENTS[self.ClassName] or {} do
			if p == name then
				return true
			end
		end
		return false
	end
	function METHODS.GetChildren(self)
		return table.clone(self._children)
	end
	function METHODS.GetDescendants(self)
		local out = {}
		local function walk(n)
			for _, c in n._children do
				table.insert(out, c)
				walk(c)
			end
		end
		walk(self)
		return out
	end
	function METHODS.FindFirstChild(self, name, recursive)
		for _, c in self._children do
			if c.Name == name then
				return c
			end
		end
		if recursive then
			for _, c in self._children do
				local r = METHODS.FindFirstChild(c, name, true)
				if r then
					return r
				end
			end
		end
		return nil
	end
	function METHODS.FindFirstChildOfClass(self, className)
		for _, c in self._children do
			if c.ClassName == className then
				return c
			end
		end
		return nil
	end
	function METHODS.FindFirstChildWhichIsA(self, className)
		for _, c in self._children do
			if c:IsA(className) then
				return c
			end
		end
		return nil
	end
	function METHODS.WaitForChild(self, name, timeout)
		local found = METHODS.FindFirstChild(self, name)
		if found then
			return found
		end
		if timeout then
			return nil
		end
		error(`mock: WaitForChild("{name}") on {self.Name} would yield forever (missing child)`, 2)
	end
	function METHODS.GetFullName(self)
		local parts, n = {}, self
		while n and n ~= world.game do
			table.insert(parts, 1, n.Name)
			n = rawget(n, "_parent")
		end
		return table.concat(parts, ".")
	end
	function METHODS.IsDescendantOf(self, ancestor)
		local p = rawget(self, "_parent")
		while p do
			if p == ancestor then
				return true
			end
			p = rawget(p, "_parent")
		end
		return false
	end
	function METHODS.Destroy(self)
		for _, c in table.clone(self._children) do
			METHODS.Destroy(c)
		end
		setParent(self, nil)
		rawset(self, "_destroyed", true)
	end
	function METHODS.ClearAllChildren(self)
		for _, c in table.clone(self._children) do
			METHODS.Destroy(c)
		end
	end
	function METHODS.SetAttribute(self, k, v)
		self._attrs[k] = v
	end
	function METHODS.GetAttribute(self, k)
		return self._attrs[k]
	end
	function METHODS.GetAttributes(self)
		return table.clone(self._attrs)
	end
	function METHODS.GetAttributeChangedSignal(self, k)
		return newSignal()
	end
	function METHODS.GetPropertyChangedSignal(self, k)
		return newSignal()
	end
	function METHODS.ScaleTo(self, s)
		rawset(self, "_scale", s)
	end
	function METHODS.GetScale(self)
		return rawget(self, "_scale") or 1
	end
	function METHODS.PivotTo(self, c)
		local root = rawget(self, "PrimaryPart")
		if root then
			root.CFrame = c
		end
		rawset(self, "_pivot", c)
	end
	function METHODS.GetPivot(self)
		return rawget(self, "_pivot") or CFrame.new()
	end
	function METHODS.GetBoundingBox(self)
		local lo, hi
		for _, d in METHODS.GetDescendants(self) do
			if d:IsA("BasePart") then
				local p, s = d.CFrame.Position, d.Size
				local a, b =
					Vector3.new(p.X - s.X / 2, p.Y - s.Y / 2, p.Z - s.Z / 2),
					Vector3.new(p.X + s.X / 2, p.Y + s.Y / 2, p.Z + s.Z / 2)
				lo = lo and Vector3.new(math.min(lo.X, a.X), math.min(lo.Y, a.Y), math.min(lo.Z, a.Z)) or a
				hi = hi and Vector3.new(math.max(hi.X, b.X), math.max(hi.Y, b.Y), math.max(hi.Z, b.Z)) or b
			end
		end
		if not lo then
			return CFrame.new(), Vector3.new(1, 1, 1)
		end
		local size = hi - lo
		return CFrame.new((lo.X + hi.X) / 2, (lo.Y + hi.Y) / 2, (lo.Z + hi.Z) / 2), size
	end
	-- remotes
	function METHODS.FireClient(self, player, ...)
		table.insert(self._fired, { to = player, args = table.pack(...) })
		world.onFireClient(self, player, table.pack(...))
	end
	function METHODS.FireAllClients(self, ...)
		table.insert(self._fired, { to = "all", args = table.pack(...) })
		world.onFireClient(self, "all", table.pack(...))
	end
	function METHODS.FireServer(self, ...)
		world.onFireServer(self, table.pack(...))
	end
	function METHODS.InvokeServer(self, ...)
		return world.onInvokeServer(self, table.pack(...))
	end
	-- player
	function METHODS.Kick(self, message)
		table.insert(world.kicked, { player = self, message = message })
		world.removePlayer(self)
	end

	local Instance = { new = newInstance }

	--------------------------------------------------------------------------
	-- Services
	--------------------------------------------------------------------------
	local game = newInstance("DataModel")
	game.Name = "game"
	world.game = game
	local workspace = newInstance("Workspace")
	workspace.Name = "Workspace"
	workspace.Parent = game
	workspace.CurrentCamera = newInstance("Camera")
	function workspace.GetServerTimeNow()
		return world.now
	end
	world.workspace = workspace

	local services = { Workspace = workspace }
	local function service(name)
		local s = newInstance(name)
		s.Name = name
		s.Parent = game
		services[name] = s
		return s
	end
	for _, n in
		{
			"ReplicatedStorage",
			"ServerScriptService",
			"Lighting",
			"StarterGui",
			"Debris",
			"UserInputService",
			"ProximityPromptService",
			"StarterPlayer",
		}
	do
		service(n)
	end

	local Players = service("Players")
	function Players.GetPlayers(self)
		local out = {}
		for _, c in self._children do
			if c.ClassName == "Player" then
				table.insert(out, c)
			end
		end
		return out
	end
	world.Players = Players

	local RunService = service("RunService")
	function RunService.IsServer()
		return opts.isClient ~= true
	end
	function RunService.IsClient()
		return opts.isClient == true
	end
	function RunService.IsStudio()
		return opts.studio ~= false
	end

	local TweenService = service("TweenService")
	function TweenService.Create(self, inst, info, goals)
		local tween = { Completed = newSignal() }
		function tween.Play()
			task.delay((info and info.Time) or 0, function()
				for k, v in goals do
					inst[k] = v
				end
				tween.Completed:Fire()
			end)
		end
		function tween.Cancel() end
		return tween
	end
	local TweenInfo = {
		new = function(t, ...)
			return { Time = t or 1 }
		end,
	}

	function services.Debris.AddItem(self, inst, t)
		task.delay(t, function()
			if not rawget(inst, "_destroyed") then
				inst:Destroy()
			end
		end)
	end

	local CollectionService = service("CollectionService")
	function CollectionService.AddTag(self, inst, tag)
		tagged[tag] = tagged[tag] or {}
		tagged[tag][inst] = true
		if isDescendantOfGame(inst) and tagSignals[tag] then
			tagSignals[tag].added:Fire(inst)
		end
	end
	function CollectionService.GetTagged(self, tag)
		local out = {}
		for inst in tagged[tag] or {} do
			if isDescendantOfGame(inst) then
				table.insert(out, inst)
			end
		end
		return out
	end
	local function signalsFor(tag)
		tagSignals[tag] = tagSignals[tag] or { added = newSignal(), removed = newSignal() }
		return tagSignals[tag]
	end
	function CollectionService.GetInstanceAddedSignal(self, tag)
		return signalsFor(tag).added
	end
	function CollectionService.GetInstanceRemovedSignal(self, tag)
		return signalsFor(tag).removed
	end

	-- DataStore (in memory, copies on the way in and out like the real thing)
	local function deepcopy(v)
		if type(v) ~= "table" then
			return v
		end
		local out = {}
		for k, x in v do
			out[k] = deepcopy(x)
		end
		return out
	end
	world.dataStores = {}
	world.dataStoreFail = false
	local DataStoreService = service("DataStoreService")
	function DataStoreService.GetDataStore(self, name)
		world.dataStores[name] = world.dataStores[name] or {}
		local data = world.dataStores[name]
		return {
			GetAsync = function(_, key)
				if world.dataStoreFail then
					error("DataStore request was rejected (mock)")
				end
				return deepcopy(data[key])
			end,
			UpdateAsync = function(_, key, fn)
				if world.dataStoreFail then
					error("DataStore request was rejected (mock)")
				end
				local new = fn(deepcopy(data[key]))
				if new ~= nil then
					data[key] = deepcopy(new)
				end
			end,
			SetAsync = function(_, key, value)
				if world.dataStoreFail then
					error("DataStore request was rejected (mock)")
				end
				data[key] = deepcopy(value)
			end,
		}
	end

	function game.GetService(self, name)
		local s = services[name]
		if not s then
			error("mock: service not available: " .. tostring(name), 2)
		end
		return s
	end
	world.bindToClose = {}
	function game.BindToClose(self, fn)
		table.insert(world.bindToClose, fn)
	end

	--------------------------------------------------------------------------
	-- Players & remotes plumbing
	--------------------------------------------------------------------------
	world.serverEventLog = {}
	function world.onFireClient(remote, target, packed) end
	function world.onFireServer(remote, packed)
		local sig = remote._signals.OnServerEvent
		if sig then
			sig:Fire(world.localPlayer, table.unpack(packed, 1, packed.n))
		end
	end
	function world.onInvokeServer(remote, packed)
		local handler = rawget(remote, "OnServerInvoke")
		if not handler then
			error("mock: no OnServerInvoke on " .. remote.Name)
		end
		return handler(world.localPlayer, table.unpack(packed, 1, packed.n))
	end

	local nextUserId = 1000
	function world.addPlayer(name, userId)
		local p = newInstance("Player")
		p.Name = name
		p.DisplayName = name .. "Display"
		nextUserId += 1
		p.UserId = userId or nextUserId
		p.Parent = Players
		Players.PlayerAdded:Fire(p)
		return p
	end
	function world.removePlayer(p)
		if p.Parent ~= Players then
			return
		end
		Players.PlayerRemoving:Fire(p)
		p.Parent = nil
	end
	function world.spawnCharacter(p)
		local char = newInstance("Model")
		char.Name = p.Name
		local hrp = newInstance("Part")
		hrp.Name = "HumanoidRootPart"
		hrp.Parent = char
		char.PrimaryPart = hrp
		char.Parent = workspace
		p.Character = char
		p.CharacterAdded:Fire(char)
		return char
	end

	--------------------------------------------------------------------------
	-- Module loading (SOURCES are injected by the test runner)
	--------------------------------------------------------------------------
	local env = setmetatable({
		Instance = Instance,
		Vector3 = Vector3,
		Vector2 = Vector2,
		CFrame = CFrame,
		Color3 = Color3,
		Enum = Enum,
		UDim2 = constructorLib("UDim2"),
		UDim = constructorLib("UDim"),
		NumberRange = constructorLib("NumberRange"),
		NumberSequence = constructorLib("NumberSequence"),
		NumberSequenceKeypoint = constructorLib("NumberSequenceKeypoint"),
		ColorSequence = constructorLib("ColorSequence"),
		ColorSequenceKeypoint = constructorLib("ColorSequenceKeypoint"),
		TweenInfo = TweenInfo,
		task = task,
		game = game,
		workspace = workspace,
		Random = Random,
		warn = function(...)
			local parts = {}
			for _, v in table.pack(...) do
				table.insert(parts, tostring(v))
			end
			table.insert(world.warnings, table.concat(parts, " "))
		end,
		os = setmetatable({
			clock = function()
				return world.now
			end,
			time = function()
				return math.floor(world.now)
			end,
		}, { __index = os }),
	}, { __index = _G })
	world.env = env

	local cache = {}
	local function sourceLoader(inst)
		local source = rawget(inst, "Source")
		local fn, err = loadstring(source, "=" .. inst:GetFullName())
		if not fn then
			error(err, 0)
		end
		setfenv(fn, setmetatable({ script = inst }, { __index = env }))
		return fn
	end
	env.require = function(inst)
		if inst.ClassName ~= "ModuleScript" then
			error("mock: require expects a ModuleScript, got " .. tostring(inst and inst.ClassName))
		end
		if cache[inst] ~= nil then
			return cache[inst]
		end
		local result = sourceLoader(inst)()
		cache[inst] = result
		return result
	end

	-- Build the DataModel tree from SOURCES, mirroring default.project.json.
	function world.mountSources(SOURCES)
		local shared = newInstance("Folder")
		shared.Name = "Shared"
		shared.Parent = services.ReplicatedStorage

		local function make(className, name, source)
			local inst = newInstance(className)
			inst.Name = name
			inst.Source = source
			return inst
		end

		local scripts = {}
		for path, source in SOURCES do
			local area, name = string.match(path, "^(%w+)/(.+)$")
			if name == "init" then
				scripts[area] = make(
					area == "server" and "Script" or "LocalScript",
					area == "server" and "Server" or "Client",
					source
				)
			end
		end
		for path, source in SOURCES do
			local area, name = string.match(path, "^(%w+)/(.+)$")
			if name ~= "init" then
				local module = make("ModuleScript", name, source)
				module.Parent = if area == "shared" then shared else scripts[area]
			end
		end
		world.serverScript, world.clientScript = scripts.server, scripts.client
		if scripts.server then
			scripts.server.Parent = services.ServerScriptService
		end
		if scripts.client then
			local sps = newInstance("StarterPlayerScripts")
			sps.Name = "StarterPlayerScripts"
			sps.Parent = services.StarterPlayer
			scripts.client.Parent = sps
		end
	end

	function world.tagsOf(inst)
		local out = {}
		for tag, set in tagged do
			if set[inst] then
				table.insert(out, tag)
			end
		end
		return out
	end
	function world.makeLocalPlayer(name, userId)
		local p = newInstance("Player")
		p.Name = name
		p.DisplayName = name
		p.UserId = userId
		local pg = newInstance("PlayerGui")
		pg.Name = "PlayerGui"
		pg.Parent = p
		p.Parent = Players
		Players.LocalPlayer = p
		return p
	end

	function world.requireShared(name)
		return env.require(services.ReplicatedStorage.Shared[name])
	end
	function world.runScript(inst)
		local fn = sourceLoader(inst)
		return task.spawn(fn)
	end

	world.Instance = Instance
	world.Vector3, world.CFrame, world.Color3 = Vector3, CFrame, Color3
	world.newSignal = newSignal
	world.services = services
	world.task = task
	world.deepcopy = deepcopy
	return world
end

return M
