--!strict
-- Always-on screen elements: the feathers counter and the Shop / Birdpedia buttons.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Birds = require(Shared:WaitForChild("Birds"))
local Format = require(Shared:WaitForChild("Format"))

local State = require(script.Parent.State)
local Ui = require(script.Parent.Ui)

local Hud = {}

function Hud.init(gui: ScreenGui, onShop: () -> (), onBirdpedia: () -> ())
	-- feathers counter
	local pill = Ui.new("Frame", {
		Name = "Feathers",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 8),
		Size = UDim2.fromOffset(250, 44),
		BackgroundColor3 = Ui.COLORS.bg,
		Parent = gui,
	}, { Ui.corner(22), Ui.stroke(Ui.COLORS.gold, 2.5) })
	local scale = Ui.new("UIScale", { Parent = pill })
	Ui.label({
		Position = UDim2.fromOffset(16, 0),
		Size = UDim2.new(0, 90, 1, 0),
		Text = "FEATHERS",
		Font = Ui.FONT_BOLD,
		TextSize = 13,
		TextColor3 = Ui.COLORS.muted,
		Parent = pill,
	})
	local amount = Ui.label({
		Position = UDim2.fromOffset(100, 0),
		Size = UDim2.new(1, -116, 1, 0),
		Text = "0",
		Font = Ui.FONT,
		TextSize = 26,
		TextColor3 = Ui.COLORS.gold,
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = pill,
	})

	-- side buttons
	local side = Ui.new("Frame", {
		Name = "SideButtons",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 12, 0.5, 0),
		Size = UDim2.fromOffset(150, 120),
		BackgroundTransparency = 1,
		Parent = gui,
	}, { Ui.new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }) })

	local shopButton = Ui.button({
		Name = "Shop",
		LayoutOrder = 1,
		Size = UDim2.new(1, 0, 0, 54),
		Text = "Seed Shop",
		BackgroundColor3 = Color3.fromRGB(214, 112, 60),
		Parent = side,
	})
	local pediaButton = Ui.button({
		Name = "Birdpedia",
		LayoutOrder = 2,
		Size = UDim2.new(1, 0, 0, 54),
		Text = "Birdpedia",
		BackgroundColor3 = Color3.fromRGB(70, 130, 196),
		Parent = side,
	})
	Ui.stroke(Color3.fromRGB(0, 0, 0), 2, 0.6).Parent = shopButton
	Ui.stroke(Color3.fromRGB(0, 0, 0), 2, 0.6).Parent = pediaButton
	shopButton.Activated:Connect(onShop)
	pediaButton.Activated:Connect(onBirdpedia)

	local lastFeathers = State.feathers
	local function refresh()
		amount.Text = Format.feathers(State.feathers)
		pediaButton.Text = `Birdpedia {State.speciesDiscovered()}/{#Birds.list}`
		if State.feathers > lastFeathers then
			scale.Scale = 1.12
			TweenService
				:Create(scale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
				:Play()
		end
		lastFeathers = State.feathers
	end
	State.changed:Connect(refresh)
	refresh()
end

return Hud
