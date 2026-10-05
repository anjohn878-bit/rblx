-- Builds the town: a pink shopping boulevard with empty store plots on both sides.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("DressStore"):WaitForChild("Config"))
local Layout = require(script.Parent.Layout)
local Parts = require(script.Parent.Parts)

local WorldBuilder = {}

local PLOT_ROW_Z = 80 -- plots sit at z = +80 and z = -80, facing the boulevard
local PLOT_SPACING_X = 110

local GRASS = Color3.fromRGB(122, 196, 104)
local PAVING = Color3.fromRGB(232, 222, 226)
local SIDEWALK = Color3.fromRGB(250, 240, 244)
local PINK = Color3.fromRGB(255, 105, 180)
local WHITE = Color3.fromRGB(255, 255, 255)

export type Plot = {
	index: number,
	cf: CFrame,
	model: Model,
	labels: { TextLabel },
	ownerBillboard: TextLabel?,
}

local function tree(parent: Instance, position: Vector3)
	Parts.cylinder(parent, CFrame.new(position + Vector3.new(0, 3, 0)), 6, 1.4, Color3.fromRGB(120, 80, 50), Enum.Material.Wood)
	Parts.ball(parent, CFrame.new(position + Vector3.new(0, 8, 0)), 7, Color3.fromRGB(90, 170, 90), Enum.Material.Grass)
	Parts.ball(parent, CFrame.new(position + Vector3.new(1.5, 10, 1)), 4.5, Color3.fromRGB(110, 190, 100), Enum.Material.Grass)
	-- blossoms
	for i = 0, 4 do
		local angle = i * math.pi * 2 / 5
		Parts.ball(
			parent,
			CFrame.new(position + Vector3.new(math.cos(angle) * 3.2, 8.5 + (i % 2), math.sin(angle) * 3.2)),
			0.9,
			Color3.fromRGB(255, 170, 210)
		)
	end
end

local function lampPost(parent: Instance, position: Vector3)
	Parts.cylinder(parent, CFrame.new(position + Vector3.new(0, 5, 0)), 10, 0.5, Color3.fromRGB(60, 50, 70), Enum.Material.Metal)
	local lamp = Parts.ball(parent, CFrame.new(position + Vector3.new(0, 10.4, 0)), 1.4, Color3.fromRGB(255, 235, 245), Enum.Material.Neon)
	Parts.light(lamp, Color3.fromRGB(255, 210, 230), 22, 1)
end

local function buildBoulevard(parent: Folder)
	local length = PLOT_SPACING_X * 3 + 40
	local frontEdge = PLOT_ROW_Z - Layout.PLOT_SIZE / 2 -- where the plots begin
	local sidewalkWidth = 12

	-- main paving and sidewalks
	Parts.new(parent, CFrame.new(0, 0.05, 0), Vector3.new(length, 0.3, (frontEdge - sidewalkWidth) * 2), PAVING, Enum.Material.Pavement)
	for _, side in { -1, 1 } do
		Parts.new(
			parent,
			CFrame.new(0, 0.07, side * (frontEdge - sidewalkWidth / 2)),
			Vector3.new(length, 0.3, sidewalkWidth),
			SIDEWALK,
			Enum.Material.SmoothPlastic
		)
		-- pink curb
		Parts.new(parent, CFrame.new(0, 0.25, side * (frontEdge - sidewalkWidth)), Vector3.new(length, 0.3, 0.8), PINK, Enum.Material.SmoothPlastic)
		for i = -4, 4 do
			lampPost(parent, Vector3.new(i * 40 + 20, 0.2, side * (frontEdge - sidewalkWidth + 2)))
		end
	end
	-- pink stripe down the middle
	Parts.new(parent, CFrame.new(0, 0.22, 0), Vector3.new(length, 0.05, 3), Color3.fromRGB(255, 190, 220), Enum.Material.SmoothPlastic)

	-- round plaza with the spawn in the middle
	Parts.cylinder(parent, CFrame.new(0, 0.26, 0), 0.12, 34, Color3.fromRGB(255, 205, 225), Enum.Material.Marble)
	Parts.cylinder(parent, CFrame.new(0, 0.3, 0), 0.12, 26, WHITE, Enum.Material.Marble)
	for i = 0, 7 do
		local angle = i * math.pi / 4
		local position = Vector3.new(math.cos(angle) * 15, 0.3, math.sin(angle) * 15)
		Parts.cylinder(parent, CFrame.new(position + Vector3.new(0, 0.6, 0)), 1, 2.4, Color3.fromRGB(240, 240, 245), Enum.Material.Marble)
		Parts.ball(parent, CFrame.new(position + Vector3.new(0, 1.6, 0)), 1.6, if i % 2 == 0 then PINK else Color3.fromRGB(200, 160, 255))
	end

	-- floating game title
	local titleAnchor = Parts.new(parent, CFrame.new(0, 26, 0), Vector3.new(1, 1, 1), WHITE)
	titleAnchor.Name = "TitleAnchor"
	titleAnchor.Transparency = 1
	titleAnchor.CanCollide = false
	titleAnchor.CanQuery = false
	titleAnchor.CanTouch = false
	local gui = Instance.new("BillboardGui")
	gui.Name = "Title"
	gui.Size = UDim2.new(46, 0, 12, 0)
	gui.LightInfluence = 0
	gui.MaxDistance = 600
	gui.Adornee = titleAnchor
	gui.Parent = titleAnchor
	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Size = UDim2.fromScale(1, 0.7)
	title.Font = Enum.Font.FredokaOne
	title.Text = "👗 " .. string.upper(Config.GAME_NAME) .. " 👗"
	title.TextScaled = true
	title.TextColor3 = Color3.fromRGB(255, 120, 190)
	title.TextStrokeColor3 = WHITE
	title.TextStrokeTransparency = 0
	title.Parent = gui
	local subtitle = Instance.new("TextLabel")
	subtitle.BackgroundTransparency = 1
	subtitle.Position = UDim2.fromScale(0, 0.7)
	subtitle.Size = UDim2.fromScale(1, 0.3)
	subtitle.Font = Enum.Font.FredokaOne
	subtitle.Text = "Sew dresses • Sell to shoppers • Build the cutest store!"
	subtitle.TextScaled = true
	subtitle.TextColor3 = WHITE
	subtitle.TextStrokeColor3 = Color3.fromRGB(200, 60, 140)
	subtitle.TextStrokeTransparency = 0
	subtitle.Parent = gui

	-- trees between the plots
	for _, z in { PLOT_ROW_Z, -PLOT_ROW_Z } do
		for _, x in { -PLOT_SPACING_X * 1.5, -PLOT_SPACING_X * 0.5, PLOT_SPACING_X * 0.5, PLOT_SPACING_X * 1.5 } do
			tree(parent, Vector3.new(x, 0, z - 20))
			tree(parent, Vector3.new(x, 0, z + 20))
		end
	end
end

local function buildPlot(parent: Folder, index: number, cf: CFrame): Plot
	local model = Instance.new("Model")
	model.Name = "Store" .. index
	local half = Layout.PLOT_SIZE / 2

	local function at(x: number, y: number, z: number): CFrame
		return cf * CFrame.new(x, y, z)
	end

	-- lawn
	Parts.new(model, at(0, 0, 0), Vector3.new(Layout.PLOT_SIZE, 0.4, Layout.PLOT_SIZE), GRASS, Enum.Material.Grass)

	-- hedges on the sides and back
	local hedge = Color3.fromRGB(70, 150, 75)
	Parts.new(model, at(0, 1.4, half - 0.75), Vector3.new(Layout.PLOT_SIZE, 2.4, 1.5), hedge, Enum.Material.Grass)
	for _, side in { -1, 1 } do
		Parts.new(model, at(side * (half - 0.75), 1.4, 0), Vector3.new(1.5, 2.4, Layout.PLOT_SIZE), hedge, Enum.Material.Grass)
	end

	-- white picket fence along the front with an opening for the gate
	local gap = 6
	local fenceLength = half - gap
	for _, side in { -1, 1 } do
		local cx = side * (gap + fenceLength / 2)
		Parts.new(model, at(cx, 1.4, -half + 0.5), Vector3.new(fenceLength, 0.3, 0.3), WHITE)
		Parts.new(model, at(cx, 0.8, -half + 0.5), Vector3.new(fenceLength, 0.3, 0.3), WHITE)
		for i = 0, math.floor(fenceLength / 2) do
			local x = side * (gap + i * 2)
			Parts.new(model, at(x, 1.0, -half + 0.5), Vector3.new(0.35, 1.8, 0.35), WHITE)
		end
	end

	-- gate arch with the owner's name
	for _, side in { -1, 1 } do
		Parts.new(model, at(side * gap, 6, -half + 0.5), Vector3.new(1.4, 12, 1.4), WHITE, Enum.Material.Marble)
		Parts.ball(model, at(side * gap, 12.6, -half + 0.5), 1.6, PINK)
	end
	local arch = Parts.new(model, at(0, 11, -half + 0.5), Vector3.new(gap * 2 + 1.4, 2.4, 0.8), PINK)
	local labels = {
		Parts.surfaceText(arch, Enum.NormalId.Front, "Empty Store", { color = WHITE, stroke = Color3.fromRGB(150, 0, 90) }),
		Parts.surfaceText(arch, Enum.NormalId.Back, "Empty Store", { color = WHITE, stroke = Color3.fromRGB(150, 0, 90) }),
	}

	-- big floating owner name, visible from far away
	local nameAnchor = Parts.new(model, at(0, 32, 0), Vector3.new(1, 1, 1), WHITE)
	nameAnchor.Name = "NameAnchor"
	nameAnchor.Transparency = 1
	nameAnchor.CanCollide = false
	nameAnchor.CanQuery = false
	nameAnchor.CanTouch = false
	local _, ownerLabel = Parts.billboard(nameAnchor, Vector3.zero, 30, 5, "", Color3.fromRGB(255, 230, 245), 400)

	-- little store number sign
	local post = Parts.new(model, at(half - 6, 2, -half + 2), Vector3.new(0.4, 4, 0.4), WHITE)
	local numberSign = Parts.new(model, at(half - 6, 4.3, -half + 2), Vector3.new(3, 1.6, 0.3), Color3.fromRGB(200, 160, 255))
	Parts.surfaceText(numberSign, Enum.NormalId.Front, "Store #" .. index, { color = WHITE })
	post.CanCollide = false

	model.Parent = parent
	return {
		index = index,
		cf = cf,
		model = model,
		labels = labels,
		ownerBillboard = ownerLabel,
	}
end

-- Builds the town and returns the store plots.
function WorldBuilder.build(): { Plot }
	local folder = Instance.new("Folder")
	folder.Name = "DressStoreTown"
	folder.Parent = workspace

	local baseplate = workspace:FindFirstChild("Baseplate")
	if baseplate and baseplate:IsA("BasePart") then
		baseplate.Color = Color3.fromRGB(110, 185, 95)
		baseplate.Material = Enum.Material.Grass
		local texture = baseplate:FindFirstChildOfClass("Texture")
		if texture then
			texture:Destroy()
		end
	end

	buildBoulevard(folder)

	local plotsFolder = Instance.new("Folder")
	plotsFolder.Name = "Stores"
	plotsFolder.Parent = folder

	local plots = {}
	local perRow = math.ceil(Config.PLOT_COUNT / 2)
	for i = 1, Config.PLOT_COUNT do
		local row = if i <= perRow then 1 else -1
		local column = ((i - 1) % perRow) - (perRow - 1) / 2
		local position = Vector3.new(column * PLOT_SPACING_X, 0, row * PLOT_ROW_Z)
		-- each plot faces the boulevard (plot space -Z points at the street)
		local cf = CFrame.new(position) * CFrame.Angles(0, if row == 1 then 0 else math.pi, 0)
		table.insert(plots, buildPlot(plotsFolder, i, cf))
	end
	return plots
end

return WorldBuilder
