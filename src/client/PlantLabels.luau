--!strict
-- Floating name + countdown above every plant (yours and other players').
-- Purely visual and computed locally from the plant's attributes, so it costs
-- no network traffic while you wait.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Clock = require(Shared:WaitForChild("Clock"))
local Config = require(Shared:WaitForChild("Config"))
local Format = require(Shared:WaitForChild("Format"))
local Growth = require(Shared:WaitForChild("Growth"))
local Seeds = require(Shared:WaitForChild("Seeds"))
local Types = require(Shared:WaitForChild("Types"))

local Ui = require(script.Parent.Ui)

local PlantLabels = {}

type Label = {
	gui: BillboardGui,
	status: TextLabel,
	bar: Frame,
	fill: Frame,
	seed: Types.SeedDef,
	model: Model,
}

local labels: { [Instance]: Label } = {}

local function add(instance: Instance)
	if not instance:IsA("Model") or labels[instance] then
		return
	end
	local model: Model = instance
	local seed = Seeds.get(tostring(model:GetAttribute("SeedId")))
	if not seed then
		return
	end
	task.spawn(function()
		local root = model:WaitForChild("Root", 10)
		if not root or not root:IsA("BasePart") or not model.Parent or labels[model] then
			return
		end
		local color = Config.RARITY_COLORS[seed.rarity]

		local gui = Ui.new("BillboardGui", {
			Name = "PlantLabel",
			Size = UDim2.fromOffset(190, 56),
			MaxDistance = 90,
			LightInfluence = 0,
			Adornee = root,
			StudsOffsetWorldSpace = Vector3.new(0, seed.labelHeight * Config.SCALE_MIN + 1.8, 0),
			Parent = root,
		})
		local frame = Ui.new("Frame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = Ui.COLORS.bg,
			BackgroundTransparency = 0.15,
			Parent = gui,
		}, { Ui.corner(10), Ui.stroke(color, 2, 0.2) })
		Ui.label({
			Position = UDim2.fromOffset(8, 2),
			Size = UDim2.new(1, -16, 0, 24),
			Text = seed.name,
			Font = Ui.FONT,
			TextSize = 19,
			TextColor3 = color,
			TextXAlignment = Enum.TextXAlignment.Center,
			Parent = frame,
		})
		local status = Ui.label({
			Position = UDim2.fromOffset(8, 24),
			Size = UDim2.new(1, -16, 0, 16),
			Text = "",
			Font = Ui.FONT_BOLD,
			TextSize = 13,
			TextXAlignment = Enum.TextXAlignment.Center,
			Parent = frame,
		})
		local bar = Ui.new("Frame", {
			Position = UDim2.new(0, 10, 1, -13),
			Size = UDim2.new(1, -20, 0, 7),
			BackgroundColor3 = Color3.fromRGB(20, 32, 27),
			BorderSizePixel = 0,
			Parent = frame,
		}, { Ui.corner(4) })
		local fill = Ui.new(
			"Frame",
			{ Size = UDim2.fromScale(0, 1), BackgroundColor3 = color, BorderSizePixel = 0, Parent = bar },
			{ Ui.corner(4) }
		)

		labels[model] = { gui = gui, status = status, bar = bar, fill = fill, seed = seed, model = model }
	end)
end

local function remove(instance: Instance)
	local label = labels[instance]
	if label then
		labels[instance] = nil
		label.gui:Destroy()
	end
end

function PlantLabels.init()
	CollectionService:GetInstanceAddedSignal("Plant"):Connect(add)
	CollectionService:GetInstanceRemovedSignal("Plant"):Connect(remove)
	for _, plant in CollectionService:GetTagged("Plant") do
		add(plant)
	end

	task.spawn(function()
		while true do
			local now = Clock.now()
			for model, label in labels do
				if not model.Parent then
					remove(model)
				else
					local plantedAt = model:GetAttribute("PlantedAt")
					if type(plantedAt) == "number" then
						local progress = Growth.progress(plantedAt, label.seed.growTime, now)
						if progress >= 1 then
							label.status.Text = "Blooming - birds visit!"
							label.status.TextColor3 = Ui.COLORS.good
							label.bar.Visible = false
						else
							label.status.Text = "Growing  " .. Format.duration(label.seed.growTime - (now - plantedAt))
							label.status.TextColor3 = Ui.COLORS.text
							label.bar.Visible = true
							label.fill.Size = UDim2.fromScale(progress, 1)
						end
						label.gui.StudsOffsetWorldSpace =
							Vector3.new(0, label.seed.labelHeight * Growth.scale(progress) + 1.8, 0)
					end
				end
			end
			task.wait(0.2)
		end
	end)
end

return PlantLabels
