-- Build a Marble Run: client
-- Build UI, ghost previews with auto-snapping, delete mode and marble follow camera.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local Shared = ReplicatedStorage:WaitForChild("MarbleRun")
local Config = require(Shared:WaitForChild("Config"))
local Pieces = require(Shared:WaitForChild("Pieces"))
local Remotes = ReplicatedStorage:WaitForChild("MarbleRunRemotes")
local PlaceFn = Remotes:WaitForChild("PlacePiece")
local DeleteFn = Remotes:WaitForChild("DeletePiece")
local ClearFn = Remotes:WaitForChild("ClearPlot")
local DropEvent = Remotes:WaitForChild("DropMarble")
local NotifyEvent = Remotes:WaitForChild("Notify")
local MarbleEvent = Remotes:WaitForChild("MarbleState")

local LH = Config.LEVEL_HEIGHT
local CELL = Config.CELL
local SIZE = Config.GRID * CELL

---------------------------------------------------------------------------
-- State
---------------------------------------------------------------------------

local selected: string? = nil -- piece type being placed
local deleteMode = false
local followCam = true
local rot = 0
local workLevel = Config.START_LEVEL -- height (in levels) where the next piece's entry should sit
local pointer: Vector2? = nil
local busy = false

local plot: Model? = nil
local origin: Vector3? = nil

---------------------------------------------------------------------------
-- UI helpers
---------------------------------------------------------------------------

local function make(className: string, props: { [string]: any }, children: { Instance }?): any
	local inst = Instance.new(className)
	for k, v in props do
		if k ~= "Parent" then
			(inst :: any)[k] = v
		end
	end
	for _, child in children or {} do
		child.Parent = inst
	end
	if props.Parent then
		inst.Parent = props.Parent
	end
	return inst
end

local function corner(r: number)
	return make("UICorner", { CornerRadius = UDim.new(0, r) })
end

local function stroke(color: Color3, thickness: number)
	return make("UIStroke", { Color = color, Thickness = thickness, ApplyStrokeMode = Enum.ApplyStrokeMode.Border })
end

local gui = make("ScreenGui", {
	Name = "MarbleRunGui",
	ResetOnSpawn = false,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	Parent = player:WaitForChild("PlayerGui"),
})

local uiScales = {}
local function scaled(frame: GuiObject)
	local s = make("UIScale", { Parent = frame })
	table.insert(uiScales, s)
end

local function updateScale()
	local w = camera.ViewportSize.X
	local s = math.clamp(w / 1000, 0.55, 1)
	for _, scale in uiScales do
		scale.Scale = s
	end
end

-- Coins pill
local coinsLabel = make("TextLabel", {
	Name = "Coins",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 8),
	Size = UDim2.fromOffset(200, 44),
	BackgroundColor3 = Color3.fromRGB(30, 30, 40),
	BackgroundTransparency = 0.15,
	Font = Enum.Font.FredokaOne,
	TextSize = 26,
	TextColor3 = Color3.fromRGB(255, 215, 60),
	Text = "🪙 0",
	Parent = gui,
}, { corner(22), stroke(Color3.fromRGB(255, 215, 60), 2) })
scaled(coinsLabel)

-- Toasts
local toastHolder = make("Frame", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 62),
	Size = UDim2.fromOffset(600, 200),
	BackgroundTransparency = 1,
	Parent = gui,
}, {
	make("UIListLayout", {
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}),
})
scaled(toastHolder)

local TOAST_COLORS = {
	info = Color3.fromRGB(60, 120, 220),
	success = Color3.fromRGB(40, 170, 90),
	error = Color3.fromRGB(210, 60, 70),
}

local toastOrder = 0
local function toast(text: string, kind: string?)
	toastOrder += 1
	local label = make("TextLabel", {
		Size = UDim2.fromOffset(560, 40),
		LayoutOrder = toastOrder,
		BackgroundColor3 = TOAST_COLORS[kind or "info"] or TOAST_COLORS.info,
		Font = Enum.Font.GothamBold,
		TextSize = 18,
		TextWrapped = true,
		TextColor3 = Color3.new(1, 1, 1),
		Text = text,
		Parent = toastHolder,
	}, { corner(10) })
	task.delay(3.5, function()
		local info = TweenInfo.new(0.5)
		TweenService:Create(label, info, { BackgroundTransparency = 1, TextTransparency = 1 }):Play()
		task.wait(0.5)
		label:Destroy()
	end)
end

NotifyEvent.OnClientEvent:Connect(toast)

-- Hotbar
local hotbar = make("Frame", {
	Name = "Hotbar",
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -12),
	Size = UDim2.fromOffset(#Pieces.Order * 86 + 12, 100),
	BackgroundColor3 = Color3.fromRGB(25, 25, 35),
	BackgroundTransparency = 0.25,
	Parent = gui,
}, {
	corner(14),
	make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}),
})
scaled(hotbar)

local pieceButtons: { [string]: TextButton } = {}

-- Build info bar (shown while placing)
local buildBar = make("Frame", {
	Name = "BuildBar",
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -122),
	Size = UDim2.fromOffset(560, 46),
	BackgroundColor3 = Color3.fromRGB(25, 25, 35),
	BackgroundTransparency = 0.25,
	Visible = false,
	Parent = gui,
}, {
	corner(12),
	make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}),
})
scaled(buildBar)

local function smallButton(parent: Instance, text: string, order: number, width: number, color: Color3): TextButton
	return make("TextButton", {
		Size = UDim2.fromOffset(width, 36),
		LayoutOrder = order,
		BackgroundColor3 = color,
		Font = Enum.Font.GothamBold,
		TextSize = 16,
		TextColor3 = Color3.new(1, 1, 1),
		Text = text,
		AutoButtonColor = true,
		Parent = parent,
	}, { corner(8) })
end

local downBtn = smallButton(buildBar, "▼ Q", 1, 64, Color3.fromRGB(70, 80, 110))
local levelLabel = make("TextLabel", {
	Size = UDim2.fromOffset(150, 36),
	LayoutOrder = 2,
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	TextSize = 16,
	TextColor3 = Color3.new(1, 1, 1),
	Text = "Height 40",
	Parent = buildBar,
})
local upBtn = smallButton(buildBar, "▲ E", 3, 64, Color3.fromRGB(70, 80, 110))
local rotBtn = smallButton(buildBar, "⟳ Rotate (R)", 4, 120, Color3.fromRGB(70, 80, 110))
local cancelBtn = smallButton(buildBar, "✕ Done", 5, 90, Color3.fromRGB(150, 60, 70))

-- Side panel
local side = make("Frame", {
	Name = "Side",
	AnchorPoint = Vector2.new(1, 0.5),
	Position = UDim2.new(1, -12, 0.5, 0),
	Size = UDim2.fromOffset(170, 260),
	BackgroundTransparency = 1,
	Parent = gui,
}, {
	make("UIListLayout", {
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		VerticalAlignment = Enum.VerticalAlignment.Center,
	}),
})
scaled(side)

local function sideButton(text: string, order: number, color: Color3, height: number?): TextButton
	return make("TextButton", {
		Size = UDim2.fromOffset(170, height or 48),
		LayoutOrder = order,
		BackgroundColor3 = color,
		Font = Enum.Font.FredokaOne,
		TextSize = 20,
		TextColor3 = Color3.new(1, 1, 1),
		Text = text,
		Parent = side,
	}, { corner(12), stroke(Color3.new(0, 0, 0), 1.5) })
end

local dropBtn = sideButton("🔮 Drop Marble (F)", 1, Color3.fromRGB(40, 180, 90), 70)
dropBtn.TextWrapped = true
local deleteBtn = sideButton("🗑 Delete (X)", 2, Color3.fromRGB(120, 60, 70))
local followBtn = sideButton("🎥 Follow: ON", 3, Color3.fromRGB(70, 90, 140))
local clearBtn = sideButton("💥 Clear Plot", 4, Color3.fromRGB(90, 60, 60))

local hint = make("TextLabel", {
	AnchorPoint = Vector2.new(0, 1),
	Position = UDim2.new(0, 12, 1, -12),
	Size = UDim2.fromOffset(330, 120),
	BackgroundTransparency = 1,
	Font = Enum.Font.Gotham,
	TextSize = 14,
	TextColor3 = Color3.new(1, 1, 1),
	TextStrokeTransparency = 0.5,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextYAlignment = Enum.TextYAlignment.Bottom,
	TextWrapped = true,
	Text = "Pick a piece below (1-8) and click to place it.\n"
		.. "Pieces auto-snap to the end of your track.\n"
		.. "R rotate • Q/E height • X delete • F drop marble\n"
		.. "Finish in a Goal cup to earn coins!",
	Parent = gui,
})
scaled(hint)

---------------------------------------------------------------------------
-- Plot lookup
---------------------------------------------------------------------------

local function refreshPlot()
	local index = player:GetAttribute("PlotIndex")
	if type(index) == "number" then
		plot = workspace:WaitForChild("Plots"):WaitForChild("Plot" .. index) :: Model
		origin = Config.PLOT_ORIGINS[index]
	end
end
refreshPlot()
player:GetAttributeChangedSignal("PlotIndex"):Connect(refreshPlot)

local function myCoins(): number
	local ls = player:FindFirstChild("leaderstats")
	local c = ls and ls:FindFirstChild("Coins")
	return if c then (c :: IntValue).Value else 0
end

---------------------------------------------------------------------------
-- Piece index (for snapping and validity)
---------------------------------------------------------------------------

type Info = { t: string, x: number, z: number, l: number, r: number, model: Model? }

local function cellKey(x: number, z: number): string
	return x .. "," .. z
end

local function placedPieces(): { Info }
	local list: { Info } = {}
	local folder = plot and plot:FindFirstChild("Pieces")
	if not folder then
		return list
	end
	for _, m in folder:GetChildren() do
		local t = m:GetAttribute("Type")
		if t then
			table.insert(list, {
				t = t,
				x = m:GetAttribute("CX"),
				z = m:GetAttribute("CZ"),
				l = m:GetAttribute("Level"),
				r = m:GetAttribute("Rot"),
				model = m,
			})
		end
	end
	return list
end

-- Cached index of exits that lead into each cell, rebuilt when pieces change.
local exitsInto: { [string]: { { dir: Vector2, level: number } } } = {}
local occupants: { [string]: { Info } } = {}
local indexDirty = true

local function rebuildIndex()
	exitsInto = {}
	occupants = {}
	local function addExit(x: number, z: number, dir: Vector2, level: number)
		local key = cellKey(x + dir.X, z + dir.Y)
		exitsInto[key] = exitsInto[key] or {}
		table.insert(exitsInto[key], { dir = dir, level = level })
	end
	addExit(Config.START_CELL.X, Config.START_CELL.Y, Pieces.entryDir(Config.START_ROT), Config.START_LEVEL)
	for _, info in placedPieces() do
		local dir, level = Pieces.exitInfo(info.t, info.r, info.l)
		if dir then
			addExit(info.x, info.z, dir, level)
		end
		local key = cellKey(info.x, info.z)
		occupants[key] = occupants[key] or {}
		table.insert(occupants[key], info)
	end
	indexDirty = false
end

local function watchPieces()
	if not plot then
		return
	end
	local folder = plot:WaitForChild("Pieces")
	folder.ChildAdded:Connect(function()
		indexDirty = true
	end)
	folder.ChildRemoved:Connect(function()
		indexDirty = true
	end)
end
task.spawn(watchPieces)
player:GetAttributeChangedSignal("PlotIndex"):Connect(function()
	indexDirty = true
	task.spawn(watchPieces)
end)

-- Mirrors the server's placement rules so the ghost can show red/green.
local function placementProblem(t: string, x: number, z: number, l: number): string?
	local def = Pieces.Defs[t]
	if x < 0 or z < 0 or x >= Config.GRID or z >= Config.GRID then
		return "outside"
	end
	if x == Config.START_CELL.X and z == Config.START_CELL.Y then
		return "start"
	end
	if l < Config.MIN_LEVEL or l + def.drop > Config.MAX_LEVEL then
		return "height"
	end
	local lo, hi = Pieces.verticalSpan(t, l)
	if lo < 0 then
		return "ground"
	end
	for _, info in occupants[cellKey(x, z)] or {} do
		local lo2, hi2 = Pieces.verticalSpan(info.t, info.l)
		if lo < hi2 + Config.MARBLE_SIZE and lo2 < hi + Config.MARBLE_SIZE then
			return "blocked"
		end
	end
	if def.maxPerPlot then
		local n = 0
		for _, list in occupants do
			for _, info in list do
				if info.t == t then
					n += 1
				end
			end
		end
		if n >= def.maxPerPlot then
			return "limit"
		end
	end
	if myCoins() < def.price then
		return "coins"
	end
	return nil
end

---------------------------------------------------------------------------
-- Ghost preview
---------------------------------------------------------------------------

local ghost: Model? = nil
local ghostType: string? = nil
local ghostKey = ""
-- Highlights adorn their parent, so they are only ever parented to the model they mark.
local ghostHighlight = make("Highlight", {
	FillTransparency = 0.5,
	OutlineTransparency = 0,
	DepthMode = Enum.HighlightDepthMode.AlwaysOnTop,
})
local deleteHighlight = make("Highlight", {
	FillColor = Color3.fromRGB(255, 50, 50),
	OutlineColor = Color3.fromRGB(255, 255, 255),
	FillTransparency = 0.3,
	DepthMode = Enum.HighlightDepthMode.AlwaysOnTop,
})

local levelPlane = make("Part", {
	Name = "LevelPlane",
	Anchored = true,
	CanCollide = false,
	CanQuery = false,
	CanTouch = false,
	CastShadow = false,
	Material = Enum.Material.ForceField,
	Color = Color3.fromRGB(120, 200, 255),
	Transparency = 0.2,
	Size = Vector3.new(SIZE, 0.05, SIZE),
})

local current: { t: string, x: number, z: number, l: number, r: number, ok: boolean, reason: string? }? = nil

local function clearGhost()
	ghostHighlight.Parent = nil
	if ghost then
		ghost:Destroy()
		ghost = nil
	end
	ghostType = nil
	ghostKey = ""
	current = nil
end

local function makeGhost(t: string, cf: CFrame)
	clearGhost()
	local m = Pieces.Build(t, cf)
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.CastShadow = false
			d.Transparency = math.max(d.Transparency, 0.4)
		elseif d:IsA("ParticleEmitter") then
			d:Destroy()
		end
	end
	m.Parent = workspace
	ghost = m
	ghostType = t
	ghostHighlight.Parent = m
end

local function pointerRay(): Ray?
	if not pointer then
		return nil
	end
	return camera:ScreenPointToRay(pointer.X, pointer.Y)
end

local REASONS = {
	outside = "That's outside your plot.",
	start = "The start tower is there.",
	height = "Too high or too low.",
	ground = "Too close to the ground. Raise it up (E).",
	blocked = "Something is already there.",
	limit = "You already have one of those.",
	coins = "Not enough coins!",
}

local function updateGhost()
	if not selected or not origin then
		clearGhost()
		return
	end
	local ray = pointerRay()
	if not ray then
		clearGhost()
		return
	end
	-- Intersect the pointer ray with the horizontal plane at the working height.
	local planeY = origin.Y + workLevel * LH
	if math.abs(ray.Direction.Y) < 1e-4 then
		clearGhost()
		return
	end
	local t = (planeY - ray.Origin.Y) / ray.Direction.Y
	if t < 0 then
		clearGhost()
		return
	end
	local hitPos = ray.Origin + ray.Direction * t
	local x = math.floor((hitPos.X - origin.X) / CELL)
	local z = math.floor((hitPos.Z - origin.Z) / CELL)
	if x < 0 or z < 0 or x >= Config.GRID or z >= Config.GRID then
		clearGhost()
		return
	end

	local def = Pieces.Defs[selected]
	local r = rot
	local level = workLevel - def.drop
	-- Snap to an exit that leads into this cell (prefer the one nearest the working height).
	local best, bestDist = nil, math.huge
	for _, ex in exitsInto[cellKey(x, z)] or {} do
		local d = math.abs(ex.level - workLevel)
		if d < bestDist then
			best, bestDist = ex, d
		end
	end
	if best then
		for candidate = 0, 3 do
			if Pieces.entryDir(candidate) == best.dir then
				r = candidate
				break
			end
		end
		level = best.level - def.drop
	end

	local reason = placementProblem(selected, x, z, level)
	local key = table.concat({ selected, x, z, level, r }, ":")
	if key ~= ghostKey or not ghost then
		makeGhost(selected, Pieces.pieceCFrame(origin, x, z, level, r))
		ghostKey = key
	end
	current = { t = selected, x = x, z = z, l = level, r = r, ok = reason == nil, reason = reason }
	if reason then
		ghostHighlight.FillColor = Color3.fromRGB(255, 60, 60)
		ghostHighlight.OutlineColor = Color3.fromRGB(255, 150, 150)
	else
		ghostHighlight.FillColor = Color3.fromRGB(60, 255, 120)
		ghostHighlight.OutlineColor = Color3.fromRGB(200, 255, 220)
	end
end

local hoveredDelete: Model? = nil
local function updateDelete()
	hoveredDelete = nil
	deleteHighlight.Parent = nil
	if not deleteMode or not plot then
		return
	end
	local ray = pointerRay()
	if not ray then
		return
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { plot:FindFirstChild("Pieces") }
	local result = workspace:Raycast(ray.Origin, ray.Direction * 1000, params)
	if result then
		local m = result.Instance:FindFirstAncestorWhichIsA("Model")
		if m and m:GetAttribute("PieceId") then
			hoveredDelete = m
			deleteHighlight.Parent = m
		end
	end
end

---------------------------------------------------------------------------
-- Mode switching
---------------------------------------------------------------------------

local function refreshButtons()
	for t, btn in pieceButtons do
		local outline = btn:FindFirstChildOfClass("UIStroke")
		if outline then
			outline.Thickness = if t == selected then 4 else 1.5
			outline.Color = if t == selected then Color3.new(1, 1, 1) else Color3.new(0, 0, 0)
		end
	end
	buildBar.Visible = selected ~= nil
	deleteBtn.BackgroundColor3 = if deleteMode then Color3.fromRGB(230, 60, 70) else Color3.fromRGB(120, 60, 70)
	deleteBtn.Text = if deleteMode then "🗑 Deleting… (X)" else "🗑 Delete (X)"
	followBtn.Text = if followCam then "🎥 Follow: ON" else "🎥 Follow: OFF"
	levelLabel.Text = string.format("Height %d / %d", workLevel, Config.MAX_LEVEL)
	levelPlane.Parent = if selected and origin then workspace else nil
	if origin then
		levelPlane.CFrame = CFrame.new(origin + Vector3.new(SIZE / 2, workLevel * LH - 0.05, SIZE / 2))
	end
end

local function selectPiece(t: string?)
	if t == selected then
		t = nil
	end
	selected = t
	if t then
		deleteMode = false
	end
	clearGhost()
	refreshButtons()
end

local function setDeleteMode(on: boolean)
	deleteMode = on
	if on then
		selected = nil
		clearGhost()
	end
	updateDelete()
	refreshButtons()
end

local function changeLevel(delta: number)
	workLevel = math.clamp(workLevel + delta, Config.MIN_LEVEL, Config.MAX_LEVEL)
	ghostKey = ""
	refreshButtons()
end

local function rotate()
	rot = (rot + 1) % 4
	ghostKey = ""
end

for i, t in Pieces.Order do
	local def = Pieces.Defs[t]
	local btn = make("TextButton", {
		Name = t,
		Size = UDim2.fromOffset(80, 84),
		LayoutOrder = i,
		BackgroundColor3 = def.color,
		Text = "",
		AutoButtonColor = true,
		Parent = hotbar,
	}, {
		corner(10),
		stroke(Color3.new(0, 0, 0), 1.5),
		make("TextLabel", {
			Size = UDim2.new(1, 0, 0, 18),
			Position = UDim2.fromOffset(4, 2),
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamBold,
			TextSize = 13,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = Color3.new(1, 1, 1),
			TextStrokeTransparency = 0.4,
			Text = tostring(i),
		}),
		make("TextLabel", {
			Size = UDim2.new(1, -4, 0, 30),
			Position = UDim2.new(0, 2, 0, 18),
			BackgroundTransparency = 1,
			Font = Enum.Font.FredokaOne,
			TextScaled = true,
			TextColor3 = Color3.new(1, 1, 1),
			TextStrokeTransparency = 0.3,
			Text = def.name,
		}),
		make("TextLabel", {
			Size = UDim2.new(1, 0, 0, 22),
			Position = UDim2.new(0, 0, 1, -26),
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamBold,
			TextSize = 15,
			TextColor3 = Color3.fromRGB(255, 240, 150),
			TextStrokeTransparency = 0.3,
			Text = if def.price > 0 then "🪙 " .. def.price else "FREE",
		}),
	})
	btn.MouseButton1Click:Connect(function()
		selectPiece(t)
		if selected == t then
			toast(def.name .. ": " .. def.description, "info")
		end
	end)
	pieceButtons[t] = btn
end

---------------------------------------------------------------------------
-- Actions
---------------------------------------------------------------------------

local function tryPlace()
	if busy or not current then
		return
	end
	local c = current
	if not c.ok then
		toast(REASONS[c.reason or ""] or "Can't place that there.", "error")
		return
	end
	busy = true
	local ok, msg = PlaceFn:InvokeServer(c.t, c.x, c.z, c.l, c.r)
	busy = false
	if ok then
		-- The next piece should start where this one ends.
		workLevel = c.l
		rot = c.r
		ghostKey = ""
		refreshButtons()
	else
		toast(msg or "Can't place that there.", "error")
	end
end

local function tryDelete()
	if busy or not hoveredDelete then
		return
	end
	local id = hoveredDelete:GetAttribute("PieceId")
	busy = true
	DeleteFn:InvokeServer(id)
	busy = false
	updateDelete()
end

local clearArmedUntil = 0
local function tryClear()
	if os.clock() > clearArmedUntil then
		clearArmedUntil = os.clock() + 3
		clearBtn.Text = "Really? Click again"
		task.delay(3, function()
			clearBtn.Text = "💥 Clear Plot"
		end)
		return
	end
	clearArmedUntil = 0
	clearBtn.Text = "💥 Clear Plot"
	ClearFn:InvokeServer()
	workLevel = Config.START_LEVEL
	refreshButtons()
	toast("Plot cleared. All coins refunded.", "info")
end

local function drop()
	DropEvent:FireServer()
end

dropBtn.MouseButton1Click:Connect(drop)
deleteBtn.MouseButton1Click:Connect(function()
	setDeleteMode(not deleteMode)
end)
followBtn.MouseButton1Click:Connect(function()
	followCam = not followCam
	refreshButtons()
end)
clearBtn.MouseButton1Click:Connect(tryClear)
upBtn.MouseButton1Click:Connect(function()
	changeLevel(1)
end)
downBtn.MouseButton1Click:Connect(function()
	changeLevel(-1)
end)
rotBtn.MouseButton1Click:Connect(rotate)
cancelBtn.MouseButton1Click:Connect(function()
	selectPiece(nil)
end)

---------------------------------------------------------------------------
-- Input
---------------------------------------------------------------------------

local KEY_TO_INDEX = {
	[Enum.KeyCode.One] = 1,
	[Enum.KeyCode.Two] = 2,
	[Enum.KeyCode.Three] = 3,
	[Enum.KeyCode.Four] = 4,
	[Enum.KeyCode.Five] = 5,
	[Enum.KeyCode.Six] = 6,
	[Enum.KeyCode.Seven] = 7,
	[Enum.KeyCode.Eight] = 8,
}

UserInputService.InputChanged:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
		pointer = Vector2.new(input.Position.X, input.Position.Y)
	end
end)

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		pointer = Vector2.new(input.Position.X, input.Position.Y)
		if selected then
			if input.UserInputType == Enum.UserInputType.Touch then
				updateGhost()
			end
			tryPlace()
		elseif deleteMode then
			updateDelete()
			tryDelete()
		end
	elseif input.UserInputType == Enum.UserInputType.Keyboard then
		local key = input.KeyCode
		local idx = KEY_TO_INDEX[key]
		if idx and Pieces.Order[idx] then
			selectPiece(Pieces.Order[idx])
		elseif key == Enum.KeyCode.R then
			rotate()
		elseif key == Enum.KeyCode.E then
			changeLevel(1)
		elseif key == Enum.KeyCode.Q then
			changeLevel(-1)
		elseif key == Enum.KeyCode.X then
			setDeleteMode(not deleteMode)
		elseif key == Enum.KeyCode.F then
			drop()
		end
	end
end)

---------------------------------------------------------------------------
-- Marble camera
---------------------------------------------------------------------------

local function resetCamera()
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		camera.CameraSubject = humanoid
	end
end

MarbleEvent.OnClientEvent:Connect(function(marble: BasePart?, state: string)
	if state == "dropped" and marble and followCam then
		camera.CameraSubject = marble
	elseif state == "finished" or state == "lost" then
		task.delay(if state == "finished" then 1.5 else 0.3, function()
			if camera.CameraSubject == nil or not camera.CameraSubject:IsA("Humanoid") then
				resetCamera()
			end
		end)
	end
end)

---------------------------------------------------------------------------
-- Main loop
---------------------------------------------------------------------------

local lastCoins = -1
RunService.RenderStepped:Connect(function()
	if indexDirty then
		rebuildIndex()
		ghostKey = ""
	end
	local coins = myCoins()
	if coins ~= lastCoins then
		lastCoins = coins
		coinsLabel.Text = "🪙 " .. coins
		ghostKey = ""
	end
	if selected then
		updateGhost()
	elseif deleteMode then
		updateDelete()
	end
end)

camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale)
updateScale()
refreshButtons()
