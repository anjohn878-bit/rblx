--!strict
-- Studio-only cheat buttons for testing. Never appears in a published game.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes")).get()

local Ui = require(script.Parent.Ui)

local DevPanel = {}

function DevPanel.init(gui: ScreenGui)
	if not RunService:IsStudio() then
		return
	end

	local panel = Ui.new("Frame", {
		Name = "DevPanel",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -12, 0.5, 0),
		Size = UDim2.fromOffset(150, 220),
		BackgroundColor3 = Ui.COLORS.bg,
		BackgroundTransparency = 0.15,
		Parent = gui,
	}, {
		Ui.corner(12),
		Ui.stroke(Ui.COLORS.bad, 2),
		Ui.padding(8),
		Ui.new("UIListLayout", { Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	Ui.label({
		LayoutOrder = 0,
		Size = UDim2.new(1, 0, 0, 18),
		Text = "DEV (Studio only)",
		Font = Ui.FONT_BOLD,
		TextSize = 12,
		TextColor3 = Ui.COLORS.bad,
		Parent = panel,
	})

	local actions = {
		{ "feathers", "+100K Feathers" },
		{ "seeds", "+5 of every seed" },
		{ "grow", "Grow all plants" },
		{ "plots", "Unlock all plots" },
		{ "stock", "Fill shop stock" },
	}
	for i, entry in actions do
		local button = Ui.button({
			LayoutOrder = i,
			Size = UDim2.new(1, 0, 0, 32),
			Text = entry[2],
			TextSize = 13,
			Parent = panel,
		})
		button.Activated:Connect(function()
			Remotes.Dev:FireServer(entry[1])
		end)
	end
end

return DevPanel
