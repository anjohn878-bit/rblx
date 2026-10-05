--[[
	The garage: browse vehicles with live 3D previews, buy them, and pick which one to drive.

	All rules (price, rank, cash) are enforced by the server; this UI only displays state and sends
	requests via GarageRequest. Buttons reflect what the server will accept.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Economy = require(ReplicatedStorage.Shared.Economy)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local VehicleBuilder = require(ReplicatedStorage.Shared.VehicleBuilder)
local State = require(script.Parent.State)
local Theme = require(script.Parent.Theme)
local UIKit = require(script.Parent.UIKit)

local GarageUI = {}

local CARD_WIDTH, CARD_HEIGHT = 190, 330

-- Best value across all vehicles, so stat bars are comparable.
local function maxima()
	local m = { Speed = 0, Accel = 0, Handling = 0 }
	for _, v in Config.Vehicles do
		m.Speed = math.max(m.Speed, v.MaxSpeed)
		m.Accel = math.max(m.Accel, v.Accel)
		m.Handling = math.max(m.Handling, v.Turn * math.sqrt(v.Grip))
	end
	return m
end

local function statBar(parent: Instance, name: string, fraction: number, order: number)
	local row = UIKit.create("Frame", {
		Name = name,
		Size = UDim2.new(1, 0, 0, 20),
		BackgroundTransparency = 1,
		LayoutOrder = order,
		Parent = parent,
	})
	UIKit.label({
		Size = UDim2.new(0, 70, 1, 0),
		Font = Theme.FontBold,
		TextSize = 11,
		TextColor3 = Theme.TextDim,
		Text = string.upper(name),
		Parent = row,
	})
	local track = UIKit.create("Frame", {
		Position = UDim2.new(0, 72, 0.5, -4),
		Size = UDim2.new(1, -72, 0, 8),
		BackgroundColor3 = Theme.NavyLight,
		BorderSizePixel = 0,
		Parent = row,
	}, { UIKit.corner(4) })
	UIKit.create("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(math.clamp(fraction, 0.05, 1), 1),
		BackgroundColor3 = Theme.Orange,
		BorderSizePixel = 0,
		Parent = track,
	}, { UIKit.corner(4) })
end

-- A rotating 3D preview of a vehicle. Returns the ViewportFrame and a function(angle) to spin it.
local function buildPreview(vehicleId: string)
	local viewport = UIKit.create("ViewportFrame", {
		Name = "Preview",
		Size = UDim2.new(1, 0, 0, 120),
		BackgroundColor3 = Theme.NavyLight,
		BackgroundTransparency = 0.3,
		BorderSizePixel = 0,
		Ambient = Color3.fromRGB(150, 156, 175),
		LightColor = Color3.fromRGB(255, 244, 224),
		LightDirection = Vector3.new(-0.5, -1, -0.6),
	}, { UIKit.corner(10) })

	local model = VehicleBuilder.build(vehicleId)
	local pivot = model:GetPivot()
	local size = model:GetExtentsSize()
	model.Parent = viewport

	local camera = Instance.new("Camera")
	camera.FieldOfView = 38
	local focus = pivot.Position + Vector3.new(0, size.Y * 0.1, 0)
	local distance = math.max(size.X, size.Y, size.Z) * 1.75
	camera.CFrame = CFrame.lookAt(focus + Vector3.new(0, size.Y * 0.35, distance), focus)
	camera.Parent = viewport
	viewport.CurrentCamera = camera

	local function spin(angle: number)
		model:PivotTo(CFrame.new(pivot.Position) * CFrame.Angles(0, angle, 0))
	end
	spin(math.rad(-35))
	return viewport, spin
end

-- deps.toast(message, kind)
function GarageUI.build(gui: ScreenGui, deps)
	local overlay = UIKit.create("TextButton", {
		Name = "Garage",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.45,
		Text = "",
		AutoButtonColor = false,
		Visible = false,
		ZIndex = 10,
		Parent = gui,
	})

	local window = UIKit.panel({
		Name = "Window",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(920, 470),
		BackgroundTransparency = 0.02,
		ZIndex = 11,
		Parent = overlay,
	})
	UIKit.autoScale(window)

	UIKit.label({
		Position = UDim2.fromOffset(24, 14),
		Size = UDim2.fromOffset(300, 36),
		Font = Theme.FontBold,
		TextSize = 30,
		Text = "GARAGE",
		ZIndex = 12,
		Parent = window,
	})
	local cashLabel = UIKit.label({
		Name = "Cash",
		Position = UDim2.new(1, -330, 0, 14),
		Size = UDim2.fromOffset(240, 36),
		Font = Theme.FontBold,
		TextSize = 26,
		TextColor3 = Theme.Green,
		TextXAlignment = Enum.TextXAlignment.Right,
		Text = "$0",
		ZIndex = 12,
		Parent = window,
	})

	local garage = {}

	function garage.close()
		overlay.Visible = false
	end

	UIKit.button({
		Name = "CloseButton",
		Position = UDim2.new(1, -68, 0, 16),
		Size = UDim2.fromOffset(44, 36),
		Text = "X",
		BackgroundColor3 = Theme.NavyLighter,
		TextColor3 = Theme.Text,
		ZIndex = 12,
		OnClick = garage.close,
		Parent = window,
	})

	local list = UIKit.create("ScrollingFrame", {
		Name = "List",
		Position = UDim2.fromOffset(24, 70),
		Size = UDim2.new(1, -48, 1, -90),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		ScrollingDirection = Enum.ScrollingDirection.X,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.X,
		ZIndex = 12,
		Parent = window,
	}, {
		UIKit.list({ FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 14) }),
	})

	local best = maxima()
	local cards = {} -- [vehicleId] = { Button, Status, Spin }

	local function request(action: string, vehicleId: string)
		task.spawn(function()
			local ok, reply = pcall(function()
				return Remotes.GarageRequest:InvokeServer(action, vehicleId)
			end)
			if ok and type(reply) == "table" then
				deps.toast(reply.message, reply.ok and "success" or "error")
			else
				deps.toast("Something went wrong - try again.", "error")
			end
		end)
	end

	for index, spec in Config.Vehicles do
		local card = UIKit.create("Frame", {
			Name = spec.Id,
			Size = UDim2.fromOffset(CARD_WIDTH, CARD_HEIGHT),
			BackgroundColor3 = Theme.NavyLight,
			BackgroundTransparency = 0.25,
			BorderSizePixel = 0,
			LayoutOrder = index,
			ZIndex = 12,
			Parent = list,
		}, {
			UIKit.corner(14),
			UIKit.padding(10),
		})
		local stroke = UIKit.stroke(Theme.NavyLighter, 2, 0.3)
		stroke.Parent = card

		local inner = UIKit.create("Frame", {
			Name = "Inner",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			ZIndex = 12,
			Parent = card,
		}, {
			UIKit.list({ Padding = UDim.new(0, 6) }),
		})

		local preview, spin = buildPreview(spec.Id)
		preview.LayoutOrder = 1
		preview.Parent = inner

		UIKit.label({
			Size = UDim2.new(1, 0, 0, 22),
			Font = Theme.FontBold,
			TextSize = 17,
			Text = spec.Name,
			LayoutOrder = 2,
			Parent = inner,
		})
		UIKit.label({
			Size = UDim2.new(1, 0, 0, 30),
			Font = Theme.FontRegular,
			TextSize = 11,
			TextColor3 = Theme.TextDim,
			TextWrapped = true,
			TextYAlignment = Enum.TextYAlignment.Top,
			Text = spec.Description,
			LayoutOrder = 3,
			Parent = inner,
		})
		local stats = UIKit.create("Frame", {
			Size = UDim2.new(1, 0, 0, 62),
			BackgroundTransparency = 1,
			LayoutOrder = 4,
			Parent = inner,
		}, { UIKit.list({}) })
		statBar(stats, "Speed", spec.MaxSpeed / best.Speed, 1)
		statBar(stats, "Accel", spec.Accel / best.Accel, 2)
		statBar(stats, "Handling", spec.Turn * math.sqrt(spec.Grip) / best.Handling, 3)

		local status = UIKit.label({
			Name = "Status",
			Size = UDim2.new(1, 0, 0, 20),
			Font = Theme.FontBold,
			TextSize = 14,
			TextXAlignment = Enum.TextXAlignment.Center,
			Text = "",
			LayoutOrder = 5,
			Parent = inner,
		})
		local button
		button = UIKit.button({
			Name = "ActionButton",
			Size = UDim2.new(1, 0, 0, 36),
			Text = "",
			LayoutOrder = 6,
			ZIndex = 13,
			OnClick = function()
				local action = button:GetAttribute("Action")
				if action then
					request(action, spec.Id)
				end
			end,
			Parent = inner,
		})

		cards[spec.Id] = { Frame = card, Stroke = stroke, Status = status, Button = button, Spin = spin }
	end

	-- Reflect ownership / cash / rank on every card.
	local function refresh()
		local cash = State.get("Cash", 0)
		local rank = State.get("RankIndex", 1)
		local equipped = State.get("Equipped", Config.DefaultVehicle)
		cashLabel.Text = Economy.formatMoney(cash)

		for _, spec in Config.Vehicles do
			local card = cards[spec.Id]
			local owned = State.owns(spec.Id)
			local isEquipped = equipped == spec.Id
			card.Stroke.Color = isEquipped and Theme.Orange or Theme.NavyLighter

			if isEquipped then
				card.Status.Text = "IN USE"
				card.Status.TextColor3 = Theme.Orange
				card.Button:SetAttribute("Action", nil)
				card.Button.Text = "EQUIPPED"
				UIKit.setButtonEnabled(card.Button, false, Theme.Orange)
			elseif owned then
				card.Status.Text = "OWNED"
				card.Status.TextColor3 = Theme.Green
				card.Button:SetAttribute("Action", "Equip")
				card.Button.Text = "EQUIP"
				UIKit.setButtonEnabled(card.Button, true, Theme.Green)
			elseif rank < spec.RankRequired then
				card.Status.Text = "LOCKED"
				card.Status.TextColor3 = Theme.Red
				card.Button:SetAttribute("Action", nil)
				card.Button.Text = "RANK: " .. string.upper(Config.Ranks[spec.RankRequired].Name)
				UIKit.setButtonEnabled(card.Button, false, Theme.Orange)
			else
				card.Status.Text = Economy.formatMoney(spec.Price)
				card.Status.TextColor3 = cash >= spec.Price and Theme.Green or Theme.Red
				card.Button:SetAttribute("Action", cash >= spec.Price and "Buy" or nil)
				card.Button.Text = "BUY"
				UIKit.setButtonEnabled(card.Button, cash >= spec.Price, Theme.Orange)
			end
		end
	end
	for _, name in { "Cash", "RankIndex", "Equipped", "Owned" } do
		State.watch(name, refresh)
	end

	-- Spin the previews only while the garage is open.
	local angle = 0
	UIKit.onFrame(function(dt)
		if not overlay.Visible then
			return
		end
		angle += dt * 0.9
		for _, card in cards do
			card.Spin(angle)
		end
	end)

	function garage.open()
		refresh()
		overlay.Visible = true
	end

	function garage.toggle()
		if overlay.Visible then
			garage.close()
		else
			garage.open()
		end
	end

	-- Clicking the dimmed background closes it (the window swallows clicks inside it).
	UIKit.on(overlay, "Activated", garage.close)
	window.Active = true

	-- Exposed for tests.
	garage.Overlay = overlay
	garage.Cards = cards
	garage.refresh = refresh
	return garage
end

return GarageUI
