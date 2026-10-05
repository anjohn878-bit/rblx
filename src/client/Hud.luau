--[[
	Always-on heads-up display:
	  top-left    cash, rank + XP bar, delivery streak
	  top-centre  what to do next (the objective banner)
	  left        Garage and "Call vehicle" buttons
	  bottom      speedometer while driving
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Economy = require(ReplicatedStorage.Shared.Economy)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local State = require(script.Parent.State)
local Theme = require(script.Parent.Theme)
local UIKit = require(script.Parent.UIKit)
local VehicleController = require(script.Parent.VehicleController)

local Hud = {}

local STREAK_STEP = 5 -- shown as +5% per streak step

-- deps.openGarage: function to open the garage UI
function Hud.build(gui: ScreenGui, deps)
	-- Stats card ------------------------------------------------------------------
	local card = UIKit.panel({
		Name = "StatsCard",
		Position = UDim2.new(0, 16, 0, 12),
		Size = UDim2.fromOffset(268, 92),
		Parent = gui,
	})
	UIKit.autoScale(card)

	local cashLabel = UIKit.label({
		Name = "Cash",
		Position = UDim2.new(0, 16, 0, 8),
		Size = UDim2.new(1, -32, 0, 36),
		Font = Theme.FontBold,
		TextSize = 32,
		TextColor3 = Theme.Green,
		Text = "$0",
		Parent = card,
	})
	local rankLabel = UIKit.label({
		Name = "Rank",
		Position = UDim2.new(0, 16, 0, 46),
		Size = UDim2.new(0.62, 0, 0, 18),
		Font = Theme.FontBold,
		TextSize = 14,
		TextColor3 = Theme.Text,
		Text = "ROOKIE",
		Parent = card,
	})
	local xpLabel = UIKit.label({
		Name = "XP",
		Position = UDim2.new(0.5, 0, 0, 46),
		Size = UDim2.new(0.5, -16, 0, 18),
		Font = Theme.FontMedium,
		TextSize = 13,
		TextColor3 = Theme.TextDim,
		TextXAlignment = Enum.TextXAlignment.Right,
		Text = "0 / 120 XP",
		Parent = card,
	})
	local barTrack = UIKit.create("Frame", {
		Name = "XPBar",
		Position = UDim2.new(0, 16, 0, 70),
		Size = UDim2.new(1, -32, 0, 10),
		BackgroundColor3 = Theme.NavyLight,
		BorderSizePixel = 0,
		Parent = card,
	}, { UIKit.corner(5) })
	local barFill = UIKit.create("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = Theme.Orange,
		BorderSizePixel = 0,
		Parent = barTrack,
	}, { UIKit.corner(5) })

	local streakChip = UIKit.create("Frame", {
		Name = "StreakChip",
		Position = UDim2.new(0, 16, 0, 112),
		Size = UDim2.fromOffset(190, 28),
		BackgroundColor3 = Theme.Orange,
		BorderSizePixel = 0,
		Visible = false,
		Parent = gui,
	}, { UIKit.corner(14) })
	UIKit.autoScale(streakChip)
	local streakLabel = UIKit.label({
		Size = UDim2.fromScale(1, 1),
		Font = Theme.FontBold,
		TextSize = 14,
		TextColor3 = Theme.Navy,
		TextXAlignment = Enum.TextXAlignment.Center,
		Text = "",
		Parent = streakChip,
	})

	-- Objective banner --------------------------------------------------------------
	local banner = UIKit.panel({
		Name = "Objective",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 12),
		Size = UDim2.fromOffset(440, 40),
		Parent = gui,
	})
	UIKit.autoScale(banner)
	local objectiveLabel = UIKit.label({
		Name = "Text",
		Size = UDim2.new(1, -24, 1, 0),
		Position = UDim2.fromOffset(12, 0),
		Font = Theme.FontBold,
		TextSize = 17,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextWrapped = true,
		Text = "",
		Parent = banner,
	})

	-- Buttons -------------------------------------------------------------------------
	local buttons = UIKit.create("Frame", {
		Name = "Buttons",
		Position = UDim2.new(0, 16, 0, 152),
		Size = UDim2.fromOffset(190, 100),
		BackgroundTransparency = 1,
		Parent = gui,
	}, {
		UIKit.list({ Padding = UDim.new(0, 8) }),
	})
	UIKit.autoScale(buttons)
	UIKit.button({
		Name = "GarageButton",
		Size = UDim2.new(1, 0, 0, 44),
		Text = "GARAGE",
		LayoutOrder = 1,
		BackgroundColor3 = Theme.NavyLighter,
		TextColor3 = Theme.Text,
		OnClick = deps.openGarage,
		Parent = buttons,
	})
	UIKit.button({
		Name = "CallButton",
		Size = UDim2.new(1, 0, 0, 44),
		Text = "MY VEHICLE  [V]",
		LayoutOrder = 2,
		OnClick = function()
			Remotes.CallVehicle:FireServer()
		end,
		Parent = buttons,
	})

	-- Speedometer ----------------------------------------------------------------------
	local speedo = UIKit.panel({
		Name = "Speedometer",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -20),
		Size = UDim2.fromOffset(220, 66),
		Visible = false,
		Parent = gui,
	})
	UIKit.autoScale(speedo)
	local speedLabel = UIKit.label({
		Name = "Speed",
		Position = UDim2.fromOffset(16, 4),
		Size = UDim2.new(0.6, 0, 0, 40),
		Font = Theme.FontBold,
		TextSize = 36,
		Text = "0",
		Parent = speedo,
	})
	UIKit.label({
		Position = UDim2.new(0.55, 0, 0, 14),
		Size = UDim2.new(0.45, -16, 0, 22),
		Font = Theme.FontBold,
		TextSize = 14,
		TextColor3 = Theme.TextDim,
		TextXAlignment = Enum.TextXAlignment.Right,
		Text = "KM/H",
		Parent = speedo,
	})
	local speedTrack = UIKit.create("Frame", {
		Position = UDim2.new(0, 16, 1, -18),
		Size = UDim2.new(1, -32, 0, 8),
		BackgroundColor3 = Theme.NavyLight,
		BorderSizePixel = 0,
		Parent = speedo,
	}, { UIKit.corner(4) })
	local speedFill = UIKit.create("Frame", {
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = Theme.Orange,
		BorderSizePixel = 0,
		Parent = speedTrack,
	}, { UIKit.corner(4) })

	-- Live state ----------------------------------------------------------------------
	local function refreshMoney()
		cashLabel.Text = Economy.formatMoney(State.get("Cash", 0))
	end
	local function refreshRank()
		local xp = State.get("XP", 0)
		local info = Economy.rankInfo(xp)
		rankLabel.Text = string.format("RANK %d  %s", info.Index, string.upper(info.Name))
		if info.XPNext then
			xpLabel.Text = string.format("%d / %d XP", xp, info.XPNext)
		else
			xpLabel.Text = "MAX RANK"
		end
		UIKit.tween(barFill, 0.35, { Size = UDim2.fromScale(info.Fraction, 1) })
	end
	local function refreshStreak()
		local streak = State.get("Streak", 0)
		streakChip.Visible = streak > 0
		streakLabel.Text = string.format("STREAK x%d   +%d%% TIPS & BONUS", streak, math.min(streak * STREAK_STEP, 50))
	end
	State.watch("Cash", refreshMoney)
	State.watch("XP", refreshRank)
	State.watch("Streak", refreshStreak)

	-- Speedometer: show only while driving our own vehicle.
	local topSpeed = 1
	UIKit.onFrame(function()
		local model = VehicleController.currentVehicle()
		if not model or not model.PrimaryPart then
			speedo.Visible = false
			return
		end
		topSpeed = model:GetAttribute("MaxSpeed") or topSpeed
		local velocity = model.PrimaryPart.AssemblyLinearVelocity
		local speed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
		speedo.Visible = true
		speedLabel.Text = tostring(math.floor(speed * 0.8 + 0.5))
		speedFill.Size = UDim2.fromScale(math.clamp(speed / topSpeed, 0, 1), 1)
	end)

	local hud = {}

	function hud.setObjective(text: string)
		objectiveLabel.Text = text
	end

	-- Exposed for tests.
	hud.CashLabel = cashLabel
	hud.RankLabel = rankLabel
	hud.XPLabel = xpLabel
	hud.StreakChip = streakChip
	hud.StreakLabel = streakLabel
	hud.ObjectiveLabel = objectiveLabel
	hud.Speedometer = speedo
	return hud
end

return Hud
