--[[
	Title card shown when you join: the game's name and a three-step "how to play".
	Fades out on click/tap or after a few seconds, and waits for the save to load first.
]]

local Config = require(game:GetService("ReplicatedStorage").Shared.Config)
local State = require(script.Parent.State)
local Theme = require(script.Parent.Theme)
local UIKit = require(script.Parent.UIKit)

local Splash = {}

local SHOW_SECONDS = 7

local STEPS = {
	{ "1", "Take an order", "Head to the DISPATCH counter in the depot (follow the arrow) and press E." },
	{ "2", "Hit the road", "Drive to the glowing ring (WASD / arrow keys / thumbstick). Press V to call your vehicle." },
	{ "3", "Get paid", "Slow down inside the ring. Fast, on-time runs earn bonuses, tips and streaks!" },
}

function Splash.build(gui: ScreenGui)
	local overlay = UIKit.create("TextButton", {
		Name = "Splash",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.Navy,
		BackgroundTransparency = 0.05,
		Text = "",
		AutoButtonColor = false,
		ZIndex = 50,
		Parent = gui,
	})

	local content = UIKit.create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(640, 420),
		BackgroundTransparency = 1,
		ZIndex = 51,
		Parent = overlay,
	})
	UIKit.autoScale(content)

	UIKit.label({
		Position = UDim2.fromOffset(0, 0),
		Size = UDim2.new(1, 0, 0, 22),
		Font = Theme.FontBold,
		TextSize = 16,
		TextColor3 = Theme.Orange,
		TextXAlignment = Enum.TextXAlignment.Center,
		Text = "SWIFT DROP DEPOT PRESENTS",
		ZIndex = 52,
		Parent = content,
	})
	UIKit.label({
		Position = UDim2.fromOffset(0, 26),
		Size = UDim2.new(1, 0, 0, 100),
		Font = Theme.FontBold,
		TextSize = 44,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Center,
		Text = string.upper(Config.GameName),
		ZIndex = 52,
		Parent = content,
	})

	for index, step in STEPS do
		local row = UIKit.panel({
			Position = UDim2.fromOffset(0, 140 + (index - 1) * 74),
			Size = UDim2.new(1, 0, 0, 64),
			BackgroundColor3 = Theme.NavyLight,
			ZIndex = 52,
			Parent = content,
		})
		UIKit.create("Frame", {
			Position = UDim2.fromOffset(12, 12),
			Size = UDim2.fromOffset(40, 40),
			BackgroundColor3 = Theme.Orange,
			BorderSizePixel = 0,
			ZIndex = 53,
			Parent = row,
		}, {
			UIKit.corner(20),
			UIKit.label({
				Size = UDim2.fromScale(1, 1),
				Font = Theme.FontBold,
				TextSize = 22,
				TextColor3 = Theme.Navy,
				TextXAlignment = Enum.TextXAlignment.Center,
				Text = step[1],
				ZIndex = 54,
			}),
		})
		UIKit.label({
			Position = UDim2.fromOffset(66, 6),
			Size = UDim2.new(1, -80, 0, 24),
			Font = Theme.FontBold,
			TextSize = 18,
			Text = step[2],
			ZIndex = 53,
			Parent = row,
		})
		UIKit.label({
			Position = UDim2.fromOffset(66, 28),
			Size = UDim2.new(1, -80, 0, 32),
			Font = Theme.FontRegular,
			TextSize = 14,
			TextColor3 = Theme.TextDim,
			TextWrapped = true,
			TextYAlignment = Enum.TextYAlignment.Top,
			Text = step[3],
			ZIndex = 53,
			Parent = row,
		})
	end

	local prompt = UIKit.label({
		Position = UDim2.new(0, 0, 1, -28),
		Size = UDim2.new(1, 0, 0, 24),
		Font = Theme.FontBold,
		TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Center,
		Text = "Loading your profile...",
		ZIndex = 52,
		Parent = content,
	})

	local splash = {}
	local closed = false

	function splash.close()
		if closed then
			return
		end
		closed = true
		UIKit.tween(overlay, 0.5, { BackgroundTransparency = 1 })
		task.delay(0.5, function()
			overlay:Destroy()
		end)
		for _, descendant in content:GetDescendants() do
			if descendant:IsA("TextLabel") then
				UIKit.tween(descendant, 0.4, { TextTransparency = 1 })
			end
		end
	end

	UIKit.on(overlay, "Activated", function()
		if State.get("Loaded", false) then
			splash.close()
		end
	end)

	-- Ready to play as soon as the profile is loaded; auto-close shortly after.
	State.watch("Loaded", function(loaded)
		if loaded then
			prompt.Text = "Click or tap anywhere to start"
			task.delay(SHOW_SECONDS, splash.close)
		end
	end)

	-- Exposed for tests.
	splash.Overlay = overlay
	splash.Prompt = prompt
	return splash
end

return Splash
