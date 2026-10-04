--[[
	SettingsPanel
	Camera sensitivity, default match camera and control hints. Saved to the
	profile through UpdateSettings (server clamps values).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)

local ClientState = require(script.Parent.Parent.ClientState)
local UIKit = require(script.Parent.UIKit)

local T = UIKit.Theme

local SettingsPanel = {}

local frame: Frame
local refs = {}
local settings = { CameraSensitivity = 1, CameraMode = "Follow", ShowControls = true }

local function push()
	Remotes.Get("UpdateSettings"):FireServer(settings)
	-- Apply locally right away; the server copy follows on the next profile sync.
	local profile = ClientState.Profile
	if profile then
		profile.Settings = table.clone(settings)
		ClientState.SetProfile(profile)
	end
end

local function refresh()
	refs.Sens.Text = string.format("%.1fx", settings.CameraSensitivity)
	refs.Mode.Text = string.upper(settings.CameraMode)
	refs.Hints.Text = if settings.ShowControls then "ON" else "OFF"
end

local function row(parent, y: number, label: string)
	UIKit.Label({ Size = UDim2.new(0.5, 0, 0, 40), Position = UDim2.fromOffset(20, y), Text = label, Font = T.Bold, TextSize = 16, Parent = parent })
end

function SettingsPanel.Create(gui: ScreenGui, close: () -> ())
	frame = UIKit.Panel({
		Name = "Settings",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(480, 300),
		Visible = false,
		Parent = gui,
	})
	UIKit.Label({ Size = UDim2.new(1, -80, 0, 30), Position = UDim2.fromOffset(20, 12), Text = "SETTINGS", Font = T.Heavy, TextSize = 26, Parent = frame })
	UIKit.Button({ Size = UDim2.fromOffset(40, 40), Position = UDim2.new(1, -52, 0, 12), Text = "✕", Parent = frame }, close)

	row(frame, 70, "Camera sensitivity")
	UIKit.Button({ Size = UDim2.fromOffset(40, 40), Position = UDim2.new(1, -170, 0, 70), Text = "−", Parent = frame }, function()
		settings.CameraSensitivity = math.max(0.2, math.floor((settings.CameraSensitivity - 0.1) * 10 + 0.5) / 10)
		refresh()
		push()
	end)
	refs.Sens = UIKit.Label({ Size = UDim2.fromOffset(70, 40), Position = UDim2.new(1, -126, 0, 70), TextXAlignment = Enum.TextXAlignment.Center, Font = T.Heavy, TextSize = 18, Text = "1.0x", Parent = frame })
	UIKit.Button({ Size = UDim2.fromOffset(40, 40), Position = UDim2.new(1, -52, 0, 70), Text = "+", Parent = frame }, function()
		settings.CameraSensitivity = math.min(3, math.floor((settings.CameraSensitivity + 0.1) * 10 + 0.5) / 10)
		refresh()
		push()
	end)

	row(frame, 130, "Match camera (C)")
	refs.Mode = UIKit.Button({ Size = UDim2.fromOffset(158, 40), Position = UDim2.new(1, -170, 0, 130), Text = "FOLLOW", Parent = frame }, function()
		settings.CameraMode = if settings.CameraMode == "Follow" then "Broadcast" else "Follow"
		refresh()
		push()
	end)

	row(frame, 190, "Show control hints")
	refs.Hints = UIKit.Button({ Size = UDim2.fromOffset(158, 40), Position = UDim2.new(1, -170, 0, 190), Text = "ON", Parent = frame }, function()
		settings.ShowControls = not settings.ShowControls
		refresh()
		push()
	end)
end

function SettingsPanel.Open()
	local profile = ClientState.Profile
	if profile and profile.Settings then
		settings = table.clone(profile.Settings)
	end
	frame.Visible = true
	refresh()
end

function SettingsPanel.Close()
	frame.Visible = false
end

return SettingsPanel
