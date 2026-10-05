--[[
	Everything about the current delivery:
	  * the order card (package, address, countdown, payout, cancel)
	  * toast notifications
	  * the "Delivered!" result popup with the payout breakdown
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Economy = require(ReplicatedStorage.Shared.Economy)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local State = require(script.Parent.State)
local Theme = require(script.Parent.Theme)
local UIKit = require(script.Parent.UIKit)

local OrderPanel = {}

local MAX_TOASTS = 4
local TOAST_SECONDS = 4.5
local RESULT_SECONDS = 5

local function timerColor(remaining: number, limit: number): Color3
	if remaining < 0 then
		return Theme.Red
	end
	local fraction = remaining / math.max(limit, 1)
	if fraction > 0.4 then
		return Theme.Green
	elseif fraction > 0.15 then
		return Theme.Yellow
	end
	return Theme.Red
end

function OrderPanel.build(gui: ScreenGui)
	-- Order card ----------------------------------------------------------------------
	local card = UIKit.panel({
		Name = "OrderCard",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 12),
		Size = UDim2.fromOffset(280, 178),
		Visible = false,
		Parent = gui,
	})
	UIKit.autoScale(card)

	UIKit.label({
		Position = UDim2.fromOffset(16, 10),
		Size = UDim2.new(1, -32, 0, 16),
		Font = Theme.FontBold,
		TextSize = 12,
		TextColor3 = Theme.Orange,
		Text = "CURRENT ORDER",
		Parent = card,
	})
	local packageLabel = UIKit.label({
		Name = "Package",
		Position = UDim2.fromOffset(16, 28),
		Size = UDim2.new(1, -32, 0, 18),
		Font = Theme.FontMedium,
		TextSize = 14,
		TextColor3 = Theme.TextDim,
		Text = "",
		Parent = card,
	})
	local addressLabel = UIKit.label({
		Name = "Address",
		Position = UDim2.fromOffset(16, 46),
		Size = UDim2.new(1, -32, 0, 28),
		Font = Theme.FontBold,
		TextSize = 24,
		TextScaled = false,
		Text = "",
		Parent = card,
	})
	local timerLabel = UIKit.label({
		Name = "Timer",
		Position = UDim2.fromOffset(16, 78),
		Size = UDim2.new(0.5, 0, 0, 44),
		Font = Theme.FontBold,
		TextSize = 40,
		TextColor3 = Theme.Green,
		Text = "0:00",
		Parent = card,
	})
	local timerCaption = UIKit.label({
		Name = "TimerCaption",
		Position = UDim2.fromOffset(16, 120),
		Size = UDim2.new(0.5, 0, 0, 16),
		Font = Theme.FontMedium,
		TextSize = 12,
		TextColor3 = Theme.TextDim,
		Text = "TIME LEFT",
		Parent = card,
	})
	local payLabel = UIKit.label({
		Name = "Pay",
		Position = UDim2.new(0.5, 0, 0, 84),
		Size = UDim2.new(0.5, -16, 0, 22),
		Font = Theme.FontBold,
		TextSize = 20,
		TextColor3 = Theme.Green,
		TextXAlignment = Enum.TextXAlignment.Right,
		Text = "",
		Parent = card,
	})
	local distanceLabel = UIKit.label({
		Name = "Distance",
		Position = UDim2.new(0.5, 0, 0, 108),
		Size = UDim2.new(0.5, -16, 0, 18),
		Font = Theme.FontMedium,
		TextSize = 14,
		TextColor3 = Theme.TextDim,
		TextXAlignment = Enum.TextXAlignment.Right,
		Text = "",
		Parent = card,
	})
	UIKit.button({
		Name = "CancelButton",
		Position = UDim2.new(1, -96, 1, -38),
		Size = UDim2.fromOffset(80, 28),
		Text = "CANCEL",
		TextSize = 13,
		BackgroundColor3 = Theme.NavyLighter,
		TextColor3 = Theme.TextDim,
		OnClick = function()
			Remotes.CancelOrder:FireServer()
		end,
		Parent = card,
	})
	UIKit.label({
		Position = UDim2.new(0, 16, 1, -38),
		Size = UDim2.new(1, -120, 0, 28),
		Font = Theme.FontMedium,
		TextSize = 12,
		TextColor3 = Theme.TextDim,
		TextWrapped = true,
		Text = "Slow down inside the ring to deliver.",
		Parent = card,
	})

	-- Toasts ------------------------------------------------------------------------------
	local toastHolder = UIKit.create("Frame", {
		Name = "Toasts",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 176),
		Size = UDim2.fromOffset(460, 200),
		BackgroundTransparency = 1,
		Parent = gui,
	}, {
		UIKit.list({
			Padding = UDim.new(0, 6),
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
		}),
	})
	UIKit.autoScale(toastHolder)
	local toastOrder = 0

	local function toast(message: string, kind: string?)
		local accent = Theme.Kinds[kind or "info"] or Theme.Kinds.info
		toastOrder += 1
		local pill = UIKit.panel({
			Name = "Toast",
			Size = UDim2.fromOffset(0, 40), -- animates open
			LayoutOrder = toastOrder,
			ClipsDescendants = true,
			BackgroundTransparency = 0.05,
			Parent = toastHolder,
		})
		local stroke = pill:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Color = accent
			stroke.Transparency = 0
		end
		UIKit.create("Frame", {
			Position = UDim2.fromOffset(6, 6),
			Size = UDim2.new(0, 4, 1, -12),
			BackgroundColor3 = accent,
			BorderSizePixel = 0,
			Parent = pill,
		}, { UIKit.corner(2) })
		UIKit.label({
			Position = UDim2.fromOffset(16, 0),
			Size = UDim2.new(1, -28, 1, 0),
			Font = Theme.FontBold,
			TextSize = 16,
			TextWrapped = true,
			Text = message,
			Parent = pill,
		})
		UIKit.tween(pill, 0.2, { Size = UDim2.fromOffset(440, 40) })

		-- Oldest toasts make room when too many pile up.
		local children = toastHolder:GetChildren()
		local pills = {}
		for _, child in children do
			if child.Name == "Toast" then
				table.insert(pills, child)
			end
		end
		if #pills > MAX_TOASTS then
			table.sort(pills, function(a, b)
				return a.LayoutOrder < b.LayoutOrder
			end)
			pills[1]:Destroy()
		end

		task.delay(TOAST_SECONDS, function()
			if pill.Parent then
				UIKit.tween(pill, 0.25, { Size = UDim2.fromOffset(0, 40), BackgroundTransparency = 1 })
				task.delay(0.3, function()
					pill:Destroy()
				end)
			end
		end)
	end

	-- Result popup --------------------------------------------------------------------------
	local result = UIKit.panel({
		Name = "ResultCard",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.42, 0),
		Size = UDim2.fromOffset(340, 320),
		Visible = false,
		BackgroundTransparency = 0.05,
		Parent = gui,
	})
	UIKit.autoScale(result)
	local resultTitle = UIKit.label({
		Name = "Title",
		Position = UDim2.fromOffset(0, 14),
		Size = UDim2.new(1, 0, 0, 34),
		Font = Theme.FontBold,
		TextSize = 30,
		TextColor3 = Theme.Green,
		TextXAlignment = Enum.TextXAlignment.Center,
		Text = "DELIVERED!",
		Parent = result,
	})
	local resultAddress = UIKit.label({
		Name = "Address",
		Position = UDim2.fromOffset(0, 48),
		Size = UDim2.new(1, 0, 0, 20),
		Font = Theme.FontMedium,
		TextSize = 15,
		TextColor3 = Theme.TextDim,
		TextXAlignment = Enum.TextXAlignment.Center,
		Text = "",
		Parent = result,
	})
	local resultStars = UIKit.label({
		Name = "Stars",
		Position = UDim2.fromOffset(0, 72),
		Size = UDim2.new(1, 0, 0, 34),
		Font = Theme.FontBold,
		TextSize = 28,
		TextColor3 = Theme.Yellow,
		TextXAlignment = Enum.TextXAlignment.Center,
		Text = "",
		Parent = result,
	})
	local lines = UIKit.create("Frame", {
		Name = "Lines",
		Position = UDim2.fromOffset(24, 114),
		Size = UDim2.new(1, -48, 0, 130),
		BackgroundTransparency = 1,
		Parent = result,
	}, { UIKit.list({ Padding = UDim.new(0, 2) }) })
	local resultTotal = UIKit.label({
		Name = "Total",
		Position = UDim2.new(0, 0, 1, -62),
		Size = UDim2.new(1, 0, 0, 40),
		Font = Theme.FontBold,
		TextSize = 36,
		TextColor3 = Theme.Green,
		TextXAlignment = Enum.TextXAlignment.Center,
		Text = "",
		Parent = result,
	})
	local resultXP = UIKit.label({
		Name = "XP",
		Position = UDim2.new(0, 0, 1, -26),
		Size = UDim2.new(1, 0, 0, 20),
		Font = Theme.FontBold,
		TextSize = 14,
		TextColor3 = Theme.Orange,
		TextXAlignment = Enum.TextXAlignment.Center,
		Text = "",
		Parent = result,
	})
	local resultToken = 0

	local function addLine(index: number, name: string, value: string, color: Color3?)
		local row = UIKit.create("Frame", {
			Name = "Line" .. index,
			Size = UDim2.new(1, 0, 0, 24),
			BackgroundTransparency = 1,
			LayoutOrder = index,
			Parent = lines,
		})
		UIKit.label({
			Size = UDim2.fromScale(0.6, 1),
			TextSize = 16,
			TextColor3 = Theme.TextDim,
			Text = name,
			Parent = row,
		})
		UIKit.label({
			Position = UDim2.fromScale(0.6, 0),
			Size = UDim2.fromScale(0.4, 1),
			Font = Theme.FontBold,
			TextSize = 16,
			TextColor3 = color or Theme.Text,
			TextXAlignment = Enum.TextXAlignment.Right,
			Text = value,
			Parent = row,
		})
	end

	local function showResult(data)
		resultToken += 1
		local token = resultToken
		for _, child in lines:GetChildren() do
			if child:IsA("Frame") then
				child:Destroy()
			end
		end

		resultTitle.Text = data.OnTime and "DELIVERED!" or "DELIVERED... LATE"
		resultTitle.TextColor3 = data.OnTime and Theme.Green or Theme.Yellow
		resultAddress.Text = string.format("%s to %s", data.Package, data.Address)
		resultStars.Text = string.rep("★", data.Stars) .. string.rep("☆", 5 - data.Stars)

		local index = 0
		local function line(name, value, color)
			index += 1
			addLine(index, name, value, color)
		end
		line("Delivery fee", Economy.formatMoney(data.Base))
		if data.TimeBonus > 0 then
			line("Speed bonus", "+" .. Economy.formatMoney(data.TimeBonus), Theme.Green)
		end
		if data.Tip > 0 then
			line("Customer tip", "+" .. Economy.formatMoney(data.Tip), Theme.Green)
		end
		if data.StreakBonus > 0 then
			line(string.format("Streak x%d", data.Streak - 1), "+" .. Economy.formatMoney(data.StreakBonus), Theme.Orange)
		end
		if not data.OnTime then
			line("Late - no bonuses", "", Theme.Red)
		end

		resultTotal.Text = "+" .. Economy.formatMoney(data.Total)
		resultXP.Text = string.format("+%d XP", data.XP) .. (data.RankedUpTo and ("   -   RANK UP: " .. string.upper(data.RankedUpTo)) or "")

		result.Visible = true
		result.Position = UDim2.new(0.5, 0, 0.5, 0)
		UIKit.tween(result, 0.35, { Position = UDim2.new(0.5, 0, 0.42, 0) }, Enum.EasingStyle.Back)
		task.delay(RESULT_SECONDS, function()
			if token == resultToken then
				result.Visible = false
			end
		end)
	end

	-- Live updates --------------------------------------------------------------------------
	local function refreshOrder()
		local active = State.get("OrderId", 0) > 0
		card.Visible = active
		if not active then
			return
		end
		packageLabel.Text = string.upper(State.get("OrderPackage", ""))
		addressLabel.Text = State.get("OrderAddress", "")
		payLabel.Text = "~" .. Economy.formatMoney(State.get("OrderReward", 0))
		distanceLabel.Text = string.format("%d studs away", math.floor(State.get("OrderDistance", 0) + 0.5))
	end
	State.watch("OrderId", refreshOrder)

	UIKit.onFrame(function()
		if not card.Visible then
			return
		end
		local remaining = State.get("OrderDeadline", 0) - Workspace:GetServerTimeNow()
		local color = timerColor(remaining, State.get("OrderTimeLimit", 1))
		timerLabel.TextColor3 = color
		if remaining >= 0 then
			timerLabel.Text = Economy.formatTime(remaining)
			timerCaption.Text = "TIME LEFT"
		else
			timerLabel.Text = "+" .. Economy.formatTime(-remaining)
			timerCaption.Text = "LATE - NO BONUS"
		end
	end)

	local panel = {}
	panel.toast = toast
	panel.showResult = showResult

	-- Exposed for tests.
	panel.Card = card
	panel.Result = result
	panel.TimerLabel = timerLabel
	panel.ToastHolder = toastHolder
	return panel
end

return OrderPanel
