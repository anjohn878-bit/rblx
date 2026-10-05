-- The garage window: browse, buy and drive delivery vehicles. Each row shows a live 3D preview
-- built from the same models the server spawns.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Format = require(Shared:WaitForChild("Format"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local VehicleModels = require(Shared:WaitForChild("VehicleModels"))
local UI = require(script.Parent.UI)

local Shop = {}

local COLORS = Config.Colors
local ROW_HEIGHT = 104

local player = Players.LocalPlayer
local window: Frame
local cashLabel: TextLabel
local rows: { [string]: { Button: TextButton, Badge: TextLabel } } = {}
local state = nil
local busy = false
local onMessage: (string, string) -> () = function() end

local function makePreview(id: string): ViewportFrame
	local viewport = UI.new("ViewportFrame", {
		Position = UDim2.fromOffset(8, 8),
		Size = UDim2.new(0, 140, 1, -16),
		BackgroundColor3 = COLORS.NavyLight,
		Ambient = Color3.fromRGB(170, 170, 180),
		LightColor = Color3.new(1, 1, 1),
		LightDirection = Vector3.new(-1, -2, -0.5),
	}, { UI.corner(8) })
	local model = VehicleModels.build(id)
	model.Parent = viewport
	local camera = Instance.new("Camera")
	camera.FieldOfView = 40
	camera.Parent = viewport
	viewport.CurrentCamera = camera
	local boxCFrame, size = model:GetBoundingBox()
	local radius = size.Magnitude / 2
	-- Front three-quarter view: the vehicle faces -Z, so look from the front-left and above.
	local direction = Vector3.new(-1, 0.6, -1.1).Unit
	camera.CFrame = CFrame.lookAt(boxCFrame.Position + direction * radius * 2.7, boxCFrame.Position)
	return viewport
end

local function buildRow(info: Config.VehicleInfo, order: number, parent: Instance)
	local row = UI.new("Frame", {
		Size = UDim2.new(1, -8, 0, ROW_HEIGHT),
		BackgroundColor3 = COLORS.Navy,
		LayoutOrder = order,
		Parent = parent,
	}, { UI.corner(10) })
	makePreview(info.Id).Parent = row

	UI.label({
		Position = UDim2.fromOffset(160, 10),
		Size = UDim2.new(1, -300, 0, 24),
		Font = Enum.Font.FredokaOne,
		TextSize = 21,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Text = info.Name,
		Parent = row,
	})
	UI.label({
		Position = UDim2.fromOffset(160, 36),
		Size = UDim2.new(1, -300, 0, 32),
		TextSize = 13,
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextColor3 = COLORS.Muted,
		Text = info.Description,
		Parent = row,
	})
	UI.label({
		Position = UDim2.fromOffset(160, 72),
		Size = UDim2.new(1, -300, 0, 18),
		Font = Enum.Font.GothamBold,
		TextSize = 13,
		TextColor3 = COLORS.White,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Text = string.format(
			"%s mph  ·  %d package%s",
			Format.speed(info.TopSpeed),
			info.Capacity,
			if info.Capacity == 1 then "" else "s"
		),
		Parent = row,
	})

	local button = UI.button({
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -12, 0.5, 8),
		Size = UDim2.fromOffset(124, 42),
		TextSize = 16,
		TextWrapped = true,
		Parent = row,
	})
	local badge = UI.label({
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 10),
		Size = UDim2.fromOffset(124, 18),
		Font = Enum.Font.GothamBold,
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = COLORS.Money,
		Parent = row,
	})

	button.Activated:Connect(function()
		if busy or not state then
			return
		end
		busy = true
		if state.Owned[info.Id] then
			local ok, message = true, ""
			if state.Equipped ~= info.Id then
				ok, message = Remotes.EquipVehicle:InvokeServer(info.Id)
			end
			if ok then
				Remotes.SpawnVehicle:FireServer()
				Shop.close()
			else
				onMessage(message, "error")
			end
		else
			local ok, message = Remotes.BuyVehicle:InvokeServer(info.Id)
			if not ok then
				onMessage(message, "error")
			end
		end
		busy = false
	end)

	rows[info.Id] = { Button = button, Badge = badge }
end

local function refresh()
	if not state or not window then
		return
	end
	cashLabel.Text = Format.money(state.Cash)
	for _, info in Config.Vehicles do
		local row = rows[info.Id]
		local owned = state.Owned[info.Id]
		local rankOk = state.RankIndex >= info.Rank
		if owned then
			row.Button.Text = "DRIVE"
			row.Button.BackgroundColor3 = COLORS.Brand
			row.Badge.Text = if state.Equipped == info.Id then "EQUIPPED" else "OWNED"
			row.Badge.TextColor3 = COLORS.Money
		elseif not rankOk then
			row.Button.Text = "LOCKED"
			row.Button.BackgroundColor3 = COLORS.NavyLight
			row.Badge.Text = "Needs " .. Config.Ranks[info.Rank].Name
			row.Badge.TextColor3 = Config.Ranks[info.Rank].Color
		else
			row.Button.Text = "BUY " .. Format.money(info.Price)
			row.Button.BackgroundColor3 = if state.Cash >= info.Price then Color3.fromRGB(60, 170, 90) else COLORS.NavyLight
			row.Badge.Text = ""
		end
	end
end

function Shop.update(newState)
	state = newState
	refresh()
end

function Shop.open()
	if window then
		refresh()
		window.Visible = true
	end
end

function Shop.close()
	if window then
		window.Visible = false
	end
end

function Shop.toggle()
	if window and window.Visible then
		Shop.close()
	else
		Shop.open()
	end
end

function Shop.init(messageHandler: (string, string) -> ())
	onMessage = messageHandler
	local gui = UI.new("ScreenGui", {
		Name = "Garage",
		ResetOnSpawn = false,
		DisplayOrder = 5,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = player:WaitForChild("PlayerGui"),
	})
	window = UI.new("Frame", {
		Name = "Window",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.9, 0.82),
		BackgroundColor3 = COLORS.NavyLight,
		Visible = false,
		Parent = gui,
	}, {
		UI.corner(16),
		UI.stroke(COLORS.Brand, 3),
		UI.new("UISizeConstraint", { MaxSize = Vector2.new(640, 480) }),
	})

	UI.label({
		Position = UDim2.fromOffset(18, 12),
		Size = UDim2.new(1, -200, 0, 34),
		Font = Enum.Font.FredokaOne,
		TextSize = 30,
		Text = "Garage",
		Parent = window,
	})
	cashLabel = UI.label({
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -64, 0, 16),
		Size = UDim2.fromOffset(140, 28),
		Font = Enum.Font.FredokaOne,
		TextSize = 24,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = COLORS.Money,
		Parent = window,
	})
	local close = UI.button({
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 12),
		Size = UDim2.fromOffset(40, 40),
		BackgroundColor3 = COLORS.Danger,
		Text = "X",
		Parent = window,
	})
	close.Activated:Connect(Shop.close)

	local list = UI.new("ScrollingFrame", {
		Position = UDim2.fromOffset(12, 60),
		Size = UDim2.new(1, -24, 1, -72),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		Parent = window,
	}, { UI.new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }) })

	for order, info in Config.Vehicles do
		buildRow(info, order, list)
	end
	refresh()
end

return Shop
