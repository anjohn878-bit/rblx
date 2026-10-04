-- Build a Marble Run: server
-- Owns plots, validates building, runs marbles, pays out coins and saves progress.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")

local Shared = ReplicatedStorage:WaitForChild("MarbleRun")
local Config = require(Shared:WaitForChild("Config"))
local Pieces = require(Shared:WaitForChild("Pieces"))

local LH = Config.LEVEL_HEIGHT

---------------------------------------------------------------------------
-- Remotes
---------------------------------------------------------------------------

local remotes = Instance.new("Folder")
remotes.Name = "MarbleRunRemotes"

local function remote(className: string, name: string): any
	local r = Instance.new(className)
	r.Name = name
	r.Parent = remotes
	return r
end

local PlaceFn: RemoteFunction = remote("RemoteFunction", "PlacePiece")
local DeleteFn: RemoteFunction = remote("RemoteFunction", "DeletePiece")
local ClearFn: RemoteFunction = remote("RemoteFunction", "ClearPlot")
local DropEvent: RemoteEvent = remote("RemoteEvent", "DropMarble")
local NotifyEvent: RemoteEvent = remote("RemoteEvent", "Notify")
local MarbleEvent: RemoteEvent = remote("RemoteEvent", "MarbleState")
remotes.Parent = ReplicatedStorage

---------------------------------------------------------------------------
-- Plots
---------------------------------------------------------------------------

type PieceRecord = { id: string, t: string, x: number, z: number, l: number, r: number, model: Model }

type Plot = {
	index: number,
	origin: Vector3,
	folder: Model,
	piecesFolder: Folder,
	sign: TextLabel,
	spawnCf: CFrame,
	owner: Player?,
	pieces: { [string]: PieceRecord },
	count: number,
}

local plotsFolder = Instance.new("Folder")
plotsFolder.Name = "Plots"
plotsFolder.Parent = workspace

local plots: { Plot } = {}
local plotOf: { [Player]: Plot } = {}

local SIZE = Config.GRID * Config.CELL

local function makePlot(index: number, origin: Vector3): Plot
	local folder = Instance.new("Model")
	folder.Name = "Plot" .. index
	folder:SetAttribute("PlotIndex", index)
	folder:SetAttribute("OwnerId", 0)

	local floor = Instance.new("Part")
	floor.Name = "PlotFloor"
	floor.Anchored = true
	floor.Size = Vector3.new(SIZE, 1, SIZE)
	floor.CFrame = CFrame.new(origin + Vector3.new(SIZE / 2, -0.45, SIZE / 2))
	floor.Color = Color3.fromRGB(46, 52, 64)
	floor.Material = Enum.Material.SmoothPlastic
	floor.TopSurface = Enum.SurfaceType.Smooth
	floor.Parent = folder

	for i = 0, Config.GRID do
		for _, axis in { "x", "z" } do
			local line = Instance.new("Part")
			line.Name = "GridLine"
			line.Anchored = true
			line.CanCollide = false
			line.CanQuery = false
			line.CanTouch = false
			line.Material = Enum.Material.Neon
			line.Color = Color3.fromRGB(90, 110, 140)
			line.Transparency = 0.5
			if axis == "x" then
				line.Size = Vector3.new(0.12, 0.05, SIZE)
				line.CFrame = CFrame.new(origin + Vector3.new(i * Config.CELL, 0.07, SIZE / 2))
			else
				line.Size = Vector3.new(SIZE, 0.05, 0.12)
				line.CFrame = CFrame.new(origin + Vector3.new(SIZE / 2, 0.07, i * Config.CELL))
			end
			line.Parent = folder
		end
	end

	local tower, spawnCf = Pieces.BuildStartTower(origin)
	tower.Parent = folder

	local signPart = Instance.new("Part")
	signPart.Name = "SignAnchor"
	signPart.Anchored = true
	signPart.CanCollide = false
	signPart.CanQuery = false
	signPart.CanTouch = false
	signPart.Transparency = 1
	signPart.Size = Vector3.new(1, 1, 1)
	signPart.CFrame = CFrame.new(origin + Vector3.new(SIZE / 2, Config.START_LEVEL * LH + 14, SIZE / 2))
	signPart.Parent = folder
	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromScale(40, 6)
	billboard.LightInfluence = 0
	billboard.MaxDistance = 400
	billboard.Parent = signPart
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.3
	label.Text = "Empty Plot"
	label.Parent = billboard

	local piecesFolder = Instance.new("Folder")
	piecesFolder.Name = "Pieces"
	piecesFolder.Parent = folder

	folder.Parent = plotsFolder

	return {
		index = index,
		origin = origin,
		folder = folder,
		piecesFolder = piecesFolder,
		sign = label,
		spawnCf = spawnCf,
		owner = nil,
		pieces = {},
		count = 0,
	}
end

for i, origin in Config.PLOT_ORIGINS do
	plots[i] = makePlot(i, origin)
end

-- Where a player stands when they spawn: in front of the plot edge facing the lobby.
local function standCFrame(plot: Plot): CFrame
	local o = plot.origin
	local centre = o + Vector3.new(SIZE / 2, 0, SIZE / 2)
	local z = if centre.Z < 0 then o.Z + SIZE + 6 else o.Z - 6
	local pos = Vector3.new(centre.X, o.Y + 4, z)
	return CFrame.lookAt(pos, Vector3.new(centre.X, pos.Y, centre.Z))
end

---------------------------------------------------------------------------
-- Player data
---------------------------------------------------------------------------

type SavedPiece = { t: string, x: number, z: number, l: number, r: number }
type Data = { coins: number, best: number, pieces: { SavedPiece } }

local store: DataStore? = nil
do
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(Config.DATASTORE_NAME)
	end)
	if ok then
		store = result
	else
		warn("[MarbleRun] DataStore unavailable, progress will not save:", result)
	end
end

local dataOf: { [Player]: Data } = {}
local canSave: { [Player]: boolean } = {}
local statsOf: { [Player]: { coins: IntValue, best: IntValue } } = {}

local function loadData(player: Player): (Data, boolean)
	local default: Data = { coins = Config.START_COINS, best = 0, pieces = {} }
	if not store then
		return default, false
	end
	for attempt = 1, 3 do
		local ok, result = pcall(function()
			return (store :: DataStore):GetAsync("player_" .. player.UserId)
		end)
		if ok then
			if type(result) == "table" then
				return {
					coins = tonumber(result.coins) or Config.START_COINS,
					best = tonumber(result.best) or 0,
					pieces = if type(result.pieces) == "table" then result.pieces else {},
				}, true
			end
			return default, true
		end
		warn("[MarbleRun] Load failed (attempt " .. attempt .. "):", result)
		task.wait(attempt)
	end
	-- Don't save over data we failed to read.
	return default, false
end

local function saveData(player: Player)
	local data = dataOf[player]
	if not store or not data or not canSave[player] then
		return
	end
	local plot = plotOf[player]
	local saved: { SavedPiece } = {}
	if plot then
		for _, rec in plot.pieces do
			table.insert(saved, { t = rec.t, x = rec.x, z = rec.z, l = rec.l, r = rec.r })
		end
	end
	data.pieces = saved
	local ok, err = pcall(function()
		(store :: DataStore):SetAsync("player_" .. player.UserId, {
			coins = data.coins,
			best = data.best,
			pieces = saved,
		})
	end)
	if not ok then
		warn("[MarbleRun] Save failed for " .. player.Name .. ":", err)
	end
end

local function setCoins(player: Player, coins: number)
	local data = dataOf[player]
	if not data then
		return
	end
	data.coins = coins
	local s = statsOf[player]
	if s then
		s.coins.Value = coins
	end
end

local function notify(player: Player, text: string, kind: string?)
	NotifyEvent:FireClient(player, text, kind or "info")
end

---------------------------------------------------------------------------
-- Building
---------------------------------------------------------------------------

local function isInt(n: any): boolean
	return type(n) == "number" and n == n and math.floor(n) == n
end

-- Returns nil if the placement is legal, otherwise a reason.
local function checkPlacement(plot: Plot, t: string, x: number, z: number, l: number, r: number): string?
	local def = Pieces.Defs[t]
	if not def then
		return "Unknown piece."
	end
	if not (isInt(x) and isInt(z) and isInt(l) and isInt(r)) then
		return "Bad position."
	end
	if x < 0 or z < 0 or x >= Config.GRID or z >= Config.GRID then
		return "That's outside your plot."
	end
	if r < 0 or r > 3 then
		return "Bad rotation."
	end
	if x == Config.START_CELL.X and z == Config.START_CELL.Y then
		return "The start tower is there."
	end
	if l < Config.MIN_LEVEL or l + def.drop > Config.MAX_LEVEL then
		return "Too high or too low."
	end
	local lo, hi = Pieces.verticalSpan(t, l)
	if lo < 0 then
		return "Too close to the ground. Raise it up (E)."
	end
	if plot.count >= Config.MAX_PIECES then
		return "Your plot is full (" .. Config.MAX_PIECES .. " pieces)."
	end
	local sameType = 0
	for _, rec in plot.pieces do
		if rec.t == t then
			sameType += 1
		end
		if rec.x == x and rec.z == z then
			local lo2, hi2 = Pieces.verticalSpan(rec.t, rec.l)
			-- Leave headroom for the marble above each piece.
			if lo < hi2 + Config.MARBLE_SIZE and lo2 < hi + Config.MARBLE_SIZE then
				return "Something is already there."
			end
		end
	end
	if def.maxPerPlot and sameType >= def.maxPerPlot then
		return "You can only have " .. def.maxPerPlot .. " " .. def.name .. "."
	end
	return nil
end

local function addPiece(plot: Plot, t: string, x: number, z: number, l: number, r: number): PieceRecord
	local id = HttpService:GenerateGUID(false)
	local model = Pieces.Build(t, Pieces.pieceCFrame(plot.origin, x, z, l, r))
	model.Name = t
	model:SetAttribute("PieceId", id)
	model:SetAttribute("Type", t)
	model:SetAttribute("CX", x)
	model:SetAttribute("CZ", z)
	model:SetAttribute("Level", l)
	model:SetAttribute("Rot", r)
	model.Parent = plot.piecesFolder
	local rec = { id = id, t = t, x = x, z = z, l = l, r = r, model = model }
	plot.pieces[id] = rec
	plot.count += 1
	return rec
end

local function removePiece(plot: Plot, id: string): PieceRecord?
	local rec = plot.pieces[id]
	if not rec then
		return nil
	end
	plot.pieces[id] = nil
	plot.count -= 1
	rec.model:Destroy()
	return rec
end

PlaceFn.OnServerInvoke = function(player: Player, t: any, x: any, z: any, l: any, r: any)
	local plot = plotOf[player]
	local data = dataOf[player]
	if not plot or not data then
		return false, "You don't have a plot."
	end
	if type(t) ~= "string" then
		return false, "Unknown piece."
	end
	local reason = checkPlacement(plot, t, x, z, l, r)
	if reason then
		return false, reason
	end
	local price = Pieces.Defs[t].price
	if data.coins < price then
		return false, "Not enough coins! Drop marbles into your Goal to earn more."
	end
	setCoins(player, data.coins - price)
	addPiece(plot, t, x, z, l, r)
	return true, nil
end

DeleteFn.OnServerInvoke = function(player: Player, id: any)
	local plot = plotOf[player]
	local data = dataOf[player]
	if not plot or not data or type(id) ~= "string" then
		return false
	end
	local rec = removePiece(plot, id)
	if not rec then
		return false
	end
	setCoins(player, data.coins + Pieces.Defs[rec.t].price)
	return true
end

ClearFn.OnServerInvoke = function(player: Player)
	local plot = plotOf[player]
	local data = dataOf[player]
	if not plot or not data then
		return false
	end
	local refund = 0
	for id, rec in plot.pieces do
		refund += Pieces.Defs[rec.t].price
		removePiece(plot, id)
	end
	setCoins(player, data.coins + refund)
	return true
end

---------------------------------------------------------------------------
-- Marbles
---------------------------------------------------------------------------

type Run = {
	marble: Part,
	plot: Plot,
	started: number,
	touched: { [string]: boolean },
	touchedCount: number,
	chimes: { [string]: boolean },
	bonus: number,
	slowSince: number?,
	boostDebounce: { [string]: number },
	finished: boolean,
}

local runs: { [Player]: Run } = {}
local lastDrop: { [Player]: number } = {}

local MARBLE_COLORS = {
	Color3.fromRGB(255, 80, 80),
	Color3.fromRGB(80, 170, 255),
	Color3.fromRGB(90, 230, 120),
	Color3.fromRGB(255, 210, 60),
	Color3.fromRGB(200, 110, 255),
	Color3.fromRGB(255, 140, 200),
}

local function playSound(parent: Instance, id: string, speed: number, volume: number)
	local s = Instance.new("Sound")
	s.SoundId = id
	s.PlaybackSpeed = speed
	s.Volume = volume
	s.Parent = parent
	s:Play()
	task.delay(3, function()
		s:Destroy()
	end)
end

local function endRun(player: Player, success: boolean, reason: string?)
	local run = runs[player]
	if not run or run.finished then
		return
	end
	run.finished = true
	runs[player] = nil
	local marble = run.marble
	MarbleEvent:FireClient(player, nil, if success then "finished" else "lost")

	if success then
		local data = dataOf[player]
		local elapsed = os.clock() - run.started
		local reward = Config.REWARD_BASE
			+ run.touchedCount * Config.REWARD_PER_PIECE
			+ math.floor(elapsed * Config.REWARD_PER_SECOND)
			+ run.bonus
		if data then
			setCoins(player, data.coins + reward)
			if run.touchedCount > data.best then
				data.best = run.touchedCount
				local s = statsOf[player]
				if s then
					s.best.Value = run.touchedCount
				end
			end
		end
		notify(
			player,
			string.format("GOAL! +%d coins  (%d pieces, %.1fs)", reward, run.touchedCount, elapsed),
			"success"
		)
		task.delay(1.5, function()
			marble:Destroy()
		end)
	else
		notify(player, reason or "Marble lost!", "error")
		marble:Destroy()
	end
end

local function onMarbleTouched(player: Player, run: Run, hit: BasePart)
	if run.finished then
		return
	end
	local model = hit.Parent
	if not model or not model:IsA("Model") or model.Parent ~= run.plot.piecesFolder then
		if hit.Name == "PlotFloor" or hit == workspace:FindFirstChild("Baseplate") then
			endRun(player, false, "Your marble hit the ground!")
		end
		return
	end
	local id = model:GetAttribute("PieceId")
	if type(id) ~= "string" then
		return
	end
	if not run.touched[id] then
		run.touched[id] = true
		run.touchedCount += 1
	end

	if hit.Name == "BoostPad" then
		local now = os.clock()
		if (run.boostDebounce[id] or 0) > now then
			return
		end
		run.boostDebounce[id] = now + 0.4
		local look = model:GetPivot().LookVector
		local v = run.marble.AssemblyLinearVelocity
		local along = math.max(v:Dot(look), Config.BOOST_SPEED)
		run.marble.AssemblyLinearVelocity = look * along + Vector3.new(0, v.Y, 0)
		playSound(run.marble, "rbxasset://sounds/swoosh.wav", 1.2, 0.6)
	elseif hit.Name == "Chime" then
		if not run.chimes[id] then
			run.chimes[id] = true
			run.bonus += Config.CHIME_BONUS
			local bell = model:FindFirstChild("Bell")
			local level = model:GetAttribute("Level") or 0
			playSound(bell or hit, "rbxasset://sounds/electronicpingshort.wav", 0.8 + (level % 12) / 12, 0.8)
		end
	elseif hit.Name == "GoalSensor" then
		local confetti = hit:FindFirstChild("Confetti")
		if confetti and confetti:IsA("ParticleEmitter") then
			confetti:Emit(60)
		end
		endRun(player, true)
	end
end

DropEvent.OnServerEvent:Connect(function(player: Player)
	local plot = plotOf[player]
	if not plot then
		return
	end
	local now = os.clock()
	if (lastDrop[player] or 0) + 1 > now then
		return
	end
	lastDrop[player] = now
	if runs[player] then
		endRun(player, false, "Marble reset.")
	end

	local marble = Instance.new("Part")
	marble.Name = player.Name .. "Marble"
	marble.Shape = Enum.PartType.Ball
	marble.Size = Vector3.one * Config.MARBLE_SIZE
	marble.Color = MARBLE_COLORS[math.random(#MARBLE_COLORS)]
	marble.Material = Enum.Material.Glass
	marble.Reflectance = 0.2
	marble.CustomPhysicalProperties = PhysicalProperties.new(2, 0.3, 0.15, 1, 1)
	marble.CFrame = plot.spawnCf
	marble.TopSurface = Enum.SurfaceType.Smooth
	marble.BottomSurface = Enum.SurfaceType.Smooth

	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, 0.5, 0)
	a0.Parent = marble
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, -0.5, 0)
	a1.Parent = marble
	local trail = Instance.new("Trail")
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Lifetime = 0.4
	trail.Color = ColorSequence.new(marble.Color)
	trail.Transparency = NumberSequence.new(0.3, 1)
	trail.LightEmission = 0.6
	trail.FaceCamera = true
	trail.Parent = marble

	local light = Instance.new("PointLight")
	light.Color = marble.Color
	light.Range = 8
	light.Brightness = 1.5
	light.Parent = marble

	marble.Parent = workspace
	marble:SetNetworkOwner(nil)
	marble.AssemblyLinearVelocity = plot.spawnCf.LookVector * 4

	local run: Run = {
		marble = marble,
		plot = plot,
		started = now,
		touched = {},
		touchedCount = 0,
		chimes = {},
		bonus = 0,
		slowSince = nil,
		boostDebounce = {},
		finished = false,
	}
	runs[player] = run
	marble.Touched:Connect(function(hit)
		onMarbleTouched(player, run, hit)
	end)
	MarbleEvent:FireClient(player, marble, "dropped")
end)

RunService.Heartbeat:Connect(function()
	local now = os.clock()
	for player, run in runs do
		local marble = run.marble
		if not marble.Parent then
			endRun(player, false)
			continue
		end
		local v = marble.AssemblyLinearVelocity
		local speed = v.Magnitude
		if speed > Config.MARBLE_MAX_SPEED then
			marble.AssemblyLinearVelocity = v * (Config.MARBLE_MAX_SPEED / speed)
		end
		if speed < Config.MARBLE_STUCK_SPEED then
			run.slowSince = run.slowSince or now
			if now - (run.slowSince :: number) > Config.MARBLE_STUCK_TIME then
				endRun(player, false, "Your marble got stuck!")
				continue
			end
		else
			run.slowSince = nil
		end
		if now - run.started > Config.MARBLE_TIMEOUT then
			endRun(player, false, "Your marble ran out of time!")
		elseif marble.Position.Y < run.plot.origin.Y - 20 then
			endRun(player, false, "Your marble fell off the world!")
		end
	end
end)

---------------------------------------------------------------------------
-- Players
---------------------------------------------------------------------------

local function claimPlot(player: Player): Plot?
	for _, plot in plots do
		if not plot.owner then
			plot.owner = player
			plot.folder:SetAttribute("OwnerId", player.UserId)
			plot.sign.Text = player.DisplayName .. "'s Marble Run"
			plotOf[player] = plot
			player:SetAttribute("PlotIndex", plot.index)
			return plot
		end
	end
	return nil
end

local function releasePlot(player: Player)
	local plot = plotOf[player]
	if not plot then
		return
	end
	for id in plot.pieces do
		removePiece(plot, id)
	end
	plot.owner = nil
	plot.folder:SetAttribute("OwnerId", 0)
	plot.sign.Text = "Empty Plot"
	plotOf[player] = nil
end

local function onPlayerAdded(player: Player)
	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	local coins = Instance.new("IntValue")
	coins.Name = "Coins"
	coins.Parent = leaderstats
	local best = Instance.new("IntValue")
	best.Name = "Best Run"
	best.Parent = leaderstats
	leaderstats.Parent = player
	statsOf[player] = { coins = coins, best = best }

	local plot = claimPlot(player)

	player.CharacterAdded:Connect(function(character)
		local p = plotOf[player]
		if p then
			local root = character:WaitForChild("HumanoidRootPart", 10) :: BasePart?
			if root then
				task.wait()
				character:PivotTo(standCFrame(p))
			end
		end
	end)

	local data, ok = loadData(player)
	if not player.Parent then
		return
	end
	dataOf[player] = data
	canSave[player] = ok
	coins.Value = data.coins
	best.Value = data.best

	if plot then
		-- Rebuild the saved run. Invalid entries (e.g. after a layout change) are skipped.
		for _, sp in data.pieces do
			if type(sp) == "table" and type(sp.t) == "string" then
				if checkPlacement(plot, sp.t, sp.x, sp.z, sp.l, sp.r) == nil then
					addPiece(plot, sp.t, sp.x, sp.z, sp.l, sp.r)
				end
			end
		end
		notify(player, "Welcome! Build a track from the start tower to a Goal, then press Drop Marble.", "info")
	else
		notify(player, "All plots are taken. You can watch other players' runs!", "error")
	end
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in Players:GetPlayers() do
	task.spawn(onPlayerAdded, player)
end

Players.PlayerRemoving:Connect(function(player)
	local run = runs[player]
	if run then
		run.finished = true
		runs[player] = nil
		run.marble:Destroy()
	end
	saveData(player)
	releasePlot(player)
	dataOf[player] = nil
	canSave[player] = nil
	statsOf[player] = nil
	lastDrop[player] = nil
end)

-- Autosave every few minutes.
task.spawn(function()
	while true do
		task.wait(180)
		for _, player in Players:GetPlayers() do
			task.spawn(saveData, player)
		end
	end
end)

game:BindToClose(function()
	if RunService:IsStudio() and not store then
		return
	end
	local pending = 0
	for _, player in Players:GetPlayers() do
		pending += 1
		task.spawn(function()
			saveData(player)
			pending -= 1
		end)
	end
	local deadline = os.clock() + 25
	while pending > 0 and os.clock() < deadline do
		task.wait(0.1)
	end
end)
