--[[
	ProfilePanel
	Level, title, reputation progress, lifetime stats and the attribute
	upgrade screen (points come from levelling up, never from purchases).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Progression = require(Shared.Progression)
local Remotes = require(Shared.Remotes)

local ClientState = require(script.Parent.Parent.ClientState)
local UIKit = require(script.Parent.UIKit)

local T = UIKit.Theme
local new = UIKit.new

local ProfilePanel = {}

local player = Players.LocalPlayer
local frame: Frame
local refs = { Stats = {}, Attributes = {} }

local ATTRIBUTE_LABELS = {
	Pace = "PACE", Shooting = "SHOOTING", Passing = "PASSING", Dribbling = "DRIBBLING",
	BallControl = "BALL CONTROL", Defending = "DEFENDING", Physicality = "PHYSICAL", Stamina = "STAMINA",
}
local STAT_ORDER = {
	{ "Matches", "MATCHES" }, { "Wins", "WINS" }, { "Draws", "DRAWS" }, { "Losses", "LOSSES" },
	{ "Goals", "GOALS" }, { "Assists", "ASSISTS" }, { "Passes", "PASSES" }, { "Tackles", "TACKLES" },
	{ "SkillMoves", "SKILLS" }, { "BestWinStreak", "BEST STREAK" }, { "WinRate", "WIN RATE" },
}

local function refresh()
	local profile = ClientState.Profile
	if not profile or not frame then
		return
	end
	local tierIndex, tierName, nextMin = Progression.GetReputationTier(profile.Reputation)
	local tierMin = Progression.ReputationTiers[tierIndex].Min
	refs.Header.Text = string.format("LEVEL %d · %s", profile.Level, string.upper(Progression.GetTitle(profile.Level)))
	refs.RepText.Text = if nextMin
		then string.format("REPUTATION · %s  (%d / %d)", string.upper(tierName), profile.Reputation, nextMin)
		else string.format("REPUTATION · %s  (%d)", string.upper(tierName), profile.Reputation)
	refs.RepFill.Size = UDim2.fromScale(if nextMin then math.clamp((profile.Reputation - tierMin) / (nextMin - tierMin), 0, 1) else 1, 1)

	local s = profile.Stats
	for key, label in refs.Stats do
		if key == "WinRate" then
			label.Text = if s.Matches > 0 then string.format("%d%%", math.floor(s.Wins / s.Matches * 100 + 0.5)) else "—"
		else
			label.Text = UIKit.FormatNumber(s[key] or 0)
		end
	end

	refs.Points.Text = string.format("%d POINT%s TO SPEND", profile.AttributePoints, if profile.AttributePoints == 1 then "" else "S")
	refs.Points.TextColor3 = if profile.AttributePoints > 0 then T.Accent else T.Muted
	for name, r in refs.Attributes do
		local value = profile.Attributes[name] or Config.Attributes.Start
		r.Value.Text = tostring(value)
		r.Fill.Size = UDim2.fromScale(value / Config.Attributes.Max, 1)
		r.Plus.Visible = profile.AttributePoints > 0 and value < Config.Attributes.Max
	end
end

function ProfilePanel.Create(gui: ScreenGui, close: () -> ())
	frame = UIKit.Panel({
		Name = "Profile",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(820, 520),
		Visible = false,
		Parent = gui,
	})
	UIKit.Label({ Size = UDim2.new(1, -80, 0, 30), Position = UDim2.fromOffset(20, 12), Text = string.upper(player.DisplayName), Font = T.Heavy, TextSize = 28, Parent = frame })
	refs.Header = UIKit.Label({ Size = UDim2.new(1, -80, 0, 20), Position = UDim2.fromOffset(20, 44), TextColor3 = T.Accent, Font = T.Heavy, TextSize = 16, Text = "", Parent = frame })
	UIKit.Button({ Size = UDim2.fromOffset(40, 40), Position = UDim2.new(1, -52, 0, 12), Text = "✕", Parent = frame }, close)

	refs.RepText = UIKit.Label({ Size = UDim2.new(0.5, -30, 0, 18), Position = UDim2.fromOffset(20, 74), TextColor3 = T.Muted, Font = T.Bold, TextSize = 13, Text = "", Parent = frame })
	local _, repFill = UIKit.Bar({ Size = UDim2.new(0.5, -30, 0, 8), Position = UDim2.fromOffset(20, 96), Parent = frame }, T.Secondary)
	refs.RepFill = repFill

	-- Stats grid (left)
	local stats = new("Frame", {
		Size = UDim2.new(0.5, -30, 1, -140),
		Position = UDim2.fromOffset(20, 120),
		BackgroundTransparency = 1,
		Parent = frame,
	}, { new("UIGridLayout", { CellSize = UDim2.fromOffset(120, 64), CellPadding = UDim2.fromOffset(8, 8), SortOrder = Enum.SortOrder.LayoutOrder }) })
	for i, entry in STAT_ORDER do
		local cell = new("Frame", { BackgroundColor3 = T.PanelLight, LayoutOrder = i, Parent = stats }, { UIKit.Corner(10) })
		UIKit.Label({ Size = UDim2.new(1, -16, 0, 14), Position = UDim2.fromOffset(8, 8), TextColor3 = T.Muted, Font = T.Bold, TextSize = 11, Text = entry[2], Parent = cell })
		refs.Stats[entry[1]] = UIKit.Label({ Size = UDim2.new(1, -16, 0, 30), Position = UDim2.fromOffset(8, 24), Font = T.Heavy, TextSize = 24, Text = "0", Parent = cell })
	end

	-- Attributes (right)
	local right = new("Frame", {
		Size = UDim2.new(0.5, -30, 1, -80),
		Position = UDim2.new(0.5, 10, 0, 70),
		BackgroundTransparency = 1,
		Parent = frame,
	})
	UIKit.Label({ Size = UDim2.new(1, 0, 0, 22), Text = "PLAYER ATTRIBUTES", Font = T.Heavy, TextSize = 18, Parent = right })
	refs.Points = UIKit.Label({ Size = UDim2.new(1, 0, 0, 18), Position = UDim2.fromOffset(0, 24), Font = T.Bold, TextSize = 13, Text = "", Parent = right })
	for i, name in Config.Attributes.List do
		local y = 52 + (i - 1) * 46
		UIKit.Label({ Size = UDim2.new(0.5, 0, 0, 16), Position = UDim2.fromOffset(0, y), Text = ATTRIBUTE_LABELS[name] or name, Font = T.Bold, TextSize = 13, Parent = right })
		local value = UIKit.Label({ Size = UDim2.fromOffset(40, 16), Position = UDim2.new(1, -86, 0, y), Text = "50", TextXAlignment = Enum.TextXAlignment.Right, Font = T.Heavy, TextSize = 15, Parent = right })
		local _, fill = UIKit.Bar({ Size = UDim2.new(1, -50, 0, 10), Position = UDim2.fromOffset(0, y + 20), Parent = right }, T.Accent)
		local plus = UIKit.Button({
			Size = UDim2.fromOffset(36, 30),
			Position = UDim2.new(1, -38, 0, y),
			Text = "+",
			TextSize = 20,
			BackgroundColor3 = T.Accent,
			TextColor3 = T.AccentDark,
			Parent = right,
		}, function()
			pcall(function()
				Remotes.Get("SpendAttribute"):InvokeServer(name)
			end)
		end)
		refs.Attributes[name] = { Value = value, Fill = fill, Plus = plus }
	end
	UIKit.Label({
		Size = UDim2.new(1, 0, 0, 30),
		Position = UDim2.fromOffset(0, 52 + #Config.Attributes.List * 46),
		Text = "Earn points by levelling up. Attributes give small boosts; skill decides games.",
		TextWrapped = true,
		TextColor3 = T.Muted,
		Font = T.Medium,
		TextSize = 12,
		Parent = right,
	})

	ClientState.Changed:Connect(refresh)
end

function ProfilePanel.Open()
	frame.Visible = true
	refresh()
end

function ProfilePanel.Close()
	frame.Visible = false
end

return ProfilePanel
