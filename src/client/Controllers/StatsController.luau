--[[
	StatsController
	"Your career" panel: doctor level, hospital, patients, money, doctors...
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local HospitalLevels = require(Shared:WaitForChild("Config"):WaitForChild("HospitalLevels"))
local Format = require(Shared:WaitForChild("Util"):WaitForChild("Format"))
local UIKit = require(script.Parent.Parent.UI.UIKit)
local Theme = UIKit.Theme

local StatsController = {}

local controllers: any = nil
local panel: Frame
local grid: Frame
local isOpen = false

local function tile(order: number, emoji: string, title: string, value: string)
	local frame = UIKit.New("Frame", {
		BackgroundColor3 = Theme.Colors.White,
		LayoutOrder = order,
		Parent = grid,
	}, {
		UIKit.Corner(14),
		UIKit.Stroke(3, Theme.Colors.PanelAlt:Lerp(Theme.Colors.Stroke, 0.25)),
	})
	UIKit.Label({ Text = emoji, TextSize = 34, Size = UDim2.fromOffset(56, 76), Position = UDim2.fromOffset(6, 0), Parent = frame })
	UIKit.Label({
		Text = title,
		Font = Theme.BodyFont,
		TextSize = 14,
		TextColor3 = Theme.Colors.TextMuted,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, -70, 0, 22),
		Position = UDim2.fromOffset(64, 10),
		Parent = frame,
	})
	UIKit.Label({
		Text = value,
		TextSize = 24,
		TextColor3 = Theme.Colors.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextScaled = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Size = UDim2.new(1, -70, 0, 32),
		Position = UDim2.fromOffset(64, 32),
		Parent = frame,
	})
end

local function render()
	local state = controllers.ClientState.Get()
	if not state or not isOpen then
		return
	end
	for _, child in grid:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	local level = HospitalLevels.Get(state.HospitalLevel)
	local rare = state.RareTreated or {}
	local rareText = string.format("%d / %d / %d", rare.Rare or 0, rare.Epic or 0, rare.Legendary or 0)
	tile(1, "🥼", "Doctor Level", string.format("Lv %d (%d/%d XP)", state.DoctorLevel, state.DoctorXP, state.DoctorXPNeeded))
	tile(2, "🏥", "Hospital", string.format("Lv %d %s", level.Level, level.Name))
	tile(3, "🩺", "Patients Treated", Format.Commas(state.PatientsTreated))
	tile(4, "🙋", "Treated by You / Auto", string.format("%s / %s", Format.Short(state.ManualTreated), Format.Short(state.AutoTreated)))
	tile(5, "💰", "Money Earned (all time)", Format.Money(state.LifetimeEarned))
	tile(6, "🏦", "Hospital Value", Format.Money(state.HospitalValue))
	tile(7, "🤖", "Auto Doctors", string.format("%d / %d rooms", #state.Doctors, level.ExamRooms))
	tile(8, "🔥", "Best Combo", "x" .. tostring(state.BestCombo))
	tile(9, "⭐", "Rare / Epic / Legendary", rareText)
	tile(10, "⏱️", "Time Played", Format.Time(state.PlayTime or 0))
	tile(11, "💾", "Saving", if state.SavingEnabled then "On ✔" else "Off (Studio/offline)")
end

function StatsController.Open()
	controllers.ShopController.Close()
	isOpen = true
	panel.Visible = true
	UIKit.PopIn(panel)
	controllers.SoundController.Play("Open")
	render()
end

function StatsController.Close()
	isOpen = false
	if panel then
		panel.Visible = false
	end
end

function StatsController.Toggle()
	if isOpen then
		StatsController.Close()
	else
		StatsController.Open()
	end
end

function StatsController.Init(all: any)
	controllers = all
	local gui = UIKit.New("ScreenGui", {
		Name = "Stats",
		ResetOnSpawn = false,
		DisplayOrder = 6,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
	})
	local content
	panel, content = UIKit.Panel({
		Name = "StatsPanel",
		Title = "📊 YOUR CAREER",
		Size = Vector2.new(720, 520),
		Color = Theme.Colors.Blue,
		Parent = gui,
		OnClose = StatsController.Close,
	})
	grid = UIKit.New("Frame", {
		Position = UDim2.fromOffset(16, 14),
		Size = UDim2.new(1, -32, 1, -28),
		BackgroundTransparency = 1,
		Parent = content,
	}, {
		UIKit.New("UIGridLayout", {
			CellSize = UDim2.fromOffset(334, 76),
			CellPadding = UDim2.fromOffset(12, 10),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
end

function StatsController.Start()
	controllers.ClientState.Changed:Connect(function()
		if isOpen then
			render()
		end
	end)
end

return StatsController
