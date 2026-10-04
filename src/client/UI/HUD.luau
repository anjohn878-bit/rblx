--[[
	HUD
	Always-on interface: profile card (avatar, level, title, XP, Kicks,
	reputation), main menu buttons, stamina + shot charge bars, control hints,
	queue status pill and toast notifications.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Progression = require(Shared.Progression)
local Remotes = require(Shared.Remotes)

local ClientState = require(script.Parent.Parent.ClientState)
local InputController = require(script.Parent.Parent.Controllers.InputController)
local UIKit = require(script.Parent.UIKit)

local T = UIKit.Theme
local new = UIKit.new

local HUD = {}

local player = Players.LocalPlayer
local refs = {}

local function buildProfileCard(gui: ScreenGui)
	local card = UIKit.Panel({
		Name = "ProfileCard",
		Size = UDim2.fromOffset(300, 92),
		Position = UDim2.fromOffset(16, 16),
		Parent = gui,
	})
	local avatar = new("ImageLabel", {
		Size = UDim2.fromOffset(68, 68),
		Position = UDim2.fromOffset(12, 12),
		BackgroundColor3 = T.PanelLight,
		Image = "",
		Parent = card,
	}, { UIKit.Corner(34), UIKit.Stroke(T.Accent, 2) })
	task.spawn(function()
		local ok, image = pcall(function()
			return Players:GetUserThumbnailAsync(player.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size100x100)
		end)
		if ok then
			avatar.Image = image
		end
	end)
	local levelBadge = new("TextLabel", {
		Size = UDim2.fromOffset(30, 22),
		Position = UDim2.fromOffset(56, 60),
		BackgroundColor3 = T.Accent,
		TextColor3 = T.AccentDark,
		Font = T.Heavy,
		TextSize = 14,
		Text = "1",
		Parent = card,
	}, { UIKit.Corner(8) })
	UIKit.Label({
		Size = UDim2.new(1, -100, 0, 22),
		Position = UDim2.fromOffset(92, 10),
		Text = player.DisplayName,
		Font = T.Heavy,
		TextSize = 18,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = card,
	})
	local title = UIKit.Label({
		Size = UDim2.new(1, -100, 0, 16),
		Position = UDim2.fromOffset(92, 32),
		Text = "Fresh Laces · Unknown",
		TextColor3 = T.Accent,
		Font = T.Bold,
		TextSize = 13,
		Parent = card,
	})
	local _, xpFill = UIKit.Bar({
		Size = UDim2.new(1, -104, 0, 8),
		Position = UDim2.fromOffset(92, 54),
		Parent = card,
	}, T.Accent)
	local kicks = UIKit.Label({
		Size = UDim2.new(0.5, -50, 0, 16),
		Position = UDim2.fromOffset(92, 66),
		Text = "◆ 0",
		TextColor3 = T.Gold,
		Font = T.Heavy,
		TextSize = 14,
		Parent = card,
	})
	local xpText = UIKit.Label({
		Size = UDim2.new(0.5, -60, 0, 16),
		Position = UDim2.new(0.5, 40, 0, 66),
		Text = "0 / 100 XP",
		TextColor3 = T.Muted,
		TextXAlignment = Enum.TextXAlignment.Right,
		Font = T.Medium,
		TextSize = 12,
		Parent = card,
	})
	refs.Level = levelBadge
	refs.Title = title
	refs.XPFill = xpFill
	refs.Kicks = kicks
	refs.XPText = xpText
end

local function buildMenu(gui: ScreenGui, open: (string) -> ())
	local menu = new("Frame", {
		Name = "Menu",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(150, 260),
		Position = UDim2.new(0, 16, 0.5, -110),
		Parent = gui,
	}, { UIKit.List(Enum.FillDirection.Vertical, 8) })
	local entries = {
		{ "PLAY", "Play", T.Accent, T.AccentDark },
		{ "LOCKER", "Locker", T.PanelLight, T.Text },
		{ "PROFILE", "Profile", T.PanelLight, T.Text },
		{ "SETTINGS", "Settings", T.PanelLight, T.Text },
	}
	for i, e in entries do
		local button = UIKit.Button({
			Size = UDim2.new(1, 0, 0, 46),
			Text = e[1],
			BackgroundColor3 = e[3],
			TextColor3 = e[4],
			TextSize = 18,
			LayoutOrder = i,
			Parent = menu,
		}, function()
			open(e[2])
		end)
		if i == 1 then
			refs.PlayButton = button
		end
	end
	local hint = UIKit.Label({
		Size = UDim2.new(1, 0, 0, 16),
		Text = "M to toggle menu",
		TextColor3 = T.Muted,
		Font = T.Medium,
		TextSize = 12,
		LayoutOrder = 10,
		Parent = menu,
	})
	if InputController.IsTouch() then
		hint.Visible = false
	end
	refs.Menu = menu
end

local function buildBottom(gui: ScreenGui)
	local bottom = new("Frame", {
		Name = "Bottom",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -18),
		Size = UDim2.fromOffset(420, 70),
		Parent = gui,
	})
	UIKit.Label({
		Size = UDim2.fromOffset(80, 14),
		Position = UDim2.fromOffset(0, 0),
		Text = "STAMINA",
		TextColor3 = T.Muted,
		Font = T.Bold,
		TextSize = 11,
		Parent = bottom,
	})
	local _, stamina = UIKit.Bar({ Size = UDim2.new(1, 0, 0, 10), Position = UDim2.fromOffset(0, 16), Parent = bottom }, T.Accent)
	local chargeBack, charge = UIKit.Bar({ Size = UDim2.new(1, 0, 0, 8), Position = UDim2.fromOffset(0, 30), Visible = false, Parent = bottom }, T.Secondary)
	local controls = UIKit.Label({
		Size = UDim2.new(1, 0, 0, 16),
		Position = UDim2.fromOffset(0, 46),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = T.Muted,
		Font = T.Medium,
		TextSize = 12,
		Text = "LMB Pass · RMB Shoot (hold) · F Through · Space Lob · E Tackle · Q Skill · Shift Sprint · C Camera",
		Parent = bottom,
	})
	refs.Stamina = stamina
	refs.ChargeBack = chargeBack
	refs.Charge = charge
	refs.Controls = controls
	if InputController.IsTouch() then
		controls.Visible = false
	end
end

local function buildQueuePill(gui: ScreenGui)
	local pill = UIKit.Panel({
		Name = "QueuePill",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 16),
		Size = UDim2.fromOffset(380, 46),
		Visible = false,
		Parent = gui,
	})
	local text = UIKit.Label({
		Size = UDim2.new(1, -110, 1, 0),
		Position = UDim2.fromOffset(16, 0),
		Font = T.Bold,
		TextSize = 14,
		Text = "IN QUEUE",
		Parent = pill,
	})
	UIKit.Button({
		Size = UDim2.fromOffset(84, 30),
		Position = UDim2.new(1, -92, 0.5, -15),
		Text = "LEAVE",
		TextSize = 13,
		BackgroundColor3 = T.Danger,
		Parent = pill,
	}, function()
		Remotes.Get("RequestQueue"):FireServer(false)
	end)
	refs.QueuePill = pill
	refs.QueueText = text
end

local function buildToasts(gui: ScreenGui)
	local holder = new("Frame", {
		Name = "Toasts",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 16),
		Size = UDim2.fromOffset(320, 400),
		Parent = gui,
	}, { UIKit.List(Enum.FillDirection.Vertical, 6, Enum.HorizontalAlignment.Right) })
	refs.Toasts = holder
end

function HUD.Toast(text: string, kind: string?)
	local holder = refs.Toasts
	if not holder then
		return
	end
	local color = if kind == "levelup" then T.Accent elseif kind == "error" then T.Danger else T.PanelLight
	local textColor = if kind == "levelup" then T.AccentDark else T.Text
	local toast = new("TextLabel", {
		Size = UDim2.fromOffset(320, 40),
		BackgroundColor3 = color,
		BackgroundTransparency = 0.05,
		TextColor3 = textColor,
		Font = T.Bold,
		TextSize = 14,
		TextWrapped = true,
		Text = text,
		Parent = holder,
	}, { UIKit.Corner(10), UIKit.Padding(8) })
	task.delay(3.5, function()
		UIKit.Tween(toast, 0.4, { BackgroundTransparency = 1, TextTransparency = 1 })
		task.wait(0.45)
		toast:Destroy()
	end)
end

local function refreshProfile(profile)
	if not profile or not refs.Level then
		return
	end
	local _, tierName = Progression.GetReputationTier(profile.Reputation)
	refs.Level.Text = tostring(profile.Level)
	refs.Title.Text = Progression.GetTitle(profile.Level) .. " · " .. tierName
	local need = Progression.XPToNext(profile.Level)
	refs.XPFill.Size = UDim2.fromScale(math.clamp(profile.XP / need, 0, 1), 1)
	refs.XPText.Text = string.format("%s / %s XP", UIKit.FormatNumber(profile.XP), UIKit.FormatNumber(need))
	refs.Kicks.Text = "◆ " .. UIKit.FormatNumber(profile.Kicks) .. " " .. Config.CurrencyName
	if refs.Controls and profile.Settings then
		refs.Controls.Visible = profile.Settings.ShowControls ~= false and not InputController.IsTouch()
	end
end

local function updateFrame()
	if refs.Stamina then
		refs.Stamina.Size = UDim2.fromScale(ClientState.Stamina / Config.Movement.StaminaMax, 1)
		refs.Stamina.BackgroundColor3 = if ClientState.Stamina < 25 then T.Danger else T.Accent
	end
	if refs.Charge then
		local charging = InputController.IsCharging()
		refs.ChargeBack.Visible = charging
		refs.Charge.Size = UDim2.fromScale(InputController.GetChargeAlpha(), 1)
	end

	-- Queue pill
	local queued = player:GetAttribute("QueuedPitch")
	if refs.QueuePill then
		refs.QueuePill.Visible = queued ~= nil
		if queued then
			local matches = ReplicatedStorage:FindFirstChild("Matches")
			local state = matches and matches:FindFirstChild(queued)
			if state then
				local count = state:GetAttribute("QueueCount") or 0
				local needed = state:GetAttribute("QueueNeeded") or 6
				local text = string.format("IN QUEUE · %s · %d/%d", state:GetAttribute("PitchName") or "", count, needed)
				local fillAt = state:GetAttribute("BotFillAt") or 0
				if state:GetAttribute("State") ~= "Idle" then
					text ..= " · next game"
				elseif fillAt > 0 then
					local secondsLeft = math.max(0, math.ceil(fillAt - Workspace:GetServerTimeNow()))
					text ..= string.format(" · Regulars join in %ds", secondsLeft)
				end
				refs.QueueText.Text = text
			end
		end
	end

	-- Hide the menu during matches
	local inMatch = player:GetAttribute("MatchId") ~= nil
	if refs.Menu then
		refs.Menu.Visible = not inMatch
	end
end

function HUD.Create(gui: ScreenGui, openPanel: (string) -> ())
	buildProfileCard(gui)
	buildMenu(gui, openPanel)
	buildBottom(gui)
	buildQueuePill(gui)
	buildToasts(gui)
	ClientState.Changed:Connect(refreshProfile)
	refreshProfile(ClientState.Profile)
	RunService.Heartbeat:Connect(updateFrame)
	Remotes.Get("Notify").OnClientEvent:Connect(HUD.Toast)
end

return HUD
