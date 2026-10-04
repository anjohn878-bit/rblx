--[[
	MatchHUD
	Scoreboard ("VOLT 2 — 1 EMBER") with the match clock, shown to players in the
	match and to spectators near the pitch. Big centre-screen moments:
	MATCH FOUND -> VOLT vs EMBER rosters -> 3, 2, 1, GO -> GOAL!
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)

local UIKit = require(script.Parent.UIKit)

local T = UIKit.Theme
local new = UIKit.new

local MatchHUD = {}

local player = Players.LocalPlayer
local refs = {}
local SPECTATE_DISTANCE = 110

local function teamBlock(parent, team: string, order: number)
	local info = Config.Teams[team]
	local block = new("Frame", {
		Size = UDim2.fromOffset(150, 52),
		BackgroundColor3 = info.Color,
		LayoutOrder = order,
		Parent = parent,
	}, { UIKit.Corner(10) })
	UIKit.Label({
		Size = UDim2.fromScale(1, 1),
		Text = info.Name,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = info.Dark,
		Font = T.Heavy,
		TextSize = 24,
		Parent = block,
	})
	return block
end

local function buildScoreboard(gui: ScreenGui)
	local board = new("Frame", {
		Name = "Scoreboard",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 14),
		Size = UDim2.fromOffset(440, 86),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = gui,
	})
	local row = new("Frame", {
		Size = UDim2.new(1, 0, 0, 52),
		BackgroundTransparency = 1,
		Parent = board,
	}, { UIKit.List(Enum.FillDirection.Horizontal, 6, Enum.HorizontalAlignment.Center) })
	teamBlock(row, "A", 1)
	local score = new("TextLabel", {
		Size = UDim2.fromOffset(120, 52),
		BackgroundColor3 = T.Bg,
		BackgroundTransparency = 0.05,
		TextColor3 = T.Text,
		Font = T.Heavy,
		TextSize = 30,
		Text = "0 — 0",
		LayoutOrder = 2,
		Parent = row,
	}, { UIKit.Corner(10) })
	teamBlock(row, "B", 3)
	local timer = new("TextLabel", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 58),
		Size = UDim2.fromOffset(110, 26),
		BackgroundColor3 = T.Bg,
		BackgroundTransparency = 0.1,
		TextColor3 = T.Accent,
		Font = T.Heavy,
		TextSize = 18,
		Text = "4:00",
		Parent = board,
	}, { UIKit.Corner(8) })
	refs.Board = board
	refs.Score = score
	refs.Timer = timer
end

local function buildCenter(gui: ScreenGui)
	local center = new("Frame", {
		Name = "Announce",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.38),
		Size = UDim2.fromOffset(900, 300),
		BackgroundTransparency = 1,
		Parent = gui,
	})
	local big = UIKit.Label({
		Name = "Big",
		Size = UDim2.new(1, 0, 0, 110),
		TextXAlignment = Enum.TextXAlignment.Center,
		Font = T.Heavy,
		TextSize = 96,
		Text = "",
		TextTransparency = 1,
		Parent = center,
	})
	new("UIStroke", { Thickness = 3, Color = Color3.new(0, 0, 0), Transparency = 0.3, Parent = big })
	local small = UIKit.Label({
		Name = "Small",
		Position = UDim2.fromOffset(0, 110),
		Size = UDim2.new(1, 0, 0, 40),
		TextXAlignment = Enum.TextXAlignment.Center,
		Font = T.Bold,
		TextSize = 26,
		Text = "",
		TextTransparency = 1,
		Parent = center,
	})
	new("UIStroke", { Thickness = 2, Color = Color3.new(0, 0, 0), Transparency = 0.4, Parent = small })

	-- Rosters "VOLT vs EMBER"
	local versus = new("Frame", {
		Name = "Versus",
		Position = UDim2.fromOffset(0, 160),
		Size = UDim2.new(1, 0, 0, 140),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = center,
	})
	local function rosterColumn(team: string, x: number)
		local col = UIKit.Panel({
			Position = UDim2.new(x, 0, 0, 0),
			Size = UDim2.new(0.4, 0, 1, 0),
			Parent = versus,
		})
		new("UIStroke", { Color = Config.Teams[team].Color, Thickness = 2, Parent = col })
		local list = new("Frame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Parent = col,
		}, { UIKit.List(Enum.FillDirection.Vertical, 4, Enum.HorizontalAlignment.Center), UIKit.Padding(10) })
		return list
	end
	refs.RosterA = rosterColumn("A", 0.05)
	refs.RosterB = rosterColumn("B", 0.55)
	UIKit.Label({
		Position = UDim2.fromScale(0.45, 0.3),
		Size = UDim2.new(0.1, 0, 0, 40),
		Text = "VS",
		TextXAlignment = Enum.TextXAlignment.Center,
		Font = T.Heavy,
		TextSize = 34,
		Parent = versus,
	})
	refs.Big = big
	refs.Small = small
	refs.Versus = versus
end

local announceToken = 0
function MatchHUD.Announce(bigText: string, smallText: string?, color: Color3?, duration: number?)
	announceToken += 1
	local token = announceToken
	refs.Big.Text = bigText
	refs.Big.TextColor3 = color or T.Text
	refs.Small.Text = smallText or ""
	refs.Big.TextTransparency = 1
	refs.Small.TextTransparency = 1
	refs.Big.TextSize = 130
	UIKit.Tween(refs.Big, 0.35, { TextTransparency = 0, TextSize = 96 }, Enum.EasingStyle.Back)
	UIKit.Tween(refs.Small, 0.35, { TextTransparency = 0 })
	task.delay(duration or 1.6, function()
		if token == announceToken then
			UIKit.Tween(refs.Big, 0.3, { TextTransparency = 1 })
			UIKit.Tween(refs.Small, 0.3, { TextTransparency = 1 })
		end
	end)
end

local function fillRoster(list: Frame, entries)
	for _, child in list:GetChildren() do
		if child:IsA("TextLabel") then
			child:Destroy()
		end
	end
	for i, entry in entries do
		local isMe = entry.Id == player.UserId
		UIKit.Label({
			Size = UDim2.new(1, 0, 0, 24),
			TextXAlignment = Enum.TextXAlignment.Center,
			Text = entry.Name .. (if entry.IsBot then "  ·  REGULAR" else ""),
			TextColor3 = if isMe then T.Accent else (if entry.IsBot then T.Muted else T.Text),
			Font = if isMe then T.Heavy else T.Bold,
			TextSize = 18,
			LayoutOrder = i,
			Parent = list,
		})
	end
end

local function onMatchEvent(kind: string, payload)
	if kind == "MatchFound" then
		MatchHUD.Announce("MATCH FOUND", payload.PitchName .. " · 3v3", T.Accent, 1.4)
		task.delay(1.5, function()
			fillRoster(refs.RosterA, payload.Teams.A)
			fillRoster(refs.RosterB, payload.Teams.B)
			MatchHUD.Announce(Config.Teams.A.Name .. "  vs  " .. Config.Teams.B.Name, "Get ready", T.Text, 2.4)
			refs.Versus.Visible = true
			task.delay(2.5, function()
				refs.Versus.Visible = false
			end)
		end)
	elseif kind == "Countdown" then
		if payload.PitchId ~= player:GetAttribute("MatchId") then
			return
		end
		local seconds = payload.Seconds or 3
		task.spawn(function()
			for i = seconds, 1, -1 do
				MatchHUD.Announce(tostring(i), nil, T.Text, 0.8)
				task.wait(1)
			end
			MatchHUD.Announce("GO!", nil, T.Accent, 0.7)
		end)
	elseif kind == "Goal" then
		local inThisMatch = payload.PitchId == player:GetAttribute("MatchId")
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		local nearby = root and payload.BallPosition and (root.Position - payload.BallPosition).Magnitude < SPECTATE_DISTANCE * 1.5
		if not inThisMatch and not nearby then
			return
		end
		local teamInfo = Config.Teams[payload.Team]
		local line
		if payload.OwnGoal then
			line = "Own goal!"
		elseif payload.Scorer then
			line = payload.Scorer .. (if payload.Assister then "  ·  assist " .. payload.Assister else "")
		end
		MatchHUD.Announce("GOAL!", line, teamInfo.Color, 3)
	end
end

local function nearestActiveMatch()
	local matches = ReplicatedStorage:FindFirstChild("Matches")
	if not matches then
		return nil
	end
	local myMatch = player:GetAttribute("MatchId")
	if myMatch then
		return matches:FindFirstChild(myMatch)
	end
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return nil
	end
	for _, state in matches:GetChildren() do
		local s = state:GetAttribute("State")
		if s and s ~= "Idle" and s ~= "MatchFound" then
			local center = Vector3.new(state:GetAttribute("CenterX") or 0, root.Position.Y, state:GetAttribute("CenterZ") or 0)
			if (center - root.Position).Magnitude < SPECTATE_DISTANCE then
				return state
			end
		end
	end
	return nil
end

local lastUpdate = 0
local function update()
	local now = os.clock()
	if now - lastUpdate < 0.1 then
		return
	end
	lastUpdate = now
	local state = nearestActiveMatch()
	local s = state and state:GetAttribute("State")
	local show = s ~= nil and s ~= "Idle" and s ~= "MatchFound"
	refs.Board.Visible = show
	if not show then
		return
	end
	refs.Score.Text = string.format("%d — %d", state:GetAttribute("ScoreA") or 0, state:GetAttribute("ScoreB") or 0)
	local timeLeft
	local endsAt = state:GetAttribute("EndsAt") or 0
	if s == "Playing" and endsAt > 0 then
		timeLeft = endsAt - Workspace:GetServerTimeNow()
	else
		timeLeft = state:GetAttribute("TimeLeft") or 0
	end
	timeLeft = math.max(0, math.ceil(timeLeft))
	refs.Timer.Text = if s == "Ended" then "FULL TIME" else string.format("%d:%02d", timeLeft // 60, timeLeft % 60)
	refs.Timer.TextColor3 = if timeLeft <= 30 and s == "Playing" then T.Secondary else T.Accent
	refs.Timer.Size = if s == "Ended" then UDim2.fromOffset(130, 26) else UDim2.fromOffset(110, 26)
end

function MatchHUD.Create(gui: ScreenGui)
	buildScoreboard(gui)
	buildCenter(gui)
	Remotes.Get("MatchEvent").OnClientEvent:Connect(onMatchEvent)
	RunService.Heartbeat:Connect(update)
end

return MatchHUD
