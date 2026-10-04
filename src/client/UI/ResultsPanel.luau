--[[
	ResultsPanel
	End-of-match screen: outcome, final score, your stat line, rewards with an
	animated XP bar, every player's line, and a one-click PLAY AGAIN.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Progression = require(Shared.Progression)
local Remotes = require(Shared.Remotes)

local UIKit = require(script.Parent.UIKit)

local T = UIKit.Theme
local new = UIKit.new

local ResultsPanel = {}

local player = Players.LocalPlayer
local frame: Frame
local refs = {}

local function clearList(list: Instance)
	for _, child in list:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

function ResultsPanel.Create(gui: ScreenGui, close: () -> ())
	frame = UIKit.Panel({
		Name = "Results",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(860, 540),
		Visible = false,
		Parent = gui,
	})
	refs.Outcome = UIKit.Label({ Size = UDim2.new(1, -40, 0, 60), Position = UDim2.fromOffset(20, 10), Font = T.Heavy, TextSize = 52, Text = "VICTORY", Parent = frame })
	refs.Score = UIKit.Label({ Size = UDim2.new(1, -40, 0, 26), Position = UDim2.fromOffset(22, 70), Font = T.Bold, TextSize = 20, TextColor3 = T.Muted, Text = "", Parent = frame })

	-- Left: your match + rewards
	local left = new("Frame", { Size = UDim2.new(0.42, -20, 1, -190), Position = UDim2.fromOffset(20, 110), BackgroundColor3 = T.Bg, Parent = frame }, { UIKit.Corner(12), UIKit.Padding(14) })
	UIKit.Label({ Size = UDim2.new(1, 0, 0, 20), Text = "YOUR MATCH", Font = T.Heavy, TextSize = 16, Parent = left })
	refs.MyLine = UIKit.Label({ Size = UDim2.new(1, 0, 0, 44), Position = UDim2.fromOffset(0, 24), Font = T.Bold, TextSize = 14, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, Text = "", Parent = left })
	UIKit.Label({ Size = UDim2.new(1, 0, 0, 20), Position = UDim2.fromOffset(0, 78), Text = "REWARDS", Font = T.Heavy, TextSize = 16, Parent = left })
	refs.XP = UIKit.Label({ Size = UDim2.new(1, 0, 0, 22), Position = UDim2.fromOffset(0, 102), Font = T.Heavy, TextSize = 18, TextColor3 = T.Accent, Text = "", Parent = left })
	refs.Kicks = UIKit.Label({ Size = UDim2.new(1, 0, 0, 22), Position = UDim2.fromOffset(0, 126), Font = T.Heavy, TextSize = 18, TextColor3 = T.Gold, Text = "", Parent = left })
	refs.Rep = UIKit.Label({ Size = UDim2.new(1, 0, 0, 22), Position = UDim2.fromOffset(0, 150), Font = T.Heavy, TextSize = 18, TextColor3 = T.Secondary, Text = "", Parent = left })
	refs.LevelText = UIKit.Label({ Size = UDim2.new(1, 0, 0, 18), Position = UDim2.fromOffset(0, 184), Font = T.Bold, TextSize = 13, TextColor3 = T.Muted, Text = "", Parent = left })
	local _, xpFill = UIKit.Bar({ Size = UDim2.new(1, 0, 0, 10), Position = UDim2.fromOffset(0, 206), Parent = left }, T.Accent)
	refs.XPFill = xpFill

	-- Right: everyone's line
	local right = new("Frame", { Size = UDim2.new(0.58, -20, 1, -190), Position = UDim2.new(0.42, 10, 0, 110), BackgroundColor3 = T.Bg, Parent = frame }, { UIKit.Corner(12), UIKit.Padding(14) })
	UIKit.Label({ Size = UDim2.new(1, 0, 0, 20), Text = "PLAYER                         G    A    PASS  TKL", Font = T.Heavy, TextSize = 13, TextColor3 = T.Muted, Parent = right })
	refs.Table = new("Frame", { Size = UDim2.new(1, 0, 1, -26), Position = UDim2.fromOffset(0, 26), BackgroundTransparency = 1, Parent = right }, { UIKit.List(Enum.FillDirection.Vertical, 4) })

	-- Buttons
	UIKit.Button({
		Size = UDim2.fromOffset(240, 54),
		Position = UDim2.new(1, -260, 1, -70),
		Text = "PLAY AGAIN",
		TextSize = 20,
		BackgroundColor3 = T.Accent,
		TextColor3 = T.AccentDark,
		Parent = frame,
	}, function()
		Remotes.Get("RequestQueue"):FireServer(true)
		close()
	end)
	UIKit.Button({
		Size = UDim2.fromOffset(240, 54),
		Position = UDim2.new(1, -510, 1, -70),
		Text = "BACK TO THE GROUNDS",
		TextSize = 16,
		Parent = frame,
	}, close)
end

function ResultsPanel.Show(data)
	local outcomeText = if data.Aborted then "MATCH ENDED" elseif data.Outcome == "Win" then "VICTORY" elseif data.Outcome == "Draw" then "DRAW" else "DEFEAT"
	refs.Outcome.Text = outcomeText
	refs.Outcome.TextColor3 = if data.Outcome == "Win" then T.Accent elseif data.Outcome == "Draw" then T.Text else T.Secondary
	refs.Score.Text = string.format("%s %d — %d %s   ·   you played for %s", Config.Teams.A.Name, data.ScoreA, data.ScoreB, Config.Teams.B.Name, Config.Teams[data.MyTeam] and Config.Teams[data.MyTeam].Name or "?")

	local s = data.MyStats or {}
	refs.MyLine.Text = string.format("%d goals · %d assists · %d passes · %d tackles · %d shots · %d skills", s.Goals or 0, s.Assists or 0, s.Passes or 0, s.Tackles or 0, s.Shots or 0, s.SkillMoves or 0)

	local rewards = data.Rewards
	if rewards then
		refs.XP.Text = "+" .. UIKit.FormatNumber(rewards.XP) .. " XP"
		refs.Kicks.Text = "+" .. UIKit.FormatNumber(rewards.Kicks) .. " " .. Config.CurrencyName
		refs.Rep.Text = "+" .. rewards.Reputation .. " Reputation"
		local before, after = rewards.Before, rewards.After
		local leveled = after.Level > before.Level
		refs.LevelText.Text = if leveled then string.format("LEVEL UP!  %d → %d", before.Level, after.Level) else string.format("Level %d", after.Level)
		refs.LevelText.TextColor3 = if leveled then T.Accent else T.Muted
		refs.XPFill.Size = UDim2.fromScale(if leveled then 0 else before.XP / Progression.XPToNext(before.Level), 1)
		task.delay(0.4, function()
			UIKit.Tween(refs.XPFill, 1.2, { Size = UDim2.fromScale(math.clamp(after.XP / Progression.XPToNext(after.Level), 0, 1), 1) })
		end)
	else
		refs.XP.Text = "No rewards (match did not finish)"
		refs.Kicks.Text = ""
		refs.Rep.Text = ""
		refs.LevelText.Text = ""
		refs.XPFill.Size = UDim2.fromScale(0, 1)
	end

	clearList(refs.Table)
	for i, p in data.Players or {} do
		local color = Config.Teams[p.Team] and Config.Teams[p.Team].Color or T.Text
		local isMe = p.Id == player.UserId
		local rowFrame = new("Frame", { Size = UDim2.new(1, 0, 0, 30), BackgroundColor3 = if isMe then T.PanelLight else T.Panel, LayoutOrder = i, Parent = refs.Table }, { UIKit.Corner(6) })
		new("Frame", { Size = UDim2.new(0, 4, 1, -8), Position = UDim2.fromOffset(4, 4), BackgroundColor3 = color, Parent = rowFrame })
		UIKit.Label({
			Size = UDim2.new(0.55, -14, 1, 0),
			Position = UDim2.fromOffset(14, 0),
			Text = (if i == 1 then "★ " else "") .. p.Name .. (if p.IsBot then " (Regular)" else ""),
			TextTruncate = Enum.TextTruncate.AtEnd,
			Font = if isMe then T.Heavy else T.Bold,
			TextColor3 = if isMe then T.Accent else T.Text,
			TextSize = 14,
			Parent = rowFrame,
		})
		UIKit.Label({
			Size = UDim2.new(0.45, -10, 1, 0),
			Position = UDim2.new(0.55, 0, 0, 0),
			Text = string.format("%d    %d    %d    %d", p.Goals, p.Assists, p.Passes, p.Tackles),
			Font = T.Bold,
			TextSize = 14,
			Parent = rowFrame,
		})
	end

	frame.Visible = true
end

function ResultsPanel.Open()
	frame.Visible = true
end

function ResultsPanel.Close()
	frame.Visible = false
end

return ResultsPanel
