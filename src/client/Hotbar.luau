--!strict
-- The seed bar along the bottom. Click a slot or press 1-6 to pick the seed
-- you'll plant next.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Format = require(Shared:WaitForChild("Format"))
local PlantModels = require(Shared:WaitForChild("PlantModels"))
local Seeds = require(Shared:WaitForChild("Seeds"))

local State = require(script.Parent.State)
local Ui = require(script.Parent.Ui)
local Viewport = require(script.Parent.Viewport)

local Hotbar = {}

type Slot = {
	frame: Frame,
	stroke: UIStroke,
	scale: UIScale,
	count: TextLabel,
	key: TextLabel,
}

local KEYS = {
	[Enum.KeyCode.One] = 1,
	[Enum.KeyCode.Two] = 2,
	[Enum.KeyCode.Three] = 3,
	[Enum.KeyCode.Four] = 4,
	[Enum.KeyCode.Five] = 5,
	[Enum.KeyCode.Six] = 6,
}

function Hotbar.init(gui: ScreenGui)
	-- A full-width transparent strip; the slots are centred inside it by a list layout.
	local root = Ui.new("Frame", {
		Name = "Hotbar",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -14),
		Size = UDim2.new(1, 0, 0, 104),
		BackgroundTransparency = 1,
		Parent = gui,
	})
	local hint = Ui.label({
		Name = "Hint",
		Position = UDim2.fromOffset(0, 0),
		Size = UDim2.new(1, 0, 0, 22),
		TextXAlignment = Enum.TextXAlignment.Center,
		Font = Ui.FONT_BOLD,
		TextSize = 14,
		TextStrokeTransparency = 0.5,
		Parent = root,
	})
	local row = Ui.new("Frame", {
		Name = "Slots",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 1, 0),
		Size = UDim2.new(1, 0, 0, 80),
		BackgroundTransparency = 1,
		Parent = root,
	}, {
		Ui.new("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Bottom,
			Padding = UDim.new(0, 8),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})

	local slots: { [string]: Slot } = {}
	for _, seed in Seeds.list do
		local color = Config.RARITY_COLORS[seed.rarity]
		local frame = Ui.new("Frame", {
			Name = seed.id,
			LayoutOrder = seed.tier,
			Size = UDim2.fromOffset(68, 68),
			BackgroundColor3 = Ui.COLORS.bg,
			Visible = false,
			Parent = row,
		}, { Ui.corner(14) })
		local stroke = Ui.stroke(color, 2)
		stroke.Parent = frame
		local scale = Ui.new("UIScale", { Parent = frame })

		local preview = Ui.new("ViewportFrame", { Size = UDim2.fromScale(1, 1), Parent = frame })
		local model = PlantModels.build(seed.id, CFrame.new(), true)
		if model then
			Viewport.mount(preview, model, Vector3.new(0.4, 0.3, -1))
		end

		local count = Ui.label({
			AnchorPoint = Vector2.new(1, 1),
			Position = UDim2.new(1, -5, 1, -3),
			Size = UDim2.fromOffset(40, 18),
			TextXAlignment = Enum.TextXAlignment.Right,
			Font = Ui.FONT,
			TextSize = 17,
			TextStrokeTransparency = 0.3,
			ZIndex = 3,
			Parent = frame,
		})
		local key = Ui.label({
			Position = UDim2.fromOffset(6, 3),
			Size = UDim2.fromOffset(20, 16),
			Font = Ui.FONT_BOLD,
			TextSize = 13,
			TextColor3 = Ui.COLORS.muted,
			TextStrokeTransparency = 0.5,
			ZIndex = 3,
			Parent = frame,
		})

		local click = Ui.new(
			"TextButton",
			{ Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "", ZIndex = 4, Parent = frame }
		)
		click.Activated:Connect(function()
			State.select(seed.id)
		end)

		slots[seed.id] = { frame = frame, stroke = stroke, scale = scale, count = count, key = key }
	end

	local visibleOrder: { string } = {}
	local function refresh()
		visibleOrder = {}
		for _, seed in Seeds.list do
			local slot = slots[seed.id]
			local owned = State.seedCount(seed.id)
			slot.frame.Visible = owned > 0
			if owned > 0 then
				table.insert(visibleOrder, seed.id)
				slot.count.Text = "x" .. Format.commas(owned)
				slot.key.Text = tostring(#visibleOrder)
				local selected = State.selected == seed.id
				slot.stroke.Color = if selected then Ui.COLORS.gold else Config.RARITY_COLORS[seed.rarity]
				slot.stroke.Thickness = if selected then 4 else 2
				slot.scale.Scale = if selected then 1.12 else 1
			end
		end
		local selected = State.selected and Seeds.get(State.selected)
		if selected then
			hint.Text = `{selected.name}  -  grows in {Format.growTime(selected.growTime)}`
			hint.TextColor3 = Config.RARITY_COLORS[selected.rarity]
		else
			hint.Text = ""
		end
	end

	State.changed:Connect(refresh)
	State.selectedChanged:Connect(refresh)
	refresh()

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		local position = KEYS[input.KeyCode]
		local id = if position then visibleOrder[position] else nil
		if id then
			State.select(id)
		end
	end)
end

return Hotbar
