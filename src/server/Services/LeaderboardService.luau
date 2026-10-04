--[[
	LeaderboardService (MVP)
	Fills the physical board in the plaza with the top players in this server
	by level, plus wins/goals. A global board (OrderedDataStore) comes next.
]]

local Players = game:GetService("Players")

local DataService = require(script.Parent.DataService)
local MapBuilder = require(script.Parent.MapBuilder)

local LeaderboardService = {}

local rows = {}

local function buildBoard(board: BasePart)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 30
	gui.LightInfluence = 0
	gui.Brightness = 1.4
	gui.Parent = board

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, 0, 0.14, 0)
	title.BackgroundColor3 = Color3.fromRGB(205, 255, 64)
	title.Text = "TOP OF THE GROUNDS"
	title.Font = Enum.Font.GothamBlack
	title.TextScaled = true
	title.TextColor3 = Color3.fromRGB(14, 14, 18)
	title.Parent = gui

	local header = Instance.new("TextLabel")
	header.Size = UDim2.new(1, 0, 0.08, 0)
	header.Position = UDim2.fromScale(0, 0.15)
	header.BackgroundTransparency = 1
	header.Text = "  #   PLAYER                         LVL   WINS   GOALS"
	header.Font = Enum.Font.GothamBold
	header.TextScaled = true
	header.TextXAlignment = Enum.TextXAlignment.Left
	header.TextColor3 = Color3.fromRGB(160, 160, 170)
	header.Parent = gui

	for i = 1, 8 do
		local row = Instance.new("TextLabel")
		row.Size = UDim2.new(1, -20, 0.085, 0)
		row.Position = UDim2.new(0, 10, 0.24 + (i - 1) * 0.094, 0)
		row.BackgroundColor3 = if i % 2 == 0 then Color3.fromRGB(28, 28, 34) else Color3.fromRGB(22, 22, 28)
		row.Font = Enum.Font.GothamMedium
		row.TextScaled = true
		row.TextXAlignment = Enum.TextXAlignment.Left
		row.TextColor3 = Color3.new(1, 1, 1)
		row.Text = ""
		row.Parent = gui
		rows[i] = row
	end
end

local function refresh()
	local entries = {}
	for _, player in Players:GetPlayers() do
		local profile = DataService.GetProfile(player)
		if profile then
			table.insert(entries, { Name = player.DisplayName, Level = profile.Level, Wins = profile.Stats.Wins, Goals = profile.Stats.Goals, XP = profile.XP })
		end
	end
	table.sort(entries, function(a, b)
		if a.Level ~= b.Level then
			return a.Level > b.Level
		end
		return a.XP > b.XP
	end)
	for i, row in rows do
		local e = entries[i]
		if e then
			row.Text = string.format("  %d   %-28s  %3d   %4d   %5d", i, string.sub(e.Name, 1, 20), e.Level, e.Wins, e.Goals)
		else
			row.Text = ""
		end
	end
end

function LeaderboardService.Init() end

function LeaderboardService.Start()
	local board = MapBuilder.GetRoot().Hub:FindFirstChild("Leaderboard")
	if not board then
		return
	end
	buildBoard(board)
	task.spawn(function()
		while true do
			refresh()
			task.wait(10)
		end
	end)
end

return LeaderboardService
