--[[
	Theme
	Colours and fonts for the whole UI. Bright, chunky and readable for
	younger players.
]]

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

return {
	Font = Enum.Font.FredokaOne,
	BodyFont = Enum.Font.GothamBold,

	Colors = {
		Panel = rgb(248, 250, 255),
		PanelAlt = rgb(232, 240, 252),
		PanelDark = rgb(32, 40, 62),
		Text = rgb(40, 50, 75),
		TextMuted = rgb(110, 120, 145),
		White = rgb(255, 255, 255),
		Stroke = rgb(24, 30, 48),

		Green = rgb(80, 205, 95),
		GreenDark = rgb(40, 150, 60),
		Blue = rgb(70, 150, 245),
		BlueDark = rgb(40, 100, 200),
		Teal = rgb(40, 195, 185),
		TealDark = rgb(20, 140, 140),
		Yellow = rgb(255, 205, 60),
		YellowDark = rgb(220, 150, 20),
		Orange = rgb(255, 150, 60),
		Red = rgb(240, 80, 80),
		RedDark = rgb(180, 40, 50),
		Purple = rgb(160, 100, 240),
		Gray = rgb(170, 175, 190),
		GrayDark = rgb(110, 115, 130),
		Money = rgb(110, 235, 110),
	},
}
